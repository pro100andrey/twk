// Colors per cell and per layer, labels and the background on the
// emulator; the widget laid out and rebuilt in a tree.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart'
    show Shot, hasBg, hasFg, styleAt, testTwk;

import '../layout/view.dart';
import 'shot.dart';

const red = Color.rgb(255, 0, 0);
const green = Color.rgb(0, 255, 0);
const blue = Color.rgb(0, 0, 255);
const grey = Color.rgb(1, 2, 3);
const Color none = Color.defaultColor;

var draws = 0;

/// The outline of the bounds, 0 to 7 on both axes; counts its calls in
/// [draws].
void outline(DotContext c) {
  draws++;
  c.draw(const .rectangle(0, 0, 7, 7));
}

void main() {
  group('colors', () {
    test('a cell takes the color of the last dot set in it', () {
      final shot = drawn(1, 1, (c) {
        c
          ..draw(const .points([(0, 3)], color: red))
          ..draw(const .points([(1, 0)], color: green));
      });
      expect(shot.colors(0), [('⢁', green, none)]);
    });

    test('a later layer covers the cells it sets a dot in', () {
      // the last layer ended or not
      for (final end in [false, true]) {
        final shot = drawn(2, 1, (c) {
          c
            ..draw(const .points([(0, 3), (2, 3)], color: red))
            ..layer()
            ..draw(const .points([(1, 0)], color: green));
          if (end) {
            c.layer();
          }
        });
        expect(shot.colors(0), [('⢀', green, none), ('⠁', red, none)]);
      }
    });

    test('half blocks show a color in each half', () {
      final shot = drawn(
        4,
        1,
        (c) => c
          ..draw(const .points([(0, 1), (1, 1), (1, 0)], color: red))
          ..draw(const .points([(0, 0)], color: blue))
          ..draw(const .points([(2, 0)], color: green))
          ..draw(const .points([(3, 1)], color: green)),
        marker: Marker.halfBlock,
        background: grey,
      );
      expect(shot.colors(0), [
        ('▀', red, blue),
        ('█', red, grey),
        ('▄', green, grey),
        ('▀', green, grey),
      ]);
    });

    test('a later layer covers each half on its own', () {
      // the last layer ended or not
      for (final end in [false, true]) {
        final shot = drawn(1, 1, (c) {
          c
            ..draw(const .points([(0, 1)], color: red))
            ..draw(const .points([(0, 0)], color: blue))
            ..layer()
            ..draw(const .points([(0, 1)], color: green));
          if (end) {
            c.layer();
          }
        }, marker: Marker.halfBlock);
        expect(shot.colors(0), [('▀', green, blue)]);
      }
    });

    test('every cell has the background', () {
      final shot = drawn(
        2,
        1,
        (c) => c.draw(const .points([(0, 3)], color: red)),
        background: grey,
      );
      expect(shot.colors(0), [('⠁', red, grey), (' ', none, grey)]);
    });
  });

  group('labels', () {
    // a line along the bottom of 4 braille cells, x from 0 to 7
    void bottom(DotContext c) => c.draw(const .line(0, 0, 7, 0));

    test('start in the cell their point falls in', () {
      final shot = drawn(4, 1, (c) {
        bottom(c);
        c.label(2, 3, 'hi');
      });
      expect(shot.rows, ['⣀hi⣀']);
    });

    test('go over every layer', () {
      final shot = drawn(4, 1, (c) {
        c
          ..label(2, 3, 'hi')
          ..layer();
        bottom(c);
      });
      expect(shot.rows, ['⣀hi⣀']);
    });

    test('are left out outside the bounds', () {
      final shot = drawn(4, 1, (c) {
        bottom(c);
        c
          ..label(8, 0, 'x')
          ..label(0, -1, 'y');
      });
      expect(shot.rows, ['⣀⣀⣀⣀']);
    });

    test('in their style, over the background', () {
      final shot = drawn(
        2,
        1,
        (c) => c.label(0, 0, 'a', const Style(fg: red)),
        background: grey,
      );
      expect(shot.colors(0), [('a', red, grey), (' ', none, grey)]);
    });
  });

  group('RenderDotCanvas', () {
    test('is a repaint boundary that paints every cell', () {
      final shot = drawn(
        3,
        2,
        (c) => c.draw(const .points([(0, 7)])),
        under: 'x',
      );
      expect(shot.top.isRepaintBoundary, isTrue);
      expect(shot.rows, ['⠁', '']);
    });

    test('draws again when a property changes, into the same cells', () {
      final canvas = RenderDotCanvas(
        draw: (c) => c.draw(const .line(0, 0, 3, 3)),
        xBounds: (0, 3),
        yBounds: (0, 3),
      );
      final shot = Shot.render(canvas, 2, 1);
      expect(shot.rows, ['⡠⠊']);
      canvas.marker = Marker.halfBlock;
      shot.frame();
      expect(shot.rows, ['▄▀']);
      canvas.xBounds = (0, 7);
      shot.frame();
      expect(shot.rows, ['█']);
      canvas.yBounds = (0, 6);
      shot.frame();
      expect(shot.rows, ['▄']);
      canvas.draw = (c) => c.draw(const .line(0, 0, 7, 0));
      shot.frame();
      expect(shot.rows, ['▄▄']);
      canvas.background = grey;
      shot.frame();
      expect(shot.colors(0), [('▄', none, grey), ('▄', none, grey)]);
    });
  });

  group('DotCanvas', () {
    test('fills the room it gets', () {
      final v = View(4, 2)
        ..pump(
          const DotCanvas(draw: outline, xBounds: (0, 7), yBounds: (0, 7)),
        );
      expect(v.rows(), ['⡏⠉⠉⢹', '⣇⣀⣀⣸']);
    });

    test('rebuilt, configures the same render object', () {
      final v = View(4, 2)
        ..pump(
          const DotCanvas(draw: outline, xBounds: (0, 7), yBounds: (0, 7)),
        );
      final canvas = v.top;
      v.pump(
        const DotCanvas(
          draw: outline,
          xBounds: (0, 7),
          yBounds: (0, 7),
          marker: Marker.quadrant,
        ),
      );
      expect(v.top, same(canvas));
      expect(v.rows(), ['▛▀▀▜', '▙▄▄▟']);
      v.pump(
        const DotCanvas(
          draw: outline,
          xBounds: (0, 7),
          yBounds: (0, 3),
          marker: Marker.quadrant,
          background: grey,
        ),
      );
      canvas as RenderDotCanvas;
      expect(canvas.draw, same(outline));
      expect((canvas.xBounds, canvas.yBounds), ((0, 7), (0, 3)));
      expect(canvas.marker, Marker.quadrant);
      expect(canvas.background, grey);
      expect(canvas.labelColor, isNot(grey));
    });

    test('draws again only when something changed', () {
      const widget = DotCanvas(draw: outline, xBounds: (0, 7), yBounds: (0, 7));
      final v = View(4, 2)..pump(widget);
      draws = 0;
      // a new widget, with bounds equal to those it had
      final bounds = (v.top as RenderDotCanvas).xBounds;
      v
        ..pump(widget)
        ..pump(DotCanvas(draw: outline, xBounds: bounds, yBounds: bounds));
      expect(draws, 0);
      v.pump(
        DotCanvas(
          draw: (c) {
            draws++;
            c.draw(const .rectangle(0, 0, 7, 7));
          },
          xBounds: bounds,
          yBounds: bounds,
        ),
      );
      expect(draws, 1);
    });

    test('takes the room a flex gives it', () {
      final v = View(6, 1)
        ..pump(
          const Row(
            children: [
              Label('a'),
              Expanded(
                child: DotCanvas(
                  draw: outline,
                  xBounds: (0, 7),
                  yBounds: (0, 7),
                ),
              ),
              Label('b'),
            ],
          ),
        );
      expect(v.rows(), ['a⣏⣉⣉⣹b']);
    });

    test('takes the least room along an axis without bounds', () {
      final canvas = RenderDotCanvas(
        draw: outline,
        xBounds: (0, 7),
        yBounds: (0, 7),
      )..layout(const BoxConstraints(2, BoxConstraints.unbounded, 0, 5));
      expect((canvas.width, canvas.height), (2, 5));
      canvas.layout(const BoxConstraints(0, 3, 1, BoxConstraints.unbounded));
      expect((canvas.width, canvas.height), (3, 1));
    });

    testTwk("on the theme's background, its labels in the theme's text "
        'where their style sets none', (t) async {
      const theme = ThemeData.light;
      Widget tree({Color? background}) => Theme(
        data: theme,
        child: DotCanvas(
          draw: (c) => c
            ..draw(const .points([(0, 0)], color: red))
            ..label(0, 1, 'ab')
            ..label(3, 1, 'c', const Style(fg: green)),
          xBounds: (0, 3),
          yBounds: (0, 1),
          marker: Marker.block,
          background: background,
        ),
      );
      await t.pumpWidget(tree(), size: (4, 2));
      expect(t.lines, ['ab c', '█']);
      final background = theme.background.bg!;
      expect(t, styleAt(0, 0, allOf(hasFg(theme.text.fg!), hasBg(background))));
      expect(t, styleAt(3, 0, allOf(hasFg(green), hasBg(background))));
      expect(t, styleAt(0, 1, allOf(hasFg(red), hasBg(background))));
      expect(t, styleAt(3, 1, hasBg(background)));
      await t.pumpWidget(tree(background: grey));
      expect(t, styleAt(3, 1, hasBg(grey)));
    });
  });
}
