/// What stands in on the web for the process the core runs in
/// (`platform.dart`; `io.dart` on the VM): there is no environment, no
/// stdin or stdout, no signals, files or local sockets. What would watch
/// does nothing; what would open, read, write or serve throws
/// [UnsupportedError]. A terminal there is one over a link
/// (`Terminal.overLink`). The web build is dart2wasm: dart2js compiles
/// this too, but its Uint64List and Int64List throw at run time.
library;

import 'dart:async';
import 'dart:typed_data';

import '../terminal/link.dart';

/// None on the web.
Map<String, String> get environment => const {};

/// Whether the process runs on Windows: false on the web.
bool get isWindows => false;

/// 0 on the web.
int get processId => 0;

/// None on the web.
TerminalLink? ownTerminalLink() => null;

/// False: there is no stdout on the web.
bool get outputIsTerminal => false;

/// Throws [UnsupportedError]: there is no stdout on the web.
TerminalLink plainStdio() =>
    throw UnsupportedError('no plain output on the web: no stdout');

/// Prints [line] outside any zone: to the console.
void printError(Object? line) => Zone.root.print('$line');

/// Throws [UnsupportedError].
void appendFile(String path, String text) => throw _noFiles(path);

/// Throws [UnsupportedError].
Uint8List readFile(String path) => throw _noFiles(path);

/// A file being written ([createFile]).
typedef FileWriter = ({
  Future<void> Function(List<int> bytes) write,
  Future<void> Function() close,
});

/// Throws [UnsupportedError].
FileWriter createFile(String path, List<int> header) => throw _noFiles(path);

/// None on the web.
List<StreamSubscription<void>> watchSignals(
  void Function() interrupt,
  Future<void> Function() terminate,
) => const [];

/// Throws [UnsupportedError].
void stopProcessGroup() => throw UnsupportedError('no job control on the web');

UnsupportedError _noFiles(String path) =>
    UnsupportedError('no files on the web: $path');

UnsupportedError _noSockets(String what) =>
    UnsupportedError('$what: no local sockets on the web');

/// A local socket's address: never made on the web.
abstract final class LocalAddress {
  /// The TCP port of the socket, 0 for a Unix domain socket.
  int get port;

  /// What a client sends first to be served.
  String get token;
}

/// What a [TerminalShell] tells the command around it.
enum ShellEvent {
  /// An app connected and has the terminal.
  connected,

  /// The app went away and the terminal is back as before it came.
  disconnected,
}

/// The link to a `twk shell`: never made on the web.
abstract final class SocketLink implements TerminalLink {
  /// Throws [UnsupportedError].
  static Future<SocketLink> connect(LocalAddress address) async =>
      throw _noSockets('Terminal.connect');

  /// Throws [UnsupportedError]: `Terminal.open` finds no terminal of its
  /// own on the web.
  static Future<SocketLink?> toShell([
    String? directory,
    Map<String, String> env = const {},
  ]) async => throw UnsupportedError(
    'Terminal.open: no terminal of its own on the web; '
    'Terminal.overLink opens one over a link',
  );
}

/// A `twk shell`: never made on the web.
abstract final class TerminalShell {
  /// Throws [UnsupportedError].
  static Future<TerminalShell> start({
    String? directory,
    void Function(ShellEvent event)? onEvent,
  }) async => throw _noSockets('TerminalShell');

  /// Where the shell listens.
  LocalAddress get address;
}

/// The socket a `LogSink` serves on: never made on the web.
abstract final class LogServer {
  /// Throws [UnsupportedError].
  static Future<LogServer> start(
    String? directory,
    Iterable<String> Function() backlog,
  ) async => throw _noSockets('LogSink.serve');

  /// Where the server listens.
  LocalAddress get address;

  /// Whether a client is sent the lines.
  bool get serving;

  /// Sends [line] to the clients.
  void send(String line);

  /// Closes the server.
  Future<void> close();
}
