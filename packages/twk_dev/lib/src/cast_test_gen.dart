/// `twk test-from-cast`: [CastTestCommand], and [castTestSource], the one
/// generator of a test over a recording.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:twk_term/twk_term.dart';

import 'cast.dart';
import 'project.dart';

/// `twk test-from-cast`: copies a recording into a project's `test/` and
/// writes a test of it beside it ([castTestSource]).
final class CastTestCommand extends Command<int> {
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
        'force',
        negatable: false,
        help:
            'Overwrite a different recording of the same name beside the '
            'test.',
      );
  }

  @override
  String get name => 'test-from-cast';

  @override
  String get invocation =>
      'twk test-from-cast <file.cast> [--out=<file>] [--force]';

  @override
  String get description =>
      'Write a test from a recording.\n\n'
      'Copies the recording next to the test (test/<name>.cast; it stays '
      'where it is when it is already there; another recording of that name '
      'there is refused with 1 unless --force) and writes a test of it that '
      "plays its output through twk_test's screenFrames: for each marker "
      'of the recording a check of a line of the screen it showed, or, '
      'where it has none, of its last screen, and that the emulator took '
      'all of it. Ends with 0; 1 when the recording cannot be read or the '
      'files written, 64 for a wrong command line. See doc/record-play.md.';

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
            p.split(p.relative(copy, from: _packageOf(out) ?? project)),
          ),
          source: p.basename(source),
          note: (text) => stderr.writeln('twk test-from-cast: $text'),
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
    return 0;
  }
}

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

/// A screen the recording showed: `number` from 1, its `time` in seconds,
/// its rows without the blanks that end them.
typedef _Frame = ({int number, double time, List<String> lines});

/// The screens of [cast]: a frame after each output that leaves no
/// synchronized update open, a resize keeping the emulator's screen, as
/// twk_test's `screenFrames` takes them.
List<_Frame> _frames(Cast cast) {
  final screen = TerminalEmulator(
    width: cast.header.width,
    height: cast.header.height,
  );
  final frames = <_Frame>[];
  for (final write in cast.writes) {
    if (write.size case (final w, final h)?) {
      screen.resize(w, h);
    } else if (write.output case final output?) {
      screen.feedText(output);
      if (!screen.mode(TerminalMode.synchronizedOutput)) {
        frames.add((
          number: frames.length + 1,
          time: write.time,
          lines: [
            for (var y = 0; y < screen.height; y++) screen.lineText(y),
          ],
        ));
      }
    }
  }
  return frames;
}

/// The Dart source of a test of [cast]: it reads the recording at
/// [castPath] (relative to the package, where `dart test` runs), plays it
/// through twk_test's `screenFrames` and checks, for each marker, one line
/// of the screen shown there; for a recording without markers, one line of
/// its last screen. It checks too that the emulator took in all of it.
///
/// The line is the first that differs from the one checked before (the
/// first of the screen for the first), the first that is not blank when
/// none does. [source] is the recording's name for the comment on top.
///
/// The test for a recording of one line:
///
/// ```dart
/// final cast = Cast.parse(
///   '{"version": 2, "width": 20, "height": 3}\n'
///   '[0.1, "o", "hello\\r\\n"]\n',
/// );
/// final source = castTestSource(cast, castPath: 'test/hello.cast');
/// ```
String castTestSource(
  Cast cast, {
  required String castPath,
  String source = 'the recording',
  void Function(String)? note,
}) {
  final frames = _frames(cast);
  final marks = [
    for (final e in cast.events)
      if (e.code == CastEvent.marker) e,
  ];
  // the frame each check is of: the last shown at the marker's time, or the
  // last one; one pass, both lists being in time order
  final targets = <(String?, _Frame)>[];
  final unchecked = <String>[];
  if (frames.isNotEmpty) {
    if (marks.isEmpty) {
      targets.add((null, frames.last));
    } else {
      var at = -1;
      for (final m in marks) {
        while (at + 1 < frames.length && frames[at + 1].time <= m.time) {
          at++;
        }
        if (at >= 0) {
          targets.add((m.data, frames[at]));
        } else {
          unchecked.add(
            'the marker ${m.data.isEmpty ? '' : '${_shown(m.data)} '}at '
            '${m.time.toStringAsFixed(3)} s: no frame at or before it',
          );
        }
      }
    }
  }
  for (final text in unchecked) {
    note?.call('$text, no check for it');
  }
  final out = StringBuffer()
    ..writeln('// Written by `twk test-from-cast` from $source.')
    ..writeln('// The recording is played through the test emulator; each')
    ..writeln('// check is a line of a screen it showed.')
    ..writeln("import 'package:test/test.dart';")
    ..writeln("import 'package:twk_dev/twk_dev.dart' show Cast;")
    ..writeln("import 'package:twk_test/twk_test.dart' show screenFrames;")
    ..writeln()
    ..writeln('void main() {')
    ..writeln('  final cast = Cast.read(${_quote(castPath)});')
    ..writeln('  final frames = screenFrames(')
    ..writeln('    cast.header.width,')
    ..writeln('    cast.header.height,')
    ..writeln('    cast.writes,')
    ..writeln('  );')
    ..writeln()
    ..writeln("  test('the emulator takes in all of it', () {")
    ..writeln('    expect(frames, isNotEmpty);')
    ..writeln('    expect(frames.last.errors, isEmpty);')
    ..write('  });');
  List<String>? before;
  for (final (label, frame) in targets) {
    final lines = frame.lines;
    var row = -1;
    for (var y = 0; y < lines.length && row < 0; y++) {
      if (lines[y].isNotEmpty &&
          (before == null || _at(before, y) != lines[y])) {
        row = y;
      }
    }
    if (row < 0) {
      row = lines.indexWhere((l) => l.isNotEmpty);
    }
    before = lines;
    final what = label == null
        ? 'the last screen'
        : label.isEmpty
        ? 'the marker at ${frame.time.toStringAsFixed(3)} s'
        : 'the marker $label';
    out
      ..writeln()
      ..writeln()
      ..writeln('  test(${_quote(what)}, () {');
    if (row < 0) {
      out.writeln(
        '    expect(frames[${frame.number - 1}].lines.where((l) => '
        'l.isNotEmpty), isEmpty);',
      );
    } else {
      out
        ..writeln(
          '    // frame ${frame.number}, at '
          '${frame.time.toStringAsFixed(3)} s',
        )
        ..writeln(
          '    expect(frames[${frame.number - 1}].lines[$row], '
          '${_quote(lines[row])});',
        );
    }
    out.write('  });');
  }
  for (final text in unchecked) {
    out
      ..writeln()
      ..write('  // $text, so no check');
  }
  out
    ..writeln()
    ..writeln('}');
  return out.toString();
}

/// [text] with its control characters written out, for one line of a
/// comment or of the terminal.
String _shown(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    switch (rune) {
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case < 0x20 || 0x7f || (>= 0x80 && <= 0x9f) || 0x2028 || 0x2029:
        out.write('\\u{${rune.toRadixString(16)}}');
      default:
        out.writeCharCode(rune);
    }
  }
  return out.toString();
}

String _at(List<String> lines, int y) => y < lines.length ? lines[y] : '';

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
