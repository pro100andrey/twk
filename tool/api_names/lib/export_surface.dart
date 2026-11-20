/// What a library exports, and what the public signatures of those
/// declarations name, read from the analyzer's element model, for the tests
/// of the packages that hold their export surface (`exports_test.dart`).
///
/// The result is plain data: a test that imports this library needs no
/// dependency on the analyzer itself.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as p;

/// A declaration a library exports, by [name].
final class Declaration {
  Declaration._(this._element);

  final Element _element;

  /// The exported name.
  String get name => _element.displayName;

  /// The library that declares it, such as `package:twk/src/text/text.dart`.
  Uri get library => _element.library!.uri;

  /// The package that declares it.
  String get package => library.pathSegments.first;

  /// Whether it is a class, mixin, enum or extension type.
  bool get isInterface => _element is InterfaceElement;

  /// Whether it is a class declared `abstract`.
  bool get isAbstract => switch (_element) {
    final ClassElement c => c.isAbstract,
    _ => false,
  };

  /// Whether it is, or has among its supertypes, the declaration [name] of
  /// [inPackage] (any package where it is null).
  bool isSubclassOf(String name, {String? inPackage}) {
    final e = _element;
    if (e is! InterfaceElement) {
      return false;
    }
    bool matches(InterfaceElement s) =>
        s.displayName == name &&
        (inPackage == null || s.library.uri.pathSegments.first == inPackage);
    return matches(e) || e.allSupertypes.any((t) => matches(t.element));
  }

  /// The types the public signature of the declaration names, each with
  /// where: those of its fields, parameters and results, its supertypes and
  /// type bounds, and of its members, the declaration's own.
  Iterable<TypeUse> signature() => _signature(_element, name);

  /// The same for the constructors of a class alone.
  Iterable<TypeUse> constructorSignatures() sync* {
    final e = _element;
    if (e is InterfaceElement) {
      for (final c in e.constructors) {
        if (!c.isPrivate) {
          yield* _signature(c, '$name.${c.displayName}');
        }
      }
    }
  }

  @override
  String toString() => '$name ($library)';
}

/// A declaration named by a type: its [name] and the [package] that
/// declares it.
final class TypeRef {
  /// The declaration [name] of [package].
  const TypeRef(this.name, this.package);

  /// The name.
  final String name;

  /// The package that declares it.
  final String package;

  @override
  bool operator ==(Object other) =>
      other is TypeRef && other.name == name && other.package == package;

  @override
  int get hashCode => Object.hash(name, package);

  @override
  String toString() => '$package:$name';
}

/// The declarations a type of a signature is or names ([types], through its
/// type arguments, parameters, bounds and aliases), and [where] it stands.
final class TypeUse {
  /// A use [where], naming [types].
  const TypeUse(this.where, this.types);

  /// The member or supertype that names them, such as `Text.new`.
  final String where;

  /// What the type is or names.
  final Set<TypeRef> types;
}

/// The libraries of the packages that resolve from a directory.
final class ExportSurface {
  ExportSurface._(this._session);

  /// Resolves from [directory] (a package's, its working directory when
  /// null): every library the package's dependencies reach is resolved on
  /// demand and kept, so one surface per test file.
  factory ExportSurface.open([String? directory]) {
    // the analyzer takes only absolute, normalized paths: no trailing
    // separator, and on Windows no '/' in a path of '\'s
    final path = p.normalize(p.absolute(directory ?? Directory.current.path));
    final collection = AnalysisContextCollection(includedPaths: [path]);
    return ExportSurface._(collection.contextFor(path).currentSession);
  }

  final AnalysisSession _session;

