// Gauges filled in eighths with the label in the middle, swapped over the
// filled part; line gauges after their label to the nearest half cell;
// braille and ASCII where block elements and box drawing are two columns
// wide; and repainting nothing but the gauge.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart'
    show Shot, hasAttr, hasBg, hasFg, styleAt, testTwk;

import '../layout/view.dart';
import 'shot.dart';

const red = Color.rgb(255, 0, 0);
const grey = Color.rgb(1, 2, 3);
const Color none = Color.defaultColor;

/// [gauge] shown on [width] × [height] cells.
Shot show(
  RenderObject gauge,
  int width, {
  int height = 1,
  int ambiguousWidth = 1,
}) {
  final shot = Shot.render(
    gauge,
    width,
    height,
    ambiguousWidth: ambiguousWidth,
  );
  expect(shot.vt.errors, isEmpty);
  expect(shot.anyWide, isFalse);
  return shot;
}

void main() {
  test('either gauge shows nothing beside its fill without a label or the '
      'percentage, and takes a label or the percentage, not both', () {
    expect(show(RenderGauge(ratio: 0.5), 6).rows, ['███']);
    expect(show(RenderLineGauge(ratio: 0.5), 4).rows, ['────']);
    expect(
      () => Gauge(ratio: 0.5, label: 'a', percentage: true),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => LineGauge(ratio: 0.5, label: 'a', percentage: true),
      throwsA(isA<AssertionError>()),
    );
  });

  group('Gauge', () {
    test('fills the ratio of its width, the percentage in the middle', () {
      final shot = show(RenderGauge(ratio: 0.5, percentage: true), 10);
      expect(shot.rows, ['███50%']);
      // swapped over the filled part
      expect(shot.attrs(0), [
        0,
        0,
        0,
        Attr.reverse,
        Attr.reverse,
        0,
        0,
        0,
        0,
        0,
      ]);
    });

    test('fills to the nearest eighth of a cell', () {
      String bar(double ratio) =>
          show(RenderGauge(ratio: ratio), 10).rows.single;
      expect(bar(0.55), '█████▌');
      expect(bar(0.0125), '▏');
      expect(bar(0.99), '█████████▉');
      expect(bar(0.006), '');
    });

    test('fills in braille halves where eighth blocks are two columns', () {
      final shot = show(
        RenderGauge(ratio: 0.55),
        10,
        ambiguousWidth: 2,
      );
      expect(shot.rows, ['⣿⣿⣿⣿⣿⡇']);
    });

    test('fills every row, the label on the middle one', () {
      final shot = show(RenderGauge(ratio: 0.25, label: 'cpu'), 8, height: 3);
      expect(shot.rows, ['██', '██cpu', '██']);
      expect(shot.attrs(1).every((a) => a == 0), isTrue);
    });

    test('takes a ratio beyond 0 and 1 as the nearest', () {
      expect(show(RenderGauge(ratio: 1.5, percentage: true), 6).rows, [
        '█100%█',
      ]);
      expect(show(RenderGauge(ratio: -1, percentage: true), 6).rows, ['  0%']);
      expect(show(RenderGauge(ratio: double.nan, percentage: true), 6).rows, [
        '  0%',
      ]);
    });

    test('writes the percentage cut, as a ProgressList does: 100% only '
        'once it is full', () {
      expect(show(RenderGauge(ratio: 0.996, percentage: true), 6).rows, [
        '█99%██',
      ]);
      expect(show(RenderGauge(ratio: 0.29, percentage: true), 6).rows, [
        '█29%',
      ]);
    });

    test('cuts the label off at its edges', () {
      expect(show(RenderGauge(ratio: 0, label: 'abcdef'), 3).rows, ['abc']);
    });

    test('in its style, the label in the label style', () {
      final shot = show(
        RenderGauge(
          ratio: 0.5,
          label: 'ab',
          style: const Style(fg: red, bg: grey),
          labelStyle: const Style(attrs: Attr.bold),
        ),
        4,
      );
      expect(shot.colors(0), [
        ('█', red, grey),
        ('a', red, grey),
        ('b', red, grey),
        (' ', none, grey),
      ]);
      expect(shot.attrs(0), [0, Attr.bold | Attr.reverse, Attr.bold, 0]);
    });

    test('repaints when a property changes', () {
      final gauge = RenderGauge(ratio: 0.5);
      final shot = show(gauge, 4);
      expect(shot.rows, ['██']);
      gauge.ratio = 0.75;
      shot.frame();
      expect(shot.rows, ['███']);
      gauge.label = 'x';
      shot.frame();
      expect(shot.rows, ['█x█']);
      gauge.labelStyle = const Style(attrs: Attr.bold);
      shot.frame();
      expect(shot.attrs(0)[1], Attr.bold | Attr.reverse);
      gauge.style = const Style(bg: grey);
      shot.frame();
      expect(shot.colors(0)[3], (' ', none, grey));
    });

    test('is as wide as it may be and a row tall', () {
      final gauge = RenderGauge(ratio: 0)
        ..layout(const BoxConstraints(0, 5, 0, BoxConstraints.unbounded));
      expect((gauge.width, gauge.height), (5, 1));
      gauge.layout(const BoxConstraints(2, BoxConstraints.unbounded, 3, 4));
      expect((gauge.width, gauge.height), (2, 3));
    });

    test('a new ratio repaints the gauge alone', () {
      final count = PaintCount();
      Widget tree(double ratio) => Column(
        children: [
          Counted(count),
          Gauge(ratio: ratio),
        ],
      );
      final v = View(4, 2)..pump(tree(0.25));
      expect(v.rows(), ['', '█']);
      v.pump(tree(1));
      expect(v.rows(), ['', '████']);
      expect(count.paints, 1);
    });

    test('rebuilt, configures the same render object', () {
      final v = View(4, 1)..pump(const Gauge(ratio: 0.5));
      final gauge = v.top;
      v.pump(
        const Gauge(
          ratio: 0.25,
          label: 'ab',
          labelStyle: Style(attrs: Attr.bold),
        ),
      );
      expect(v.top, same(gauge));
      expect(v.rows(), ['█ab']);
      gauge as RenderGauge;
      expect((gauge.ratio, gauge.label), (0.25, 'ab'));
      expect(gauge.labelStyle, const Style(attrs: Attr.bold));
    });

    testTwk("in the theme's text where its styles set none, over what is "
        'under it', (
      t,
    ) async {
      const theme = ThemeData.light;
      await t.pumpWidget(
        const Theme(
          data: theme,
          child: Gauge(ratio: 0.5, label: 'ab'),
        ),
        size: (6, 1),
      );
      expect(t.lines, ['██ab']);
      final text = theme.text.fg!;
      // over what is under it: nothing painted here, the terminal's own
      const background = Color.defaultColor;
      expect(t, styleAt(0, 0, allOf(hasFg(text), hasBg(background))));
      // swapped over the filled part, not over the rest
      expect(t, styleAt(2, 0, allOf(hasFg(text), hasBg(background))));
      expect(t, styleAt(5, 0, hasBg(background)));
    });

    testTwk('in the DefaultTextStyle where its styles set none, over the '
        "theme's", (t) async {
      const theme = ThemeData.light;
      await t.pumpWidget(
        const Theme(
          data: theme,
          child: DefaultTextStyle(
            style: Style(fg: red, attrs: Attr.bold),
            child: Row(
              children: [
                Expanded(child: Gauge(ratio: 0.5, label: 'ab')),
                Expanded(
                  child: Gauge(
                    ratio: 0.5,
                    label: 'ab',
                    style: Style(fg: grey, attrsOff: Attr.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
        size: (12, 1),
      );
      expect(t.lines, ['██ab  ██ab']);
      // over what is under it: nothing painted here, the terminal's own
      const background = Color.defaultColor;
      expect(t, styleAt(0, 0, allOf(hasFg(red), hasBg(background))));
      expect(t, styleAt(4, 0, hasAttr(Attr.bold)));
      // its own style over the default text style
      expect(t, styleAt(6, 0, allOf(hasFg(grey), hasBg(background))));
      expect(t, styleAt(10, 0, isNot(hasAttr(Attr.bold))));
    });
  });

  group('LineGauge', () {
    /// A line gauge of [ratio] on [width] cells.
    String line(
      double ratio,
      int width, {
      String? label,
      bool percentage = false,
      BorderType type = BorderType.single,
      int ambiguousWidth = 1,
    }) => show(
      RenderLineGauge(
        ratio: ratio,
        label: label,
        percentage: percentage,
        type: type,
      ),
      width,
      ambiguousWidth: ambiguousWidth,
    ).rows.single;

    test('draws the line after the percentage and a blank', () {
      final shot = show(
        RenderLineGauge(
          ratio: 0.5,
          percentage: true,
          filledStyle: const Style(fg: red),
          unfilledStyle: const Style(fg: grey),
        ),
        14,
      );
      expect(shot.rows, ['50% ──────────']);
      expect(
        [for (final c in shot.colors(0)) c.$2],
        [
          for (var x = 0; x < 4; x++) none,
          for (var x = 0; x < 5; x++) red,
          for (var x = 0; x < 5; x++) grey,
        ],
      );
    });

    test('writes the percentage cut: 100% only once it is full', () {
      expect(line(0.996, 8, percentage: true), '99% ━━━━'.replaceAll('━', '─'));
      expect(line(1, 8, percentage: true), '100% ───');
    });

    test('fills to the nearest half cell where the type has one', () {
      expect(line(0.45, 14, percentage: true), '45% ────╴─────');
      expect(
        line(0.45, 14, percentage: true, type: BorderType.heavy),
        '45% ━━━━╸━━━━━',
      );
      expect(
        line(0.05, 14, percentage: true, type: BorderType.rounded),
        '5% ╴──────────',
      );
    });

    test('fills whole cells where it has none', () {
      final shot = show(
        RenderLineGauge(
          ratio: 0.45,
          percentage: true,
          type: BorderType.double,
          filledStyle: const Style(fg: red),
        ),
        14,
      );
      expect(shot.rows, ['45% ══════════']);
      expect(shot.colors(0)[8].$2, red);
      expect(shot.colors(0)[9].$2, none);
    });

    test('draws ASCII where box drawing is two columns wide', () {
      expect(
        line(0.45, 14, percentage: true, ambiguousWidth: 2),
        '45% ----------',
      );
    });

    test('without a label, from the left edge', () {
      expect(line(0.5, 4), '────');
      expect(line(0.5, 4, label: ''), '────');
      expect(line(0.5, 6, label: 'ab'), 'ab ─╴─');
    });

    test('cuts the label off at the right edge', () {
      expect(line(0.5, 3, percentage: true), '50%');
      expect(line(0.5, 4, percentage: true), '50%');
      expect(line(0.5, 2, label: 'abc'), 'ab');
    });

    test('on the middle row', () {
      final shot = show(RenderLineGauge(ratio: 1), 2, height: 3);
      expect(shot.rows, ['', '──', '']);
    });

    test('repaints when a property changes', () {
      final gauge = RenderLineGauge(ratio: 0.5);
      final shot = show(gauge, 4);
      gauge.type = BorderType.heavy;
      shot.frame();
      expect(shot.rows, ['━━━━']);
      gauge.filledStyle = const Style(fg: red);
      shot.frame();
      expect(shot.colors(0)[1].$2, red);
      gauge.unfilledStyle = const Style(fg: grey);
      shot.frame();
      expect(shot.colors(0)[2].$2, grey);
    });

    test('rebuilt, configures the same render object', () {
      final v = View(6, 1)..pump(const LineGauge(ratio: 0.5));
      final gauge = v.top;
      v.pump(
        const LineGauge(
          ratio: 1,
          label: 'a',
          type: BorderType.heavy,
          filledStyle: Style(fg: red),
          unfilledStyle: Style(fg: grey),
        ),
      );
      expect(v.top, same(gauge));
      expect(v.rows(), ['a ━━━━']);
      gauge as RenderLineGauge;
      expect((gauge.ratio, gauge.label), (1, 'a'));
      expect(gauge.type, BorderType.heavy);
      expect(gauge.filledStyle, const Style(fg: red));
      expect(gauge.unfilledStyle, const Style(fg: grey));
    });

    testTwk("in the theme's text where its styles set none, over what is "
        'under it', (
      t,
    ) async {
      const theme = ThemeData.light;
      await t.pumpWidget(
        const Theme(
          data: theme,
          child: LineGauge(
            ratio: 0.5,
            percentage: true,
            filledStyle: Style(fg: red),
          ),
        ),
        size: (8, 1),
      );
      expect(t.lines, ['50% ────']);
      final text = theme.text.fg!;
      // over what is under it: nothing painted here, the terminal's own
      const background = Color.defaultColor;
      expect(t, styleAt(0, 0, allOf(hasFg(text), hasBg(background))));
      expect(t, styleAt(3, 0, hasBg(background)));
      expect(t, styleAt(4, 0, allOf(hasFg(red), hasBg(background))));
      expect(t, styleAt(7, 0, allOf(hasFg(text), hasBg(background))));
    });

    testTwk('in the DefaultTextStyle where its styles set none, over the '
        "theme's: a new one repaints it", (t) async {
      const theme = ThemeData.light;
      Widget tree(Style style) => Theme(
        data: theme,
        child: DefaultTextStyle(
          style: style,
          child: const LineGauge(
            ratio: 0.5,
            percentage: true,
            filledStyle: Style(fg: red),
          ),
        ),
      );
      await t.pumpWidget(tree(const Style(bg: grey)), size: (8, 1));
      expect(t.lines, ['50% ────']);
      final text = theme.text.fg!;
      expect(t, styleAt(0, 0, allOf(hasFg(text), hasBg(grey))));
      expect(t, styleAt(4, 0, allOf(hasFg(red), hasBg(grey))));
      expect(t, styleAt(7, 0, allOf(hasFg(text), hasBg(grey))));
      await t.pumpWidget(tree(const Style(fg: grey)));
      // over what is under it: nothing painted here, the terminal's own
      const background = Color.defaultColor;
      expect(t, styleAt(0, 0, allOf(hasFg(grey), hasBg(background))));
      expect(t, styleAt(4, 0, allOf(hasFg(red), hasBg(background))));
      expect(t, styleAt(7, 0, allOf(hasFg(grey), hasBg(background))));
    });
  });

  test('either gauge asks for the row it takes where nothing sets its '
      'height, so that a Column of them is as tall as they are', () {
    for (final gauge in [
      RenderGauge(ratio: 0.5),
      RenderLineGauge(ratio: 0.5),
    ]) {
      expect(gauge.getMinIntrinsicHeight(10), 1);
      expect(gauge.getMaxIntrinsicHeight(10), 1);
      gauge.layout(const BoxConstraints(0, 10, 0, 5));
      expect(gauge.height, 1);
    }
  });

  testTwk('segmented: a column a cell, the filled ones in filledStyle, the '
      'rest in unfilledStyle, after its label', (t) async {
    await t.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 14,
          child: LineGauge(
            ratio: 0.75,
            label: 'cpu',
            segmented: true,
            filledStyle: Style(fg: Color.green),
            unfilledStyle: Style(fg: Color.white),
          ),
        ),
      ),
      size: (14, 1),
    );
    expect(t.lines, ['cpu ▍▍▍▍▍▍▍▍▍▍']);
    // ten columns, 0.75 of them rounded: eight filled
    expect(t, styleAt(4, 0, hasFg(Color.green)));
    expect(t, styleAt(11, 0, hasFg(Color.green)));
    expect(t, styleAt(12, 0, hasFg(Color.white)));
  });
}
