/// Where in the app's code a widget was made, or a build method is:
/// [SourceLocator], [SourceSpot].
library;

import 'dart:async';

import 'app_client.dart';
import 'source_find.dart';

/// A place in a file of the app's code.
final class SourceSpot {
  /// The place [line] and [column] (from 1) in the file [uri].
  const SourceSpot({
    required this.uri,
    required this.line,
    required this.column,
    required this.exact,
    required this.method,
  });

  /// The file's URI (`file:`), or the script's own where the app's package
  /// config does not resolve it.
  final String uri;

  /// From 1.
  final int line;

  /// From 1.
  final int column;

  /// Whether it is the one call that made the widget, or a guess among
  /// several of its type in that build.
  final bool exact;

  /// The build method it is in, `_CounterState.build`.
  final String method;

  /// The file's path, null where [uri] is not a `file:` one.
  String? get path {
    final u = Uri.tryParse(uri);
    return u != null && u.scheme == 'file' ? u.toFilePath() : null;
  }

  @override
  String toString() => '$uri:$line:$column ($method)';
}

/// The source of a build method: its script's text, URI, and where the
/// method begins and ends in it.
final class _BuildSource {
  const _BuildSource({
    required this.uri,
    required this.source,
    required this.start,
    required this.end,
    required this.line,
    required this.column,
    required this.method,
  });

  final String uri;
  final String source;
  final int start;
  final int end;
  final int line;
  final int column;
  final String method;
}

/// A class the VM has, by its id, name and library.
typedef _ClassRef = ({String id, String name, String? library});

/// Where in the app's code a widget was made, found through the VM service
/// of the app ([VmQueries]): the classes by name (`getClassList`), a
/// class's `build` and its place in its script (`getObject`), the script's
/// source as the VM runs it, and a package: URI as a file
/// (`lookupResolvedPackageUris`). What it looks for in that source is
/// source_find.dart's. All of it asked when a place is wanted, nothing
/// while the app runs; what it read is kept until [forget] (a hot reload
/// changes the code).
final class SourceLocator {
  /// A locator asking the app.
  SourceLocator(this._app);

  final VmQueries _app;

  /// How far up a class's supertypes a `build` is looked for.
  static const _superDepth = 6;

  Future<List<_ClassRef>>? _classes;
  final _builds = <String, Future<List<_BuildSource>>>{};
  final _files = <String, Future<String?>>{};
  final _scripts = <String, Future<Json>>{};

  /// Forgets what it read: the app's code changed (a hot reload).
  void forget() {
    _classes = null;
    _builds.clear();
    _files.clear();
    _scripts.clear();
  }

  /// Where the widget of the element [id] in the tree [root] was made, a
  /// widget of the class [type]: in the nearest build above it whose source
  /// calls a constructor of its type ([creationOwners]); null where none
  /// does.
  Future<SourceSpot?> creation(InspectNode? root, int id, String type) async {
    final name = className(type);
    // which builds make widgets of that type, of all the tree's
    final making = <String, bool>{};
    await Future.wait([
      for (final b in buildsIn(root))
        () async {
          final sources = await _buildsOf(b);
          // one not found: taken as making some, its elements its own
          making[b] =
              sources.isEmpty ||
              sources.any(
                (s) =>
                    constructorCalls(s.source, s.start, s.end, name).isNotEmpty,
              );
        }(),
    ]);
    for (final owner in creationOwners(root, id, (b) => making[b] ?? true)) {
      for (final b in await _buildsOf(owner.build)) {
        final picked = pickCall(
          constructorCalls(b.source, b.start, b.end, name),
          owner.index,
          owner.count,
        );
        if (picked != null) {
          final at = lineColumnOf(b.source, picked.offset);
          return SourceSpot(
            uri: await _fileOf(b.uri),
            line: at.line,
            column: at.column,
            exact: picked.exact,
            method: b.method,
          );
        }
      }
    }
    return null;
  }

  /// Where the `build` method of the type [build] (a widget's, a state's)
  /// begins; null for none found.
  Future<SourceSpot?> buildMethod(String build) async {
    final found = await _buildsOf(build);
    if (found.isEmpty) {
      return null;
    }
    final b = found.first;
    return SourceSpot(
      uri: await _fileOf(b.uri),
      line: b.line,
      column: b.column,
      exact: true,
      method: b.method,
    );
  }

  /// The build methods of the classes named [type] (of the app's libraries
  /// first, `dart:` ones never).
  Future<List<_BuildSource>> _buildsOf(String type) {
    final name = className(type);
    return _builds[name] ??= _findBuilds(name).catchError(
      (Object _) => <_BuildSource>[],
    );
  }

