/// The terminal a [Cli] writes to and reads from: [CliTerminal], the
/// process's own by default, and the [CliClock] its time is kept by.
///
/// @docImport 'cli.dart';
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:twk/twk.dart' show TerminalBackend, TerminalOptions;
import 'package:twk_core/twk_core.dart' show Terminal;

import 'capabilities.dart';

/// Where a [Cli]'s time comes from and where the timers of its inline
/// session run: the wall clock ([CliClock.system]), or one a test moves by
/// hand (the fake terminal's, `package:twk_cli/testing.dart`).
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
/// `package:twk_cli/testing.dart`, which captures what is written and
/// replays what is typed.
abstract class CliTerminal {
  /// A terminal subclasses build on.
  CliTerminal();

  /// The process's stdio: `stdin`, `stdout` and `stderr`, or [out] for
  /// what goes to stdout: `stderr` where stdout is reserved (a server
  /// speaking JSON-RPC on it).
  ///
  /// Capabilities are detected once, from stdio and [environment] (the
  /// process environment by default); [ansi], [interactive] and
  /// [hyperlinks] override detection, see [CliCapabilities.detect].
  factory CliTerminal.system({
    io.Stdout? out,
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
    io.Stdout? out,
    this._environment,
    this._ansi,
    this._interactive,
    this._hyperlinks,
  }) : _out = out ?? io.stdout;

  final io.Stdout _out;
  final Map<String, String>? _environment;
  final bool? _ansi;
  final bool? _interactive;
  final bool? _hyperlinks;

  Map<String, String> get _env => _environment ?? io.Platform.environment;

  @override
  late final capabilities = CliCapabilities.detect(
    environment: _env,
    inputIsTerminal: io.stdin.hasTerminal,
    // the inline session draws on stdout: a redirected one has none
    outputIsTerminal: _out.hasTerminal && identical(_out, io.stdout),
    outputSupportsAnsi: _out.supportsAnsiEscapes,
    errorIsTerminal: io.stderr.hasTerminal,
    ansi: _ansi,
    interactive: _interactive,
    hyperlinks: _hyperlinks,
    windows: io.Platform.isWindows,
  );

  @override
  StringSink get out => _out;

  @override
  StringSink get err => io.stderr;

  @override
  int? get columns {
    if (_out.hasTerminal) {
      return _out.terminalColumns;
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
    final lines = _lines ??= StreamIterator(
      io.stdin.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final echo = hidden && io.stdin.hasTerminal;
    StreamSubscription<io.ProcessSignal>? interrupted;
    if (echo) {
      io.stdin.echoMode = false;
      if (!io.Platform.isWindows) {
        // Ctrl+C ends the process as ever, the echo back on first
        interrupted = io.ProcessSignal.sigint.watch().listen((_) async {
          io.stdin.echoMode = true;
          _out.writeln();
          await interrupted?.cancel();
          io.Process.killPid(io.pid, io.ProcessSignal.sigint);
        });
      }
    }
    try {
      return await lines.moveNext() ? lines.current : null;
    } finally {
      if (echo) {
        await interrupted?.cancel();
        io.stdin.echoMode = true;
        _out.writeln();
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
  void interrupt() {
    if (io.Platform.isWindows) {
      io.exit(130);
    }
    io.Process.killPid(io.pid, io.ProcessSignal.sigint);
  }

  @override
  int get exitCode => io.exitCode;

  @override
  set exitCode(int code) => io.exitCode = code;

  @override
  Future<void> flush() async {
    await _out.flush();
    await io.stderr.flush();
  }

  @override
  Future<void> close() async {
    final lines = _lines;
    _lines = null;
    _closed = true;
    await lines?.cancel();
  }
}
