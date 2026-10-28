/// A program a test runs in a process of its own, compiled to a kernel
/// once and kept for the runs after: [compiledProgram].
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

// Examples can assume:
// import 'dart:io';
// import 'dart:isolate';
// import 'package:test/test.dart';

/// The path of the kernel (a `.dill` file) of the Dart program at
/// [program], compiled against the packages that [packages] (a
/// `package_config.json`) names and kept in the directory [cache]: what a
/// test runs as `dart <kernel>` in a process of its own in place of
/// `dart <program>`, which compiles it again for each process.
///
/// It is compiled without the platform (`dart compile kernel
/// --no-link-platform`), which the VM that runs it carries itself, so it
/// runs on the Dart that compiled it only. With it, [cache] keeps the
/// names of the files it was compiled from, as the compiler gives them
/// (the program, the libraries it imports, of its package and of the
/// others, and [packages]), and a hash of what they hold and of the Dart
/// version: a later call, in this run or in another, that finds them
/// holding the same returns the kernel compiled then, compiling nothing.
/// One edited, removed or added to them, or another Dart, and it is
/// compiled again.
///
/// It is called once per suite, in `setUpAll`, which is bounded by
/// minutes rather than by a test's timeout: a compile is seconds on a
/// loaded machine. Calls at once in processes of their own for the same
/// program wait for each other (a lock in [cache]), so the program is
/// compiled by one of them (isolates of one process may each compile it,
/// its kernel the same); [cache] is best a directory of its own in the
/// package's `.dart_tool`, which git ignores. A program that does not
/// compile is a [TestFailure] with what the compiler said.
///
/// [defines] are the environment declarations it is compiled with (`-D`),
/// which a `const bool.fromEnvironment` reads as it is compiled, not as
/// it runs: `dart -D... <kernel>` does not change them, so a program
/// asked for with others is a kernel of its own. Without them it is not
/// in product mode (`dart.vm.product` is false), as `dart <program>` runs
/// it; `dart compile kernel` alone compiles it in product mode, which
/// `defines: {'dart.vm.product': 'true'}` asks for.
///
/// The kernel holds the libraries of its packages. What looks a package
/// up while it runs (`Isolate.resolvePackageUri`, the paths of a stack
/// trace's frames) finds the configuration the VM finds from the kernel's
/// directory up, in a package's `.dart_tool` the package's; a program to
/// run without it is run with `--packages` naming another.
///
/// A program of the package's tests, compiled once for the suite:
///
/// ```dart
/// late String app;
/// setUpAll(() async {
///   app = await compiledProgram(
///     'test/app.dart',
///     packages: (await Isolate.packageConfig)!.toFilePath(),
///     cache: '.dart_tool/twk_test/programs',
///   );
/// });
///
/// test('the app ends well', () async {
///   final res = await Process.run(Platform.resolvedExecutable, [app]);
///   expect(res.exitCode, 0);
/// });
/// ```
Future<String> compiledProgram(
  String program, {
  required String packages,
  required String cache,
  Map<String, String> defines = const {},
}) async {
  final source = File(program).absolute.path;
  final config = File(packages).absolute.path;
  final dir = Directory(cache).absolute..createSync(recursive: true);
  final declarations = [
    for (final MapEntry(:key, :value) in {
      'dart.vm.product': 'false',
      ...defines,
    }.entries)
      '-D$key=$value',
  ]..sort();
  // the place of the program's kernel: one per program, packages and
  // declarations
  final name = source.split(Platform.pathSeparator).last.split('.').first;
  final place = [source, config, ...declarations].join('\n');
  final slot = '${dir.path}/$name-${_hex(_hash([utf8.encode(place)]))}';
  final kernel = '$slot.dill';
  final manifest = File('$slot.deps');
  final lock = await File('$slot.lock').open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.blockingExclusive);
    if (_kept(manifest, kernel)) {
      return kernel;
    }
    // written beside the kept ones and moved over them once whole, as
    // another isolate of this process (which the lock does not hold
    // off) may be at the same
    final temporary = '$slot.${pid}_${DateTime.now().microsecondsSinceEpoch}';
    final depfile = File('$temporary.d');
    try {
      final compiled = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        '--no-link-platform',
        '--packages=$config',
        '--depfile=${depfile.path}',
        ...declarations,
        '-o',
        '$temporary.dill',
        source,
      ]);
      if (compiled.exitCode != 0) {
        fail(
          '$program does not compile:\n${compiled.stdout}${compiled.stderr}',
        );
      }
      final inputs = _inputs(depfile.readAsStringSync());
      File('$temporary.dill').renameSync(kernel);
      File('$temporary.deps')
        ..writeAsStringSync('${_key(inputs)}\n${inputs.join('\n')}\n')
        ..renameSync(manifest.path);
    } finally {
      for (final f in ['$temporary.dill', '$temporary.d', '$temporary.deps']) {
        if (File(f).existsSync()) {
          File(f).deleteSync();
        }
      }
    }
    return kernel;
  } finally {
    await lock.close();
  }
}

/// Whether [kernel] was compiled from files that hold now what they held
/// then, by [manifest]: its first line their key, the others their paths.
bool _kept(File manifest, String kernel) {
  if (!manifest.existsSync() || !File(kernel).existsSync()) {
    return false;
  }
  final lines = manifest.readAsLinesSync();
  if (lines.isEmpty) {
    return false;
  }
  final [key, ...inputs] = lines;
  return inputs.every((f) => File(f).existsSync()) && _key(inputs) == key;
}

/// The paths a depfile (Ninja's format: `out: in in ...`, a space in a
/// path escaped by a backslash) names as the inputs.
List<String> _inputs(String depfile) => [
  for (final path in depfile.trim().split(RegExp(r'(?<!\\)\s+')).skip(1))
    path.replaceAll(r'\ ', ' '),
];

/// The hash of the Dart version and of [inputs], their paths and what
/// they hold, as hexadecimal digits.
String _key(List<String> inputs) => _hex(
  _hash([
    utf8.encode(Platform.version),
    for (final path in inputs) ...[
      utf8.encode(path),
      File(path).readAsBytesSync(),
    ],
  ]),
);

/// The 64-bit FNV-1a hash of [parts], each ended by a zero byte.
int _hash(List<Uint8List> parts) {
  // the offset basis, put together of its halves: its literal is past
  // what an int holds
  var h = 0xcbf29ce4 << 32 | 0x84222325;
  for (final part in parts) {
    for (final b in part) {
      h = (h ^ b) * 0x100000001b3;
    }
    h *= 0x100000001b3;
  }
  return h;
}

/// The 64 bits of [h] as 16 hexadecimal digits.
String _hex(int h) => [
  h >>> 32,
  h & 0xffffffff,
].map((half) => half.toRadixString(16).padLeft(8, '0')).join();
