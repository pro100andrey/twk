// The frame loop against a headless terminal: what it writes and when,
// and that every way out restores the terminal first.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;
import 'package:twk_test/vt_terminal.dart';

/// A repaint boundary, unless [boundary] is false, that counts its paints
/// and can fail on demand.
final class Probe extends RenderObject {
  Probe(this.pen, {this.boundary = true, Stopwatch? clock})
    : _clock = clock ?? _wall;
  final int pen;
  final bool boundary;
  var paints = 0;
  Error? throwOnPaint;

  /// When each paint began, in microseconds on the clock given, by
  /// default the wall clock.
  final paintedAt = <int>[];
  final Stopwatch _clock;
  static final _wall = Stopwatch()..start();

  @override
  bool get isRepaintBoundary => boundary;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {
    paints++;
    paintedAt.add(_clock.elapsedMicroseconds);
    if (throwOnPaint != null) {
      throw throwOnPaint!;
    }
    ctx.canvas
      ..fill(0, 0, width, height, pen)
      ..text(0, 0, 'paint $paints', pen);
  }
}

/// As many rows as [rows] says, each showing its number.
final class Rows extends RenderObject {
  Rows(this.pen);
  final int pen;
  var rows = 1;

  @override
  int computeMaxIntrinsicHeight(int width) => rows;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {
    for (var y = 0; y < height; y++) {
      ctx.canvas.text(0, y, 'row $y', pen);
    }
  }
}

/// Takes at least [layoutMicros] to lay out and [paintMicros] to paint.
///
/// It spends real time on purpose: what it stands for is work that takes
/// the CPU that long, which the app's stats measure on their own
/// stopwatch, so only minimums are expected of it.
final class Slow extends RenderObject {
  Slow({this.layoutMicros = 0, this.paintMicros = 0});
  final int layoutMicros;
  final int paintMicros;

  static void _wait(int micros) {
    final watch = Stopwatch()..start();
    while (watch.elapsedMicroseconds < micros) {}
  }

  @override
  void performLayout(BoxConstraints c) {
    _wait(layoutMicros);
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) => _wait(paintMicros);
}

/// [top] on the first row and [rest] below it.
final class Pair extends RenderObject {
  Pair(this.top, this.rest) {
    adopt(top);
    adopt(rest);
  }
  final RenderObject top;
  final RenderObject rest;

  @override
  void visitChildren(void Function(RenderObject child) visit) {
    visit(top);
    visit(rest);
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    top.layout(BoxConstraints.tight(width, 1));
    rest
      ..layout(BoxConstraints.tight(width, height - 1))
      ..parentData.dy = 1;
  }

  @override
  void paint(PaintContext ctx) {
    paintChild(ctx, top);
    paintChild(ctx, rest);
  }
}

/// A stopwatch that reads [micros], which only the test moves.
final class _Clock implements Stopwatch {
  var micros = 0;

  @override
  int get elapsedMicroseconds => micros;

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Stopwatch.${invocation.memberName}');
}

