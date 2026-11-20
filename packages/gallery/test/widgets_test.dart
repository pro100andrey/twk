// Every widget twk, twk_rich (its image library too) and twk_term export
// is in the gallery: built in lib/ (on a page, or by the shell around them) or named
// by a page's title in the catalog. A widget added to one of them without
// a page fails here, naming the library it is declared in.
//
// The analyzer resolves the packages once for the file, which takes seconds
// on a quiet machine and longer on a loaded one.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:gallery/testing.dart';
import 'package:test/test.dart';
import 'package:twk_api_names/export_surface.dart';

/// The widgets the packages export that no page builds, and why.
const unpaged = {
  'RootWidget': 'every app, the gallery too, is mounted in one',
  'TwkLocalizations':
      'gives the widgets below it the words twk writes (TwkStrings); '
      'nothing of its own to see, the localization guide shows it',
  'InputDecorator':
      "what a TextField's and a Select's decoration are drawn in: every "
      'field of the InputDecoration page',
};

/// The libraries whose widgets the gallery shows, each with its package.
const libraries = [
  ('package:twk/twk.dart', 'twk'),
  ('package:twk_rich/twk_rich.dart', 'twk_rich'),
  ('package:twk_rich/image.dart', 'twk_rich'),
  ('package:twk_term/twk_term.dart', 'twk_term'),
];

void main() {
  // one analysis for the file
  final surface = ExportSurface.open();

  test('every widget the packages export is in the gallery', () async {
    final code = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          file.readAsStringSync(),
    ].join('\n').replaceAll(RegExp('//.*'), '');
    final titles = [
      for (final g in catalog)
        for (final p in g.pages) p.title,
    ].join('\n');
    expect([
      for (final (library, package) in libraries)
        for (final c in (await surface.exports(library)).values)
          if (c.isInterface &&
              c.isSubclassOf('Widget', inPackage: 'twk') &&
              !c.isAbstract &&
              c.package == package &&
              !unpaged.containsKey(c.name) &&
              !RegExp('\\b${c.name}\\s*[(<.]').hasMatch(code) &&
              !RegExp('\\b${c.name}\\b').hasMatch(titles))
            _missing(c),
    ], isEmpty);
  });
}

/// What the test says of [c], a widget no page builds.
String _missing(Declaration c) =>
    '${c.name}: build it on a page of lib/src/pages/ (declared in '
    '${c.library})';
