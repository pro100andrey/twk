// Writes skills/twk/references/ from doc/widgets/ and doc/guides/.
//
//   dart run tool/skill_references/bin/skill_references.dart
//   dart run tool/xtask.dart skill-references
//
// Files of the references that the catalog no longer gives are deleted. The
// xtask task fails where this changed a file.
import 'dart:io';

import 'package:twk_doc_snippets/packages.dart' show findRoot;
import 'package:twk_skill_references/skill_references.dart';

void main() {
  final root = findRoot();
  final Map<String, String> files;
  try {
    files = buildReferences(
      docWidgets: _read(Directory('$root/doc/widgets')),
      docGuides: _read(Directory('$root/doc/guides')),
    );
  } on ReferenceError catch (e) {
    stderr.writeln(e);
    exitCode = 1;
    return;
  }
  final out = Directory('$root/skills/twk/references');
  if (out.existsSync()) {
    out.deleteSync(recursive: true);
  }
  var total = 0;
  for (final MapEntry(:key, :value) in files.entries) {
    final file = File('${out.path}/$key')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(value);
    final size = file.lengthSync();
    total += size;
    stdout.writeln('${(size / 1024).toStringAsFixed(1).padLeft(6)} KB  $key');
  }
  stdout.writeln(
    '${(total / 1024).toStringAsFixed(1).padLeft(6)} KB  ${files.length} files',
  );
}

/// The Markdown files under [dir] by their path under it.
Map<String, String> _read(Directory dir) => {
  for (final e in dir.listSync(recursive: true).whereType<File>())
    if (e.path.endsWith('.md'))
      e.path.substring(dir.path.length + 1): e.readAsStringSync(),
};
