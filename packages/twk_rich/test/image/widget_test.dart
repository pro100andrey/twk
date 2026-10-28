// The Image widget in an app run by the tester: its size in cells, the
// image placed with each protocol as the emulator records it, the block
// fallback, fit and alignment, what it keeps between frames, and its
// sources.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/image.dart';
import 'package:twk_test/twk_test.dart';

import 'fixtures.dart';

const red = 0xFFFF0000;
const blue = 0xFF0000FF;

/// [width] × [height] pixels, [top] in the rows above [split] and [bottom]
/// in the rest, [left] in the columns left of [splitX] where given.
Bitmap picture(
  int width,
  int height, {
  int top = red,
  int bottom = red,
  int split = 0,
  int? left,
  int splitX = 0,
}) {
  final b = Bitmap(width, height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      b.setPixel(
        x,
        y,
        left != null && x < splitX ? left : (y < split ? top : bottom),
      );
    }
  }
  return b;
}

/// [image] at the top left of the screen, as big as it likes.
Widget topLeft(Widget image) =>
    Align(alignment: Alignment.topLeft, child: image);

/// The size the image was laid out at.
(int, int) sizeOf(TwkTester t) {
  final r = t.renderObject<RenderImage>(find.byType(Image));
  return (r.width, r.height);
}

List<String> shown(TwkTester t) => [for (final i in t.vt.images) '$i'];

/// What the frames written so far sent: kitty's image files, decoded from
/// the transmissions (`a=T`, in chunks `m=1` up to the last).
List<Uint8List> kittyFiles(TwkTester t) {
  final s = latin1.decode([for (final f in t.terminal.frames) ...f]);
  final files = <Uint8List>[];
  StringBuffer? data;
  for (final m in RegExp(
    r'\x1b_G([^;\x1b]*)(?:;([^\x1b]*))?\x1b\\',
  ).allMatches(s)) {
    final keys = m[1]!.split(',');
    if (data == null && !keys.contains('a=T')) {
      continue;
    }
    (data ??= StringBuffer()).write(m[2] ?? '');
    if (!keys.contains('m=1')) {
      files.add(base64.decode('$data'));
      data = null;
    }
  }
  return files;
}

/// The raster attributes of the sixel images sent: their size in pixels.
List<String> sixelSizes(TwkTester t) {
  final s = latin1.decode([for (final f in t.terminal.frames) ...f]);
  return [
    for (final m in RegExp(r'\x1bP0;1;0q"1;1;(\d+);(\d+)').allMatches(s))
      '${m[1]}x${m[2]}',
  ];
}

/// The color [argb] as the emulator's cells hold it.
int cellColor(int argb) =>
    Color.rgb(argb >> 16 & 0xFF, argb >> 8 & 0xFF, argb & 0xFF).value;

