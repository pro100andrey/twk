// An app in a fixed viewport on the normal screen: its frames through the
// emulator over a screen that showed a pattern everywhere before, which
// stays outside the viewport after each frame, a resize and the exit; the
// mouse relative to it; plain output; the terminal's mouse reports on the
// normal screen.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/src/terminal/plain.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;
import 'package:twk_test/vt.dart';

import '../terminal/fake_link.dart';
import 'pattern.dart';

/// Fills what it is laid out at with [pen] and writes its lines from its
/// first row.
final class Panel extends RenderObject {
  Panel(this.pen, this._lines);
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
  void paint(PaintContext ctx) {
    ctx.canvas.fill(0, 0, width, height, pen);
    for (var i = 0; i < _lines.length; i++) {
      ctx.canvas.text(0, i, _lines[i], pen);
    }
  }
}

/// An SGR mouse report of [button] (32 added for a drag) at screen cell
/// ([x], [y]); a release with [up].
String mouse(int button, int x, int y, {bool up = false}) =>
    '\x1b[<$button;${x + 1};${y + 1}${up ? 'm' : 'M'}';

void main() {
  const cursor = (2, 0);
  // The apps run on a clock of the test's: their frames are spaced by it
  // and run as it moves on ([pass]). A frame a resize asks for is asked
  // for once the terminal's ResizeEvent arrives, after a wait on the wall
  // clock had begun: on a loaded machine that wait could end first.
  late FakeClock clock;
  late HeadlessTerminal term;
  late Vt vt;
  late TwkApp app;
  late Panel root;
  late Future<void> done;
  late Map<(int, int), String> before;
  final events = <InputEvent>[];
  var fed = 0;

  setUp(() => clock = FakeClock());

  /// Moves the clock on by [ms]: the frames due by then run.
  Future<void> pass([int ms = 30]) => clock.elapse(Duration(milliseconds: ms));

  bool inside(int x, int y) {
    final v = app.viewport!;
    return x >= v.left &&
        y >= v.top &&
        x < v.left + app.screen.width &&
        y < v.top + app.screen.height;
  }

  /// Feeds the frames [term] kept since the last call into [vt].
  void feed() {
    for (; fed < term.frames.length; fed++) {
      vt.feed(term.frames[fed]);
    }
  }

  /// The cells outside the viewport that changed since [before].
  List<String> outsideChanges() {
    feed();
    return changes(before, shownOutside(vt, inside));
  }

  /// What the viewport shows, row by row.
  List<String> shownInside() {
    feed();
    final v = app.viewport!;
    return [
      for (var y = v.top; y < v.top + app.screen.height; y++)
        [
          for (var x = v.left; x < v.left + app.screen.width; x++)
            vt.cell(x, y).text,
        ].join(),
    ];
  }

  Future<void> start(
    Viewport view, {
    int width = 30,
    int height = 10,
    TerminalOptions options = const TerminalOptions(alternateScreen: false),
  }) async {
    vt = Vt(width, height);
    paintPattern(vt, cursor);
    fed = 0;
    events.clear();
    term = HeadlessTerminal(width: width, height: height, options: options);
    app = TwkApp(
      term,
      maxFps: 1000,
      viewport: view,
      clock: clock.stopwatch,
      environment: const {},
    );
    root = Panel(app.screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 90))), [
      'hello',
      'world',
    ]);
    before = shownOutside(vt, inside);
    done = clock.run(() => app.run(root, events.add));
    await pass();
  }

  Future<void> stop() async {
    app.quit();
    await clock.elapseUntil(done);
    feed();
  }

  /// The terminal becomes [width] x [height] and keeps what it shows.
  Future<void> resize(int width, int height) async {
    feed();
    before = shownOutside(vt, inside);
    vt.resizeKeeping(width, height);
    term.resize(width, height);
    await pass();
  }

  test('the app is laid out at the viewport, drawn in it and nowhere else, '
      'and leaves it as it is with the cursor where it found it', () async {
    await start(const Viewport.fixed(6, 3, 12, 4));
    expect((root.width, root.height), (12, 4));
    expect(shownInside(), ['hello       ', 'world       ', ' ' * 12, ' ' * 12]);
    expect(outsideChanges(), isEmpty);
    expect((vt.cx, vt.cy), cursor);
    root.show(['hello', 'there', '!']);
    await pass();
    expect(shownInside(), [
      'hello       ',
      'there       ',
      '!${' ' * 11}',
      ' ' * 12,
    ]);
    expect(outsideChanges(), isEmpty);
    expect((vt.cx, vt.cy), cursor);
    await stop();
    expect(shownInside().take(2), ['hello       ', 'there       ']);
    expect(outsideChanges(), isEmpty);
    expect((vt.cx, vt.cy), cursor);
    expect(vt.errors, isEmpty);
    expect(vt.printWraps, 0);
  });

  test("a resize cuts the viewport at the screen's edges and gives back "
      'what it cut; the rest of the screen stays', () async {
    await start(const Viewport.fixed(20, 6, 15, 6));
    expect((app.screen.width, app.screen.height), (10, 4));
    expect((root.width, root.height), (10, 4));
    expect(outsideChanges(), isEmpty);

    await resize(25, 8);
    expect((app.screen.width, app.screen.height), (5, 2));
    expect((root.width, root.height), (5, 2));
    expect(shownInside(), ['hello', 'world']);
    expect(outsideChanges(), isEmpty);

    // the viewport is off the screen: nothing to draw
    await resize(18, 8);
    expect((app.screen.width, app.screen.height), (0, 2));
    expect(outsideChanges(), isEmpty);

    await resize(40, 14);
    expect((app.screen.width, app.screen.height), (15, 6));
    expect((root.width, root.height), (15, 6));
    expect(shownInside().take(2), ['hello          ', 'world          ']);
    expect(outsideChanges(), isEmpty);
    expect((vt.cx, vt.cy), cursor);
    await stop();
    expect(outsideChanges(), isEmpty);
    expect(vt.errors, isEmpty);
  });

  test('a resize that leaves the viewport as big repaints it all the '
      'same: the terminal may have moved what it showed', () async {
    await start(const Viewport.fixed(2, 1, 8, 3));
    feed();
    vt.resize(32, 12); // what the screen shows is junk now
    term.resize(32, 12);
    await pass();
    expect(shownInside(), ['hello   ', 'world   ', ' ' * 8]);
    await stop();
    expect(vt.errors, isEmpty);
  });

  test('mouse events come relative to the viewport, those outside it are '
      'dropped, but the drags and the release of a button pressed in it, '
      'on its nearest cell', () async {
    await start(const Viewport.fixed(6, 3, 12, 4));
    events.clear();
    term.type(
      [
        mouse(0, 6, 3), // its first cell
        mouse(0, 6, 3, up: true),
        mouse(64, 17, 6), // wheel at its last cell
        mouse(0, 5, 3), // left of it
        mouse(0, 18, 6), // right of it
        mouse(64, 10, 7), // below it
        mouse(0, 10, 4), // pressed in it, dragged out and released
        mouse(32, 25, 1),
        mouse(32, 2, 9),
        mouse(0, 2, 9, up: true),
        mouse(32, 25, 1), // a drag outside, no button held
        mouse(0, 3, 9, up: true),
      ].join(),
    );
    await pass();
    expect(events.whereType<MouseEvent>(), const [
      MouseEvent(MouseKind.down, 0, 0),
      MouseEvent(MouseKind.up, 0, 0),
      MouseEvent(MouseKind.wheelUp, 11, 3),
      MouseEvent(MouseKind.down, 4, 1),
      MouseEvent(MouseKind.drag, 11, 0),
      MouseEvent(MouseKind.drag, 0, 3),
      MouseEvent(MouseKind.up, 0, 3),
    ]);
    await stop();
  });

  test('the terminal reports the mouse on the normal screen with '
      'normalScreenMouse, and the reports reach the viewport', () async {
    await start(
      const Viewport.fixed(6, 3, 12, 4),
      options: const TerminalOptions(
        alternateScreen: false,
        normalScreenMouse: true,
      ),
    );
    term.mouseTracking = MouseTracking.drags;
    expect(term.mouseTracking, MouseTracking.drags);
    expect(latin1.decode(term.frames.last), '\x1b[?1002h\x1b[?1006h');
    events.clear();
    term.type(mouse(0, 8, 4));
    await pass();
    expect(events, const [MouseEvent(MouseKind.down, 2, 1)]);
    await stop();
  });

  group('a Terminal on the normal screen', () {
    const answers = '\x1b[?2026;2\$y\x1b[?0u\x1b[?62;22c';

    test('reports the mouse with normalScreenMouse, from the start and as '
        'switched', () async {
      final link = FakeLink()..type(answers);
      final t = await Terminal.overLink(
        link,
        const TerminalOptions(
          alternateScreen: false,
          normalScreenMouse: true,
          probeTimeout: Duration(seconds: 5),
        ),
      );
      expect(t.mouseTracking, MouseTracking.drags);
      expect(link.text, contains('\x1b[?1002h\x1b[?1006h'));
      // the probe's queries on the alternate screen, the app never there
      final probed = link.text.indexOf('\x1b[?1049l');
      expect(link.text.substring(probed), isNot(contains('\x1b[?1049h')));
      t.mouseTracking = MouseTracking.motion;
      expect(t.mouseTracking, MouseTracking.motion);
      expect(link.text, contains('\x1b[?1002l\x1b[?1003h'));
      await t.close();
      expect(link.text, contains('\x1b[?1003l\x1b[?1006l'));
    });

    test('leaves the mouse to the terminal without it, in the inline '
        'mode', () async {
      final link = FakeLink()..type(answers);
      final t = await Terminal.overLink(
        link,
        const TerminalOptions(
          alternateScreen: false,
          probeTimeout: Duration(seconds: 5),
        ),
      );
      expect(t.mouseTracking, MouseTracking.off);
      t.mouseTracking = MouseTracking.drags;
      expect(t.mouseTracking, MouseTracking.off);
      await t.close();
      expect(link.text, isNot(contains('\x1b[?1002h')));
    });

    test('a HeadlessTerminal likewise', () {
      final inline = HeadlessTerminal(
        options: const TerminalOptions(alternateScreen: false),
      )..mouseTracking = MouseTracking.drags;
      expect(inline.mouseTracking, MouseTracking.off);
      expect(inline.frames, isEmpty);
    });
  });

  test('on plain output the viewport is laid out at its own size and its '
      'last frame written as lines, with nothing to place it', () async {
    final out = BytesBuilder();
    final t = await Terminal.overLink(
      PlainLink(
        const {'COLUMNS': '20', 'LINES': '6'},
        add: out.add,
        flush: () async {},
      ),
      const TerminalOptions(plain: true, alternateScreen: false),
    );
    final a = TwkApp(
      t,
      maxFps: 1000,
      viewport: const Viewport.fixed(15, 4, 10, 3),
      clock: clock.stopwatch,
      environment: const {},
    );
    final panel = Panel(a.screen.styles.pen(const Pen(attrs: Attr.bold)), [
      'a viewport',
      'there',
    ]);
    final running = clock.run(() => a.run(panel, (_) {}));
    await pass();
    expect((panel.width, panel.height), (10, 3));
    expect(out.length, 0);
    a.quit();
    await clock.elapseUntil(running);
    expect(utf8.decode(out.toBytes()), 'a viewport\nthere\n');
  });

  test('a viewport commits nothing to the history', () async {
    await start(const Viewport.fixed(1, 1, 4, 2));
    expect(() => app.commit(Panel(0, ['x'])), throwsStateError);
    await stop();
  });
}
