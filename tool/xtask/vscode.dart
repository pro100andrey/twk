// The VS Code extension's checks (editors/vscode), in a copy of its own:
//
//   vscode install   npm ci there, once per package-lock.json
//   vscode compile   its sources copied there afresh, then npm run compile
//                    (tsc: a type error fails)
//   vscode unit      its unit tests, mocha over what compile wrote
//   vscode package   the .vsix (vsce), built there from what compile
//                    wrote, its file list held to what the extension
//                    needs and no more
//
// The copy is .dart_tool/vscode/ at the root, never editors/vscode: the
// person runs the extension from editors/vscode/out, which the webview
// loads @xterm from editors/vscode/node_modules beside, and an `npm ci`
// there deletes that node_modules before it writes the new one, under a
// panel that opens meanwhile. Its depth is editors/vscode's, so what a test
// finds by __dirname (wire_golden.test.ts: the golden, six directories up
// from out/test/unit/core) is where it is in editors/vscode. Each step is
// skipped, and said so, where node or npm is not on the PATH.
import 'dart:io';

import 'package:xtask/xtask.dart';

import 'cpus.dart';
import 'verbs.dart';

/// The extension, relative to the root.
const vscodeSource = 'editors/vscode';

/// The gate's copy of it, relative to the root.
const vscodeGate = '.dart_tool/vscode';

/// What `vscode install` copies before `npm ci`: what it installs from.
const _manifests = ['package.json', 'package-lock.json'];

/// What `vscode compile` copies afresh each time: what tsc reads.
const _sources = ['src', 'tsconfig.json', 'tsconfig.webview.json'];

/// What `vscode package` copies besides the sources: what goes in the .vsix
/// and what vsce reads to make it.
const _packaged = [
  'package.json',
  'README.md',
  'CHANGELOG.md',
  'LICENSE',
  'icon.png',
  '.vscodeignore',
];

/// The .vsix `vscode package` writes, relative to the gate's copy.
const vsixName = 'twk-vscode.vsix';

/// Paths the .vsix must hold (vsce lowercases readme.md and changelog.md and
/// names the licence LICENSE.txt): the entry, the webview's scripts and the three
/// files of xterm.js the page loads from node_modules.
const vsixRequired = [
  'extension/out/vscode/extension.js',
  'extension/out/media/webview/main.js',
  'extension/node_modules/@xterm/xterm/lib/xterm.js',
  'extension/node_modules/@xterm/xterm/css/xterm.css',
  'extension/node_modules/@xterm/addon-fit/lib/addon-fit.js',
  'extension/node_modules/@xterm/addon-image/lib/addon-image.js',
  'extension/readme.md',
  'extension/changelog.md',
  'extension/LICENSE.txt',
  'extension/package.json',
];

/// What the .vsix must not hold: sources, tests, maps, the rest of
/// node_modules.
final vsixForbidden = RegExp(
  r'^extension/(src/|out/test/|tool/|DESIGN\.md|tsconfig|package-lock|'
  r'node_modules/@types|node_modules/typescript|node_modules/mocha)'
  r'|\.map$',
);

/// Written beside the gate's node_modules when `npm ci` there succeeded:
/// the manifests it installed from, one after the other.
const _installed = 'node_modules/.xtask-installed';

