#!/usr/bin/env python3
"""Independent reference implementation of Pyrogram's session string format.

Mirrors Pyrogram's own storage layer: SESSION_STRING_FORMAT = ">BI?256sQ?",
base64url encoded with padding stripped. Nothing here imports Nagram code, so
agreement between this file and the Swift codec is real cross-implementation
evidence rather than a self-consistency check.
"""
import base64
import hashlib
import struct
import sys

SESSION_STRING_FORMAT = ">BI?256sQ?"
RAW_SIZE = 271
assert struct.calcsize(SESSION_STRING_FORMAT) == RAW_SIZE


def encode(dc_id, api_id, test_mode, auth_key_hex, user_id, is_bot):
    packed = struct.pack(
        SESSION_STRING_FORMAT,
        dc_id,
        api_id,
        bool(int(test_mode)),
        bytes.fromhex(auth_key_hex),
        user_id,
        bool(int(is_bot)),
    )
    return base64.urlsafe_b64encode(packed).decode().rstrip("=")


def decode(session_string):
    padded = session_string + "=" * (-len(session_string) % 4)
    dc_id, api_id, test_mode, auth_key, user_id, is_bot = struct.unpack(
        SESSION_STRING_FORMAT, base64.urlsafe_b64decode(padded)
    )
    return "\t".join([
        str(dc_id),
        str(api_id),
        "1" if test_mode else "0",
        auth_key.hex(),
        str(user_id),
        "1" if is_bot else "0",
    ])


def auth_key_id(auth_key_hex):
    """MTProto: trailing 8 bytes of SHA1(auth_key), read as a little-endian int64."""
    digest = hashlib.sha1(bytes.fromhex(auth_key_hex)).digest()
    return struct.unpack("<q", digest[-8:])[0]


def main(argv):
    command = argv[1]
    if command == "encode":
        print(encode(int(argv[2]), int(argv[3]), argv[4], argv[5], int(argv[6]), argv[7]))
    elif command == "decode":
        print(decode(argv[2]))
    elif command == "authkeyid":
        print(auth_key_id(argv[2]))
    else:
        raise SystemExit(f"unknown command {command}")


if __name__ == "__main__":
    main(sys.argv)
