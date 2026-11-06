// The verbs xtask.yaml names: what its `run:` bodies can't say on their
// own. bin/xtask.dart hands them to the engine.
//
//   spare    ARGV...   runs ARGV on the CPUs the benchmark leaves
//   package  PATH ARGV...
//                      the same in the package PATH is in
//   tests    PATH [--joined=PACKAGE] ARGS...
//                      dart test ARGS there, or nothing, said so, where
//                      the package has no test/; in PACKAGE as group-tests
//   group-tests PATH [--groups=N] [--shuffle=SEED] ARGS...
//                      dart test ARGS there, the suite's files joined in
//                      generated entry points (test_groups.dart)
//   e2e      MODE      a demo in a pseudo-terminal, then its output through
//                      the test emulator (fullscreen or inline)
//   bench    [ARGS]    the frame benchmark, locked, pinned, its report read
//   browser  PATH ARGS...
//                      dart test -p chrome --compiler dart2wasm ARGS in the
//                      package PATH is in; skipped where there is no Chrome
//   vscode   STEP      the VS Code extension's install, compile or unit
//                      tests, in a copy of its own (vscode.dart)
//   pub      [--min=N] PATH...
//                      whether each package is ready for pub.dev: its
//                      publish dry-run and pana's score (pub_check.dart)
//   publish  PATH      the package at PATH published to pub.dev, after the
//                      checks an upload can't take back, waited for until
//                      the registry serves it, and tagged <name>-v<version>
//                      with its GitHub release (xtask_kit's)
//   tag-release PATH [COMMIT]
//                      the version of the package at PATH that COMMIT
//                      (HEAD) names, tagged there and released on GitHub
//                      (xtask_kit's): a version published before
import 'dart:io';

import 'package:xtask/xtask.dart';
import 'package:xtask_kit/xtask_kit.dart';

import 'bench.dart';
import 'cpus.dart';
import 'pub_check.dart';
import 'test_groups.dart';
import 'vscode.dart';

/// The verbs, by the names xtask.yaml gives them.
Map<String, Verb> verbs({Cpus? cpus}) {
  final host = cpus ?? Cpus.host();
  return {
    'spare': (c) => spare(c, host),
    'package': (c) => package(c, host),
    'tests': (c) => tests(c, host),
    'group-tests': (c) => groupTests(c, host),
    'e2e': (c) => e2e(c, host),
    'bench': (c) => bench(c, host),
    'browser': (c) => browser(c, host),
    'vscode': (c) => vscode(c, host),
    'pub': (c) => pubCheck(c, host),
    'publish': publish,
    'tag-release': pubTagRelease(),
  };
}

/// Publishes the package its one argument names, a path from the root,
/// as xtask_kit's pubPublish does: the changelog naming the version, the
/// package as HEAD has it, then the upload, and the version tagged
/// ([released]). A version pub.dev serves already is skipped, said so: the
/// packages go out in a chain, which a run again after one of them failed
/// takes up where it stopped, and a release bumps only some. [probe] asks
/// pub.dev what it serves.
Future<int> publish(
  VerbContext c, {
  RegistryProbe probe = askRegistry,
}) async {
  if (c.args.length != 1) {
    c.log('publish: give the package to publish, its path from the root');
    return ExitCode.invalidFile;
  }
  return pubPublish(released(c.args.single), probe: probe)(c);
}

/// The package at [directory] as [publish] publishes it:
///
/// - skipped where pub.dev serves its version already, as only some
///   packages are bumped in a release;
/// - tagged `<name>-v<version>` once uploaded, the tag pushed and released
///   on GitHub with its changelog entry, since the packages are released
///   apart (a version published before is tagged with `tag-release`);
/// - waited for until pub.dev serves it, every time: the next package's
///   check scores it with pana, which resolves its dev dependencies by
///   version too (twk_lints' tests take twk_test), and xtask_kit's
///   `needsUnserved` counts its dependencies alone.
PubPackage released(String directory) => PubPackage(
  directory,
  alreadyServed: AlreadyServed.skip,
  tag: releaseTagPattern,
);

/// [argv] prefixed with `taskset -c <spare CPUs>`, leaving the benchmark's
/// core and its sibling idle; unchanged where there is no such core, nothing
/// would be left, or taskset isn't installed.
List<String> offBenchCore(VerbContext c, Cpus cpus, List<String> argv) {
  final bench = Cpus.benchCpu(c.env);
  final left = bench == null ? null : cpus.spare(bench);
  if (left == null || c.which('taskset') == null) {
    return argv;
  }
  return ['taskset', '-c', formatCpuList(left), ...argv];
}

