// Drop shadows: the cells right of and below the child blended in the
// emulator's colours, or mixed at an exact opacity as the design mixes,
// the child's and those outside the shadow as they were; default text
// faint; an offset left and up; the mouse going
// through; what repaints on its own under it shaded again; a two-column
// glyph its edge cuts left whole; a dialog's and a window's.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// White text on orange, and both blended half and half with black.
const hot = Style(fg: Color.rgb(255, 255, 255), bg: Color.rgb(200, 100, 0));
const shadedFg = Color.rgb(127, 127, 127);
const shadedBg = Color.rgb(100, 50, 0);

/// Green on blue, and both blended half and half with black.
const green = Color.rgb(0, 200, 0);
const blue = Color.rgb(0, 0, 200);
const dimGreen = Color.rgb(0, 100, 0);
const dimBlue = Color.rgb(0, 0, 100);

Matcher get shaded => allOf(hasFg(shadedFg), hasBg(shadedBg));
Matcher get unshaded => allOf(hasFg(hot.fg!), hasBg(hot.bg!));

/// [text] in [hot] over the whole screen, wrapped, and [over] on it at
/// [left], [top].
Widget scene(Widget over, {String text = '.', int left = 2, int top = 1}) =>
    Stack(
      fit: StackFit.expand,
      children: [
        Box(
          style: hot,
          child: Text(text * 200, wrap: TextWrap.grapheme),
        ),
        Positioned(left: left, top: top, child: over),
      ],
    );

/// A box of [width] by [height] on blue.
Widget block({int width = 4, int height = 2}) => Box(
  style: const Style(bg: blue),
  child: SizedBox(width: width, height: height),
);

