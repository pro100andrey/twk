// The tester's terminal shows images with the protocol a test gives it, its
// cells of the size in pixels the test gives, which the emulator takes too;
// by default it shows none and reports no cell size.
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show TerminalImage;
import 'package:twk_test/twk_test.dart';

/// [image] in the [cols] x [rows] cells from (1, 1).
final class Picture extends LeafRenderObjectWidget {
  const Picture(this.image, this.cols, this.rows, {super.key});

  final TerminalImage image;
  final int cols;
  final int rows;

  @override
  RenderPicture createRenderObject(BuildContext context) =>
      RenderPicture(image, cols, rows);
}

final class RenderPicture extends RenderObject {
  RenderPicture(this.image, this.cols, this.rows);

  final TerminalImage image;
  final int cols;
  final int rows;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) => ctx.canvas.image(1, 1, cols, rows, image);
}

/// A kitty image of 12 bytes.
final kitty = TerminalImage(
  GraphicsProtocol.kitty,
  Uint8List(12),
  pixelWidth: 40,
  pixelHeight: 40,
);

/// A sixel image of 32 x 24 pixels: 2 x 1 cells of 16 x 24, 4 x 2 of
/// 10 x 20.
final sixel = TerminalImage(
  GraphicsProtocol.sixel,
  ascii.encode('0;1;0q"1;1;32;24#1;2;100;0;0${'#1!32~-' * 4}'),
  pixelWidth: 32,
  pixelHeight: 24,
);

List<String> shown(TwkTester t) => [for (final i in t.vt.images) '$i'];

TerminalCaps caps(TwkTester t) => t.binding.twkApp.terminal.info.caps;

void main() {
  testTwk('kitty: the image is placed, and the emulator records it', (t) async {
    await t.pumpWidget(
      Picture(kitty, 4, 2),
      size: (10, 4),
      graphics: GraphicsProtocol.kitty,
    );
    expect(caps(t).graphics, GraphicsProtocol.kitty);
    expect(shown(t), ['kitty 1/1 4x2 at (1, 1), 12 bytes']);
  });

  testTwk('sixel: the image arrives, over the cells its pixels reach into at '
      'the size the terminal reports', (t) async {
    await t.pumpWidget(
      Picture(sixel, 2, 1),
      size: (10, 4),
      graphics: GraphicsProtocol.sixel,
      cellPixels: (16, 24),
    );
    expect((caps(t).cellPixelWidth, caps(t).cellPixelHeight), (16, 24));
    expect((t.vt.cellPixelWidth, t.vt.cellPixelHeight), (16, 24));
    expect(shown(t), ['sixel 2x1 at (1, 1), ${sixel.data.length} bytes']);
  });

  testTwk('by default no image is shown, and no cell size reported', (t) async {
    await t.pumpWidget(Picture(kitty, 4, 2), size: (10, 4));
    expect(caps(t).graphics, GraphicsProtocol.none);
    expect((caps(t).cellPixelWidth, caps(t).cellPixelHeight), (0, 0));
    expect((t.vt.cellPixelWidth, t.vt.cellPixelHeight), (10, 20));
    expect(shown(t), isEmpty);
  });
}
