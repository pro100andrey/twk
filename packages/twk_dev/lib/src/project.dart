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
/// members, not hosted or git ones — whose `lib/` exists. Empty where there
/// is no configuration.
Map<String, String> pathDependencyLibs(String package, {String? pubCache}) {
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
  final cache = p.normalize(pubCache ?? _pubCache());
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
    if (p.equals(dir, own) || p.isWithin(cache, dir)) {
      continue;
    }
    final lib = p.normalize(
      p.join(
        dir,
        '${entry['packageUri'] ?? 'lib/'}'.replaceAll('/', p.separator),
      ),
    );
    if (Directory(lib).existsSync()) {
      libs['${entry['name']}'] = lib;
    }
  }
  return {for (final name in libs.keys.toList()..sort()) name: libs[name]!};
}

String _pubCache() {
  final env = Platform.environment;
  return env['PUB_CACHE'] ??
      (Platform.isWindows
          ? p.join(env['LOCALAPPDATA'] ?? '', 'Pub', 'Cache')
          : p.join(env['HOME'] ?? '', '.pub-cache'));
}
