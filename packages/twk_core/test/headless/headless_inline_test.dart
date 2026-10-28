// The inline mode on the in-memory terminal: the frames it keeps, fed into
// the emulator as a normal screen with a scrollback below lines printed
// before the app ran, which the emulator guards (a write to them, or an
// absolute row, fails the frame).
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;
import 'package:twk_test/vt.dart';
import 'package:twk_test/vt_terminal.dart';

/// Lines of text, one per row, asking for as many rows as there are;
/// with [tag], that text right-aligned on each, which only a frame laid out
/// at the width puts whole (of a row too wide, a terminal without autowrap
/// shows the last character, written over the last column).
final class Lines extends RenderObject {
  Lines(this.pen, this._lines);
  final int pen;
  List<String> _lines;
  String? tag;

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
      if (tag case final tag?) {
        ctx.canvas.text(width - tag.length, i, tag, pen);
      }
    }
  }
}

void main() {
  const history = [r'$ ls', 'a  b  c', r'$ app'];

  // The apps run on a clock of the test's: their frames are spaced by it
  // and run as it moves on ([pass]). A frame a resize asks for is asked
  // for once the terminal's ResizeEvent arrives, after a wait on the wall
  // clock had begun: on a loaded machine that wait could end first.
  late FakeClock clock;
  late HeadlessTerminal term;
  late Vt vt;
  late TwkApp app;
  late Lines root;
  late Future<void> done;
  var fed = 0;

  setUp(() => clock = FakeClock());

  /// Moves the clock on by [ms]: the frames due by then run.
  Future<void> pass([int ms = 30]) => clock.elapse(Duration(milliseconds: ms));

  /// [TwkApp.run] of [app] on the clock.
  Future<void> runOnClock(TwkApp app, RenderObject root) =>
      clock.run(() => app.run(root, (_) {}));

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

  Future<void> start(
    List<String> lines, {
    int width = 20,
    int height = 8,
    List<String> history = history,
    bool atLineStart = true,
  }) async {
    vt = Vt(
      width,
      height,
      scrollback: true,
      allowLineFeed: true,
      relativeOnly: true,
    );
    for (var i = 0; i < history.length; i++) {
      vt.feed(utf8.encode(history[i]));
      if (atLineStart || i < history.length - 1) {
        vt.feed(const [0x0D, 0x0A]);
      }
    }
    vt.guardRows(atLineStart ? vt.cy : vt.cy + 1);
    fed = 0;
    term = HeadlessTerminal(
      width: width,
      height: height,
      options: const TerminalOptions(alternateScreen: false),
      cursorColumn: vt.cx,
    );
    app = TwkApp(
      term,
      maxFps: 1000,
      clock: clock.stopwatch,
      environment: const {},
    );
    root = Lines(app.screen.styles.pen(const Pen()), lines);
    done = runOnClock(app, root);
    await pass();
  }

  Future<void> stop() async {
    app.quit();
    await clock.elapseUntil(done);
    feed();
  }

  /// The terminal becomes [width] x [height] and keeps what it shows (see
  /// [Vt.resizeKeeping]).
  Future<void> resize(int width, int height, {bool pull = false}) async {
    feed();
    vt.resizeKeeping(width, height, pull: pull);
    term.resize(width, height);
    await pass();
  }

  test('the region starts below the history, which stays; on exit the '
      'cursor is on the line below it', () async {
    await start(['one', 'two']);
    expect(app.screen.height, 2);
    expect(shown(), [...history, 'one', 'two', '', '', '']);
    await stop();
    expect(shown(), [...history, 'one', 'two', '', '', '']);
    expect((vt.cx, vt.cy), (0, 5));
    expect(term.closed, isTrue);
  });

  test('after text on the cursor line the region starts on the next '
      'line', () async {
    await start(['one'], history: [r'$ printf abc', 'abc'], atLineStart: false);
    expect(shown().take(3), [r'$ printf abc', 'abc', 'one']);
    await stop();
    expect((vt.cx, vt.cy), (0, 3));
  });

  test('the region grows into the scrollback and shrinks when '
      'asked', () async {
    await start(['1'], height: 6);
    for (var n = 2; n <= 5; n++) {
      root.show([for (var i = 1; i <= n; i++) '$i']);
      await pass();
      expect(app.screen.height, n);
    }
    expect(shown(), [...history, '1', '2', '3', '4', '5']);
    expect(vt.history, hasLength(2));
    root.show(['1', '2']);
    app.shrinkRegion();
    await pass();
    expect(app.screen.height, 2);
    expect(shown(), [...history, '1', '2', '', '', '']);
    await stop();
    expect((vt.cx, vt.cy), (0, 3));
  });

  test('a resize repaints the region at the new width; the history '
      'stays', () async {
    // The terminal cuts its rows itself (no reflow): only a frame laid
    // out at the new width ends each row in the tag.
    String tagged(String line, int width) =>
        '${line.padRight(width - 3).substring(0, width - 3)}[x]';
    await start(['first line here', 'second']);
    root
      ..tag = '[x]'
      ..show(['first line here', 'second']);
    await pass();
    expect(shown(), [
      ...history,
      tagged('first line here', 20),
      tagged('second', 20),
      '',
      '',
      '',
    ]);
    await resize(10, 8);
    expect(shown(), [...history, 'first l[x]', 'second [x]', '', '', '']);
    // the cursor's row is cut off: the screen scrolls the history up
    await resize(30, 4, pull: true);
    expect(shown(), [
      ...history,
      tagged('first line here', 30),
      tagged('second', 30),
    ]);
    expect(vt.history, hasLength(1));
    await stop();
    expect(shown(), [
      ...history,
      tagged('first line here', 30),
      tagged('second', 30),
      '',
    ]);
  });

  test('the same bytes as on the emulator backend', () async {
    Future<void> run(TerminalBackend term, void Function() resize) async {
      final app = TwkApp(
        term,
        maxFps: 1000,
        maxInlineRows: 3,
        clock: clock.stopwatch,
        environment: const {},
      );
      final root = Lines(app.screen.styles.pen(const Pen()), ['a']);
      final done = runOnClock(app, root);
      await pass();
      root.show(['a', 'b', 'c', 'd']);
      await pass();
      resize();
      await pass();
      root.show(['e']);
      app.shrinkRegion();
      await pass();
      app.quit();
      await clock.elapseUntil(done);
    }

    final emulated = VtTerminal(width: 20, height: 6, history: history);
    final headless = HeadlessTerminal(
      width: 20,
      height: 6,
      options: const TerminalOptions(alternateScreen: false),
    );
    await run(emulated, () => emulated.resize(12, 6));
    await run(headless, () => headless.resize(12, 6));
    final want = [for (final f in emulated.frames) ...f];
    expect(want, isNotEmpty);
    expect([for (final f in headless.frames) ...f], want);
  });
}
