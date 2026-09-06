#!/bin/bash
# MARK: NAGRAM — Two-way interop test for session backup/restore.
#
# Proves that Nagram's Pyrogram session strings and backup envelopes are
# interchangeable with iebb/mithka and with Pyrogram itself, in both
# directions. Three independent implementations take part:
#
#   1. Nagram's Swift codec (Nagram/SessionBackup), driven through a CLI harness
#   2. A Pyrogram-format reference implementation in Python
#   3. Mithka's own Dart code, extracted from a local checkout at test time
#
# The Swift unit test suite runs first, then the cross-implementation checks.
# The Mithka phases are skipped when Dart or a Mithka checkout is unavailable.
#
# usage: scripts/test-session-backup-interop.sh [--mithka <checkout>] [--rounds N]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INTEROP="$REPO_ROOT/Tests/NagramSessionBackupTests/Interop"
PYREF="$INTEROP/pyrogram_reference.py"
MITHKA_DIR="${MITHKA_DIR:-$REPO_ROOT/../mithka}"
ROUNDS=8

while [ $# -gt 0 ]; do
    case "$1" in
        --mithka) MITHKA_DIR="$2"; shift 2 ;;
        --rounds) ROUNDS="$2"; shift 2 ;;
        -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0
SKIPPED=0

