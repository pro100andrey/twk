// The debug keys as a user meets them: while Ctrl+G waits for its key, a
// line over the bottom row says which key does what, gone with the next
// key and laying nothing of the app out again; Ctrl+G twice still gives the
// app a Ctrl+G; the rainbow, turned on or off, shows at once on an app
// that repaints nothing. Ctrl+G is sent as Konsole sends it, CSI 103;5u.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../binding/harness.dart';

/// Ctrl+G as Konsole 26.08 sends it.
const ctrlG = '\x1b[103;5u';

/// The line of the debug keys on a screen 40 columns wide: the prefix, and
/// the commands that fit.
const hint40 = ' ctrl+g  o overlay  r rainbow  c console';

/// Every command, on a screen wide enough for all of them.
const hintAll =
    ' ctrl+g  o overlay  r rainbow  c console  l relayout  f level  y copy'
    '  s save  x clear  h reload  H restart  ctrl+g to the app';

/// [child] under a listener that takes every key and adds it to [keys], as
/// a key binding names it.
Widget listening(List<String> keys, Widget child) => InputListener(
  onEvent: (e) {
    if (e is KeyEvent) {
      keys.add('${KeyCombo.fromEvent(e)}');
    }
    return true;
  },
  child: child,
);

/// Layouts and paints counted.
final class Counts {
  var layouts = 0;
  var paints = 0;
}

/// A repaint boundary [rows] rows tall, as wide as it may be, filled with
/// [char]; it counts its layouts and paints in [counts].
final class Area extends LeafRenderObjectWidget {
  const Area(this.char, this.rows, this.counts, {super.key});

  final String char;
  final int rows;
  final Counts counts;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderArea(char, rows, counts);
}

final class _RenderArea extends RenderObject {
  _RenderArea(this.char, this.rows, this.counts);

  final String char;
  final int rows;
  final Counts counts;

  @override
  bool get isRepaintBoundary => true;

  @override
  int computeMaxIntrinsicHeight(int width) => rows;

  @override
  void performLayout(BoxConstraints c) {
    counts.layouts++;
    width = c.maxW;
    height = c.constrainH(rows);
  }

  @override
  void paint(PaintContext ctx) {
    counts.paints++;
    ctx.canvas.fill(
      0,
      0,
      width,
      height,
      ctx.canvas.styles.pen(const Pen()),
      char.codeUnitAt(0),
    );
  }
}

/// A repaint boundary one row tall and as wide as it may be that shows
/// [text]: a new text repaints it alone.
final class Line extends LeafRenderObjectWidget {
  const Line(this.text, {super.key});

  final String text;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderLine(text);

  @override
  void updateRenderObject(BuildContext context, RenderLine renderObject) =>
      renderObject.show(text);
}

/// What a [Line] lays out and paints.
final class RenderLine extends RenderObject {
  RenderLine(this._text);

  String _text;

  /// Shows [t] from the next frame on.
  void show(String t) {
    if (t != _text) {
      _text = t;
      markNeedsPaint();
    }
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    final pen = ctx.canvas.styles.pen(const Pen());
    ctx.canvas
      ..fill(0, 0, width, height, pen)
      ..text(0, 0, _text, pen);
  }
}

/// The backgrounds of the cells of [t]'s screen.
Set<int> backgrounds(TwkTester t) => {
  for (var y = 0; y < t.terminal.height; y++)
    for (var x = 0; x < t.terminal.width; x++) t.cell(x, y).bg,
};

