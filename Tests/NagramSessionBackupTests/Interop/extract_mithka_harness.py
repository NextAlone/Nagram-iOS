#!/usr/bin/env python3
"""Build a throwaway Dart harness from a local iebb/mithka checkout.

Mithka's decoder is the authority on what Mithka will accept, so the interop
test runs *its* code rather than a paraphrase of it. The functions are read out
of the developer's own checkout at test time and written to a temporary file;
no Mithka source is copied into this repository.

usage: extract_mithka_harness.py <mithka-checkout> <output-dart-file>
"""
import re
import sys
from pathlib import Path

TD_CLIENT = "lib/tdlib/td_client.dart"
BACKUP_SERVICE = "lib/auth/account_backup_service.dart"


def _code_positions(source, start):
    """Yield (index, char) for source[start:], skipping comments and string bodies.

    Dart named parameters and string interpolation both use braces, so a naive
    brace counter mis-reads a declaration. This walker only reports characters
    that are really code.
    """
    index = start
    length = len(source)
    while index < length:
        char = source[index]
        pair = source[index:index + 2]
        if pair == "//":
            newline = source.find("\n", index)
            if newline == -1:
                return
            index = newline
            continue
        if pair == "/*":
            end = source.find("*/", index + 2)
            index = length if end == -1 else end + 2
            continue
        if char in ("'", '"'):
            triple = source[index:index + 3] == char * 3
            terminator = char * 3 if triple else char
            cursor = index + len(terminator)
            while cursor < length:
                if source[cursor] == "\\":
                    cursor += 2
                    continue
                if source[cursor:cursor + len(terminator)] == terminator:
                    cursor += len(terminator)
                    break
                cursor += 1
            index = cursor
            continue
        yield index, char
        index += 1


def extract_block(source: str, signature_pattern: str, what: str) -> str:
    """Return a declaration in full, from its signature through the brace closing its body."""
    match = re.search(signature_pattern, source)
    if not match:
        raise SystemExit(f"could not find {what} in the Mithka checkout")
    start = match.start()

    # Step over the parameter list first: named parameters are wrapped in braces
    # of their own, which are not the start of the body.
    body_from = None
    paren_depth = 0
    for index, char in _code_positions(source, start):
        if char == "(":
            paren_depth += 1
        elif char == ")":
            paren_depth -= 1
            if paren_depth == 0:
                body_from = index + 1
                break
    if body_from is None:
        raise SystemExit(f"unbalanced parentheses while reading {what}")

    brace_depth = 0
    for index, char in _code_positions(source, body_from):
        if char == "{":
            brace_depth += 1
        elif char == "}":
            brace_depth -= 1
            if brace_depth == 0:
                return source[start:index + 1]
    raise SystemExit(f"unbalanced braces while reading {what}")


def main(argv):
    if len(argv) != 3:
        raise SystemExit(__doc__)
    checkout = Path(argv[1])
    output = Path(argv[2])

    td_client = (checkout / TD_CLIENT).read_text(encoding="utf-8")
    backup_service = (checkout / BACKUP_SERVICE).read_text(encoding="utf-8")

    decode_session_string = extract_block(
        td_client,
        r"static _TdSessionStringInfo _decodeSessionString\(",
        "_decodeSessionString",
    )
    encode_record = extract_block(
        backup_service, r"\n  Uint8List _encode\(", "_encode"
    )
    decode_record = extract_block(
        backup_service, r"\n  AccountSessionBackup\? _decode\(", "_decode"
    )

    harness = f'''// GENERATED - do not commit.
// Mithka's own _decodeSessionString/_encode/_decode, lifted verbatim from
// {checkout} so the interop test exercises Mithka's real behaviour.
import 'dart:convert';
import 'dart:typed_data';

enum AccountSessionBackupStorage {{ synced, local }}

class _TdSessionStringInfo {{
  const _TdSessionStringInfo({{
    required this.rawSize,
    required this.dcId,
    required this.apiId,
    required this.testMode,
    required this.userId,
    required this.isBot,
  }});
  final int rawSize;
  final int dcId;
  final int apiId;
  final bool testMode;
  final int userId;
  final bool isBot;
}}

class AccountSessionBackup {{
  const AccountSessionBackup({{
    required this.id,
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
    required this.sessionString,
    this.storage = AccountSessionBackupStorage.synced,
    this.phone,
    this.userId,
  }});
  final String id;
  final String name;
  final String? phone;
  final int? userId;
  final DateTime createdAt;
  final int sizeBytes;
  final String sessionString;
  final AccountSessionBackupStorage storage;
}}

class Mithka {{
  static const _format = 'mithka.tdlib.session_string.v2.explicit_consent';

{decode_session_string}

{encode_record}

{decode_record}
}}

void main(List<String> args) {{
  switch (args[0]) {{
    case 'session-decode':
      final info = Mithka._decodeSessionString(args[1]);
      print([
        info.dcId,
        info.apiId,
        info.testMode ? 1 : 0,
        info.userId,
        info.isBot ? 1 : 0,
      ].join('\\t'));
      break;
    case 'record-decode':
      final backup = Mithka()._decode(Uint8List.fromList(utf8.encode(args[1])));
      if (backup == null) {{
        print('REJECTED');
        break;
      }}
      print([
        backup.id,
        backup.userId,
        backup.name,
        backup.phone ?? '',
        backup.createdAt.toUtc().toIso8601String(),
        backup.sizeBytes,
        backup.storage.name,
        backup.sessionString,
      ].join('\\t'));
      break;
    case 'record-encode':
      final bytes = Mithka()._encode(
        AccountSessionBackup(
          id: args[1],
          userId: int.parse(args[2]),
          name: args[3],
          phone: args[4].isEmpty ? null : args[4],
          createdAt: DateTime.parse(args[5]).toUtc(),
          sizeBytes: utf8.encode(args[6]).length,
          sessionString: args[6],
        ),
        slot: int.parse(args[7]),
      );
      print(utf8.decode(bytes));
      break;
    default:
      throw ArgumentError('unknown command ${{args[0]}}');
  }}
}}
'''
    output.write_text(harness, encoding="utf-8")
    print(f"wrote {output}")


if __name__ == "__main__":
    main(sys.argv)
