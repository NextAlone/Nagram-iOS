#!/usr/bin/env python3
"""Finds an external TestFlight group by its name and, with --build, adds a
processed build to it and submits the build to Beta App Review, after which
TestFlight sends it to the testers of the group. With --notes the build first
gets the release notes as its What to Test text.

Adding a build to a group through the API does not submit it, unlike the web
page: without the submission the build stays Ready to Submit and no tester
gets it.

TestFlight reviews one build of a version at a time and refuses the next
submission while an earlier one waits. The API cannot withdraw a submission,
so an earlier build of the same version that never reached the testers is
expired first: the new build replaces it, and its notes should cover both.

Without --build nothing is changed: the script reports the group, where the
notes of the latest build are and which earlier builds a release of it would
expire, and fails when the group cannot be found, so the lookup can be tried
without a release.

--print-notes writes the What to Test text of --notes and contacts nobody.

Environment: ASC_KEY_ID and ASC_ISSUER_ID, with the key itself in
~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8.
"""

import argparse
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
# The limit of whatsNew in App Store Connect.
WHAT_TO_TEST_LIMIT = 4000


def fail(message):
    print(f"::error::{message}")
    sys.exit(1)


def what_to_test(path):
    """The release notes as the plain text TestFlight shows: no Markdown."""
    lines = []
    with open(path, encoding="utf-8") as file:
        for line in file.read().splitlines():
            heading = re.match(r"#+\s+(.*)", line)
            if heading:
                line = f"【{heading.group(1).strip()}】"
            line = re.sub(r"^(\s*)[-*]\s+", r"\1• ", line)
            line = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", line)
            line = re.sub(r"(\*\*|__|`)", "", line)
            lines.append(line.rstrip())
    text = re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()
    if not text:
        fail(f"{path} leaves no What to Test text.")
    if len(text) > WHAT_TO_TEST_LIMIT:
        fail(
            f"The What to Test text of {path} has {len(text)} characters, "
            f"TestFlight takes {WHAT_TO_TEST_LIMIT}."
        )
    return text


class Client:
    def __init__(self):
        # Imported here: --print-notes needs neither the package nor a key.
        from cryptography.hazmat.primitives.serialization import load_pem_private_key

        self.key_id = os.environ["ASC_KEY_ID"]
        self.issuer = os.environ["ASC_ISSUER_ID"]
        path = os.path.expanduser(
            f"~/.appstoreconnect/private_keys/AuthKey_{self.key_id}.p8"
        )
        with open(path, "rb") as file:
            self.key = load_pem_private_key(file.read(), password=None)

    def token(self):
        from cryptography.hazmat.primitives.asymmetric.ec import ECDSA
        from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
        from cryptography.hazmat.primitives.hashes import SHA256

        def encode(data):
            return base64.urlsafe_b64encode(data).rstrip(b"=")

        now = int(time.time())
        header = encode(
            json.dumps({"alg": "ES256", "kid": self.key_id, "typ": "JWT"}).encode()
        )
        payload = encode(
            json.dumps({
                "iss": self.issuer,
                "iat": now,
                "exp": now + 600,
                "aud": "appstoreconnect-v1",
            }).encode()
        )
        message = header + b"." + payload
        r, s = decode_dss_signature(self.key.sign(message, ECDSA(SHA256())))
        signature = r.to_bytes(32, "big") + s.to_bytes(32, "big")
        return (message + b"." + encode(signature)).decode()

    def request(self, method, path, query=None, body=None):
        url = API + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        request = urllib.request.Request(
            url,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token()}",
                "Content-Type": "application/json",
            },
            data=json.dumps(body).encode() if body is not None else None,
        )
        try:
            with urllib.request.urlopen(request) as response:
                content = response.read()
                return response.status, json.loads(content) if content else {}
        except urllib.error.HTTPError as error:
            return error.code, {"_body": error.read().decode(errors="replace")}


