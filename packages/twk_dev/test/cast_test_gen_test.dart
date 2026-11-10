// `twk test-from-cast`: the test written over a recording. The source: a
// check of a line a marker, of the last screen where there are none, the
// emulator's errors; the frames it counts are those of twk_test's
// screenFrames; the command copies the recording beside the test and says
// what it cannot read.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/twk_dev.dart';
import 'package:twk_test/twk_test.dart' show screenFrames;

import 'twk.dart';

/// A recording of 20 by 4 with [events].
Cast _cast(List<(double, String, String)> events) =>
    Cast(const CastHeader(width: 20, height: 4), [
      for (final (time, code, data) in events) CastEvent(time, code, data),
    ]);

/// The text of [cast] as a file.
String _text(Cast cast) =>
    '${jsonEncode(cast.header.toJson())}\n'
    '${cast.events.map((e) => e.encode()).join('\n')}\n';

void main() {
  final plan = _cast([
    (0.1, 'o', '\x1b[?2026h\x1b[2J\x1b[Hone\r\ntwo\x1b[?2026l'),
    (0.2, 'm', 'first'),
    (0.3, 'o', "\x1b[?2026h\x1b[3;1Hthree \$'\x1b[?2026l"),
    (0.4, 'o', '\x1b[?2026h\x1b[4;1Hfour'),
    (0.5, 'm', ''),
  ]);

  group('castTestSource', () {
    test('checks a line a marker: the first that changed since the one '
        'before', () {
      final source = castTestSource(
        plan,
        castPath: 'test/plan.cast',
        source: 'plan.cast',
      );

      expect(source, contains("Cast.read('test/plan.cast')"));
      expect(source, contains('from plan.cast.'));
      expect(source, contains("test('the marker first', () {"));
      expect(source, contains("expect(frames[0].lines[0], 'one');"));
      // the screen of 0.3 s, whose update ended: 'three' is row 2, the
      // first row unlike the earlier screen's; the update still open at 0.4
      // s counts for no frame, so the marker at 0.5 s is of that one
      expect(source, contains("test('the marker at 0.300 s', () {"));
      expect(source, isNot(contains('four')));
      expect(source, contains(r"expect(frames[1].lines[2], 'three \$\'');"));
      expect(source, contains('expect(frames.last.errors, isEmpty);'));
    });

    test('checks the last screen of a recording without markers', () {
      final source = castTestSource(
        _cast([(0.1, 'o', 'one\r\ntwo'), (0.2, 'o', '\x1b[3;1Hthree')]),
        castPath: 'a.cast',
      );

      expect(source, contains("test('the last screen', () {"));
      expect(source, contains("expect(frames[1].lines[0], 'one');"));
      expect(source, isNot(contains('marker')));
    });

    test('writes what makes a literal safe as an escape', () {
      final source = castTestSource(
        _cast([(0.1, 'o', r'a\b$c')]),
        castPath: 'a.cast',
      );

      expect(source, contains(r"'a\\b\$c"));
    });

    test('frames as twk_test counts them', () {
      for (final cast in [plan, _cast([])]) {
        final theirs = screenFrames(20, 4, cast.writes);
        final source = castTestSource(cast, castPath: 'a.cast');
        // the last frame is the last one checked, by its number
        final numbers = RegExp(
          r'frames\[(\d+)\]',
        ).allMatches(source).map((m) => int.parse(m[1]!));
        if (numbers.isNotEmpty) {
          expect(numbers.every((n) => n < theirs.length), isTrue);
        }
        if (cast == plan) {
          expect(theirs, hasLength(2));
          expect(theirs[0].lines[0], 'one');
        }
      }
    });
  });

  group('twk test-from-cast', () {
    late String temp;
    setUp(() async {
      temp = (await Directory.systemTemp.createTemp('twk_t2c_')).path;
      addTearDown(() => Directory(temp).delete(recursive: true));
      File(p.join(temp, 'pubspec.yaml')).writeAsStringSync('name: app\n');
    });

    test('copies the recording beside the test, which reads it by its '
        "path from the package's root", () async {
      final cast = p.join(temp, 'rec', 'my demo.cast');
      Directory(p.dirname(cast)).createSync();
      File(cast).writeAsStringSync(_text(plan));
      final out = p.join(temp, 'test', 'sub', 'x_test.dart');

      final run = await twkHere(['test-from-cast', cast, '--out=$out']);

      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(
        File(p.join(temp, 'test', 'sub', 'my_demo.cast')).readAsStringSync(),
        _text(plan),
      );
      expect(
        File(out).readAsStringSync(),
        contains("Cast.read('test/sub/my_demo.cast')"),
      );
    });

    test('says what it cannot read, and a missing recording', () async {
      final bad = p.join(temp, 'bad.cast');
      File(bad).writeAsStringSync('not json\n');
      final out = '--out=${p.join(temp, 'o_test.dart')}';

      final unreadable = await twkHere(['test-from-cast', bad, out]);
      final missing = await twkHere([
        'test-from-cast',
        p.join(temp, 'none.cast'),
        out,
      ]);
      final none = await twkHere(['test-from-cast']);

      expect(unreadable.exitCode, 1);
      expect(unreadable.stderr, contains('bad.cast'));
      expect(missing.exitCode, 1);
      expect(missing.stderr, contains('cannot read'));
      expect(none.exitCode, usageExitCode);
      expect(File(p.join(temp, 'o_test.dart')).existsSync(), isFalse);
    });
  });
}
