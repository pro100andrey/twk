/// The process packages/twk runs in, from dart:io: `platform.dart` on the
/// VM.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate' show Isolate;

/// The process's environment.
Map<String, String> get environment => Platform.environment;

/// Whether the process runs on Windows.
bool get isWindows => Platform.isWindows;

/// `\` on Windows, `/` elsewhere.
String get pathSeparator => Platform.pathSeparator;

/// The process's id.
int get processId => pid;

/// The path of the working directory.
String get currentDirectory => Directory.current.path;

/// The path of the file named [name] in the system's directory for
/// temporary files.
String tempFile(String name) =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}$name';

/// What is at a path ([kindOf]).
enum FileKind {
  /// A directory, or a link to one.
  directory,

  /// Something else: a file, a link to one, a pipe or a socket.
  file,

  /// Nothing.
  none,
}

/// What is at [path], links followed.
FileKind kindOf(String path) => switch (FileSystemEntity.typeSync(path)) {
  FileSystemEntityType.directory => FileKind.directory,
  FileSystemEntityType.notFound => FileKind.none,
  _ => FileKind.file,
};

/// An entry of a directory ([listDirectory]): its path, and whether it is
/// a directory or a link to one.
typedef DirectoryEntry = ({String path, bool isDirectory});

/// The entries of the directory at [path], or the error listing it fails
/// with.
Stream<DirectoryEntry> listDirectory(String path) =>
    Directory(path)
        .list()
        .map((entity) => (path: entity.path, isDirectory: entity is Directory));

/// The text of the file at [path], read as UTF-8, or the error reading it
/// fails with.
Future<String> readFile(String path) => File(path).readAsString();

/// The size in bytes of the file at [path]; null where it cannot be told.
Future<int?> fileSize(String path) async {
  try {
    return await File(path).length();
  } on FileSystemException {
    return null;
  }
}

/// An event each time an entry of the directory at [path] is made,
/// removed, moved or written to: of its own entries, not of those below
/// them. It fails where the directory cannot be watched, and ends once it
/// is removed.
Stream<void> watchDirectory(String path) {
  try {
    return Directory(path).watch().map<void>((_) {});
  } on FileSystemException catch (error) {
    return Stream.error(error);
  }
}

/// The bytes written to the file at [path] from now on, or with [fromEnd]
/// false from its start, as they come: told by a watch of its directory
/// where the system has one, and found by a look at its size each [poll]
/// all the same, where a watch misses a write or does not work (a network
/// drive). A file cut shorter than what was read (truncated, written anew)
/// is read again from its start; one not there yet is waited for. Ends
/// when the subscription is cancelled.
Stream<List<int>> tailFile(
  String path, {
  required bool fromEnd,
  required Duration poll,
}) {
  final file = File(path);
  final name = file.uri.pathSegments.last;
  StreamSubscription<FileSystemEvent>? watch;
  Timer? timer;
  var position = 0;
  var reading = false;
  var again = false;
  var cancelled = false;
  late final StreamController<List<int>> out;

  Future<int> length() async {
    try {
      return await file.length();
    } on FileSystemException {
      return 0;
    }
  }

  Future<void> look() async {
    if (reading) {
      again = true;
      return;
    }
    reading = true;
    try {
      do {
        again = false;
        final end = await length();
        if (end < position) {
          position = 0;
        }
        if (end > position) {
          await for (final bytes in file.openRead(position, end)) {
            if (cancelled) {
              return;
            }
            out.add(bytes);
          }
          position = end;
        }
      } while (again && !cancelled);
    } on FileSystemException {
      // gone while it was read: looked at again at the next event or poll
    } finally {
      reading = false;
    }
  }

  out = StreamController<List<int>>(
    onListen: () async {
      if (fromEnd) {
        position = await length();
      }
      if (cancelled) {
        return;
      }
      if (FileSystemEntity.isWatchSupported) {
        try {
          watch = file.parent
              .watch()
              .where((e) => e.path.endsWith(name))
              .listen((_) => look(), onError: (Object _) {});
        } on FileSystemException {
          // no watch of the directory: the poll alone
        }
      }
      timer = Timer.periodic(poll, (_) => look());
      unawaited(look());
    },
    onCancel: () async {
      cancelled = true;
      timer?.cancel();
      await watch?.cancel();
      unawaited(out.close());
    },
  );
  return out.stream;
}