def external_groups(client, app_id):
    # The filters exist on /v1/betaGroups only: /v1/apps/{id}/betaGroups takes
    # none, and a request that fails must not read as an app without groups.
    status, response = client.request("GET", "/v1/betaGroups", {
        "filter[app]": app_id,
        "filter[isInternalGroup]": "false",
        "fields[betaGroups]": "name",
        "limit": 200,
    })
    if status != 200:
        fail(f"Listing the external groups returned {status}: {response.get('_body', '')}")
    return {group["attributes"]["name"]: group["id"] for group in response["data"]}


def processed_build(client, app_id, build_number):
    # Processing takes a while after the upload: 36 attempts are half an hour.
    for attempt in range(36):
        status, response = client.request("GET", "/v1/builds", {
            "filter[app]": app_id,
            "filter[version]": build_number,
            "filter[processingState]": "VALID",
            "sort": "-uploadedDate",
            "limit": 1,
        })
        if status != 200:
            fail(f"Looking for build {build_number} returned {status}: {response.get('_body', '')}")
        if response["data"]:
            return response["data"][0]["id"]
        print(f"Waiting for build {build_number} to finish processing ({attempt + 1}/36)...", flush=True)
        time.sleep(50)
    fail(f"Build {build_number} was not processed after 30 minutes.")


# externalBuildState values that need no submission: the build is in review,
# approved, or already testing.
SUBMITTED_STATES = {
    "WAITING_FOR_BETA_REVIEW",
    "IN_BETA_REVIEW",
    "BETA_APPROVED",
    "READY_FOR_BETA_TESTING",
    "IN_BETA_TESTING",
}
# Values that the build leaves by itself shortly after processing.
TRANSIENT_STATES = {"PROCESSING", "IN_EXPORT_COMPLIANCE_REVIEW"}


def beta_detail(client, build_id):
    status, response = client.request("GET", f"/v1/builds/{build_id}/buildBetaDetail")
    if status != 200:
        fail(f"Reading the beta state of the build returned {status}: {response.get('_body', '')}")
    return response["data"]


def settled_beta_detail(client, build_id):
    """The beta detail once the external state no longer moves by itself.

    A build that just reached VALID can still read PROCESSING, or
    MISSING_EXPORT_COMPLIANCE until the ITSAppUsesNonExemptEncryption of its
    Info.plist is applied, and a submission made then is refused.
    """
    for attempt in range(20):
        detail = beta_detail(client, build_id)
        state = detail["attributes"]["externalBuildState"]
        if state not in TRANSIENT_STATES and state != "MISSING_EXPORT_COMPLIANCE":
            return detail
        print(f"External state is {state}, waiting ({attempt + 1}/20)...", flush=True)
        time.sleep(15)
    if state == "MISSING_EXPORT_COMPLIANCE":
        fail(
            "The build still misses export compliance after 5 minutes: answer it "
            "in App Store Connect, or check ITSAppUsesNonExemptEncryption in Info.plist."
        )
    fail(f"The external state of the build is still {state} after 5 minutes.")


def enable_auto_notify(client, detail):
    """Testers are told about the build as soon as it is approved."""
    if detail["attributes"].get("autoNotifyEnabled"):
        return
    status, response = client.request(
        "PATCH",
        f"/v1/buildBetaDetails/{detail['id']}",
        body={"data": {
            "type": "buildBetaDetails",
            "id": detail["id"],
            "attributes": {"autoNotifyEnabled": True},
        }},
    )
    if status != 200:
        fail(f"Enabling the tester notification returned {status}: {response.get('_body', '')}")
    print("Testers are notified automatically")


# externalBuildState values of a build that has not reached the testers yet.
UNRELEASED_STATES = {
    "READY_FOR_BETA_SUBMISSION",
    "WAITING_FOR_BETA_REVIEW",
    "IN_BETA_REVIEW",
}
# The code of a submission refused because another build of the version waits.
ANOTHER_BUILD_IN_REVIEW = "ANOTHER_BUILD_IN_REVIEW"


