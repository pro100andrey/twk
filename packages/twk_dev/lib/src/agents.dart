/// `twk agents`: [AgentsCommand], and what it does as functions, for a
/// caller that chooses what to write: [agentsPlan] (what writing its
/// files into a project would do, nothing written), [AgentsPlan.apply]
/// (writing it), [agentsProblem], [dependsOnTwk] and [mergeAgentsBlock].
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mold/mold.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'agents/skill.g.dart';
import 'project.dart';

/// What `twk agents` writes into a project, each a choice of its own.
enum AgentsFile {
  /// The twk skill in `.agents/skills/twk`, where agents that follow the
  /// AGENTS.md convention look for skills.
  agentsSkill('.agents/skills/twk'),

  /// The same skill in `.claude/skills/twk`, where Claude Code does. A
  /// copy, not a link: a link is not one on Windows.
  claudeSkill('.claude/skills/twk'),

  /// A block of `AGENTS.md`, between [agentsBegin] and [agentsEnd], which
  /// says where the skill is and how to check an app.
  agentsMd('AGENTS.md');

  const AgentsFile(this.path);

  /// Where it is in the project, with `/`.
  final String path;

  /// Whether it is a copy of the skill.
  bool get isSkill => this != agentsMd;
}

/// The line that opens twk's block in `AGENTS.md`.
const agentsBegin = '<!-- twk:agents begin -->';

/// The line that closes twk's block in `AGENTS.md`.
const agentsEnd = '<!-- twk:agents end -->';

/// What twk's block in `AGENTS.md` says, the markers included.
const agentsBlock =
    '''
$agentsBegin
## Terminal UI with twk

This project's terminal UI is built on twk (Flutter's widget model on a
grid of character cells). Its names, units and defaults differ from
Flutter's: do not write them from memory. Read the twk skill first,
`.agents/skills/twk/SKILL.md` (a copy for Claude Code is in
`.claude/skills/twk`), and look a widget up in its `references/` before
using it.

- Check with `dart analyze` and `dart test`; test the UI with `testTwk`
  (`package:twk_test/twk_test.dart`).
- `dart run twk_dev:twk run bin/main.dart` runs the app hot reloaded;
  `dart run twk_dev:twk agents` writes this block and the skill again
  after twk is upgraded. The text between the two markers is rewritten by
  it: add your own notes outside them.
$agentsEnd
''';

/// What happened, or would, to one file.
enum AgentsAction {
  /// There was none: it is written.
  wrote,

  /// There was one, another: it is written over.
  changed,

  /// There was an `AGENTS.md` without twk's block: the block is put in at
  /// its end, the rest kept.
  added,

  /// There was one, the same: left as it is.
  left,

  /// There was one, another, that the project changed since `twk agents`
  /// wrote it (the manifest of the directory lists the hash it wrote, and
  /// the file has another): it stays, and is named.
  edited,
}

/// One file of a project that `twk agents` writes, or leaves.
final class AgentsChange {
  /// A [path] (relative to the project, with `/`) that [action] is done to
  /// with [bytes].
  const AgentsChange(this.path, this.action, this.bytes, this.file);

  /// Where the file is in the project, with `/`.
  final String path;

  /// What is done to it.
  final AgentsAction action;

  /// What it holds afterwards.
  final List<int> bytes;

  /// The part of the write it belongs to.
  final AgentsFile file;
}

/// Everything writing [AgentsFile]s into a project does, and does not:
/// made by [agentsPlan] with nothing written, written by [apply].
final class AgentsPlan {
  /// The plan for [project].
  const AgentsPlan(
    this.project,
    this.changes,
    this.kept, {
    this.removed = const [],
    this.edited = const [],
    this.manifests = const [],
  });

  /// The project's directory.
  final String project;

  /// Every file the pack has (the skill's, and `AGENTS.md`), by path, with
  /// what is done to it.
  final List<AgentsChange> changes;

