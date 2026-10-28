/// asciicast v2, the recordings `twk record` writes and `twk play` plays:
/// a header line, then an event a line.
///
/// `test/cast.golden.json` holds this file, `castFrames` and the VS Code
/// extension's port of them (`editors/vscode/src/core/cast.ts`), whose
/// twk terminal records and plays the same files, to the same lines and
/// frames: a change here is made there and in the golden too.
library;

import 'dart:convert';
import 'dart:io';

// Examples can assume:
// import 'dart:io';
// late IOSink file;

/// The first line of a recording: a JSON object.
final class CastHeader {
  /// The header of a recording of a terminal of [width] × [height] cells.
  const CastHeader({
    required this.width,
    required this.height,
    this.timestamp,
    this.idleTimeLimit,
    this.command,
    this.title,
    this.env = const {},
  });

  /// [json], the header's object; a [FormatException] when it isn't one
  /// of version 2 with a width and a height.
  factory CastHeader.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('the header is no JSON object');
    }
    if (json['version'] != 2) {
      throw FormatException(
        'asciicast version ${json['version']}; this reads version 2',
      );
    }
    final width = json['width'];
    final height = json['height'];
    if (width is! int || height is! int || width < 1 || height < 1) {
      throw const FormatException('the header has no width and height');
    }
    final timestamp = json['timestamp'];
    final limit = json['idle_time_limit'];
    final command = json['command'];
    final title = json['title'];
    final env = json['env'];
    return CastHeader(
      width: width,
      height: height,
      timestamp: timestamp is num ? timestamp.toInt() : null,
      idleTimeLimit: limit is num ? limit.toDouble() : null,
      command: command is String ? command : null,
      title: title is String ? title : null,
      env: {
        if (env is Map<String, Object?>)
          for (final MapEntry(:key, :value) in env.entries)
            if (value is String) key: value,
      },
    );
  }

  /// The terminal's width when the recording began, in cells.
  final int width;

  /// The terminal's height when the recording began, in cells.
  final int height;

  /// When the recording began, in seconds since the Unix epoch.
  final int? timestamp;

  /// The longest pause a player keeps, in seconds; null for every pause
  /// as it was.
  final double? idleTimeLimit;

  /// The command recorded, as a shell would take it.
  final String? command;

  /// What the recording is called, as a player shows it.
  final String? title;

  /// What the recorded terminal was: `TERM` and `SHELL`.
  final Map<String, String> env;

  /// The header's object, as [CastHeader.fromJson] reads it: version 2,
  /// and the fields that are not null or empty.
  Map<String, Object?> toJson() => {
    'version': 2,
    'width': width,
    'height': height,
    'timestamp': ?timestamp,
    'idle_time_limit': ?idleTimeLimit,
    'command': ?command,
    'title': ?title,
    if (env.isNotEmpty) 'env': env,
  };
}

/// An event of a recording: at [time], of the kind [code], [data].
final class CastEvent {
  /// An event of the kind [code] at [time].
  const CastEvent(this.time, this.code, this.data);

  /// What the program wrote to its terminal.
  static const output = 'o';

  /// What was typed (keys, and the terminal's answers to queries).
  static const input = 'i';

  /// The terminal was resized: [data] is `<width>x<height>`.
  static const resize = 'r';

  /// A marker: a point of the recording a player can go to.
  static const marker = 'm';

  /// Seconds from the start of the recording.
  final double time;

  /// What kind of event it is: [output], [input], [resize] or [marker].
  final String code;

  /// What was written or typed, the size of a resize, or a marker's label.
  final String data;

  /// The size of a [resize] event, null for another or one that names no
  /// size.
  (int, int)? get size {
    if (code != resize) {
      return null;
    }
    final m = RegExp(r'^(\d+)x(\d+)$').firstMatch(data);
    return m == null ? null : (int.parse(m[1]!), int.parse(m[2]!));
  }

  /// The event's line: `[1.234567, "o", "text"]`.
  String encode() =>
      '[${time.toStringAsFixed(6)}, ${jsonEncode(code)}, ${jsonEncode(data)}]';

  @override
  String toString() => encode();
}

/// A recording: its [header] and its [events], in time order.
///
/// A recording read, and how long it lasts:
///
/// ```dart
/// final cast = Cast.read('demo.cast');
/// print('${cast.header.width}×${cast.header.height}, ${cast.duration} s');
/// ```
final class Cast {
  /// A recording of [header] and [events].
  Cast(this.header, this.events);