def unreleased_builds(client, build_id, build_number):
    """The earlier builds of the version of the build that never reached the testers."""
    status, response = client.request(
        "GET", f"/v1/builds/{build_id}/preReleaseVersion", {"fields[preReleaseVersions]": "version"}
    )
    if status != 200:
        fail(f"Reading the version of the build returned {status}: {response.get('_body', '')}")
    version_id = response["data"]["id"]
    status, response = client.request("GET", "/v1/builds", {
        "filter[preReleaseVersion]": version_id,
        "filter[expired]": "false",
        "include": "buildBetaDetail",
        "fields[builds]": "version,buildBetaDetail",
        "fields[buildBetaDetails]": "externalBuildState",
        "limit": 200,
    })
    if status != 200:
        fail(f"Listing the builds of the version returned {status}: {response.get('_body', '')}")
    states = {
        item["id"]: item["attributes"]["externalBuildState"]
        for item in response.get("included", [])
        if item["type"] == "buildBetaDetails"
    }
    builds = []
    for build in response["data"]:
        number = build["attributes"]["version"]
        if build["id"] == build_id or int(number) >= int(build_number):
            continue
        detail = build.get("relationships", {}).get("buildBetaDetail", {}).get("data")
        state = states.get(detail["id"]) if detail else None
        if state in UNRELEASED_STATES:
            builds.append((build["id"], number, state))
    return builds


def expire_unreleased_builds(client, build_id, build_number):
    for earlier_id, number, state in unreleased_builds(client, build_id, build_number):
        status, response = client.request(
            "PATCH",
            f"/v1/builds/{earlier_id}",
            body={"data": {"type": "builds", "id": earlier_id, "attributes": {"expired": True}}},
        )
        if status != 200:
            fail(f"Expiring build {number} ({state}) returned {status}: {response.get('_body', '')}")
        print(f"Expired build {number}, which was {state} and never reached the testers")


def submit_for_beta_review(client, build_id):
    detail = settled_beta_detail(client, build_id)
    state = detail["attributes"]["externalBuildState"]
    if state in SUBMITTED_STATES:
        print(f"Beta App Review: nothing to submit, the build is {state}")
        return
    if state != "READY_FOR_BETA_SUBMISSION":
        fail(f"The build cannot be submitted to Beta App Review: it is {state}.")
    # An expired build can hold the review of its version for a short while.
    for attempt in range(10):
        status, response = client.request(
            "POST",
            "/v1/betaAppReviewSubmissions",
            body={"data": {
                "type": "betaAppReviewSubmissions",
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
            }},
        )
        if status != 422 or ANOTHER_BUILD_IN_REVIEW not in response.get("_body", ""):
            break
        print(f"Another build of the version is still in review, waiting ({attempt + 1}/10)...", flush=True)
        time.sleep(30)
    if status != 201:
        # A run started again may find the build submitted in the meantime.
        state = beta_detail(client, build_id)["attributes"]["externalBuildState"]
        if state in SUBMITTED_STATES:
            print(f"Beta App Review: the build is {state}")
            return
        fail(f"Submitting to Beta App Review returned {status}: {response.get('_body', '')}")
    # The state follows the submission with a delay.
    for attempt in range(6):
        state = beta_detail(client, build_id)["attributes"]["externalBuildState"]
        if state in SUBMITTED_STATES:
            print(f"Submitted to Beta App Review, the build is {state}")
            return
        time.sleep(10)
    fail(f"Beta App Review accepted the submission, but the build is still {state}.")


def latest_build(client, app_id):
    status, response = client.request("GET", "/v1/builds", {
        "filter[app]": app_id,
        "sort": "-uploadedDate",
        "fields[builds]": "version,processingState",
        "limit": 1,
    })
    if status != 200:
        fail(f"Looking for the latest build returned {status}: {response.get('_body', '')}")
    if not response["data"]:
        return None, None
    return response["data"][0]["id"], response["data"][0]["attributes"]["version"]


def build_localizations(client, build_id):
    status, response = client.request(
        "GET", f"/v1/builds/{build_id}/betaBuildLocalizations", {"limit": 200}
    )
    if status != 200:
        fail(f"Listing the What to Test texts returned {status}: {response.get('_body', '')}")
    return response["data"]


