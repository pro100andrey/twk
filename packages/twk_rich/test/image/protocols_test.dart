import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_rich/image.dart';

import 'fixtures.dart';

void main() {
  test('ImageFormat tells PNG and JPEG by their first bytes', () {
    expect(ImageFormat.of(fixture('rgb8.png')), ImageFormat.png);
    expect(ImageFormat.of(fixture('jpeg420.jpg')), ImageFormat.jpeg);
    expect(ImageFormat.of(Uint8List.fromList([0x47, 0x49, 0x46])), isNull);
  });

  test('decodeImage decodes either', () {
    expect(decodeImage(fixture('rgb8.png')).pixels, fixture('rgb8.rgba'));
    expect(decodeImage(fixture('jpeg444.jpg')).pixels, fixture('jpeg444.rgba'));
    expect(
      () => decodeImage(Uint8List.fromList([1, 2, 3, 4])),
      throwsFormatException,
    );
  });

  test('imageSize reads the size from the header', () {
    expect(imageSize(fixture('rgb8_adam7_2x3.png')), (width: 2, height: 3));
    for (final name in ['jpeg420', 'jpeg_progressive444', 'jpeg_q1']) {
      expect(imageSize(fixture('$name.jpg')), (width: 37, height: 23));
    }
    expect(
      () => imageSize(Uint8List.sublistView(fixture('jpeg420.jpg'), 0, 30)),
      throwsFormatException,
    );
  });

  test('imageSize skips stray bytes, fill bytes and markers without a '
      'length before a JPEG frame', () {
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, // SOI
      0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, // APP0 with 2 bytes
      0x00, 0x12, // stray bytes
      0xFF, 0xFF, // fill
      0xFF, 0xD0, // RST0
      0xFF, 0x01, // TEM
      0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x17, 0x00, 0x25, 0x01, // SOF0
      0x01, 0x11, 0x00,
    ]);
    expect(imageSize(jpeg), (width: 37, height: 23));
  });

  test('an encoded image and a bitmap say their size', () {
    final image = pngImage(Bitmap(3, 2));
    expect('$image', 'EncodedImage(3 × 2, ${image.data.length} bytes)');
    expect('${Bitmap(3, 2)}', 'Bitmap(3 × 2)');
  });

  group('kittyImage', () {
    test('takes a PNG file as it is', () {
      final png = fixture('rgba8.png');
      final image = kittyImage(png);
      expect(image.data, same(png));
      expect((image.pixelWidth, image.pixelHeight), (13, 11));
    });

    test('encodes a JPEG file as PNG', () {
      final image = kittyImage(fixture('jpeg420.jpg'));
      expect(ImageFormat.of(image.data), ImageFormat.png);
      expect((image.pixelWidth, image.pixelHeight), (37, 23));
      expect(decodePng(image.data).pixels, fixture('jpeg420.rgba'));
    });
  });

  test('iterm2Image takes a PNG or JPEG file as it is', () {
    final jpeg = fixture('jpeg422.jpg');
    final image = iterm2Image(jpeg);
    expect(image.data, same(jpeg));
    expect((image.pixelWidth, image.pixelHeight), (37, 23));
  });

  test('pngImage encodes a bitmap', () {
    final bitmap = Bitmap(3, 2)..setPixel(2, 1, 0xFF123456);
    final image = pngImage(bitmap);
    expect((image.pixelWidth, image.pixelHeight), (3, 2));
    expect(decodePng(image.data).pixel(2, 1), 0xFF123456);
  });
}
