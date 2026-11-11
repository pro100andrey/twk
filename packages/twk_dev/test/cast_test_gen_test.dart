// `twk test-from-cast`: the test written over a recording. The source: a
// check of the screen at a marker held to a screen file, of the last
// screen where there are none, the emulator's errors; the command copies
// the recording beside the test and says what it cannot read.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/src/cast_test_gen.dart' show castTestPath;
import 'package:twk_dev/twk_dev.dart';

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
    String gen(Cast cast, {String source = 'the recording'}) => castTestSource(
      cast,
      castPath: 'test/a.cast',
      goldens: 'test/goldens/a',
      source: source,
    );

    test('holds the frame at each marker to a screen file of its own, the '
        'frame found by the test', () {
      final source = gen(plan, source: 'plan.cast');

      expect(source, contains("Cast.read('test/a.cast')"));
      expect(source, contains('from plan.cast.'));
      expect(source, contains('const times = <double>[\n    0.2,\n    0.5,'));
      expect(source, contains("test('the marker first', () {"));
      expect(source, contains('final number = at(times[0]);'));
      expect(source, contains("matchesScreenFile('test/goldens/a/1.txt')"));
      expect(source, contains("test('the marker at 0.500 s', () {"));
      expect(source, contains("matchesScreenFile('test/goldens/a/2.txt')"));
      expect(source, contains('expect(frames.last.errors, isEmpty);'));
      // nothing of the screens in it: it emulates nothing
      expect(source, isNot(contains('one')));
      expect(source, isNot(contains('three')));
    });

    test('a marker with no frame at or before it is skipped by the test', () {
      final source = gen(
        _cast([
          (0.0, 'm', 'early'),
          (0.1, 'o', 'one'),
        ]),
      );

      expect(source, contains("markTestSkipped('no frame at or before 0.000"));
      expect(source, contains("test('the marker early', () {"));
    });

    test('a label with a newline or ESC stays one escaped string', () {
      final source = gen(
        _cast([
          (0.0, 'm', 'x\nvoid evil() {}\x1b[31m'),
          (0.1, 'o', 'one'),
        ]),
      );

      expect(source, isNot(contains('\nvoid evil')));
      expect(source, isNot(contains('\x1b')));
      expect(source, contains(r'x\nvoid evil() {}\u{1b}[31m'));
    });

    test("the test goes in the project's test/, not the working one", () {
      expect(
        castTestPath('/work/packages/foo', 'demo'),
        '/work/packages/foo/test/demo_test.dart',
      );
    });

    test('holds the last frame of a recording without markers', () {
      final source = gen(
        _cast([(0.1, 'o', 'one\r\ntwo'), (0.2, 'o', '\x1b[3;1Hthree')]),
      );

      expect(source, contains("test('the last screen', () {"));
      expect(source, contains('screens: {if (shown.isNotEmpty) shown.length}'));
      expect(source, contains("matchesScreenFile('test/goldens/a/last.txt')"));
      expect(source, isNot(contains('marker')));
    });

    test('writes what makes a literal safe as an escape', () {
      final source = castTestSource(
        _cast([(0.1, 'o', 'x')]),
        castPath: r'a\b$c.cast',
        goldens: 'g',
      );

      expect(source, contains(r"'a\\b\$c.cast'"));
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

      final run = await twkHere([
        'test-from-cast',
        cast,
        '--out=$out',
        '--no-goldens',
      ]);

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

    test('a recording already beside the test is used where it is', () async {
      final cast = p.join(temp, 'test', 'my-demo.cast');
      Directory(p.dirname(cast)).createSync();
      File(cast).writeAsStringSync(_text(plan));
      final out = p.join(temp, 'test', 'x_test.dart');

      final run = await twkHere([
        'test-from-cast',
        cast,
        '--out=$out',
        '--no-goldens',
      ]);

      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(File(p.join(temp, 'test', 'my_demo.cast')).existsSync(), isFalse);
      expect(
        File(out).readAsStringSync(),
        contains("Cast.read('test/my-demo.cast')"),
      );
    });

    test(
      'refuses to overwrite another recording of the name, unless forced',
      () async {
        final first = p.join(temp, 'rec', 'demo.cast');
        Directory(p.dirname(first)).createSync();
        File(first).writeAsStringSync(_text(plan));
        final out = p.join(temp, 'test', 'x_test.dart');
        expect(
          (await twkHere([
            'test-from-cast',
            first,
            '--out=$out',
            '--no-goldens',
          ])).exitCode,
          0,
        );

        final other = p.join(temp, 'other', 'demo.cast');
        Directory(p.dirname(other)).createSync();
        final changed = _cast([(0.1, 'o', 'else')]);
        File(other).writeAsStringSync(_text(changed));
        final kept = File(p.join(temp, 'test', 'demo.cast'));

        final refused = await twkHere([
          'test-from-cast',
          other,
          '--out=$out',
          '--no-goldens',
        ]);
        expect(refused.exitCode, 1);
        expect(refused.stderr, contains('demo.cast'));
        expect(refused.stderr, contains('--force'));
        expect(kept.readAsStringSync(), _text(plan));

        // the same recording again is no overwrite
        expect(
          (await twkHere([
            'test-from-cast',
            first,
            '--out=$out',
            '--no-goldens',
          ])).exitCode,
          0,
        );

        final forced = await twkHere([
          'test-from-cast',
          other,
          '--out=$out',
          '--force',
          '--no-goldens',
        ]);
        expect(forced.exitCode, 0, reason: '${forced.stderr}');
        expect(kept.readAsStringSync(), _text(changed));
      },
    );

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

    test('without twk_test among the dev dependencies it says so, exits 1 '
        'and leaves the test and the recording', () async {
      final cast = p.join(temp, 'demo.cast');
      File(cast).writeAsStringSync(_text(plan));
      final out = p.join(temp, 'test', 'demo_test.dart');

      final run = await twkHere(['test-from-cast', cast, '--out=$out']);

      expect(run.exitCode, 1);
      expect(run.stdout, startsWith('wrote '));
      expect(run.stdout, contains('demo_test.dart and '));
      expect(run.stderr, contains('twk_test'));
      expect(File(out).existsSync(), isTrue);
      expect(File(p.join(temp, 'test', 'demo.cast')).existsSync(), isTrue);
      expect(Directory(p.join(temp, 'test', 'goldens')).existsSync(), isFalse);
    });
  });
}
