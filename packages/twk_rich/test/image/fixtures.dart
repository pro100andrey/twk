import 'dart:io';
import 'dart:typed_data';

import 'package:twk_rich/image.dart';

/// The fixture [name] of `test/image/fixtures`, which
/// `tool/image/fixtures.py` writes.
Uint8List fixture(String name) =>
    File('test/image/fixtures/$name').readAsBytesSync();

/// The names of the fixtures with the extension [extension], without it.
List<String> fixtureNames(String extension) => [
  for (final entry in Directory('test/image/fixtures').listSync())
    if (entry.path.endsWith('.$extension'))
      entry.uri.pathSegments.last.replaceFirst(RegExp(r'\.[^.]*$'), ''),
]..sort();

/// Every frame of an animation composed, for tests that compare them all.
extension AllFrames on AnimatedImage {
  List<ImageFrame> get frames => [
    for (var i = 0; i < frameCount; i++) ImageFrame(bitmapAt(i), delays[i]),
  ];
}
