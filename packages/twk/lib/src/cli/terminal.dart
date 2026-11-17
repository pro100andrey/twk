/// The terminal a [Cli] writes to and reads from: [CliTerminal], the
/// process's own by default, and the `Clock` its time is kept by.
///
/// @docImport 'cli.dart';
library;

import 'dart:async';

import 'package:twk_core/twk_core.dart' show Clock, SystemClock, Terminal;

import '../../twk.dart' show TerminalBackend, TerminalOptions;
import '../binding/driven_start.dart';
import '../platform/platform.dart' as platform;
import 'capabilities.dart';

final Clock _wall = SystemClock();

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
  /// mode: raw input, the normal screen. Called when the [Cli]'s inline
  /// session starts, and again for a new one once a Ctrl+C ended the last
  /// (its terminal closed by then); the app closes it when the session
  /// ends.
  Future<TerminalBackend> openInline();

  /// A prompt asking [question] is about to take its answer: its row is on
  /// the screen and takes keys, or a line is about to be read. Nothing
  /// happens on a terminal of the process; a terminal of a test answers it.
  void promptShown(String question) {}

  /// What a Ctrl+C nothing live took does once the inline session has
  /// ended and handed the terminal back: on the process's terminal it
  /// sends the process SIGINT, so it ends as it would at a cooked
  /// terminal, unless the program watches the signal.
  ///
  /// In a live session Ctrl+C is a key: the terminal is in raw mode, so
  /// the line discipline sends no SIGINT, neither to the process group
  /// nor to a child the program started; only this sends one, to the
  /// process itself. A program that starts processes watches
  /// `ProcessSignal.sigint` and stops them, else they run on after it
  /// ends.
  void interrupt();

  /// Where the time of the session and its timers comes from: the wall
  /// clock by default, one a test moves by hand in the fake terminal
  /// (`package:twk_test/cli.dart`).
  Clock get clock => _wall;

  /// What `AppBinding.now` reads when [clock] reads zero: null, the real
  /// time at that moment, unless [clock] is a driver's (`TWK_DRIVEN`),
  /// which names it.
  DateTime? get startTime => null;

  /// Runs [body] where the code of the inline session runs: as it is, or in
  /// the zone of the fake clock that [clock] is, whose microtasks and
  /// timers a test then moves.
  R run<R>(R Function() body) => body();

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

  // what TWK_DRIVEN asks of the process, read when first needed: a driver
  // moves the clock the session keeps its time by, which runs in a zone
  // of its own, the terminal opening on real time
  late final DrivenStart? _driven = DrivenStart.of(environment: _env);

  @override
  Clock get clock => _driven?.clock ?? super.clock;

  @override
  DateTime? get startTime => _driven?.startTime;

  @override
  R run<R>(R Function() body) {
    final driven = _driven;
    return driven == null ? body() : driven.zone.run(body);
  }

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
      final columns = platform.stdioColumns(error: _reserveStdout);
      if (columns > 0) {
        return columns;
      }
      // a terminal of no size: as a pipe
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
  Future<TerminalBackend> openInline() async {
    final driven = _driven;
    if (driven != null) {
      await DrivenStart.requireService();
    }
    // the terminal is I/O: on real time, in the zone `run` came from
    return (driven?.outer ?? Zone.current).run(
      () => Terminal.open(
        const TerminalOptions(
          alternateScreen: false,
          mouse: false,
          plain: false,
        ),
      ),
    );
  }

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
