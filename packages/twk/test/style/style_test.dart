import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/vt.dart';

const red = Color.rgb(255, 0, 0);
const green = Color.rgb(0, 255, 0);
const blue = Color.rgb(0, 0, 255);

void main() {
  group('merge', () {
    test('takes the fields the other style sets and keeps the rest', () {
      const base = Style(fg: red, bg: blue, underlineColor: green, link: 'a');
      expect(
        base.merge(const Style(fg: green, link: 'b')),
        const Style(fg: green, bg: blue, underlineColor: green, link: 'b'),
      );
      expect(
        base.merge(const Style(bg: red, underlineColor: blue)),
        const Style(fg: red, bg: red, underlineColor: blue, link: 'a'),
      );
      expect(base.merge(const Style()), base);
      expect(const Style().merge(base), base);
    });

    test('is one side itself where the other sets nothing', () {
      // instances of their own, not the canonical constants
      // ignore: prefer_const_constructors
      final base = Style(fg: red, attrs: Attr.bold, link: 'a');
      // the same: not the constant, so identical says which side it is
      // ignore: prefer_const_constructors
      final nothing = Style();
      expect(identical(base.merge(nothing), base), isTrue);
      expect(identical(nothing.merge(base), base), isTrue);
      // a style that only turns something off sets something
      const off = Style(attrsOff: Attr.bold);
      expect(identical(base.merge(off), base), isFalse);
      expect(
        base.merge(off),
        const Style(fg: red, attrsOff: Attr.bold, link: 'a'),
      );
    });

    test('takes a color with its alpha', () {
      expect(
        const Style(bg: blue, bgAlpha: 100).merge(const Style(bg: red)),
        const Style(bg: red),
      );
      expect(
        const Style(fg: red).merge(const Style(fg: blue, fgAlpha: 100)),
        const Style(fg: blue, fgAlpha: 100),
      );
      expect(
        const Style(fg: red, fgAlpha: 50).merge(const Style(bg: blue)),
        const Style(fg: red, fgAlpha: 50, bg: blue),
      );
    });

    test('takes the attributes the other style turns on or off', () {
      expect(
        const Style(
          attrs: Attr.bold | Attr.italic,
        ).merge(const Style(attrs: Attr.dim, attrsOff: Attr.bold)),
        const Style(attrs: Attr.italic | Attr.dim, attrsOff: Attr.bold),
      );
      expect(
        const Style(
          attrsOff: Attr.bold | Attr.strike,
        ).merge(const Style(attrs: Attr.bold)),
        const Style(attrs: Attr.bold, attrsOff: Attr.strike),
      );
    });

    test('replaces the kind of underline', () {
      expect(
        const Style(
          attrs: Attr.curlyUnderline | Attr.bold,
        ).merge(const Style(attrs: Attr.doubleUnderline)),
        const Style(attrs: Attr.doubleUnderline | Attr.bold),
      );
      expect(
        const Style(
          attrs: Attr.curlyUnderline | Attr.bold,
        ).merge(const Style(attrsOff: Attr.underline)),
        const Style(attrs: Attr.bold, attrsOff: Attr.underline),
      );
      expect(
        const Style(attrsOff: Attr.underline),
        const Style(attrsOff: Attr.underlineMask),
      );
    });

    test('takes an empty link, which leaves the text without one', () {
      final style = const Style(link: 'a').merge(const Style(link: ''));
      expect(style, const Style(link: ''));
      expect(style.pen.link, isNull);
    });
  });

  test(
    'a style rejects an alpha without its color, an attribute on and off',
    () {
      // built at run time, where the asserts run
      Style style({
        Color? fg,
        Color? bg,
        int fgAlpha = 255,
        int bgAlpha = 255,
        int attrs = 0,
        int attrsOff = 0,
      }) => Style(
        fg: fg,
        bg: bg,
        fgAlpha: fgAlpha,
        bgAlpha: bgAlpha,
        attrs: attrs,
        attrsOff: attrsOff,
      );
      final rejected = throwsA(isA<AssertionError>());
      expect(() => style(fgAlpha: 9), rejected);
      expect(() => style(bgAlpha: 9), rejected);
      expect(() => style(fg: red, fgAlpha: 256), rejected);
      expect(() => style(bg: red, bgAlpha: -1), rejected);
      expect(() => style(attrs: Attr.bold, attrsOff: Attr.bold), rejected);
      expect(
        () => style(attrs: Attr.doubleUnderline, attrsOff: Attr.underline),
        rejected,
      );
      expect(
        style(fg: red, fgAlpha: 0, bg: red, bgAlpha: 0, attrs: Attr.bold),
        const Style(fg: red, fgAlpha: 0, bg: red, bgAlpha: 0, attrs: Attr.bold),
      );
    },
  );

  group('a string', () {
    test('turns into a span of the style each member names', () {
      expect('x'.bold, const Span('x', Style(attrs: Attr.bold)));
      expect('x'.dim, const Span('x', Style(attrs: Attr.dim)));
      expect('x'.italic, const Span('x', Style(attrs: Attr.italic)));
      expect('x'.fg(red), const Span('x', Style(fg: red)));
      expect('x'.bg(red), const Span('x', Style(bg: red)));
      expect('x'.link('u'), const Span('x', Style(link: 'u')));
      expect('x'.underline, const Span('x', Style(attrs: Attr.underline)));
      expect(
        'x'.doubleUnderline,
        const Span('x', Style(attrs: Attr.doubleUnderline)),
      );
      expect(
        'x'.curlyUnderline,
        const Span('x', Style(attrs: Attr.curlyUnderline)),
      );
      expect(
        'x'.dottedUnderline,
        const Span('x', Style(attrs: Attr.dottedUnderline)),
      );
      expect(
        'x'.dashedUnderline,
        const Span('x', Style(attrs: Attr.dashedUnderline)),
      );
      expect('x'.reverse, const Span('x', Style(attrs: Attr.reverse)));
      expect('x'.strike, const Span('x', Style(attrs: Attr.strike)));
      expect('x'.overline, const Span('x', Style(attrs: Attr.overline)));
    });

    test('replaces the kind of underline with the one named last', () {
      expect('x'.curlyUnderline.underline, 'x'.underline);
      expect(
        'x'.underline.bold.dashedUnderline,
        const Span('x', Style(attrs: Attr.dashedUnderline | Attr.bold)),
      );
      expect(
        const Span('x', Style(attrsOff: Attr.underline)).dottedUnderline,
        'x'.dottedUnderline,
      );
    });

    test('chains them, the later member winning', () {
      expect(
        'x'.bold.italic.dim.fg(.green).bg(.blue).link('https://a'),
        const Span(
          'x',
          Style(
            fg: Color.green,
            bg: Color.blue,
            attrs: Attr.bold | Attr.italic | Attr.dim,
            link: 'https://a',
          ),
        ),
      );
      expect(
        'x'.reverse.strike.overline.curlyUnderline,
        const Span(
          'x',
          Style(
            attrs:
                Attr.reverse |
                Attr.strike |
                Attr.overline |
                Attr.curlyUnderline,
          ),
        ),
      );
      expect('x'.fg(.red).fg(.green), const Span('x', Style(fg: Color.green)));
      expect(
        const Span(
          'x',
          Style(attrsOff: Attr.bold, bgAlpha: 9, bg: red),
        ).bold.bg(blue),
        const Span('x', Style(attrs: Attr.bold, bg: blue)),
      );
    });
  });

  group('a pen', () {
    test('sets what the style sets and inherits the colors it leaves', () {
      expect(const Style().pen, const Pen());
      expect(
        const Style(
          fg: red,
          fgAlpha: 10,
          bg: blue,
          bgAlpha: 128,
          underlineColor: green,
          attrs: Attr.bold | Attr.underline,
          attrsOff: Attr.italic,
          link: 'u',
        ).pen,
        const Pen(
          fg: red,
          fgAlpha: 10,
          bg: blue,
          bgAlpha: 128,
          underlineColor: green,
          attrs: Attr.bold | Attr.underline,
          link: 'u',
        ),
      );
    });

    test('of equal styles is the same one in a table', () {
      final table = StyleTable()..pen(const Pen(bg: green));
      final other = StyleTable();
      // a new instance on each call
      Style style(int r) => Style(fg: Color.rgb(r, 0, 0));
      final id = style(255).penIn(table);
      expect(style(255).penIn(table), id);
      expect(table.penOf(id), style(255).pen);
      final otherId = style(255).penIn(other);
      expect(otherId, isNot(id));
      expect(other.penOf(otherId), style(255).pen);
    });

    test('of a style looked up before is the id the table gave it', () {
      final table = StyleTable();
      final ids = [
        for (var r = 0; r < 40; r++) Style(fg: Color.rgb(r, 0, 0)).penIn(table),
      ];
      // looked up again, in another order, as new instances
      for (var r = 39; r >= 0; r--) {
        final style = Style(fg: Color.rgb(r, 0, 0));
        expect(style.penIn(table), ids[r]);
        expect(table.pen(style.pen), ids[r]);
      }
      expect(ids.toSet(), hasLength(40));
    });
  });

  group('spans painted on a screen', () {
    late Screen screen;
    late Vt vt;
    setUp(() {
      screen = Screen(12, 1);
      vt = Vt(12, 1);
    });

    // paints [spans] from the left of a row filled with [under] (by default
    // blanks in the default colors), then shows the frame on the emulator
    void frame(
      List<Span> spans, {
      Pen under = const Pen(fg: Color.defaultColor, bg: Color.defaultColor),
    }) {
      final canvas = screen.canvas
        ..fill(0, 0, screen.width, 1, screen.styles.pen(under));
      var x = 0;
      for (final span in spans) {
        x += canvas.text(x, 0, span.text, span.style.penIn(screen.styles));
      }
      final bytes = screen.render();
      if (bytes != null) {
        vt.feed(bytes);
      }
    }

    test('show their styles', () {
      frame([
        'a'.bold,
        'b'.italic.fg(.green),
        'c'.dim.bg(const .rgb(1, 2, 3)),
        'd'.link('https://d.example'),
        const Span('e', Style(attrs: Attr.curlyUnderline, underlineColor: red)),
        const Span('f'),
      ]);
      final cells = [
        for (var x = 0; x < 6; x++)
          (
            vt.cell(x, 0).text,
            vt.cell(x, 0).fg,
            vt.cell(x, 0).bg,
            vt.cell(x, 0).attrs,
            vt.cell(x, 0).ul,
            vt.cell(x, 0).link,
          ),
      ];
      expect(cells, [
        ('a', 0, 0, Attr.bold, 0, null),
        ('b', Color.green.value, 0, Attr.italic, 0, null),
        ('c', 0, const Color.rgb(1, 2, 3).value, Attr.dim, 0, null),
        ('d', 0, 0, 0, 0, 'https://d.example'),
        ('e', 0, 0, Attr.curlyUnderline, red.value, null),
        ('f', 0, 0, 0, 0, null),
      ]);
    });

    test('show their underlines, reverse video, strike and overline', () {
      frame([
        'a'.underline,
        'b'.doubleUnderline,
        'c'.curlyUnderline,
        'd'.dottedUnderline,
        'e'.dashedUnderline,
        'f'.reverse,
        'g'.strike,
        'h'.overline,
        'i'.underline.reverse.strike.overline,
        const Span('j'),
      ]);
      expect(vt.errors, isEmpty);
      expect(
        [
          for (var x = 0; x < 10; x++)
            (vt.cell(x, 0).text, vt.cell(x, 0).attrs),
        ],
        [
          ('a', Attr.underline),
          ('b', Attr.doubleUnderline),
          ('c', Attr.curlyUnderline),
          ('d', Attr.dottedUnderline),
          ('e', Attr.dashedUnderline),
          ('f', Attr.reverse),
          ('g', Attr.strike),
          ('h', Attr.overline),
          ('i', Attr.underline | Attr.reverse | Attr.strike | Attr.overline),
          ('j', 0),
        ],
      );
    });

    test('show the colors under the ones they leave, and blend over them', () {
      const under = Pen(fg: Color.yellow, bg: Color.rgb(0, 0, 0));
      frame([
        'a'.bold,
        const Span('b', Style(bg: Color.rgb(255, 255, 255), bgAlpha: 128)),
        const Span('c', Style(fg: Color.defaultColor)),
      ], under: under);
      final cells = [
        for (var x = 0; x < 3; x++)
          (vt.cell(x, 0).text, vt.cell(x, 0).fg, vt.cell(x, 0).bg),
      ];
      const black = Color.rgb(0, 0, 0);
      expect(cells, [
        ('a', Color.yellow.value, black.value),
        ('b', Color.yellow.value, const Color.rgb(128, 128, 128).value),
        ('c', 0, black.value),
      ]);
    });

    test('replace the attributes of the cells they paint over', () {
      frame([
        const Span('a'),
        'b'.italic,
      ], under: const Pen(attrs: Attr.bold | Attr.underline));
      expect(
        [vt.cell(0, 0).attrs, vt.cell(1, 0).attrs, vt.cell(2, 0).attrs],
        [0, Attr.italic, Attr.bold | Attr.underline],
      );
    });

    test('add nothing to the style table after the first frame', () {
      List<Span> spans(int n) => [
        'a$n'.bold.fg(.green),
        const Span('b', Style(bg: Color.rgb(255, 255, 255), bgAlpha: 100)),
        'c'.italic.link('https://c.example'),
      ];
      frame(spans(0));
      final styles = screen.styles.length;
      final pens = [for (final s in spans(0)) s.style.penIn(screen.styles)];
      for (var n = 1; n < 4; n++) {
        frame(spans(n));
        expect(screen.styles.length, styles);
        expect([for (final s in spans(n)) s.style.penIn(screen.styles)], pens);
      }
      expect(vt.cell(0, 0).text + vt.cell(1, 0).text, 'a3');
    });
  });

  test('a Span with a null style has none of its own', () {
    Style? none() => null;
    expect(Span('x', none()).style, const Style());
    expect(
      Span.gradient('x', const Gradient([Color.red]), none()).style,
      const Style(),
    );
    expect(const Span('x').style, const Style());
  });
}
