// asciicast as cast.dart writes and reads it, held to cast.golden.json, the
// description of it the VS Code extension's tests hold its second
// implementation (editors/vscode/src/core/cast.ts) to as well: the lines
// CastWriter writes for a header and events, what Cast.parse reads of a
// file or the message it throws, and the frames twk_test's screenFrames
// shows of its writes. A change
// to the format here that is not made in the golden fails this test; made
// in the golden, it fails the extension's until it follows.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_dev/twk_dev.dart';
import 'package:twk_test/twk_test.dart' show ScreenFrame, screenFrames;

typedef Json = Map<String, Object?>;

/// Where the golden is, from the package's directory.
const goldenPath = 'test/cast.golden.json';

final golden = jsonDecode(File(goldenPath).readAsStringSync()) as Json;

List<Json> casesOf(String key) => (golden[key]! as List<Object?>).cast<Json>();

/// The bytes of [hex], two digits each.
Uint8List bytesOf(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

/// The file of a case's lines.
String fileOf(Json c) =>
    (c['lines']! as List<Object?>).cast<String>().join('\n');

/// The screens [cast] showed, as twk_test's emulator shows them.
List<ScreenFrame> _frames(Cast cast) =>
    screenFrames(cast.header.width, cast.header.height, cast.writes);

void main() {
  group('CastWriter writes', () {
    for (final c in casesOf('writes')) {
      test(c['name']! as String, () {
        final out = StringBuffer();
        final limit = c['idleLimitMicros'] as int?;
        final writer = CastWriter(
          out.write,
          CastHeader.fromJson(c['header']),
          idleLimit: limit == null ? null : Duration(microseconds: limit),
        );
        for (final e in (c['events']! as List<Object?>).cast<Json>()) {
          final at = Duration(microseconds: e['at']! as int);
          switch (e) {
            case {'output': final String hex}:
              writer.output(at, bytesOf(hex));
            case {'input': final String hex}:
              writer.input(at, bytesOf(hex));
            case {'resize': [final int width, final int height]}:
              writer.resize(at, width, height);
            case {'close': true}:
              writer.close(at);
            default:
              fail('an event of no kind: $e');
          }
        }
        expect(const LineSplitter().convert(out.toString()), c['lines']);
      });
    }
  });

  group('Cast.parse reads', () {
    for (final c in casesOf('reads')) {
      test(c['name']! as String, () {
        if (c['error'] case final String message) {
          expect(
            () => Cast.parse(fileOf(c)),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                message,
              ),
            ),
          );
          return;
        }
        final cast = Cast.parse(fileOf(c));
        expect(cast.header.toJson(), c['header']);
        expect([
          for (final e in cast.events) [e.time, e.code, e.data],
        ], c['events']);
        expect(cast.duration, c['duration']);
      });
    }
  });

  group('screenFrames shows', () {
    for (final c in casesOf('frames')) {
      test(c['name']! as String, () {
        expect([
          for (final f in _frames(Cast.parse(fileOf(c))))
            {
              'number': f.number,
              'time': f.time,
              'width': f.width,
              'height': f.height,
              'lines': f.lines,
            },
        ], c['frames']);
      });
    }
  });
}
