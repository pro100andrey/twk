// Compiles small apps for the web, dart2wasm's WasmGC (dart2js compiles
// the core too, but its Uint64List and Int64List throw once run), and
// makes sure nothing of a process came with them: each case's app is
// compiled with `dart compile wasm`; every library of a package the
// compiler read (the SDK's left out) is looked at for an import or export
// of dart:io, dart:ffi, dart:isolate or dart:mirrors, since dart2wasm
// compiles dart:io in as stubs that throw once run; then the build is run
// in node (22 or later, for WasmGC; no flags) and must print `done` last.
// Each case has a bound, set here and nowhere else: its app is handed it
// as its one argument, in milliseconds, to stop at and say where it
// stopped, and the run is killed [_exit] after it, so what the app says
// is in the output. The bound starts when the app's main does: node's
// start and the build's load and compile before it have a bound of their
// own, [_load], and a run stopped anywhere says the last stage it
// reached.
//
//   dart run tool/web_check.dart            # every case
//   dart run tool/web_check.dart core       # these only
//
// The cases, each of which must pass: core,
// packages/twk_core/test/web/core_app.dart (a TwkApp on a
// HeadlessTerminal, a Terminal over a link of its own); twk,
// packages/twk/test/platform/web_app.dart (runApp of a FilePicker on a
// Terminal over a link of its own, the log console saved); twk_web,
// packages/twk_web/test/web/run_web_app.dart (runWebApp on a stand-in for
// xterm.js, packages/twk_web/test/web/xterm_stub.mjs, which node loads
// before the app, since it has no page); gallery,
// packages/gallery/test/web/gallery_app.dart (every page of the gallery
// on the same stand-in, none showing an error, the Images page's PNG
// decoded without dart:io). A line per case
// and step gives its outcome and how long it took, the output of a step
// that failed or what it found following, indented. Exit status 1 when a
// case failed; 2 when none failed but one was not run (no node, or one too
// old), which is no pass; 64 for an unknown case.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _usage = 'usage: dart run tool/web_check.dart [CASE...]';

/// The libraries no library of a web app may import or export.
const _forbidden = ['io', 'ffi', 'isolate', 'mirrors'];

/// The oldest node with WasmGC on by default.
const _nodeMajor = 22;

/// How long a run may go on after its app's bound: the app to say where it
/// stopped and node to exit.
const _exit = Duration(seconds: 10);

/// How long node may take to start and to load, compile and instantiate a
/// build, before its app's main and the app's bound start: the 10 s it had
/// when one bound counted both. A run on windows-latest once ended at that
/// bound saying nothing, its cause not found; the stages are there to say
/// where the next one stops, not to wait it out.
const _load = Duration(seconds: 10);

/// What the runner writes to stderr before each of its stages, the stage
/// after it; [_mainStage] last, as the app's main is called.
const _stage = 'web_check stage: ';
const _mainStage = 'main';

/// An app to compile: [entry], relative to the root; its packages are
/// those [package] resolves with (`_packageConfig`). [prelude], a
/// module relative to the root, is loaded before it is run. [bound], how
/// long the app may take: handed to its main as its one argument, in
/// milliseconds; the run is killed [_exit] after it.
final class _Case {
  const _Case(
    this.name,
    this.package,
    this.entry, {
    required this.bound,
    this.prelude,
  });

  final String name;
  final String package;
  final String entry;
  final Duration bound;
  final String? prelude;
}

const _cases = [
  _Case(
    'core',
    'packages/twk_core',
    'packages/twk_core/test/web/core_app.dart',
    bound: Duration(seconds: 5),
  ),
  _Case(
    'twk',
    'packages/twk',
    'packages/twk/test/platform/web_app.dart',
    bound: Duration(seconds: 5),
  ),
  _Case(
    'twk_web',
    'packages/twk_web',
    'packages/twk_web/test/web/run_web_app.dart',
    bound: Duration(seconds: 5),
    prelude: 'packages/twk_web/test/web/xterm_stub.mjs',
  ),
  // some forty pages, each a frame
  _Case(
    'gallery',
    'packages/gallery',
    'packages/gallery/test/web/gallery_app.dart',
    bound: Duration(seconds: 20),
    prelude: 'packages/twk_web/test/web/xterm_stub.mjs',
  ),
];

/// Loads the prelude, if any, and the build, and runs its main with the
/// case's bound, in milliseconds:
/// `node run.mjs app.mjs app.wasm bound [prelude.mjs]`. The modules by
/// their file: URLs, which an import takes on Windows too, where a path
/// (`C:\...`) reads as a URL of the scheme `c:`. Before each stage it
/// writes [_stage] and the stage to stderr, at once (`writeSync`, which a
/// kill does not lose, as it may a `console` write to a pipe on Windows).
const _runner =
    '''
import { writeSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
const stage = (s) => writeSync(2, '$_stage' + s + '\\n');
const [mjs, wasm, bound, prelude] = process.argv.slice(2);
if (prelude) {
  stage('prelude');
  await import(pathToFileURL(prelude).href);
}
stage('import');
const app = await import(pathToFileURL(mjs).href);
stage('read');
const bytes = await readFile(wasm);
stage('compile');
const compiled = await app.compile(bytes);
stage('instantiate');
const instance = await compiled.instantiate({});
stage('$_mainStage');
instance.invokeMain(bound);
''';

