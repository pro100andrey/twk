// `twk agents`: the skill packed in twk_dev written into a project, written
// again as the pack changed, a block of the project's own AGENTS.md put in
// between its markers, and the pack held to skills/twk of the repository.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/src/agents.dart';

import '../tool/pack_skill.dart';
import 'twk.dart';

/// Every file under [dir] by path with `/`, with its bytes.
Map<String, List<int>> snapshot(String dir) => {
  for (final entity in Directory(dir).listSync(recursive: true))
    if (entity is File)
      p.posix.joinAll(p.split(p.relative(entity.path, from: dir))): entity
          .readAsBytesSync(),
};

bool _equal(List<int>? a, List<int>? b) =>
    a != null &&
    b != null &&
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

/// Expects [a] and [b] to hold the same files with the same bytes.
void expectSame(Map<String, List<int>> a, Map<String, List<int>> b) {
  expect(a.keys.toList()..sort(), b.keys.toList()..sort());
  for (final key in a.keys) {
    expect(a[key], b[key], reason: key);
  }
}

void main() {
  late Directory root;
  late String project;

  setUp(() {
    root = Directory.systemTemp.createTempSync('twk_agents');
    project = p.normalize(root.absolute.path);
    File(p.join(project, 'pubspec.yaml')).writeAsStringSync(
      'name: demo\nenvironment:\n  sdk: ^3.13.5\ndependencies:\n'
      '  twk: ^0.2.0\n',
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<ProcessResult> agents([List<String> more = const []]) =>
      twkHere(['agents', '--directory', project, ...more]);

  String read(String path) => File(p.join(project, path)).readAsStringSync();

  test(
    'the first run writes the skill twice and AGENTS.md, and says so',
    () async {
      final result = await agents();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final names = skillPaths();
      expect(result.stdout, contains('.agents/skills/twk'));
      expect(result.stdout, contains('wrote ${names.length} files'));
      expect(result.stdout, contains('AGENTS.md'));
      for (final dir in ['.agents/skills/twk', '.claude/skills/twk']) {
        for (final name in names) {
          expect(
            File(p.join(project, dir, name)).existsSync(),
            isTrue,
            reason: '$dir/$name',
          );
        }
      }
      expectSame(
        snapshot(p.join(project, '.agents', 'skills', 'twk')),
        snapshot(p.join(project, '.claude', 'skills', 'twk')),
      );
      expect(read('AGENTS.md'), agentsBlock);
      expect(
        FileSystemEntity.isLinkSync(p.join(project, '.claude/skills/twk')),
        isFalse,
      );
    },
  );

  test('a second run with nothing to do says so and changes no file', () async {
    await agents();
    final before = snapshot(project);
    final result = await agents();
    expect(result.exitCode, 0);
    expect(result.stdout, contains('nothing to do'));
    expect(result.stdout, contains('no file changed'));
    expectSame(snapshot(project), before);
  });

  test('a run after the pack changed writes over what differs, writes '
      'what is missing and leaves the rest', () async {
    await agents();
    final skill = p.join(project, '.claude', 'skills', 'twk');
    File(p.join(skill, 'SKILL.md')).writeAsStringSync('an older skill\n');
    File(p.join(skill, 'references', 'widgets.md')).deleteSync();
    final count = skillPaths().length;
    final result = await agents();
    expect(result.exitCode, 0);
    expect(
      result.stdout,
      allOf(
        contains(
          '.claude/skills/twk  wrote 1 file, changed 1 file, '
          'left ${count - 2} files as they are',
        ),
        contains('changed SKILL.md'),
        contains('wrote  references/widgets.md'),
        contains('.agents/skills/twk  left $count files as they are'),
      ),
    );
    expectSame(
      snapshot(p.join(project, '.claude', 'skills', 'twk')),
      snapshot(p.join(project, '.agents', 'skills', 'twk')),
    );
    expect((await agents()).stdout, contains('nothing to do'));
  });

  test('a file of the project own in a skill directory is left, '
      'and said', () async {
    final own = File(p.join(project, '.agents/skills/twk/notes.md'))
      ..createSync(recursive: true)
      ..writeAsStringSync('mine');
    final result = await agents();
    expect(own.readAsStringSync(), 'mine');
    expect(result.stdout, contains('.agents/skills/twk/notes.md'));
    final again = await agents();
    expect(again.stdout, contains('nothing to do'));
    expect(again.stdout, contains('.agents/skills/twk/notes.md'));
  });

  group('AGENTS.md of the project own', () {
    const head = '# Rules\n\nUse tabs.\n\n';
    const tail = '\n## Tail\n\nThe end, no final break.';

    test('twk block is appended, the text kept to the byte', () async {
      File(p.join(project, 'AGENTS.md')).writeAsStringSync(
        '${head}Last line, no break',
      );
      await agents();
      expect(
        read('AGENTS.md'),
        '${head}Last line, no break\n\n$agentsBlock',
      );
    });

    test(
      'twk block is replaced, every byte outside the markers kept',
      () async {
        File(p.join(project, 'AGENTS.md')).writeAsStringSync(
          '$head$agentsBegin\nold text of an older twk\n$agentsEnd\n$tail',
        );
        final result = await agents();
        expect(result.stdout, contains('changed the block'));
        expect(read('AGENTS.md'), '$head$agentsBlock$tail');
        expect((await agents()).stdout, contains('nothing to do'));
      },
    );

    test('a file with CRLF line endings stays CRLF', () {
      final merged = mergeAgentsBlock('# R\r\n\r\ntext\r\n');
      expect(merged, startsWith('# R\r\n\r\ntext\r\n\r\n$agentsBegin\r\n'));
      expect(merged.replaceAll('\r\n', ''), isNot(contains('\n')));
      expect(mergeAgentsBlock(merged), merged);
    });

    test('markers that are not one begin before one end are refused, '
        'the file untouched, nothing else written', () async {
      for (final text in [
        '$agentsBegin\nno end\n',
        '$agentsEnd\n$agentsBegin\n',
        '$agentsBegin\n$agentsEnd\n$agentsBegin\n$agentsEnd\n',
      ]) {
        File(p.join(project, 'AGENTS.md')).writeAsStringSync(text);
        final result = await agents();
        expect(result.exitCode, 1, reason: text);
        expect(result.stderr, contains("twk agents: AGENTS.md has twk's"));
        expect(read('AGENTS.md'), text);
        expect(Directory(p.join(project, '.agents')).existsSync(), isFalse);
      }
    });

    test('an AGENTS.md that is not UTF-8 is refused and untouched', () async {
      final bytes = [0xff, 0xfe, 0x41];
      File(p.join(project, 'AGENTS.md')).writeAsBytesSync(bytes);
      final result = await agents();
      expect(result.exitCode, 1);
      expect(result.stderr, contains('not UTF-8'));
      expect(File(p.join(project, 'AGENTS.md')).readAsBytesSync(), bytes);
    });
  });

  test('a directory with no pubspec.yaml is no project: said, exit 1, '
      'nothing written', () async {
    File(p.join(project, 'pubspec.yaml')).deleteSync();
    final result = await agents();
    expect(result.exitCode, 1);
    expect(result.stderr, contains('twk agents: no pubspec.yaml'));
    expect(result.stdout, isEmpty);
    expect(root.listSync(), isEmpty);
  });

  test(
    'a project that does not depend on twk is said so and written',
    () async {
      File(
        p.join(project, 'pubspec.yaml'),
      ).writeAsStringSync('name: demo\ndependencies:\n  args: ^2.0.0\n');
      final result = await agents();
      expect(result.exitCode, 0);
      expect(result.stderr, contains('does not depend on twk'));
      expect(File(p.join(project, 'AGENTS.md')).existsSync(), isTrue);
      expect(dependsOnTwk(project), isFalse);
    },
  );

  test('twk as a dev dependency or an override is a dependency', () {
    for (final section in ['dev_dependencies', 'dependency_overrides']) {
      File(p.join(project, 'pubspec.yaml')).writeAsStringSync(
        'name: demo\n$section:\n  twk:\n    path: ../twk\n',
      );
      expect(dependsOnTwk(project), isTrue, reason: section);
    }
  });

  test('a skill path that is a file is refused, nothing written', () async {
    Directory(p.join(project, '.claude/skills')).createSync(recursive: true);
    File(p.join(project, '.claude/skills/twk')).writeAsStringSync('x');
    final result = await agents();
    expect(result.exitCode, 1);
    expect(result.stderr, contains('.claude/skills/twk is not a directory'));
    expect(Directory(p.join(project, '.agents')).existsSync(), isFalse);
  });

  test('--dry-run names what it would write and writes nothing', () async {
    final result = await agents(['--dry-run']);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('--dry-run'));
    expect(result.stdout, contains('would write ${skillPaths().length} files'));
    expect(root.listSync().length, 1, reason: 'the pubspec alone');
  });

  test('an argument is a usage error', () async {
    final result = await twkHere(['agents', 'somewhere']);
    expect(result.exitCode, 64);
  });

  test('agentsPlan with the files a caller chooses plans those alone, '
      'and apply writes those', () {
    final plan = agentsPlan(project, files: {AgentsFile.claudeSkill});
    expect(plan.changes.map((c) => c.file).toSet(), {AgentsFile.claudeSkill});
    expect(plan.isUpToDate, isFalse);
    expect(root.listSync().length, 1, reason: 'planning writes nothing');
    plan.apply();
    expect(
      Directory(p.join(project, '.claude/skills/twk')).existsSync(),
      isTrue,
    );
    expect(Directory(p.join(project, '.agents')).existsSync(), isFalse);
    expect(File(p.join(project, 'AGENTS.md')).existsSync(), isFalse);
    expect(
      agentsPlan(project, files: {AgentsFile.claudeSkill}).isUpToDate,
      isTrue,
    );
  });

  group('the pack', () {
    late String package;
    setUpAll(() async => package = await packageDirectory());

    test('is the skill as skills/twk has it: after a change there, '
        '`dart run tool/pack_skill.dart` packs it again', () async {
      final dir = skillDirectory(package);
      if (!Directory(dir).existsSync()) {
        markTestSkipped('no skills/twk: not in a checkout of the repository');
        return;
      }
      final warnings = <String>[];
      final source = await packedSkillSource(
        dir,
        onWarning: (warning) => warnings.add('$warning'),
      );
      expect(warnings, isEmpty);
      final packed = File(packedSkillPath(package));
      final current = packed.existsSync() ? packed.readAsStringSync() : null;
      // the files that differ, not the base64 of them
      final onDisk = snapshot(dir);
      final inPack = skillFiles();
      final differ = <String>{
        for (final name in {...onDisk.keys, ...inPack.keys})
          if (!_equal(onDisk[name], inPack[name])) 'skills/twk/$name',
      }.toList()..sort();
      expect(
        current == source,
        isTrue,
        reason:
            '${p.relative(packed.path, from: package)} is stale '
            '(${differ.isEmpty ? 'the archive only' : differ.join(', ')}): '
            'dart run tool/pack_skill.dart',
      );
    });

    test('unpacks to the files of skills/twk, byte for byte', () {
      final dir = skillDirectory(package);
      if (!Directory(dir).existsSync()) {
        markTestSkipped('no skills/twk: not in a checkout of the repository');
        return;
      }
      agentsPlan(project, files: {AgentsFile.agentsSkill}).apply();
      expectSame(
        snapshot(p.join(project, '.agents/skills/twk')),
        snapshot(dir),
      );
    });

    test('has the guides recipes.md, widgets-by-need.md and details.md', () {
      expect(
        skillPaths(),
        containsAll([
          'SKILL.md',
          'references/widgets.md',
          'references/guides/recipes.md',
          'references/guides/widgets-by-need.md',
          'references/guides/details.md',
        ]),
      );
    });
  });
}