/// Runs its arguments, a program and its own, off the benchmark's core.
Future<int> spare(VerbContext c, Cpus cpus) async {
  if (c.args.isEmpty) {
    c.log('spare: give the program to run and its arguments');
    return ExitCode.invalidFile;
  }
  return answer(await c.run(offBenchCore(c, cpus, c.args)));
}

/// Runs a program off the benchmark's core in one package: its first
/// argument is a path in the package, relative to the root — `$each` of an
/// `each:` over the packages' pubspec.yaml files — and the rest are the
/// program and its own. The package is the nearest directory from there up
/// with a pubspec.yaml.
Future<int> package(VerbContext c, Cpus cpus) async {
  if (c.args.length < 2) {
    c.log(
      'package: give a path in the package, then the program to run in its '
      'directory and its arguments',
    );
    return ExitCode.invalidFile;
  }
  final [member, ...argv] = c.args;
  final dir = packageOf(c.root, member);
  if (dir == null) {
    c.log('package: no pubspec.yaml in $member or above it');
    return ExitCode.invalidFile;
  }
  c.log('$dir: ${argv.join(' ')}');
  return answer(
    await c.run(offBenchCore(c, cpus, argv), workingDirectory: dir),
  );
}

/// `dart test` and the arguments after its first, a path in the package as
/// [package] takes it, run in that package off the benchmark's core.
/// Skipped, and said so, where the package has no test/: `dart test` fails
/// there, and a package without tests is no failure of its tests.
Future<int> tests(VerbContext c, Cpus cpus) async {
  if (c.args.isEmpty) {
    c.log('tests: give a path in the package, then the arguments of dart test');
    return ExitCode.invalidFile;
  }
  final [member, ...given] = c.args;
  final dir = packageOf(c.root, member);
  if (dir == null) {
    c.log('tests: no pubspec.yaml in $member or above it');
    return ExitCode.invalidFile;
  }
  if (!Directory('${c.root}/$dir/test').existsSync()) {
    c.log('$dir: skipped, no test/');
    return ExitCode.success;
  }
  final args = [
    for (final arg in given)
      if (!arg.startsWith(_joined)) arg,
  ];
  // files named are run as they are
  if (given.contains('$_joined$dir') && args.every((a) => a.startsWith('-'))) {
    return _runGroups(c, cpus, dir, args);
  }
  final argv = ['dart', 'test', ...args];
  c.log('$dir: ${argv.join(' ')}');
  return answer(
    await c.run(offBenchCore(c, cpus, argv), workingDirectory: dir),
  );
}

/// The option of [tests] naming a package whose suite it runs in groups.
const _joined = '--joined=';

/// Runs the suite of the package its first argument is in as [tests] does,
/// its files joined in entry points written afresh (test_groups.dart) and
/// balanced by the last run's times. `--groups=N` and `--shuffle=SEED` are
/// for it, the other arguments `dart test`'s.
Future<int> groupTests(VerbContext c, Cpus cpus) async {
  if (c.args.isEmpty) {
    c.log('group-tests: give a path in the package, then dart test arguments');
    return ExitCode.invalidFile;
  }
  final [member, ...rest] = c.args;
  final dir = packageOf(c.root, member);
  if (dir == null) {
    c.log('group-tests: no pubspec.yaml in $member or above it');
    return ExitCode.invalidFile;
  }
  return _runGroups(c, cpus, dir, rest);
}

/// `dart test` with [args] in the package [dir], its files joined.
Future<int> _runGroups(
  VerbContext c,
  Cpus cpus,
  String dir,
  List<String> args,
) async {
  int? option(String name) => [
    for (final arg in args)
      if (arg.startsWith('--$name=')) int.parse(arg.split('=').last),
  ].lastOrNull;
  final package = Directory('${c.root}/$dir');
  final sources = testSources(package);
  final log = File('${package.path}/$timesFile');
  final plan = planGroups(
    sources,
    groups: option('groups') ?? 8,
    shuffle: option('shuffle'),
    times: log.existsSync() ? timesOf(log.readAsLinesSync()) : const {},
  );
  writeGroups(Directory('${package.path}/$groupsDirectory'), plan);
  c.log(
    '$dir: ${sources.length - plan.apart.length} files in '
    '${plan.groups.length} groups, ${plan.apart.length} apart',
  );
  final argv = [
    'dart',
    'test',
    '--file-reporter=json:$timesFile',
    for (final arg in args)
      if (!arg.startsWith('--groups=') && !arg.startsWith('--shuffle=')) arg,
    ...testArguments(plan, sources),
  ];
  return answer(
    await c.run(offBenchCore(c, cpus, argv), workingDirectory: dir),
  );
}

