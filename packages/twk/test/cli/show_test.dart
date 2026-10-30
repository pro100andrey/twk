import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/cli.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/cli.dart';

// as wide as the output, as a box laid out there is
const _panel = Box(
  border: Border.all(type: BorderType.rounded),
  child: Text('All systems go'),
);

void main() {
  group('show', () {
    test('writes the text of a widget where nobody answers', () async {
      final terminal = FakeCliTerminal(columns: 20);
      await Cli(terminal: terminal).show(_panel);

      expect(terminal.out.toString(), '''
╭──────────────────╮
│All systems go    │
╰──────────────────╯
''');
      expect(terminal.opened, 0);
    });

    test('lays it out at the terminal width, or the one given', () async {
      const text = Text('one two three four five six');
      final narrow = FakeCliTerminal(columns: 10);
      await Cli(terminal: narrow).show(text);
      expect(narrow.out.toString(), 'one two\nthree four\nfive six\n');

      final given = FakeCliTerminal(columns: 10);
      await Cli(terminal: given).show(text, width: 15);
      expect(given.out.toString(), 'one two three\nfour five six\n');

      // a pipe that says nothing of its width: 80 columns
      final pipe = FakeCliTerminal();
      await Cli(terminal: pipe).show(text);
      expect(pipe.out.toString(), 'one two three four five six\n');
    });

    test('writes the lines of its text on a plain terminal', () async {
      final terminal = FakeCliTerminal.plain(width: 20);
      await Cli(terminal: terminal).show(_panel);

      expect(terminal.out.toString(), contains('│All systems go    │\n'));
      expect(terminal.out.toString(), isNot(contains('\x1B')));
      expect(terminal.screenLines, [
        '╭──────────────────╮',
        '│All systems go    │',
        '╰──────────────────╯',
      ]);
    });

    test("with its styles' escapes where the output takes them", () async {
      final terminal = FakeCliTerminal(ansi: true, columns: 20);
      await Cli(terminal: terminal).show(
        Text.rich(['Deployed'.bold.fg(Color.green), const Span(' 3 services')]),
      );
      expect(
        terminal.out.toString(),
        '\x1B[1;32mDeployed\x1B[0m 3 services\n',
      );
    });

    test('under the theme of the console', () async {
      final terminal = FakeCliTerminal(columns: 20);
      final widget = Builder(
        builder: (context) => Text(Theme.of(context).brightness.name),
      );
      await Cli(
        terminal: terminal,
        theme: const CliTheme(data: ThemeData.light),
      ).show(widget);
      await Cli(terminal: terminal).show(widget);
      expect(terminal.out.toString(), 'light\ndark\n');
    });

    // a column of three rows given two
    const overflowing = SizedBox(
      height: 2,
      child: Column(children: [Text('a'), Text('b'), Text('c')]),
    );

    test("reports the core's warnings about it as the console's", () async {
      final terminal = FakeCliTerminal(columns: 10);
      final printed = await _printed(
        () => Cli(terminal: terminal).show(overflowing),
      );
      var asserts = false;
      assert(asserts = true, 'debug only');
      expect(printed, isEmpty);
      expect(terminal.out.toString(), '    a\n    b\n');
      expect(
        terminal.err.toString(),
        [
          if (asserts) 'A RenderFlex overflowed by 1 row on the bottom.\n',
        ].join(),
      );
    });

    test('and not under quiet', () async {
      final terminal = FakeCliTerminal(columns: 10);
      final printed = await _printed(
        () => Cli(terminal: terminal, level: LogLevel.error).show(overflowing),
      );
      expect(printed, isEmpty);
      expect(terminal.out.toString(), '    a\n    b\n');
      expect(terminal.err.toString(), isEmpty);
    });

    test('commits it above what is live in the interactive mode', () async {
      final clock = FakeClock();
      final terminal = FakeCliTerminal.interactive(
        width: 20,
        height: 8,
        fakeClock: clock,
      );
      final cli = Cli(terminal: terminal);
      await _settle(clock, cli.show(_panel));
      await _settle(
        clock,
        cli.show(const Text('one two three four'), width: 8),
      );
      await _settle(clock, cli.close());

      expect(terminal.out.toString(), isEmpty);
      expect(terminal.screenLines, [
        '╭──────────────────╮',
        '│All systems go    │',
        '╰──────────────────╯',
        'one two',
        'three',
        'four',
      ]);
      expect(terminal.screen.errors, isEmpty);
      // the cursor below what was shown, at the start of a line
      expect((terminal.screen.cx, terminal.screen.cy), (0, 6));
    });

    test('in the interactive mode under the theme of the console', () async {
      final clock = FakeClock();
      final terminal = FakeCliTerminal.interactive(
        width: 20,
        height: 4,
        fakeClock: clock,
      );
      final cli = Cli(
        terminal: terminal,
        theme: const CliTheme(data: ThemeData.light),
      );
      await _settle(
        clock,
        cli.show(
          Builder(
            builder: (context) => Text(Theme.of(context).brightness.name),
          ),
        ),
      );
      await _settle(clock, cli.close());
      expect(terminal.screenLines, ['light']);
    });
  });
}

/// What [body] prints, the zone's print, where the core's warnings go
/// that nobody routes.
Future<List<String>> _printed(Future<void> Function() body) async {
  final lines = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, line) => lines.add(line),
    ),
  );
  return lines;
}

/// [future], once [clock] has moved on until it completed, 60 ms (a frame
/// and then some) at a time: what the inline session shows and closes is
/// done in frames. Fails after 100 frames rather than hanging.
Future<T> _settle<T>(FakeClock clock, Future<T> future) => clock.elapseUntil(
  future,
  step: const Duration(milliseconds: 60),
  within: const Duration(seconds: 6),
);