pass() { PASSED=$((PASSED + 1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
skip() { SKIPPED=$((SKIPPED + 1)); printf '  \033[33mSKIP\033[0m  %s\n' "$1"; }
fail() {
    FAILED=$((FAILED + 1))
    printf '  \033[31mFAIL\033[0m  %s\n' "$1"
    if [ $# -gt 2 ]; then
        printf '        expected: %s\n        actual:   %s\n' "$2" "$3"
    fi
}
expect_equal() {
    # expect_equal <label> <expected> <actual>
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
random_auth_key() { python3 -c "import os; print(os.urandom(256).hex())"; }

echo "Nagram session backup interop test"
echo "  repo:   $REPO_ROOT"
echo "  mithka: $MITHKA_DIR"

# ---------------------------------------------------------------- unit tests
echo
echo "[1/5] Swift unit tests (Tests/NagramSessionBackupTests)"
PKG="$WORK/pkg"
mkdir -p "$PKG/Sources/NagramSessionBackup" "$PKG/Tests/NagramSessionBackupTests"
cat > "$PKG/Package.swift" <<'PKGSWIFT'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NagramSessionBackup",
    targets: [
        .target(name: "NagramSessionBackup"),
        .testTarget(name: "NagramSessionBackupTests", dependencies: ["NagramSessionBackup"]),
    ]
)
PKGSWIFT
ln -s "$REPO_ROOT"/Nagram/SessionBackup/*.swift "$PKG/Sources/NagramSessionBackup/"
ln -s "$REPO_ROOT"/Tests/NagramSessionBackupTests/Sources/*.swift "$PKG/Tests/NagramSessionBackupTests/"
if (cd "$PKG" && swift test > "$WORK/unit.log" 2>&1); then
    pass "$(grep -oE 'Executed [0-9]+ tests, with [0-9]+ failures' "$WORK/unit.log" | tail -1)"
else
    fail "swift test failed"
    grep -E "error:|failed" "$WORK/unit.log" | head -10
fi

# ------------------------------------------------------------- swift cli build
echo
echo "[2/5] Building the Swift codec CLI"
CLI="$WORK/nagram-session"
if swiftc -O -o "$CLI" "$INTEROP/SwiftCLI/main.swift" "$REPO_ROOT"/Nagram/SessionBackup/PyrogramSessionString.swift "$REPO_ROOT"/Nagram/SessionBackup/NagramSessionBackupRecord.swift 2> "$WORK/cli.log"; then
    pass "codec CLI built"
else
    fail "codec CLI failed to build"
    head -20 "$WORK/cli.log"
    echo; echo "passed=$PASSED failed=$FAILED skipped=$SKIPPED"; exit 1
fi

# ------------------------------------------------------- swift <-> pyrogram
echo
echo "[3/5] Nagram Swift codec vs the Pyrogram reference format ($ROUNDS rounds)"
for round in $(seq 1 "$ROUNDS"); do
    key="$(random_auth_key)"
    dc=$(( (round % 5) + 1 ))
    api=$(( 2040 + round ))
    test_mode=$(( round % 2 ))
    is_bot=$(( (round / 2) % 2 ))
    user=$(( 777000 + round * 1000003 ))

    swift_string="$("$CLI" session-encode "$dc" "$api" "$test_mode" "$key" "$user" "$is_bot")"
    python_string="$(python3 "$PYREF" encode "$dc" "$api" "$test_mode" "$key" "$user" "$is_bot")"
    expect_equal "round $round: Swift encoder is byte-identical to Pyrogram" "$python_string" "$swift_string"

    expected_fields="$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$dc" "$api" "$test_mode" "$key" "$user" "$is_bot")"
    expect_equal "round $round: Swift decodes a Pyrogram-produced string" "$expected_fields" "$("$CLI" session-decode "$python_string")"
    expect_equal "round $round: Pyrogram decodes a Swift-produced string" "$expected_fields" "$(python3 "$PYREF" decode "$swift_string")"

    sha1="$(python3 -c "import hashlib,sys; print(hashlib.sha1(bytes.fromhex(sys.argv[1])).hexdigest())" "$key")"
    expect_equal "round $round: auth key id matches the MTProto derivation" "$(python3 "$PYREF" authkeyid "$key")" "$("$CLI" authkeyid-from-sha1 "$sha1")"
done

# ------------------------------------------------------------ padding tolerance
echo
echo "[4/5] Encoding shape and input tolerance"
key="$(random_auth_key)"
canonical="$("$CLI" session-encode 2 2040 0 "$key" 777000 0)"
expect_equal "canonical output is 362 chars of unpadded base64url" "362" "${#canonical}"
case "$canonical" in
    *=*|*+*|*/*) fail "canonical output uses the base64url alphabet without padding" ;;
    *) pass "canonical output uses the base64url alphabet without padding" ;;
esac
reference="$("$CLI" session-decode "$canonical")"
expect_equal "padded input decodes identically" "$reference" "$("$CLI" session-decode "${canonical}==")"
expect_equal "whitespace-wrapped input decodes identically" "$reference" "$("$CLI" session-decode "  $canonical  ")"
standard="$(printf '%s' "$canonical" | tr -- '-_' '+/')"
expect_equal "standard-alphabet input decodes identically" "$reference" "$("$CLI" session-decode "$standard")"

# --------------------------------------------------------------- mithka phases
echo
echo "[5/5] Nagram vs Mithka's own Dart implementation"
if ! command -v dart > /dev/null 2>&1; then
    skip "dart is not installed"
elif [ ! -f "$MITHKA_DIR/lib/tdlib/td_client.dart" ]; then
    skip "no Mithka checkout at $MITHKA_DIR (pass --mithka <path>)"
else
    HARNESS="$WORK/mithka_harness.dart"
    if ! python3 "$INTEROP/extract_mithka_harness.py" "$MITHKA_DIR" "$HARNESS" > "$WORK/extract.log" 2>&1; then
        fail "could not extract Mithka's implementation"
        cat "$WORK/extract.log"
    else
        pass "extracted Mithka's decoder and envelope codec"

        key="$(random_auth_key)"
        swift_string="$("$CLI" session-encode 4 2040 1 "$key" 1234567890 1)"
        expect_equal "Mithka's decoder accepts a Nagram session string" \
            "$(printf '4\t2040\t1\t1234567890\t1')" \
            "$(dart run "$HARNESS" session-decode "$swift_string" 2>/dev/null | tail -1)"

        mithka_string="$(python3 "$PYREF" encode 5 2040 0 "$key" 424242424242 0)"
        expect_equal "Nagram decodes a session string Mithka would accept" \
            "$(printf '5\t2040\t0\t%s\t424242424242\t0' "$key")" \
            "$("$CLI" session-decode "$mithka_string")"

        created="2026-08-20T11:22:33.444Z"
        nagram_json="$("$CLI" record-encode 777000 777000 "Nagram User" "+1 234" "$created" "$swift_string" 0 synced)"
        expect_equal "Mithka reads a Nagram backup envelope" \
            "$(printf '777000\t777000\tNagram User\t+1 234\t%s\t362\tsynced\t%s' "$created" "$swift_string")" \
            "$(dart run "$HARNESS" record-decode "$nagram_json" 2>/dev/null | tail -1)"

        mithka_json="$(dart run "$HARNESS" record-encode 424242424242 424242424242 "Mithka User" "+81 90" "$created" "$mithka_string" 3 2>/dev/null | tail -1)"
        expect_equal "Nagram reads a Mithka backup envelope" \
            "$(printf '424242424242\t424242424242\tMithka User\t+81 90\t%s\t362\tsynced\t%s' "$created" "$mithka_string")" \
            "$("$CLI" record-decode "$mithka_json")"
    fi
fi

echo
echo "passed=$PASSED failed=$FAILED skipped=$SKIPPED"
[ "$FAILED" -eq 0 ]
