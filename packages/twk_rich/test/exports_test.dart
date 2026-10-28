import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';

import 'package:test/test.dart';
import 'package:twk_rich/image.dart' show Image;
// Imported so that this file fails to load when a library that twk_rich.dart
// exports is missing or does not compile.
// ignore: unused_import
import 'package:twk_rich/twk_rich.dart';

/// The topics of the package, each a library `src/<topic>/<topic>.dart`.
const topics = [
  'ansi',
  'bigtext',
  'diff',
  'highlight',
  'json_view',
  'markdown',
  'qr',
];

void main() {
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
    final libraries = currentMirrorSystem().libraries;
    final rich = _exported(
      libraries[Uri.parse('package:twk_rich/twk_rich.dart')]!,
    );
    final image = _exported(
      libraries[Uri.parse('package:twk_rich/image.dart')]!,
    );
    expect(image, contains(reflectClass(Image).simpleName));
    expect(
      [
        for (final d in image.values)
          if (!(d.owner! as LibraryMirror).uri.path.startsWith(
            'twk_rich/src/image/',
          ))
            MirrorSystem.getName(d.simpleName),
      ],
      isEmpty,
      reason: 'image.dart exports its own declarations only',
    );
    expect(
      [
        for (final name in image.keys)
          if (rich.containsKey(name)) MirrorSystem.getName(name),
      ],
      isEmpty,
      reason: 'twk_rich.dart exports no name of image.dart',
    );
    expect(
      [
        for (final d in rich.values)
          if ((d.owner! as LibraryMirror).uri.path.startsWith(
            'twk_rich/src/image/',
          ))
            MirrorSystem.getName(d.simpleName),
      ],
      isEmpty,
      reason: 'twk_rich.dart exports nothing of src/image/',
    );
  });
}

/// The public declarations [library] exports by name: its own and those of
/// the libraries it exports, through their show and hide lists.
Map<Symbol, DeclarationMirror> _exported(LibraryMirror library) {
  final names = {
    for (final MapEntry(:key, :value) in library.declarations.entries)
      if (!value.isPrivate) key: value,
  };
  for (final dependency in library.libraryDependencies) {
    if (dependency.isExport) {
      // the VM gives each name of a show or hide list a combinator of its
      // own
      final combinators = dependency.combinators;
      final shown = {
        for (final c in combinators)
          if (c.isShow) ...c.identifiers,
      };
      final hidden = {
        for (final c in combinators)
          if (c.isHide) ...c.identifiers,
      };
      names.addAll(
        _exported(dependency.targetLibrary!)..removeWhere(
          (name, _) =>
              hidden.contains(name) ||
              combinators.any((c) => c.isShow) && !shown.contains(name),
        ),
      );
    }
  }
  return names;
}
