/// `twk test-from-cast`: [CastTestCommand], and [castTestSource], the one
/// generator of a test over a recording.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'cast.dart';
import 'completion.dart';
import 'project.dart';

/// `twk test-from-cast`: copies a recording into a project's `test/` and
/// writes a test of it beside it ([castTestSource]).
final class CastTestCommand extends Command<int> with Completes {
  /// The command; `--out` names the test file.
  CastTestCommand() {
    argParser
      ..addOption(
        'out',
        abbr: 'o',
        valueHelp: 'file',
        help:
            'The test file to write; by default test/<name>_test.dart of the '
            "current directory's project, <name> the recording's.",
      )
      ..addFlag(
        'goldens',
        defaultsTo: true,
        help:
            'Run the test once with TWK_UPDATE_GOLDENS=1 to write the screen '
            'files it holds the recording to; --no-goldens leaves that to '
            'the person.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help:
            'Overwrite a different recording of the same name beside the '
            'test.',
      );
  }

  @override
  Positionals get positionals => const Positionals.files(glob: '*.cast');

  @override
  Map<String, OptionPath> get optionPaths => const {
    'out': OptionPath.file,
  };

  @override
  String get name => 'test-from-cast';

  @override
  String get invocation =>
      'twk test-from-cast <file.cast> [--out=<file>] [--force] [--no-goldens]';

  @override
  String get description =>
      'Write a test from a recording.\n\n'
      'Copies the recording next to the test (test/<name>.cast; it stays '
      'where it is when it is already there; another recording of that name '
      'there is refused with 1 unless --force) and writes a test of it that '
      "plays its output through twk_test's screenFrames: for each marker "
      'of the recording a check that the screen it showed is the one in '
      'test/goldens/<name>/<k>.txt, or, where it has none, that its last '
      'screen is test/goldens/<name>/last.txt, and that the emulator took '
      'all of it. Runs the test once with TWK_UPDATE_GOLDENS=1 to write '
      'those files (not with --no-goldens), the emulator that checks them '
      'writing them, and says which. Ends with 0; 1 when the recording '
      'cannot be read or the files written, the project has no twk_test '
      'dev dependency or the run fails (the test and recording stay), 64 '
      'for a wrong command line. See doc/record-play.md.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('One recording (.cast) to make a test of.');
    }
    final source = rest.single;
    final Cast cast;
    try {
      cast = Cast.read(source);
    } on FileSystemException catch (e) {
      stderr.writeln(
        'twk test-from-cast: cannot read $source: '
        '${e.osError?.message ?? e.message}',
      );
      return 1;
    } on FormatException catch (e) {
      stderr.writeln('twk test-from-cast: $source: ${e.message}');
      return 1;
    }
    final name = _identifier(p.basenameWithoutExtension(source));
    final project = projectOf(null);
    final out = p.absolute(
      argResults!['out'] as String? ?? castTestPath(project, name),
    );
    final package = _packageOf(out) ?? project;
    final goldens = p.posix.joinAll([
      ...p.split(p.relative(p.dirname(out), from: package)),
      'goldens',
      name,
    ]);
    // a recording already beside the test is used where it is
    final copy = p.equals(p.dirname(p.absolute(source)), p.dirname(out))
        ? p.absolute(source)
        : p.join(p.dirname(out), '$name.cast');
    try {
      Directory(p.dirname(out)).createSync(recursive: true);
      if (!p.equals(p.absolute(source), copy)) {
        final held = File(copy);
        if (!(argResults!['force'] as bool) &&
            held.existsSync() &&
            !_sameBytes(held, File(source))) {
          stderr.writeln(
            'twk test-from-cast: ${p.relative(copy)} is another recording; '
            '--force overwrites it, or name this one differently',
          );
          return 1;
        }
        File(source).copySync(copy);
      }
      File(out).writeAsStringSync(
        castTestSource(
          cast,
          castPath: p.posix.joinAll(
            p.split(p.relative(copy, from: package)),
          ),
          goldens: goldens,
          source: p.basename(source),
        ),
      );
    } on FileSystemException catch (e) {
      stderr.writeln(
        'twk test-from-cast: cannot write ${e.path ?? out}: '
        '${e.osError?.message ?? e.message}',
      );
      return 1;
    }
    stdout.writeln('wrote ${p.relative(out)} and ${p.relative(copy)}');
    if (!(argResults!['goldens'] as bool)) {
      return 0;
    }
    return _writeGoldens(
      package: package,
      test: out,
      goldens: p.join(package, goldens),
      markers: cast.events.where((e) => e.code == CastEvent.marker).length,
    );
  }

  /// Runs the test at [test] once in [package] with
  /// `TWK_UPDATE_GOLDENS=1`, so that the emulator that checks the screens
  /// writes the files in [goldens]; says which it wrote. 1 where [package]
  /// has no dependency on twk_test or the run fails or takes longer than
  /// [_goldensTimeout].
  Future<int> _writeGoldens({
    required String package,
    required String test,
    required String goldens,
    required int markers,
  }) async {
    final pubspec = File(p.join(package, 'pubspec.yaml'));
    if (!pubspec.existsSync() ||
        !RegExp(r'^\s+twk_test\s*:', multiLine: true).hasMatch(
          pubspec.readAsStringSync(),
        )) {
      stderr.writeln(
        'twk test-from-cast: ${p.relative(package)} has no twk_test '
        'dev dependency, so the screen files are not written; add it and '
        'run `TWK_UPDATE_GOLDENS=1 dart test '
        '${p.relative(test, from: package)}`',
      );
      return 1;
    }
    final dart =
        p.basenameWithoutExtension(Platform.resolvedExecutable) == 'dart'
        ? Platform.resolvedExecutable
        : 'dart';
    final Process process;
    try {
      process = await Process.start(
        dart,
        ['test', p.relative(test, from: package)],
        workingDirectory: package,
        environment: {'TWK_UPDATE_GOLDENS': '1'},
      );
    } on ProcessException catch (e) {
      stderr.writeln(
        'twk test-from-cast: cannot run the test to write the screen files: '
        '${e.message}',
      );
      return 1;
    }
    final output = StringBuffer();
    final reads = [
      process.stdout.transform(utf8.decoder).forEach(output.write),
      process.stderr.transform(utf8.decoder).forEach(output.write),
    ];
    final code = await process.exitCode.timeout(
      _goldensTimeout,
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await Future.wait(reads).timeout(
      const Duration(seconds: 5),
      onTimeout: () => const [],
    );
    if (code != 0) {
      final why = code == -1
          ? 'after ${_goldensTimeout.inSeconds} s'
          : 'exit $code';
      stderr
        ..writeln(
          'twk test-from-cast: the test did not run to the end '
          '($why), so the screen files are not all written; the test and the '
          'recording are left as they are:',
        )
        ..writeln(output.toString().trimRight());
      return 1;
    }
    final names = markers == 0
        ? ['last']
        : [for (var k = 1; k <= markers; k++) '$k'];
    final written = [
      for (final n in names)
        if (File(p.join(goldens, '$n.txt')).existsSync())
          p.relative(p.join(goldens, '$n.txt')),
    ];
    stdout.writeln(
      written.isEmpty
          ? 'wrote no screen files (no marker has a frame)'
          : 'wrote the screen files:\n${written.map((f) => '  $f').join('\n')}',
    );
    return 0;
  }
}

