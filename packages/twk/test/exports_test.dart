import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';

import 'package:test/test.dart';
import 'package:twk/hooks.dart' show HookWidget;
import 'package:twk/provider.dart' show Provider;
// Imported so that this file fails to load when a library that twk.dart
// exports is missing or does not compile.
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'sample_app.dart' as sample;

/// The topics of the package, each a library `src/<topic>/<topic>.dart`.
const topics = [
  'animation',
  'binding',
  'controls',
  'data',
  'debug',
  'editing',
  'focus',
  'foundation',
  'framework',
  'gestures',
  'layout',
  'navigation',
  'overlay',
  'scroll',
  'semantics',
  'style',
  'text',
];

/// The twk_core declarations a public signature of this package, or a
/// constructor of a core class twk.dart exports, names that twk.dart does
/// not export: the render objects the widgets create and the parent data
/// they put on them, named by their `createRenderObject`,
/// `updateRenderObject` and supertypes only (the widgets are final), the
/// core's app the binding drives (`AppBinding.twkApp`), and what the
/// constructors of `Canvas` and `PaintContext` take, the frame loop's
/// machinery: the loop makes those and hands them to the render objects
/// that paint, and an app never makes one.
const notExported = {
  'FlexParentData',
  'GlyphTable',
  'GridParentData',
  'Presenter',
  'RenderConstrainedBox',
  'RenderDecoratedBox',
  'RenderDivider',
  'RenderErrorBox',
  'RenderFlex',
  'RenderFractionallySizedBox',
  'RenderGrid',
  'RenderIntrinsicHeight',
  'RenderIntrinsicWidth',
  'RenderPadding',
  'RenderParagraph',
  'RenderPositionedBox',
  'RenderStack',
  'RenderWrap',
  'StackParentData',
  'Surface',
  'TwkApp',
};