void main() {
  // The apps run on a clock of the test's: their frames are spaced by it,
  // their timers fire as it moves on ([pass]), so what a test sees does
  // not depend on how fast the machine is.
  late FakeClock clock;
  late HeadlessTerminal term;
  late TwkApp app;
  late Probe probe;

  setUp(() => clock = FakeClock());

  /// Moves the clock on by [ms]: the frames and timers due by then run.
  Future<void> pass([int ms = 30]) => clock.elapse(Duration(milliseconds: ms));

  /// [TwkApp.run] on the clock.
  Future<void> runOnClock(
    TwkApp app,
    RenderObject root,
    void Function(InputEvent e) onEvent, {
    void Function()? beforeLayout,
    void Function()? afterPresent,
  }) => clock.run(
    () => app.run(
      root,
      onEvent,
      beforeLayout: beforeLayout,
      afterPresent: afterPresent,
    ),
  );

  /// An app on [term], or on what [wrap] makes of it.
  void start({
    int maxFps = 1000,
    void Function(InputEvent e)? onEvent,
    TerminalBackend Function(HeadlessTerminal term)? wrap,
  }) {
    term = HeadlessTerminal(width: 20, height: 4);
    app = TwkApp(
      wrap?.call(term) ?? term,
      maxFps: maxFps,
      clock: clock.stopwatch,
      environment: const {},
    );
    probe = Probe(
      app.screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 0))),
      clock: clock.stopwatch,
    );
  }

  test('layout measures text the way the screen draws it', () {
    // '─' is ambiguous: two cells on this terminal
    final app = TwkApp(
      HeadlessTerminal(ambiguousWidth: 2),
      environment: const {},
    );
    final text = RenderText('──', app.screen.styles.pen(const Pen()))
      ..attach(app.owner);
    expect(text.getMaxIntrinsicWidth(1), 4);
  });

  test('frames requested together are one frame', () async {
    start();
    final done = runOnClock(app, probe, (_) {});
    for (var i = 0; i < 10; i++) {
      app.requestFrame();
    }
    await pass();
    expect(probe.paints, 1);
    expect(term.frames, hasLength(1));
    expect(term.flushes, 1);
    await pass();
    expect(term.frames, hasLength(1), reason: 'nothing changed: no bytes');
    app.quit();
    await clock.elapseUntil(done);
    expect(term.closed, isTrue);
  });

  test('beforeLayout runs at the start of each frame, in the app: what it '
      'changes is laid out and painted by that frame', () async {
    start();
    var calls = 0;
    final done = runOnClock(
      app,
      probe,
      (_) {},
      beforeLayout: () {
        log('frame ${++calls}');
        probe.markNeedsLayout();
      },
    );
    await pass();
    expect((calls, probe.paints, term.frames.length), (1, 1, 1));
    app.requestFrame();
    await pass();
    expect((calls, probe.paints, term.frames.length), (2, 2, 2));
    final logged = [for (final r in app.logs.records) r.message];
    expect(logged, ['frame 1', 'frame 2']);
    app.quit();
    await clock.elapseUntil(done);
  });

  test('in the inline mode beforeLayout runs before the region is sized: '
      'the first frame fits what it adds', () async {
    final term = VtTerminal(width: 20, height: 6, history: [r'$ app']);
    final app = TwkApp(
      term,
      maxFps: 1000,
      clock: clock.stopwatch,
      environment: const {},
    );
    final root = Rows(app.screen.styles.pen(const Pen()));
    final done = runOnClock(
      app,
      root,
      (_) {},
      beforeLayout: () {
        if (root.rows < 3) {
          root
            ..rows = 3
            ..markNeedsLayout();
        }
      },
    );
    await pass();
    expect(term.frames, hasLength(1));
    expect(term.lines.take(4), [r'$ app', 'row 0', 'row 1', 'row 2']);
    app.quit();
    await clock.elapseUntil(done);
  });

  test('input waits for the first frame: an event that comes before it is '
      'handled after its beforeLayout', () async {
    start();
    final seen = <String>[];
    final done = runOnClock(
      app,
      probe,
      (e) {
        if (e is KeyEvent) {
          seen.add('key ${e.char}');
        }
      },
      beforeLayout: () => seen.add('frame'),
    );
    term.type('a');
    await pass();
    expect(seen, ['frame', 'key a']);
    app.quit();
    await clock.elapseUntil(done);
  });

  test('afterPresent runs at the end of each frame, in the app, once its '
      'bytes are written and before they are flushed: what it changes is '
      'laid out and painted by the next frame', () async {
    start();
    final seen = <(int, int)>[];
    final done = runOnClock(
      app,
      probe,
      (_) {},
      afterPresent: () {
        seen.add((term.frames.length, term.flushes));
        log('frame ${seen.length}');
        if (seen.length == 1) {
          probe.markNeedsPaint();
        }
      },
    );
    await pass();
    expect(seen, [(1, 0), (2, 1)]);
    expect(probe.paints, 2);
    // also when the frame writes nothing
    app.requestFrame();
    await pass();
    expect(seen, [(1, 0), (2, 1), (2, 2)]);
    final logged = [for (final r in app.logs.records) r.message];
    expect(logged, ['frame 1', 'frame 2', 'frame 3']);
    app.quit();
    await clock.elapseUntil(done);
  });

  test('stats time the stages of the last frame: what runs before layout, '
      'layout, paint and present, which add up to the frame', () async {
    term = HeadlessTerminal(width: 20, height: 4);
    app = TwkApp(
      term,
      maxFps: 1000,
      clock: clock.stopwatch,
      environment: const {},
    );
    final done = runOnClock(
      app,
      Slow(layoutMicros: 3000, paintMicros: 5000),
      (_) {},
      beforeLayout: () => Slow._wait(2000),
    );
    await pass(60);
    // each stage holds its own wait, so none holds another's: a load that
    // preempts the frame only adds to them
    final s = app.stats;
    expect(s.lastBuildMicros, greaterThanOrEqualTo(2000));
    expect(s.lastLayoutMicros, greaterThanOrEqualTo(3000));
    expect(s.lastPaintMicros, greaterThanOrEqualTo(5000));
    expect(s.lastPresentMicros, greaterThanOrEqualTo(0));
    expect(
      s.lastBuildMicros +
          s.lastLayoutMicros +
          s.lastPaintMicros +
          s.lastPresentMicros,
      s.lastMicros,
    );
    app.quit();
    await clock.elapseUntil(done);
  });

  test('stats count the repaint boundaries the last frame repainted that '
      'were marked for it, the root among them', () async {
    start();
    final pen = app.screen.styles.pen(const Pen());
    final top = Probe(pen);
    final rest = Probe(pen);
    final done = runOnClock(app, Pair(top, rest), (_) {});
    await pass();
    expect(app.stats.lastRepaints, 3, reason: 'all laid out the first time');
    top.markNeedsPaint();
    await pass();
    expect(app.stats.lastRepaints, 1);
    top.markNeedsPaint();
    rest.markNeedsPaint();
    await pass();
    expect(app.stats.lastRepaints, 2);
    app.requestFrame();
    await pass();
    expect(app.stats.lastRepaints, 0);
    app.owner.markAllDirty();
    rest.markNeedsPaint();
    expect(app.owner.dirtyBoundaries, 2);
    await pass();
    expect(app.stats.lastRepaints, 2, reason: 'rest repainted with the root');
    expect(rest.paints, 3, reason: 'once, with the root');
    expect(app.owner.dirtyBoundaries, 0);
    app.quit();
    await clock.elapseUntil(done);
  });

  test('a repaint asked for during the flush comes after it', () async {
    start();
    final hold = Completer<void>();
    term.holdFlush = hold.future;
    final done = runOnClock(app, probe, (_) {});
    await pass();
    expect(term.frames, hasLength(1));
    probe.markNeedsPaint();
    await pass();
    expect(term.frames, hasLength(1), reason: 'the flush is still pending');
    hold.complete();
    term.holdFlush = null;
    await pass();
    expect(term.frames, hasLength(2));
    expect(probe.paints, 2);
    app.quit();
    await clock.elapseUntil(done);
  });

  test('frames keep the minimum gap of maxFps', () async {
    start(maxFps: 20);
    final done = runOnClock(app, probe, (_) {});
    await pass(10);
    probe.markNeedsPaint();
    await pass(100);
    expect(term.frames, hasLength(2));
    expect(
      probe.paintedAt[1] - probe.paintedAt[0],
      greaterThanOrEqualTo(50000),
    );
    app.quit();
    await clock.elapseUntil(done);
  });

  test('frames are spaced by the clock given: the gap of maxFps passes on '
      'it, not on the wall clock', () async {
    // the timers wait on the test's clock, which stands for the wall clock
    // here; the frames are spaced by the other
    final given = _Clock();
    term = HeadlessTerminal(width: 20, height: 4);
    app = TwkApp(term, maxFps: 20, clock: given, environment: const {});
    probe = Probe(app.screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 0))));
    final done = runOnClock(app, probe, (_) {});
    await pass(70);
    probe.markNeedsPaint();
    await pass(10);
    expect(term.frames, hasLength(1), reason: 'the clock has not moved');
    await pass(50);
    expect(term.frames, hasLength(2));
    given.micros = 50000;
    probe.markNeedsPaint();
    await pass(10);
    expect(term.frames, hasLength(3), reason: 'the gap passed on the clock');
    app.quit();
    await clock.elapseUntil(done);
  });

  test('an error in paint ends run() after the terminal is restored', () async {
    start();
    probe.throwOnPaint = StateError('paint failed');
    await expectLater(
      clock.elapseUntil(runOnClock(app, probe, (_) {})),
      throwsA(isA<StateError>()),
    );
    expect(term.closed, isTrue);
  });

  test('an error in an event handler ends run()', () async {
    start();
    final done = runOnClock(app, probe, (e) {
      if (e is KeyEvent) {
        throw StateError('handler failed');
      }
    });
    await pass();
    term.type('\r');
    await expectLater(clock.elapseUntil(done), throwsA(isA<StateError>()));
    expect(term.closed, isTrue);
  });

  test('an error in a timer started by a handler ends run()', () async {
    start();
    final done = runOnClock(app, probe, (e) {
      Timer(Duration.zero, () => throw StateError('later'));
    });
    await pass();
    term.type('\r');
    await expectLater(clock.elapseUntil(done), throwsA(isA<StateError>()));
    expect(term.closed, isTrue);
  });

  group('a terminal that fails to close', () {
    void startFailing() => start(
      wrap: (term) => _Failing(term)..closeError = StateError('close failed'),
    );

    test('leaves run() the error that ended the app, its own logged', () async {
      startFailing();
      probe.throwOnPaint = StateError('paint failed');
      await expectLater(
        clock.elapseUntil(runOnClock(app, probe, (_) {})),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'paint failed'),
        ),
      );
      expect(term.closed, isTrue);
      expect(
        app.logs.records.map((r) => '${r.message}: ${r.error}'),
        contains('the terminal was not closed: Bad state: close failed'),
      );
    });

    test('ends run() with its error where nothing else did', () async {
      startFailing();
      final done = runOnClock(app, probe, (_) {});
      await pass();
      app.quit();
      await expectLater(
        clock.elapseUntil(done),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'close failed'),
        ),
      );
      expect(term.closed, isTrue);
    });
  });

  test('a terminal not taken back ends the app, though what handed it '
      'over catches the error', () async {
    start(
      wrap: (term) => _Failing(term)..resumeError = StateError('not back'),
    );
    final done = runOnClock(app, probe, (e) {
      unawaited(app.suspend(() async {}).catchError((Object _) {}));
    });
    await pass();
    term.type('\r');
    await expectLater(
      clock.elapseUntil(done),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', 'not back'),
      ),
    );
    expect(term.closed, isTrue);
  });

  test('quit() ends run() and stops frames', () async {
    start();
    final done = runOnClock(app, probe, (_) {});
    await pass();
    app.quit();
    await clock.elapseUntil(done);
    expect(term.closed, isTrue);
    probe.markNeedsPaint();
    app.requestFrame();
    await pass();
    expect(term.frames, hasLength(1));
  });

  test('a default color the terminal reports is blended with from then on: '
      'everything is repainted with it, nothing when it is the same', () async {
    start();
    // half white over the default background, default text at half over
    // it; not a boundary, so each paint starts from blank cells
    probe = Probe(
      app.screen.styles.pen(
        const Pen(
          fg: Color.defaultColor,
          fgAlpha: 128,
          bg: Color.rgb(255, 255, 255),
          bgAlpha: 128,
        ),
      ),
      boundary: false,
    );
    final seen = <InputEvent>[];
    final done = runOnClock(app, probe, seen.add);
    await pass();
    String last() => String.fromCharCodes(term.frames.last);
    expect(last(), contains('48;2;128;128;128'));
    term.type('\x1b]11;rgb:ffff/ffff/ffff\x1b\\');
    await pass();
    expect(app.screen.styles.defaultBackgroundRgb, 0xffffff);
    expect((probe.paints, term.frames.length), (2, 2));
    expect(last(), contains('48;2;255;255;255'));
    term.type('\x1b]10;rgb:0000/0000/0000\x1b\\');
    await pass();
    expect(app.screen.styles.defaultForegroundRgb, 0x000000);
    expect((probe.paints, term.frames.length), (3, 3));
    expect(last(), contains('38;2;127;127;127'));
    term.type(
      '\x1b]10;rgb:0000/0000/0000\x1b\\\x1b]11;rgb:ffff/ffff/ffff\x1b\\',
    );
    await pass();
    expect((probe.paints, term.frames.length), (3, 3));
    expect(seen.whereType<ColorReport>(), hasLength(4));
    app.quit();
    await clock.elapseUntil(done);
  });

  group('frames in a row', () {
    test('each frame in full below the last, its rows as text under a '
        'line naming it, instead of the bytes that draw it in place', () async {
      term = HeadlessTerminal(width: 40, height: 3);
      app = TwkApp(
        term,
        maxFps: 1000,
        framesInRow: true,
        clock: clock.stopwatch,
        environment: const {},
      );
      probe = Probe(app.screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 0))));
      final done = runOnClock(app, probe, (_) {});
      await pass();
      probe.markNeedsPaint();
      await pass();
      expect(app.stats.frames, 2);
      app.quit();
      await clock.elapseUntil(done);
      expect(term.frames.map(utf8.decode), [
        matches(
          RegExp(
            r'^\x1b\[H--- frame 1 \(\d+ bytes\) ---\r\n'
            r'paint 1\r\n\r\n\r\n$',
          ),
        ),
        matches(
          RegExp(r'^--- frame 2 \(\d+ bytes\) ---\r\npaint 2\r\n\r\n\r\n$'),
        ),
      ]);
    });

    test('the line naming a frame is cut to the width', () async {
      term = HeadlessTerminal(width: 12, height: 1);
      app = TwkApp(
        term,
        maxFps: 1000,
        framesInRow: true,
        clock: clock.stopwatch,
        environment: const {},
      );
      probe = Probe(app.screen.styles.pen(const Pen()));
      final done = runOnClock(app, probe, (_) {});
      await pass();
      app.quit();
      await clock.elapseUntil(done);
      expect(
        utf8.decode(term.frames.single),
        '\x1b[H--- frame 1\r\npaint 1\r\n',
      );
    });

    test('inline: below the history, committed rows before the frame they '
        'came with, and the region not left at the end', () async {
      final term = VtTerminal(width: 30, height: 12, history: [r'$ app']);
      final app = TwkApp(
        term,
        maxFps: 1000,
        framesInRow: true,
        clock: clock.stopwatch,
        environment: const {},
      );
      final pen = app.screen.styles.pen(const Pen());
      final root = Rows(pen)..rows = 2;
      final done = runOnClock(app, root, (_) {});
      await pass();
      app.commit(Rows(pen));
      await pass();
      app.quit();
      await clock.elapseUntil(done);
      expect(term.vt.errors, isEmpty);
      final lines = term.lines.where((l) => l.isNotEmpty).toList();
      expect(lines, [
        r'$ app',
        matches(r'^--- frame 1 \(\d+ bytes\) ---$'),
        'row 0',
        'row 1',
        'row 0',
        matches(r'^--- frame 2 \(\d+ bytes\) ---$'),
        'row 0',
        'row 1',
      ]);
      final all = term.lines;
      expect(
        (term.vt.history.length + term.vt.cy, term.vt.cx),
        (all.lastIndexWhere((l) => l.isNotEmpty) + 1, 0),
        reason: 'the cursor at the start of the line below the last frame',
      );
    });
  });

  test('a resize repaints everything at the new size', () async {
    start();
    final done = runOnClock(app, probe, (_) {});
    await pass();
    term.resize(30, 5);
    await pass();
    expect((app.screen.width, app.screen.height), (30, 5));
    expect((probe.width, probe.height), (30, 5));
    expect(term.frames, hasLength(2));
    expect(probe.paints, 2);
    app.quit();
    await clock.elapseUntil(done);
  });

  test('the median frame time is 0 before a frame, and after one the time '
      'that frame took', () async {
    start();
    expect(app.stats.medianMicros, 0);
    final done = runOnClock(app, probe, (_) {});
    await pass();
    expect(app.stats.frames, 1);
    expect(app.stats.medianMicros, app.stats.lastMicros);
    app.quit();
    await clock.elapseUntil(done);
  });

  test('the median frame time is the middle one of the frames that wrote '
      'bytes', () async {
    start();
    // the frames take at least these on the wall clock, the stats' own,
    // and as long again as a busy machine holds them up: the median is
    // checked against the times they were given, as each one ended
    const waits = [3000, 40000, 1000];
    var frame = 0;
    final took = <int>[];
    final done = runOnClock(
      app,
      probe,
      (_) {},
      beforeLayout: () {
        if (frame < waits.length) {
          Slow._wait(waits[frame++]);
          probe.markNeedsPaint();
        }
      },
      afterPresent: () => took.add(app.stats.lastMicros),
    );
    for (var i = 0; i < waits.length; i++) {
      await pass(60);
      app.requestFrame();
    }
    await pass(60);
    app.quit();
    await clock.elapseUntil(done);
    expect(app.stats.frames, waits.length);
    expect(took, hasLength(waits.length + 1), reason: 'one wrote nothing');
    final wrote = took.take(waits.length).toList()..sort();
    expect(app.stats.medianMicros, wrote[1]);
  });

  test(
    "blends with the terminal's default background from the start",
    () async {
      final term = HeadlessTerminal(
        width: 4,
        height: 1,
        backgroundRgb: 0xffffff,
      );
      final app = TwkApp(
        term,
        maxFps: 1000,
        clock: clock.stopwatch,
        environment: const {},
      );
      final pen = app.screen.styles.pen(
        const Pen(bg: Color.rgb(0, 0, 0), bgAlpha: 128),
      );
      final done = runOnClock(app, Probe(pen), (_) {});
      await pass();
      app.quit();
      await clock.elapseUntil(done);
      // the fill and the text over it each blend half black over white
      expect(utf8.decode(term.frames.first), contains('48;2;63;63;63'));
    },
  );

  test('a frame requested while one runs follows it', () async {
    start();
    var frames = 0;
    final done = runOnClock(
      app,
      probe,
      (_) {},
      afterPresent: () {
        if (++frames == 1) {
          app.requestFrame();
        }
      },
    );
    await pass();
    expect(frames, 2);
    app.quit();
    await clock.elapseUntil(done);
  });

  test(
    'on the timeline, a frame an error cuts short ends its slices',
    () async {
      final term = HeadlessTerminal(width: 20, height: 4);
      final app = TwkApp(
        term,
        maxFps: 1000,
        timeline: true,
        clock: clock.stopwatch,
        environment: const {},
      );
      final probe = Probe(app.screen.styles.pen(const Pen()))
        ..throwOnPaint = StateError('paint failed');
      await expectLater(
        clock.elapseUntil(runOnClock(app, probe, (_) {})),
        throwsStateError,
      );
      expect(
        Timeline.finishSync,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Uneven'),
          ),
        ),
        reason: 'no slice of the frame is left open',
      );
    },
  );

  test('frames in a row on the normal screen start on a line of their own '
      'when the cursor is after text', () async {
    final term = HeadlessTerminal(
      width: 20,
      height: 3,
      options: const TerminalOptions(alternateScreen: false),
      cursorColumn: 5,
    );
    final app = TwkApp(
      term,
      maxFps: 1000,
      framesInRow: true,
      clock: clock.stopwatch,
      environment: const {},
    );
    final done = runOnClock(
      app,
      Probe(app.screen.styles.pen(const Pen())),
      (_) {},
    );
    await pass();
    app.quit();
    await clock.elapseUntil(done);
    expect(utf8.decode(term.frames.first), startsWith('\r\n--- frame 1'));
  });

  test('a commit that fails as the app ends is logged as an error, and the '
      'terminal is still handed back', () async {
    final term = HeadlessTerminal(
      width: 20,
      height: 4,
      options: const TerminalOptions(alternateScreen: false),
    );
    final app = TwkApp(
      term,
      maxFps: 1000,
      clock: clock.stopwatch,
      environment: const {},
    );
    final done = runOnClock(
      app,
      Rows(app.screen.styles.pen(const Pen())),
      (_) {},
    );
    await pass();
    app
      ..commit(_FailsLayout())
      ..quit();
    await clock.elapseUntil(done);
    expect(term.closed, isTrue);
    final last = app.logs.records.last;
    expect(last.level, LogLevel.error);
    expect(last.error, isA<StateError>());
  });
  test('the debug defaults and TWK_LOG come from the environment given, '
      'TWK_DEBUG read once into debugNames; given none, nothing is on', () {
    final asked = TwkApp(
      HeadlessTerminal(),
      environment: const {
        'TWK_DEBUG': 'frames,rainbow,,relayout,timeline,mine',
        'TWK_LOG': '/nowhere/app.log',
      },
    );
    expect(asked.framesInRow, isTrue);
    expect(asked.timeline, isTrue);
    expect(asked.serveLogs, isFalse);
    expect(asked.owner.debugRepaintRainbow, isTrue);
    expect(asked.owner.debugRelayoutHighlight, isTrue);
    expect(asked.logs.path, '/nowhere/app.log');
    expect(asked.debugNames, {
      'frames',
      'rainbow',
      'relayout',
      'timeline',
      'mine',
    });
    expect(TwkApp.debugNamesRead, {
      'frames',
      'timeline',
      'logs',
      'rainbow',
      'relayout',
    });

    final none = TwkApp(HeadlessTerminal(), environment: const {});
    expect(none.environment, isEmpty);
    expect(none.debugNames, isEmpty);
    expect(
      [
        none.framesInRow,
        none.timeline,
        none.serveLogs,
        none.owner.debugRepaintRainbow,
        none.owner.debugRelayoutHighlight,
      ],
      everyElement(isFalse),
    );
    expect(none.logs.path, isNull);
  });

  test("with no environment given, the process's, over which the "
      "terminal's settings (TerminalInfo.settings) take the place of "
      'the variables they set; one given is the whole of it', () {
    final term = HeadlessTerminal(
      settings: const {
        'TWK_DEBUG': 'frames,timeline',
        'TWK_SCREEN_READER': '1',
      },
    );
    final app = TwkApp(term);
    expect(app.debugNames, {'frames', 'timeline'});
    expect(app.framesInRow, isTrue);
    expect(app.timeline, isTrue);
    expect(app.environment['TWK_SCREEN_READER'], '1');
    expect(
      app.environment.keys.toSet(),
      {...Platform.environment.keys, 'TWK_DEBUG', 'TWK_SCREEN_READER'},
      reason: "the process's variables kept",
    );
    expect(
      TwkApp(HeadlessTerminal(settings: const {'TWK_DEBUG': ''})).debugNames,
      isEmpty,
      reason: "set empty, whatever the process's says",
    );
    final given = TwkApp(term, environment: const {'TWK_DEBUG': 'logs'});
    expect(given.environment, {'TWK_DEBUG': 'logs'});
    expect((given.framesInRow, given.serveLogs), (false, true));
  });
}

/// Throws when it is laid out.
final class _FailsLayout extends RenderObject {
  @override
  void performLayout(BoxConstraints c) => throw StateError('no layout');

  @override
  void paint(PaintContext ctx) {}
}

/// [inner], whose [close] and [resume] throw [closeError] and
/// [resumeError] where they are set, once [inner] has done its part.
final class _Failing implements SuspendableBackend {
  _Failing(this.inner);

  final HeadlessTerminal inner;
  Error? closeError;
  Error? resumeError;

  @override
  TerminalInfo get info => inner.info;

  @override
  int get width => inner.width;

  @override
  int get height => inner.height;

  @override
  Stream<InputEvent> get events => inner.events;

  @override
  void write(Uint8List bytes) => inner.write(bytes);

  @override
  Future<void> flush() => inner.flush();

  @override
  Future<void> close() async {
    await inner.close();
    if (closeError case final error?) {
      throw error;
    }
  }

  @override
  Future<void> suspend() => inner.suspend();

  @override
  Future<void> resume() async {
    await inner.resume();
    if (resumeError case final error?) {
      throw error;
    }
  }
}
