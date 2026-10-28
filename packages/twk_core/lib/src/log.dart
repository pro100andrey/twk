/// Where `print`, [log] and uncaught errors go while a [TwkApp] owns the
/// screen: anything written to stdout or stderr then would land in the
/// middle of a frame. The records can be served over a local socket, which
/// `twk logs` tails ([LogSink.serve]); a [TwkApp] serves its own while it
/// runs when `TWK_DEBUG` names `logs` ([TwkApp.serveLogs]).
///
/// The layer above the platform's (stdio, files, sockets) and below the
/// render tree, which logs its overflows: it reaches the app in its docs
/// only, so that what logs compiles none of it.
///
/// @docImport 'app.dart';
library;

import 'dart:async';
import 'dart:convert';

import 'platform/platform.dart';

/// How much a [LogRecord] matters, from the least to the most.
enum LogLevel {
  /// Detail for finding a fault, of no use otherwise.
  debug,

  /// What happened, in the normal course of things; [log]'s default.
  info,

  /// Something went wrong that the app got past.
  warning,

  /// Something failed: an error nothing caught lands here.
  error,
}

/// One entry of a [LogSink]: when, how much it matters, the message, and
/// the error and its stack where there are.
final class LogRecord {
  /// A record of [message] at [time], at [level], with [error] and [stack]
  /// where there are.
  const LogRecord(
    this.time,
    this.level,
    this.message, {
    this.error,
    this.stack,
  });

  /// What [toJson] made: the error as its text, the stack parsed from its
  /// text.
  factory LogRecord.fromJson(Map<String, Object?> json) => LogRecord(
    DateTime.parse(json['time']! as String),
    LogLevel.values.byName(json['level']! as String),
    json['message']! as String,
    error: json['error'] as String?,
    stack: switch (json['stack']) {
      final String stack => StackTrace.fromString(stack),
      _ => null,
    },
  );

  /// When the record was made, in local time.
  final DateTime time;

  /// How much the record matters.
  final LogLevel level;

  /// What the record says.
  final String message;

  /// The error the record is about, or null for none; read back from JSON
  /// ([LogRecord.fromJson]), its text.
  final Object? error;

  /// Where [error] was thrown, or null when unknown.
  final StackTrace? stack;

  /// `time` (ISO 8601), `level` (its name), `message`, and the `error` and
  /// the `stack` as text where there are.
  Map<String, Object?> toJson() => {
    'time': time.toIso8601String(),
    'level': level.name,
    'message': message,
    if (error != null) 'error': '$error',
    if (stack != null) 'stack': '$stack',
  };

  /// The time of day of [time] as a record shows it ([toString], a log
  /// view, the console, `twk logs`): hours, minutes and seconds, two digits
  /// each, and milliseconds, three.
  ///
  /// ```dart
  /// assert(
  ///   LogRecord.formatTime(DateTime(2026, 1, 1, 9, 5, 7, 42)) ==
  ///       '09:05:07.042',
  /// );
  /// ```
  static String formatTime(DateTime time) {
    String two(int n) => '$n'.padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.'
        '${'${time.millisecond}'.padLeft(3, '0')}';
  }

  /// `09:05:07.042 warning message: error` ([formatTime]), then the stack
  /// on lines of its own.
  @override
  String toString() {
    final sb = StringBuffer()
      ..write(formatTime(time))
      ..write(' ')
      ..write(level.name)
      ..write(' ')
      ..write(message);
    if (error != null) {
      sb.write(': $error');
    }
    if (stack != null) {
      sb
        ..write('\n')
        ..write('$stack'.trimRight());
    }
    return sb.toString();
  }
}

/// The zone value under which [log] finds the sink of the app it runs in.
const logSinkKey = #twk_core.LogSink;

/// The records of one app: the last [capacity] of them kept in a ring for
/// listeners that come later (a console overlay), every one passed to the
/// listeners as it comes and, with a [path], appended to that file; while
/// it [serve]s, sent to the clients of its socket too.
///
/// A [TwkApp] has one, [TwkApp.logs], which [log] writes to while the app
/// runs. A sink of its own, its records read back:
///
/// ```dart
/// final logs = LogSink(capacity: 100)
///   ..addListener((record) => print(record.message));
/// logs.add(LogRecord(DateTime.now(), LogLevel.info, 'started'));
/// print(logs.records.length); // 1
/// ```
///
/// See also:
///
///  * [log], which writes to the sink of the app it is called in.
final class LogSink {
  /// An empty sink that keeps the last [capacity] records, 1000 by default,
  /// and appends each to the file [path] when one is given.
  ///
  /// [capacity] must be positive.
  LogSink({this.capacity = 1000, this.path})
    : assert(capacity > 0, 'capacity must be positive, not $capacity');