/// The directory, relative to [root], of the package [path] (relative to
/// [root]) is in: [path] itself or the nearest above it with a
/// pubspec.yaml; null when there is none below [root].
String? packageOf(String root, String path) {
  var dir = path.endsWith('/pubspec.yaml')
      ? path.substring(0, path.length - '/pubspec.yaml'.length)
      : path;
  while (!File('$root/$dir/pubspec.yaml').existsSync()) {
    final up = dir.lastIndexOf('/');
    if (up <= 0) {
      return null;
    }
    dir = dir.substring(0, up);
  }
  return dir;
}

/// The chat demo run in a pseudo-terminal (tool/pty_run.py: the tty back
/// in cooked mode, every mode turned off again), its output then replayed
/// into the test emulator (tool/replay.dart: no unsupported sequences,
/// wraps or unbalanced DEC 2026), fullscreen or inline. The capture goes to
/// a directory of its own, kept and named when a step failed.
Future<int> e2e(VerbContext c, Cpus cpus) async {
  final mode = c.args.length == 1 ? c.args.single : null;
  if (mode != 'fullscreen' && mode != 'inline') {
    c.log('e2e: give one mode, fullscreen or inline');
    return ExitCode.invalidFile;
  }
  final inline = mode == 'inline';
  final dir = Directory.systemTemp.createTempSync('twk_e2e_');
  final capture = '${dir.path}/$mode.bin';
  var code = await c.run(
    offBenchCore(c, cpus, [
      'python3',
      'tool/pty_run.py',
      if (inline) ...['--input', 'none'],
      '--out',
      capture,
      '--',
      'dart',
      'run',
      'packages/twk_core/example/chat_demo.dart',
      if (inline) '--inline',
      '--seconds=3',
    ]),
  );
  if (code == 0) {
    code = await c.run(
      offBenchCore(c, cpus, [
        'dart',
        'run',
        'tool/replay.dart',
        if (inline) '--inline' else '--fullscreen',
        capture,
        '100',
        '30',
      ]),
    );
  }
  if (code == 0) {
    dir.deleteSync(recursive: true);
  } else {
    c.log('e2e: the capture is kept in ${dir.path}');
  }
  return answer(code);
}

/// The names Chrome goes by, the first found the one the browser tests
/// run in where CHROME_EXECUTABLE names none.
const chromeNames = [
  'google-chrome-stable',
  'google-chrome',
  'chromium',
  'chromium-browser',
];

/// The Chrome to run the browser tests in: CHROME_EXECUTABLE where it is
/// set, else the first of [chromeNames] on the PATH; null when there is
/// none.
String? findChrome(VerbContext c) {
  final named = c.env['CHROME_EXECUTABLE'];
  if (named != null && named.isNotEmpty) {
    return c.which(named);
  }
  for (final name in chromeNames) {
    if (c.which(name) case final found?) {
      return found;
    }
  }
  return null;
}

/// The browser tests of a package: `dart test -p chrome --compiler
/// dart2wasm` and the arguments after its first, a path in the package
/// (relative to the root), run there off the benchmark's core with
/// CHROME_EXECUTABLE naming the Chrome [findChrome] found. Skipped, and
/// said so, where there is no Chrome; a test that needs the network fails
/// without it.
Future<int> browser(VerbContext c, Cpus cpus) async {
  if (c.args.isEmpty) {
    c.log('browser: give a path in the package, then the tests to run');
    return ExitCode.invalidFile;
  }
  final [member, ...tests] = c.args;
  final dir = packageOf(c.root, member);
  if (dir == null) {
    c.log('browser: no pubspec.yaml in $member or above it');
    return ExitCode.invalidFile;
  }
  final chrome = findChrome(c);
  if (chrome == null) {
    final named = c.env['CHROME_EXECUTABLE'];
    c.log(
      'browser: $dir: skipped, no Chrome '
      '${named != null && named.isNotEmpty ? '(CHROME_EXECUTABLE=$named is '
                'not there)' : '(none of ${chromeNames.join(', ')} on the '
                'PATH; CHROME_EXECUTABLE names another)'}',
    );
    return ExitCode.success;
  }
  c.log('$dir: dart test -p chrome --compiler dart2wasm in $chrome');
  return answer(
    await c.run(
      offBenchCore(c, cpus, [
        'env',
        'CHROME_EXECUTABLE=$chrome',
        'dart',
        'test',
        '-p',
        'chrome',
        '--compiler',
        'dart2wasm',
        '--reporter=failures-only',
        ...tests,
      ]),
      workingDirectory: dir,
    ),
  );
}

/// A program's exit status as the run's: a failure is 1, whatever number
/// the program gave it.
int answer(int code) =>
    code == ExitCode.success ? ExitCode.success : ExitCode.taskFailed;
