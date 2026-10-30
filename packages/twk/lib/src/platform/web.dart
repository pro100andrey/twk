/// What stands in on the web for the process packages/twk runs in
/// (`platform.dart`; `io.dart` on the VM): there is no environment and no
/// file system. Nothing is at any path, the working directory is the root;
/// what would list a directory, read or write a file fails with
/// [UnsupportedError]: a `FilePicker` says it cannot list, the log console
/// is not saved; no file has a size and no directory changes.
library;

import 'dart:async';

/// None on the web.
Map<String, String> get environment => const {};

/// False on the web.
bool get isWindows => false;

/// `/` on the web.
String get pathSeparator => '/';

/// 0 on the web.
int get processId => 0;

/// `/` on the web.
String get currentDirectory => '/';

/// [name] on the web, which has no directory for temporary files.
String tempFile(String name) => name;

/// What is at a path ([kindOf]).
enum FileKind {
  /// A directory, or a link to one.
  directory,

  /// Something else: a file, a link to one, a pipe or a socket.
  file,

  /// Nothing.
  none,
}

/// [FileKind.none] on the web.
FileKind kindOf(String path) => FileKind.none;

/// An entry of a directory ([listDirectory]): its path, and whether it is
/// a directory or a link to one.
typedef DirectoryEntry = ({String path, bool isDirectory});

/// Fails with [UnsupportedError].
Stream<DirectoryEntry> listDirectory(String path) => Stream.error(_noFiles());

/// Fails with [UnsupportedError].
Future<String> readFile(String path) async => throw _noFiles();

/// Null on the web, which has no files.
Future<int?> fileSize(String path) async => null;

/// Ends at once: the web has no directories to watch.
Stream<void> watchDirectory(String path) => const Stream.empty();

/// Fails with [UnsupportedError].
Future<void> writeFile(String path, String text) async => throw _noFiles();

/// Null on the web, which has no files.
String? sourcePath(Uri uri) => null;

/// Null on the web, which has no files.
List<String>? readLines(String path) => null;

/// What [error], from one of the above, says: the message of an
/// [UnsupportedError].
String describeFileError(Object error) =>
    error is UnsupportedError ? error.message ?? '$error' : '$error';

UnsupportedError _noFiles() => UnsupportedError('no file system on the web');

/// Fails with [UnsupportedError]: the web starts no programs.
Future<void> startApart(String executable, List<String> arguments) async =>
    throw UnsupportedError('no programs to start on the web');

/// Fails with [UnsupportedError]: the web runs no programs.
Future<int> runOnTerminal(String executable, List<String> arguments) async =>
    throw UnsupportedError('no programs to run on the web');

/// False: there is no stdin on the web.
bool get stdinIsTerminal => false;

/// False: there is no stdio on the web.
bool stdioIsTerminal({bool error = false}) => false;

/// False: there is no stdio on the web.
bool stdioSupportsAnsi({bool error = false}) => false;

/// 0: there is no terminal of the process on the web.
int stdioColumns({bool error = false}) => 0;

/// A sink that drops what is written: there is no stdio on the web.
StringSink stdioSink({bool error = false}) => _Dropped();

/// Nothing to flush on the web.
Future<void> flushStdio() async {}

/// No lines: there is no stdin on the web.
Stream<String> stdinLines() => const Stream.empty();

/// Nothing to switch on the web.
set stdinEcho(bool on) {}

/// Null: there is no signal on the web.
StreamSubscription<void>? watchInterrupt(void Function() onInterrupt) => null;

/// Nothing to interrupt on the web.
void interruptProcess() {}

/// The code the process would end with, kept: nothing ends on the web.
var processExitCode = 0;

final class _Dropped implements StringSink {
  @override
  void write(Object? object) {}

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? object = '']) {}
}
