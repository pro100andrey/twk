/// The process's own terminal as a [TerminalLink]: stdin and stdout.
library;

import 'dart:io';

import 'link.dart';
import 'posix_tty.dart';
import 'windows_console.dart';

/// The process's own terminal: stdin and stdout.
final class StdioLink implements TerminalLink {
  WindowsConsole? _windowsConsole;
  PosixTty? _tty;
  var _echo = true;
  var _line = true;

  @override
  Map<String, String> get environment => Platform.environment;

  @override
  bool get windows => Platform.isWindows;

  @override
  int get columns => stdout.terminalColumns;

  @override
  int get lines => stdout.terminalLines;

  @override
  int? get eraseChar => _tty?.eraseChar;

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

  @override
  Stream<List<int>> get input => stdin;

  @override
  void add(List<int> bytes) => stdout.add(bytes);

  @override
  Future<void> flush() => stdout.flush();

  @override
  Stream<void> get resizes => Platform.isWindows
      // no SIGWINCH on Windows; the size query is a cheap console call
      ? Stream<void>.periodic(const Duration(milliseconds: 100))
      : ProcessSignal.sigwinch.watch().map((_) {});

  @override
  void restoreWith(List<int> bytes) {}

  @override
  Future<void> close() async {}
}