void main() {
  final exported = _exported(
    currentMirrorSystem().libraries[Uri.parse('package:twk/twk.dart')]!,
  );

  test('twk.dart exports the library of every topic', () async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:twk/twk.dart'),
    );
    final source = File.fromUri(uri!).readAsStringSync();
    final exports = RegExp(
      "^export '([^']*)';",
      multiLine: true,
    ).allMatches(source).map((match) => match[1]).toList();
    expect(exports, [for (final topic in topics) 'src/$topic/$topic.dart']);
  });

  test('hooks.dart and provider.dart are libraries of their own, besides '
      'twk.dart, which exports none of their names', () async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:twk/twk.dart'),
    );
    expect(
      [
        for (final entity in File.fromUri(uri!).parent.listSync())
          if (entity is File && entity.path.endsWith('.dart'))
            entity.uri.pathSegments.last,
      ]..sort(),
      ['hooks.dart', 'provider.dart', 'twk.dart'],
    );
    for (final (library, widget) in [
      ('hooks', HookWidget),
      ('provider', Provider),
    ]) {
      final names = _exported(
        currentMirrorSystem().libraries[Uri.parse(
          'package:twk/$library.dart',
        )]!,
      );
      expect(names, contains(reflectClass(widget).simpleName));
      expect(
        [
          for (final d in names.values)
            if (!(d.owner! as LibraryMirror).uri.path.startsWith(
              'twk/src/$library/',
            ))
              _name(d),
        ],
        isEmpty,
        reason: '$library.dart exports its own declarations only',
      );
      expect(
        [
          for (final name in names.keys)
            if (exported.containsKey(name)) MirrorSystem.getName(name),
        ],
        isEmpty,
        reason: 'twk.dart exports no name of $library.dart',
      );
    }
  });

  // an extension type is its representation type here (Color an int): the
  // sample app below names those
  test('twk.dart exports the core types that public signatures name, and '
      'those a core class it exports is made with, but the render objects '
      'of its widgets', () {
    final named = <String, String>{};
    for (final d in exported.values) {
      for (final (where, type) in [
        if (_isIn(d, 'twk'))
          ..._signature(d, _name(d))
        // a core class twk.dart exports: what an app makes one with (a
        // HeadlessTerminal for a test)
        else if (d is ClassMirror)
          for (final c in d.declarations.values)
            if (c is MethodMirror && c.isConstructor && !c.isPrivate)
              ..._signature(c, _name(c)),
      ]) {
        for (final core in _coreTypes(type)) {
          named.putIfAbsent(core, () => where);
        }
      }
    }
    expect(named.keys, containsAll(notExported));
    expect({
      for (final MapEntry(:key, :value) in named.entries)
        if (!exported.containsKey(MirrorSystem.getSymbol(key)) &&
            !notExported.contains(key))
          key: value,
    }, isEmpty);
  });

  test('an app that imports only twk.dart builds every public widget and '
      'names every core declaration twk.dart exports', () async {
    final source = File('test/sample_app.dart').readAsStringSync();
    expect(
      [
        for (final m in RegExp(
          "^import '([^']*)';",
          multiLine: true,
        ).allMatches(source))
          if (!m[1]!.startsWith('dart:')) m[1],
      ],
      ['package:twk/twk.dart'],
    );
    final parts = [
      for (final m in RegExp(
        "^part '([^']*)';",
        multiLine: true,
      ).allMatches(source))
        m[1]!,
    ];
    expect(parts, [for (final topic in topics) 'sample_app/$topic.dart']);
    final code = [
      source,
      for (final part in parts) File('test/$part').readAsStringSync(),
    ].join('\n').replaceAll(RegExp('//.*'), '');
    final words = {for (final m in RegExp(r'\w+').allMatches(code)) m[0]};
    final widget = reflectClass(Widget);
    expect([
      for (final d in exported.values)
        if (!words.contains(_name(d)))
          if (_isIn(d, 'twk_core'))
            '${_name(d)}: name it in test/sample_app.dart or a part of it'
          else if (d is ClassMirror &&
              _isIn(d, 'twk') &&
              d.isSubclassOf(widget))
            '${_name(d)}: build it in test/sample_app/${_topic(d)}.dart',
    ], isEmpty);
    expect(sample.snapshot(), 'snap');
    final clock = FakeClock();
    final logged = await clock.elapseUntil(
      clock.run(() => sample.runInMemory(clock: clock.stopwatch)),
    );
    expect([
      for (final r in logged)
        if (r.level.index >= LogLevel.warning.index) '${r.message}: ${r.error}',
    ], isEmpty);
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

String _name(DeclarationMirror d) => MirrorSystem.getName(d.simpleName);

/// The topic of the library that declares [d], `package:twk/src/<topic>/`.
String _topic(DeclarationMirror d) =>
    (d.owner! as LibraryMirror).uri.pathSegments[2];

/// Whether [d] is declared in a library of [package].
bool _isIn(DeclarationMirror d, String package) => switch (d.owner) {
  final LibraryMirror l => l.uri.toString().startsWith('package:$package/'),
  _ => false,
};

/// The types the public signature of [d] names, each with where: those of
/// its fields, parameters and results, its supertypes and type bounds.
Iterable<(String, TypeMirror)> _signature(
  DeclarationMirror d,
  String where,
) sync* {
  switch (d) {
    case ClassMirror(:final superclass):
      for (var s = superclass; s != null; s = s.superclass) {
        yield ('$where (supertype)', s);
        yield ('$where (supertype)', s.mixin);
        // a mixin application is anonymous: its superclass is named too
        if (s.mixin == s) {
          break;
        }
      }
      for (final i in d.superinterfaces) {
        yield ('$where (supertype)', i);
      }
      for (final v in d.typeVariables) {
        yield ('$where (bound)', v.upperBound);
      }
      for (final m in d.declarations.values) {
        if (!m.isPrivate) {
          yield* _signature(m, '$where.${_name(m)}');
        }
      }
    case MethodMirror():
      if (!d.isConstructor) {
        yield (where, d.returnType);
      }
      for (final p in d.parameters) {
        yield (where, p.type);
      }
    case VariableMirror():
      yield (where, d.type);
    case TypedefMirror():
      yield (where, d.referent);
  }
}

/// The names of the twk_core declarations [type] is or names in its type
/// arguments, parameters and bounds.
Set<String> _coreTypes(TypeMirror type, [Set<TypeMirror>? seen]) {
  seen ??= {};
  if (!seen.add(type)) {
    return const {};
  }
  return switch (type) {
    FunctionTypeMirror(:final returnType, :final parameters) => {
      ..._coreTypes(returnType, seen),
      for (final p in parameters) ..._coreTypes(p.type, seen),
    },
    ClassMirror(:final originalDeclaration, :final typeArguments) => {
      if (_isIn(originalDeclaration, 'twk_core')) _name(originalDeclaration),
      for (final a in typeArguments) ..._coreTypes(a, seen),
    },
    TypedefMirror(:final referent) => {
      if (_isIn(type, 'twk_core')) _name(type),
      ..._coreTypes(referent, seen),
    },
    TypeVariableMirror(:final upperBound) => _coreTypes(upperBound, seen),
    _ => const {},
  };
}
