// The sequence names of lib/src/decode.dart held to decode.golden.json, the
// description of them the VS Code extension's tests hold its first
// implementation (editors/vscode/src/core/sequences.ts, seqlog.ts) to as
// well: bytes cut into tokens and named, for what the app writes and for
// what the terminal sends, and bytes into the entries and frames of a log.
// A change to a name here that is not made in the golden fails this test;
// made in the golden, it fails the extension's until it follows.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
// the decoder is not part of the package's API: it is the CLI's
import 'package:twk_dev/src/decode.dart';

typedef Json = Map<String, Object?>;

/// Where the golden is, from the package's directory.
const goldenPath = 'test/decode.golden.json';

final golden = jsonDecode(File(goldenPath).readAsStringSync()) as Json;

List<Json> casesOf(String key) => (golden[key]! as List<Object?>).cast<Json>();

Uint8List bytesOf(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

String hexOf(String latin1) =>
    latin1.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('reads', () {
    for (final c in casesOf('reads')) {
      test(c['name']! as String, () {
        final input = c['direction'] == 'in';
        final reader = SequenceReader(input: input);
        final tokens = <Json>[];
        for (final chunk in (c['chunks']! as List<Object?>).cast<String>()) {
          // the terminal's reads are whole each, as the log reads them
          for (final t in (input ? SequenceReader(input: true) : reader).read(
            bytesOf(chunk),
          )) {
            tokens.add({
              'kind': t.kind,
              'raw': hexOf(t.raw),
              'name': input ? describeInput(t) : describeOutput(t),
            });
          }
        }
        expect(tokens, c['tokens']);
        expect(input ? '' : hexOf(reader.waiting), c['waiting'] ?? '');
      });
    }
  });

  group('logs', () {
    for (final c in casesOf('logs')) {
      test(c['name']! as String, () {
        final log = SequenceLog();
        for (final e in (c['events']! as List<Object?>).cast<Json>()) {
          final time = e['time']! as int;
          switch (e['direction']) {
            case 'out':
              log.output(time, bytesOf(e['bytes']! as String));
            case 'in':
              log.input(time, bytesOf(e['bytes']! as String));
            default:
              log.note(time, e['note']! as String);
          }
        }
        expect(
          jsonDecode(jsonEncode([for (final e in log.all()) e.toJson()])),
          c['entries'],
        );
      });
    }
  });
}
