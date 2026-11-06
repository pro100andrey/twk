/// The public names of a package, as its libraries really export them, and
/// the rules a name is held to.
///
/// A package's public libraries are the Dart files of its `lib/` outside
/// `lib/src/`. What each exports is read from the analyzer's element model
/// (`LibraryElement.exportNamespace`), so that `export`s, `hide` and `show`
/// are followed as the compiler follows them.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';

/// One public name: [name], a [kind] of declaration, exported by [library].
final class ApiName implements Comparable<ApiName> {
  /// The [name] of a [kind] exported by [library] (a path under `lib/`).
  const ApiName(this.library, this.kind, this.name);

  /// The public library that exports it, as a path under `lib/`.
  final String library;

  /// `class`, `mixin`, `enum`, `extension`, `extension type`, `typedef`,
  /// `function`, `const`, `variable`, `getter` or `setter`.
  final String kind;

  /// The name.
  final String name;

  /// The line of the package's file: `library kind name`.
  String get line => '$library $kind $name';

  @override
  int compareTo(ApiName other) => line.compareTo(other.line);

  @override
  bool operator ==(Object other) => other is ApiName && other.line == line;

  @override
  int get hashCode => line.hashCode;

  @override
  String toString() => line;
}

/// The public names of the package at [packagePath] (its directory), sorted
/// and without repeats.
///
/// The package must resolve (`dart pub get`).
Future<List<ApiName>> publicNames(String packagePath) async =>
    (await publicNamesOf([packagePath])).values.single;

/// The packages of [packagesDir] that are published: each directory with a
/// `pubspec.yaml` that does not say `publish_to: none`, by name, sorted.
/// Throws a [FormatException] naming the pubspec of a package whose name it
/// cannot read, or that is not the name of its directory.
List<String> publishedPackages(String packagesDir) {
  final names = <String>[];
  final directories = Directory(packagesDir).listSync().whereType<Directory>();
  for (final directory in directories) {
    final file = File('${directory.path}/pubspec.yaml');
    if (!file.existsSync()) {
      continue;
    }
    final text = file.readAsStringSync();
    final name = RegExp(
      r'^name:[ \t]*([a-z0-9_]+)[ \t]*(#.*)?$',
      multiLine: true,
    ).firstMatch(text)?.group(1);
    final directoryName = directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    if (name == null || name != directoryName) {
      throw FormatException(
        'cannot read the package name of ${file.path}: '
        '${name == null ? 'no `name:` line' : '`$name` is not $directoryName'}',
      );
    }
    final publishTo = RegExp(
      r'''^publish_to:[ \t]*["']?(\S*?)["']?[ \t]*(#.*)?$''',
      multiLine: true,
    ).firstMatch(text)?.group(1);
    if (publishTo != 'none') {
      names.add(name);
    }
  }
  return names..sort();
}