enum _Outcome { passed, failed, skipped }

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln(_usage);
    return;
  }
  final names = _cases.map((c) => c.name).toList();
  final unknown = args.where((a) => !names.contains(a)).toList();
  if (unknown.isNotEmpty) {
    stderr
      ..writeln('no case ${unknown.join(', ')} (${names.join(', ')})')
      ..writeln(_usage);
    exitCode = 64;
    return;
  }
  final root = Directory.fromUri(Platform.script.resolve('..')).absolute;
  final sdk = File(Platform.resolvedExecutable).parent.parent.path;
  final (node, noNode) = await _node();
  final temp = Directory.systemTemp.createTempSync('web_check');
  final failed = <String>[];
  final skipped = <String>[];
  try {
    for (final c in _cases) {
      if (args.isNotEmpty && !args.contains(c.name)) {
        continue;
      }
      final outcome = await _check(c, root.path, sdk, node, noNode, temp.path);
      if (outcome == _Outcome.failed) {
        failed.add(c.name);
      } else if (outcome == _Outcome.skipped) {
        skipped.add(c.name);
      }
    }
  } finally {
    temp.deleteSync(recursive: true);
  }
  if (failed.isNotEmpty) {
    stdout.writeln('failed: ${failed.join(', ')}');
    exitCode = 1;
  } else if (skipped.isNotEmpty) {
    stdout.writeln('not run: ${skipped.join(', ')} ($noNode)');
    exitCode = 2;
  }
}

/// The `.dart_tool/package_config.json` that [package], a directory
/// relative to [root], resolves its imports with: the nearest from it up,
/// which for a member of the pub workspace is the root's. The root's when
/// there is none yet, for the message that says to run `dart pub get`.
String _packageConfig(String root, String package) {
  for (var dir = package; ;) {
    final file = '$root/$dir/.dart_tool/package_config.json';
    if (dir == '.' || File(file).existsSync()) {
      return file;
    }
    final up = dir.lastIndexOf('/');
    dir = up < 0 ? '.' : dir.substring(0, up);
  }
}

/// Compiles, scans and runs [c] (in [node]; not when null, for [noNode]).
Future<_Outcome> _check(
  _Case c,
  String root,
  String sdk,
  String? node,
  String noNode,
  String temp,
) async {
  final out = Directory('$temp/${c.name}')..createSync();
  // the longest case name: the steps of every case line up
  final width = _cases.fold(0, (w, k) => k.name.length > w ? k.name.length : w);
  final packages = _packageConfig(root, c.package);
  final entry = '$root/${c.entry}';
  void say(String step, String outcome, Duration took, [String more = '']) {
    final seconds = (took.inMilliseconds / 1000).toStringAsFixed(1);
    stdout.writeln(
      '${c.name.padRight(width)} ${step.padRight(5)} ${outcome.padRight(7)} '
      '${seconds.padLeft(5)} s',
    );
    for (final line in const LineSplitter().convert(more)) {
      if (line.trim().isNotEmpty) {
        stdout.writeln('    $line');
      }
    }
  }

  if (!File(packages).existsSync()) {
    say('pub', 'FAILED', Duration.zero, 'no $packages: dart pub get there');
    return _Outcome.failed;
  }
  final wasm = await _run('dart', [
    'compile',
    'wasm',
    '--packages=$packages',
    '--depfile=${out.path}/app.wasm.d',
    '-o',
    '${out.path}/app.wasm',
    entry,
  ]);
  say('wasm', wasm.ok ? 'ok' : 'FAILED', wasm.took, wasm.ok ? '' : wasm.output);
  if (!wasm.ok) {
    return _Outcome.failed;
  }
  final watch = Stopwatch()..start();
  final read = [
    for (final path in _depfile(File('${out.path}/app.wasm.d')))
      if (path.endsWith('.dart') && !path.startsWith(sdk)) path,
  ]..sort();
  final found = [for (final path in read) ..._imports(path, root)];
  say(
    'io',
    found.isEmpty ? 'ok' : 'FAILED',
    watch.elapsed,
    found.isEmpty
        ? '${read.length} libraries, none imports '
              '${_forbidden.map((l) => 'dart:$l').join(', ')}'
        : found.join('\n'),
  );
  if (node == null) {
    say('run', 'skipped', Duration.zero, noNode);
    return found.isEmpty ? _Outcome.skipped : _Outcome.failed;
  }
  final runner = File('${out.path}/run.mjs')..writeAsStringSync(_runner);
  final run = await _runApp(node, [
    runner.path,
    '${out.path}/app.mjs',
    '${out.path}/app.wasm',
    '${c.bound.inMilliseconds}',
    if (c.prelude case final prelude?) '$root/$prelude',
  ], c.bound + _exit);
  final lines = const LineSplitter()
      .convert(run.output)
      .where((l) => l.trim().isNotEmpty && !l.startsWith(_stage));
  final ran = run.ok && lines.isNotEmpty && lines.last == 'done';
  say('run', ran ? 'ok' : 'FAILED', run.took, ran ? '' : run.output);
  return found.isEmpty && ran ? _Outcome.passed : _Outcome.failed;
}

