import 'package:test/test.dart';
import 'package:twk_rich/image.dart';

const _red = 0xFF0000;
const _blue = 0x0000FF;
const _green = 0x00FF00;
const _white = 0xFFFFFF;

/// A bitmap of the colours of [rows], `0xRRGGBB` opaque or null for a
/// transparent pixel.
Bitmap _bitmap(List<List<int?>> rows) {
  final image = Bitmap(rows.first.length, rows.length);
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      final c = rows[y][x];
      image.setPixel(x, y, c == null ? 0 : 0xFF000000 | c);
    }
  }
  return image;
}

void main() {
  group('BlockImage.fromPixels in half blocks', () {
    test('draws two pixels a cell, ▀ in the upper on the lower', () {
      final blocks = BlockImage.fromPixels(
        _bitmap([
          [_red, _blue, null, null],
          [_green, _blue, _white, null],
        ]),
      );
      expect((blocks.columns, blocks.rows), (4, 1));
      expect(blocks.cells, const [
        BlockCell('▀', fg: _red, bg: _green),
        BlockCell('▀', fg: _blue, bg: _blue),
        BlockCell('▄', fg: _white),
        BlockCell.empty,
      ]);
    });

    test('leaves the lower half of the last row undrawn', () {
      final blocks = BlockImage.fromPixels(
        _bitmap([
          [_red],
          [_green],
          [_blue],
        ]),
      );
      expect((blocks.columns, blocks.rows), (1, 2));
      expect(blocks.cellAt(0, 1), const BlockCell('▀', fg: _blue));
    });

    test('blends every pixel over a background where one is given', () {
      final image = Bitmap(1, 2)
        ..setPixel(0, 0, 0x80FF0000)
        ..setPixel(0, 1, 0x00000000);
      final blocks = BlockImage.fromPixels(image, background: 0x000000);
      expect(blocks.cellAt(0, 0), const BlockCell('▀', fg: 0x800000, bg: 0));
    });
  });

  group('BlockImage.fromPixels in quadrants', () {
    BlockCell cell(List<List<int?>> rows) => BlockImage.fromPixels(
      _bitmap(rows),
      mode: BlockMode.quadrant,
    ).cells.single;

    test('splits four pixels in the two colours they are of', () {
      expect(
        cell([
          [_red, _blue],
          [_blue, _blue],
        ]),
        const BlockCell('▘', fg: _red, bg: _blue),
      );
      expect(
        cell([
          [_red, _blue],
          [_red, _blue],
        ]),
        const BlockCell('▌', fg: _red, bg: _blue),
      );
      expect(
        cell([
          [_red, _blue],
          [_blue, _red],
        ]),
        const BlockCell('▚', fg: _red, bg: _blue),
      );
      expect(
        cell([
          [_red, _red],
          [_red, _blue],
        ]),
        const BlockCell('▛', fg: _red, bg: _blue),
      );
      expect(
        cell([
          [_green, _green],
          [_green, _green],
        ]),
        const BlockCell('▀', fg: _green, bg: _green),
      );
    });

    test('keeps the closest colours together where they are more', () {
      // Two reds and two blues: the reds' mean on the blues'.
      expect(
        cell([
          [0xF00000, 0x0000F0],
          [0xE00000, 0x0000E0],
        ]),
        const BlockCell('▌', fg: 0xE80000, bg: 0x0000E8),
      );
    });

    test('draws only the pixels that are not transparent', () {
      expect(
        cell([
          [_red, null],
          [_blue, null],
        ]),
        const BlockCell('▌', fg: 0x800080),
      );
      expect(
        cell([
          [null, null],
          [null, _white],
        ]),
        const BlockCell('▗', fg: _white),
      );
      expect(
        cell([
          [null, null],
          [null, null],
        ]),
        BlockCell.empty,
      );
    });
  });

  test('cells of one glyph and colours are equal, hash alike and say what '
      'they show', () {
    const cell = BlockCell('▀', fg: _red, bg: _blue);
    expect(const BlockCell('▀', fg: _red, bg: _blue).hashCode, cell.hashCode);
    expect(cell, isNot(const BlockCell('▀', fg: _red)));
    expect('$cell', 'BlockCell(▀ #ff0000 on #0000ff)');
    expect('${const BlockCell('▄', fg: _green)}', 'BlockCell(▄ #00ff00 on -)');
  });

  group('BlockImage', () {
    test('fits an image to the box of cells', () {
      // 40 × 20 pixels in 8 × 8 cells of 10 × 20: 80 × 40 pixels, contained
      // in 8 × 2 cells; half blocks of 8 × 4 pixels.
      final image = Bitmap(40, 20);
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 40; x++) {
          image.setPixel(x, y, y < 10 ? 0xFFFF0000 : 0xFF0000FF);
        }
      }
      final half = BlockImage(image, columns: 8, rows: 8);
      expect((half.columns, half.rows), (8, 2));
      expect(half.cellAt(3, 0), const BlockCell('▀', fg: _red, bg: _red));
      expect(half.cellAt(3, 1), const BlockCell('▀', fg: _blue, bg: _blue));
      final quadrant = BlockImage(
        image,
        columns: 8,
        rows: 8,
        mode: BlockMode.quadrant,
      );
      expect((quadrant.columns, quadrant.rows), (8, 2));
    });

    test('writes its rows as text with SGR colours', () {
      final blocks = BlockImage.fromPixels(
        _bitmap([
          [_red, _red, null],
          [_blue, _blue, _white],
        ]),
      );
      const row =
          '\x1b[38;2;255;0;0m\x1b[48;2;0;0;255m▀▀'
          '\x1b[38;2;255;255;255m\x1b[49m▄\x1b[0m';
      expect(blocks.toAnsi(), [row]);
      expect(
        BlockImage.fromPixels(
          _bitmap([
            [null],
          ]),
        ).toAnsi(),
        [' '],
      );
    });
  });
}
