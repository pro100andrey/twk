// The analyzer resolves the packages once for the file, which takes seconds
// on a quiet machine and longer on a loaded one.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_api_names/export_surface.dart';
// Imported so that this file fails to load when a library that twk_rich.dart
// exports is missing or does not compile.
// ignore: unused_import
import 'package:twk_rich/twk_rich.dart';

/// The topics of the package, each a library `src/<topic>/<topic>.dart`.
const topics = [
  'bigtext',
  'diff',
  'highlight',
  'json_view',
  'markdown',
  'qr',
];

void main() {
  // one analysis for the file
  final surface = ExportSurface.open();

  test('twk_rich.dart exports the library of every topic', () async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:twk_rich/twk_rich.dart'),
    );
    final source = File.fromUri(uri!).readAsStringSync();
    final exports = RegExp(
      "^export '([^']*)';",
      multiLine: true,
    ).allMatches(source).map((match) => match[1]).toList();
    expect(exports, [for (final topic in topics) 'src/$topic/$topic.dart']);
  });

  test('image.dart is a library of its own, besides twk_rich.dart, which '
      'exports none of its names', () async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:twk_rich/twk_rich.dart'),
    );
    expect(
      [
        for (final entity in File.fromUri(uri!).parent.listSync())
          if (entity is File) entity.uri.pathSegments.last,
      ]..sort(),
      ['image.dart', 'twk_rich.dart'],
    );
    final rich = await surface.exports('package:twk_rich/twk_rich.dart');
    final image = await surface.exports('package:twk_rich/image.dart');
    expect(image, contains('Image'));
    expect(
      [
        for (final d in image.values)
          if (!d.library.path.startsWith('twk_rich/src/image/')) d.name,
      ],
      isEmpty,
      reason: 'image.dart exports its own declarations only',
    );
    expect(
      [
        for (final name in image.keys)
          if (rich.containsKey(name)) name,
      ],
      isEmpty,
      reason: 'twk_rich.dart exports no name of image.dart',
    );
    expect(
      [
        for (final d in rich.values)
          if (d.library.path.startsWith('twk_rich/src/image/')) d.name,
      ],
      isEmpty,
      reason: 'twk_rich.dart exports nothing of src/image/',
    );
  });
}
