/// The process packages/twk runs in, from dart:io: `platform.dart` on the
/// VM.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate' show Isolate;
import 'dart:math' show max, min;

import 'file_identity.dart';
import 'follow_machine.dart';
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
/// order of the events among themselves, and of them and a look, is not
/// relied on. The poll alone cannot tell it, `dart:io` giving no inode, so a
/// replacement no longer than what was read goes unseen on a platform
/// without a directory watch (or on a drive where it misses events), and a
/// longer one is read from the old position.
///
/// A look that has something to read opens the file once: its length and
/// the range read are of that one handle, so a file renamed over the name in
/// the middle of a look is never read at the old file's range; the look is
/// made again when the watch told a file put at the name since it began. A
/// look the name tells nothing new to opens nothing: Windows refuses a
/// writer the rename or delete of a file open anywhere, so a follower that
/// held the file at each poll would fail its rotation.
///
/// The future of the subscription's `cancel` ends with the look under way,
/// its handle closed: on Windows the file can be deleted after it. A look is
/// real I/O and goes on in the root zone with the watch, their turns no fake
/// clock's, so that the cancel ends under a clock nobody moves; only the poll
/// is the zone's.
///
/// What is a start over and what to read is decided by a [FollowMachine];
/// the stream is the file, the watch and the poll around it. The poll runs
/// on `Timer.periodic` of the zone the stream is listened to in, so a
/// test's fake clock moves it; [startPeriodic] starts it otherwise.
Stream<TailEvent> tailFile(
  String path, {
  required bool fromEnd,
  required Duration poll,
  Timer Function(Duration, void Function(Timer)) startPeriodic = Timer.periodic,
}) {
  final file = File(path);
  final name = file.uri.pathSegments.last;
  final machine = FollowMachine(
    tellsIdentity: knowsFileIdentity,
    eventsTell: !Platform.isMacOS,
  );
  StreamSubscription<FileSystemEvent>? watch;
  Timer? timer;
  var reading = false;
  var again = false;
  var cancelled = false;
  var looked = Completer<void>()..complete();
  late final StreamController<TailEvent> out;

  // The file the name holds, opened once for a look, with its identity
  // taken by the name on both sides of the open: where the two differ a file
  // was put at the name meanwhile and the handle may be of either, so it is
  // opened again. Null where there is no file.
  Future<(RandomAccessFile, Object?)?> openFile() async {
    for (var tries = 0; ; tries++) {
      final before = fileIdentity(path);
      final RandomAccessFile handle;
      try {
        handle = await file.open();
      } on FileSystemException {
        return null;
      }
      // given up on, the later identity, the handle being likelier that
      // file's, unless the name holds nothing by now
      final after = fileIdentity(path);
      if (before == after || tries >= 3) {
        return (handle, after ?? before);
      }
      await handle.close();
    }
  }

  Future<void> look() async {
    if (reading) {
      again = true;
      return;
    }
    reading = true;
    looked = Completer<void>();
    try {
      do {
        again = false;
        final began = machine.beginLook();
        int? named;
        try {
          named = await file.length();
        } on FileSystemException {
          named = null;
        }
        if (cancelled) {
          return;
        }
        if (machine.settled(size: named, identity: fileIdentity(path))) {
          continue;
        }
        // one handle a look: the length and the range read are of the one
        // file, whatever is renamed over the name in between
        final opened = await openFile();
        final handle = opened?.$1;
        try {
          if (cancelled) {
            return;
          }
          final size = await handle?.length();
          if (cancelled) {
            return;
          }
          if (handle != null && machine.putSince(began)) {
            // a file was put at the name since the look began, and the
            // handle may be of the file it replaced: the event stays, and
            // the look is made again with a handle of the file now there
            again = true;
            continue;
          }
          final plan = machine.look(began, size: size, identity: opened?.$2);
          if (plan.reset) {
            out.add(const FileReset());
          }
          if (handle != null && plan.reads) {
            await handle.setPosition(plan.from);
            var at = plan.from;
            while (at < plan.to) {
              final bytes = await handle.read(min(plan.to - at, _readChunk));
              if (cancelled) {
                return;
              }
              if (bytes.isEmpty) {
                break;
              }
              at += bytes.length;
              out.add(FileBytes(bytes));
              // told: a read that fails further on goes on from here
              machine.told(bytes.length);
            }
          }
        } finally {
          await handle?.close();
        }
      } while (again && !cancelled);
    } on FileSystemException {
      // gone while it was read: looked at again at the next event or poll
    } finally {
      reading = false;
      looked.complete();
    }
  }

  void lookNow() => unawaited(Zone.root.run(look));

  out = StreamController<TailEvent>(
    onListen: () {
      // the end as the stream is listened to, before anything else can
      // write: a write after it is read
      int? size;
      try {
        size = file.lengthSync();
      } on FileSystemException {
        size = null;
      }
      machine.start(
        fromEnd: fromEnd,
        size: size,
        identity: fileIdentity(path),
      );
      if (FileSystemEntity.isWatchSupported) {
        try {
          void onEvent(FileSystemEvent e) {
            machine.nameEvent(puts: _replaces(e, name));
            lookNow();
          }

          // a watch that fails (its queue overflowed, the directory gone)
          // has lost events: a look now, and the poll goes on, read what was
          // written; a file put at the name among the lost is told where
          // files are told apart, elsewhere only once it is shorter
          void onError(Object _) {
            machine.eventsLost();
            lookNow();
          }

          // in the zone of the looks: what a look reads and what the watch
          // tells keep the order they happen in
          watch = Zone.root.run(
            () => file.parent
                .watch()
                .where((e) => _names(e, name))
                .listen(onEvent, onError: onError),
          );
        } on FileSystemException {
          // no watch of the directory: the poll alone
        }
      }
      timer = startPeriodic(poll, (_) => lookNow());
      lookNow();
    },
    onCancel: () async {
      cancelled = true;
      timer?.cancel();
      await watch?.cancel();
      await looked.future;
      unawaited(out.close());
    },
  );
  return out.stream;
}

/// The most bytes one read of a look takes: what a file stream reads at a
/// time.
const int _readChunk = 64 * 1024;

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