  /// The public declarations the library [uri] exports by name, `exports` and
  /// their `show` and `hide` followed as the compiler follows them.
  Future<Map<String, Declaration>> exports(String uri) async {
    final result = await _session.getLibraryByUri(uri);
    if (result is! LibraryElementResult) {
      throw StateError('$uri does not resolve: $result');
    }
    final names = result.element.exportNamespace.definedNames2;
    final getters = {
      for (final e in names.values)
        if (e is GetterElement) e.displayName,
    };
    return {
      for (final MapEntry(:key, :value) in names.entries)
        if (!key.startsWith('_') &&
            // a setter beside a getter of its name is the variable's
            !(value is SetterElement && getters.contains(value.displayName)))
          key.replaceAll('=', ''): Declaration._(value),
    };
  }
}

Iterable<TypeUse> _signature(Element d, String where) sync* {
  switch (d) {
    case final InterfaceElement e:
      for (var s = e.supertype; s != null; s = s.superclass) {
        yield TypeUse('$where (supertype)', _refs(s));
        for (final m in s.mixins) {
          yield TypeUse('$where (supertype)', _refs(m));
        }
      }
      for (final m in e.mixins) {
        yield TypeUse('$where (supertype)', _refs(m));
      }
      for (final i in e.interfaces) {
        yield TypeUse('$where (supertype)', _refs(i));
      }
      if (e is ExtensionTypeElement) {
        yield TypeUse(where, _refs(e.representation.type));
      }
      for (final v in e.typeParameters) {
        final bound = v.bound;
        if (bound != null) {
          yield TypeUse('$where (bound)', _refs(bound));
        }
      }
      for (final m in [
        ...e.fields,
        ...e.getters,
        ...e.setters,
        ...e.methods,
        ...e.constructors,
      ]) {
        if (!m.isPrivate && !_synthetic(m)) {
          yield* _signature(m, '$where.${m.displayName}');
        }
      }
    case final ExecutableElement e:
      if (e is! ConstructorElement) {
        yield TypeUse(where, _refs(e.returnType));
      }
      for (final p in e.formalParameters) {
        yield TypeUse(where, _refs(p.type));
      }
    case final VariableElement e:
      yield TypeUse(where, _refs(e.type));
    case final TypeAliasElement e:
      yield TypeUse(where, _refs(e.aliasedType));
    case final ExtensionElement e:
      yield TypeUse(where, _refs(e.extendedType));
      for (final m in [...e.fields, ...e.getters, ...e.setters, ...e.methods]) {
        if (!m.isPrivate && !_synthetic(m)) {
          yield* _signature(m, '$where.${m.displayName}');
        }
      }
  }
}

/// The declarations [type] is or names in its type arguments, parameters,
/// bounds and aliases.
Set<TypeRef> _refs(DartType type, [Set<DartType>? seen]) {
  seen ??= {};
  if (!seen.add(type)) {
    return const {};
  }
  final alias = type.alias;
  return {
    if (alias != null) ...[
      TypeRef(
        alias.element.displayName,
        alias.element.library.uri.pathSegments.first,
      ),
      for (final a in alias.typeArguments) ..._refs(a, seen),
    ],
    ...switch (type) {
      FunctionType(:final returnType, :final formalParameters) => {
        ..._refs(returnType, seen),
        for (final p in formalParameters) ..._refs(p.type, seen),
      },
      InterfaceType(:final element, :final typeArguments) => {
        TypeRef(element.displayName, element.library.uri.pathSegments.first),
        for (final a in typeArguments) ..._refs(a, seen),
      },
      TypeParameterType(:final bound) => _refs(bound, seen),
      RecordType(:final positionalFields, :final namedFields) => {
        for (final f in [...positionalFields, ...namedFields])
          ..._refs(f.type, seen),
      },
      _ => const <TypeRef>{},
    },
  };
}

/// Whether [m] is made by the compiler, such as the getter of a field, the
/// field of a getter or a default constructor.
bool _synthetic(Element m) => switch (m) {
  PropertyAccessorElement(:final isOriginDeclaration) => !isOriginDeclaration,
  FieldElement(:final isOriginDeclaration) => !isOriginDeclaration,
  ConstructorElement(:final isOriginDeclaration) => !isOriginDeclaration,
  _ => false,
};