/// The public names of each of the packages at [packagePaths] (their
/// directories), by directory, in one analysis: packages that depend on one
/// another are resolved once.
Future<Map<String, List<ApiName>>> publicNamesOf(
  List<String> packagePaths,
) async {
  final libs = [for (final p in packagePaths) Directory('$p/lib').absolute];
  final collection = AnalysisContextCollection(
    includedPaths: [for (final l in libs) l.path],
  );
  final found = <String, List<ApiName>>{};
  for (var i = 0; i < libs.length; i++) {
    final lib = libs[i];
    final session = collection.contextFor(lib.path).currentSession;
    final files = [
      for (final e in lib.listSync(recursive: true, followLinks: false))
        if (e is File && e.path.endsWith('.dart') && !_isSrc(lib, e)) e.path,
    ]..sort();
    final names = <ApiName>{};
    for (final file in files) {
      final result = await session.getLibraryByUri(
        session.uriConverter.pathToUri(file)!.toString(),
      );
      if (result is! LibraryElementResult) {
        // A part file, not a library of its own.
        continue;
      }
      final path = file.substring(lib.path.length + 1).replaceAll(r'\', '/');
      final exported = result.element.exportNamespace.definedNames2;
      final getters = {
        for (final e in exported.values)
          if (e is GetterElement) e.displayName,
      };
      for (final entry in exported.entries) {
        if (entry.key.startsWith('_')) {
          continue;
        }
        final kind = _kindOf(entry.value, getters);
        // A setter beside a getter of its name is the variable's, listed
        // once.
        if (kind != 'setter-of-getter') {
          names.add(ApiName(path, kind, entry.key.replaceAll('=', '')));
        }
      }
    }
    found[packagePaths[i]] = names.toList()..sort();
  }
  return found;
}

bool _isSrc(Directory lib, File file) {
  final relative = file.path.substring(lib.path.length + 1);
  return relative.startsWith('src/') || relative.startsWith(r'src\');
}

String _kindOf(Element e, Set<String> getters) => switch (e) {
  MixinElement() => 'mixin',
  EnumElement() => 'enum',
  ClassElement() => 'class',
  ExtensionTypeElement() => 'extension type',
  ExtensionElement() => 'extension',
  TypeAliasElement() => 'typedef',
  TopLevelFunctionElement() => 'function',
  TopLevelVariableElement(:final isConst) => isConst ? 'const' : 'variable',
  GetterElement(:final variable, :final isOriginVariable) =>
    variable.isConst
        ? 'const'
        : isOriginVariable
        ? 'variable'
        : 'getter',
  SetterElement() =>
    getters.contains(e.displayName) ? 'setter-of-getter' : 'setter',
  _ => 'other',
};

/// The text of a package's file: one `library kind name` line per name,
/// sorted.
String renderNames(Iterable<ApiName> names) {
  final lines = {for (final n in names) n.line}.toList()..sort();
  return lines.isEmpty ? '' : '${lines.join('\n')}\n';
}

/// The names too general for an export, and the exceptions to them, as
/// `banned_names.txt` writes them.
final class Rules {
  /// Rules from their parts.
  const Rules(this.banned, this.allowed);

  /// Reads [text]: blank lines and `#` comments are skipped, and each rule
  /// is a line
  ///
  ///     ban <name> -- <reason>
  ///     allow <package> <name> -- <reason>
  ///
  /// A line of another shape, or a rule without a reason, throws a
  /// [FormatException].
  factory Rules.parse(String text) {
    final banned = <String, String>{};
    final allowed = <Allowed>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      final m = RegExp(
        r'^(?:ban (\w+)|allow (\w+) (\w+)) -- (\S.*)$',
      ).firstMatch(line);
      if (m == null) {
        throw FormatException(
          'line ${i + 1}: "$line" is neither "ban <name> -- <reason>" nor '
          '"allow <package> <name> -- <reason>"',
        );
      }
      final reason = m[4]!;
      if (m[1] != null) {
        banned[m[1]!] = reason;
      } else {
        allowed.add(Allowed(m[2]!, m[3]!, reason));
      }
    }
    return Rules(banned, allowed);
  }

  /// The banned names, each with the reason it is.
  final Map<String, String> banned;

  /// The exceptions: the package, the name and the reason it is right.
  final List<Allowed> allowed;
}

/// An exception: [package] exports [name], and why that is right.
final class Allowed {
  /// The exception for [name] of [package], for [reason].
  const Allowed(this.package, this.name, this.reason);

  /// The package.
  final String package;

  /// The name.
  final String name;

  /// Why the name is right as it is.
  final String reason;
}

/// What is wrong with [names] (each package's public names, by package
/// name) under [rules], one message each, in a stable order: a banned name
/// with no exception, and an exception that matches no name.
List<String> checkRules(Rules rules, Map<String, List<ApiName>> names) {
  final problems = <String>[];
  final used = <Allowed>{};
  for (final package in names.keys.toList()..sort()) {
    final reported = <String>{};
    for (final n in names[package]!) {
      if (!rules.banned.containsKey(n.name)) {
        continue;
      }
      final exception = rules.allowed
          .where((a) => a.package == package && a.name == n.name)
          .firstOrNull;
      if (exception != null) {
        used.add(exception);
      } else if (reported.add(n.name)) {
        problems.add(
          '$package exports `${n.name}` (${n.kind}, ${n.library}), a name '
          'too general for an export: ${rules.banned[n.name]}. Rename it, '
          'or if it is right as it is, add '
          '`allow $package ${n.name} -- <why>` to '
          'tool/api_names/banned_names.txt.',
        );
      }
    }
  }
  for (final a in rules.allowed) {
    if (used.contains(a)) {
      continue;
    }
    problems.add(
      'tool/api_names/banned_names.txt allows `${a.name}` in ${a.package}, '
      'which exports no such banned name any more. Remove the line '
      '`allow ${a.package} ${a.name}`.',
    );
  }
  return problems;
}
