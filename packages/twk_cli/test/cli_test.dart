import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_cli/testing.dart';
import 'package:twk_cli/twk_cli.dart';

void main() {
  group('channels', () {
    test('results to the output, diagnostics to the error output', () {
      final terminal = FakeCliTerminal();
      Cli(terminal: terminal, level: LogLevel.debug)
        ..detail('d')
        ..info('i')
        ..success('s')
        ..warn('w')
        ..err('e')
        ..alert('a');

      expect(terminal.out.toString(), 'd\ni\ns\n');
      expect(terminal.err.toString(), 'w\ne\na\n');
    });

    test('in their styles where the terminal takes ANSI', () {
      final terminal = FakeCliTerminal(ansi: true);
      Cli(terminal: terminal, level: LogLevel.debug)
        ..detail('d')
        ..info('i')
        ..success('s')
        ..warn('w')
        ..err('e')
        ..alert('a');

      expect(terminal.out.toString(), '\x1B[2md\x1B[0m\ni\n\x1B[32ms\x1B[0m\n');
      expect(
        terminal.err.toString(),
        '\x1B[33mw\x1B[0m\n\x1B[31me\x1B[0m\n\x1B[1;97;41ma\x1B[0m\n',
      );
    });

    test('a theme restyles a channel', () {
      final terminal = FakeCliTerminal(ansi: true);
      Cli(
          terminal: terminal,
          theme: const CliTheme(
            success: Style(fg: Color.cyan, attrs: Attr.bold),
          ),
        )
        ..success('ok')
        ..warn('w');

      expect(terminal.out.toString(), '\x1B[1;36mok\x1B[0m\n');
      expect(terminal.err.toString(), '\x1B[33mw\x1B[0m\n');
    });

    test("a message's own styles go over its channel's", () {
      final terminal = FakeCliTerminal(ansi: true);
      Cli(terminal: terminal)
        ..info(['Saved'.bold, ' to ', 'disk'.fg(Color.green)])
        ..err(['failed: '.bold, 'x']);

      expect(
        terminal.out.toString(),
        '\x1B[1mSaved\x1B[0m to \x1B[32mdisk\x1B[0m\n',
      );
      expect(terminal.err.toString(), '\x1B[1;31mfailed: \x1B[22mx\x1B[0m\n');
    });

    test('no escapes where the terminal takes none, the strings too', () {
      final terminal = FakeCliTerminal();
      Cli(terminal: terminal)
        ..info(['Saved'.bold, ' to disk'])
        ..info('\x1B[1;32mPASS\x1B[0m 3 tests')
        ..alert('down');

      expect(terminal.out.toString(), 'Saved to disk\nPASS 3 tests\n');
      expect(terminal.err.toString(), 'down\n');
    });

    test('a message of several lines, null and others', () {
      final terminal = FakeCliTerminal();
      Cli(terminal: terminal)
        ..info('one\ntwo')
        ..info(null)
        ..info('')
        ..info(42)
        ..info('ends\n');

      expect(terminal.out.toString(), 'one\ntwo\n\n\n42\nends\n');
    });

    test('write is verbatim, without a line break', () {
      final terminal = FakeCliTerminal();
      Cli(terminal: terminal)
        ..write('a\x1B[1mb')
        ..write('c\n');

      expect(terminal.out.toString(), 'a\x1B[1mbc\n');
    });

    test('delayed lines wait for flush', () {
      final terminal = FakeCliTerminal();
      final cli = Cli(terminal: terminal)
        ..delayed('later')
        ..info('now');
      expect(terminal.out.toString(), 'now\n');
      cli.flush();
      expect(terminal.out.toString(), 'now\nlater\n');
      cli.flush();
      expect(terminal.out.toString(), 'now\nlater\n');
    });
  });

  group('levels', () {
    void logAll(Cli cli) => cli
      ..detail('detail')
      ..info('info')
      ..success('success')
      ..warn('warn')
      ..err('err')
      ..alert('alert');

    List<String> shown(LogLevel level) {
      final terminal = FakeCliTerminal();
      logAll(Cli(terminal: terminal, level: level));
      return '${terminal.out}${terminal.err}'.trim().split('\n');
    }

    test('each lets its channels and those above it through', () {
      expect(shown(LogLevel.debug), [
        'detail',
        'info',
        'success',
        'warn',
        'err',
        'alert',
      ]);
      expect(shown(LogLevel.info), ['info', 'success', 'warn', 'err', 'alert']);
      expect(shown(LogLevel.warning), ['warn', 'err', 'alert']);
      expect(shown(LogLevel.error), ['err', 'alert']);
    });

    test('info by default, and mutable', () {
      final terminal = FakeCliTerminal();
      final cli = Cli(terminal: terminal);
      expect(cli.level, LogLevel.info);
      cli
        ..detail('hidden')
        ..level = LogLevel.debug
        ..detail('shown');
      expect(terminal.out.toString(), 'shown\n');
    });

    test('from the flags: -v wins over -q', () {
      expect(levelFromFlags(), LogLevel.info);
      expect(levelFromFlags(verbose: true), LogLevel.debug);
      expect(levelFromFlags(quiet: true), LogLevel.error);
      expect(levelFromFlags(verbose: true, quiet: true), LogLevel.debug);
    });
  });

  group('link', () {
    test('OSC 8 where the terminal takes hyperlinks', () {
      final cli = Cli(terminal: FakeCliTerminal.interactive());
      expect(
        cli.link(Uri.parse('https://dart.dev'), 'Dart'),
        '\x1B]8;;https://dart.dev\x1B\\Dart\x1B]8;;\x1B\\',
      );
    });

    test('the label alone elsewhere, the uri without one', () {
      final cli = Cli(terminal: FakeCliTerminal());
      expect(cli.link(Uri.parse('https://dart.dev'), 'Dart'), 'Dart');
      expect(cli.link(Uri.parse('https://dart.dev')), 'https://dart.dev');
    });

    test('a message reads it back as a link', () {
      final terminal = FakeCliTerminal(ansi: true, hyperlinks: true);
      final cli = Cli(terminal: terminal);
      cli.info(['see ', cli.link(Uri.parse('https://dart.dev'), 'Dart')]);
      expect(
        terminal.out.toString(),
        'see \x1B]8;;https://dart.dev\x1B\\Dart\x1B]8;;\x1B\\\n',
      );
    });
  });

  group('flags', () {
    test('run hands open what they decide and leaves the rest to it', () async {
      final asked = <(bool?, bool?)>[];
      CliTerminal open({bool? ansi, bool? interactive}) {
        asked.add((ansi, interactive));
        return FakeCliTerminal();
      }

      await Cli.run((_) {}, open: open);
      await Cli.run((_) {}, color: false, input: false, open: open);
      expect(asked, [(null, null), (false, false)]);
    });

    test('run picks the level from -v and -q', () async {
      FakeCliTerminal open({bool? ansi, bool? interactive}) =>
          FakeCliTerminal();

      expect(await Cli.run((cli) => cli.level, open: open), LogLevel.info);
      expect(
        await Cli.run((cli) => cli.level, quiet: true, open: open),
        LogLevel.error,
      );
      expect(
        await Cli.run(
          (cli) => cli.level,
          verbose: true,
          quiet: true,
          open: open,
        ),
        LogLevel.debug,
      );
    });

    test('runWithArgs takes them off the arguments', () async {
      final asked = <(bool?, bool?)>[];
      CliTerminal open({bool? ansi, bool? interactive}) {
        asked.add((ansi, interactive));
        return FakeCliTerminal();
      }

      final (level, rest) = await Cli.runWithArgs(
        ['build', '-q', '--no-color', 'web', '--no-input', '--', '-v', 'x'],
        (cli, rest) => (cli.level, rest),
        open: open,
      );
      expect(level, LogLevel.error);
      expect(rest, ['build', 'web', '--', '-v', 'x']);
      expect(asked, [(false, false)]);

      final (verbose, _) = await Cli.runWithArgs(
        ['-v', '--quiet'],
        (cli, rest) => (cli.level, rest),
        open: open,
      );
      expect(verbose, LogLevel.debug);
    });

    test(
      '--no-color writes no escapes, the strings styled elsewhere too',
      () async {
        late FakeCliTerminal terminal;
        await Cli.runWithArgs(
          ['--no-color'],
          (cli, _) => cli.err(['x'.bold, '\x1B[31my\x1B[0m']),
          open: ({ansi, interactive}) {
            expect(ansi, isFalse);
            return terminal = FakeCliTerminal(ansi: ansi ?? true);
          },
        );
        expect(terminal.err.toString(), 'xy\n');
      },
    );
  });

  group('current', () {
    test("is the run's, in its asynchronous continuations too", () async {
      late Cli inside;
      await Cli.run((cli) async {
        await Future<void>.delayed(Duration.zero);
        inside = Cli.current;
        expect(Cli.current, same(cli));
      }, open: ({ansi, interactive}) => FakeCliTerminal());
      expect(Cli.current, isNot(same(inside)));
    });

    test('is one on stdio outside a run, the same each time', () {
      expect(Cli.current, same(Cli.current));
    });
  });

  test("mode is the terminal's", () {
    expect(Cli(terminal: FakeCliTerminal()).mode, CliMode.nonInteractive);
    expect(Cli(terminal: FakeCliTerminal.plain()).mode, CliMode.plain);
    expect(
      Cli(terminal: FakeCliTerminal.interactive()).mode,
      CliMode.interactive,
    );
  });
}
