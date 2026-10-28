// The pictures the gallery holds as bytes (lib/src/pages/pictures.dart)
// are the files of lib/src/pages/assets/, which the Code tab names.
import 'dart:io';

import 'package:gallery/src/pages/pictures.dart';
import 'package:test/test.dart';

void main() {
  test('each picture is its file in lib/src/pages/assets/', () {
    final files = {
      for (final f in Directory('lib/src/pages/assets').listSync())
        if (f is File) f.uri.pathSegments.last: f.readAsBytesSync(),
    };
    expect(pictureBytes.keys, unorderedEquals(files.keys));
    for (final MapEntry(:key, :value) in pictureBytes.entries) {
      expect(value, files[key], reason: key);
    }
  });
}
