// The traceback of an error: what was thrown, the source of the app's code
// it was thrown in, and the frames that led there, those not of the app
// folded.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';

const _config = '''
import 'dart:convert';

/* The configuration of the tool,
   read from JSON. */
class Config {
  Config(this.name);

  final String name;

  static Config load(String text) {
    final map = jsonDecode(text) as Map<String, Object?>;
    if (map['name'] == null) {
      throw StateError('the config has no "name"');
    }
\treturn Config(map['name']! as String);
  }
}
''';

/// The text of [lines], a line each.
List<String> _text(List<List<Span>> lines) => [
  for (final line in lines) line.map((s) => s.text).join(),
];

Future<void> _later() async {
  await Future<void>.delayed(Duration.zero);
  throw StateError('later');
}

Future<void> _caller() async {
  await _later();
}

void main() {
  late Directory dir;
  late File config;
  late File tool;

  setUp(() {
    // under the working directory, so that they are shown from it
    dir = Directory('.dart_tool').createTempSync('tb').absolute;
    addTearDown(() => dir.deleteSync(recursive: true));
    config = File('${dir.path}/config.dart')..writeAsStringSync(_config);
    tool = File('${dir.path}/tool.dart')..writeAsStringSync('void main() {}\n');
  });

  /// Where [file] is shown: its path from the working directory.
  String shown(File file) =>
      '.dart_tool/${dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty)}/'
      '${file.uri.pathSegments.last}';

  StackTrace stack() => StackTrace.fromString('''
#0      Config.load (${config.uri}:13:7)
#1      _rootRun (dart:async/zone.dart:1399:13)
#2      _CustomZone.run (dart:async/zone.dart:1301:19)
#3      AppBinding.run.<anonymous closure> (package:twk/src/binding/app_binding.dart:120:9)
<asynchronous suspension>
#4      main (${tool.uri}:12:3)
#5      _startIsolate.<anonymous closure> (dart:isolate-patch/isolate_patch.dart:300:19)
''');

  final error = StateError('the config has no "name"');

  group('traceback', () {
    test("the error, the lines around the app's first frame, the frames, "
        "those not of the app's own code folded", () {
      expect(_text(traceback(error, stack())), [
        '✗ StateError: Bad state: the config has no "name"',
        '',
        '  ${shown(config)}:13:7',
        '    11 │     final map = jsonDecode(text) as Map<String, Object?>;',
        "    12 │     if (map['name'] == null) {",
        "  ▶ 13 │       throw StateError('the config has no \"name\"');",
        '    14 │     }',
        "    15 │   return Config(map['name']! as String);",
        '',
        '  ${shown(config)}:13:7  Config.load',
        '  … 3 frames of dart:async, twk',
        '  ${shown(tool)}:12:3    main',
        '  … 1 frame of dart:isolate-patch',
      ]);
    });

    test('every frame with allFrames, as many lines around as asked', () {
      final lines = _text(
        traceback(error, stack(), allFrames: true, context: 0),
      );
      expect(lines.sublist(2, 4), [
        '  ${shown(config)}:13:7',
        "  ▶ 13 │       throw StateError('the config has no \"name\"');",
      ]);
      expect(lines.skip(5), [
        startsWith('  ${shown(config)}:13:7  '),
        startsWith('  dart:async/zone.dart:1399:13  '),
        startsWith('  dart:async/zone.dart:1301:19  '),
        // a package's frame by the file it resolves to
        startsWith('  lib/src/binding/app_binding.dart:120:9  '),
        startsWith('  ${shown(tool)}:12:3  '),
        startsWith('  dart:isolate-patch/isolate_patch.dart:300:19  '),
      ]);
      expect(lines.skip(5).map((l) => l.split(' ').last), [
        'Config.load',
        '_rootRun',
        '_CustomZone.run',
        'AppBinding.run.<fn>',
        'main',
        '_startIsolate.<fn>',
      ]);
      expect(
        _text(traceback(error, stack(), context: 5)).sublist(3, 9).first,
        '     8 │   final String name;',
      );
    });

    test('no lines of source where the file is gone or no frame is the '
        "app's; the frames alone where there is no app frame", () {
      config.deleteSync();
      expect(_text(traceback(error, stack())).sublist(0, 3), [
        '✗ StateError: Bad state: the config has no "name"',
        '',
        '  ${shown(config)}:13:7  Config.load',
      ]);
      final library = StackTrace.fromString('''
#0      _rootRun (dart:async/zone.dart:1399:13)
#1      Function.apply (dart:core/function.dart:10:5)
''');
      expect(_text(traceback(error, library)), [
        '✗ StateError: Bad state: the config has no "name"',
        '',
        '  dart:async/zone.dart:1399:13  _rootRun',
        '  dart:core/function.dart:10:5  Function.apply',
      ]);
      expect(_text(traceback(error, StackTrace.empty)), [
        '✗ StateError: Bad state: the config has no "name"',
      ]);
    });

    test('the type before the text, unless the text starts with it or '
        'the error is a string; the lines after the first indented', () {
      String first(Object e) => _text(traceback(e, StackTrace.empty)).first;
      expect(first(const FormatException('bad')), '✗ FormatException: bad');
      expect(first(Exception('x')), '✗ Exception: x');
      expect(
        first(ArgumentError('n')),
        '✗ ArgumentError: Invalid argument(s): n',
      );
      expect(first('boom'), '✗ boom');
      expect(first(_Opaque()), "✗ Instance of '_Opaque'");
      expect(first(_Failure()), '✗ Failure: it broke');
      expect(_text(traceback(_Failure(lines: true), StackTrace.empty)), [
        '✗ Failure: it broke',
        '  while saving',
        '',
        '  at x',
      ]);
      expect(first(_Throwing()), '✗ Throwing: <toString() threw StateError>');
    });

    test("in styles: the error in the theme's error colour, its type bold, "
        'the code as sourceLines gives it, its text unstyled without, the '
        'places linked to their files', () {
      const theme = ThemeData.terminal(Brightness.dark);
      final lines = traceback(error, stack());
      expect(lines[0].map((s) => s.style), [
        theme.error,
        theme.error.merge(const Style(attrs: Attr.bold)),
      ]);
      expect(lines[2][1].text, '${shown(config)}:13:7');
      expect(lines[2][1].style.link, config.uri.toString());
      final marked = lines[5];
      expect(_text([marked]).single, startsWith('  ▶ 13 │ '));
      expect(marked[1].style, theme.error);
      expect(marked[3].style, theme.muted);
      expect(marked.skip(4).map((s) => s.style), everyElement(const Style()));
      final place = lines.firstWhere(
        (l) => l.length == 3 && l[1].text.startsWith(shown(tool)),
      );
      expect(place[1].style, theme.muted.merge(Style(link: '${tool.uri}')));

      // the styles given, and the lines sourceLines gives, from the first
      const red = Style(fg: Color.red);
      const dim = Style(attrs: Attr.dim);
      final given = traceback(
        error,
        stack(),
        errorStyle: red,
        hintStyle: dim,
        sourceLines: (excerpt, theme) => [
          for (var n = excerpt.firstLine; n <= excerpt.lastLine; n++)
            [Span('line $n', red), const Span('  ')],
        ],
      );
      expect(given[0].first.style, red);
      expect(_text(given.sublist(3, 8)), [
        '    11 │ line 11',
        '    12 │ line 12',
        '  ▶ 13 │ line 13',
        '    14 │ line 14',
        '    15 │ line 15',
      ]);
      expect(given[4][1].style, dim);
    });

    test('of an error thrown past an asynchronous gap: the frames of each '
        'function awaited, the source of the first', () async {
      late StackTrace thrown;
      try {
        await _caller();
      } on Object catch (_, s) {
        thrown = s;
      }
      final lines = _text(traceback(StateError('later'), thrown));
      expect(lines[2], matches(r'^  test/debug/traceback_test\.dart:\d+:\d+$'));
      expect(
        lines.firstWhere((l) => l.startsWith('  ▶ ')),
        endsWith("throw StateError('later');"),
      );
      final frames = lines.skipWhile((l) => !l.endsWith('_later')).toList();
      expect(frames.take(3), [
        matches(r'^  test/debug/traceback_test\.dart:\d+:\d+ +_later$'),
        matches(r'^  test/debug/traceback_test\.dart:\d+:\d+ +_caller$'),
        matches(
          r'^  test/debug/traceback_test\.dart:\d+:\d+ +main\.<fn>\.<fn>$',
        ),
      ]);
    });
  });
}

final class _Opaque {}

final class _Failure {
  _Failure({this.lines = false});

  final bool lines;

  @override
  String toString() =>
      lines ? 'Failure: it broke\nwhile saving\n\nat x' : 'Failure: it broke';
}

final class _Throwing {
  @override
  String toString() => throw StateError('no');
}