void main() {
  const theme = ThemeData.terminal(Brightness.dark);

  testTwk('while Ctrl+G waits for its key, a line over the bottom row names '
      'it and the commands that fit; the next key takes it away; the app '
      'is not laid out again, and painted again only where the line was', (
    t,
  ) async {
    final top = Counts();
    final bottom = Counts();
    final keys = <String>[];
    await t.pumpWidget(
      listening(
        keys,
        Column(children: [Area('u', 4, top), Area('b', 2, bottom)]),
      ),
      size: (40, 6),
    );
    t.binding.debug.keys = true;
    final screen = t.lines;

    await t.type(ctrlG);
    await t.pump();
    expect(t.lines.take(5), screen.take(5));
    expect(t.lines.last, hint40);
    // the prefix on the primary's fill
    expect(
      t,
      styleAt(1, 5, allOf(hasBg(theme.primary.fg!), hasAttr(Attr.bold))),
    );
    expect(t, styleAt(1, 5, hasFg(theme.onPrimary.fg!)));
    expect(
      t,
      styleAt(9, 5, allOf(hasFg(theme.primary.fg!), hasAttr(Attr.bold))),
    );
    expect(t, styleAt(9, 5, isNot(hasAttr(Attr.reverse))));
    expect(t, styleAt(11, 5, hasFg(const Color.indexed(245))));
    expect((top.layouts, bottom.layouts), (1, 1));
    expect((top.paints, bottom.paints), (1, 1));

    await t.press('x');
    await t.pump();
    expect(t.lines, screen);
    expect(keys, isEmpty, reason: 'x after Ctrl+G is dropped');
    expect((top.layouts, bottom.layouts), (1, 1));
    expect((top.paints, bottom.paints), (1, 2));

    await t.press('x');
    expect(keys, ['x']);
  });

  testTwk('an app that repaints under it has it painted over again', (
    t,
  ) async {
    final key = GlobalKey<ProbeState>();
    await t.pumpWidget(
      Probe(
        key: key,
        (s) => Column(
          children: [
            Area('u', 3, Counts()),
            Line('count ${s.count}'),
          ],
        ),
      ),
      size: (40, 4),
    );
    t.binding.debug.keys = true;
    await t.type(ctrlG);
    await t.pump();
    expect(t.lines.last, hint40);
    key.currentState!.change(() => key.currentState!.count++);
    await t.pump();
    expect(t.lines.last, hint40);
    expect(t.binding.twkApp.stats.lastRepaints, 1, reason: 'the line alone');
    await t.press('escape');
    await t.pump();
    expect(t.lines.last, 'count 1');
  });

  testTwk('on a screen wide enough the line lists every command', (t) async {
    await t.pumpWidget(const Label('app'), size: (130, 4));
    t.binding.debug.keys = true;
    await t.type(ctrlG);
    await t.pump();
    expect(t.lines.last, hintAll);
  });

  testTwk('Ctrl+G twice gives the app a Ctrl+G, and the line goes with the '
      "second; the key after it is the app's", (t) async {
    final keys = <String>[];
    await t.pumpWidget(listening(keys, const Label('app')), size: (40, 4));
    t.binding.debug.keys = true;
    await t.type(ctrlG);
    await t.pump();
    expect(t.lines.last, hint40);
    await t.type(ctrlG);
    await t.pump();
    expect(keys, ['ctrl+g']);
    expect(t.lines, ['app', '', '', '']);
    await t.press('c');
    await t.pump();
    expect(keys, ['ctrl+g', 'c']);
    expect(t.binding.debug.console.isOpen, isFalse);
  });

  testTwk('in the inline mode the line goes over the bottom row of the '
      'region, which does not grow, and the app is not laid out again', (
    t,
  ) async {
    final counts = Counts();
    await t.pumpWidget(
      Area('a', 2, counts),
      mode: ScreenMode.inline,
      size: (40, 10),
      history: [r'$ run'],
    );
    t.binding.debug.keys = true;
    final a = 'a' * 40;
    expect(t.lines.take(4), [r'$ run', a, a, '']);

    await t.type(ctrlG);
    await t.pump();
    expect(t.lines.take(4), [r'$ run', a, hint40, '']);
    expect(counts.layouts, 1);

    await t.press('escape');
    await t.pump();
    expect(t.lines.take(4), [r'$ run', a, a, '']);
    expect(counts.layouts, 1);
  });

  testTwk('in the inline mode a region that kept rows the app no longer '
      'fills keeps them once the line goes', (t) async {
    final key = GlobalKey<ProbeState>();
    await t.pumpWidget(
      Probe(
        key: key,
        (s) => column([for (var i = 0; i < 3 - 2 * s.count; i++) Label('$i')]),
      ),
      mode: ScreenMode.inline,
      size: (40, 10),
      history: [r'$ run'],
    );
    t.binding.debug.keys = true;
    key.currentState!.change(() => key.currentState!.count++);
    await t.pump();
    final screen = t.binding.twkApp.screen;
    expect(screen.height, 3, reason: 'by itself the region only grows');

    await t.type(ctrlG);
    await t.pump();
    expect(t.lines.take(5), [r'$ run', '0', '', hint40, '']);
    await t.press('escape');
    await t.pump();
    expect(screen.height, 3);
    expect(t.lines.take(5), [r'$ run', '0', '', '', '']);
  });

  testTwk('over the open console it covers the bottom row, also while the '
      'console shows a new record; Escape after Ctrl+G is dropped', (
    t,
  ) async {
    await t.pumpWidget(const Label('app'), size: (60, 14));
    t.binding.debug.keys = true;
    final time = DateTime(2026, 10, 19, 9, 5, 7, 42);
    for (var i = 0; i < 9; i++) {
      t.logs.add(LogRecord(time, LogLevel.info, 'm$i'));
    }
    await t.type('${ctrlG}c');
    await t.pump();
    final console = t.binding.debug.console;
    expect(console.isOpen, isTrue);
    expect(t.lines.last, ' 09:05:07.042 INFO  m8');

    await t.type(ctrlG);
    await t.pump();
    expect(t.lines.last, startsWith(' ctrl+g  o overlay'));
    t.logs.add(LogRecord(time, LogLevel.info, 'two'));
    await t.pump();
    expect(t.lines[4], ' console  debug+  10 of 10');
    expect(t.lines.last, startsWith(' ctrl+g  o overlay'));

    await t.press('escape');
    await t.pump();
    expect(console.isOpen, isTrue);
    expect(t.lines.last, ' 09:05:07.042 INFO  two');
  });

  testTwk('over the frame overlay where the overlay reaches the bottom row, '
      'also when the overlay shows new numbers', (t) async {
    final key = GlobalKey<ProbeState>();
    await t.pumpWidget(
      Probe(key: key, (s) => Label('count ${s.count}')),
      size: (40, 8),
    );
    t.binding.debug.keys = true;
    await t.type('${ctrlG}o');
    await t.pump(const Duration(seconds: 1));
    expect(t.lines.first, endsWith(' fps'));

    await t.type(ctrlG);
    await t.pump();
    expect(t.lines.last, hint40);
    final shown = t.lines.sublist(1, 7);
    key.currentState!.change(() => key.currentState!.count++);
    await t.pump(const Duration(seconds: 1));
    expect(t.lines.first, startsWith('count 1'));
    expect(t.lines.sublist(1, 7), isNot(shown), reason: 'new numbers');
    expect(t.lines.last, hint40);
  });

  testTwk('turned off while Ctrl+G waits, the keys take the line away, and '
      "the next key is the app's", (t) async {
    final keys = <String>[];
    await t.pumpWidget(listening(keys, const Label('app')), size: (40, 4));
    final debug = t.binding.debug..keys = true;
    await t.type(ctrlG);
    await t.pump();
    expect(t.lines.last, hint40);
    debug.keys = false;
    await t.pump();
    expect(t.lines, ['app', '', '', '']);
    await t.press('o');
    expect(keys, ['o']);
    expect(debug.overlay, isFalse);
  });

  testTwk('Ctrl+G r on an app that repaints nothing tints all of the screen '
      'at once, not only the line the hint was over, and Ctrl+G r again '
      'takes the tint off all of it at once', (t) async {
    await t.pumpWidget(
      Column(children: [Area('u', 5, Counts()), const Line('status')]),
      size: (40, 6),
    );
    t.binding.debug.keys = true;
    final plain = backgrounds(t);
    expect(plain, hasLength(1));

    await t.type(ctrlG);
    await t.pump();
    await t.press('r');
    await t.pump();
    expect(t.binding.debug.rainbow, isTrue);
    final tinted = backgrounds(t);
    expect(tinted, hasLength(1), reason: 'one tint over all of the screen');
    expect(tinted, isNot(plain));
    expect(t.lines.last, 'status');

    await t.type(ctrlG);
    await t.pump();
    await t.press('r');
    await t.pump();
    expect(t.binding.debug.rainbow, isFalse);
    expect(backgrounds(t), plain);
  });
}
