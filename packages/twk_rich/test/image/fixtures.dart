import 'dart:io';
import 'dart:typed_data';

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
