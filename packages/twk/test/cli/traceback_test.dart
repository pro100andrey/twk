// The traceback of an error written by Cli.error as the terminal takes it,
// its source as the console's sourceLines gives it.
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/cli.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/cli.dart';

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

  StackTrace stack() => StackTrace.fromString('''
#0      Config.load (${config.uri}:13:7)
#1      _rootRun (dart:async/zone.dart:1399:13)
#2      _CustomZone.run (dart:async/zone.dart:1301:19)
#3      Cli.run.<anonymous closure> (package:twk/src/cli/cli.dart:120:9)
<asynchronous suspension>
#4      main (${tool.uri}:12:3)
#5      _startIsolate.<anonymous closure> (dart:isolate-patch/isolate_patch.dart:300:19)
''');

  final error = StateError('the config has no "name"');

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

    test("the source as the console's sourceLines gives it", () {
      final terminal = FakeCliTerminal();
      Cli(
        terminal: terminal,
        sourceLines: (excerpt, theme) => [
          for (var n = excerpt.firstLine; n <= excerpt.lastLine; n++)
            [Span('line $n')],
        ],
      ).error(error, stack());
      expect(terminal.err.toString(), contains('  ▶ 13 │ line 13\n'));
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
