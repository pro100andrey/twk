/// [TraceOptions] and [Trace], the trace a session writes (part 8 of
/// DESIGN.md): the pty's output as a cast, and what each step did as JSON
/// lines.
library;

import 'dart:convert';
import 'dart:io';

import 'cast.dart';

// Examples can assume:
// late ProcessSpec spec;

/// Where a session writes its trace, and what it says of the program.
///
/// A session that writes a trace beside a test's own files:
///
/// ```dart
/// final session = await Session.start(
///   spec,
///   trace: const TraceOptions('.dart_tool/traces/counter'),
/// );
/// print(session.trace!.castPath);
/// ```
final class TraceOptions {
  /// A trace written to `<path>.cast` and `<path>.trace.jsonl`; the
  /// directory is made.
  const TraceOptions(this.path, {this.program, this.profile, this.log});

  /// The files' path without the extensions.
  final String path;

  /// What the header calls the program; the spec's, by default.
  final String? program;

  /// The terminal profile the app ran under, for the header.
  final String? profile;

  /// Where the app's log is read from: called at the end of each step, it
  /// returns the records written since its last call, as text lines. None
  /// given, the steps have an empty log: the app service has no way to
  /// read it.
  final List<String> Function()? log;
}

/// The trace a session writes: where its two files are.
///
/// `<name>.cast` is asciicast v2 ([Cast.read]): one output event for the
/// bytes each posted frame's boundary took in (and one for what came
/// between), raw as the pty gave them, and a marker for each step.
/// `<name>.trace.jsonl` is a line each of four kinds, told by its `type`:
/// `header`, `frame`, `step` and `tree`; see part 8 of DESIGN.md.
abstract interface class Trace {
  /// The cast file.
  String get castPath;

  /// The JSON lines file.
  String get tracePath;

  /// Deletes both files, for a run that did not fail.
  void delete();
}

/// The writer of a [Trace].
final class TraceRecorder implements Trace {
  /// Opens the files of [options] for a program on a terminal of [width] by
  /// [height] cells; `now` is the time since the start.
  TraceRecorder(
    this.options, {
    required String program,
    required int width,
    required int height,
    required bool driven,
    required this._now,
    List<String> arguments = const [],
  }) : size = (width, height) {
    File(options.path).parent.createSync(recursive: true);
    _cast = File(castPath).openSync(mode: FileMode.write);
    _json = File(tracePath).openSync(mode: FileMode.write);
    final started = DateTime.now().toUtc();
    final name = options.program ?? program;
    _writer = CastWriter(
      (text) => _cast!.writeStringSync(text),
      CastHeader(
        width: width,
        height: height,
        timestamp: started.millisecondsSinceEpoch ~/ 1000,
        command: [name, ...arguments].join(' '),
        title: File(options.path).uri.pathSegments.last,
      ),
    );
    _line({
      'type': 'header',
      'version': 1,
      'program': name,
      'size': [width, height],
      'profile': options.profile,
      'driven': driven,
      'start': started.toIso8601String(),
    });
  }

  /// What it was opened with.
  final TraceOptions options;

  /// The size of the terminal in the header.
  final (int, int) size;

  final Duration Function() _now;
  RandomAccessFile? _cast;
  RandomAccessFile? _json;
  late final CastWriter _writer;
  var _lastOutput = -1;
  String? _lastTree;
  var _treeKeys = 0;

  @override
  String get castPath => '${options.path}.cast';

  @override
  String get tracePath => '${options.path}.trace.jsonl';

  /// How many cast events were written.
  int get events => _writer.count;

  /// The index of the cast event the last output went in; -1 for none.
  int get lastOutput => _lastOutput;

  void _line(Map<String, Object?> line) =>
      _json?.writeStringSync('${jsonEncode(line)}\n');

  /// What the app wrote, as the pty gave it: one event, whole (a frame
  /// boundary is an event boundary). Returns the event's index, or the
  /// last output's when [bytes] is empty.
  int output(List<int> bytes) {
    if (_cast == null || bytes.isEmpty) {
      return _lastOutput;
    }
    final before = _writer.count;
    _writer.output(_now(), bytes);
    if (_writer.count > before) {
      _lastOutput = before;
    }
    return _lastOutput;
  }

  /// The terminal of the frames became [width] by [height].
  void resize(int width, int height) {
    if (_cast != null) {
      _writer.resize(_now(), width, height);
    }
  }

  /// A marker for a step; returns its index.
  int marker(String label) {
    if (_cast == null) {
      return -1;
    }
    final index = _writer.count;
    _writer.marker(_now(), label);
    return index;
  }

  /// A line of the frames table: [frame] ended at the cast event
  /// [castEvent], the app having written [outputWritten] bytes and the pty
  /// given [raw].
  void frame(int frame, int castEvent, int outputWritten, int raw) => _line({
    'type': 'frame',
    'frame': frame,
    'castEvent': castEvent,
    'outputWritten': outputWritten,
    'raw': raw,
  });

  /// Keeps the widget tree [text] of [frame] unless it is the last one
  /// kept; returns its key.
  String tree(int frame, String text) {
    if (text != _lastTree) {
      _lastTree = text;
      _treeKeys++;
      _line({
        'type': 'tree',
        'key': 't$_treeKeys',
        'frame': frame,
        'text': text,
      });
    }
    return 't$_treeKeys';
  }

  /// A step's line.
  void step(Map<String, Object?> step) => _line({'type': 'step', ...step});

  /// Ends the files: what is left of a character is written, and they are
  /// closed. Ends nothing twice.
  void close() {
    if (_cast == null) {
      return;
    }
    _writer.close(_now());
    _cast?.closeSync();
    _json?.closeSync();
    _cast = null;
    _json = null;
  }

  @override
  void delete() {
    close();
    for (final path in [castPath, tracePath]) {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }
}
