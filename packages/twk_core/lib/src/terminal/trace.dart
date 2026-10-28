/// Raw bytes a terminal read or wrote, each read or write with when it
/// happened, kept in a file: `TWK_TRACE_INPUT` and `TWK_TRACE_OUTPUT` for a
/// `Terminal`.
///
/// The format: a header line, then one record per read or write.
///
/// ```text
/// twk-trace 1 output 100x30\n       magic, version, input|output, size
/// 1532 412\n<412 bytes>\n            µs since the trace began, length
/// ```
///
/// The size is the terminal's when the trace began. The line feed after a
/// record's bytes is not part of them: it only keeps a record from running
/// into the next one's header when the file is read as text.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../byte_sink.dart';
import '../platform/platform.dart';

/// Which way the bytes of a trace went.
enum TraceDirection {
  /// What the terminal read: the keys, the mouse, the replies.
  input,

  /// What the terminal wrote: the frames and its own sequences.
  output,
}

/// One read or write of a trace.
final class TraceRecord {
  /// A read or write of [bytes] at [micros].
  const TraceRecord(this.micros, this.bytes);

  /// When, in microseconds since the trace began.
  final int micros;

  /// What was read or written.
  final Uint8List bytes;
}

/// A trace read back: the [records] of what a terminal read or wrote
/// ([direction]), and its size when the trace began.
///
/// A trace is recorded where `TWK_TRACE_INPUT` or `TWK_TRACE_OUTPUT` names
/// a file ([TraceWriter]). An input trace replays what was typed into a
/// `HeadlessTerminal`, with the pauses that decided what a lone ESC was:
///
/// ```dart
/// final trace = Trace.read('input.trace');
/// final terminal = HeadlessTerminal(width: trace.width, height: trace.height);
/// trace.feed(
///   terminal.input,
///   waiting: () => terminal.inputTimeout,
///   timeOut: terminal.timeOutInput,
/// );
/// ```
///
/// An output trace's [bytes] are what the screen was sent, to be fed to an
/// emulator.
final class Trace {
  /// A trace of [direction] from a terminal of [width] x [height] cells,
  /// with [records]; [truncated] where its file ended inside a record.
  Trace(
    this.direction,
    this.width,
    this.height,
    this.records, {
    this.truncated = false,
  });

  /// Reads the trace file at [path] (see [Trace.parse]). Throws
  /// [UnsupportedError] on the web, which has no files.
  factory Trace.read(String path) => Trace.parse(readFile(path));

  /// Reads a trace from [bytes]; its records are views into them. Throws
  /// [FormatException] when [bytes] are not a trace or a record is broken.
  /// A file that ends inside a record (its writer never closed) keeps the
  /// records before it and is [truncated].
  factory Trace.parse(Uint8List bytes) {
    final eol = bytes.indexOf(0x0A);
    final header = eol < 0
        ? const <String>[]
        : latin1.decode(Uint8List.sublistView(bytes, 0, eol)).split(' ');
    final direction = header.length == 4
        ? TraceDirection.values.asNameMap()[header[2]]
        : null;
    final size = header.length == 4 ? header[3].split('x') : const <String>[];
    final width = size.length == 2 ? int.tryParse(size[0]) : null;
    final height = size.length == 2 ? int.tryParse(size[1]) : null;
    if (header.length != 4 ||
        header[0] != magic ||
        header[1] != '$version' ||
        direction == null ||
        width == null ||
        height == null) {
      throw FormatException('not a trace of version $version', bytes, 0);
    }
    final records = <TraceRecord>[];
    var truncated = false;
    var i = eol + 1;
    while (i < bytes.length) {
      final time = _number(bytes, i, 0x20);
      final length = time == null ? null : _number(bytes, time.$2, 0x0A);
      if (time == null || length == null) {
        truncated = true;
        break;
      }
      final from = length.$2;
      final to = from + length.$1;
      if (to >= bytes.length) {
        truncated = true;
        break;
      }
      if (bytes[to] != 0x0A) {
        throw FormatException('a record longer than it says', bytes, to);
      }
      records.add(TraceRecord(time.$1, Uint8List.sublistView(bytes, from, to)));
      i = to + 1;
    }
    return Trace(direction, width, height, records, truncated: truncated);
  }

  /// The first word of a trace file.
  static const magic = 'twk-trace';

  /// The version of the format a trace file is written in, the second word
  /// of its header.
  static const version = 1;

  /// Whether the trace is of what was read or what was written.
  final TraceDirection direction;

  /// The terminal's number of columns when the trace began.
  final int width;

  /// The terminal's number of rows when the trace began.
  final int height;

