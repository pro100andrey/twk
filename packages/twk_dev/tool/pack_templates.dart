// Packs each template of `twk create`, a package in templates/<name>/ with
// a mold.yaml, with mold into lib/src/templates/<name>.g.dart: the archive
// as a base64 Dart source, which `twk create` unpacks. Run from this
// package's directory after a template changed:
//
//   dart run tool/pack_templates.dart
//
// test/templates_test.dart fails while a packed source is not the one its
// template packs into.
import 'dart:io';

import 'package:mold/mold.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  final package = p.dirname(p.dirname(p.fromUri(Platform.script)));
  for (final template in templateDirectories(package)) {
    final packed = packedPath(package, p.basename(template));
    File(packed).writeAsStringSync(
      await packedSource(template, onWarning: (w) => stderr.writeln('$w')),
    );
    stdout.writeln(
      '${p.relative(template, from: package)} -> '
      '${p.relative(packed, from: package)}',
    );
  }
}

/// The directories of the templates under [package]'s `templates/`, each
/// with a `mold.yaml`, sorted.
List<String> templateDirectories(String package) => [
  for (final entity in Directory(p.join(package, 'templates')).listSync())
    if (entity is Directory &&
        File(p.join(entity.path, 'mold.yaml')).existsSync())
      entity.path,
]..sort();

/// Where the template named [name] is packed to in [package].
String packedPath(String package, String name) =>
    p.join(package, 'lib', 'src', 'templates', '$name.g.dart');

/// The Dart source of the template in [dir] packed with mold by its
/// `mold.yaml`: the archive in base64, as `mold pack -f base64` writes it,
/// its constant documented. [onWarning] has what mold warns of.
Future<String> packedSource(String dir, {WarningSink? onWarning}) async {
  final manifest = Manifest.fromFile(p.join(dir, 'mold.yaml'));
  final archive = await const Bundler().bundle(
    projectDir: dir,
    manifest: manifest,
    onWarning: onWarning,
  );
  return const EmbedSource().base64Source(
    archive: archive,
    name: manifest.name,
    doc:
        'The `${p.basename(dir)}` template of `twk create`, its package '
        'packed\nwith mold, in base64.',
  );
}
