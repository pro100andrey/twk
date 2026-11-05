/// The libc calls twk's packages bind on Linux and macOS, through
/// `dart:ffi` (no `package:ffi`), with the constants those give them: what
/// the core reads the terminal with, and what a `Pty` of twk_term and twk's
/// file watch take too. A symbol is looked up in the process on its first
/// call, so one a platform lacks is never touched there.
library;

import 'dart:ffi';
import 'dart:io' show Platform;

final bool _macos = Platform.isMacOS;

/// `struct pollfd`, the same on Linux and macOS.
final class PollFd extends Struct {
  /// The file descriptor polled.
  @Int()
  external int fd;

  /// The events waited for: [pollIn], [pollOut].
  @Short()
  external int events;

  /// The events that happened, set by [poll]: those of [events], and
  /// [pollErr], [pollHup] or [pollNval].
  @Short()
  external int revents;
}

/// POLLIN: there is data to read.
const pollIn = 0x1;

/// POLLOUT: a write would not block.
const pollOut = 0x4;

/// POLLERR: the descriptor has an error.
const pollErr = 0x8;

/// POLLHUP: the other end hung up.
const pollHup = 0x10;

/// POLLNVAL: the descriptor is not open.
const pollNval = 0x20;

/// F_GETFL, for [fcntl]: the descriptor's status flags.
const fGetfl = 3;

/// F_SETFL, for [fcntl]: sets the descriptor's status flags.
const fSetfl = 4;

/// O_NONBLOCK: a call on the descriptor does not block.
final oNonblock = _macos ? 0x4 : 0x800;

/// EINTR: a call interrupted by a signal.
const eintr = 4;

/// EAGAIN: a non-blocking call would block.
final eagain = _macos ? 35 : 11;

/// TCSANOW, for [tcsetattr]: the attributes change at once.
const tcsanow = 0;

/// FIONREAD, for [ioctl]: how many bytes a descriptor holds to be read (an
/// `int`).
final fionread = _macos ? 0x4004667F : 0x541B;

/// calloc(3): [count] zeroed elements of [size] bytes, or `nullptr`.
@Native<Pointer<Void> Function(Size, Size)>(isLeaf: true)
external Pointer<Void> calloc(int count, int size);

/// free(3): frees [p], taken from [calloc].
@Native<Void Function(Pointer<Void>)>(isLeaf: true)
external void free(Pointer<Void> p);

@Native<Pointer<Int> Function()>(symbol: '__errno_location', isLeaf: true)
external Pointer<Int> _errnoLinux();

@Native<Pointer<Int> Function()>(symbol: '__error', isLeaf: true)
external Pointer<Int> _errnoMacos();

/// errno, read right after the leaf call that set it: after one that is
/// not a leaf call the VM may have changed it.
int get errno => (_macos ? _errnoMacos() : _errnoLinux()).value;

/// close(2): closes [fd]; 0, or -1.
@Native<Int Function(Int)>(isLeaf: true)
external int close(int fd);

/// read(2): reads at most [count] bytes of [fd] into [buf]; how many,
/// 0 at the end, or -1. A leaf call: read only what is there (after
/// [poll], or as many as [fionread] says), or it blocks the isolate's
/// thread.
@Native<Long Function(Int, Pointer<Void>, Size)>(isLeaf: true)
external int read(int fd, Pointer<Void> buf, int count);

/// write(2): writes at most [count] bytes of [buf] to [fd]; how many, or
/// -1. A leaf call, like [read].
@Native<Long Function(Int, Pointer<Void>, Size)>(isLeaf: true)
external int write(int fd, Pointer<Void> buf, int count);

/// fcntl(2): [command] ([fGetfl], [fSetfl]) on [fd], with [arg]; what it
/// gives, or -1. A leaf call, like [read].
@Native<Int Function(Int, Int, VarArgs<(Int,)>)>(isLeaf: true)
external int fcntl(int fd, int command, int arg);

/// pipe(2): a pipe, its read end in `fds[0]`, its write end in `fds[1]`;
/// 0, or -1.
@Native<Int Function(Pointer<Int>)>(isLeaf: true)
external int pipe(Pointer<Int> fds);

/// poll(2): waits for the events of [count] descriptors of [fds], at most
/// [timeout] milliseconds (-1 for ever); how many have some, 0 when the
/// time ran out, or -1 (a signal came: EINTR).
///
/// Not a leaf call, as it blocks: the VM goes on while it waits, and errno
/// after it can't be trusted.
@Native<Int Function(Pointer<PollFd>, UnsignedLong, Int)>()
external int poll(Pointer<PollFd> fds, int count, int timeout);

/// ioctl(2): the [request] ([fionread], …) on [fd] with [arg]; -1 on an
/// error.
@Native<Int Function(Int, UnsignedLong, VarArgs<(Pointer<Void>,)>)>(
  isLeaf: true,
)
external int ioctl(int fd, int request, Pointer<Void> arg);

/// tcgetattr(3): reads the attributes of the terminal [fd] into
/// [termios]; 0, or -1.
@Native<Int Function(Int, Pointer<Void>)>(isLeaf: true)
external int tcgetattr(int fd, Pointer<Void> termios);

/// tcsetattr(3): sets the attributes of the terminal [fd] to [termios],
/// [when] ([tcsanow], …) says when; 0, or -1.
///
/// Not a leaf call: TCSAFLUSH and TCSADRAIN wait for the output to be
/// sent.
@Native<Int Function(Int, Int, Pointer<Void>)>()
external int tcsetattr(int fd, int when, Pointer<Void> termios);
