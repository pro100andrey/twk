// The traceback of an error: what was thrown, the source of the app's code
// it was thrown in, highlighted, and the frames that led there, those not
// of the app folded; written by Cli.error as the terminal takes it.
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_cli/testing.dart';
import 'package:twk_cli/twk_cli.dart';
import 'package:twk_rich/twk_rich.dart' show SyntaxTheme;

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

/// [future], once [clock] has moved on until it completed, 60 ms (a frame
/// and then some) at a time; fails after 100 frames rather than hanging.
Future<T> _settle<T>(FakeClock clock, Future<T> future) => clock.elapseUntil(
  future,
  step: const Duration(milliseconds: 60),
  within: const Duration(seconds: 6),
);

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
#3      Cli.run.<anonymous closure> (package:twk_cli/src/cli.dart:120:9)
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
        '  … 3 frames of dart:async, twk_cli',
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
        startsWith('  lib/src/cli.dart:120:9  '),
        startsWith('  ${shown(tool)}:12:3  '),
        startsWith('  dart:isolate-patch/isolate_patch.dart:300:19  '),
      ]);
      expect(lines.skip(5).map((l) => l.split(' ').last), [
        'Config.load',
        '_rootRun',
        '_CustomZone.run',
        'Cli.run.<fn>',
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

    test('in styles: the error in red, its type bold, the code highlighted '
        'from the top of the file, the places linked to their files', () {
      const theme = CliTheme();
      final syntax = SyntaxTheme.from(const CliTheme().lineData);
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
      expect(marked[3].style, theme.hint);
      expect(
        marked.firstWhere((s) => s.text == 'throw').style,
        syntax.keyword,
      );
      expect(
        marked.firstWhere((s) => s.text.startsWith("'")).style,
        syntax.string,
      );
      final place = lines.firstWhere(
        (l) => l.length == 3 && l[1].text.startsWith(shown(tool)),
      );
      expect(place[1].style, theme.hint.merge(Style(link: '${tool.uri}')));

      // the line inside a block comment that opens above it
      final inComment = traceback(
        error,
        StackTrace.fromString('#0      x (${config.uri}:4:1)\n'),
        context: 0,
      );
      expect(_text([inComment[3]]).single, '  ▶ 4 │    read from JSON. */');
      expect(inComment[3].last.style, syntax.comment);
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
      expect(lines[2], matches(r'^  test/traceback_test\.dart:\d+:\d+$'));
      expect(
        lines.firstWhere((l) => l.startsWith('  ▶ ')),
        endsWith("throw StateError('later');"),
      );
      final frames = lines.skipWhile((l) => !l.endsWith('_later')).toList();
      expect(frames.take(3), [
        matches(r'^  test/traceback_test\.dart:\d+:\d+ +_later$'),
        matches(r'^  test/traceback_test\.dart:\d+:\d+ +_caller$'),
        matches(r'^  test/traceback_test\.dart:\d+:\d+ +main\.<fn>\.<fn>$'),
      ]);
    });
  });

  group('Cli.error', () {
    test('writes the traceback to the error output, as text where the '
        'terminal takes no escapes, at the quiet level too', () {
      final terminal = FakeCliTerminal();
      Cli(terminal: terminal, level: LogLevel.error).error(error, stack());
      expect(terminal.out.toString(), isEmpty);
      expect(
        terminal.err.toString(),
        '${_text(traceback(error, stack())).join('\n')}\n',
      );
    });

    test('every frame at the verbose level', () {
      final terminal = FakeCliTerminal();
      Cli(terminal: terminal, level: LogLevel.debug).error(error, stack());
      expect(terminal.err.toString(), isNot(contains('…')));
      expect(terminal.err.toString(), contains('_CustomZone.run'));
    });

    test('in the styles and with the links the terminal takes', () {
      final terminal = FakeCliTerminal(ansi: true, hyperlinks: true);
      Cli(terminal: terminal).error(error, stack());
      final err = terminal.err.toString();
      expect(err, startsWith('\x1B[31m✗ \x1B[1mStateError'));
      expect(err, contains('\x1B]8;;${config.uri}\x1B\\'));
      final plain = FakeCliTerminal(ansi: true);
      Cli(terminal: plain).error(error, stack());
      expect(plain.err.toString(), isNot(contains('\x1B]8;')));
    });

    test('is committed above what is live in the inline session', () async {
      // the session on a fake clock: the frame the traceback is committed
      // in is drawn when the clock is moved past it, not in real time
      final clock = FakeClock();
      final terminal = FakeCliTerminal.interactive(
        width: 100,
        height: 30,
        fakeClock: clock,
      );
      final cli = Cli(terminal: terminal);
      addTearDown(() => _settle(clock, cli.close()));
      await _settle(clock, cli.show(const Text('before')));
      cli.error(error, stack());
      await clock.elapse(const Duration(milliseconds: 60));
      expect(terminal.screenLines.take(3), [
        'before',
        '✗ StateError: Bad state: the config has no "name"',
        '',
      ]);
      expect(terminal.err.toString(), isEmpty);
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