  /// The files in the skill's directories that the pack does not have, by
  /// path: the project's own, which `twk agents` leaves as they are.
  final List<String> kept;

  /// The files the pack dropped since `twk agents` wrote them, and the
  /// project did not change since: removed by [apply], by path.
  final List<String> removed;

  /// The files the pack dropped that the project changed since `twk agents`
  /// wrote them, by path: they stay.
  final List<String> edited;

  /// The manifest ([agentsManifest]) of each skill's directory, written
  /// where there is none, or where something else changes there.
  final List<AgentsChange> manifests;

  /// The files that are written, new or over another.
  Iterable<AgentsChange> get writes => changes.where(
    (c) => c.action != AgentsAction.left && c.action != AgentsAction.edited,
  );

  /// The files of the skill that the project changed since `twk agents`
  /// wrote them, by path: they stay as they are.
  Iterable<String> get modified => [
    for (final c in changes)
      if (c.action == AgentsAction.edited) c.path,
  ];

  /// Whether the project already has all of it: nothing to write, nothing
  /// to remove.
  bool get isUpToDate =>
      writes.isEmpty &&
      removed.isEmpty &&
      manifests.every((c) => c.action == AgentsAction.left);

  /// Removes [removed] and the directories that are then empty, and writes
  /// [writes] and the manifests, the directories on the way made; a file
  /// that is [AgentsAction.left] is not touched.
  void apply() {
    for (final path in removed) {
      final file = File(p.joinAll([project, ...path.split('/')]));
      if (file.existsSync()) {
        file.deleteSync();
      }
      final stop = AgentsFile.values
          .where((f) => f.isSkill && path.startsWith('${f.path}/'))
          .map((f) => p.joinAll([project, ...f.path.split('/')]))
          .first;
      for (
        var dir = file.parent;
        p.isWithin(stop, dir.path);
        dir = dir.parent
      ) {
        if (!dir.existsSync() || dir.listSync().isNotEmpty) {
          break;
        }
        dir.deleteSync();
      }
    }
    for (final change in [
      ...writes,
      ...manifests.where((c) => c.action != AgentsAction.left),
    ]) {
      final file = File(p.joinAll([project, ...change.path.split('/')]));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(change.bytes);
    }
  }
}

/// Whether the path [name] of [dir] goes through a link, its last part too:
/// what it points at may be outside the project.
bool _throughLink(String dir, String name) {
  var path = dir;
  for (final part in name.split('/')) {
    path = p.join(path, part);
    if (FileSystemEntity.isLinkSync(path)) {
      return true;
    }
  }
  return false;
}

/// A reason `twk agents` cannot write into a project, to be said as it is.
final class AgentsException implements Exception {
  /// An exception that says [message].
  const AgentsException(this.message);

  /// What stops it.
  final String message;

  @override
  String toString() => message;
}