  /// How many records are kept: when there are more, the oldest go.
  final int capacity;

  /// The file every record is appended to (`TWK_LOG` for a [TwkApp]); on
  /// the web, which has no files, [add] throws [UnsupportedError] for one.
  final String? path;

  final _ring = <LogRecord>[];

  /// Where the next record goes once the ring is full: the oldest one.
  var _next = 0;

  final _listeners = <void Function(LogRecord record)>[];

  /// The records kept, oldest first.
  List<LogRecord> get records => [
    ..._ring.skip(_next),
    ..._ring.take(_next),
  ];

  /// Keeps [record], dropping the oldest when the ring is full, writes it
  /// to [path], then passes it to the listeners.
  void add(LogRecord record) {
    if (_ring.length < capacity) {
      _ring.add(record);
    } else {
      _ring[_next] = record;
      _next = (_next + 1) % capacity;
    }
    final path = this.path;
    if (path != null) {
      appendFile(path, '$record\n');
    }
    for (final listener in [..._listeners]) {
      listener(record);
    }
  }

  /// Calls [listener] with every record added after this call, as it is
  /// added.
  void addListener(void Function(LogRecord record) listener) =>
      _listeners.add(listener);

  /// Stops calling [listener], added with [addListener]; does nothing when
  /// it is not a listener. A listener removed while a record is passed to
  /// the listeners still gets that record.
  void removeListener(void Function(LogRecord record) listener) =>
      _listeners.remove(listener);

  /// The server [serve] started, or is starting.
  Future<LogServer>? _starting;

  /// The server, once started.
  LogServer? _server;

  /// Serves the records over a local socket ([LocalAddress.bind]) until
  /// [close], for `twk logs`: a client that sends the address's token and a
  /// line feed gets the records kept, oldest first, then each one as it is
  /// added, as lines of JSON ([LogRecord.toJson]). The address goes to the
  /// address file `.dart_tool/twk/logs` of the project [directory] is in
  /// ([LocalAddress.projectOf]), in place of another app's. Returns the
  /// address; the one served already, or being started, when called
  /// again, so that one socket is served however many calls overlap. The
  /// socket keeps the process alive until [close]. What fails fails each
  /// call that waited for it, and the next call tries again. Throws
  /// [UnsupportedError] on the web, which has no local sockets.
  Future<LocalAddress> serve({String? directory}) async {
    final starting = _starting ??= LogServer.start(
      directory,
      () => records.map(_line),
    );
    final LogServer server;
    try {
      server = await starting;
    } on Object {
      if (identical(_starting, starting)) {
        _starting = null;
      }
      rethrow;
    }
    // the first call to see it started; none once closed meanwhile
    if (identical(_starting, starting) && _server == null) {
      _server = server;
      addListener(_send);
    }
    return server.address;
  }

  /// Sends [record] to the clients of the socket being served; with none,
  /// it is not made a line of JSON.
  void _send(LogRecord record) {
    final server = _server;
    if (server != null && server.serving) {
      server.send(_line(record));
    }
  }

  /// [record] as a line of JSON ([LogRecord.toJson]), without its line
  /// feed.
  static String _line(LogRecord record) => jsonEncode(record.toJson());

  /// Stops serving ([serve]): the clients are disconnected, the socket
  /// closed and the address file removed if it still holds this sink's
  /// address; one still starting is closed once it has. Does nothing when
  /// not serving.
  Future<void> close() async {
    final starting = _starting;
    _starting = null;
    _server = null;
    removeListener(_send);
    if (starting == null) {
      return;
    }
    final LogServer server;
    try {
      server = await starting;
    } on Object {
      return; // it never started: what failed is serve's
    }
    await server.close();
  }
}

/// Records [message] in the [LogSink] of the app whose handlers, timers or
/// frames call it; elsewhere prints the record.
///
/// [message] is recorded as its text ([Object.toString]), at [level],
/// [LogLevel.info] by default, with [error] and its [stack] where given.
/// Inside [TwkApp.run] the record goes to [TwkApp.logs], so it does not
/// land in the middle of a frame; `twk logs` shows it while the app serves
/// its log ([TwkApp.serveLogs]).
///
/// ```dart
/// try {
///   int.parse('x');
/// } on FormatException catch (e, stack) {
///   log('bad input', level: LogLevel.warning, error: e, stack: stack);
/// }
/// ```
void log(
  Object? message, {
  LogLevel level = LogLevel.info,
  Object? error,
  StackTrace? stack,
}) {
  final record = LogRecord(
    DateTime.now(),
    level,
    '$message',
    error: error,
    stack: stack,
  );
  final sink = Zone.current[logSinkKey] as LogSink?;
  if (sink != null) {
    sink.add(record);
  } else {
    Zone.current.print('$record');
  }
}