/// The paths a Ninja depfile names after its target's colon; a space in a
/// path is escaped with a backslash.
List<String> _depfile(File depfile) {
  final text = depfile.readAsStringSync();
  final paths = <String>[];
  final path = StringBuffer();
  for (var i = text.indexOf(': ') + 2; i < text.length; i++) {
    final c = text[i];
    if (c == r'\' && i + 1 < text.length) {
      path.write(text[++i]);
    } else if (c == ' ' || c == '\n') {
      if (path.isNotEmpty) {
        paths.add(path.toString());
        path.clear();
      }
    } else {
      path.write(c);
    }
  }
  if (path.isNotEmpty) {
    paths.add(path.toString());
  }
  return paths;
}

final _directive = RegExp(
  '^\\s*(import|export)\\s+[\'"]dart:(${_forbidden.join('|')})[\'"]',
  multiLine: true,
);

/// A line that starts a declaration: at its start, and none of a
/// directive, a comment or an annotation. A library's directives come
/// before its declarations, so what follows one (a string holding a
/// program, as a gallery page's sample) is no import.
final _declaration = RegExp(
  r'^(?!import\b|export\b|library\b|part\b|//|/\*|@|#!)[A-Za-z_]',
  multiLine: true,
);

/// Where the library at [path] imports or exports a forbidden library:
/// `path:line: import 'dart:io'`, the path relative to [root].
Iterable<String> _imports(String path, String root) sync* {
  final whole = File(path).readAsStringSync();
  final text = switch (_declaration.firstMatch(whole)) {
    final m? => whole.substring(0, m.start),
    null => whole,
  };
  final shown = path.startsWith('$root/')
      ? path.substring(root.length + 1)
      : path;
  for (final m in _directive.allMatches(text)) {
    final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
    yield "$shown:$line: ${m[1]} 'dart:${m[2]}'";
  }
}

/// The node to run the builds in, or null and why there is none: not on
/// the PATH, or older than [_nodeMajor].
Future<(String?, String)> _node() async {
  try {
    final r = await Process.run('node', ['--version']);
    final version = (r.stdout as String).trim();
    final major = int.tryParse(
      RegExp(r'^v(\d+)\.').firstMatch(version)?[1] ?? '',
    );
    if (r.exitCode != 0 || major == null) {
      return (null, 'node --version failed: $version${r.stderr}');
    }
    return major < _nodeMajor
        ? (null, 'node $version: WasmGC needs $_nodeMajor or later')
        : ('node', 'node $version');
  } on ProcessException {
    return (null, 'no node on the PATH');
  }
}

/// What running [executable] with [args] gave: whether it exited with 0,
/// its stdout and stderr together, how long it took.
Future<({bool ok, String output, Duration took})> _run(
  String executable,
  List<String> args, {
  Duration timeout = const Duration(minutes: 5),
}) async {
  final watch = Stopwatch()..start();
  final process = await Process.start(executable, args);
  final output = StringBuffer();
  final done = [
    process.stdout.transform(utf8.decoder).forEach(output.write),
    process.stderr.transform(utf8.decoder).forEach(output.write),
  ];
  final code = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      process.kill();
      output.write('\ntimed out after ${timeout.inSeconds} s');
      return -1;
    },
  );
  await Future.wait(done);
  return (ok: code == 0, output: output.toString(), took: watch.elapsed);
}

/// What running a build with [node] and the runner's [args] gave, as
/// [_run] tells it: killed [_load] after its start while the runner has
/// not reached the app's main, or [bound] after it did, saying in the
/// output which bound it was and the last stage the runner reached.
Future<({bool ok, String output, Duration took})> _runApp(
  String node,
  List<String> args,
  Duration bound,
) async {
  final watch = Stopwatch()..start();
  final process = await Process.start(node, args);
  final output = StringBuffer();
  var stage = 'start';
  final started = Completer<void>();
  void line(String l) {
    output.writeln(l);
    if (l.startsWith(_stage)) {
      stage = l.substring(_stage.length).trim();
      if (stage == _mainStage && !started.isCompleted) {
        started.complete();
      }
    }
  }

  final done = [
    process.stdout.transform(utf8.decoder).forEach(output.write),
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(line),
  ];
  final exited = process.exitCode;
  Timer? kill;
  void killAfter(Duration after, String what) {
    kill?.cancel();
    kill = Timer(after, () {
      process.kill();
      output.write(
        '\ntimed out: $what after ${after.inSeconds} s, at the stage $stage',
      );
    });
  }

  killAfter(_load, "node did not reach the app's main");
  unawaited(
    started.future.then(
      (_) => killAfter(bound, 'the app did not end within its bound'),
    ),
  );
  final code = await exited;
  kill?.cancel();
  await Future.wait(done);
  return (ok: code == 0, output: output.toString(), took: watch.elapsed);
}