/// What [files] of the pack writing into [project] would do: for each file
/// of the skill in the directories of [files] whether it is written, over
/// another or not, and `AGENTS.md`'s block put in ([mergeAgentsBlock]).
/// Nothing is written ([AgentsPlan.apply] does).
///
/// A file of the project's own in a skill's directory, which the pack has
/// no file of that path for, is in [AgentsPlan.kept], and stays. One that
/// the manifest of the directory ([agentsManifest]) lists, from an older
/// run, is in [AgentsPlan.removed] where it is still as that run wrote it,
/// else in [AgentsPlan.edited], and stays; with no manifest nothing is
/// removed. A file of the pack that the project changed since a run wrote
/// it, which the manifest tells by the hash it lists, is [AgentsAction.edited]
/// and stays, as does one that differs from the pack and that no manifest
/// lists: nothing says a run wrote it. Throws
/// an [AgentsException] where `AGENTS.md` cannot be merged into, a skill's
/// path is a file or a file's path in it a directory, and so nothing is
/// changed. A link at a file's path, or on the way to it inside the skill's
/// directory, is the project's: it stays as [AgentsAction.edited], and what
/// it points at is not written. The directory itself may be a link, one skill
/// shared by two directories: what is in it is written as in any other.
AgentsPlan agentsPlan(
  String project, {
  Set<AgentsFile> files = const {...AgentsFile.values},
}) {
  final changes = <AgentsChange>[];
  final kept = <String>[];
  final removed = <String>[];
  final edited = <String>[];
  final manifests = <AgentsChange>[];
  final skill = skillFiles();
  for (final target in AgentsFile.values) {
    if (!files.contains(target)) {
      continue;
    }
    if (!target.isSkill) {
      changes.add(_mergeChange(project, target));
      continue;
    }
    final dir = p.joinAll([project, ...target.path.split('/')]);
    if (FileSystemEntity.typeSync(dir) case final type
        when type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory) {
      throw AgentsException('${target.path} is not a directory');
    }
    final manifest = File(p.join(dir, agentsManifest));
    final listed = _readManifest(manifest);
    final changedByProject = <String>{};
    for (final MapEntry(key: name, value: bytes) in skill.entries) {
      final path = '${target.path}/$name';
      final file = File(p.joinAll([project, ...path.split('/')]));
      final type = FileSystemEntity.typeSync(file.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        // refused here, before apply has changed anything
        throw AgentsException('$path is a directory');
      }
      final link = _throughLink(dir, name);
      final action = switch (file.existsSync()) {
        false when link => AgentsAction.edited,
        false => AgentsAction.wrote,
        true when _same(file.readAsBytesSync(), bytes) => AgentsAction.left,
        true when link => AgentsAction.edited,
        // no manifest, one that does not list it, or one that lists another
        // hash than the file has: not what a run wrote
        true when listed[name] != agentsHash(file.readAsBytesSync()) =>
          AgentsAction.edited,
        true => AgentsAction.changed,
      };
      if (action == AgentsAction.edited) {
        changedByProject.add(name);
      }
      changes.add(AgentsChange(path, action, bytes, target));
    }
    var dropped = 0;
    if (Directory(dir).existsSync()) {
      // links are not followed: a link is one entry, kept as it is
      for (final entity in Directory(dir).listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is Directory) {
          continue;
        }
        final name = p.posix.joinAll(
          p.split(p.relative(entity.path, from: dir)),
        );
        if (skill.containsKey(name) || name == agentsManifest) {
          continue;
        }
        final path = '${target.path}/$name';
        final hash = listed[name];
        if (hash == null) {
          kept.add(path);
        } else if (entity is Link) {
          // listed, and a link now: not what a run wrote, whatever it points
          // at, and not for this run to remove
          edited.add(path);
        } else if (hash == agentsHash((entity as File).readAsBytesSync())) {
          removed.add(path);
          dropped++;
        } else {
          edited.add(path);
        }
      }
    }
    final hashes = {
      for (final name in skill.keys.toList()..sort())
        // what was written: a file of the project's stays, with the hash of
        // what was written before it (none: it was not listed)
        if (!changedByProject.contains(name) || listed.containsKey(name))
          name: changedByProject.contains(name)
              ? listed[name]!
              : agentsHash(skill[name]!),
    };
    final json = const JsonEncoder.withIndent('  ').convert({'files': hashes});
    final bytes = utf8.encode('$json\n');
    final writing =
        dropped > 0 ||
        changes.any(
          (c) =>
              c.file == target &&
              c.action != AgentsAction.left &&
              c.action != AgentsAction.edited,
        );
    manifests.add(
      AgentsChange(
        '${target.path}/$agentsManifest',
        switch (manifest.existsSync()) {
          // also where nothing else is written: from here on the project's
          // edits are told from what a run wrote
          false => AgentsAction.wrote,
          true when !writing => AgentsAction.left,
          true when _same(manifest.readAsBytesSync(), bytes) =>
            AgentsAction.left,
          true => AgentsAction.changed,
        },
        bytes,
        target,
      ),
    );
  }
  kept.sort();
  removed.sort();
  edited.sort();
  return AgentsPlan(
    project,
    changes,
    kept,
    removed: removed,
    edited: edited,
    manifests: manifests,
  );
}

