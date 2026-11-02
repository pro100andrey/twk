/// The process packages/twk runs in, from dart:io: `platform.dart` on the
/// VM.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate' show Isolate;
import 'dart:math' show max;

import 'file_identity.dart';
import 'tail_event.dart';

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

/// Streams the bytes written to the file at [path] from when the stream is
/// listened to, or with [fromEnd] false from its start, as they come: told
/// by a watch of its directory where the system has one, and found by a
/// look at its size each [poll] all the same, where a watch misses a write
/// or does not work (a network drive). A file cut shorter than what was
/// read (truncated, written anew) is read again from its start; one not
/// there yet is waited for. Where one is read again from its start, the
/// stream holds a [FileReset] first. Ends when the subscription is cancelled.
///
/// A file replaced at [path] (another renamed over it, as log rotation and
/// atomic saves do) is read from its start too, but only where the watch
/// works: it tells the create or move of the name, by the file's own
/// history: a create or move onto the name after the file was seen not there
/// (before the stream was listened to, or by a look) is that file's
/// appearance, however late after a look found it, and replaces nothing; any
/// other is a replacement, whatever the bytes the two files start with. The
/// order of the events among themselves is not relied on. The poll alone cannot
/// tell it, `dart:io` giving no inode, so a replacement no longer than
/// what was read goes unseen on a platform without a directory watch (or
/// on a drive where it misses events), and a longer one is read from the
/// old position.
///
/// The poll runs on the timer [startPeriodic] starts (`Timer.periodic` by
/// default): an app's passes its binding's (`AppBinding.startPeriodic`), so
/// that its clock moves the poll wherever the stream is listened to.
Stream<TailEvent> tailFile(
  String path, {
  required bool fromEnd,
  required Duration poll,
  Timer Function(Duration, void Function(Timer)) startPeriodic = Timer.periodic,
}) {
  final file = File(path);
  final name = file.uri.pathSegments.last;
  StreamSubscription<FileSystemEvent>? watch;
  Timer? timer;
  var position = 0;
  var reading = false;
  var again = false;
  var cancelled = false;
  // a file made or moved onto the name: read from its start
  var replaced = false;
  // the file was seen not there (at the start, or by a look) and has not been
  // put there by an event since: the next create or move onto the name is
  // that file's own appearance, however late after a look found it, and
  // replaces nothing
  var owed = false;
  // where the platform tells files apart (macOS): the file the name held at
  // the last look, a look that finds another replacing it whatever the
  // watch's events said
  FileIdentity? held;
  late final StreamController<TailEvent> out;

  Future<int> length() async {
    try {
      return await file.length();
    } on FileSystemException {
      owed = true;
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
        if (knowsFileIdentity) {
          final now = fileIdentity(path);
          if (now != null) {
            replaced = replaced || (held != null && now != held);
            held = now;
          }
        }
        if (replaced) {
          replaced = false;
          if (position > 0) {
            out.add(const FileReset());
            position = 0;
          }
        }
        final end = await length();
        if (cancelled) {
          return;
        }
        if (end < position) {
          out.add(const FileReset());
          position = 0;
        }
        if (end > position) {
          await for (final bytes in file.openRead(position, end)) {
            if (cancelled) {
              return;
            }
            out.add(FileBytes(bytes));
            // told: a read that fails further on goes on from here
            position += bytes.length;
          }
        }
      } while (again && !cancelled);
    } on FileSystemException {
      // gone while it was read: looked at again at the next event or poll
    } finally {
      reading = false;
    }
  }

  out = StreamController<TailEvent>(
    onListen: () {
      // the end as the stream is listened to, before anything else can
      // write: a write after it is read
      held = fileIdentity(path);
      if (fromEnd) {
        try {
          position = file.lengthSync();
        } on FileSystemException {
          position = 0;
          owed = true;
        }
      } else {
        owed = !file.existsSync();
      }
      if (FileSystemEntity.isWatchSupported) {
        try {
          watch = file.parent.watch().where((e) => _names(e, name)).listen((e) {
            // where files are told apart the look decides; macOS tells a
            // write to a file made just before the watch as its making
            if (!knowsFileIdentity && _replaces(e, name)) {
              if (owed) {
                owed = false;
              } else {
                replaced = true;
              }
            }
            unawaited(look());
          }, onError: (Object _) {});
        } on FileSystemException {
          // no watch of the directory: the poll alone
        }
      }
      timer = startPeriodic(poll, (_) => look());
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

/// Whether [e] is of the entry called [name]: made, written, removed, or
/// moved from or onto it.
bool _names(FileSystemEvent e, String name) =>
    _baseName(e.path) == name || _movedOnto(e, name);

/// The last segment of [path], the name of the entry.
String _baseName(String path) {
  final slash = path.lastIndexOf('/');
  final cut = Platform.isWindows ? max(slash, path.lastIndexOf(r'\')) : slash;
  return path.substring(cut + 1);
}

/// Whether [e] puts a file at [name]: made there, or moved onto it.
bool _replaces(FileSystemEvent e, String name) =>
    e is FileSystemCreateEvent || _movedOnto(e, name);

bool _movedOnto(FileSystemEvent e, String name) {
  if (e is! FileSystemMoveEvent) {
    return false;
  }
  final to = e.destination;
  return to != null && _baseName(to) == name;
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