/// How long the test that writes the screen files may run.
const _goldensTimeout = Duration(seconds: 90);

/// Where the test of the recording called [name] is written by default: in
/// the `test/` of [project], whatever directory the command runs in.
String castTestPath(String project, String name) =>
    p.join(project, 'test', '${name}_test.dart');

bool _sameBytes(File a, File b) {
  final x = a.readAsBytesSync();
  final y = b.readAsBytesSync();
  if (x.length != y.length) {
    return false;
  }
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) {
      return false;
    }
  }
  return true;
}

/// The nearest directory above [file] with a `pubspec.yaml`, null if none.
String? _packageOf(String file) {
  for (var dir = p.dirname(file); ; dir = p.dirname(dir)) {
    if (File(p.join(dir, 'pubspec.yaml')).existsSync()) {
      return dir;
    }
    if (p.dirname(dir) == dir) {
      return null;
    }
  }
}

String _identifier(String name) {
  final id = name.replaceAll(RegExp('[^A-Za-z0-9_]+'), '_');
  return id.isEmpty ? 'recording' : id;
}

/// The Dart source of a test of [cast]: it reads the recording at
/// [castPath] (relative to the package, where `dart test` runs), plays it
/// through twk_test's `screenFrames` and holds, for each marker, the frame
/// shown at or before its time to the screen file `<goldens>/<k>.txt`
/// (`matchesScreenFile`), k from 1 in the order of the markers; for a
/// recording without markers, its last frame to `<goldens>/last.txt`. It
/// checks too that the emulator took in all of it.
///
/// The generator emulates nothing: which frame a marker shows is found by
/// the test itself, with the emulator that checks it, and the screen files
/// are written by that emulator, by running the test once with
/// `TWK_UPDATE_GOLDENS=1` (what `twk test-from-cast` does). A marker with
/// no frame at or before it is skipped by the test, with the reason.
///
/// [goldens] is the directory of the screen files, relative to the package
/// as [castPath] is. [source] is the recording's name for the comment on
/// top.
///
/// The test for a recording of one line:
///
/// ```dart
/// final cast = Cast.parse(
///   '{"version": 2, "width": 20, "height": 3}\n'
///   '[0.1, "o", "hello\\r\\n"]\n',
/// );
/// final source = castTestSource(
///   cast,
///   castPath: 'test/hello.cast',
///   goldens: 'test/goldens/hello',
/// );
/// ```
String castTestSource(
  Cast cast, {
  required String castPath,
  required String goldens,
  String source = 'the recording',
}) {
  final marks = [
    for (final e in cast.events)
      if (e.code == CastEvent.marker) e,
  ];
  final out = StringBuffer()
    ..writeln('// Written by `twk test-from-cast` from $source.')
    ..writeln('// The recording is played through the test emulator; each')
    ..writeln('// check holds a screen it showed to a screen file, written')
    ..writeln('// by running this test with TWK_UPDATE_GOLDENS=1.')
    ..writeln("import 'package:test/test.dart';")
    ..writeln("import 'package:twk_dev/twk_dev.dart' show Cast;")
    ..writeln(
      "import 'package:twk_test/twk_test.dart' "
      'show matchesScreenFile, screenFrames;',
    )
    ..writeln()
    ..writeln('void main() {')
    ..writeln('  final cast = Cast.read(${_quote(castPath)});')
    ..writeln('  final writes = cast.writes.toList();')
    ..writeln('  final width = cast.header.width;')
    ..writeln('  final height = cast.header.height;')
    ..writeln('  final shown = screenFrames(width, height, writes);')
    ..writeln();
  if (marks.isEmpty) {
    out
      ..writeln('  // the screens kept for the golden files: the last one')
      ..writeln('  final frames = screenFrames(')
      ..writeln('    width,')
      ..writeln('    height,')
      ..writeln('    writes,')
      ..writeln('    screens: {if (shown.isNotEmpty) shown.length},')
      ..writeln('  );');
  } else {
    out
      ..writeln('  /// The number of the frame shown at or before [time].')
      ..writeln('  int? at(double time) {')
      ..writeln('    int? number;')
      ..writeln('    for (final frame in shown) {')
      ..writeln('      if (frame.time > time) {')
      ..writeln('        break;')
      ..writeln('      }')
      ..writeln('      number = frame.number;')
      ..writeln('    }')
      ..writeln('    return number;')
      ..writeln('  }')
      ..writeln()
      ..writeln('  // the screens kept for the golden files: those of the')
      ..writeln('  // markers')
      ..writeln('  const times = <double>[');
    for (final m in marks) {
      out.writeln('    ${m.time},');
    }
    out
      ..writeln('  ];')
      ..writeln('  final frames = screenFrames(')
      ..writeln('    width,')
      ..writeln('    height,')
      ..writeln('    writes,')
      ..writeln('    screens: {')
      ..writeln('      for (final time in times)')
      ..writeln('        if (at(time) case final number?) number,')
      ..writeln('    },')
      ..writeln('  );');
  }
  out
    ..writeln()
    ..writeln("  test('the emulator takes in all of it', () {")
    ..writeln('    expect(frames, isNotEmpty);')
    ..writeln('    expect(frames.last.errors, isEmpty);')
    ..write('  });');
  if (marks.isEmpty) {
    out
      ..writeln()
      ..writeln()
      ..writeln("  test('the last screen', () {")
      ..writeln('    expect(')
      ..writeln('      frames.last,')
      ..writeln('      matchesScreenFile(${_quote('$goldens/last.txt')}),')
      ..writeln('    );')
      ..write('  });');
  }
  for (final (i, m) in marks.indexed) {
    final what = m.data.isEmpty
        ? 'the marker at ${m.time.toStringAsFixed(3)} s'
        : 'the marker ${m.data}';
    out
      ..writeln()
      ..writeln()
      ..writeln('  test(${_quote(what)}, () {')
      ..writeln('    final number = at(times[$i]);')
      ..writeln('    if (number == null) {')
      ..writeln(
        '      markTestSkipped(${_quote('no frame at or before '
        '${m.time.toStringAsFixed(3)} s')});',
      )
      ..writeln('      return;')
      ..writeln('    }')
      ..writeln('    expect(')
      ..writeln('      frames[number - 1],')
      ..writeln(
        '      matchesScreenFile(${_quote('$goldens/${i + 1}.txt')}),',
      )
      ..writeln('    );')
      ..write('  });');
  }
  out
    ..writeln()
    ..writeln('}');
  return out.toString();
}

/// [text] as a single-quoted Dart string literal.
String _quote(String text) {
  final out = StringBuffer("'");
  for (final rune in text.runes) {
    switch (rune) {
      case 0x27:
        out.write(r"\'");
      case 0x5c:
        out.write(r'\\');
      case 0x24:
        out.write(r'\$');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case < 0x20 || 0x7f:
        out.write('\\u{${rune.toRadixString(16)}}');
      default:
        out.writeCharCode(rune);
    }
  }
  return (out..write("'")).toString();
}
