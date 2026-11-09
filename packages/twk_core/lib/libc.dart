/// The libc calls twk's packages share on Linux and macOS, bound through
/// `dart:ffi`: [poll] and [PollFd], [read], [write], [open], [ttyname],
/// [isatty], [signal], [getppid], [pipe], [close],
/// [ioctl] (with [fionread]), [tcgetattr] and [tcsetattr], [calloc] and
/// [free], and [errno]. The core reads the process's terminal with them,
/// twk_term's `Pty` drives a pseudo-terminal with them beside calls of its
/// own, and twk's file watch takes its memory from them.
///
/// For the VM on Linux and macOS: a symbol is looked up in the process on
/// its first call, so importing it costs nothing elsewhere, but calling one
/// on Windows or the web fails. It is no part of
/// `package:twk_core/twk_core.dart`, which compiles for the web too.
///
/// How many bytes the terminal on stdin holds, unread:
///
/// ```dart
/// import 'dart:ffi';
///
/// int unread() {
///   final n = calloc(1, sizeOf<Int>()).cast<Int>();
///   try {
///     return ioctl(0, fionread, n.cast()) == 0 ? n.value : 0;
///   } finally {
///     free(n.cast());
///   }
/// }
/// ```
///
/// @docImport 'src/platform/libc.dart';
library;

export 'src/platform/libc.dart';
