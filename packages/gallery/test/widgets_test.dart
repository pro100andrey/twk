// Every widget twk, twk_rich (its image library too) and twk_term export
// is in the gallery: built in lib/ (on a page, or by the shell around them) or named
// by a page's title in the catalog. A widget added to one of them without
// a page fails here, naming the library it is declared in.
import 'dart:io';
import 'dart:mirrors';

import 'package:gallery/gallery.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';

/// The widgets the packages export that no page builds, and why.
const unpaged = {
  'RootWidget': 'every app, the gallery too, is mounted in one',
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
  test('every widget the packages export is in the gallery', () {
    final code = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          file.readAsStringSync(),
    ].join('\n').replaceAll(RegExp('//.*'), '');
    final titles = [
      for (final g in catalog)
        for (final p in g.pages) p.title,
    ].join('\n');
    final widget = reflectClass(Widget);
    final mirrors = currentMirrorSystem().libraries;
    expect([
      for (final (library, package) in libraries)
        for (final c in _exportedClasses(mirrors[Uri.parse(library)]!))
          if (c.isSubclassOf(widget) &&
              !c.isAbstract &&
              _isIn(c, package) &&
              !unpaged.containsKey(_name(c)) &&
              !RegExp('\\b${_name(c)}\\s*[(<.]').hasMatch(code) &&
              !RegExp('\\b${_name(c)}\\b').hasMatch(titles))
            _missing(c),
    ], isEmpty);
  });
}

/// The public classes [library] exports: its own and those of the
/// libraries it exports, through their show and hide lists.
Iterable<ClassMirror> _exportedClasses(LibraryMirror library) => [
  for (final d in library.declarations.values)
    if (d is ClassMirror && !d.isPrivate) d,
  for (final dependency in library.libraryDependencies)
    if (dependency.isExport)
      for (final c in _exportedClasses(dependency.targetLibrary!))
        if (_passes(dependency.combinators, c.simpleName)) c,
];

/// Whether [name] passes the show and hide lists of [combinators] (the VM
/// gives each name of a list a combinator of its own).
bool _passes(List<CombinatorMirror> combinators, Symbol name) {
  final shown = combinators.where((c) => c.isShow);
  return combinators.every((c) => c.isShow || !c.identifiers.contains(name)) &&
      (shown.isEmpty || shown.any((c) => c.identifiers.contains(name)));
}

/// What the test says of [c], a widget no page builds.
String _missing(ClassMirror c) =>
    '${_name(c)}: build it on a page of lib/src/pages/ (declared in '
    '${(c.owner! as LibraryMirror).uri})';

String _name(DeclarationMirror d) => MirrorSystem.getName(d.simpleName);

/// Whether [d] is declared in a library of [package].
bool _isIn(DeclarationMirror d, String package) => switch (d.owner) {
  final LibraryMirror l => l.uri.toString().startsWith('package:$package/'),
  _ => false,
};