/// The files a manifest lists, by path with their hashes; none where it is
/// not there or not one.
Map<String, String> _readManifest(File file) {
  if (!file.existsSync()) {
    return const {};
  }
  try {
    final json = jsonDecode(utf8.decode(file.readAsBytesSync()));
    if (json is Map && json['files'] is Map) {
      return {
        for (final MapEntry(:key, :value) in (json['files'] as Map).entries)
          if (key is String && value is String) key: value,
      };
    }
  } on FormatException {
    // not a manifest of ours: as if there were none
  }
  return const {};
}

AgentsChange _mergeChange(String project, AgentsFile target) {
  final file = File(p.join(project, target.path));
  final String? current;
  if (file.existsSync()) {
    try {
      current = utf8.decode(file.readAsBytesSync());
    } on FormatException {
      throw AgentsException('${target.path} is not UTF-8 text');
    }
  } else {
    current = null;
  }
  final merged = mergeAgentsBlock(current, path: target.path);
  final bytes = utf8.encode(merged);
  final action = switch (current) {
    null => AgentsAction.wrote,
    final text when text == merged => AgentsAction.left,
    final text when !text.contains(agentsBegin) => AgentsAction.added,
    _ => AgentsAction.changed,
  };
  return AgentsChange(target.path, action, bytes, target);
}

/// Where, in a skill's directory, `twk agents` lists the files it wrote.
const agentsManifest = '.twk-agents.json';

/// The fingerprint of [bytes] a manifest holds for a file (FNV-1a, 64 bits,
/// in hex): to tell a file `twk agents` wrote from one the project changed,
/// not to guard against anyone.
String agentsHash(List<int> bytes) {
  // the offset basis in two halves: a 64-bit literal is no JavaScript int
  var hash = (0xcbf29ce4 << 32) | 0x84222325;
  for (final byte in bytes) {
    hash = (hash ^ byte) * 0x100000001b3;
  }
  return 'fnv1a64:${hash.toUnsigned(64).toRadixString(16).padLeft(16, '0')}';
}

/// The files of the packed skill by path in it, with `/`, with their bytes.
Map<String, List<int>> skillFiles() {
  final plan = const Unbundler().plan(
    bytes: base64.decode(kTwkSkillTemplateBase64),
    withContent: false,
  );
  return {for (final file in plan.files) file.to: file.bytes};
}

/// The paths of the packed skill, with `/`: what `twk agents` writes under
/// each skill's directory.
List<String> skillPaths() => skillFiles().keys.toList()..sort();

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// [current], the text of an `AGENTS.md` (null: there is none), with twk's
/// [agentsBlock] put in: between its markers where it has them, else at
/// the end after a blank line. Whatever is outside the markers is kept to
/// the byte; a line ending the file uses ([current] has `\r\n`) is the
/// block's.
///
/// Throws an [AgentsException] naming [path] where the markers are not a
/// begin and an end, once each and in that order: the file is not
/// guessed at.
String mergeAgentsBlock(String? current, {String path = 'AGENTS.md'}) {
  final crlf = current != null && current.contains('\r\n');
  final block = crlf ? agentsBlock.replaceAll('\n', '\r\n') : agentsBlock;
  if (current == null || current.isEmpty) {
    return block;
  }
  final begins = RegExp.escape(agentsBegin);
  final ends = RegExp.escape(agentsEnd);
  final begin = RegExp(begins).allMatches(current).toList();
  final end = RegExp(ends).allMatches(current).toList();
  if (begin.isEmpty && end.isEmpty) {
    final eol = crlf ? '\r\n' : '\n';
    final lead = current.endsWith('\n') ? '' : eol;
    return '$current$lead$eol$block';
  }
  if (begin.length != 1 ||
      end.length != 1 ||
      begin.single.start > end.single.start) {
    throw AgentsException(
      "$path has twk's markers ($agentsBegin, $agentsEnd) not once each "
      'and in that order: put it right, or remove them for a new block '
      'at the end',
    );
  }
  // the block's own closing line break is the file's: it stays outside
  var stop = end.single.end;
  final eol = crlf ? '\r\n' : '\n';
  if (current.startsWith(eol, stop)) {
    stop += eol.length;
  }
  return '${current.substring(0, begin.single.start)}$block'
      '${current.substring(stop)}';
}

