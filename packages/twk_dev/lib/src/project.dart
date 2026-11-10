/// The project a command works for: [projectOf].
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:twk_core/twk_core.dart';

/// The directory of the project [directory] is in, the current one when
/// not given: [LocalAddress.projectOf] of [directory] made absolute and
/// normalised, so that `..` goes up and the path it gives has no `.` or
/// `..` in it.
String projectOf(String? directory) =>
    LocalAddress.projectOf(p.normalize(p.absolute(directory ?? '.')));

/// The `lib/` directories of the path dependencies of the package in
/// [package], by the package's name, sorted by it: every package of the
/// package configuration (`.dart_tool/package_config.json`, the nearest
/// one up from [package], a workspace's the same for each member) that is
/// not [package] itself and is not in the pub cache ([pubCache], else
/// `PUB_CACHE`, else pub's default one) — path dependencies and workspace
/// members, not hosted or git ones — whose package directory (its
/// `packageUri` from the root, the root itself where the entry has none, as
/// the package configuration says) exists. Where no pub cache is known (no
/// [pubCache], no `PUB_CACHE`, no home directory in [environment]), a
/// package under a directory called `.pub-cache` or `Pub/Cache` counts as
/// hosted, and only those are left out. Empty where there is no
/// configuration.
Map<String, String> pathDependencyLibs(
  String package, {
  String? pubCache,
  Map<String, String>? environment,
}) {
  File? config;
  for (var dir = p.normalize(p.absolute(package)); ; dir = p.dirname(dir)) {
    final file = File(p.join(dir, '.dart_tool', 'package_config.json'));
    if (file.existsSync()) {
      config = file;
      break;
    }
    if (p.dirname(dir) == dir) {
      return const {};
    }
  }
  final Object? json;
  try {
    json = jsonDecode(config.readAsStringSync());
  } on FormatException {
    return const {};
  }
  final cache = pubCache ?? _pubCache(environment ?? Platform.environment);
  final base = config.uri;
  final own = p.normalize(p.absolute(package));
  final libs = <String, String>{};
  for (final entry in (json is Map ? json['packages'] : null) as List? ?? []) {
    if (entry is! Map ||
        entry['name'] is! String ||
        entry['rootUri'] is! String) {
      continue;
    }
    final root = base.resolve('${entry['rootUri']}');
    if (root.scheme != 'file') {
      continue;
    }
    final dir = p.normalize(root.toFilePath());
    if (p.equals(dir, own) || _inCache(dir, cache)) {
      continue;
    }
    final lib = p.normalize(
      p.join(
        dir,
        '${entry['packageUri'] ?? ''}'.replaceAll('/', p.separator),
      ),
    );
    if (Directory(lib).existsSync()) {
      libs['${entry['name']}'] = lib;
    }
  }
  return {for (final name in libs.keys.toList()..sort()) name: libs[name]!};
}

String? _pubCache(Map<String, String> env) {
  final cache = env['PUB_CACHE'];
  if (cache != null && cache.isNotEmpty) {
    return p.normalize(p.absolute(cache));
  }
  final home = Platform.isWindows ? env['LOCALAPPDATA'] : env['HOME'];
  if (home == null || home.isEmpty) {
    return null;
  }
  return p.normalize(
    Platform.isWindows
        ? p.join(home, 'Pub', 'Cache')
        : p.join(home, '.pub-cache'),
  );
}

bool _inCache(String dir, String? cache) {
  if (cache != null) {
    return p.isWithin(cache, dir);
  }
  final parts = p.split(dir);
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] == '.pub-cache' ||
        (parts[i] == 'Pub' &&
            i + 1 < parts.length &&
            parts[i + 1] == 'Cache')) {
      return true;
    }
  }
  return false;
}