  Future<List<_BuildSource>> _findBuilds(String name) async {
    final classes = [
      for (final c in await _classList())
        if (c.name == name && !(c.library?.startsWith('dart:') ?? false)) c,
    ];
    // the app's own (file:) before the packages'; the sort is stable
    final own = [
      for (final c in classes)
        if (c.library?.startsWith('file:') ?? false) c,
    ];
    final rest = [
      for (final c in classes)
        if (!(c.library?.startsWith('file:') ?? false)) c,
    ];
    final builds = <_BuildSource>[];
    for (final c in [...own, ...rest]) {
      final b = await _buildOfClass(c.id, name);
      if (b != null) {
        builds.add(b);
      }
    }
    return builds;
  }

  Future<List<_ClassRef>> _classList() {
    final asked = _classes ??= () async {
      final list = await _app.vm('getClassList');
      return [
        for (final c in _records(list['classes']))
          if (c['id'] case final String id when c['name'] is String)
            (
              id: id,
              name: c['name']! as String,
              library: switch (c['library']) {
                {'uri': final String uri} => uri,
                _ => null,
              },
            ),
      ];
    }();
    // one that failed is asked again next time
    unawaited(asked.then<void>((_) {}, onError: (Object _) => _classes = null));
    return asked;
  }

  /// The `build` of the class [id], or of the nearest of its superclasses
  /// with one.
  Future<_BuildSource?> _buildOfClass(String id, String name) async {
    String? classId = id;
    for (var depth = 0; classId != null && depth < _superDepth; depth++) {
      final c = await _app.vm('getObject', {'objectId': classId});
      final builds = _records(c['functions'])
          .where((f) => f['name'] == 'build');
      final buildId = builds.isEmpty ? null : builds.first['id'];
      if (buildId is String) {
        return _sourceOf(buildId, '$name.build');
      }
      classId = switch (c['super']) {
        {'id': final String id} => id,
        _ => null,
      };
    }
    return null;
  }

  Future<_BuildSource?> _sourceOf(String functionId, String method) async {
    final f = await _app.vm('getObject', {'objectId': functionId});
    final location = f['location'];
    if (location is! Map<String, Object?> ||
        location['script'] is! Map<String, Object?>) {
      return null;
    }
    final scriptId = (location['script']! as Map<String, Object?>)['id'];
    if (scriptId is! String) {
      return null;
    }
    final script = await (_scripts[scriptId] ??= _app.vm('getObject', {
      'objectId': scriptId,
    }));
    final source = script['source'];
    final uri = script['uri'];
    if (source is! String || uri is! String) {
      return null;
    }
    final table = [
      for (final row in script['tokenPosTable'] as List<Object?>? ?? const [])
        if (row is List<Object?> && row.every((n) => n is int)) row.cast<int>(),
    ];
    ({int line, int column})? at(Object? pos) =>
        pos is int ? tokenLineColumn(table, pos) : null;
    final begin =
        at(location['tokenPos']) ??
        (location['line'] is int && location['column'] is int
            ? (
                line: location['line']! as int,
                column: location['column']! as int,
              )
            : null);
    if (begin == null) {
      return null;
    }
    final finish = at(location['endTokenPos']);
    final start = offsetOf(source, begin.line, begin.column);
    final end = finish == null
        ? source.length
        : offsetOf(source, finish.line, finish.column) + 1;
    // the method's name, after its metadata (@override), where it begins
    final name = RegExp(r'\bbuild\s*\(').allMatches(codeOnly(source), start);
    final first = name.isEmpty ? null : name.first;
    final shown = first != null && first.start < end
        ? lineColumnOf(source, first.start)
        : begin;
    return _BuildSource(
      uri: uri,
      source: source,
      start: start,
      end: end,
      line: shown.line,
      column: shown.column,
      method: method,
    );
  }

  /// The `file:` URI of the script [uri]: a `package:` one as the app's
  /// package config resolves it.
  Future<String> _fileOf(String uri) async {
    if (!uri.startsWith('package:')) {
      return uri;
    }
    final file = await (_files[uri] ??= () async {
      try {
        final r = await _app.vm('lookupResolvedPackageUris', {
          'uris': [uri],
        });
        final uris = r['uris'];
        return uris is List<Object?> && uris.isNotEmpty && uris[0] is String
            ? uris[0]! as String
            : null;
      } on Object {
        return null;
      }
    }());
    return file ?? uri;
  }

  static List<Json> _records(Object? v) => [
    if (v is List<Object?>)
      for (final e in v)
        if (e is Map<String, Object?>) e,
  ];
}
