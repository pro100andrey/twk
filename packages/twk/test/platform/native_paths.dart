// The paths of the tests that write theirs as POSIX ones, in the
// platform's form: the names and paths a FilePicker and a DirectoryTree
// show, and the absolute paths of a tree in memory, which are a drive's
// on Windows (paths_test.dart).
import 'dart:io';

/// The platform's separator: `\` on Windows, `/` elsewhere.
final String sep = Platform.pathSeparator;

/// [posix], written with `/`, with the platform's separator.
String native(String posix) => posix.replaceAll('/', sep);

/// [posix], an absolute path from `/`, as the same path of a tree in
/// memory is on this platform: as it is on Linux and macOS, from the root
/// of the drive `C:` on Windows (`/home/me` is `C:\home\me`).
String rooted(String posix) =>
    Platform.isWindows ? 'C:${native(posix)}' : posix;
