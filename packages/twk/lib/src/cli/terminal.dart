/// The terminal a [Cli] writes to and reads from: [CliTerminal], the
/// process's own by default, and the [CliClock] its time is kept by.
///
/// @docImport 'cli.dart';
library;

import 'dart:async';

import 'package:twk_core/twk_core.dart' show Terminal;

import '../../twk.dart' show TerminalBackend, TerminalOptions;
import '../platform/platform.dart' as platform;
import 'capabilities.dart';

/// Where a [Cli]'s time comes from and where the timers of its inline
/// session run: the wall clock ([CliClock.system]), or one a test moves by
/// hand (the fake terminal's, `package:twk_test/cli.dart`).
abstract interface class CliClock {
  /// The wall clock: [run] runs its body as it is, [stopwatch] is a new
  /// [Stopwatch].
  const factory CliClock.system() = _SystemClock;

  /// A stopwatch on this clock, started.
  Stopwatch stopwatch();

  /// Runs [body] where the timers it starts are this clock's.
  R run<R>(R Function() body);
}

final class _SystemClock implements CliClock {
  const _SystemClock();

  @override
  Stopwatch stopwatch() => Stopwatch()..start();

  @override
  R run<R>(R Function() body) => body();
}

/// The terminal a [Cli] talks through: where lines go ([out], [err]),
/// where a plain prompt reads them ([readLine]), what both can do
/// ([capabilities], [mode]), and, in the interactive mode, the terminal an
/// inline twk app runs on ([openInline]).
///
/// [CliTerminal.system] is the process's stdio. Tests pass the fake one of
/// `package:twk_test/cli.dart`, which captures what is written and
/// replays what is typed.
abstract class CliTerminal {
  /// A terminal subclasses build on.
  CliTerminal();

  /// The process's stdio: `stdin`, `stdout` and `stderr`; with
  /// [reserveStdout] what goes to stdout goes to `stderr`, for a program
  /// whose stdout is another's (a server speaking JSON-RPC on it).
  ///
  /// Capabilities are detected once, from stdio and [environment] (the
  /// process environment by default); [ansi], [interactive] and
  /// [hyperlinks] override detection, see [CliCapabilities.detect].
  factory CliTerminal.system({
    bool reserveStdout,
    Map<String, String>? environment,
    bool? ansi,
    bool? interactive,
    bool? hyperlinks,
  }) = _SystemTerminal;

  /// What this terminal can do.
  CliCapabilities get capabilities;

  /// How it may be talked to ([CliCapabilities.mode]).
  CliMode get mode => capabilities.mode;

  /// Where ordinary output goes, line by line, while no inline session
  /// holds the screen.
  StringSink get out;

  /// Where diagnostics go.
  StringSink get err;

  /// Width in columns; null when output is not a terminal and nothing
  /// says how wide it is.
  int? get columns;

  /// Reads one line as the terminal reads it, without its line break; null
  /// at the end of input. [hidden] switches echo off while it reads, where
  /// input is a terminal.
  Future<String?> readLine({bool hidden = false});

  /// Opens the terminal an inline twk app runs on, in the interactive
  /// mode: raw input, the normal screen. Called once, when the [Cli]'s
  /// inline session starts; the app closes it when the session ends.
  Future<TerminalBackend> openInline();

  /// What a Ctrl+C nothing live took does once the inline session has
  /// ended and handed the terminal back: on the process's terminal it
  /// sends the process SIGINT, so it ends as it would at a cooked
  /// terminal, unless the program watches the signal.
  void interrupt();

  /// Where the time of the session and its timers comes from.
  CliClock get clock => const CliClock.system();

  /// Flushes [out] and [err] where they buffer.
  Future<void> flush();

  /// The code the process ends with: on the process's terminal, `exitCode`
  /// of dart:io, which [Cli.run] sets when its body fails. Elsewhere it is
  /// kept here, 0 until it is set, so that a test reads it without ending
  /// its own process with it.
  var exitCode = 0;

  /// Lets go of what it holds: on the process's terminal, stdin, once a
  /// [readLine] listened to it, so that the process can end. Nothing is
  /// read after it. [Cli.close] calls it; nothing by default.
  Future<void> close() async {}
}

final class _SystemTerminal extends CliTerminal {
  _SystemTerminal({
    this._reserveStdout = false,
    this._environment,
    this._ansi,
    this._interactive,
    this._hyperlinks,
  });

  // whether stdout is another's, what goes to it going to stderr
  final bool _reserveStdout;
  final Map<String, String>? _environment;
  final bool? _ansi;
  final bool? _interactive;
  final bool? _hyperlinks;

  Map<String, String> get _env => _environment ?? platform.environment;

  @override
  late final capabilities = CliCapabilities.detect(
    environment: _env,
    inputIsTerminal: platform.stdinIsTerminal,
    // the inline session draws on stdout: a reserved one has none
    outputIsTerminal: !_reserveStdout && platform.stdioIsTerminal(),
    outputSupportsAnsi: platform.stdioSupportsAnsi(error: _reserveStdout),
    errorIsTerminal: platform.stdioIsTerminal(error: true),
    ansi: _ansi,
    interactive: _interactive,
    hyperlinks: _hyperlinks,
    windows: platform.isWindows,
  );

  @override
  late final StringSink out = platform.stdioSink(error: _reserveStdout);

  @override
  final StringSink err = platform.stdioSink(error: true);

  @override
  int? get columns {
    if (platform.stdioIsTerminal(error: _reserveStdout)) {
      return platform.stdioColumns(error: _reserveStdout);
    }
    // a positive number only, as twk_core's plain output takes it
    final columns = int.tryParse(_env['COLUMNS'] ?? '');
    return columns != null && columns > 0 ? columns : null;
  }

  StreamIterator<String>? _lines;
  var _closed = false;

  @override
  Future<String?> readLine({bool hidden = false}) async {
    if (_closed) {
      return null;
    }
    final lines = _lines ??= StreamIterator(platform.stdinLines());
    final echo = hidden && platform.stdinIsTerminal;
    StreamSubscription<void>? interrupted;
    if (echo) {
      platform.stdinEcho = false;
      // Ctrl+C ends the process as ever, the echo back on first
      interrupted = platform.watchInterrupt(() async {
        platform.stdinEcho = true;
        out.writeln();
        await interrupted?.cancel();
        platform.interruptProcess();
      });
    }
    try {
      return await lines.moveNext() ? lines.current : null;
    } finally {
      if (echo) {
        await interrupted?.cancel();
        platform.stdinEcho = true;
        out.writeln();
      }
    }
  }

  // the mode said a terminal redraws here: plain output is not what the
  // session is for, under CI where it was asked to (`interactive: true`)
  // too
  @override
  Future<TerminalBackend> openInline() => Terminal.open(
    const TerminalOptions(alternateScreen: false, mouse: false, plain: false),
  );

  @override
  void interrupt() => platform.interruptProcess();

  @override
  int get exitCode => platform.processExitCode;

  @override
  set exitCode(int code) => platform.processExitCode = code;

  @override
  Future<void> flush() => platform.flushStdio();

  @override
  Future<void> close() async {
    final lines = _lines;
    _lines = null;
    _closed = true;
    await lines?.cancel();
  }
}
