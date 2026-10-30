// The repository's xtask checks (xtask.yaml, tool/xtask.dart and its verbs
// in tool/xtask/): the per-package tasks run over a tree of their own —
// xtask.yaml copied into a pub workspace whose members are two fake
// packages under packages/, `good` and `bad` (a lint the analyzer reports
// as an info, a file `dart format` would change, a test/ without
// package:test), beside a template outside the workspace, resolved by
// itself, and a directory without a pubspec.yaml — and the verbs' own
// logic against fakes.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show runProcess;
import 'package:xtask/xtask.dart';

import '../../tool/xtask/bench.dart';
import '../../tool/xtask/cpus.dart';
import '../../tool/xtask/pub_check.dart';
import '../../tool/xtask/verbs.dart';
import '../../tool/xtask/vscode.dart';

void main() {
  group('over a tree of packages', () {
    late Directory tree;
    final entry = File('tool/xtask.dart').absolute.path;

    void write(String path, String text) => File('${tree.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);

    String pubspec(String name) => 'name: $name\nenvironment:\n  sdk: ^3.6.0\n';

    // a template, as twk_dev's are: a package of its own, no member
    const template = 'packages/twk_dev/templates/app';

    setUpAll(() {
      tree = Directory.systemTemp.createTempSync('xtask_checks');
      File('xtask.yaml').copySync('${tree.path}/xtask.yaml');
      write(
        'pubspec.yaml',
        '${pubspec('root')}workspace:\n'
            '  - packages/good\n'
            '  - packages/bad\n',
      );
      // what the `plugin` task analyzes
      write('tool/xtask.dart', 'void main() {}\n');
      write(
        'packages/good/pubspec.yaml',
        '${pubspec('good')}resolution: workspace\n',
      );
      write('packages/good/lib/good.dart', 'int answer() => 42;\n');
      write(
        'packages/bad/pubspec.yaml',
        '${pubspec('bad')}resolution: workspace\n',
      );
      write('$template/pubspec.yaml', pubspec('app'));
      write('$template/lib/app.dart', 'int answer() => 42;\n');
      write(
        'packages/bad/analysis_options.yaml',
        'linter:\n  rules:\n    - prefer_single_quotes\n',
      );
      write('packages/bad/lib/bad.dart', 'String  name( ) =>"bad";\n');
      write('packages/bad/test/bad_test.dart', 'void main() {}\n');
      write('packages/notes/README.md', 'not a package\n');
    });
    tearDownAll(() => tree.deleteSync(recursive: true));

    Future<ProcessResult> xtask(
      List<String> args, {
      Map<String, String> env = const {},
    }) => runProcess(
      Platform.resolvedExecutable,
      [entry, ...args],
      workingDirectory: tree.path,
      // its output as on a terminal of a developer's, not GitHub's groups
      environment: {'GITHUB_ACTIONS': '', ...env},
    );

    String out(ProcessResult res) => '${res.stdout}${res.stderr}';

    test('analyze runs in every package with a pubspec.yaml after pub get, '
        'and a failure fails the task with its output', () async {
      final res = await xtask(['pkg-analyze', '--keep-going']);
      expect(res.exitCode, 1, reason: out(res));
      expect(
        res.stdout,
        stringContainsInOrder([
          // the workspace's one resolution, then the template's own
          '── get ──',
          'Got dependencies!',
          '$template: dart pub get',
          'packages/bad: dart analyze --fatal-infos',
          'info - lib/bad.dart:1:',
          'prefer_single_quotes',
          'packages/good: dart analyze --fatal-infos',
          'No issues found!',
          '$template: dart analyze --fatal-infos',
          'No issues found!',
          'error: task `pkg-analyze` at `packages/bad/pubspec.yaml`',
          'failed with exit code 1',
        ]),
      );
      expect(res.stdout, isNot(contains('notes')));
      // the members resolve at the root only
      expect(res.stdout, isNot(contains('packages/good: dart pub get')));
    });

    test('format fails on a file it would change, naming it', () async {
      final res = await xtask(['pkg-format', '--keep-going']);
      expect(res.exitCode, 1, reason: out(res));
      expect(
        res.stdout,
        stringContainsInOrder([
          'packages/bad: dart format',
          'Changed lib/bad.dart',
          'packages/good: dart format',
          'error: task `pkg-format` at `packages/bad/pubspec.yaml`',
        ]),
      );
    });

    test('tests run in the packages that have a test/, the others skipped '
        'and said so', () async {
      final res = await xtask(['pkg-test', '--keep-going']);
      expect(res.exitCode, 1, reason: out(res));
      expect(
        res.stdout,
        stringContainsInOrder([
          'packages/bad: dart test',
          'Could not find package `test`',
          'packages/good: skipped, no test/',
          'error: task `pkg-test` at `packages/bad/pubspec.yaml`',
        ]),
      );
      expect(res.stdout, isNot(contains('packages/good: dart test')));
    });

    for (final task in ['pkg-analyze', 'pkg-test']) {
      test('--only packages narrows $task', () async {
        final res = await xtask([task, '--only', 'packages=packages/good/*']);
        expect(res.exitCode, 0, reason: out(res));
        expect(res.stdout, contains('packages/good: '));
        expect(res.stdout, contains('1 of 3 members'));
        expect(res.stdout, isNot(contains('packages/bad')));
      });
    }

    test('--only with a pattern no package matches is refused', () async {
      final res = await xtask([
        'pkg-format',
        '--only',
        'packages=packages/good/*,packages/nope/*',
      ]);
      expect(res.exitCode, 2, reason: out(res));
      expect(res.stdout, contains('`packages/nope/*`'));
      expect(res.stdout, isNot(contains('packages/good: dart format')));
    });

    test('a template whose pub get fails is not analyzed', () async {
      const broken = 'packages/twk_dev/templates/broken';
      write(
        '$broken/pubspec.yaml',
        '${pubspec('broken')}dependencies:\n  gone:\n    path: ../gone\n',
      );
      addTearDown(
        () => Directory('${tree.path}/$broken').deleteSync(recursive: true),
      );
      final res = await xtask([
        'pkg-analyze',
        '--keep-going',
        '--only',
        'packages=$broken/*',
      ]);
      expect(res.exitCode, 1, reason: out(res));
      expect(
        res.stdout,
        contains('error: task `pkg-get` at `$broken/pubspec.yaml`'),
      );
      expect(res.stdout, isNot(contains('broken: dart analyze')));
    });
    // each test starts xtask and dart programs: under a loaded machine
    // (the fleet's handovers at once, group: true) 30 seconds is not enough
  }, timeout: const Timeout.factor(4));

  test("the repository's xtask.yaml is valid, its verbs registered", () async {
    final res = await runProcess(Platform.resolvedExecutable, [
      'tool/xtask.dart',
      '--validate',
    ], group: true);
    expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
    expect(res.stdout, contains('nothing wrong'));
  });

  group('cpus', () {
    test('lists parse and print as taskset takes them', () {
      expect(parseCpuList('0-10,12-22\n'), {
        for (var c = 0; c <= 22; c++)
          if (c != 11) c,
      });
      expect(parseCpuList('11,23'), {11, 23});
      expect(parseCpuList('3-1'), isNull);
      expect(parseCpuList('a'), isNull);
      expect(formatCpuList({0, 1, 2, 3, 5, 7, 8}), '0-3,5,7-8');
      expect(formatCpuList(parseCpuList('0-10,12-22')!), '0-10,12-22');
    });

    test('the spare CPUs leave out the bench core and its sibling', () {
      final cpus = Cpus(
        allowed: parseCpuList('0-23'),
        siblings: (c) => c == 23 ? {11, 23} : null,
      );
      expect(formatCpuList(cpus.spare(23)!), '0-10,12-22');
      expect(cpus.spare(30), isNull, reason: 'not online');
      final pinned = Cpus(allowed: {23}, siblings: (c) => {11, 23});
      expect(pinned.spare(23), isNull, reason: 'nothing left');
      expect(Cpus.benchCpu(const {}), 23);
      expect(Cpus.benchCpu(const {'BENCH_CPU': '7'}), 7);
    });
  });

  group('verbs', () {
    final cpus = Cpus(
      allowed: parseCpuList('0-23'),
      siblings: (c) => c == 23 ? {11, 23} : null,
    );

    ({
      VerbContext context,
      List<List<String>> ran,
      List<String> log,
      List<String> shown,
    })
    fake(
      List<String> args, {
      Map<String, String> env = const {},
      Set<String> installed = const {'taskset', 'flock'},
      String report = '',
      String? root,
    }) {
      final ran = <List<String>>[];
      final log = <String>[];
      final shown = <String>[];
      return (
        context: VerbContext(
          args: args,
          env: env,
          root: root ?? Directory.current.path,
          workingDirectory: root ?? Directory.current.path,
          log: log.add,
          start: (argv, {workingDirectory}) async {
            ran.add(argv);
            return 0;
          },
          locate: (name, {workingDirectory}) =>
              installed.contains(name) ? '/usr/bin/$name' : null,
          collect: (argv, {workingDirectory, timeout}) async {
            ran.add(argv);
            return (exitCode: 0, stdout: report, stderr: '');
          },
          // as the engine's: each line through log as it comes, then kept
          relay: (argv, {workingDirectory, timeout}) async {
            ran.add(argv);
            for (final line in report.split('\n').where((l) => l.isNotEmpty)) {
              shown.add(line);
              log.add(line);
            }
            return (exitCode: 0, stdout: report, stderr: '');
          },
        ),
        ran: ran,
        log: log,
        shown: shown,
      );
    }

    test('spare runs off the bench core where taskset is there', () async {
      final f = fake(['dart', 'test']);
      expect(await spare(f.context, cpus), 0);
      expect(f.ran.single, ['taskset', '-c', '0-10,12-22', 'dart', 'test']);

      final bare = fake(['dart', 'test'], installed: const {});
      await spare(bare.context, cpus);
      expect(bare.ran.single, ['dart', 'test']);
    });

    test('publish takes one package, uploads nothing where a check before '
        'the upload fails, and skips a version pub.dev serves', () async {
      Future<Set<String>> none(String registry, String package) async => {};
      for (final args in [
        <String>[],
        ['packages/twk', 'packages/twk_core'],
      ]) {
        final f = fake(args);
        expect(await publish(f.context, probe: none), ExitCode.invalidFile);
        expect(f.ran, isEmpty);
      }
      // the dry run lists no files: what would go up is not known
      final f = fake(['packages/twk_core']);
      expect(await publish(f.context, probe: none), ExitCode.taskFailed);
      expect(
        f.ran,
        anyElement(equals(['dart', 'pub', 'publish', '--dry-run'])),
      );
      expect(f.ran, isNot(anyElement(contains('--force'))));
      // the version of its pubspec served already: nothing else asked
      final version = RegExp(r'^version: (\S+)$', multiLine: true).firstMatch(
        File('packages/twk_core/pubspec.yaml').readAsStringSync(),
      )![1]!;
      final out = fake(['packages/twk_core']);
      expect(
        await publish(out.context, probe: (_, _) async => {version}),
        ExitCode.success,
      );
      expect(out.ran, isEmpty);
    });

    test('package runs in the package of the path it is given', () {
      final root = Directory.current.path;
      expect(packageOf(root, 'packages/twk/pubspec.yaml'), 'packages/twk');
      expect(packageOf(root, 'packages/twk/test'), 'packages/twk');
      expect(packageOf(root, 'nowhere/test'), isNull);
    });

    test('tests runs dart test in a package with a test/ and skips one '
        'without, saying so', () async {
      final f = fake(['packages/twk/pubspec.yaml', '--reporter=x']);
      expect(await tests(f.context, cpus), 0);
      expect(f.ran.single, [
        'taskset',
        '-c',
        '0-10,12-22',
        'dart',
        'test',
        '--reporter=x',
      ]);

      final none = fake(['tool/alloc/pubspec.yaml']);
      expect(await tests(none.context, cpus), 0);
      expect(none.ran, isEmpty);
      expect(none.log.single, 'tool/alloc: skipped, no test/');
    });

    test('browser runs the tests in the Chrome found, CHROME_EXECUTABLE '
        'first, and skips, saying so, where there is none', () async {
      const args = ['packages/twk_web', 'test/browser/'];
      final found = fake(
        args,
        installed: const {'taskset', 'env', 'chromium', 'google-chrome'},
      );
      expect(await browser(found.context, cpus), 0);
      expect(found.ran.single, [
        'taskset',
        '-c',
        '0-10,12-22',
        'env',
        'CHROME_EXECUTABLE=/usr/bin/google-chrome',
        'dart',
        'test',
        '-p',
        'chrome',
        '--compiler',
        'dart2wasm',
        '--reporter=failures-only',
        'test/browser/',
      ]);

      final named = fake(
        args,
        env: const {'CHROME_EXECUTABLE': 'chromium'},
        installed: const {'env', 'chromium', 'google-chrome'},
      );
      await browser(named.context, cpus);
      expect(named.ran.single[1], 'CHROME_EXECUTABLE=/usr/bin/chromium');

      for (final (env, why) in [
        (const <String, String>{}, 'none of google-chrome-stable'),
        (const {'CHROME_EXECUTABLE': '/no/chrome'}, '/no/chrome is not there'),
      ]) {
        final none = fake(args, env: env, installed: const {'env'});
        expect(await browser(none.context, cpus), 0);
        expect(none.ran, isEmpty);
        expect(none.log.single, contains('skipped, no Chrome'));
        expect(none.log.single, contains(why));
      }
    });

    test('bench runs locked, pinned, against HEAD or BENCH_BASELINE', () async {
      final f = fake(const [], report: _report());
      expect(await bench(f.context, cpus), 0);
      expect(f.ran.single, [
        'flock',
        defaultBenchLock,
        'taskset',
        '-c',
        '23',
        'dart',
        'run',
        'tool/bench.dart',
        '--baseline=HEAD',
      ]);

      final g = fake(
        ['--only=wrap'],
        env: const {'BENCH_BASELINE': 'abc123', 'BENCH_LOCK': '/tmp/x.lock'},
        installed: const {'flock'},
        report: _report(),
      );
      await bench(g.context, cpus);
      expect(g.ran.single, [
        'flock',
        '/tmp/x.lock',
        'dart',
        'run',
        'tool/bench.dart',
        '--baseline=abc123',
        '--only=wrap',
      ]);
      expect(g.log.first, contains('not pinned'));

      final h = fake(const ['--baseline=v1'], report: _report(bytes: 'wrap'));
      expect(await bench(h.context, cpus), 1);
      expect(h.ran.single.where((a) => a.startsWith('--baseline=')), [
        '--baseline=v1',
      ]);
    });

    test(
      'bench shows the report as it comes, once, then the verdict',
      () async {
        final f = fake(const [], report: _report(bytes: 'wrap'));
        expect(await bench(f.context, cpus), 1);
        final lines = _report(
          bytes: 'wrap',
        ).split('\n').where((l) => l.isNotEmpty);
        expect(f.shown, lines, reason: 'shown as it came, through tee');
        expect(f.log.first, isNot(contains('when it ends')));
        expect(f.log.skip(1).toList(), [
          ...lines,
          'bench: more bytes per frame in wrap',
        ]);
      },
    );
  });

  group('vscode', () {
    final cpus = Cpus(
      allowed: parseCpuList('0-23'),
      siblings: (c) => c == 23 ? {11, 23} : null,
    );
    const spare = ['taskset', '-c', '0-10,12-22'];
    late Directory root;

    void write(String path, String text) => File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    String read(String path) => File('${root.path}/$path').readAsStringSync();
    bool there(String path) =>
        FileSystemEntity.typeSync('${root.path}/$path') !=
        FileSystemEntityType.notFound;

    setUp(() {
      root = Directory.systemTemp.createTempSync('xtask_vscode');
      write('$vscodeSource/package.json', '{"name": "x"}\n');
      write('$vscodeSource/package-lock.json', '{"lockfileVersion": 3}\n');
      write('$vscodeSource/tsconfig.json', '{}\n');
      write('$vscodeSource/tsconfig.webview.json', '{}\n');
      write('$vscodeSource/src/core/wire.ts', 'export {};\n');
      // what the person runs the extension from: no step touches it
      write('$vscodeSource/out/vscode/extension.js', 'theirs\n');
      write('$vscodeSource/node_modules/@xterm/xterm/x.js', 'theirs\n');
    });
    tearDown(() => root.deleteSync(recursive: true));

    /// Runs the step [args], the programs it starts answering [answer].
    Future<({int code, List<List<String>> ran, List<String> log})> step(
      List<String> args, {
      Set<String> installed = const {'taskset', 'node', 'npm'},
      int answer = 0,
    }) async {
      final ran = <List<String>>[];
      final log = <String>[];
      final code = await vscode(
        VerbContext(
          args: args,
          env: const {},
          root: root.path,
          workingDirectory: root.path,
          log: log.add,
          start: (argv, {workingDirectory}) async {
            ran.add([...argv, 'in $workingDirectory']);
            return answer;
          },
          locate: (name, {workingDirectory}) =>
              installed.contains(name) ? '/usr/bin/$name' : null,
        ),
        cpus,
      );
      return (code: code, ran: ran, log: log);
    }

    tearDown(() {
      expect(read('$vscodeSource/out/vscode/extension.js'), 'theirs\n');
      expect(read('$vscodeSource/node_modules/@xterm/xterm/x.js'), 'theirs\n');
    });

    test('every step is skipped, said so, without node or npm', () async {
      for (final s in ['install', 'compile', 'unit']) {
        for (final installed in [
          const {'npm'},
          const {'node'},
        ]) {
          final r = await step([s], installed: installed);
          expect(r.code, 0);
          expect(r.ran, isEmpty);
          expect(r.log.single, contains('vscode $s: skipped, no '));
          expect(r.log.single, contains('on the PATH'));
        }
      }
      expect(there(vscodeGate), isFalse);
    });

    test('install without the manifests says which are missing and runs '
        'nothing', () async {
      File('${root.path}/$vscodeSource/package-lock.json').deleteSync();
      final r = await step(['install']);
      expect(r.code, isNot(0));
      expect(r.ran, isEmpty);
      expect(
        r.log.single,
        'no $vscodeSource/package-lock.json: nothing to '
        'install from',
      );
    });

    test('install runs npm ci in the copy, once per package-lock.json, '
        'and again after one that failed', () async {
      final first = await step(['install']);
      expect(first.code, 0);
      expect(first.ran.single, [
        ...spare,
        'npm',
        'ci',
        '--no-audit',
        '--no-fund',
        'in $vscodeGate',
      ]);
      expect(read('$vscodeGate/package-lock.json'), '{"lockfileVersion": 3}\n');

      final again = await step(['install']);
      expect(again.ran, isEmpty);
      expect(again.log.single, contains('up to date'));

      write('$vscodeSource/package-lock.json', '{"lockfileVersion": 4}\n');
      final failed = await step(['install'], answer: 3);
      expect(failed.code, 1);
      expect(failed.ran, hasLength(1));
      final retried = await step(['install']);
      expect(retried.ran, hasLength(1), reason: 'the failed one is no stamp');
      expect(read('$vscodeGate/package-lock.json'), '{"lockfileVersion": 4}\n');
    });

    test('compile copies the sources afresh, then npm run compile there; '
        'it needs install first', () async {
      final early = await step(['compile']);
      expect(early.code, 1);
      expect(early.log.single, contains('run vscode-install first'));

      await step(['install']);
      write('$vscodeGate/src/gone.ts', 'stale\n');
      write('$vscodeGate/out/gone.js', 'stale\n');
      final r = await step(['compile']);
      expect(r.code, 0);
      expect(r.ran.single, [
        ...spare,
        'npm',
        'run',
        'compile',
        'in $vscodeGate',
      ]);
      expect(read('$vscodeGate/src/core/wire.ts'), 'export {};\n');
      expect(there('$vscodeGate/tsconfig.webview.json'), isTrue);
      expect(there('$vscodeGate/src/gone.ts'), isFalse);
      expect(there('$vscodeGate/out'), isFalse, reason: 'tsc writes it anew');

      expect((await step(['compile'], answer: 2)).code, 1);
    });

    test("unit runs mocha over the compile's out/test/unit", () async {
      final early = await step(['unit']);
      expect(early.code, 1);
      expect(early.log.single, contains('run vscode-compile first'));

      write('$vscodeGate/out/test/unit/core/wire_golden.test.js', '\n');
      final r = await step(['unit', '--grep', 'golden']);
      expect(r.code, 0);
      expect(r.ran.single, [
        ...spare,
        'node',
        'node_modules/mocha/bin/mocha.js',
        'out/test/unit/**/*.test.js',
        '--grep',
        'golden',
        'in $vscodeGate',
      ]);
      expect((await step(['unit'], answer: 1)).code, 1);
    });

    test('a step it does not know is refused', () async {
      expect((await step(['test'])).code, ExitCode.invalidFile);
      expect((await step(const [])).code, ExitCode.invalidFile);
    });
  });

  group('the bench report', () {
    test('more bytes per frame fail', () {
      final r = judgeReport(_report(bytes: 'typing, wrap'));
      expect(r.failed, isTrue);
      expect(r.notes, ['bench: more bytes per frame in typing, wrap']);
    });

    test('slower fails when the sibling was idle', () {
      final r = judgeReport(_report(slower: 'wrap ×1.08'));
      expect(r.failed, isTrue);
      expect(r.notes.single, contains('slower by more than 5 %: wrap ×1.08'));
    });

    test('slower is noted, not failed, when the times do not count', () {
      const busy =
          'pinned to CPU 23 · sibling CPU 11 busy up to 31.0% — busy: the '
          'times are not reliable';
      for (final noise in [
        busy,
        'not pinned to a core: expect noise (taskset -c N)',
      ]) {
        final r = judgeReport(_report(slower: 'wrap ×1.08', noise: noise));
        expect(r.failed, isFalse, reason: noise);
        expect(r.notes.single, contains('do not count'));
      }
    });

    test('nothing worse passes; no baseline compares nothing', () {
      final quiet = judgeReport(_report());
      expect(quiet.failed, isFalse);
      expect(quiet.notes, ['bench: no more bytes, none slower']);
      expect(judgeReport('twk_core frame benchmark\n').notes, [
        'bench: no baseline, nothing compared',
      ]);
    });
  });

  group('pub check', () {
    test('publish_to: none is private, in any quoting', () {
      expect(isPrivate('name: a\npublish_to: none\n'), isTrue);
      expect(isPrivate("name: a\npublish_to: 'none' # not yet\n"), isTrue);
      expect(isPrivate('name: a\n# publish_to: none\n'), isFalse);
      expect(isPrivate('name: a\nversion: 0.1.0\n'), isFalse);
    });

    test('the dry run fails on an error, not on a warning', () {
      const files = '├── lib\n│   └── a.dart (<1 KB)\n';
      final warned = validationOf(
        '${files}Validating package...\n'
        'Package validation found the following potential issue:\n'
        '* Please add a `CHANGELOG.md` to your package.\n'
        '\n'
        'Package has 1 warning.\n',
        exitCode: 65,
      );
      expect(warned.hasErrors, isFalse);
      expect(warned.lines.first, 'Validating package...');
      expect(warned.lines, isNot(contains(contains('a.dart'))));

      final refused = validationOf(
        'Validating package...\n'
        'Package validation found the following error:\n'
        '* Use the hosted source for "twk_core", not the path source.\n'
        "Sorry, your package is missing a requirement and can't be "
        'published yet.\n',
      );
      expect(refused.hasErrors, isTrue);

      // failed before validating: what it said is no warning count
      final broken = validationOf(
        'Resolving dependencies...\n'
        'Because twk depends on twk_core ^9.0.0 which does not match any '
        'versions, version solving failed.\n',
        exitCode: 1,
      );
      expect(broken.hasErrors, isTrue);
      expect(validationOf('Package has 0 warnings.\n').hasErrors, isFalse);
    });

    test('code git tracks that the archive leaves out', () {
      // twk_dev's `.pubignore` once said `templates/`, which took
      // lib/src/templates/ out with the templates' sources
      expect(
        unshippedCode(
          ['lib/a.dart', 'bin/b.dart', 'README.md'],
          ['lib/a.dart', 'lib/src/templates/t.g.dart', 'bin/b.dart'],
        ),
        ['lib/src/templates/t.g.dart'],
      );
      expect(unshippedCode(['lib/a.dart'], ['lib/a.dart']), isEmpty);
    });

    test("screenshots need libwebp's tools, and only screenshots", () {
      const shots = 'name: a\nscreenshots:\n  - path: a.png\n';
      expect(screenshotTools(shots, (_) => false), [
        'cwebp',
        'webpinfo',
        'gif2webp',
      ]);
      expect(screenshotTools(shots, (tool) => tool != 'webpinfo'), [
        'webpinfo',
      ]);
      expect(screenshotTools('name: a\n', (_) => false), isEmpty);
    });

    test("pana's report: the score, and what lost points", () {
      final score = PanaScore.parse(
        'Resolving dependencies...\n'
        '${_pana(docs: '### [*] 10/10 points: 20% or more of the public '
            'API has dartdoc comments\n\n'
            '### [x] 0/10 points: Package has an example\n\n'
            '<details>\n<summary>\nNo example found.\n</summary>\n')}',
      )!;
      expect(score.granted, 150);
      expect(score.unpublished, isNull);
      expect(score.lines, [
        'pana: 150/160 points',
        '  10/20 Provide documentation',
        '    - 0/10 points: Package has an example',
        '      No example found.',
        '  140/140 Everything else',
      ]);
      expect(PanaScore.parse('Resolving dependencies...\n'), isNull);
    });

    test('a dependency pana cannot resolve is named', () {
      for (final at in ['https://pub.dev', '"../twk_core"']) {
        final score = PanaScore.parse(
          _pana(
            docs:
                '### [x] 0/10 points: dartdoc\n\nBecause twk depends on '
                "twk_core which doesn't exist (could not find package "
                'twk_core at $at), version solving failed.',
          ),
        )!;
        expect(score.unpublished, 'twk_core', reason: at);
      }
    });

    test("a package's dependencies of this repository by a version, its "
        'dev ones too, not those by a path or of pub.dev only', () {
      expect(
        repositoryDependencies(
          'name: twk_lints\n'
          'dependencies:\n'
          '  analyzer: ^14.7.0\n'
          '  twk_core: ^0.1.0\n'
          'dev_dependencies:\n'
          '  test: ^1.33.0\n'
          '  twk: ^0.1.0\n'
          '  twk_test:\n'
          '    path: ../twk_test\n'
          'dependency_overrides:\n'
          '  twk_term: ^0.1.0\n',
          {'twk', 'twk_core', 'twk_test', 'twk_term'},
        ),
        ['twk_core', 'twk'],
      );
    });

    test('--scored fails a package pana cannot score, its dependencies of '
        'this repository not on pub.dev yet', () async {
      final root = Directory.systemTemp.createTempSync('pub_check');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/packages/a/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('name: a\ndependencies:\n  b: ^0.1.0\n');
      File('${root.path}/packages/b/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('name: b\n');
      Future<int> check(List<String> args, List<String> log) => pubCheck(
        VerbContext(
          args: args,
          env: const {},
          root: root.path,
          workingDirectory: root.path,
          log: log.add,
          start: (argv, {workingDirectory}) async => 0,
          locate: (name, {workingDirectory}) => null,
          collect: (argv, {workingDirectory, timeout}) async => (
            // pana activated; b not on pub.dev
            exitCode: argv.first == 'curl' ? 22 : 0,
            stdout: argv.contains('list') ? 'pana 0.23.19\n' : '',
            stderr: '',
          ),
        ),
        Cpus(allowed: parseCpuList('0-3'), siblings: (_) => null),
      );
      final log = <String>[];
      expect(await check(const ['packages/a'], log), ExitCode.success);
      expect(
        log,
        contains(startsWith('packages/a: not scored, it depends on b')),
      );
      final scored = <String>[];
      expect(
        await check(const ['--scored', 'packages/a'], scored),
        ExitCode.taskFailed,
      );
      expect(scored, contains('packages/a: --scored, and pana gave no score'));
    });

    test('a private package is failed, the rest still run', () async {
      final root = Directory.systemTemp.createTempSync('pub_check');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/packages/a/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('name: a\npublish_to: none\n');
      final ran = <List<String>>[];
      final log = <String>[];
      final code = await pubCheck(
        VerbContext(
          args: const ['packages/a'],
          env: const {},
          root: root.path,
          workingDirectory: root.path,
          log: log.add,
          start: (argv, {workingDirectory}) async => 0,
          locate: (name, {workingDirectory}) => null,
          collect: (argv, {workingDirectory, timeout}) async {
            ran.add(argv);
            return (exitCode: 0, stdout: '', stderr: '');
          },
        ),
        Cpus(allowed: parseCpuList('0-3'), siblings: (_) => null),
      );
      expect(code, ExitCode.taskFailed);
      expect(log, contains('packages/a: publish_to: none, so not publishable'));
      expect(ran, contains(equals(['dart', 'pub', 'publish', '--dry-run'])));
      expect(log.last, contains('pana skipped, not activated'));
    });
  });
}

