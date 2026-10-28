// Gradients in the emulator's colours: a background along the columns and
// along the rows, at stops, of palette and default colours, without a
// child; text along a line and down the rows, a two-column glyph in the
// color of its first column, also where it repaints on its own; a new
// gradient; the 256 colours of a terminal that has no more; a phase that
// turns the colours round their loop, palette ones without a jump.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const black = Color.rgb(0, 0, 0);
const red = Color.rgb(255, 0, 0);
const green = Color.rgb(0, 200, 0);
const blue = Color.rgb(0, 0, 255);

/// Black to red over five cells: the red at 0, 1/4, 1/2, 3/4 and 1.
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
  testTwk('a background along the columns: the first cell in the first '
      'color, the last in the last, those between mixed; the text of the '
      'child over it in its own color', (t) async {
    await t.pumpWidget(
      topLeft(
        const GradientBackground(
          gradient: Gradient([black, red]),
          child: SizedBox(
            width: 5,
            height: 2,
            child: Text('ab', style: Style(fg: green)),
          ),
        ),
      ),
      size: (8, 3),
    );
    for (var x = 0; x < 5; x++) {
      for (var y = 0; y < 2; y++) {
        expect(t, styleAt(x, y, hasBg(reds[x])), reason: '$x, $y');
      }
    }
    expect(t, hasTextAt(0, 0, 'ab'));
    expect(t, styleAt(1, 0, hasFg(green)));
    expect(t, styleAt(5, 0, hasBg(Color.defaultColor)));
    expect(t, styleAt(0, 2, hasBg(Color.defaultColor)));
  });

  testTwk('along the rows, its colors at its stops: the first before the '
      'first stop; a box over it with no background of its own on it', (
    t,
  ) async {
    await t.pumpWidget(
      topLeft(
        const GradientBackground(
          gradient: Gradient(
            [blue, red, green],
            stops: [0.25, 0.5, 1],
            direction: Axis.vertical,
          ),
          child: SizedBox(
            width: 4,
            height: 5,
            child: Box(border: Border.all()),
          ),
        ),
      ),
      size: (6, 6),
    );
    final rows = [blue, blue, red, const Color.rgb(127, 100, 0), green];
    for (var y = 0; y < 5; y++) {
      for (final x in [0, 1, 3]) {
        expect(t, styleAt(x, y, hasBg(rows[y])), reason: '$x, $y');
      }
    }
    expect(t, hasTextAt(0, 0, '┌──┐'));
  });

  testTwk('a palette color mixes as the core takes it, the default color as '
      "the terminal's background; one color fills it all", (t) async {
    await t.pumpWidget(
      topLeft(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GradientBackground(
              gradient: Gradient([Color.defaultColor, Color.brightWhite]),
              child: SizedBox(width: 3, height: 1),
            ),
            GradientBackground(
              gradient: Gradient([green]),
              child: SizedBox(width: 3, height: 1),
            ),
          ],
        ),
      ),
      size: (4, 3),
      backgroundRgb: 0x204060,
    );
    expect(t, styleAt(0, 0, hasBg(Color.defaultColor)));
    expect(t, styleAt(1, 0, hasBg(const Color.rgb(144, 160, 176))));
    // the palette's bright white as the RGB it is mixed as, xterm's
    expect(t, styleAt(2, 0, hasBg(const Color.rgb(255, 255, 255))));
    for (var x = 0; x < 3; x++) {
      expect(t, styleAt(x, 1, hasBg(green)), reason: '$x');
    }
  });

  testTwk('without a child a background is as big as the constraints '
      'allow', (t) async {
    await t.pumpWidget(
      topLeft(
        const ConstrainedBox(
          constraints: BoxConstraints(0, 5, 0, 1),
          child: GradientBackground(gradient: Gradient([black, red])),
        ),
      ),
      size: (6, 2),
    );
    for (var x = 0; x < 5; x++) {
      expect(t, styleAt(x, 0, hasBg(reds[x])), reason: '$x');
    }
    expect(t, styleAt(5, 0, hasBg(Color.defaultColor)));
  });

  testTwk('text along a line: each glyph in the color of its column, a '
      'two-column glyph in that of its first; its background and attributes '
      'kept', (t) async {
    const style = Style(fg: green, bg: Color.rgb(9, 9, 9), attrs: Attr.bold);
    await t.pumpWidget(
      topLeft(
        const GradientForeground(
          gradient: Gradient([red, blue]),
          child: Text('a漢bc', style: style),
        ),
      ),
      size: (6, 2),
    );
    expect(t, hasTextAt(0, 0, 'a漢bc'));
    final colors = {
      0: red,
      1: const Color.rgb(191, 0, 64),
      3: const Color.rgb(64, 0, 191),
      4: blue,
    };
    for (final MapEntry(key: x, value: color) in colors.entries) {
      expect(
        t,
        styleAt(
          x,
          0,
          allOf(hasFg(color), hasBg(style.bg!), hasAttr(Attr.bold)),
        ),
        reason: '$x',
      );
    }
  });

  testTwk('text down the rows: each line in the color of its row', (t) async {
    await t.pumpWidget(
      topLeft(
        const GradientForeground(
          gradient: Gradient([red, blue], direction: Axis.vertical),
          child: Text('ab\ncd'),
        ),
      ),
      size: (4, 3),
    );
    for (final (x, y, color) in [
      (0, 0, red),
      (1, 0, red),
      (0, 1, blue),
      (1, 1, blue),
    ]) {
      expect(t, styleAt(x, y, hasFg(color)), reason: '$x, $y');
    }
  });

  testTwk('text that repaints on its own in the child takes the gradient '
      'again', (t) async {
    final bars = GlobalKey<BarsState>();
    await t.pumpWidget(
      topLeft(
        GradientForeground(
          gradient: const Gradient([black, red]),
          child: Bars(key: bars),
        ),
      ),
      size: (6, 2),
    );
    expect(t, hasTextAt(0, 0, '█'));
    expect(t, styleAt(0, 0, hasFg(black)));
    bars.currentState!.grow();
    await t.pump();
    expect(t, hasTextAt(0, 0, '██'));
    expect(t, styleAt(1, 0, hasFg(reds[1])));
  });

  testTwk('a new gradient repaints', (t) async {
    Widget fill(Gradient gradient) => topLeft(
      GradientBackground(
        gradient: gradient,
        child: const SizedBox(width: 5, height: 1),
      ),
    );
    await t.pumpWidget(fill(const Gradient([black, red])), size: (6, 2));
    expect(t, styleAt(4, 0, hasBg(red)));
    await t.pumpWidget(fill(const Gradient([black, blue])));
    expect(t, styleAt(4, 0, hasBg(blue)));
    expect(t, styleAt(0, 0, hasBg(black)));
  });

  testTwk('a new gradient repaints the text in its colors', (t) async {
    Widget text(Gradient gradient) => topLeft(
      GradientForeground(gradient: gradient, child: const Text('abcde')),
    );
    await t.pumpWidget(text(const Gradient([black, red])), size: (6, 2));
    expect(t, styleAt(4, 0, hasFg(red)));
    await t.pumpWidget(text(const Gradient([black, blue])));
    expect(t, styleAt(4, 0, hasFg(blue)));
    expect(t, styleAt(0, 0, hasFg(black)));
  });

  testTwk('a terminal of 256 colors shows the nearest of them', (t) async {
    await t.pumpWidget(
      topLeft(
        const GradientBackground(
          gradient: Gradient([black, red]),
          child: SizedBox(width: 5, height: 1),
        ),
      ),
      size: (6, 2),
    );
    t.binding.twkApp.screen.styles.colorMode = ColorMode.ansi256;
    // a new size paints the whole screen again
    await t.pumpWidget(
      topLeft(
        const GradientBackground(
          gradient: Gradient([black, red]),
          child: SizedBox(width: 5, height: 1),
        ),
      ),
      size: (7, 2),
    );
    const palette = [16, 52, 88, 124, 196];
    for (var x = 0; x < 5; x++) {
      expect(t, styleAt(x, 0, hasBg(Color.indexed(palette[x]))), reason: '$x');
    }
  });

  group('a phase', () {
    /// The backgrounds of the first [n] cells of row [y], as the emulator
    /// packs a color.
    List<int> backgrounds(TwkTester t, int y, [int n = 11]) => [
      for (var x = 0; x < n; x++) t.vt.cell(x, y).bg,
    ];

    /// [gradients], one a row, each 11 cells across.
    Widget rows(List<Gradient> gradients) => topLeft(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final g in gradients)
            GradientBackground(
              gradient: g,
              child: const SizedBox(width: 11, height: 1),
            ),
        ],
      ),
    );

    const loop = [Color.blue, Color.magenta, Color.red, Color.green];

    testTwk('0.5: the colors round their loop, the first again after the '
        'last, shifted half of it; palette colors mixed between as at '
        'stops', (t) async {
      await t.pumpWidget(
        rows(const [
          Gradient(loop, phase: 0.5),
          Gradient([
            Color.red,
            Color.green,
            Color.blue,
            Color.magenta,
            Color.red,
          ]),
          Gradient(loop, phase: 1.5),
          Gradient(loop, phase: -0.5),
        ]),
        size: (12, 5),
      );
      final shifted = backgrounds(t, 1);
      expect(backgrounds(t, 0), shifted);
      // red as the RGB it is mixed as, xterm's
      expect(shifted.first, const Color.rgb(205, 0, 0).value);
      expect(shifted[1] & 0x1000000, isNonZero, reason: 'a mix, in RGB');
      expect(backgrounds(t, 2), shifted, reason: 'a whole turn more');
      expect(backgrounds(t, 3), shifted, reason: 'turned back');
    });

    testTwk('0: the loop as it is; 0.25: turned a quarter towards the last '
        'cell; its stops shifted with it, from the last round to the first', (
      t,
    ) async {
      await t.pumpWidget(
        rows(const [
          Gradient(loop, phase: 0),
          Gradient([...loop, Color.blue]),
          Gradient(loop, phase: 0.25),
          Gradient([
            Color.green,
            Color.blue,
            Color.magenta,
            Color.red,
            Color.green,
          ]),
          Gradient([black, red], stops: [0, 0.5], phase: 0.5),
          Gradient([red, black, red]),
        ]),
        size: (12, 7),
      );
      expect(backgrounds(t, 0), backgrounds(t, 1));
      expect(backgrounds(t, 2), backgrounds(t, 3));
      expect(backgrounds(t, 4), backgrounds(t, 5));
    });

    testTwk('growing, it turns palette colors with no jump: frame by '
        'frame each cell a little nearer the next color', (t) async {
      final styles = StyleTable();
      int rgb(int color) => (color & 0x2000000) != 0
          ? styles.paletteRgb(color & 0xFF)
          : color & 0xFFFFFF;
      Widget at(double phase) => rows([
        Gradient(const [Color.blue, Color.red], phase: phase),
      ]);
      await t.pumpWidget(at(0), size: (12, 2));
      var last = backgrounds(t, 0);
      for (var k = 1; k <= 100; k++) {
        await t.pumpWidget(at(k / 100));
        final now = backgrounds(t, 0);
        for (var x = 0; x < now.length; x++) {
          for (final shift in [16, 8, 0]) {
            final step =
                ((rgb(now[x]) >> shift & 0xFF) - (rgb(last[x]) >> shift & 0xFF))
                    .abs();
            expect(step, lessThanOrEqualTo(8), reason: 'cell $x at $k/100');
          }
        }
        last = now;
      }
    });

    testTwk('flowing, never shows a palette color as the terminal draws '
        'it beside the RGB its mixes take it for: a cell on a stop is that '
        'RGB too, so that none flickers as it lands on one', (t) async {
      for (var k = 0; k < 40; k++) {
        await t.pumpWidget(
          rows([
            Gradient(const [Color.blue, Color.magenta], phase: k / 40),
          ]),
          size: (12, 2),
        );
        for (final (x, color) in backgrounds(t, 0).indexed) {
          expect(color & 0x2000000, 0, reason: 'cell $x at $k/40');
        }
      }
    });

    test('is part of what makes gradients equal', () {
      expect(
        const Gradient([black, red], phase: 0.5),
        const Gradient([black, red], phase: 0.5),
      );
      expect(
        const Gradient([black, red], phase: 0.5).hashCode,
        const Gradient([black, red], phase: 0.5).hashCode,
      );
      expect(
        const Gradient([black, red], phase: 0.5),
        isNot(const Gradient([black, red], phase: 0.25)),
      );
      expect(
        const Gradient([black, red], phase: 0),
        isNot(const Gradient([black, red])),
      );
    });
  });

  group('palette colors as the terminal shows them (OSC 4)', () {
    // a themed terminal's blue and magenta, told by OSC 4 after the app
    // started; xterm's would mix to (103, 0, 221)
    Future<void> tellPalette(TwkTester t) => t.input(
      '\x1b]4;4;rgb:89/b4/fa\x1b\\\x1b]4;5;rgb:cb/a6/f7\x1b\\'.codeUnits,
    );
    const blueToMagenta = Gradient([Color.blue, Color.magenta]);
    const themedMix = Color.rgb(170, 173, 248);

    testTwk("a background between two palette colors mixes the terminal's "
        'own', (t) async {
      await t.pumpWidget(const SizedBox(), size: (5, 2));
      await tellPalette(t);
      await t.pumpWidget(
        topLeft(
          const GradientBackground(
            gradient: blueToMagenta,
            child: SizedBox(width: 3, height: 1),
          ),
        ),
      );
      expect(t, styleAt(1, 0, hasBg(themedMix)));
    });

    testTwk('a span of text between two palette colors mixes the '
        "terminal's own", (t) async {
      await t.pumpWidget(const SizedBox(), size: (5, 2));
      await tellPalette(t);
      await t.pumpWidget(
        topLeft(const Text.rich([Span.gradient('abc', blueToMagenta)])),
      );
      expect(t, hasTextAt(0, 0, 'abc'));
      expect(t, styleAt(1, 0, hasFg(themedMix)));
    });
  });
}

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
    width: 5,
    child: Sparkline(
      data: _data,
      max: 8,
      style: const Style(fg: green),
    ),
  );
}
