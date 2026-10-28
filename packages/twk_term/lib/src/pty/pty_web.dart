/// [Pty] on the web, which has no pseudo-terminals and no processes: the
/// same members as on the VM (`pty.dart`), [Pty.start] throwing, so that an
/// app with a `TerminalSession` over a link of its own (a scripted shell,
/// a remote terminal) compiles for the browser too.
library;

// The members are the VM's, so that one app compiles for both; on the web
// they take what they are given and do nothing with it.
// ignore_for_file: avoid_unused_constructor_parameters

import 'dart:async';
import 'dart:typed_data';

/// A program run in a pseudo-terminal; on the web there is none, and
/// [Pty.start] throws an [UnsupportedError].
///
/// ```dart
/// try {
///   Pty.start('ls', const []);
/// } on UnsupportedError {
///   // in a browser
/// }
/// ```
final class Pty {
  /// Throws an [UnsupportedError]: a browser runs no programs.
  factory Pty.start(
    String executable,
    List<String> arguments, {
    int width = 80,
    int height = 24,
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) => throw UnsupportedError('Pty runs on Linux and macOS only');

  /// The program's process id; there is none on the web.
  int get pid => -1;

  /// The terminal's device name; there is none on the web.
  String get ttyName => '';

  /// What the program writes to its terminal; nothing on the web.
  Stream<Uint8List> get output => const Stream.empty();

  /// The program's exit code; there is none on the web.
  Future<int?> get exitCode => Future.value();

  /// How many columns the terminal has.
  int get width => 0;

  /// How many rows the terminal has.
  int get height => 0;

  /// Hands [bytes] to the program; nothing on the web.
  void write(List<int> bytes) {}

  /// Sets the terminal's size; nothing on the web.
  void resize(int width, int height) {}

  /// Sends the program [signal]; false on the web, where none runs.
  bool kill([Object? signal]) => false;

  /// Hangs the terminal up; nothing on the web.
  void close() {}
}