/// Why [project] is no Dart project `twk agents` writes into, null when
/// it is one: it has no `pubspec.yaml`, or one that is not YAML.
String? agentsProblem(String project) {
  final file = File(p.join(project, 'pubspec.yaml'));
  if (!file.existsSync()) {
    return 'no pubspec.yaml in $project: this is no Dart project (the '
        'directory to work in is --directory)';
  }
  try {
    if (loadYaml(file.readAsStringSync()) is! YamlMap) {
      return '${file.path} is not a pubspec';
    }
  } on YamlException catch (e) {
    return '${file.path} is not YAML: ${e.message}';
  }
  return null;
}

/// Whether the pubspec of [project] depends on twk: in its dependencies,
/// dev dependencies or overrides.
bool dependsOnTwk(String project) {
  final yaml = loadYaml(
    File(p.join(project, 'pubspec.yaml')).readAsStringSync(),
  );
  if (yaml is! YamlMap) {
    return false;
  }
  return const [
    'dependencies',
    'dev_dependencies',
    'dependency_overrides',
  ].any(
    (section) =>
        yaml[section] is YamlMap &&
        (yaml[section] as YamlMap).containsKey('twk'),
  );
}

/// `twk agents`: writes the twk skill, packed in twk_dev, and a block of
/// `AGENTS.md` into a project, and writes them again after twk was
/// upgraded.
final class AgentsCommand extends Command<int> {
  /// Sets up `twk agents`'s options: `--directory` and `--dry-run`.
  AgentsCommand() {
    argParser
      ..addOption(
        'directory',
        abbr: 'C',
        valueHelp: 'path',
        help:
            'A directory of the project to write into (default: the '
            'current one).',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Say what it would write, and write nothing.',
      );
  }

  @override
  String get name => 'agents';

  @override
  String get invocation => 'twk agents [--directory=<path>] [--dry-run]';

  @override
  String get description =>
      'Teach coding agents twk in this project.\n\n'
      'Writes the twk skill, the one that comes with this twk_dev, whole to '
      '.agents/skills/twk and .claude/skills/twk (copies, no links), and '
      'a short block to AGENTS.md between two markers: appended to an '
      "AGENTS.md of the project's own, which keeps all its text outside "
      'them, replaced where it has one. A second run writes over what the '
      'pack changed, leaves what is the same, and says so; files of the '
      "project's own in the skills' directories are left. --dry-run "
      'names what it would do.';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isNotEmpty) {
      usageException('No arguments: the project is --directory.');
    }
    final project = projectOf(args.option('directory'));
    if (agentsProblem(project) case final problem?) {
      stderr.writeln('twk agents: $problem');
      return 1;
    }
    if (!dependsOnTwk(project)) {
      stderr.writeln(
        'twk agents: the pubspec of $project does not depend on twk: '
        'writing anyway',
      );
    }
    final dryRun = args.flag('dry-run');
    final AgentsPlan plan;
    try {
      plan = agentsPlan(project);
      if (!dryRun) {
        plan.apply();
      }
    } on AgentsException catch (e) {
      stderr.writeln('twk agents: $e');
      return 1;
    } on IOException catch (e) {
      stderr.writeln('twk agents: $e');
      return 1;
    }
    stdout.write(describeAgents(plan, dryRun: dryRun));
    return 0;
  }
}

