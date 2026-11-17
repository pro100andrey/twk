import 'package:test/test.dart';
import 'package:twk/twk.dart' show Marker;
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

  group('BlockImage.fromPixels in sextants', () {
    BlockCell cell(List<List<int?>> rows) => BlockImage.fromPixels(
      _bitmap(rows),
      mode: BlockMode.sextant,
    ).cells.single;

    test('splits six pixels in two colours, as the Marker draws them', () {
      // Pixels 0 and 1 (the top row) red: the sextant of the pattern 3.
      expect(
        cell([
          [_red, _red],
          [_blue, _blue],
          [_blue, _blue],
        ]),
        BlockCell(
          String.fromCharCode(Marker.sextant.glyphOf(3)),
          fg: _red,
          bg: _blue,
        ),
      );
      // The left column: the left half block, encoded apart.
      expect(
        cell([
          [_red, _blue],
          [_red, _blue],
          [_red, _blue],
        ]),
        const BlockCell('▌', fg: _red, bg: _blue),
      );
      // One pixel apart, the second of the middle row (pattern 8).
      expect(
        cell([
          [_blue, _blue],
          [_blue, _red],
          [_blue, _blue],
        ]),
        BlockCell(
          String.fromCharCode(Marker.sextant.glyphOf(0x3F ^ 8)),
          fg: _blue,
          bg: _red,
        ),
      );
    });

    test('is 2 × 3 pixels a cell and draws only those not transparent', () {
      final blocks = BlockImage.fromPixels(
        _bitmap([
          [_red, _red, _red],
          [_red, _red, _red],
          [_red, _red, _red],
          [_red, _red, _red],
        ]),
        mode: BlockMode.sextant,
      );
      expect((blocks.columns, blocks.rows), (2, 2));
      expect(
        cell([
          [null, null],
          [null, null],
          [null, _white],
        ]),
        BlockCell(
          String.fromCharCode(Marker.sextant.glyphOf(32)),
          fg: _white,
        ),
      );
    });
  });

  group('BlockImage.fromPixels in octants', () {
    BlockCell cell(List<List<int?>> rows) => BlockImage.fromPixels(
      _bitmap(rows),
      mode: BlockMode.octant,
    ).cells.single;

    test('splits eight pixels in the best two colours', () {
      // The right column red: pattern 0xAA, the right half block.
      expect(
        cell([
          [_blue, _red],
          [_blue, _red],
          [_blue, _red],
          [_blue, _red],
        ]),
        const BlockCell('▌', fg: _blue, bg: _red),
      );
      // Only the third row's left pixel: an octant of the block U+1CD00.
      // the split has the first pixel in the ink: all but that one
      final want = String.fromCharCode(Marker.octant.glyphOf(255 ^ 16));
      expect(want.runes.single, greaterThan(0xFFFF));
      expect(
        cell([
          [_blue, _blue],
          [_blue, _blue],
          [_red, _blue],
          [_blue, _blue],
        ]),
        BlockCell(want, fg: _blue, bg: _red),
      );
    });

    test('a uniform cell is one colour, a half missing is one ink', () {
      expect(
        cell([
          [_green, _green],
          [_green, _green],
          [_green, _green],
          [_green, _green],
        ]),
        const BlockCell('▀', fg: _green, bg: _green),
      );
      expect(
        cell([
          [_green, _green],
          [_green, _green],
          [null, null],
          [null, null],
        ]),
        const BlockCell('▀', fg: _green),
      );
    });
  });

  group('BlockImage.fromPixels in braille', () {
    BlockCell cell(List<List<int?>> rows) => BlockImage.fromPixels(
      _bitmap(rows),
      mode: BlockMode.braille,
    ).cells.single;

    test('a dot for each pixel as bright as the threshold, in their mean', () {
      expect(
        cell([
          [_white, 0x000000],
          [0x000000, _white],
          [0x000000, 0x000000],
          [0x000000, 0x000000],
        ]),
        BlockCell(
          String.fromCharCode(Marker.braille.glyphOf(1 | 8)),
          fg: _white,
        ),
      );
      expect(
        String.fromCharCode(Marker.braille.glyphOf(1 | 8)),
        '\u2811',
      );
      // red (luma 76) is dark, green (149) bright, so one dot, in green
      expect(
        cell([
          [_red, _green],
          [null, null],
          [null, null],
          [null, null],
        ]),
        BlockCell(
          String.fromCharCode(Marker.braille.glyphOf(2)),
          fg: _green,
        ),
      );
    });

    test('no dot is nothing drawn, so the cell under it shows', () {
      expect(
        cell([
          [0x101010, 0x202020],
          [null, null],
          [_blue, _red],
          [0x000000, 0x000000],
        ]),
        BlockCell.empty,
      );
    });

    test('is 2 × 4 pixels a cell', () {
      final blocks = BlockImage.fromPixels(
        Bitmap(5, 9)..setPixel(4, 8, 0xFFFFFFFF),
        mode: BlockMode.braille,
      );
      expect((blocks.columns, blocks.rows), (3, 3));
      expect(blocks.cellAt(2, 2).glyph, String.fromCharCode(0x2801));
    });
  });

  group('BlockImage.fromPixels in ascii', () {
    test('a character as dense as the pixel is bright, in its colour', () {
      final blocks = BlockImage.fromPixels(
        _bitmap([
          [0x000000, 0x808080, _white, null],
        ]),
        mode: BlockMode.ascii,
      );
      expect(blocks.cells, const [
        BlockCell(' ', fg: 0x000000),
        BlockCell('+', fg: 0x808080),
        BlockCell('@', fg: _white),
        BlockCell.empty,
      ]);
    });
  });

  group('BlockImage in every mode', () {
    test('fits the box, a cell holding as many pixels as the mode says', () {
      final photo = Bitmap(60, 40);
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 60; x++) {
          photo.setPixel(x, y, 0xFF000000 | (x * 4) << 16 | (y * 6) << 8);
        }
      }
      for (final mode in BlockMode.values) {
        final blocks = BlockImage(
          photo,
          columns: 10,
          rows: 5,
          cell: const CellSize(1, 2),
          mode: mode,
        );
        expect(blocks.columns, lessThanOrEqualTo(10), reason: '$mode');
        expect(blocks.rows, lessThanOrEqualTo(5), reason: '$mode');
        expect(blocks.cells.length, blocks.columns * blocks.rows);
      }
      // 10 × 5 cells of 1 × 2 are 10 × 10 units: 60 × 40 fits 10 × 6.67,
      // so 10 across, 7 down (rounded) of the 5 rows are capped.
      final octants = BlockImage(
        photo,
        columns: 10,
        rows: 5,
        cell: const CellSize(1, 2),
        mode: BlockMode.octant,
      );
      expect(octants.rows, lessThanOrEqualTo(5));
    });

    test('a small image per mode, as the ANSI text it prints', () {
      final photo = _bitmap([
        [_red, _red, _blue, _blue],
        [_red, _white, _blue, _green],
        [_green, _green, _white, _blue],
        [_white, _green, _red, _red],
      ]);
      final out = {
        for (final mode in BlockMode.values)
          mode: BlockImage.fromPixels(photo, mode: mode).toAnsi().join('|'),
      };
      // the glyphs of the ascii ramp by the luma of each pixel
      expect(
        BlockImage.fromPixels(
          photo,
          mode: BlockMode.ascii,
        ).cells.map((c) => c.glyph).join(),
        '::..:@.+++@.@+::',
      );
      // every mode draws the whole image in cells of its own size
      for (final mode in BlockMode.values) {
        final blocks = BlockImage.fromPixels(photo, mode: mode);
        expect(blocks.columns, (4 / mode.across).ceil(), reason: '$mode');
        expect(blocks.rows, (4 / mode.down).ceil(), reason: '$mode');
      }
      expect(out[BlockMode.quadrant], contains('▛'));
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
