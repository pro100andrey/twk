// Points of the data space mapped to dots, and the dots of each shape, in
// braille on the emulator.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'shot.dart';

/// [draw] on 2 × 1 braille cells: 4 × 4 dots, one data unit apart.
List<String> square(DotDrawer draw) => drawn(2, 1, draw).rows;

void main() {
  group('DotGrid', () {
    test('is sized in cells, and in dots by its marker', () {
      final grid = DotGrid()..reset(3, 2, Marker.quadrant, TextSegmenter());
      expect((grid.columns, grid.rows), (3, 2));
      expect((grid.width, grid.height), (6, 4));
      grid.reset(1, 4, Marker.braille, TextSegmenter());
      expect((grid.columns, grid.rows), (1, 4));
      expect((grid.width, grid.height), (2, 16));
    });
  });

  group('dotAt', () {
    // 4 × 4 dots; x from 0 to 6, y from 0 to 3
    final grid = DotGrid()..reset(2, 1, Marker.braille, TextSegmenter());
    final painter = DotPainter(grid, (0, 6), (0, 3));

    test('puts the bounds on the outermost dots, y upwards', () {
      expect(painter.dotAt(0, 0), (0, 3));
      expect(painter.dotAt(6, 3), (3, 0));
      expect(painter.dotAt(0, 3), (0, 0));
    });

    test('takes the nearest dot', () {
      expect(painter.dotAt(1, 1.4), (1, 2));
      expect(painter.dotAt(0.9, 1.6), (0, 1));
    });

    test('is null outside the bounds', () {
      expect(painter.dotAt(-0.1, 0), isNull);
      expect(painter.dotAt(6.1, 0), isNull);
      expect(painter.dotAt(0, 3.1), isNull);
      expect(painter.dotAt(double.nan, 0), isNull);
      expect(DotPainter(grid, (1, 1), (0, 3)).dotAt(1, 1), isNull);
    });
  });

  group('shapes', () {
    test('points', () {
      expect(square((c) => c.draw(const .points([(0, 3), (3, 0)]))), ['⠁⢀']);
      expect(square((c) => c.draw(const .points([(4, 0), (-1, 0)]))), ['']);
    });

    test('lines', () {
      expect(square((c) => c.draw(const .line(0, 0, 3, 3))), ['⡠⠊']);
      expect(square((c) => c.draw(const .line(3, 3, 0, 0))), ['⡠⠊']);
      expect(square((c) => c.draw(const .line(0, 1, 3, 1))), ['⠤⠤']);
      expect(square((c) => c.draw(const .line(1, 0, 1, 3))), ['⢸']);
      expect(square((c) => c.draw(const .line(2, 2, 2, 2))), [' ⠂']);
    });

    test('lines as far as they run inside the bounds', () {
      expect(square((c) => c.draw(const .line(-3, -3, 6, 6))), ['⡠⠊']);
      expect(
        square((c) => c.draw(const .line(-1000000000, 1, 1000000000, 1))),
        ['⠤⠤'],
      );
      expect(square((c) => c.draw(const .line(-3, 0, 0, 3))), ['⠁']);
      expect(square((c) => c.draw(const .line(4, 0, 9, 3))), ['']);
      expect(
        square((c) => c.draw(const .line(0, 0, double.infinity, 3))),
        [''],
      );
    });

    test('rectangles', () {
      expect(square((c) => c.draw(const .rectangle(0, 0, 3, 3))), ['⣏⣹']);
      expect(square((c) => c.draw(const .rectangle(1, 1, 1, 1))), ['⠰⠆']);
    });

    test('polylines', () {
      expect(
        square((c) => c.draw(const .polyline([(0, 0), (3, 3), (3, 0)]))),
        ['⡠⢺'],
      );
      expect(square((c) => c.draw(const .polyline([(1, 1)]))), ['⠠']);
      expect(square((c) => c.draw(const .polyline([]))), ['']);
    });

    test('circles', () {
      final shot = drawn(
        5,
        3,
        (c) => c.draw(const .circle(0, 0, 1)),
        x: (-1, 1),
        y: (-1, 1),
      );
      expect(shot.rows, ['⡠⠊⠉⠑⢄', '⡇   ⢸', '⠑⢄⣀⡠⠊']);
    });

    test('a circle less than half a dot across is the dot at its center', () {
      expect(square((c) => c.draw(const .circle(1, 1, 0.1))), ['⠠']);
      expect(square((c) => c.draw(const .circle(1, 1, 0))), ['⠠']);
    });

    test('in the color they are given', () {
      final shot = drawn(
        2,
        1,
        (c) => c.draw(const .line(0, 0, 3, 3, color: Color.red)),
      );
      expect(shot.colors(0), [
        ('⡠', Color.red, Color.defaultColor),
        ('⠊', Color.red, Color.defaultColor),
      ]);
    });
  });
}