void main() {
  group('size', () {
    testTwk('as many cells as its pixels take, 10 × 20 where the terminal '
        'reports no cell size', (t) async {
      await t.pumpWidget(topLeft(Image.bitmap(picture(40, 40))));
      expect(sizeOf(t), (4, 2));
    });

    testTwk('at the cell size the terminal reports', (t) async {
      await t.pumpWidget(
        topLeft(Image.bitmap(picture(40, 40))),
        cellPixels: (8, 16),
      );
      expect(sizeOf(t), (5, 3));
    });

    testTwk('a width or a height given, the other follows by its aspect; '
        'both given, the box is theirs', (t) async {
      final b = picture(40, 40);
      await t.pumpWidget(topLeft(Image.bitmap(b, width: 8)));
      expect(sizeOf(t), (8, 4));
      await t.pumpWidget(topLeft(Image.bitmap(b, height: 1)));
      expect(sizeOf(t), (2, 1));
      await t.pumpWidget(topLeft(Image.bitmap(b, width: 10, height: 2)));
      expect(sizeOf(t), (10, 2));
    });

    testTwk('within the constraints, its aspect kept; tight ones are '
        'taken as they are', (t) async {
      await t.pumpWidget(topLeft(Image.bitmap(picture(1600, 800))));
      expect(sizeOf(t), (80, 20), reason: 'as wide as the screen');
      await t.pumpWidget(topLeft(Image.bitmap(picture(400, 2000))));
      expect(sizeOf(t), (10, 24), reason: 'as tall as the screen');
      await t.pumpWidget(
        topLeft(
          SizedBox(width: 20, height: 3, child: Image.bitmap(picture(40, 40))),
        ),
      );
      expect(sizeOf(t), (20, 3));
    });

    test('its intrinsic sizes follow from the other axis by its aspect', () {
      final r = RenderImage(ImageSource.bitmap(picture(40, 40)));
      expect(r.getMaxIntrinsicWidth(4), 8);
      expect(r.getMinIntrinsicWidth(4), 8);
      expect(r.getMaxIntrinsicHeight(8), 4);
      expect(r.getMinIntrinsicHeight(8), 4);
      expect(r.getMaxIntrinsicWidth(BoxConstraints.unbounded), 4);
      expect(r.getMaxIntrinsicHeight(BoxConstraints.unbounded), 2);
    });
  });

  group('protocols', () {
    for (final protocol in [
      GraphicsProtocol.kitty,
      GraphicsProtocol.sixel,
      GraphicsProtocol.iterm2,
    ]) {
      testTwk('${protocol.name}: placed in its cells, which stay blank', (
        t,
      ) async {
        await t.pumpWidget(
          topLeft(Image.bitmap(picture(40, 40))),
          graphics: protocol,
        );
        final id = protocol == GraphicsProtocol.kitty ? ' 1/1' : '';
        expect(shown(t), [startsWith('${protocol.name}$id 4x2 at (0, 0), ')]);
        expect(t.lines.take(2), ['', '']);
      });
    }

    testTwk('kitty and iTerm2: a PNG as big as the cells, transparent past '
        'the image, so that the terminal does not stretch it', (t) async {
      await t.pumpWidget(
        topLeft(Image.bitmap(picture(35, 40))),
        graphics: GraphicsProtocol.kitty,
      );
      final png = decodePng(kittyFiles(t).single);
      expect((png.width, png.height), (40, 40));
      expect(png.pixel(0, 0), red);
      expect(png.pixel(34, 39), red);
      expect(png.pixel(35, 0) >>> 24, 0);
    });

    testTwk('sixel: in whole bands of six pixels, no taller than its cells', (
      t,
    ) async {
      await t.pumpWidget(
        topLeft(Image.bitmap(picture(40, 40))),
        graphics: GraphicsProtocol.sixel,
      );
      expect(sixelSizes(t), ['36x36']);
      expect(shown(t), [startsWith('sixel 4x2 at (0, 0), ')]);
    });

    testTwk("none: half blocks in the image's colours", (t) async {
      final b = picture(40, 40, bottom: blue, split: 10);
      await t.pumpWidget(topLeft(Image.bitmap(b)));
      expect(shown(t), isEmpty);
      final upper = t.cell(0, 0);
      expect(
        (upper.text, upper.fg, upper.bg),
        (
          '▀',
          cellColor(red),
          cellColor(blue),
        ),
      );
      final lower = t.cell(3, 1);
      expect(
        (lower.text, lower.fg, lower.bg),
        (
          '▀',
          cellColor(blue),
          cellColor(blue),
        ),
      );
      expect(t.cell(4, 0).text, ' ', reason: 'past the image');
    });

    testTwk('none: quadrants with BlockMode.quadrant, cell for cell as '
        'BlockImage draws them', (t) async {
      final b = picture(40, 40, left: red, splitX: 15, bottom: blue);
      await t.pumpWidget(
        topLeft(Image.bitmap(b, blockMode: BlockMode.quadrant)),
      );
      final blocks = BlockImage(b, columns: 4, rows: 2, mode: .quadrant);
      expect(blocks.cellAt(1, 0).glyph, isNot(anyOf(' ', '█')));
      for (var row = 0; row < 2; row++) {
        for (var column = 0; column < 4; column++) {
          final want = blocks.cellAt(column, row);
          final got = t.cell(column, row);
          expect(
            (got.text, got.fg, got.bg),
            (
              want.glyph,
              want.fg == null ? 0 : cellColor(want.fg! | 0xFF000000),
              want.bg == null ? 0 : cellColor(want.bg! | 0xFF000000),
            ),
            reason: 'cell ($column, $row)',
          );
        }
      }
    });

    testTwk('none: a transparent pixel leaves the cell under it as it is', (
      t,
    ) async {
      final b = picture(40, 40, bottom: 0, split: 10);
      await t.pumpWidget(
        Box(
          style: const Style(bg: Color.green),
          child: Stack(
            children: [
              const Column(children: [Text('abcd'), Text('efgh')]),
              topLeft(Image.bitmap(b)),
            ],
          ),
        ),
      );
      final upper = t.cell(0, 0);
      expect(
        (upper.text, upper.fg, upper.bg),
        (
          '▀',
          cellColor(red),
          Color.green.value,
        ),
      );
      final lower = t.cell(0, 1);
      expect((lower.text, lower.bg), ('e', Color.green.value));
    });

    testTwk('forceBlocks: blocks where the terminal shows images', (t) async {
      await t.pumpWidget(
        topLeft(Image.bitmap(picture(40, 40), forceBlocks: true)),
        graphics: GraphicsProtocol.kitty,
      );
      expect(shown(t), isEmpty);
      expect(t.cell(0, 0).text, '▀');
    });
  });

  testTwk('fit and alignment: placed in the cells the box leaves', (t) async {
    final b = picture(40, 40);
    final cases = {
      (ImageFit.contain, Alignment.center): '4x2 at (3, 0)',
      (ImageFit.contain, Alignment.topLeft): '4x2 at (0, 0)',
      (ImageFit.contain, Alignment.bottomRight): '4x2 at (6, 0)',
      (ImageFit.scaleDown, Alignment.center): '4x2 at (3, 0)',
      (ImageFit.cover, Alignment.center): '10x2 at (0, 0)',
      (ImageFit.fill, Alignment.center): '10x2 at (0, 0)',
    };
    for (final MapEntry(key: (fit, alignment), :value) in cases.entries) {
      final image = Image.bitmap(
        b,
        width: 10,
        height: 2,
        fit: fit,
        alignment: alignment,
      );
      await t.pumpWidget(topLeft(image), graphics: GraphicsProtocol.kitty);
      expect(shown(t), [
        matches('^kitty \\d+/\\d+ ${RegExp.escape(value)}, '),
      ], reason: '${fit.name} ${describeAlignment(alignment)}');
    }
  });

  testTwk('the image is placed again as it is until its box or a property '
      'changes, then encoded anew', (t) async {
    final b = picture(40, 40);
    Widget app(String text, Image image) => topLeft(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(text), image],
      ),
    );
    await t.pumpWidget(
      app('first', Image.bitmap(b, width: 4)),
      graphics: GraphicsProtocol.kitty,
    );
    await t.pumpWidget(app('second', Image.bitmap(b, width: 4)));
    expect(t.lines.first, 'second');
    expect(kittyFiles(t), hasLength(1), reason: 'repainted, the same image');
    await t.pumpWidget(app('second', Image.bitmap(b, width: 6)));
    expect(kittyFiles(t), hasLength(2), reason: 'a box of 6 × 3');
    expect(shown(t), [startsWith('kitty 2/2 6x3 at (0, 1), ')]);
    await t.pumpWidget(app('second', Image.bitmap(b, width: 6, fit: .fill)));
    expect(kittyFiles(t), hasLength(3), reason: 'another fit');
  });

  group('properties', () {
    testTwk('another blockMode draws the image again in its blocks', (
      t,
    ) async {
      // a cell's two by two quadrant pixels: blue on the left, red on the
      // right; one pixel, their mean, across in half blocks
      final b = picture(10, 20, left: blue, splitX: 5);
      await t.pumpWidget(topLeft(Image.bitmap(b)));
      expect(t.cell(0, 0).text, '▀');
      await t.pumpWidget(
        topLeft(Image.bitmap(b, blockMode: BlockMode.quadrant)),
      );
      expect(t.cell(0, 0).text, isIn(['▌', '▐']));
    });

    testTwk('blocks painted again with the rest of the app keep their '
        'colours', (t) async {
      final b = picture(10, 20, bottom: blue, split: 10);
      Widget app(String text) => topLeft(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(text), Image.bitmap(b)],
        ),
      );
      await t.pumpWidget(app('first'));
      await t.pumpWidget(app('second'));
      expect(t.lines.first, 'second');
      final cell = t.cell(0, 1);
      expect(
        (cell.text, cell.fg, cell.bg),
        ('▀', cellColor(red), cellColor(blue)),
      );
    });

    testTwk('forceBlocks set and reset takes the image from the protocol to '
        'blocks and back', (t) async {
      final b = picture(40, 40);
      await t.pumpWidget(
        topLeft(Image.bitmap(b)),
        graphics: GraphicsProtocol.kitty,
      );
      expect(shown(t), hasLength(1));
      await t.pumpWidget(topLeft(Image.bitmap(b, forceBlocks: true)));
      expect(shown(t), isEmpty);
      expect(t.cell(0, 0).text, '▀');
      await t.pumpWidget(topLeft(Image.bitmap(b)));
      expect(shown(t), hasLength(1));
      expect(t.cell(0, 0).text, isNot('▀'));
    });

    test('another cell size lays the image out again at it', () {
      final r = RenderImage(ImageSource.bitmap(picture(40, 40)));
      expect(r.cell, CellSize.fallback);
      expect(r.getMaxIntrinsicWidth(BoxConstraints.unbounded), 4);
      r.cell = const CellSize(20, 20);
      expect(r.getMaxIntrinsicWidth(BoxConstraints.unbounded), 2);
    });

    testTwk("the render object takes the widget's properties and "
        'describes them', (t) async {
      final b = picture(40, 40);
      await t.pumpWidget(
        topLeft(
          Image(
            ImageSource.bitmap(b),
            width: 4,
            height: 3,
            fit: ImageFit.cover,
            alignment: Alignment.topLeft,
            blockMode: BlockMode.quadrant,
            forceBlocks: true,
          ),
        ),
      );
      final r = t.renderObject<RenderImage>(find.byType(Image));
      expect(
        (r.boxWidth, r.boxHeight, r.fit, r.alignment, r.blockMode),
        (4, 3, ImageFit.cover, Alignment.topLeft, BlockMode.quadrant),
      );
      expect(r.forceBlocks, isTrue);
      expect(r.source, ImageSource.bitmap(b));
      expect(
        r.describe().toStringDeep(),
        startsWith(
          'RenderImage ‹source: bitmap(40 × 40), width: 4, height: 3, '
          'fit: "cover", alignment: "topLeft", blockMode: "quadrant", '
          'forceBlocks: true, cell: "10×20", ',
        ),
      );
      await t.pumpWidget(topLeft(Image(ImageSource.bitmap(b))));
      expect(
        t
            .renderObject<RenderImage>(find.byType(Image))
            .describe()
            .toStringDeep(),
        startsWith('RenderImage ‹source: bitmap(40 × 40), cell: "10×20", '),
        reason: 'the defaults left out',
      );
    });
  });

  test('two sources are equal where they are the same bytes, the same path '
      'or the same bitmap, and say which', () {
    final bytes = Uint8List(4);
    final bitmap = picture(2, 2);
    expect(ImageSource.memory(bytes), ImageSource.memory(bytes));
    expect(
      ImageSource.memory(bytes).hashCode,
      ImageSource.memory(bytes).hashCode,
    );
    expect(ImageSource.memory(bytes), isNot(ImageSource.memory(Uint8List(4))));
    // paths made at run time, so that no two are the same constant
    ImageSource file(String name) => ImageSource.file('$name.png');
    expect(file('a'), file('a'));
    expect(file('a').hashCode, file('a').hashCode);
    expect(file('a'), isNot(file('b')));
    expect(ImageSource.bitmap(bitmap), ImageSource.bitmap(bitmap));
    expect(
      ImageSource.bitmap(bitmap).hashCode,
      ImageSource.bitmap(bitmap).hashCode,
    );
    expect(
      ImageSource.bitmap(bitmap),
      isNot(ImageSource.bitmap(picture(2, 2))),
    );
    expect('${ImageSource.memory(bytes)}', 'memory(4 bytes)');
    expect('${file('a')}', 'file(a.png)');
    expect('${ImageSource.bitmap(bitmap)}', 'bitmap(2 × 2)');
  });

  group('sources', () {
    testTwk('Image.memory: a PNG or a JPEG file', (t) async {
      final png = encodePng(picture(20, 20, bottom: blue, split: 10));
      await t.pumpWidget(topLeft(Image.memory(png)));
      expect(sizeOf(t), (2, 1));
      expect(
        (t.cell(0, 0).fg, t.cell(0, 0).bg),
        (
          cellColor(red),
          cellColor(blue),
        ),
      );
      await t.pumpWidget(topLeft(Image.memory(fixture('jpeg444.jpg'))));
      expect(sizeOf(t), (4, 2), reason: '37 × 23 pixels');
    });

    testTwk('Image.file: the file read when first laid out', (t) async {
      final dir = Directory.systemTemp.createTempSync('twk_image');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/red.png';
      File(path).writeAsBytesSync(encodePng(picture(30, 20)));
      await t.pumpWidget(topLeft(Image.file(path)));
      expect(sizeOf(t), (3, 1));
      expect(t.cell(2, 0).fg, cellColor(red));
    });

    testTwk('a file that is no image, or none, is an error shown in its '
        'place', (t) async {
      await t.pumpWidget(
        topLeft(Image.memory(Uint8List.fromList(utf8.encode('not an image')))),
      );
      expect(t.lines.first, contains('Neither a PNG nor a JPEG file'));
      await t.pumpWidget(topLeft(Image.file('/no/such/file.png')));
      expect(t.lines.first, contains('/no/such/file.png'));
    });
  });
}
