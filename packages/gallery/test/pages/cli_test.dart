// App › Cli: the console programs of lib/cli/ run on twk_test's fake
// terminal, their screens at the gallery's time, and the Code tab each
// program's file.
import 'dart:io';

import 'package:gallery/cli/check.dart' as check;
import 'package:gallery/cli/create.dart' as create;
import 'package:gallery/cli/install.dart' as install;
import 'package:gallery/cli/run.dart';
import 'package:gallery/gallery.dart';
import 'package:gallery/src/pages/cli_code.dart';
import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart';

const _programs = <String, CliProgram>{
  'create': create.create,
  'install': install.install,
  'check': check.check,
};

/// The screen of [name]'s run at [ms], the clock standing still there,
/// on a terminal of [size].
Future<List<String>> _at(
  TwkTester t,
  String name,
  int ms, {
  (int, int) size = (60, 20),
}) async {
  await t.pumpWidget(
    CliRun(
      script: cliScripts[name]!,
      program: _programs[name]!,
      at: Duration(milliseconds: ms),
    ),
    size: size,
  );
  await t.pump(const Duration(milliseconds: 100));
  return t.lines;
}

void main() {
  test("each program's Code is its file", () {
    for (final name in _programs.keys) {
      expect(
        cliCode[name],
        File('lib/cli/$name.dart').readAsStringSync(),
        reason:
            '$name: lib/src/pages/cli_code.dart is to have lib/cli/$name.dart '
            'as it is',
      );
    }
  });

  group('create', () {
    testTwk('a refused name shows under the field', (t) async {
      final lines = await _at(t, 'create', 1000);
      expect(lines[0], r'$ dart run lib/cli/create.dart');
      expect(lines[1], '? Project name? (my_app) todo cli');
      expect(lines[2], '✗ lowercase letters, digits and _');
    });

    testTwk('an answered question leaves its line, the next asked', (
      t,
    ) async {
      final lines = await _at(t, 'create', 2000);
      expect(lines.sublist(1, 4), [
        '✔ Project name? todo_cli',
        '? Template?',
        '▎console',
      ]);
    });

    testTwk('every answer a line once done, the shell after it', (t) async {
      final lines = await _at(t, 'create', 4500);
      expect(lines.sublist(1, 8), [
        '✔ Project name? todo_cli',
        '✔ Template? server',
        '✔ Features? Linter, Tests',
        '✔ Create todo_cli? yes',
        'Created todo_cli from server with Linter, Tests',
        r'$',
        '',
      ]);
    });
  });

  group('install', () {
    testTwk('a line logged lands above the live tasks', (t) async {
      final lines = await _at(t, 'install', 2000);
      expect(lines[1], '✓ Resolved 4 packages in 0.6 s');
      expect(lines[2], 'compiled 118 libraries');
      expect(lines[3], startsWith('⠴ assets.zip '));
      expect(lines[3], contains('76% • 1.3 MB/s'));
      expect(lines[4], startsWith('✓ fonts.tar '));
      expect(lines[5], startsWith('⠴ Compiling '));
    });

    testTwk('the list as it ended is committed in its place', (t) async {
      final lines = await _at(t, 'install', 4500);
      expect(lines[3], startsWith('✓ assets.zip '));
      expect(lines[3], endsWith('100% • 1.8 s'));
      expect(lines[6], 'Installed in build/app.');
      expect(lines[7], r'$');
    });
  });

  testTwk('check: what it read, then the traceback at the line it threw', (
    t,
  ) async {
    final lines = await _at(t, 'check', 2000, size: (60, 24));
    expect(lines.sublist(1, 8), [
      '✓ Read twk.yaml in 0.4 s',
      'config:',
      '{',
      '  "version": 2,',
      '  "target": "web"',
      '}',
      '✗ StateError: Bad state: no "name" set',
    ]);
    expect(lines, contains('  lib/cli/check.dart:29:3'));
    expect(
      lines,
      contains('''  ▶ 29 │   throw StateError('no "name" set');'''),
    );
    expect(lines, contains(startsWith('  lib/cli/check.dart:22:')));
  });

  // the Code check runs the Code on the app's clock, the stage at a time
  // standing still: both show the same screen
  for (final (name, ms) in [('create', 2000), ('install', 2000)]) {
    group('$name at $ms ms', () {
      late List<String> still;
      testTwk('standing still', (t) async {
        still = await _at(t, name, ms);
      });
      testTwk('at the app time shows the same', (t) async {
        await t.pumpWidget(
          CliRun(script: cliScripts[name]!, program: _programs[name]!),
          size: (60, 20),
          duration: Duration.zero,
        );
        await t.pump(Duration(milliseconds: ms));
        expect(t.lines, still);
      });
    });
  }

  testTwk('the page runs it in a terminal on the stage', (t) async {
    await t.pumpWidget(
      galleryApp(route: GalleryRoute.parse('#/app/cli?t=2000')),
      size: (120, 36),
      duration: Duration.zero,
    );
    await t.pump(const Duration(milliseconds: 2000));
    final text = t.lines.join('\n');
    expect(text, contains('╭ terminal '));
    expect(text, contains(r'$ dart run lib/cli/create.dart'));
    expect(text, contains('✔ Project name? todo_cli'));
  });
}