  /// Every read or write, in the order they happened.
  final List<TraceRecord> records;

  /// Whether the file ended inside a record: [records] are those before it.
  final bool truncated;

  /// The bytes of every record, in a row.
  Uint8List get bytes {
    final b = BytesBuilder(copy: false);
    for (final r in records) {
      b.add(r.bytes);
    }
    return b.takeBytes();
  }

  /// Feeds an input trace to [input] read by read, as the terminal
  /// delivered it (`HeadlessTerminal.input`). Where a read came after a
  /// pause at least as long as what [waiting] says is pending waits for
  /// (`HeadlessTerminal.inputTimeout`), [timeOut] resolves that first
  /// (`HeadlessTerminal.timeOutInput`), as a `Terminal`'s timer did: a
  /// lone ESC is the Escape key, not Alt with the next key.
  void feed(
    void Function(Uint8List bytes) input, {
    Duration? Function()? waiting,
    void Function()? timeOut,
  }) {
    var last = 0;
    for (final r in records) {
      final wait = waiting?.call();
      if (wait != null &&
          timeOut != null &&
          r.micros - last >= wait.inMicroseconds) {
        timeOut();
      }
      input(r.bytes);
      last = r.micros;
    }
  }

  /// The decimal number at [i] in [b] up to [end], and where the bytes
  /// after [end] start; null when [b] ends first.
  static (int, int)? _number(Uint8List b, int i, int end) {
    var v = 0;
    for (var k = i; k < b.length; k++) {
      final c = b[k];
      if (c == end && k > i) {
        return (v, k + 1);
      }
      if (c < 0x30 || c > 0x39) {
        throw FormatException('a broken record', b, k);
      }
      v = v * 10 + c - 0x30;
    }
    return null;
  }
}

/// A trace file being written, records appended off the caller's path.
///
/// A record is copied into a buffer, and a write started on a later turn of
/// the event loop takes the buffer to the file. One write is on its way at
/// a time; records pile up meanwhile and go with the next one, so a slow
/// file holds nobody up.
final class TraceWriter {
  TraceWriter._(this._file, this._clock);

  /// Creates (or empties) the file at [path] and writes the header of a
  /// trace of [direction] from a terminal of [width] x [height] cells.
  /// Times count from [clock] (by default one started now): one clock for
  /// both traces of a terminal puts its reads and writes on one time line.
  /// Throws [UnsupportedError] on the web.
  factory TraceWriter.open(
    String path,
    TraceDirection direction,
    int width,
    int height, {
    Stopwatch? clock,
  }) {
    final file = createFile(
      path,
      ascii.encode(
        '${Trace.magic} ${Trace.version} ${direction.name} '
        '${width}x$height\n',
      ),
    );
    return TraceWriter._(file, clock ?? (Stopwatch()..start()));
  }

  final FileWriter _file;
  final Stopwatch _clock;

  /// Records waiting for the next write, and those of the write on its way.
  var _pending = ByteSink(1 << 12);
  var _writing = ByteSink(1 << 12);

  /// A write is scheduled or on its way.
  var _busy = false;
  Future<void>? _draining;
  Object? _error;
  StackTrace? _stack;
  var _closed = false;

  /// Records [bytes], copied, as read or written now. Dropped once closed,
  /// or once a write failed (see [close]).
  void add(List<int> bytes) {
    if (_closed || _error != null) {
      return;
    }
    final b = _pending
      ..decimal(_clock.elapsedMicroseconds)
      ..byte(0x20)
      ..decimal(bytes.length)
      ..byte(0x0A);
    if (bytes is Uint8List) {
      b.bytes(bytes);
    } else {
      bytes.forEach(b.byte);
    }
    b.byte(0x0A);
    if (!_busy) {
      _busy = true;
      Timer.run(_drainLater);
    }
  }

  void _drainLater() {
    if (!_closed) {
      _draining = _drain();
    }
  }

  /// Writes what piled up, one write at a time, until nothing is left.
  Future<void> _drain() async {
    try {
      while (_pending.length > 0) {
        final out = _pending;
        _pending = _writing..reset();
        _writing = out;
        await _file.write(out.view);
      }
    } on Object catch (e, s) {
      _error ??= e;
      _stack ??= s;
    } finally {
      _busy = false;
    }
  }

  /// Writes what is left and closes the file; what a write failed with is
  /// thrown once the file is closed. Safe to call more than once.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _draining;
    if (_error == null) {
      await _drain();
    }
    await _file.close();
    final error = _error;
    if (error != null) {
      Error.throwWithStackTrace(error, _stack!);
    }
  }
}