/// Writes [text] to the file at [path] in place of what it held.
Future<void> writeFile(String path, String text) =>
    File(path).writeAsString(text);

/// The path of the file a frame of a stack trace whose URI is [uri] is
/// in: that of a `file:` URI, or of a `package:` URI as the program
/// resolves it; null for a URI of another scheme, and for a package the
/// program can't resolve, as an AOT build resolves none.
String? sourcePath(Uri uri) {
  final file = uri.isScheme('package')
      ? Isolate.resolvePackageUriSync(uri)
      : uri;
  return file != null && file.isScheme('file') ? file.toFilePath() : null;
}

/// The lines of the text file at [path]; null where there is none to
/// read: no file there, or one that is not UTF-8.
List<String>? readLines(String path) {
  try {
    return File(path).readAsLinesSync();
  } on FileSystemException {
    return null;
  }
}

/// What [error], from one of the above, says: the system's message for a
/// [FileSystemException].
String describeFileError(Object error) => error is FileSystemException
    ? error.osError?.message ?? error.message
    : '$error';

/// Starts [executable] with [arguments] apart from this process, which
/// waits for nothing of it: an editor with a window of its own.
Future<void> startApart(String executable, List<String> arguments) async {
  await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.detached,
  );
}

/// Runs [executable] with [arguments] on this process's terminal (its
/// stdin, stdout and stderr) until it ends; its exit code.
Future<int> runOnTerminal(String executable, List<String> arguments) async {
  final p = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );
  return p.exitCode;
}

/// Whether stdin is a terminal.
bool get stdinIsTerminal => stdin.hasTerminal;

/// Stdout, or stderr with [error].
Stdout _stdio({required bool error}) => error ? stderr : stdout;

/// Whether stdout, or stderr with [error], is a terminal.
bool stdioIsTerminal({bool error = false}) => _stdio(error: error).hasTerminal;

/// Whether stdout, or stderr with [error], takes ANSI escapes.
bool stdioSupportsAnsi({bool error = false}) =>
    _stdio(error: error).supportsAnsiEscapes;

/// How many columns wide the terminal stdout (stderr with [error]) is.
int stdioColumns({bool error = false}) => _stdio(error: error).terminalColumns;

/// Stdout, or stderr with [error], as the sink text is written to.
StringSink stdioSink({bool error = false}) => _stdio(error: error);

/// Flushes stdout and stderr.
Future<void> flushStdio() async {
  await stdout.flush();
  await stderr.flush();
}

/// The lines read from stdin, as UTF-8, without their line breaks.
Stream<String> stdinLines() =>
    stdin.transform(utf8.decoder).transform(const LineSplitter());

/// Switches the echo of what is typed at stdin on or off.
set stdinEcho(bool on) => stdin.echoMode = on;

/// Calls [onInterrupt] on each SIGINT, which then does not end the
/// process, until the subscription is cancelled; null on Windows, which
/// has no SIGINT to watch.
StreamSubscription<void>? watchInterrupt(void Function() onInterrupt) =>
    Platform.isWindows
    ? null
    : ProcessSignal.sigint.watch().listen((_) => onInterrupt());

/// Interrupts the process as Ctrl+C at a cooked terminal does: SIGINT to
/// itself, which ends it unless it watches the signal; on Windows, its end
/// with 130.
void interruptProcess() {
  if (Platform.isWindows) {
    exit(130);
  }
  Process.killPid(pid, ProcessSignal.sigint);
}

/// The code the process ends with.
int get processExitCode => exitCode;

set processExitCode(int code) => exitCode = code;
