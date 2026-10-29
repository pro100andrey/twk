/// The process the core runs in, from dart:io: `platform.dart` on the VM.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../terminal/link.dart';
import '../terminal/plain.dart';
import '../terminal/stdio_link.dart';

export '../terminal/address.dart' show LocalAddress;
export '../terminal/socket.dart' show ShellEvent, SocketLink, TerminalShell;
export 'log_server.dart' show LogServer;

/// The process's environment.
Map<String, String> get environment => Platform.environment;

/// Whether the process runs on Windows.
bool get isWindows => Platform.isWindows;

/// The process's id.
int get processId => pid;

/// The process's own terminal, stdin and stdout; null when either is not
/// one.
TerminalLink? ownTerminalLink() =>
    stdin.hasTerminal && stdout.hasTerminal ? StdioLink() : null;

/// Whether [link] is the process's own terminal ([ownTerminalLink]), the
/// controlling terminal of the shell that started it.
bool isOwnTerminal(TerminalLink link) => link is StdioLink;

/// Whether stdout is a terminal.
bool get outputIsTerminal => stdout.hasTerminal;

/// The process's output as plain text ([PlainLink]): stdout, with stdin
/// as its input where that is a terminal, and none otherwise.
TerminalLink plainStdio() => PlainLink(
  Platform.environment,
  add: stdout.add,
  flush: stdout.flush,
  input: stdin.hasTerminal ? stdin : null,
);

/// Writes [line] to stderr.
void printError(Object? line) => stderr.writeln(line);

/// Appends [text] to the file at [path], made if there is none.
void appendFile(String path, String text) =>
    File(path).writeAsStringSync(text, mode: FileMode.append);

/// The bytes of the file at [path].
Uint8List readFile(String path) => File(path).readAsBytesSync();

/// A file being written ([createFile]): one `write` on its way at a time.
typedef FileWriter = ({
  Future<void> Function(List<int> bytes) write,
  Future<void> Function() close,
});

/// Creates (or empties) the file at [path] and writes [header] to it.
FileWriter createFile(String path, List<int> header) {
  final file = File(path).openSync(mode: FileMode.write);
  try {
    file.writeFromSync(header);
  } on Object {
    file.closeSync();
    rethrow;
  }
  return (write: file.writeFrom, close: file.close);
}

/// SIGINT (a CTRL_C_EVENT on Windows) calls [interrupt]; SIGTERM, or on
/// Windows SIGHUP (the console being closed), awaits [terminate], then
/// exits with 143 or 129.
List<StreamSubscription<void>> watchSignals(
  void Function() interrupt,
  Future<void> Function() terminate,
) {
  StreamSubscription<ProcessSignal> exitOn(ProcessSignal s, int code) =>
      s.watch().listen((_) async {
        try {
          await terminate();
        } finally {
          exit(code);
        }
      });
  return [
    ProcessSignal.sigint.watch().listen((_) => interrupt()),
    // Windows: SIGHUP is the console being closed; SIGTERM isn't there
    if (Platform.isWindows)
      exitOn(ProcessSignal.sighup, 129)
    else
      exitOn(ProcessSignal.sigterm, 143),
  ];
}

/// SIGTSTP to the process's group (POSIX).
void stopProcessGroup() {
  Process.killPid(0, ProcessSignal.sigtstp);
}
