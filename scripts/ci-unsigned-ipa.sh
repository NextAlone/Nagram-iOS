#!/usr/bin/env bash
# Repacks a signed IPA without its code signatures and provisioning profiles.
# The copy posted to the Telegram channel is signed anew by whoever installs
# it, and an App Store signature is of no use outside TestFlight.
#
# Prints the MinimumOSVersion of the application, for the caption of the post.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <signed.ipa> <unsigned.ipa>" >&2
  exit 2
fi

input="$1"
output="$2"
case "$output" in
  /*) ;;
  *) output="$PWD/$output" ;;
esac

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

# Only the application is kept: SwiftSupport and Symbols are for the App Store.
unzip -q "$input" 'Payload/*' -d "$stage"

app="$(find "$stage/Payload" -maxdepth 1 -name '*.app' -type d | head -n 1)"
if [ -z "$app" ]; then
  echo "error: $input has no Payload/*.app" >&2
  exit 1
fi

# Nested bundles come first, so that a bundle is unsigned after its contents.
find "$stage/Payload" -depth -type d \
  \( -name '*.app' -o -name '*.appex' -o -name '*.framework' \) -print0 |
  while IFS= read -r -d '' bundle; do
    codesign --remove-signature "$bundle"
  done
find "$stage/Payload" -type f -name '*.dylib' -print0 |
  while IFS= read -r -d '' library; do
    codesign --remove-signature "$library"
  done

find "$stage/Payload" -type d -name _CodeSignature -prune -exec rm -rf {} +
find "$stage/Payload" -type f -name embedded.mobileprovision -delete

if codesign --display "$app" > /dev/null 2>&1; then
  echo "error: $(basename "$app") is still signed" >&2
  exit 1
fi

rm -f "$output"
(cd "$stage" && zip -q -r -y "$output" Payload)

/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app/Info.plist"
