/// The log of an app: [log] records a message, with its [LogLevel], and a
/// [LogSink] keeps what is recorded as [LogRecord]s.
///
/// It is a library of its own because `log` is also a function of dart:math
/// and dart:developer: an app that imports either has no clash with
/// `twk.dart`, and one that logs imports this beside it.
///
/// @docImport 'package:twk_core/terminal.dart';
library;

export 'package:twk_core/terminal.dart' show LogLevel, LogRecord, LogSink, log;