/// pana's `--json` report with a documentation section of [docs] (its
/// Markdown, as JSON writes it) and one section holding the other points.
String _pana({required String docs}) {
  final granted = docs.contains('### [x]') ? 10 : 20;
  return '{"scores": {"grantedPoints": ${granted + 140}, "maxPoints": 160},\n'
      ' "report": {"sections": [\n'
      '  {"title": "Provide documentation", "grantedPoints": $granted,\n'
      '   "maxPoints": 20, "summary": ${_json(docs)}},\n'
      '  {"title": "Everything else", "grantedPoints": 140,\n'
      '   "maxPoints": 140, "summary": ""}]}}\n';
}

String _json(String text) =>
    '"${text.replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';

/// The lines of a tool/bench.dart report against a baseline that
/// [judgeReport] reads.
String _report({
  String slower = 'none',
  String bytes = 'none',
  String noise = 'pinned to CPU 23 · sibling CPU 11 busy up to 0.4%',
}) =>
    'twk_core frame benchmark · 200x60 · AOT · 5 rounds · Dart 3.13.5\n'
    '$noise · load 1.2 → 1.3\n'
    'before: HEAD · after: working tree\n'
    '\n'
    'slower by more than 5%: $slower\n'
    'more bytes per frame: $bytes\n';
