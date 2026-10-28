import 'package:test/test.dart';
import 'package:twk_rich/image.dart';

void main() {
  group('CellFit', () {
    test('contains an image in the box, its aspect kept', () {
      final fit = CellFit(400, 300, columns: 20, rows: 5);
      // The box is 200 × 100 pixels: 133 × 100.
      expect((fit.width, fit.height), (133, 100));
      expect((fit.columns, fit.rows), (14, 5));
      expect((fit.cropWidth, fit.cropHeight), (400, 300));
    });

    test('covers the box, cut to it from the middle', () {
      final fit = CellFit(
        400,
        300,
        columns: 20,
        rows: 5,
        fit: ImageFit.cover,
      );
      expect((fit.width, fit.height), (200, 100));
      expect((fit.columns, fit.rows), (20, 5));
      expect(
        (fit.cropX, fit.cropY, fit.cropWidth, fit.cropHeight),
        (0, 50, 400, 200),
      );
    });

    test('fills the box, stretched', () {
      final fit = CellFit(
        400,
        300,
        columns: 3,
        rows: 4,
        fit: ImageFit.fill,
      );
      expect((fit.width, fit.height, fit.columns, fit.rows), (30, 80, 3, 4));
    });

    test('scales down, never up', () {
      final small = CellFit(
        25,
        30,
        columns: 20,
        rows: 5,
        fit: ImageFit.scaleDown,
      );
      expect(
        (small.width, small.height, small.columns, small.rows),
        (
          25,
          30,
          3,
          2,
        ),
      );
      final large = CellFit(
        400,
        300,
        columns: 20,
        rows: 5,
        fit: ImageFit.scaleDown,
      );
      expect((large.width, large.height), (133, 100));
    });

    test('takes the box down to whole bands', () {
      final fit = CellFit(
        100,
        100,
        columns: 10,
        rows: 1,
        cell: const CellSize(8, 17),
        fit: ImageFit.fill,
        bandHeight: 6,
      );
      expect((fit.width, fit.height), (80, 12));
    });

    test('falls back to 10 × 20 pixels where none are reported', () {
      expect(CellSize.reported(0, 0), CellSize.fallback);
      expect(CellSize.reported(8, 16), const CellSize(8, 16));
    });
  });

  test('cells of one size are equal, hash alike and say their size', () {
    const cell = CellSize(8, 16);
    expect(CellSize.reported(8, 16).hashCode, cell.hashCode);
    expect(cell, isNot(const CellSize(16, 8)));
    expect('$cell', 'CellSize(8 × 16)');
  });

  test('fits of one image in one box are equal, hash alike and say where '
      'the image goes', () {
    final fit = CellFit(400, 300, columns: 20, rows: 5, fit: ImageFit.cover);
    final same = CellFit(400, 300, columns: 20, rows: 5, fit: ImageFit.cover);
    expect(same, fit);
    expect(same.hashCode, fit.hashCode);
    expect(CellFit(400, 300, columns: 20, rows: 5), isNot(fit));
    expect(
      '$fit',
      'CellFit(20 × 5 cells, 200 × 100 pixels of 400 × 200 at 0, 50)',
    );
  });

  group('resize', () {
    test('keeps a flat colour flat', () {
      final image = Bitmap(30, 20);
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 30; x++) {
          image.setPixel(x, y, 0xFF2080C0);
        }
      }
      for (final (w, h) in [(7, 3), (30, 20), (61, 45), (1, 1)]) {
        final scaled = resize(image, w, h);
        expect((scaled.width, scaled.height), (w, h));
        expect(scaled.pixel(w ~/ 2, h ~/ 2), 0xFF2080C0);
        expect(scaled.pixel(w - 1, h - 1), 0xFF2080C0);
      }
    });

    test('takes the mean of the pixels under one', () {
      final image = Bitmap(2, 2)
        ..setPixel(0, 0, 0xFF000000)
        ..setPixel(1, 0, 0xFFFFFFFF)
        ..setPixel(0, 1, 0xFFFFFFFF)
        ..setPixel(1, 1, 0xFF000000);
      expect(resize(image, 1, 1).pixel(0, 0), 0xFF808080);
    });

    test('does not bleed the colour of transparent pixels', () {
      final image = Bitmap(2, 1)
        ..setPixel(0, 0, 0x00FF0000)
        ..setPixel(1, 0, 0xFF0000FF);
      expect(resize(image, 1, 1).pixel(0, 0), 0x800000FF);
    });

    test('copies a part of the size asked', () {
      final image = Bitmap(4, 4);
      for (var i = 0; i < 16; i++) {
        image.setPixel(i % 4, i ~/ 4, 0xFF000000 | i);
      }
      final part = resize(
        image,
        2,
        2,
        cropX: 1,
        cropY: 2,
        cropWidth: 2,
        cropHeight: 2,
      );
      expect([part.pixel(0, 0), part.pixel(1, 1)], [0xFF000009, 0xFF00000E]);
    });

    test('scales a gradient up and down smoothly', () {
      final image = Bitmap(16, 1);
      for (var x = 0; x < 16; x++) {
        image.setPixel(x, 0, 0xFF000000 | x * 17 << 16);
      }
      for (final width in [5, 40]) {
        final scaled = resize(image, width, 3);
        var last = -1;
        for (var x = 0; x < width; x++) {
          final red = scaled.pixel(x, 1) >> 16 & 0xFF;
          expect(red, greaterThanOrEqualTo(last));
          last = red;
        }
      }
    });

    test('scales to a CellFit', () {
      final image = Bitmap(400, 300);
      final fit = CellFit(
        400,
        300,
        columns: 20,
        rows: 5,
        fit: ImageFit.cover,
      );
      final scaled = fit.scale(image);
      expect((scaled.width, scaled.height), (200, 100));
    });
  });
}
