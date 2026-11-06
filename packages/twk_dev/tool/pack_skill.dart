// Packs the twk skill, skills/twk/ of the repository (SKILL.md and its
// references/), with mold into lib/src/agents/skill.g.dart: the archive as
// a base64 Dart source, which `twk agents` unpacks into a project. Run from
// this package's directory after the skill changed:
//
//   dart run tool/pack_skill.dart
//
// test/agents_test.dart fails while the packed source is not the one the
// skill packs into.
import 'dart:io';

import 'package:mold/mold.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  final package = p.dirname(p.dirname(p.fromUri(Platform.script)));
  final packed = packedSkillPath(package);
  File(packed).writeAsStringSync(
    await packedSkillSource(
      skillDirectory(package),
      onWarning: (w) => stderr.writeln('$w'),
    ),
  );
  stdout.writeln(
    '${p.relative(skillDirectory(package), from: package)} -> '
    '${p.relative(packed, from: package)}',
  );
}

/// The skill's directory in the repository [package] (twk_dev) is in:
/// `skills/twk/`, two directories above `packages/twk_dev`.
String skillDirectory(String package) =>
    p.normalize(p.join(package, '..', '..', 'skills', 'twk'));

/// Where the skill is packed to in [package].
String packedSkillPath(String package) =>
    p.join(package, 'lib', 'src', 'agents', 'skill.g.dart');

/// The Dart source of the skill in [dir] packed with mold: the archive in
/// base64, as `mold pack -f base64` writes it, its constant documented.
/// [onWarning] has what mold warns of.
///
/// The skill is no mold project, so the manifest is this one: all the
/// files, the repository's `.gitignore` left out.
Future<String> packedSkillSource(String dir, {WarningSink? onWarning}) async {
  final manifest = Manifest.fromYaml(
    'name: twk_skill\nversion: 1.0.0\nuse_gitignore: false\n',
  );
  final archive = await const Bundler().bundle(
    projectDir: dir,
    manifest: manifest,
    onWarning: onWarning,
  );
  return const EmbedSource().base64Source(
    archive: archive,
    name: manifest.name,
    doc:
        'The twk skill, `skills/twk/` of the repository, which `twk agents`\n'
        'writes into a project, packed with mold, in base64.',
  );
}