def set_what_to_test(client, app_id, build_id, text):
    localizations = build_localizations(client, build_id)
    for localization in localizations:
        status, response = client.request(
            "PATCH",
            f"/v1/betaBuildLocalizations/{localization['id']}",
            body={"data": {
                "type": "betaBuildLocalizations",
                "id": localization["id"],
                "attributes": {"whatsNew": text},
            }},
        )
        if status != 200:
            fail(f"Setting What to Test returned {status}: {response.get('_body', '')}")
        print(f"What to Test set for {localization['attributes']['locale']}")
    if localizations:
        return

    # A build without a text yet gets one in the primary language of the app.
    status, response = client.request(
        "GET", f"/v1/apps/{app_id}", {"fields[apps]": "primaryLocale"}
    )
    if status != 200:
        fail(f"Reading the primary language returned {status}: {response.get('_body', '')}")
    locale = response["data"]["attributes"]["primaryLocale"]
    status, response = client.request(
        "POST",
        "/v1/betaBuildLocalizations",
        body={"data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": locale, "whatsNew": text},
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
        }},
    )
    if status != 201:
        fail(f"Creating What to Test returned {status}: {response.get('_body', '')}")
    print(f"What to Test created for {locale}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--app", help="App Store id of the application")
    parser.add_argument("--group", help="name of the external group")
    parser.add_argument("--build", help="build number to add to the group")
    parser.add_argument("--notes", help="release notes to set as What to Test")
    parser.add_argument(
        "--print-notes", action="store_true",
        help="print the What to Test text of --notes and stop",
    )
    arguments = parser.parse_args()

    text = what_to_test(arguments.notes) if arguments.notes else None
    if arguments.print_notes:
        if text is None:
            parser.error("--print-notes needs --notes")
        print(text)
        return
    if not arguments.app or not arguments.group:
        parser.error("--app and --group are required")

    client = Client()
    groups = external_groups(client, arguments.app)
    print("External groups: " + (", ".join(sorted(groups)) or "none"))
    group_id = groups.get(arguments.group)

    if arguments.build is None:
        if group_id is None:
            fail(f"External group '{arguments.group}' not found.")
        print(f"Group: {arguments.group} ({group_id})")
        build_id, version = latest_build(client, arguments.app)
        if build_id is not None:
            locales = ", ".join(
                f"{item['attributes']['locale']} ({len(item['attributes'].get('whatsNew') or '')} characters)"
                for item in build_localizations(client, build_id)
            )
            print(f"What to Test of the latest build {version}: {locales or 'none'}")
            earlier = unreleased_builds(client, build_id, version)
            print("A release of a later build would expire: " + (
                ", ".join(f"{number} ({state})" for _, number, state in earlier) or "none"
            ))
        return

    if group_id is None:
        # The upload is not undone by a group that was renamed or removed.
        print(
            f"::warning::External group '{arguments.group}' not found; "
            f"build {arguments.build} was uploaded but not distributed."
        )
        return
    print(f"Group: {arguments.group} ({group_id})")

    build_id = processed_build(client, arguments.app, arguments.build)
    print(f"Build: {arguments.build} ({build_id})")
    # Before the group: the testers are told about the build as it is added.
    if text is not None:
        set_what_to_test(client, arguments.app, build_id, text)
    enable_auto_notify(client, beta_detail(client, build_id))
    expire_unreleased_builds(client, build_id, arguments.build)
    status, response = client.request(
        "POST",
        f"/v1/betaGroups/{group_id}/relationships/builds",
        body={"data": [{"type": "builds", "id": build_id}]},
    )
    # 409: the build is in the group already, as when a run is started again.
    if status not in (200, 201, 204, 409):
        fail(f"Adding build {arguments.build} to '{arguments.group}' returned {status}: {response.get('_body', '')}")
    print(f"Added build {arguments.build} to group '{arguments.group}' (status {status})")
    submit_for_beta_review(client, build_id)


if __name__ == "__main__":
    main()