  /// The recording in [text]; a [FormatException] for one that isn't
  /// asciicast v2.
  factory Cast.parse(String text) {
    final lines = const LineSplitter().convert(text);
    final first = lines.indexWhere((l) => l.trim().isNotEmpty);
    if (first < 0) {
      throw const FormatException('no header');
    }
    final header = CastHeader.fromJson(_json(lines[first], first));
    final events = <CastEvent>[];
    for (var i = first + 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) {
        continue;
      }
      final event = _json(lines[i], i);
      if (event case [final num time, final String code, final String data]) {
        events.add(CastEvent(time.toDouble(), code, data));
      } else {
        throw FormatException('line ${i + 1}: no [time, code, data] event');
      }
    }
    return Cast(header, events);
  }

  /// The recording in the file [path].
  factory Cast.read(String path) => Cast.parse(File(path).readAsStringSync());

  static Object? _json(String line, int index) {
    try {
      return jsonDecode(line);
    } on FormatException catch (e) {
      throw FormatException('line ${index + 1}: ${e.message}');
    }
  }

  /// The recording's first line.
  final CastHeader header;

  /// What happened, in time order.
  final List<CastEvent> events;

  /// Seconds from the start to the last event.
  double get duration => events.isEmpty ? 0 : events.last.time;
}

/// Writes a recording as it happens, through the function it is given:
/// the header at once, then each event, its time the real time since the
/// start with every pause longer than [idleLimit] cut to it. What the
/// program wrote and what was typed are decoded as UTF-8 a stream each, so
/// a character split between two events is put together; a malformed one
/// is U+FFFD.
///
/// A recording of a program that wrote one line, written to a file as it
/// goes:
///
/// ```dart
/// final writer = CastWriter(
///   file.write,
///   const CastHeader(width: 80, height: 24),
/// );
/// writer.output(Duration.zero, 'hello\r\n'.codeUnits);
/// writer.close(const Duration(seconds: 1));
/// ```
final class CastWriter {
  /// A writer that writes [header] at once through the function it is
  /// given, then each event.
  CastWriter(this._write, CastHeader header, {this.idleLimit}) {
    _write('${jsonEncode(header.toJson())}\n');
  }

  final void Function(String text) _write;

  /// The longest pause kept; null keeps each as it was.
  final Duration? idleLimit;

  final _output = _Utf8Stream();
  final _input = _Utf8Stream();

  // the real time of the last event, and the time written for it
  Duration _real = Duration.zero;
  Duration _time = Duration.zero;

  /// How many events were written.
  int get count => _count;
  var _count = 0;

  /// The time written for the last event, in seconds.
  double get time => _time.inMicroseconds / 1e6;

  /// What the program wrote, at [at] since the start; returns it as text,
  /// empty when it is the start of a character only.
  String output(Duration at, List<int> bytes) {
    final text = _output.decode(bytes);
    _event(at, CastEvent.output, text);
    return text;
  }

  /// What was typed, at [at].
  void input(Duration at, List<int> bytes) =>
      _event(at, CastEvent.input, _input.decode(bytes));

  /// The terminal became [width] by [height] cells at [at].
  void resize(Duration at, int width, int height) =>
      _event(at, CastEvent.resize, '${width}x$height', always: true);

  /// Writes what is left of a character cut off at the end, at [at].
  void close(Duration at) {
    _event(at, CastEvent.output, _output.close());
    _event(at, CastEvent.input, _input.close());
  }

  void _event(Duration at, String code, String data, {bool always = false}) {
    if (data.isEmpty && !always) {
      return;
    }
    final limit = idleLimit;
    final gap = at - _real;
    _time += limit == null || gap <= limit ? gap : limit;
    _real = at;
    _write('${CastEvent(time, code, data).encode()}\n');
    _count++;
  }
}

/// A stream of UTF-8 decoded a piece at a time.
final class _Utf8Stream {
  final _text = StringBuffer();
  late final ByteConversionSink _sink = const Utf8Decoder(
    allowMalformed: true,
  ).startChunkedConversion(StringConversionSink.fromStringSink(_text));

  String decode(List<int> bytes) {
    _sink.add(bytes);
    return _take();
  }

  String close() {
    _sink.close();
    return _take();
  }

  String _take() {
    final s = _text.toString();
    _text.clear();
    return s;
  }
}
