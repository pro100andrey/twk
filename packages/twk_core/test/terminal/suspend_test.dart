// Handing the terminal to another program and taking it back: the frame
// loop on the in-memory terminal, which records being handed over, with
// what the screen shows in the emulator (the inline one below guarded
// history).
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;
import 'package:twk_test/vt.dart';
import 'package:twk_test/vt_terminal.dart';

/// Lines of text, one per row, asking for as many rows as there are.
final class Lines extends RenderObject {
  Lines(this.pen, this._lines);
  final int pen;
  List<String> _lines;

  void show(List<String> lines) {
    _lines = lines;
    markNeedsLayout();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  int computeMaxIntrinsicHeight(int width) => _lines.length;

  @override
  void paint(PaintContext ctx) {
    ctx.canvas.fill(0, 0, width, height, pen);
    for (var i = 0; i < _lines.length; i++) {
      ctx.canvas.text(0, i, _lines[i], pen);
    }
  }
}

void main() {
  // The apps run on a clock of the test's: their frames are timers that
  // fire as it moves on ([settle]); what is handed over runs in its zone
  // ([handOver]), where a wait ([later]) is one of its timers too.
  late FakeClock clock;
  setUp(() => clock = FakeClock());

  /// Moves the clock on by [ms]: the frames due by then run.
  Future<void> settle([int ms = 30]) =>
      clock.elapse(Duration(milliseconds: ms));

  /// [TwkApp.suspend] of [app] with [run], in the clock's zone, once the
  /// clock has moved on until it returned; [returned] runs as it returns,
  /// before the clock moves on to the frames it asked for.
  Future<T> handOver<T>(
    TwkApp app,
    Future<T> Function() run, [
    void Function()? returned,
  ]) => clock.elapseUntil(
    clock.run(
      () => app.suspend(run).whenComplete(() => returned?.call()),
    ),
  );

  /// A wait of [ms] on the clock, for code run in its zone.
  Future<void> later([int ms = 30]) =>
      // called only in the bodies handOver runs in the clock's zone
      // ignore: twk_lints/wall_time_in_tests
      Future<void>.delayed(Duration(milliseconds: ms));

  /// [TwkApp.run] of [app] in the clock's zone.
  Future<void> run(TwkApp app, RenderObject root) =>
      clock.run(() => app.run(root, (_) {}));

  group('fullscreen', () {
    late Vt vt;
    late HeadlessTerminal term;
    late TwkApp app;
    late Lines root;
    late Future<void> done;
    var fed = 0;

    /// Feeds the frames [term] kept since the last call into [vt].
    void feed() {
      for (; fed < term.frames.length; fed++) {
        vt.feed(term.frames[fed]);
      }
    }

    Future<void> start() async {
      vt = Vt(20, 4);
      fed = 0;
      term = HeadlessTerminal(width: 20, height: 4);
      app = TwkApp(
        term,
        maxFps: 1000,
        clock: clock.stopwatch,
        environment: const {},
      );
      root = Lines(app.screen.styles.pen(const Pen()), ['one']);
      done = run(app, root);
      await settle();
    }

    /// What another program leaves on the screen: every cell written.
    void scribble() {
      feed();
      for (var y = 0; y < 4; y++) {
        vt.feed(utf8.encode('\x1b[${y + 1}Hxxxxxxxxxxxxxxxxxxxx'));
      }
    }

    test('frames wait while the terminal is handed over; taken back, '
        'all of the screen is repainted', () async {
      await start();
      expect(term.frames, hasLength(1));
      late (bool, int, int) back;
      final got = await handOver(
        app,
        () async {
          expect(term.suspended, isTrue, reason: 'handed over before run');
          root.show(['two']);
          await later();
          scribble();
          return 7;
        },
        () => back = (term.suspended, term.suspends, term.frames.length),
      );
      expect(got, 7);
      expect(back.$1, isFalse, reason: 'taken back before it returns');
      expect((back.$2, back.$3), (1, 1));
      await settle();
      expect(term.frames, hasLength(2));
      feed();
      expect(vt.lines, ['two', '', '', '']);
      app.quit();
      await clock.elapseUntil(done);
    });

    test('what run throws reaches the caller once the terminal is '
        'back', () async {
      await start();
      late (bool, int, int) back;
      await expectLater(
        handOver<void>(
          app,
          () {
            scribble();
            return Future.error(StateError('editor failed'));
          },
          () => back = (term.suspended, term.suspends, term.frames.length),
        ),
        throwsA(isA<StateError>()),
      );
      expect(back, (false, 1, 1));
      await settle();
      feed();
      expect(vt.lines, ['one', '', '', '']);
      app.quit();
      await clock.elapseUntil(done);
    });

    test('suspending while handed over is an error', () async {
      await start();
      await handOver(app, () async {
        await expectLater(
          app.suspend(() async {}),
          throwsA(isA<StateError>()),
        );
        expect(term.suspended, isTrue);
      });
      expect((term.suspended, term.suspends), (false, 1));
      app.quit();
      await clock.elapseUntil(done);
    });
  });

  group('inline', () {
    const history = [r'$ app'];

    late Vt vt;
    late HeadlessTerminal term;
    late TwkApp app;
    late Lines root;
    late Future<void> done;
    var fed = 0;

    /// Feeds the frames [term] kept since the last call into [vt].
    void feed() {
      for (; fed < term.frames.length; fed++) {
        vt.feed(term.frames[fed]);
      }
    }

    /// Every line on the emulator: the scrollback, then the screen.
    List<String> shown() {
      feed();
      return vt.lines;
    }

    Future<void> start(List<String> lines) async {
      vt = Vt(20, 10, scrollback: true, allowLineFeed: true, relativeOnly: true)
        ..feed(utf8.encode('${history.single}\r\n'));
      vt.guardRows(vt.cy);
      fed = 0;
      term = HeadlessTerminal(
        width: 20,
        height: 10,
        options: const TerminalOptions(alternateScreen: false),
      );
      app = TwkApp(
        term,
        maxFps: 1000,
        clock: clock.stopwatch,
        environment: const {},
      );
      root = Lines(app.screen.styles.pen(const Pen()), lines);
      done = run(app, root);
      await settle();
    }

    /// Another program prints [text] where the cursor is: what it printed
    /// is guarded from then on, and the cursor is found where it left it.
    void other(String text) {
      feed();
      vt
        ..feed(utf8.encode(text))
        ..guardRows(vt.cx == 0 ? vt.cy : vt.cy + 1);
      term.resumeColumn = vt.cx;
    }

    test('the region stays above what the other program prints and '
        'starts again below it', () async {
      await start(['one', 'two']);
      await handOver(app, () async {
        feed();
        expect((vt.cx, vt.cy), (0, 3), reason: 'parked');
        other('\$ vim notes\r\nsaved');
      });
      await settle();
      expect(shown(), [
        ...history,
        'one',
        'two',
        r'$ vim notes',
        'saved',
        'one',
        'two',
        '',
        '',
        '',
      ]);
      root.show(['one', 'two', 'three']);
      await settle();
      app.quit();
      await clock.elapseUntil(done);
      expect(shown().skip(5), ['one', 'two', 'three', '', '']);
      expect((vt.cx, vt.cy), (0, 8));
    });

    test('the region starts on the cursor line when the other program '
        'ended its line', () async {
      await start(['one']);
      await handOver(app, () async => other('done\r\n'));
      await settle();
      expect(shown().take(5), [...history, 'one', 'done', 'one', '']);
      app.quit();
      await clock.elapseUntil(done);
    });

    test('quit while handed over ends run() without taking the terminal '
        'back or writing to it', () async {
      await start(['one']);
      await handOver(app, () async {
        other('elsewhere');
        app.quit();
        await done;
      });
      expect((term.suspended, term.closed), (true, true));
      expect(term.frames, hasLength(2), reason: 'the frame and the park');
      expect(shown().take(3), [...history, 'one', 'elsewhere']);
    });

    test('a backend that can not be handed over only waits with the '
        'frames', () async {
      final plain = VtTerminal(width: 20, history: history);
      app = TwkApp(
        plain,
        maxFps: 1000,
        clock: clock.stopwatch,
        environment: const {},
      );
      root = Lines(app.screen.styles.pen(const Pen()), ['one']);
      done = run(app, root);
      await settle();
      expect(plain, isNot(isA<SuspendableBackend>()));
      await handOver(app, () async {
        root.show(['two']);
        await later();
        expect(plain.frames, hasLength(2), reason: 'the frame and the park');
      });
      await settle();
      expect(plain.frames, hasLength(3));
      expect(plain.lines.take(3), [...history, 'one', 'two']);
      app.quit();
      await clock.elapseUntil(done);
    });
  });
}
