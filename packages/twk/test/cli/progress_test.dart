import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/cli.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/cli.dart';

const _ms = Duration(milliseconds: 1);

void main() {
  group('where the output is no terminal, a progress', () {
    test('writes nothing on start or update', () {
      final terminal = FakeCliTerminal();
      Cli(terminal: terminal).progress('Resolving').update('Resolving 1/2');
      expect(terminal.out.toString(), isEmpty);
    });

    test('writes the closing line alone, without a time', () {
      final terminal = FakeCliTerminal();
      Cli(terminal: terminal).progress('Resolving')
        ..update('Resolving 1/2')
        ..complete('Resolved 2');
      expect(terminal.out.toString(), '✓ Resolved 2\n');
    });

    test('closes with the last message where none is given', () {
      final terminal = FakeCliTerminal();
      Cli(terminal: terminal).progress('Resolving')
        ..update('Resolving 1/2')
        ..fail();
      expect(terminal.out.toString(), '✗ Resolving 1/2\n');
    });

    test('closes once: later calls are ignored, cancel writes none', () {
      final terminal = FakeCliTerminal();
      final cli = Cli(terminal: terminal);
      final progress = cli.progress('a')..complete();
      expect(progress.isActive, isFalse);
      progress
        ..fail('b')
        ..update('c')
        ..complete('d');
      cli.progress('e').cancel();
      expect(terminal.out.toString(), '✓ a\n');
    });

    test('writes whatever the level, to the output', () {
      final terminal = FakeCliTerminal();
      Cli(terminal: terminal, level: LogLevel.error).progress('a').complete();
      expect(terminal.out.toString(), '✓ a\n');
      expect(terminal.err.toString(), isEmpty);
    });

    test('styles its mark where the output takes escapes', () {
      final terminal = FakeCliTerminal(ansi: true);
      Cli(terminal: terminal).progress('a').fail();
      expect(terminal.out.toString(), '\x1B[31m✗ \x1B[0ma\n');
    });
  });

  group('on a terminal that does not redraw, a progress', () {
    test('writes the message on start, each changed one, the close', () {
      final terminal = FakeCliTerminal.plain();
      Cli(terminal: terminal).progress('Resolving')
        ..update('Resolving 1/2')
        ..update('Resolving 1/2')
        ..update('Resolving 2/2')
        ..complete('Resolved 2');
      expect(terminal.screenLines, [
        'Resolving',
        'Resolving 1/2',
        'Resolving 2/2',
        '✓ Resolved 2',
      ]);
    });

    test('writes its lines where nobody answers', () {
      final terminal = FakeCliTerminal(outputIsTerminal: true);
      expect(terminal.mode, CliMode.nonInteractive);
      Cli(terminal: terminal).progress('Building').complete('Built');
      expect(terminal.out.toString(), 'Building\n✓ Built\n');
    });

    test('keeps a message on one line', () {
      final terminal = FakeCliTerminal.plain();
      Cli(terminal: terminal).progress('a\nb').complete();
      expect(terminal.screenLines, ['a b', '✓ a b']);
    });
  });

  group('run', () {
    test("completes with done's message for the value", () async {
      final terminal = FakeCliTerminal();
      final progress = Cli(terminal: terminal).progress('Writing');
      final n = await progress.run(() => 3, done: (n) => 'Wrote $n');
      expect(n, 3);
      expect(progress.isActive, isFalse);
      expect(terminal.out.toString(), '✓ Wrote 3\n');
    });

    test("fails with done's message for a value ok says is not ok", () async {
      final terminal = FakeCliTerminal();
      final progress = Cli(terminal: terminal).progress('Building');
      final code = await progress.run(
        () => 2,
        ok: (code) => code == 0,
        done: (code) => 'Exit code $code',
      );
      expect(code, 2);
      expect(progress.isActive, isFalse);
      expect(terminal.out.toString(), '✗ Exit code 2\n');
    });

    test('completes where ok says the value is ok', () async {
      final terminal = FakeCliTerminal();
      final progress = Cli(terminal: terminal).progress('Building');
      await progress.run(
        () => 0,
        ok: (code) => code == 0,
        done: (_) => 'Built',
      );
      expect(terminal.out.toString(), '✓ Built\n');
    });

    test("fails with failed's message for the error, and rethrows", () async {
      final terminal = FakeCliTerminal();
      final progress = Cli(terminal: terminal).progress('Writing');
      await expectLater(
        progress.run<int>(
          () => throw StateError('disk full'),
          failed: (e) => 'Could not write: $e',
        ),
        throwsStateError,
      );
      expect(progress.isActive, isFalse);
      expect(
        terminal.out.toString(),
        '✗ Could not write: Bad state: disk full\n',
      );
    });

    test('closes with the last message without done or failed', () async {
      final terminal = FakeCliTerminal();
      final cli = Cli(terminal: terminal);
      await cli.progress('one').run(() {});
      await expectLater(
        cli.progress('two').run<void>(() => throw StateError('x')),
        throwsStateError,
      );
      expect(terminal.out.toString(), '✓ one\n✗ two\n');
    });

    test('leaves a progress the body closed as it is', () async {
      final terminal = FakeCliTerminal();
      final progress = Cli(terminal: terminal).progress('a');
      await progress.run(progress.cancel, done: (_) => 'never');
      expect(terminal.out.toString(), isEmpty);
    });

    test('cancels it where done throws, and that error goes on', () async {
      final terminal = FakeCliTerminal();
      final progress = Cli(terminal: terminal).progress('a');
      await expectLater(
        progress.run(() => 1, done: (_) => throw const FormatException()),
        throwsFormatException,
      );
      expect(progress.isActive, isFalse);
      expect(terminal.out.toString(), isEmpty);
    });
  });

  group('in the interactive mode, a progress', () {
    late FakeClock clock;
    late FakeCliTerminal terminal;
    late Cli cli;

    setUp(() {
      clock = FakeClock();
      terminal = FakeCliTerminal.interactive(
        width: 40,
        height: 8,
        fakeClock: clock,
        progressReports: true,
      );
      cli = Cli(terminal: terminal);
    });

    Future<void> close() async {
      final closing = cli.close();
      await clock.elapse(_ms * 100);
      await closing;
    }

    test('spins in the session with the time so far', () async {
      cli.progress('Building');
      await clock.elapse(_ms * 50);
      expect(terminal.screenLines, [_spinning('Building (0.0 s)')]);

      await clock.elapse(_ms * 1250);
      expect(terminal.screenLines, [_spinning('Building (1.3 s)')]);
      // a frame of the spinner further on
      expect(terminal.screenLines.single, isNot(startsWith('⠋')));
      await close();
    });

    test('commits its closing line with the time it took', () async {
      final progress = cli.progress('Building');
      await clock.elapse(_ms * 3100);
      progress.complete('Built');
      await clock.elapse(_ms * 50);
      expect(terminal.screenLines, ['✓ Built in 3.1 s']);
      expect(
        terminal.screen.cell(0, 0).fg,
        isNot(terminal.screen.cell(2, 0).fg),
      );
      // nothing is drawn any more
      final frames = terminal.backend!.frames.length;
      await clock.elapse(const Duration(seconds: 2));
      expect(terminal.backend!.frames.length, frames);
      await close();
      expect(terminal.screenLines, ['✓ Built in 3.1 s']);
      expect(terminal.out.toString(), isEmpty);
    });

    test(
      'writes the time it took cut to the tenth, from a minute a clock',
      () async {
        final quick = cli.progress('Building');
        await clock.elapse(_ms * 3190);
        quick.complete('Built');
        await clock.elapse(_ms * 50);
        final slow = cli.progress('Linking');
        await clock.elapse(const Duration(minutes: 1, seconds: 5));
        slow.complete('Linked');
        await clock.elapse(_ms * 50);
        expect(terminal.screenLines, ['✓ Built in 3.1 s', '✓ Linked in 01:05']);
        await close();
      },
    );

    test('redraws an updated message in place', () async {
      final progress = cli.progress('Resolving');
      await clock.elapse(_ms * 50);
      progress.update('Resolving 1/2');
      await clock.elapse(_ms * 50);
      expect(terminal.screenLines, [_spinning('Resolving 1/2 (0.1 s)')]);
      progress.fail();
      await clock.elapse(_ms * 50);
      expect(terminal.screenLines, ['✗ Resolving 1/2 in 0.1 s']);
      await close();
    });

    test('cuts a long message short, the time kept', () async {
      cli.progress('a long message that takes more than the row has');
      await clock.elapse(_ms * 50);
      expect(terminal.screenLines, [
        _spinning('a long message that takes mor… (0.0 s)'),
      ]);
      await close();
    });

    test('goes on cancel, leaving no line', () async {
      final progress = cli.progress('Building');
      cli.info('before');
      await clock.elapse(_ms * 50);
      expect(terminal.screenLines, ['before', _spinning('Building (0.0 s)')]);
      progress.cancel();
      await clock.elapse(_ms * 50);
      expect(terminal.screenLines, ['before']);
      await close();
    });

    test('keeps the lines logged and the prompts asked above it', () async {
      final progress = cli.progress('Building');
      await clock.elapse(_ms * 50);
      cli.info('step 1');
      await clock.elapse(_ms * 50);
      expect(terminal.screenLines, ['step 1', _spinning('Building (0.1 s)')]);

      final name = cli.prompt('Name?');
      await clock.elapse(_ms * 50);
      expect(terminal.screenLines, [
        'step 1',
        '? Name?',
        _spinning('Building (0.1 s)'),
      ]);
      terminal.type('x\r');
      await clock.elapse(_ms * 50);
      expect(await name, 'x');
      expect(terminal.screenLines, [
        'step 1',
        '✔ Name? x',
        _spinning('Building (0.2 s)'),
      ]);
      progress.complete();
      await clock.elapse(_ms * 50);
      expect(terminal.screenLines, [
        'step 1',
        '✔ Name? x',
        '✓ Building in 0.2 s',
      ]);
      await close();
    });

    test('closes before the session is open', () async {
      cli.progress('quick').complete('done');
      await clock.elapse(_ms * 50);
      expect(terminal.screenLines, ['✓ done in 0.0 s']);
      await close();
    });

    test('leaves neither spinner nor frames behind an error', () async {
      final progress = cli.progress('Building');
      final gate = Completer<void>();
      final failing = progress.run<void>(() async {
        await gate.future;
        throw StateError('broken');
      });
      final checked = expectLater(failing, throwsStateError);
      await clock.elapse(_ms * 500);
      expect(terminal.screenLines, [_spinning('Building (0.5 s)')]);
      await clock.elapse(_ms * 500);
      gate.complete();
      await clock.elapse(_ms * 50);
      await checked;
      expect(terminal.screenLines, ['✗ Building in 1.0 s']);
      // no frame is asked for: no timer waits
      expect(clock.pendingTimers, 0);
      final frames = terminal.backend!.frames.length;
      await clock.elapse(const Duration(seconds: 5));
      expect(terminal.backend!.frames.length, frames);
      await close();
    });

    test('shows a progress going on in the tab while it spins', () async {
      final progress = cli.progress('Building');
      await clock.elapse(_ms * 50);
      expect(_tab(terminal), ['\x1B]9;4;3\x1B\\']);
      progress.complete();
      await clock.elapse(_ms * 50);
      expect(_tab(terminal), ['\x1B]9;4;3\x1B\\', '\x1B]9;4;0\x1B\\']);
      await close();
    });

    test('writes its closing line once the session ended under it', () async {
      final progress = cli.progress('Building');
      await clock.elapse(_ms * 50);
      terminal.type('\x03');
      await clock.elapse(_ms * 50);
      expect(terminal.interrupts, 1);
      progress.complete('Built');
      expect(terminal.out.toString(), contains('Built'));
      expect(terminal.screenLines.last, '✓ Built in 0.1 s');
      await close();
    });
  });

  group('tasks', () {
    test(
      'where the output is no terminal, writes each task as it ends',
      () async {
        final clock = FakeClock();
        final terminal = FakeCliTerminal(fakeClock: clock);
        final cli = Cli(terminal: terminal);
        final download = Completer<void>();
        final running = cli.tasks(
          (tracker) => Future.wait([
            tracker.run(
              'Downloading assets.zip',
              (task) async {
                task.advance(1700000);
                await download.future;
                task.advance(1700000);
              },
              total: 3400000,
              unit: ProgressUnit.bytes,
            ),
            tracker.run('Building binary', (_) => 'built'),
          ]),
        );
        await clock.elapse(_ms * 1000);
        expect(terminal.out.toString(), '✓ Building binary • 0.0 s\n');
        await clock.elapse(_ms * 1100);
        download.complete();
        expect(await running, [null, 'built']);
        expect(
          terminal.out.toString(),
          '✓ Building binary • 0.0 s\n'
          '✓ Downloading assets.zip • 3.4/3.4 MB • 2.1 s\n',
        );
      },
    );

    test(
      'on a terminal that does not redraw, writes each as it starts too',
      () async {
        final clock = FakeClock();
        final terminal = FakeCliTerminal.plain(fakeClock: clock);
        final cli = Cli(terminal: terminal);
        await cli.tasks((tracker) async {
          final a = tracker.add('Fetching', total: 4)..start();
          final b = tracker.add('Linking');
          await clock.elapse(_ms * 500);
          a
            ..advance(2)
            ..label = 'Fetching more';
          b.skip();
          await clock.elapse(_ms * 500);
          a.fail('timed out');
        });
        expect(terminal.screenLines, [
          'Fetching',
          'Fetching more',
          '↓ Linking',
          '✗ Fetching more • 2/4 • 1.0 s • timed out',
        ]);
      },
    );

    test("throws the body's error again, the tracker done with", () async {
      final terminal = FakeCliTerminal();
      late ProgressTracker tracker;
      await expectLater(
        Cli(terminal: terminal).tasks((t) async {
          tracker = t;
          await t.run('a', (_) => throw StateError('x'));
        }),
        throwsStateError,
      );
      expect(terminal.out.toString(), startsWith('✗ a • 0.0 s • Bad state: x'));
      expect(() => tracker.addListener(() {}), throwsA(isA<AssertionError>()));
    });

    group('in the interactive mode', () {
      late FakeClock clock;
      late FakeCliTerminal terminal;
      late Cli cli;

      setUp(() {
        clock = FakeClock();
        terminal = FakeCliTerminal.interactive(
          width: 60,
          height: 10,
          fakeClock: clock,
          progressReports: true,
        );
        cli = Cli(terminal: terminal);
      });

      tearDown(() async {
        final closing = cli.close();
        await clock.elapse(_ms * 100);
        await closing;
      });

      test('shows the tasks with bars, rate and ETA, logs above', () async {
        final gate = Completer<void>();
        late ProgressTask zip;
        final running = cli.tasks((tracker) async {
          zip = tracker.add(
            'assets.zip',
            total: 3000000,
            unit: ProgressUnit.bytes,
          )..start();
          tracker.add('binary').start();
          await gate.future;
          for (final task in tracker.tasks) {
            task.done();
          }
        });
        await clock.elapse(_ms * 50);
        expect(terminal.screenLines, [
          matches(r'^⠋ assets\.zip ━+ +0% • ETA --:--$'),
          matches(r'^⠋ binary +━+$'),
        ]);
        for (var i = 0; i < 10; i++) {
          zip.advance(100000);
          await clock.elapse(_ms * 100);
        }
        cli.info('halfway');
        await clock.elapse(_ms * 100);
        final lines = terminal.screenLines;
        expect(lines[0], 'halfway');
        // a million bytes in 1.15 s, two million left
        expect(
          lines[1],
          matches(r'^. assets\.zip [━╸]+ +33% • 870 kB/s • ETA 00:02$'),
        );
        // the tab follows the fraction: a third of one, nothing of the other
        expect(_tab(terminal).last, '\x1B]9;4;1;17\x1B\\');

        gate.complete();
        await clock.elapse(_ms * 50);
        await running;
        expect(terminal.screenLines, [
          'halfway',
          '✓ assets.zip ${'━' * 30} 100% • 1.1 s',
          '✓ binary     ${'━' * 30} 100% • 1.1 s',
        ]);
        expect(_tab(terminal).last, '\x1B]9;4;0\x1B\\');
      });

      test('commits the finished above with hideFinished', () async {
        final first = Completer<void>();
        final second = Completer<void>();
        final running = cli.tasks(
          (tracker) async {
            final a = tracker.add('first', total: 2)..start();
            final b = tracker.add('second')..start();
            await first.future;
            a.done();
            await second.future;
            b.fail('no');
          },
          columns: const [ProgressColumn.mark, ProgressColumn.label],
          hideFinished: true,
        );
        await clock.elapse(_ms * 150);
        expect(terminal.screenLines, [
          matches('^. first'),
          matches('^. second'),
        ]);
        first.complete();
        await clock.elapse(_ms * 50);
        expect(terminal.screenLines, [
          '✓ first • 2/2 • 0.1 s',
          matches('^. second'),
        ]);
        expect(_tab(terminal).last, '\x1B]9;4;1;50\x1B\\');
        second.complete();
        await clock.elapse(_ms * 50);
        await running;
        await clock.elapse(_ms * 50);
        expect(terminal.screenLines, ['✓ first • 2/2 • 0.1 s', '✗ second']);
      });

      test(
        'commits what failed as it stands, the error thrown again',
        () async {
          final gate = Completer<void>();
          final done = expectLater(
            cli.tasks(
              (tracker) => Future.wait([
                tracker.run('a', (_) => throw StateError('x'), total: 1),
                tracker.run('b', (_) => gate.future),
              ]),
              columns: const [ProgressColumn.mark, ProgressColumn.label],
            ),
            throwsStateError,
          );
          await clock.elapse(_ms * 50);
          expect(terminal.screenLines, ['✗ a', matches(r'^. b$')]);
          // the tab in the error state, nothing done
          expect(_tab(terminal).last, '\x1B]9;4;2;0\x1B\\');
          gate.complete();
          await clock.elapse(_ms * 50);
          await done;
          await clock.elapse(_ms * 50);
          expect(terminal.screenLines, ['✗ a', '✓ b']);
        },
      );
    });
  });
}

/// The OSC 9;4 sequences the session wrote, in order.
List<String> _tab(FakeCliTerminal terminal) => [
  for (final frame in terminal.backend!.frames)
    for (final m in RegExp('\x1B\\]9;4;[^\x1B]*\x1B\\\\').allMatches(
      utf8.decode(frame, allowMalformed: true),
    ))
      m[0]!,
];

/// A row of a spinning progress: a frame of the spinner, then [text].
Matcher _spinning(String text) =>
    matches(RegExp('^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] ${RegExp.escape(text)}\$'));
