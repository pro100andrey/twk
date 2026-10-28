// What Cli.run does with an error its body throws, or leaves uncaught in
// its zone: the traceback on the error output, the exit code set, the
// terminal restored; a prompt nobody answered ends quietly with its
// question; without handleErrors the error is the run's.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk_cli/testing.dart';
import 'package:twk_cli/twk_cli.dart';

void main() {
  late FakeCliTerminal terminal;

  CliTerminal Function({bool? ansi, bool? interactive}) open(
    FakeCliTerminal Function() make,
  ) =>
      ({ansi, interactive}) => terminal = make();

  group('an error the body throws', () {
    test('is shown as a traceback on the error output, the exit code 1, '
        'and the run completes with null', () async {
      final result = await Cli.run<String?>((cli) {
        cli.info('started');
        throw StateError('the config has no "name"');
      }, open: open(FakeCliTerminal.new));
      expect(result, isNull);
      expect(terminal.out.toString(), 'started\n');
      final err = terminal.err.toString().split('\n');
      expect(err.first, '✗ StateError: Bad state: the config has no "name"');
      expect(
        err,
        contains(matches(r'^  test/run_errors_test\.dart:\d+:\d+ +main\.')),
      );
      expect(terminal.exitCode, 1);
      expect(terminal.closed, isTrue);
    });

    test('sets errorExitCode; runWithArgs handles it too, every frame '
        'under --verbose', () async {
      await Cli.runWithArgs<void>(
        ['-v'],
        (cli, _) async {
          await Future<void>.delayed(Duration.zero);
          throw const FormatException('bad input');
        },
        errorExitCode: 3,
        open: open(FakeCliTerminal.new),
      );
      expect(terminal.exitCode, 3);
      final err = terminal.err.toString();
      expect(err, startsWith('✗ FormatException: bad input\n'));
      // the frame of the run, folded without it
      expect(err, isNot(contains('… ')));
      expect(err, contains('Cli.run.<fn>'));
    });

    test('is thrown again, once shown, where the run has to complete with '
        'a value', () async {
      await expectLater(
        Cli.run<int>(
          (cli) => throw StateError('no value'),
          open: open(FakeCliTerminal.new),
        ),
        throwsStateError,
      );
      expect(terminal.err.toString(), startsWith('✗ StateError: '));
      expect(terminal.exitCode, 1);
      expect(terminal.closed, isTrue);
    });

    test("without handleErrors is the run's: nothing shown, the code "
        'left', () async {
      await expectLater(
        Cli.run<void>(
          (cli) => throw StateError('mine'),
          handleErrors: false,
          open: open(FakeCliTerminal.new),
        ),
        throwsStateError,
      );
      expect(terminal.err.toString(), isEmpty);
      expect(terminal.exitCode, 0);
      expect(terminal.closed, isTrue);
    });

    test('a run that ends well sets no code', () async {
      expect(
        await Cli.run((cli) => 'done', open: open(FakeCliTerminal.new)),
        'done',
      );
      expect(terminal.exitCode, 0);
      expect(terminal.err.toString(), isEmpty);
    });
  });

  group('an error nothing catches in the zone', () {
    test('ends the run the body is still in, as one it throws', () async {
      await Cli.run<void>((cli) async {
        unawaited(
          Future<void>.delayed(Duration.zero, () => throw StateError('lost')),
        );
        // never ends of itself
        await Completer<void>().future;
      }, open: open(FakeCliTerminal.new));
      expect(
        terminal.err.toString(),
        startsWith('✗ StateError: Bad state: lost'),
      );
      expect(terminal.exitCode, 1);
      expect(terminal.closed, isTrue);
    });

    test('once the run has ended is shown, and sets the code, all the '
        'same', () async {
      // the run's zone on a fake clock: the body's timer fires when the
      // test moves the clock past it, after the run has ended
      final clock = FakeClock();
      var thrown = false;
      await clock.elapseUntil(
        clock.run(
          () => Cli.run<void>((cli) {
            Timer(const Duration(milliseconds: 10), () {
              thrown = true;
              throw StateError('after');
            });
          }, open: open(FakeCliTerminal.new)),
        ),
      );
      expect(thrown, isFalse);
      expect(terminal.exitCode, 0);
      await clock.elapse(const Duration(milliseconds: 10));
      expect(thrown, isTrue);
      expect(
        terminal.err.toString(),
        startsWith('✗ StateError: Bad state: after'),
      );
      expect(terminal.exitCode, 1);
    });
  });

  group('a prompt nobody answered', () {
    test('where nobody can answer: its question and why, no traceback, '
        'errorExitCode', () async {
      await Cli.run<void>(
        (cli) => cli.confirm('Proceed?'),
        errorExitCode: 2,
        open: open(FakeCliTerminal.new),
      );
      expect(
        terminal.err.toString(),
        '✗ Proceed?  nobody can answer, and it has no default\n',
      );
      expect(terminal.exitCode, 2);

      await Cli.run<void>(
        (cli) => cli.prompt(
          'Name?',
          defaultValue: 'x y',
          validate: (name) => name.contains(' ') ? 'no blanks' : null,
        ),
        open: open(FakeCliTerminal.new),
      );
      expect(
        terminal.err.toString(),
        '✗ Name?  nobody can answer, and its default is refused: no blanks\n',
      );
      expect(terminal.exitCode, 1);
    });

    test(
      'cancelled at the end of input: its question, errorExitCode',
      () async {
        await Cli.run<void>(
          (cli) => cli.prompt('Name?'),
          open: open(FakeCliTerminal.plain),
        );
        expect(terminal.screenLines, ['? Name?', '✗ Name?']);
        expect(terminal.screenLines.join('\n'), isNot(contains('Prompt')));
        expect(terminal.exitCode, 1);
      },
    );

    test('cancelled with Ctrl+C in the interactive mode: the question the '
        'prompt left, once, and 130', () async {
      // the session on a fake clock: what it draws comes when the clock is
      // moved a frame on, not in real time
      final clock = FakeClock();
      Future<void> frame() => clock.elapse(const Duration(milliseconds: 60));
      final run = Cli.run<void>(
        (cli) => cli.prompt('Name?'),
        open: open(
          () => FakeCliTerminal.interactive(
            width: 40,
            height: 8,
            fakeClock: clock,
          ),
        ),
      );
      // Ctrl+C at the prompt on the screen, not before it is asked
      for (
        var i = 0;
        i < 100 && !terminal.screenLines.any((l) => l.startsWith('? '));
        i++
      ) {
        await frame();
      }
      expect(terminal.screenLines, ['? Name?']);
      terminal.type('\x03');
      // fails 100 frames after Ctrl+C rather than hanging
      await clock.elapseUntil(
        run,
        step: const Duration(milliseconds: 60),
        within: const Duration(seconds: 6),
      );
      expect(terminal.screenLines, ['✗ Name?']);
      expect(terminal.err.toString(), isEmpty);
      expect(terminal.exitCode, 130);
      expect(terminal.backend!.closed, isTrue);
    });
  });
}