void main() {
  test('shadows of the same offset, color and strength are equal and hash '
      'alike', () {
    const a = BoxShadow(dx: 1, dy: 2, color: blue, opacity: 0.5);
    const b = BoxShadow(dx: 1, dy: 2, color: blue, opacity: 0.5);
    expect(BoxShadow(dx: a.dx, dy: a.dy, color: blue, opacity: 0.5), a);
    expect(
      BoxShadow(dx: b.dx, dy: b.dy, color: blue, opacity: 0.5).hashCode,
      a.hashCode,
    );
    expect(a, isNot(const BoxShadow(dx: 1, dy: 2, color: blue)));
  });

  testTwk('a shadow blends the cells beside and below its child, moved by '
      'its offset, glyphs kept; the child is in its place, and the cells '
      'outside the shadow and in its corners are as they were', (t) async {
    await t.pumpWidget(
      Theme.terminal(child: scene(Shadow(child: block()))),
      size: (12, 5),
    );
    final shadow = t.renderObject(find.byType(Shadow));
    expect((shadow.width, shadow.height), (6, 3));
    // the child at 2, 1, 4 × 2: the shadow from 4, 2
    for (final x in [6, 7]) {
      expect(t, styleAt(x, 2, shaded), reason: 'right of the child $x');
    }
    for (var x = 4; x < 8; x++) {
      expect(t, styleAt(x, 3, shaded), reason: 'below the child $x');
    }
    expect(t, hasTextAt(4, 3, '....'));
    for (final (x, y) in [(6, 1), (7, 1), (2, 3), (3, 3), (8, 2), (8, 3)]) {
      expect(t, styleAt(x, y, unshaded), reason: 'outside $x,$y');
    }
    for (var x = 2; x < 6; x++) {
      expect(t, styleAt(x, 1, hasBg(blue)), reason: 'the child $x');
    }
  });

  testTwk('its colour and alpha are those it blends with; text in the '
      'default colour is faint while the terminal has not told it', (
    t,
  ) async {
    await t.pumpWidget(
      Theme.terminal(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Text('.' * 60, wrap: TextWrap.grapheme),
            Positioned(
              left: 0,
              top: 0,
              child: Shadow(
                shadow: const BoxShadow(
                  dx: 1,
                  dy: 0,
                  color: Color.rgb(255, 0, 0),
                  alpha: 0x40,
                ),
                child: block(width: 2, height: 1),
              ),
            ),
          ],
        ),
      ),
      size: (6, 2),
      backgroundRgb: 0x204060,
    );
    expect(
      t,
      styleAt(
        2,
        0,
        allOf(
          hasAttr(Attr.dim),
          hasFg(Color.defaultColor),
          hasBg(const Color.rgb(88, 48, 72)),
        ),
      ),
    );
    expect(t, styleAt(3, 0, hasBg(Color.defaultColor)));
    expect(t, styleAt(2, 1, hasBg(Color.defaultColor)));
  });

  testTwk('an opacity takes the text, background and underline colours '
      'that far to its colour, each rounded once, as the design mixes them; '
      'not a whole number of 255ths', (t) async {
    const grey = Color.rgb(101, 101, 101);
    const ul = Color.rgb(200, 100, 51);
    await t.pumpWidget(
      Theme.terminal(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Box(
              style: const Style(fg: grey, bg: grey),
              child: Text(
                '.' * 60,
                wrap: TextWrap.grapheme,
                style: const Style(attrs: Attr.underline, underlineColor: ul),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: Shadow(
                shadow: const BoxShadow(dx: 1, dy: 0, opacity: 0.55),
                child: block(width: 2, height: 1),
              ),
            ),
          ],
        ),
      ),
      size: (6, 2),
    );
    // 101 at 55 % to black is 45.45; at 140 of 255 it would be 45.55
    const dark = Color.rgb(45, 45, 45);
    expect(t, styleAt(2, 0, allOf(hasFg(dark), hasBg(dark))));
    expect(t.cell(2, 0).ul, const Color.rgb(90, 45, 23).value);
    expect(t, styleAt(3, 0, hasBg(grey)));
    expect(t.cell(3, 0).ul, ul.value);
    expect(const BoxShadow(opacity: 0.55).strength, 0.55);
    expect(const BoxShadow(alpha: 51).strength, 0.2);
    expect(
      const BoxShadow(opacity: 0.55),
      isNot(const BoxShadow(opacity: 0.5)),
    );
  });

  testTwk('an offset left and up casts the shadow there, the child in from '
      'it', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: scene(
          Shadow(shadow: const BoxShadow(dx: -1, dy: -1), child: block()),
        ),
      ),
      size: (12, 5),
    );
    // the child at 3, 2: the shadow from 2, 1
    expect(t, styleAt(3, 2, hasBg(blue)));
    expect(t, styleAt(2, 2, hasBg(shadedBg)));
    for (var x = 2; x < 6; x++) {
      expect(t, styleAt(x, 1, shaded), reason: 'above $x');
    }
    expect(t, styleAt(6, 1, unshaded));
    expect(t, styleAt(2, 3, unshaded));
  });

  testTwk('the mouse goes through the shadow to what is under it', (t) async {
    var under = 0;
    var child = 0;
    await t.pumpWidget(
      Theme.terminal(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              behavior: HitTestBehavior.opaque,
              onDown: (_) => under++,
              child: const SizedBox.expand(),
            ),
            Positioned(
              left: 2,
              top: 1,
              child: Shadow(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onDown: (_) => child++,
                  child: block(),
                ),
              ),
            ),
          ],
        ),
      ),
      size: (12, 5),
    );
    await t.click(6, 1);
    await t.click(5, 3);
    await t.pump();
    expect((under, child), (2, 0));
    await t.click(5, 2);
    await t.pump();
    expect((under, child), (2, 1));
  });

  testTwk('what repaints on its own under the shadow is blended again', (
    t,
  ) async {
    final bars = GlobalKey<BarsState>();
    await t.pumpWidget(
      Theme.terminal(
        child: Stack(
          children: [
            Positioned(left: 4, top: 3, child: Bars(key: bars)),
            Positioned(left: 2, top: 1, child: Shadow(child: block())),
          ],
        ),
      ),
      size: (12, 5),
    );
    expect(t, hasTextAt(4, 3, '█ '));
    expect(t, styleAt(4, 3, allOf(hasFg(dimGreen), hasBg(dimBlue))));
    bars.currentState!.grow();
    await t.pump();
    expect(t, hasTextAt(4, 3, '██ '));
    expect(t, styleAt(4, 3, allOf(hasFg(dimGreen), hasBg(dimBlue))));
    expect(t, styleAt(5, 3, allOf(hasFg(dimGreen), hasBg(dimBlue))));
    expect(t, styleAt(6, 3, hasBg(dimBlue)));
  });

  testTwk('a two-column glyph the edge of the shadow cuts through is left as '
      'it is', (t) async {
    // the glyphs from column 1: from 1, 3, 5 and 7
    await t.pumpWidget(
      Theme.terminal(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 1),
              child: Box(
                style: hot,
                child: Text('漢' * 30, wrap: TextWrap.grapheme),
              ),
            ),
            Positioned(left: 2, top: 1, child: Shadow(child: block())),
          ],
        ),
      ),
      size: (11, 5),
    );
    // beside the child, columns 6 and 7: a blank where the child cut a
    // glyph, and the first half of one
    expect(t, hasTextAt(6, 2, ' 漢'));
    expect(t, styleAt(6, 2, hasBg(shadedBg)));
    expect(t, styleAt(7, 2, unshaded));
    // below it, columns 4 to 7: the glyph at 5 whole
    expect(t, hasTextAt(3, 3, '漢漢漢'));
    expect(t, styleAt(3, 3, unshaded));
    expect(t, styleAt(5, 3, shaded));
    expect(t, styleAt(7, 3, unshaded));
  });

  testTwk('a dialog with a shadow casts it over the barrier', (t) async {
    final key = GlobalKey();
    await t.pumpWidget(
      Theme.terminal(
        child: Overlay(
          child: scene(SizedBox(key: key), left: 0, top: 0),
        ),
      ),
      size: (20, 7),
    );
    unawaited(
      showDialog<void>(
        key.currentContext!,
        (_) => const Dialog(
          look: PanelLook.bordered,
          shadow: BoxShadow(),
          child: Text('hello'),
        ),
        fadeIn: Duration.zero,
      ),
    );
    await t.pump();
    final top = t.lines.indexWhere((line) => line.contains('┌'));
    final left = t.lines[top].indexOf('┌');
    expect(t.lines[top + 1].substring(left), startsWith('│ hello │'));
    // the barrier's blend, and the shadow's over it: white at half to
    // black is 127.5, 128, and the shadow's 128 of 255 over that 63.75
    const deep = Style(fg: Color.rgb(64, 64, 64), bg: Color.rgb(50, 25, 0));
    final shadowed = allOf(hasFg(deep.fg!), hasBg(deep.bg!));
    expect(t, styleAt(left + 9, top + 1, shadowed));
    expect(t, styleAt(left + 10, top + 2, shadowed));
    expect(t, styleAt(left + 2, top + 3, shadowed));
    // the barrier alone: the theme's black at half
    final barred = allOf(
      hasFg(const Color.rgb(128, 128, 128)),
      hasBg(shadedBg),
    );
    expect(t, styleAt(left + 9, top, barred));
    expect(t, styleAt(left + 1, top + 3, barred));
  });

  testTwk('a window with a shadow casts it beside its cells, where it asks '
      'to be, under the windows in front of it; the mouse goes through it', (
    t,
  ) async {
    var pressed = 0;
    final alpha = WindowController(left: 2, top: 1, width: 12, height: 3);
    final beta = WindowController(top: 5, width: 12, height: 3);
    addTearDown(alpha.dispose);
    addTearDown(beta.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: WindowLayer(
          windows: [
            Window(
              title: 'A',
              controller: alpha,
              shadow: const BoxShadow(),
              child: const Text('alpha'),
            ),
            Window(title: 'B', controller: beta, child: const Text('beta')),
          ],
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onDown: (_) => pressed++,
            child: scene(const SizedBox.shrink()),
          ),
        ),
      ),
      size: (20, 8),
    );
    expect(t.lines.sublist(1, 4), [
      '..┌ A ── _ □ ┐......',
      '..│alpha     │......',
      '..└──────────┘......',
    ]);
    expect(t, styleAt(14, 1, unshaded));
    expect(t, styleAt(14, 2, shaded));
    expect(t, styleAt(15, 3, shaded));
    expect(t, styleAt(4, 4, shaded));
    expect(t, styleAt(15, 4, shaded));
    expect(t, styleAt(3, 4, unshaded));
    expect(t, styleAt(16, 2, unshaded));
    // beta, in front, over the shadow's last row
    beta.moveTo(8, 4);
    await t.pump();
    expect(t, hasTextAt(8, 4, '┌ B'));
    expect(t, styleAt(9, 4, isNot(hasBg(shadedBg))));
    expect(t, styleAt(7, 4, shaded));
    await t.click(14, 2);
    await t.pump();
    expect(pressed, 1);
    expect(rect(alpha), (2, 1, 12, 3));
  });
}

/// Where [c] asks its window to be.
(int, int, int, int) rect(WindowController c) =>
    (c.left, c.top, c.width, c.height);

/// A sparkline of full bars, a repaint boundary: [BarsState.grow] adds one.
final class Bars extends StatefulWidget {
  const Bars({super.key});

  @override
  State<Bars> createState() => BarsState();
}

final class BarsState extends State<Bars> {
  var _data = const [8.0];

  void grow() => setState(() => _data = [..._data, 8]);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 6,
    child: Sparkline(
      data: _data,
      max: 8,
      style: const Style(fg: green, bg: blue),
    ),
  );
}
