/// `twk logs`: [LogsCommand], and how it writes a record of the log:
/// [formatLine] and [formatRecord].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:twk_core/twk_core.dart';

import 'project.dart';

// Examples can assume:
// import 'dart:convert';
// import 'package:twk_core/twk_core.dart';

/// `twk logs`: tails the log an app of the project serves
/// (`LogSink.serve`), one app after another, until stopped.
final class LogsCommand extends Command<int> {
  /// Sets up `twk logs`'s options: `--directory` and `--[no-]color`.
  LogsCommand() {
    argParser
      ..addOption(
        'directory',
        abbr: 'C',
        valueHelp: 'path',
        help:
            'A directory of the project whose apps to tail (default: the '
            'current one).',
      )
      ..addFlag(
        'color',
        defaultsTo: null,
        help:
            'Color the levels (default: when stdout is a terminal that '
            'takes colors: NO_COLOR and TERM=dumb say it does not, and CI '
            'or TWK_PLAIN=1 that it takes plain text).',
      );
  }

  @override
  String get name => 'logs';

  @override
  String get invocation => 'twk logs [--directory=<path>] [--[no-]color]';

  @override
  String get description =>
      'Tail the log of the app running from this project.\n\n'
      'Reads the log over the local socket whose address the app writes '
      "to the project's .dart_tool/twk/logs (LogSink.serve): the records "
      'it kept, then each one as it comes, with levels and colours, on '
      'stdout. Waits for an app, and for the next one when it ends.';

  /// How often the address file is read while no app serves its log.
  static const poll = Duration(milliseconds: 200);

  @override
  Future<int> run() async {
    final args = argResults!;
    final project = projectOf(args.option('directory'));
    final color =
        args['color'] as bool? ??
        colorsLevels(
          Platform.environment,
          outputIsTerminal: stdout.hasTerminal && stdout.supportsAnsiEscapes,
        );
    final file = LocalAddress.fileOf('logs', project);
    var waiting = false;
    for (;;) {
      final address = LocalAddress.read(file);
      Socket? socket;
      if (address != null) {
        try {
          socket = await address.connect();
        } on SocketException {
          // left behind by an app that didn't stop, or reset by one that is
          // stopping: its address is still in the file as it closes
          socket = null;
        }
      }
      if (socket == null) {
        if (!waiting) {
          stderr.writeln('twk logs: waiting for an app of $project');
          waiting = true;
        }
        await Future<void>.delayed(poll);
        continue;
      }
      waiting = false;
      socket.write('${address!.token}\n');
      unawaited(socket.done.then<void>((_) {}, onError: (Object _) {}));
      try {
        await for (final line
            in utf8.decoder.bind(socket).transform(const LineSplitter())) {
          stdout.writeln(formatLine(line, color: color));
        }
      } on SocketException {
        // the app went away
      }
      stderr.writeln('twk logs: the app ended');
    }
  }
}

/// Whether `twk logs` colors the levels where `--[no-]color` says
/// nothing: on a terminal ([outputIsTerminal], one that takes ANSI
/// escapes) whose environment [env] takes colors ([colorModeFor]) and not
/// plain text only ([plainAsked], else [runsInCi]), as twk_core tells
/// where it opens a terminal.
bool colorsLevels(
  Map<String, String> env, {
  required bool outputIsTerminal,
}) =>
    outputIsTerminal &&
    colorModeFor(env) != ColorMode.none &&
    !(plainAsked(env) ?? runsInCi(env));

/// A line of a served log as `twk logs` shows it: the record
/// ([formatRecord]), or the line itself when it is not one.
///
/// ```dart
/// final record = LogRecord(
///   DateTime(2026, 1, 1, 9, 5, 7),
///   LogLevel.info,
///   'saved',
/// );
/// assert(
///   formatLine(jsonEncode(record.toJson()), color: false) ==
///       '09:05:07.000 info    saved',
/// );
/// assert(formatLine('plain text', color: false) == 'plain text');
/// ```
String formatLine(String line, {required bool color}) {
  try {
    final json = jsonDecode(line);
    if (json is Map<String, Object?>) {
      return formatRecord(LogRecord.fromJson(json), color: color);
    }
  } on Object {
    // not a record of this version
  }
  return line;
}

/// [record] as `09:05:07.042 warning message: error` (the time as
/// [LogRecord.formatTime] writes it), the level padded to
/// the longest, then the stack on lines of its own; with [color] the time
/// and the stack dim, the level, and the error, in the level's colour.
///
/// ```dart
/// final record = LogRecord(
///   DateTime(2026, 1, 1, 9, 5, 7, 42),
///   LogLevel.warning,
///   'retrying',
///   error: 'timeout',
/// );
/// assert(
///   formatRecord(record, color: false) ==
///       '09:05:07.042 warning retrying: timeout',
/// );
/// ```
String formatRecord(LogRecord record, {required bool color}) {
  String paint(String text, String sgr) =>
      color ? '\x1b[${sgr}m$text\x1b[0m' : text;
  final sgr = switch (record.level) {
    LogLevel.debug => '2',
    LogLevel.info => '36',
    LogLevel.warning => '33',
    LogLevel.error => '1;31',
  };
  final sb = StringBuffer()
    ..write(paint(LogRecord.formatTime(record.time), '2'))
    ..write(' ')
    ..write(paint(record.level.name.padRight(7), sgr))
    ..write(' ')
    ..write(record.message);
  if (record.error != null) {
    sb.write(paint(': ${record.error}', sgr));
  }
  final stack = record.stack;
  if (stack != null) {
    for (final line in const LineSplitter().convert('$stack'.trimRight())) {
      sb
        ..write('\n')
        ..write(paint(line, '2'));
    }
  }
  return sb.toString();
}
