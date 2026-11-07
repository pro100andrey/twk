// `twk agents`: the skill packed in twk_dev written into a project, written
// again as the pack changed, a block of the project's own AGENTS.md put in
// between its markers, and the pack held to skills/twk of the repository.
import 'dart:convert';
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
    // the older run wrote it: its manifest lists the hash of that text
    final manifest = File(p.join(skill, agentsManifest));
    final json = jsonDecode(manifest.readAsStringSync()) as Map;
    (json['files'] as Map)['SKILL.md'] = agentsHash(
      utf8.encode('an older skill\n'),
    );
    manifest.writeAsStringSync(jsonEncode(json));
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

  group('the manifest of a skill directory', () {
    const dirs = ['.agents/skills/twk', '.claude/skills/twk'];

    /// A project that `twk agents` wrote with an older pack: [name] is a file
    /// of it the pack no longer has, [text] what it holds, and the manifest
    /// of each directory lists it (unless [listed] is false).
    Future<void> oldPack(String name, String text, {bool listed = true}) async {
      await agents();
      for (final dir in dirs) {
        File(p.join(project, dir, name))
          ..createSync(recursive: true)
          ..writeAsStringSync(text);
        if (listed) {
          final manifest = File(p.join(project, dir, agentsManifest));
          final json = jsonDecode(manifest.readAsStringSync()) as Map;
          (json['files'] as Map)[name] = agentsHash(utf8.encode(text));
          manifest.writeAsStringSync(jsonEncode(json));
        }
      }
    }

    bool has(String path) => File(p.join(project, path)).existsSync();

    test('a directory where the pack has a file is refused with nothing '
        'changed', () async {
      await agents();
      final dir = p.join(project, dirs.first);
      File(p.join(dir, 'SKILL.md')).deleteSync();
      Directory(p.join(dir, 'SKILL.md')).createSync();
      File(p.join(project, dirs.last, 'SKILL.md')).writeAsStringSync('old\n');
      final before = snapshot(project);
      final result = await agents();
      expect(result.exitCode, 1);
      expect(result.stderr, contains('SKILL.md is a directory'));
      expectSame(snapshot(project), before);
    });

    test("a link where the pack has a file is the project's, and what it "
        'points at is not written', () async {
      await agents();
      final outside = File(p.join(root.path, 'outside.md'))
        ..writeAsStringSync('mine\n');
      final path = p.join(project, dirs.first, 'SKILL.md');
      File(path).deleteSync();
      Link(path).createSync(outside.path);
      final result = await agents();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(outside.readAsStringSync(), 'mine\n');
      expect(FileSystemEntity.isLinkSync(path), isTrue);
    });

    test(
      'nor is what a link on the way to a file of the pack points at',
      () async {
        await agents();
        final inside = skillPaths().firstWhere((n) => n.contains('/'));
        final part = inside.split('/').first;
        final outside = Directory(p.join(root.path, 'outside'))..createSync();
        final there =
            File(p.join(outside.path, inside.split('/').skip(1).join('/')))
              ..createSync(recursive: true)
              ..writeAsStringSync('mine\n');
        final linked = p.join(project, dirs.first, part);
        Directory(linked).deleteSync(recursive: true);
        Link(linked).createSync(outside.path);
        final result = await agents();
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(there.readAsStringSync(), 'mine\n');
      },
    );

    test('is written with the skill, listing each file of the pack with its '
        'hash, and is no file of the pack', () async {
      await agents();
      final pack = skillFiles();
      for (final dir in dirs) {
        final json =
            jsonDecode(read('$dir/$agentsManifest')) as Map<String, dynamic>;
        final files = (json['files'] as Map).cast<String, String>();
        expect(files.keys.toList()..sort(), skillPaths());
        for (final MapEntry(key: name, value: hash) in files.entries) {
          expect(hash, agentsHash(pack[name]!), reason: name);
        }
      }
      expect(skillPaths(), isNot(contains(agentsManifest)));
    });

    test('a file the pack dropped, as it was written, is removed, and its '
        'emptied directory with it; --dry-run says it would', () async {
      await oldPack('references/old/gone.md', 'old');
      final dry = await agents(['--dry-run']);
      expect(dry.stdout, contains('would remove references/old/gone.md'));
      expect(has('.claude/skills/twk/references/old/gone.md'), isTrue);
      final result = await agents();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('removed references/old/gone.md'));
      for (final dir in dirs) {
        expect(has('$dir/references/old/gone.md'), isFalse);
        expect(
          Directory(p.join(project, dir, 'references/old')).existsSync(),
          isFalse,
        );
        expect(has('$dir/references/widgets.md'), isTrue);
        expect(
          (jsonDecode(read('$dir/$agentsManifest')) as Map)['files'],
          isNot(contains('references/old/gone.md')),
        );
      }
      final before = snapshot(project);
      final again = await agents();
      expect(again.stdout, contains('nothing to do'));
      expectSame(snapshot(project), before);
    });

    test('the same file changed by the project stays, and is named', () async {
      await oldPack('references/old.md', 'old');
      File(
        p.join(project, '.claude/skills/twk/references/old.md'),
      ).writeAsStringSync('mine now');
      final result = await agents();
      expect(has('.agents/skills/twk/references/old.md'), isFalse);
      expect(read('.claude/skills/twk/references/old.md'), 'mine now');
      expect(result.stdout, contains('.claude/skills/twk/references/old.md'));
      expect(result.stdout, contains('changed since'));
    });

    test('a file of the skill that the project changed stays, and is named; '
        'the manifest keeps the hash of what was written, and a run with '
        'nothing more to do changes nothing', () async {
      await agents();
      const path = '.claude/skills/twk/SKILL.md';
      File(p.join(project, path)).writeAsStringSync('my own SKILL\n');
      final dry = await agents(['--dry-run']);
      expect(dry.stdout, contains(path));
      expect(dry.stdout, contains('project changed'));
      final manifestBefore = read('.claude/skills/twk/$agentsManifest');
      final result = await agents();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(read(path), 'my own SKILL\n');
      expect(result.stdout, contains(path));
      expect(result.stdout, contains('project changed'));
      expect(read('.claude/skills/twk/$agentsManifest'), manifestBefore);
      final before = snapshot(project);
      final again = await agents();
      expect(again.stdout, contains('nothing to do'));
      expect(again.stdout, contains(path));
      expectSame(snapshot(project), before);
      // the copy in the other directory was not touched by it
      expect(read('.agents/skills/twk/SKILL.md'), isNot('my own SKILL\n'));
    });

    test('a file of the skill changed and a file of it older, as written, '
        'are written over, the manifest saying what was written', () async {
      await agents();
      const edited = '.claude/skills/twk/SKILL.md';
      File(p.join(project, edited)).writeAsStringSync('mine');
      // an older pack's file: the manifest lists its hash
      const old = '.agents/skills/twk/SKILL.md';
      File(p.join(project, old)).writeAsStringSync('older');
      final manifest = File(
        p.join(project, '.agents/skills/twk/$agentsManifest'),
      );
      final json = jsonDecode(manifest.readAsStringSync()) as Map;
      (json['files'] as Map)['SKILL.md'] = agentsHash(utf8.encode('older'));
      manifest.writeAsStringSync(jsonEncode(json));
      final result = await agents();
      expect(read(old), isNot('older'));
      expect(read(edited), 'mine');
      expect(result.stdout, contains(edited));
      expect(result.stdout, isNot(contains('.agents/skills/twk/SKILL.md,')));
      final hashes =
          (jsonDecode(manifest.readAsStringSync()) as Map)['files'] as Map;
      expect(hashes['SKILL.md'], agentsHash(skillFiles()['SKILL.md']!));
    });

    test('a manifest-listed dropped path that is a link stays, and is '
        'named', () async {
      await oldPack('references/old.md', 'old');
      final target = File(p.join(project, 'elsewhere.md'))
        ..writeAsStringSync('old');
      for (final dir in dirs) {
        final path = p.join(project, dir, 'references/old.md');
        File(path).deleteSync();
        Link(path).createSync(target.path);
      }
      const dir = '.claude/skills/twk';
      final result = await agents();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('$dir/references/old.md'));
      for (final d in dirs) {
        expect(
          FileSystemEntity.isLinkSync(p.join(project, d, 'references/old.md')),
          isTrue,
        );
      }
      expect(target.readAsStringSync(), 'old');
      // a link to nothing is the same
      File(p.join(project, 'elsewhere.md')).deleteSync();
      final dangling = await agents();
      expect(dangling.exitCode, 0, reason: '${dangling.stderr}');
      expect(dangling.stdout, contains('$dir/references/old.md'));
    });

    test('a file in no manifest stays, and is named', () async {
      await agents();
      File(
        p.join(project, '.agents/skills/twk/notes.md'),
      ).writeAsStringSync('mine');
      final result = await agents();
      expect(read('.agents/skills/twk/notes.md'), 'mine');
      expect(result.stdout, contains('.agents/skills/twk/notes.md'));
    });

    test('with no manifest nothing is removed', () async {
      await oldPack('references/old.md', 'old');
      for (final dir in dirs) {
        File(p.join(project, dir, agentsManifest)).deleteSync();
      }
      File(
        p.join(project, '.claude/skills/twk/SKILL.md'),
      ).writeAsStringSync('an older skill\n');
      final result = await agents();
      expect(result.exitCode, 0);
      for (final dir in dirs) {
        expect(has('$dir/references/old.md'), isTrue, reason: dir);
      }
      expect(result.stdout, contains('references/old.md'));
    });

    test('where the pack is there with no manifest, one is written and no '
        "other file, so that the project's edits stay from then on", () async {
      await agents();
      for (final dir in dirs) {
        File(p.join(project, dir, agentsManifest)).deleteSync();
      }
      final result = await agents();
      expect(result.stdout, contains('wrote its manifest'));
      expect(result.stdout, isNot(contains('nothing to do')));
      for (final dir in dirs) {
        expect(has('$dir/$agentsManifest'), isTrue, reason: dir);
      }
      final before = snapshot(project);
      expect((await agents()).stdout, contains('nothing to do'));
      expectSame(snapshot(project), before);

      const edit = 'the project wrote this\n';
      final skill = File(p.join(project, dirs.first, 'SKILL.md'))
        ..writeAsStringSync(edit);
      await agents();
      expect(skill.readAsStringSync(), edit);
    });

    test('with no manifest a file that differs from the pack stays, and is '
        'named: nothing says a run wrote it', () async {
      await agents();
      for (final dir in dirs) {
        File(p.join(project, dir, agentsManifest)).deleteSync();
      }
      const copied = 'copied by hand\n';
      final skill = File(p.join(project, dirs.first, 'SKILL.md'))
        ..writeAsStringSync(copied);
      final result = await agents();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(skill.readAsStringSync(), copied);
      expect(result.stdout, contains('${dirs.first}/SKILL.md'));
      // deleted, it is the skill's again
      skill.deleteSync();
      await agents();
      expect(skill.readAsStringSync(), isNot(copied));
    });
  });

  group('AGENTS.md of the project own', () {
    const head = '# Rules\n\nUse tabs.\n\n';
    const tail = '\n## Tail\n\nThe end, no final break.';

    test('twk block is appended, the text kept to the byte', () async {
      File(p.join(project, 'AGENTS.md')).writeAsStringSync(
        '${head}Last line, no break',
      );
      final dry = await agents(['--dry-run']);
      expect(dry.stdout, contains('would add the block'));
      final result = await agents();
      expect(result.stdout, contains('added the block'));
      expect(result.stdout, isNot(contains('changed the block')));
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
      // the manifest is the project's record, no file of the pack
      expectSame(
        snapshot(p.join(project, '.agents/skills/twk'))..remove(agentsManifest),
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
