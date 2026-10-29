import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_cli/testing.dart';
import 'package:twk_cli/twk_cli.dart';

void main() {
  group('the inline session', () {
    test('is not opened by lines alone', () async {
      final terminal = FakeCliTerminal.interactive();
      final cli = Cli(terminal: terminal)
        ..info('one')
        ..warn('two');
      await cli.close();

      expect(terminal.opened, 0);
      expect(terminal.out.toString(), 'one\n');
      expect(terminal.err.toString(), '\x1B[33mtwo\x1B[0m\n');
      expect(terminal.screenLines, ['one', 'two']);
    });

    test('of a terminal without underline styles opens a backend without '
        'them', () async {
      final terminal = FakeCliTerminal(
        ansi: true,
        interactiveInput: true,
        outputIsTerminal: true,
        styledUnderlines: false,
      );
      final backend = await terminal.openInline();
      expect(backend.info.caps.styledUnderlines, isFalse);
      expect(
        (await FakeCliTerminal.interactive().openInline())
            .info
            .caps
            .styledUnderlines,
        isTrue,
      );
    });

    test('tells the lines written after it opened what its probe found of '
        'the underline styles', () async {
      // Terminal.app over ssh: the environment doesn't tell it
      final terminal = FakeCliTerminal(
        ansi: true,
        interactiveInput: true,
        outputIsTerminal: true,
        probedStyledUnderlines: false,
      );
      final cli = Cli(terminal: terminal)..writeLine(['a'.curlyUnderline]);
      expect(cli.styledUnderlines, isTrue);
      await cli.session();
      cli.writeLine(['b'.curlyUnderline]);
      expect(cli.styledUnderlines, isFalse);
      expect(
        terminal.out.toString(),
        '\x1B[4:3ma\x1B[0m\n\x1B[4mb\x1B[0m\n',
      );
      await cli.close();
    });

    test('is opened by show and kept until close', () async {
      final clock = FakeClock();
      final terminal = FakeCliTerminal.interactive(
        width: 30,
        height: 6,
        fakeClock: clock,
      );
      final cli = Cli(terminal: terminal)..info('before');
      await _settle(clock, cli.show(const Text('first widget')));
      await _settle(clock, cli.show(const Text('second widget')));
      expect(terminal.opened, 1);
      expect(terminal.backend!.closed, isFalse);
      cli.info('a line');
      await _settle(clock, cli.close());

      expect(terminal.backend!.closed, isTrue);
      expect(terminal.screenLines, [
        'before',
        'first widget',
        'second widget',
        'a line',
      ]);
      // what the session wrote went to the screen, not to the sink
      expect(terminal.out.toString(), 'before\n');
    });

    test('puts lines logged while something is live above it', () async {
      final clock = FakeClock();
      final terminal = FakeCliTerminal.interactive(
        width: 30,
        height: 6,
        fakeClock: clock,
      );
      final cli = Cli(terminal: terminal);
      final session = await _settle(clock, cli.session());
      final live = session.mount(const Text('working…'));
      cli.info('step 1');
      await _settle(clock, cli.show(const Text('step 2')));
      expect(terminal.screenLines, ['step 1', 'step 2', 'working…']);

      live.update(const Text('almost'));
      await clock.elapse(_frame);
      expect(terminal.screenLines, ['step 1', 'step 2', 'almost']);

      live.remove();
      await _settle(clock, cli.show(const Text('done')));
      expect(terminal.screenLines, ['step 1', 'step 2', 'done']);
      await _settle(clock, cli.close());
      expect(terminal.screenLines, ['step 1', 'step 2', 'done']);
    });

    test('ends on Ctrl+C that nothing took, and passes it on', () async {
      final clock = FakeClock();
      final terminal = FakeCliTerminal.interactive(
        width: 30,
        height: 6,
        fakeClock: clock,
      );
      final cli = Cli(terminal: terminal);
      final session = await _settle(clock, cli.session());
      session.mount(const Text('waiting'));
      await clock.elapse(_frame);
      terminal.type('\x03');
      await _settle(clock, session.done);

      expect(terminal.interrupts, 1);
      expect(terminal.backend!.closed, isTrue);
      expect(session.isOpen, isFalse);
      // the terminal is back: lines are written as they are
      cli.info('after');
      expect(terminal.out.toString(), 'after\n');
      expect(cli.session, throwsStateError);
      await _settle(clock, cli.show(const Text('shown')));
      expect(terminal.screenLines.last, 'shown');
      await _settle(clock, cli.close());
    });

    test('is closed by Cli.run, by an error too', () async {
      final clock = FakeClock();
      late FakeCliTerminal terminal;
      await expectLater(
        _settle(
          clock,
          Cli.run(
            (cli) async {
              await cli.show(const Text('shown'));
              throw StateError('failed');
            },
            handleErrors: false,
            open: ({ansi, interactive}) =>
                terminal = FakeCliTerminal.interactive(fakeClock: clock),
          ),
        ),
        throwsStateError,
      );
      expect(terminal.backend!.closed, isTrue);
      expect(terminal.screenLines, ['shown']);
    });

    test('is closed by Cli.run once the traceback of an error it handles '
        'is committed', () async {
      final clock = FakeClock();
      late FakeCliTerminal terminal;
      await _settle(
        clock,
        Cli.run<void>(
          (cli) async {
            await cli.show(const Text('shown'));
            throw StateError('failed');
          },
          open: ({ansi, interactive}) =>
              terminal = FakeCliTerminal.interactive(fakeClock: clock),
        ),
      );
      expect(terminal.backend!.closed, isTrue);
      expect(terminal.exitCode, 1);
      expect(
        terminal.screenLines.take(2),
        ['shown', '✗ StateError: Bad state: failed'],
      );
    });

    test('writes what write left without a line break on close', () async {
      final clock = FakeClock();
      final terminal = FakeCliTerminal.interactive(
        width: 30,
        height: 6,
        fakeClock: clock,
      );
      final cli = Cli(terminal: terminal);
      await _settle(clock, cli.show(const Text('w')));
      cli
        ..write('abc')
        ..write('def\nghi');
      await clock.elapse(_frame);
      expect(terminal.screenLines, ['w', 'abcdef']);
      await _settle(clock, cli.close());
      expect(terminal.screenLines, ['w', 'abcdef', 'ghi']);
    });

    test('keeps the styles of what is logged', () async {
      final clock = FakeClock();
      final terminal = FakeCliTerminal.interactive(
        width: 30,
        height: 6,
        fakeClock: clock,
      );
      final cli = Cli(terminal: terminal);
      await _settle(clock, cli.show(const Text('w')));
      cli.err(['bad '.bold, 'thing']);
      await _settle(clock, cli.close());

      expect(terminal.screenLines, ['w', 'bad thing']);
      final bad = terminal.screen.cell(0, 1);
      final thing = terminal.screen.cell(4, 1);
      expect(bad.fg, thing.fg);
      expect(bad.attrs & Attr.bold, Attr.bold);
      expect(thing.attrs & Attr.bold, 0);
      expect(terminal.err.toString(), isEmpty);
    });

    test('leaves an error output that is no terminal to its sink', () async {
      final clock = FakeClock();
      final terminal = FakeCliTerminal(
        ansi: true,
        interactiveInput: true,
        outputIsTerminal: true,
        errorIsTerminal: false,
        fakeClock: clock,
      );
      final cli = Cli(terminal: terminal);
      await _settle(clock, cli.show(const Text('w')));
      cli
        ..warn('to the log')
        ..info('to the screen');
      await _settle(clock, cli.close());

      expect(terminal.err.toString(), '\x1B[33mto the log\x1B[0m\n');
      expect(terminal.screenLines, ['w', 'to the screen']);
    });

    test('runs on the fake clock when given one', () async {
      final clock = FakeClock();
      final terminal = FakeCliTerminal.interactive(
        width: 20,
        height: 4,
        fakeClock: clock,
      );
      final cli = Cli(terminal: terminal);
      var shown = false;
      final showing = cli.show(const Text('later')).then((_) => shown = true);
      await clock.flushMicrotasks();
      expect(shown, isFalse);
      await clock.elapse(const Duration(milliseconds: 100));
      await showing;
      expect(terminal.screenLines, ['later']);
      final closing = cli.close();
      await clock.elapse(const Duration(milliseconds: 100));
      await closing;
      expect(terminal.backend!.closed, isTrue);
    });
  });
}

/// A frame and then some: what the session draws in that time.
const _frame = Duration(milliseconds: 60);

/// [future], once [clock] has moved on until it completed, a frame at a
/// time: what the session shows, commits and closes is done in frames.
/// Fails after 100 frames rather than hanging.
Future<T> _settle<T>(FakeClock clock, Future<T> future) =>
    clock.elapseUntil(future, step: _frame, within: _frame * 100);