/// The extension's checks: [c]'s first argument is the step (`install`,
/// `compile`, `unit` or `package`), the rest go to its program.
Future<int> vscode(VerbContext c, Cpus cpus) async {
  final step = c.args.isEmpty ? null : c.args.first;
  final rest = c.args.skip(1).toList();
  if (!const ['install', 'compile', 'unit', 'package'].contains(step)) {
    c.log('vscode: give the step, install, compile, unit or package');
    return ExitCode.invalidFile;
  }
  final missing = [
    for (final tool in ['node', 'npm'])
      if (c.which(tool) == null) tool,
  ];
  if (missing.isNotEmpty) {
    c.log(
      'vscode $step: skipped, no ${missing.join(' or ')} on the PATH '
      '(the extension in $vscodeSource is checked with node and npm)',
    );
    return ExitCode.success;
  }
  final source = Directory('${c.root}/$vscodeSource');
  final gate = Directory('${c.root}/$vscodeGate');
  switch (step) {
    case 'install':
      final missing = [
        for (final m in _manifests)
          if (!File('${source.path}/$m').existsSync()) '$vscodeSource/$m',
      ];
      if (missing.isNotEmpty) {
        c.log('no ${missing.join(' and ')}: nothing to install from');
        return ExitCode.invalidFile;
      }
      final wanted = _manifests
          .map((m) => File('${source.path}/$m').readAsStringSync())
          .join();
      final stamp = File('${gate.path}/$_installed');
      if (stamp.existsSync() && stamp.readAsStringSync() == wanted) {
        c.log('$vscodeGate: node_modules up to date with package-lock.json');
        return ExitCode.success;
      }
      gate.createSync(recursive: true);
      for (final m in _manifests) {
        File('${source.path}/$m').copySync('${gate.path}/$m');
      }
      c.log('$vscodeGate: npm ci');
      final code = await c.run(
        offBenchCore(c, cpus, ['npm', 'ci', '--no-audit', '--no-fund']),
        workingDirectory: vscodeGate,
      );
      if (code == ExitCode.success) {
        stamp
          ..createSync(recursive: true)
          ..writeAsStringSync(wanted);
      }
      return answer(code);
    case 'compile':
      if (!File('${gate.path}/$_installed').existsSync()) {
        c.log(
          'vscode compile: nothing installed in $vscodeGate; '
          'run vscode-install first',
        );
        return ExitCode.taskFailed;
      }
      for (final name in [..._sources, 'out']) {
        final there = '${gate.path}/$name';
        if (FileSystemEntity.typeSync(there) != FileSystemEntityType.notFound) {
          Directory(there).deleteSync(recursive: true);
        }
      }
      for (final name in _sources) {
        _copy('${source.path}/$name', '${gate.path}/$name');
      }
      c.log('$vscodeGate: npm run compile, $vscodeSource/src copied');
      return answer(
        await c.run(
          offBenchCore(c, cpus, ['npm', 'run', 'compile', ...rest]),
          workingDirectory: vscodeGate,
        ),
      );
    case 'package':
      if (!Directory('${gate.path}/out/vscode').existsSync()) {
        c.log(
          'vscode package: no out/ in $vscodeGate; '
          'run vscode-compile first',
        );
        return ExitCode.taskFailed;
      }
      for (final name in _packaged) {
        final from = File('${source.path}/$name');
        if (!from.existsSync()) {
          c.log('vscode package: no $vscodeSource/$name');
          return ExitCode.invalidFile;
        }
        from.copySync('${gate.path}/$name');
      }
      c.log('$vscodeGate: npm run package -> $vsixName');
      final code = await c.run(
        offBenchCore(c, cpus, [
          'npm',
          'run',
          'package',
          '--',
          '--out',
          vsixName,
          ...rest,
        ]),
        workingDirectory: vscodeGate,
      );
      if (code != ExitCode.success) return answer(code);
      return answer(_checkVsix('${gate.path}/$vsixName', c));
    default:
      if (!Directory('${gate.path}/out/test/unit').existsSync()) {
        c.log(
          'vscode unit: no out/test/unit in $vscodeGate; '
          'run vscode-compile first',
        );
        return ExitCode.taskFailed;
      }
      c.log('$vscodeGate: mocha out/test/unit/**/*.test.js');
      return answer(
        await c.run(
          offBenchCore(c, cpus, [
            'node',
            'node_modules/mocha/bin/mocha.js',
            'out/test/unit/**/*.test.js',
            ...rest,
          ]),
          workingDirectory: vscodeGate,
        ),
      );
  }
}

/// Copies the file or directory [from] to [to], which is not there yet.
void _copy(String from, String to) {
  if (FileSystemEntity.isDirectorySync(from)) {
    Directory(to).createSync(recursive: true);
    for (final e in Directory(from).listSync(followLinks: false)) {
      _copy(e.path, '$to/${e.path.split('/').last}');
    }
  } else {
    File(from).copySync(to);
  }
}

/// Lists the files of the .vsix at [vsix] (`unzip -Z1`, else python's
/// zipfile) and holds them to [vsixRequired] and [vsixForbidden].
int _checkVsix(String vsix, VerbContext c) {
  final lines = _listZip(vsix);
  if (lines == null) {
    c.log('vscode package: cannot list $vsix (needs unzip or python3)');
    return ExitCode.taskFailed;
  }
  var bad = false;
  for (final need in vsixRequired) {
    if (!lines.contains(need)) {
      c.log('vscode package: $need is not in the .vsix');
      bad = true;
    }
  }
  for (final l in lines.where(vsixForbidden.hasMatch)) {
    c.log('vscode package: $l must not be in the .vsix');
    bad = true;
  }
  c.log(
    'vscode package: $vsix, ${File(vsix).lengthSync()} bytes, '
    '${lines.length} files${bad ? ', checks failed' : ''}',
  );
  return bad ? ExitCode.taskFailed : ExitCode.success;
}

List<String>? _listZip(String vsix) {
  for (final argv in [
    ['unzip', '-Z1', vsix],
    [
      'python3',
      '-c',
      'import sys,zipfile;print("\\n".join(zipfile.ZipFile(sys.argv[1]).namelist()))',
      vsix,
    ],
  ]) {
    try {
      final r = Process.runSync(argv.first, argv.skip(1).toList());
      if (r.exitCode == 0) {
        return (r.stdout as String)
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
      }
    } on ProcessException {
      continue;
    }
  }
  return null;
}