/// What [plan] says, as `twk agents` prints it: a line a part of the
/// write, the files that changed named when some did, the project's own
/// files in the skills' directories named. With [dryRun] it is what would
/// be done.
String describeAgents(AgentsPlan plan, {bool dryRun = false}) {
  final out = StringBuffer();
  final lead = dryRun ? 'twk agents --dry-run' : 'twk agents';
  if (plan.isUpToDate) {
    out.writeln(
      '$lead: nothing to ${dryRun ? 'write' : 'do'} in ${plan.project}: '
      '${_parts(plan)} ${dryRun ? 'are' : 'are already'} as this twk_dev '
      'has them, no file changed.',
    );
  } else {
    out.writeln('$lead: ${plan.project}:');
    final targets = {for (final c in plan.changes) c.file};
    final width = targets
        .map((t) => t.path.length)
        .fold(0, (a, b) => a > b ? a : b);
    for (final target in AgentsFile.values.where(targets.contains)) {
      final mine = plan.changes.where((c) => c.file == target).toList();
      int count(AgentsAction a) => mine.where((c) => c.action == a).length;
      final wrote = count(AgentsAction.wrote);
      final changed = count(AgentsAction.changed);
      final added = count(AgentsAction.added);
      final left = count(AgentsAction.left);
      final edited = count(AgentsAction.edited);
      final removing = plan.removed
          .where((r) => r.startsWith('${target.path}/'))
          .toList();
      final drop = dryRun ? 'would remove' : 'removed';
      final listing =
          wrote == 0 &&
          plan.manifests.any(
            (m) => m.file == target && m.action == AgentsAction.wrote,
          );
      final said = [
        if (listing) '${dryRun ? 'would write' : 'wrote'} its manifest',
        if (removing.isNotEmpty) '$drop ${_files(removing.length, target)}',
        if (wrote > 0)
          '${dryRun ? 'would write' : 'wrote'} ${_files(wrote, target)}',
        if (changed > 0)
          '${dryRun ? 'would change' : 'changed'} ${_files(changed, target)}',
        if (added > 0)
          '${dryRun ? 'would add' : 'added'} ${_files(added, target)}',
        if (left > 0)
          'left ${_files(left, target)} as ${left == 1 ? 'it is' : 'they are'}',
        if (edited > 0) 'kept ${_files(edited, target)} the project changed',
      ];
      out.writeln('  ${target.path.padRight(width)}  ${said.join(', ')}');
      for (final path in removing) {
        out.writeln(
          '    ${dryRun ? 'would remove' : 'removed'} '
          '${path.substring(target.path.length + 1)}',
        );
      }
      if (target.isSkill && (changed > 0 || (wrote > 0 && left > 0))) {
        for (final c in mine.where((c) => c.action != AgentsAction.left)) {
          out.writeln(
            '    ${c.action == AgentsAction.wrote ? 'wrote ' : 'changed'} '
            '${c.path.substring(target.path.length + 1)}',
          );
        }
      }
    }
  }
  if (plan.modified.isNotEmpty) {
    out.writeln(
      'Left as they are, files of the skill that the project changed since '
      "twk agents wrote them (delete one to have the skill's again): "
      '${plan.modified.join(', ')}',
    );
  }
  if (plan.edited.isNotEmpty) {
    out.writeln(
      'Left as they are, files the skill dropped that the project changed '
      'since twk agents wrote them: ${plan.edited.join(', ')}',
    );
  }
  if (plan.kept.isNotEmpty) {
    out.writeln(
      "Left as they are, files of the project's own that the skill does not "
      'have: ${plan.kept.join(', ')}',
    );
  }
  return out.toString();
}

String _files(int count, AgentsFile target) =>
    target.isSkill ? '$count ${count == 1 ? 'file' : 'files'}' : 'the block';

String _parts(AgentsPlan plan) {
  final targets = {for (final c in plan.changes) c.file};
  return [for (final t in AgentsFile.values.where(targets.contains)) t.path]
      .join(', ');
}
