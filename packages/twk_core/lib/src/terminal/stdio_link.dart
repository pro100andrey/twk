/// The process's own terminal as a [TerminalLink]: stdin and stdout.
library;

import 'dart:io';

import '../platform/io.dart' show stdioIsTerminal;
import 'isolate_input.dart';
import 'link.dart';
import 'posix_input.dart';
import 'posix_output.dart';
import 'posix_tty.dart';
import 'windows_console.dart';
import 'windows_input.dart';

/// The process's own terminal: stdin and stdout.
final class StdioLink implements DrainingLink {
  WindowsConsole? _windowsConsole;
  PosixTty? _tty;
  var _echo = true;
  var _line = true;

  /// What writes to a terminal on Linux and macOS, so that one that reads
  /// nothing blocks nothing; elsewhere, and into a pipe or a file, `stdout`.
  late final PosixOutput? _output = !Platform.isWindows && stdioIsTerminal()
      ? PosixOutput.open()
      : null;

  @override
  int? get taken => _output?.taken;

  @override
  Map<String, String> get environment => Platform.environment;

  @override
  bool get windows => Platform.isWindows;

  /// The terminal's width; on one of no size (a pseudo-terminal `script`
  /// opens with no terminal around it), `COLUMNS` where it is a positive
  /// number, else 80.
  @override
  int get columns => _size(() => stdout.terminalColumns, 'COLUMNS', 80);

  /// The terminal's height; on one of no size, `LINES` where it is a
  /// positive number, else 24.
  @override
  int get lines => _size(() => stdout.terminalLines, 'LINES', 24);

  static int _size(int Function() read, String variable, int otherwise) {
    try {
      final n = read();
      if (n > 0) {
        return n;
      }
    } on StdoutException {
      // no size: as below
    }
    final given = int.tryParse(Platform.environment[variable] ?? '');
    return given != null && given > 0 ? given : otherwise;
  }

  @override
  int? get eraseChar => _tty?.eraseChar;

  /// Returns once this process may touch its terminal: in the background it
  /// stops until it is given it ([PosixTty.waitForForeground]). At once on
  /// Windows and where stdin is no terminal.
  static void waitForTerminal() {
    if (!Platform.isWindows && stdin.hasTerminal) {
      PosixTty.waitForForeground();
    }
  }

  @override
  void enterRaw() {
    if (Platform.isWindows) {
      final win = _windowsConsole;
      if (win != null) {
        win.enable();
        return;
      }
      if (!stdin.hasTerminal) {
        throw const TerminalException('not a terminal');
      }
      final first = WindowsConsole();
      if (!first.enable()) {
        throw const TerminalException(
          'this Windows console does not support VT sequences',
        );
      }
      _windowsConsole = first;
      return;
    }
    // before anything touches the terminal: in the background, wait for it
    waitForTerminal();
    try {
      // put back as found: a parent program may have turned echo off itself
      _echo = stdin.echoMode;
      _line = stdin.lineMode;
      stdin
        ..echoMode = false
        ..lineMode = false;
    } on StdinException {
      // a character device that is no terminal (/dev/null), which
      // stdin.hasTerminal takes for one
      throw const TerminalException('not a terminal');
    }
    (_tty ??= PosixTty.forStdin())?.enterRaw();
  }

  @override
  void restore() {
    final win = _windowsConsole;
    if (win != null) {
      win.restore();
      return;
    }
    _tty?.restore();
    try {
      stdin
        ..lineMode = _line
        ..echoMode = _echo;
    } on StdinException {
      // terminal already gone
    }
  }

  /// Where stdin is a terminal, read by an [IsolateInput] of its own (fd 0
  /// on Linux and macOS, [PosixInput]; the console on Windows,
  /// [WindowsInput]), which leaves it open once it is cancelled (dart:io's
  /// `stdin` closes it), for a program started after and for a later
  /// terminal; elsewhere (a pipe, a file) `stdin`.
  @override
  Stream<List<int>> get input => stdin.hasTerminal
      ? _read(WindowsInput.open()) ?? _read(PosixInput.open()) ?? stdin
      : stdin;

  // what [device] reads, where the platform has it (each is null off its
  // own platform)
  static Stream<List<int>>? _read<W extends Object>(InputDevice<W>? device) =>
      device == null ? null : IsolateInput(device).stream;

  @override
  void add(List<int> bytes) {
    final output = _output;
    if (output == null) {
      stdout.add(bytes);
    } else {
      output.add(bytes);
    }
  }

  @override
  Future<void> flush() => _output?.flush() ?? stdout.flush();

  @override
  Stream<void> get resizes => Platform.isWindows
      ? _consoleResizes()
      : ProcessSignal.sigwinch.watch().map((_) {});

  /// No SIGWINCH on Windows: the size is asked for ten times a second, a
  /// cheap console call, and told only when it is another. Told at each
  /// ask, a shell sent the app the size it had, ten times a second.
  static Stream<void> _consoleResizes() {
    int? columns;
    int? lines;
    void ask() {
      try {
        columns = stdout.terminalColumns;
        lines = stdout.terminalLines;
      } on StdoutException {
        columns = lines = null; // no console
      }
    }

    // the size it starts at, then each that differs from the last
    ask();
    return Stream<void>.periodic(const Duration(milliseconds: 100)).where((
      _,
    ) {
      final c = columns;
      final l = lines;
      ask();
      return columns != c || lines != l;
    });
  }

  @override
  void restoreWith(List<int> bytes) {}

  @override
  Future<void> close() async => _output?.close();
}
