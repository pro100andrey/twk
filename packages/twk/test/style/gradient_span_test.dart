// A span of a Text.rich in the colours of a gradient, grapheme by
// grapheme, in the emulator's colours: inside plain text, across a wrap,
// wide glyphs and a grapheme of several code points, the span's own style
// kept, a mix with the default colour, the 256 colours of a terminal that
// has no more; lines broken as they are without the gradient; a phase;
// spans with a gradient compared.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const black = Color.rgb(0, 0, 0);
const red = Color.rgb(255, 0, 0);
const green = Color.rgb(0, 200, 0);

const blackToRed = Gradient([black, red]);

/// Black to red over five graphemes: the red at 0, 1/4, 1/2, 3/4 and 1.
const List<Color> reds = [
  black,
  Color.rgb(64, 0, 0),
  Color.rgb(128, 0, 0),
  Color.rgb(191, 0, 0),
  red,
];

/// [child] at the top left, as small as it is.
Widget topLeft(Widget child) =>
    Align(alignment: Alignment.topLeft, child: child);

void main() {
  testTwk('a span inside plain text: each of its graphemes in its color '
      'along the gradient, the text around it in its own', (t) async {
    await t.pumpWidget(
      topLeft(
        const Text.rich([
          Span('ab', Style(fg: green)),
          Span.gradient('cdefg', blackToRed),
          Span('h'),
        ]),
      ),
      size: (10, 2),
    );
    expect(t, hasTextAt(0, 0, 'abcdefgh'));
    expect(t, styleAt(0, 0, hasFg(green)));
    expect(t, styleAt(1, 0, hasFg(green)));
    for (var i = 0; i < 5; i++) {
      expect(t, styleAt(2 + i, 0, hasFg(reds[i])), reason: '$i');
    }
    expect(t, styleAt(7, 0, hasFg(Color.defaultColor)));
  });

  testTwk('across a wrap the gradient goes on from where the line before '
      'left it, the space at the wrap a step; a line break is none', (
    t,
  ) async {
    await t.pumpWidget(
      topLeft(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 3,
              child: Text.rich([Span.gradient('ab cd', blackToRed)]),
            ),
            Text.rich([Span.gradient('ab\r\ncde', blackToRed)]),
          ],
        ),
      ),
      size: (6, 5),
    );
    expect(t.lines.take(4), ['ab', 'cd', 'ab', 'cde']);
    for (final (x, y, color) in [
      (0, 0, reds[0]),
      (1, 0, reds[1]),
      (0, 1, reds[3]),
      (1, 1, reds[4]),
      (0, 2, reds[0]),
      (1, 2, reds[1]),
      (0, 3, reds[2]),
      (2, 3, reds[4]),
    ]) {
      expect(t, styleAt(x, y, hasFg(color)), reason: '$x, $y');
    }
  });

  testTwk('the lines break where they do without the gradient', (t) async {
    const text = 'well-known e\u0301x\r\nab 漢字 cd\u200Bef';
    Widget paragraph(int width, {required bool gradient}) => topLeft(
      SizedBox(
        width: width,
        child: Text.rich([
          const Span('> '),
          if (gradient)
            const Span.gradient(text, blackToRed)
          else
            const Span(text),
          const Span(' <'),
        ]),
      ),
    );
    for (final width in [3, 4, 6, 9, 12]) {
      await t.pumpWidget(paragraph(width, gradient: false), size: (14, 9));
      final plain = t.lines;
      await t.pumpWidget(paragraph(width, gradient: true));
      expect(t.lines, plain, reason: '$width');
    }
  });

  testTwk('a wide glyph in the color of its grapheme in both its cells; a '
      'grapheme of several code points one step', (t) async {
    await t.pumpWidget(
      topLeft(const Text.rich([Span.gradient('漢ae\u0301字b', blackToRed)])),
      size: (9, 2),
    );
    expect(t, hasTextAt(0, 0, '漢ae\u0301字b'));
    for (final (x, color) in [
      (0, reds[0]),
      (1, reds[0]),
      (2, reds[1]),
      (3, reds[2]),
      (4, reds[3]),
      (5, reds[3]),
      (6, reds[4]),
    ]) {
      expect(t, styleAt(x, 0, hasFg(color)), reason: '$x');
    }
  });

  testTwk("the span's own style beside the gradient: its background and "
      'attributes, also of a member called after it', (t) async {
    await t.pumpWidget(
      topLeft(
        Text.rich(
          ['abcde'.gradient(blackToRed).bold.bg(green)],
          style: const Style(fg: green, attrs: Attr.italic),
        ),
      ),
      size: (6, 2),
    );
    for (var x = 0; x < 5; x++) {
      expect(
        t,
        styleAt(
          x,
          0,
          allOf(
            hasFg(reds[x]),
            hasBg(green),
            hasAttr(Attr.bold),
            hasAttr(Attr.italic),
          ),
        ),
        reason: '$x',
      );
    }
  });

  testTwk('a mix with the default color is the other color at its share '
      'of the mix over the background the text is on; one grapheme takes '
      'the first color, a span of none is drawn as it is', (t) async {
    const gradient = Gradient([Color.defaultColor, Color.brightWhite]);
    await t.pumpWidget(
      topLeft(
        const Text.rich([
          Span.gradient('abc', gradient),
          Span('\n'),
          Span.gradient('abc', gradient, Style(bg: black)),
          Span.gradient('\n', blackToRed),
          Span.gradient('a', blackToRed),
        ]),
      ),
      size: (4, 4),
      backgroundRgb: 0x204060,
    );
    expect(t.lines.take(3), ['abc', 'abc', 'a']);
    expect(t, styleAt(0, 0, hasFg(Color.defaultColor)));
    expect(t, styleAt(1, 0, hasFg(const Color.rgb(144, 160, 176))));
    expect(t, styleAt(2, 0, hasFg(const Color.rgb(255, 255, 255))));
    expect(t, styleAt(1, 1, hasFg(const Color.rgb(128, 128, 128))));
    expect(t, styleAt(0, 2, hasFg(black)));
  });

  testTwk('a mix towards the default color is the first color at its share '
      'of the mix over the background the text is on', (t) async {
    await t.pumpWidget(
      topLeft(
        const Text.rich([
          Span.gradient(
            'abc',
            Gradient([Color.brightWhite, Color.defaultColor]),
          ),
        ]),
      ),
      size: (4, 2),
      backgroundRgb: 0x204060,
    );
    expect(t, styleAt(0, 0, hasFg(const Color.rgb(255, 255, 255))));
    expect(t, styleAt(1, 0, hasFg(const Color.rgb(143, 159, 175))));
    expect(t, styleAt(2, 0, hasFg(Color.defaultColor)));
  });

  testTwk('a terminal of 256 colors shows the nearest of them', (t) async {
    const text = Text.rich([Span.gradient('abcde', blackToRed)]);
    await t.pumpWidget(topLeft(text), size: (6, 2));
    t.binding.twkApp.screen.styles.colorMode = ColorMode.ansi256;
    // a new size paints the whole screen again
    await t.pumpWidget(topLeft(text), size: (7, 2));
    const palette = [16, 52, 88, 124, 196];
    for (var x = 0; x < 5; x++) {
      expect(t, styleAt(x, 0, hasFg(Color.indexed(palette[x]))), reason: '$x');
    }
  });

  testTwk('a phase turns the colors round their loop, the first again after '
      'the last: 0.5 as the loop shifted half of it', (t) async {
    const loop = [Color.blue, Color.magenta, Color.red, Color.green];
    await t.pumpWidget(
      topLeft(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich([
              Span.gradient('abcdefghijk', Gradient(loop, phase: 0.5)),
            ]),
            Text.rich([
              Span.gradient(
                'abcdefghijk',
                Gradient([
                  Color.red,
                  Color.green,
                  Color.blue,
                  Color.magenta,
                  Color.red,
                ]),
              ),
            ]),
          ],
        ),
      ),
      size: (12, 3),
    );
    List<int> colors(int y) => [
      for (var x = 0; x < 11; x++) t.vt.cell(x, y).fg,
    ];
    expect(colors(0), colors(1));
    expect(colors(0).first, const Color.rgb(205, 0, 0).value);
  });

  test('a span with a gradient equals one with the same text, style and '
      'gradient', () {
    const bold = Style(attrs: Attr.bold);
    expect(
      'ab'.gradient(blackToRed).bold,
      const Span.gradient('ab', blackToRed, bold),
    );
    expect(
      'ab'.gradient(blackToRed).hashCode,
      const Span.gradient('ab', blackToRed).hashCode,
    );
    expect('ab'.gradient(blackToRed), isNot(const Span('ab')));
    expect(
      'ab'.gradient(blackToRed),
      isNot('ab'.gradient(const Gradient([black, green]))),
    );
  });
}
