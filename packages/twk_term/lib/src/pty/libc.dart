/// The libc calls a pseudo-terminal takes, bound through dart:ffi, with the
/// constants Linux (x86-64, arm64) and macOS give them. A symbol is looked
/// up on its first call, so one a platform lacks is never touched there.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

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

final bool _macos = Platform.isMacOS;

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

/// O_RDWR: opened for reading and writing.
const oRdwr = 2;

/// O_NOCTTY: a terminal opened does not become the controlling
/// terminal.
final oNoctty = _macos ? 0x20000 : 0x100;

/// O_NONBLOCK: reads and writes return at once.
final oNonblock = _macos ? 0x4 : 0x800;

/// O_CLOEXEC: the descriptor is closed in a program exec'd.
final oCloexec = _macos ? 0x1000000 : 0x80000;

/// F_GETFD, for [fcntl]: the descriptor's flags.
const fGetfd = 1;

/// F_SETFD, for [fcntl]: sets the descriptor's flags.
const fSetfd = 2;

/// F_GETFL, for [fcntl]: the file status flags.
const fGetfl = 3;

/// F_SETFL, for [fcntl]: sets the file status flags.
const fSetfl = 4;

/// FD_CLOEXEC, a descriptor flag: closed in a program exec'd.
const fdCloexec = 1;

/// EINTR: a call interrupted by a signal.
const eintr = 4;

/// ECHILD: no such child to wait for.
const echild = 10;

/// EAGAIN: a non-blocking call would block.
final eagain = _macos ? 35 : 11;

/// WNOHANG, for [waitpid]: return at once where no child ended.
const wnohang = 1;

/// TCSANOW, for [tcsetattr]: the attributes change at once.
const tcsanow = 0;

/// TCSAFLUSH, for [tcsetattr]: the attributes change once the output
/// written has been sent, and the input not read yet is dropped.
const tcsaflush = 2;

/// TIOCSWINSZ, for [ioctl]: sets a terminal's size (`struct winsize`).
final tiocswinsz = _macos ? 0x80087467 : 0x5414;

/// FIONREAD, for [ioctl]: how many bytes a descriptor holds to be read (an
/// `int`).
final fionread = _macos ? 0x4004667F : 0x541B;

/// IUTF8 in `c_iflag`: the line discipline erases a UTF-8 character whole.
const iutf8 = 0x4000;

/// POSIX_SPAWN_SETSIGDEF: the signals of [spawnattrSetsigdefault] are
/// reset to their default action in the child.
const spawnSetSigDef = 0x04;

/// POSIX_SPAWN_SETSIGMASK: the child's signal mask is that of
/// [spawnattrSetsigmask].
const spawnSetSigMask = 0x08;

/// POSIX_SPAWN_SETSID: glibc 2.26 and later; 0x400 in macOS's spawn.h.
final spawnSetsid = _macos ? 0x400 : 0x80;

/// POSIX_SPAWN_CLOEXEC_DEFAULT (macOS): only what the file actions make
/// is inherited. Linux closes the rest with addclosefrom_np instead.
final spawnCloexecDefault = _macos ? 0x4000 : 0;

final _process = DynamicLibrary.process();

/// calloc(3): [count] zeroed elements of [size] bytes, or `nullptr`.
@Native<Pointer<Void> Function(Size, Size)>(isLeaf: true)
external Pointer<Void> calloc(int count, int size);

/// free(3): frees [p], taken from [calloc].
@Native<Void Function(Pointer<Void>)>(isLeaf: true)
external void free(Pointer<Void> p);

/// strlen(3): the bytes of the C string [s] before its NUL.
@Native<Size Function(Pointer<Char>)>(isLeaf: true)
external int strlen(Pointer<Char> s);

/// strerror(3): what the error number [code] means.
@Native<Pointer<Char> Function(Int)>(isLeaf: true)
external Pointer<Char> strerror(int code);

@Native<Pointer<Int> Function()>(symbol: '__errno_location', isLeaf: true)
external Pointer<Int> _errnoLinux();

@Native<Pointer<Int> Function()>(symbol: '__error', isLeaf: true)
external Pointer<Int> _errnoMacos();

/// errno, read right after the (leaf) call that set it.
int get errno => (_macos ? _errnoMacos() : _errnoLinux()).value;

/// posix_openpt(3): opens a pseudo-terminal's master with [flags];
/// its descriptor, or -1.
@Native<Int Function(Int)>(symbol: 'posix_openpt', isLeaf: true)
external int posixOpenpt(int flags);

/// Not a leaf call: older glibc runs a helper.
@Native<Int Function(Int)>()
external int grantpt(int fd);

/// unlockpt(3): lets the slave of the master [fd] be opened; 0, or -1.
@Native<Int Function(Int)>(isLeaf: true)
external int unlockpt(int fd);

@Native<Int Function(Int, Pointer<Char>, Size)>(
  symbol: 'ptsname_r',
  isLeaf: true,
)
external int _ptsnameR(int fd, Pointer<Char> buf, int size);

@Native<Pointer<Char> Function(Int)>(symbol: 'ptsname', isLeaf: true)
external Pointer<Char> _ptsname(int fd);

/// open(2): opens [path] with [flags] (and [mode] where it creates the
/// file); the descriptor, or -1.
@Native<Int Function(Pointer<Char>, Int, VarArgs<(Int,)>)>(isLeaf: true)
external int open(Pointer<Char> path, int flags, int mode);

/// close(2): closes [fd]; 0, or -1.
@Native<Int Function(Int)>(isLeaf: true)
external int close(int fd);

/// read(2): reads at most [count] bytes of [fd] into [buf]; how many,
/// 0 at the end, or -1.
@Native<Long Function(Int, Pointer<Void>, Size)>(isLeaf: true)
external int read(int fd, Pointer<Void> buf, int count);

/// write(2): writes at most [count] bytes of [buf] to [fd]; how many, or
/// -1.
@Native<Long Function(Int, Pointer<Void>, Size)>(isLeaf: true)
external int write(int fd, Pointer<Void> buf, int count);

/// fcntl(2): the command [cmd] ([fGetfd], [fSetfl], …) on [fd] with
/// [arg]; -1 on an error.
@Native<Int Function(Int, Int, VarArgs<(Int,)>)>(isLeaf: true)
external int fcntl(int fd, int cmd, int arg);

/// ioctl(2): the [request] ([tiocswinsz], …) on [fd] with [arg]; -1 on an
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
/// [when] ([tcsanow], [tcsaflush]) says when; 0, or -1.
///
/// Not a leaf call: with [tcsaflush] it waits for the output to be sent.
@Native<Int Function(Int, Int, Pointer<Void>)>()
external int tcsetattr(int fd, int when, Pointer<Void> termios);

/// cfmakeraw(3): sets [termios] to raw mode: input byte by byte, no
/// signals, no echo, no output processing.
@Native<Void Function(Pointer<Void>)>(isLeaf: true)
external void cfmakeraw(Pointer<Void> termios);

/// pipe(2): a pipe, its read end in `fds[0]`, its write end in `fds[1]`;
/// 0, or -1.
@Native<Int Function(Pointer<Int>)>(isLeaf: true)
external int pipe(Pointer<Int> fds);

/// Blocks: not a leaf call, so the VM goes on while it waits.
@Native<Int Function(Pointer<PollFd>, UnsignedLong, Int)>()
external int poll(Pointer<PollFd> fds, int count, int timeout);

/// waitpid(2): waits for the child [pid], its wait status into [status];
/// with [wnohang] in [options], 0 where it has not ended. The child's id,
/// or -1.
@Native<Int Function(Int, Pointer<Int>, Int)>(isLeaf: true)
external int waitpid(int pid, Pointer<Int> status, int options);

/// sigemptyset(3): empties the signal set [set].
@Native<Int Function(Pointer<Void>)>(isLeaf: true)
external int sigemptyset(Pointer<Void> set);

/// sigfillset(3): fills the signal set [set] with every signal.
@Native<Int Function(Pointer<Void>)>(isLeaf: true)
external int sigfillset(Pointer<Void> set);

typedef _SpawnC = Int Function(
  Pointer<Int>,
  Pointer<Char>,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Pointer<Char>>,
  Pointer<Pointer<Char>>,
);

/// Not a leaf call: the child is made and exec'd before it returns.
@Native<_SpawnC>(symbol: 'posix_spawn')
external int _posixSpawn(
  Pointer<Int> pid,
  Pointer<Char> path,
  Pointer<Void> actions,
  Pointer<Void> attr,
  Pointer<Pointer<Char>> argv,
  Pointer<Pointer<Char>> envp,
);

@Native<_SpawnC>(symbol: 'pidfd_spawn')
external int _pidfdSpawn(
  Pointer<Int> pidfd,
  Pointer<Char> path,
  Pointer<Void> actions,
  Pointer<Void> attr,
  Pointer<Pointer<Char>> argv,
  Pointer<Pointer<Char>> envp,
);

@Native<Int Function(Int)>(symbol: 'pidfd_getpid', isLeaf: true)
external int _pidfdGetpid(int pidfd);

@Native<Int Function(Int, UnsignedInt)>(symbol: 'pidfd_open', isLeaf: true)
external int _pidfdOpen(int pid, int flags);

@Native<Int Function(Int, Int, Pointer<Void>, UnsignedInt)>(
  symbol: 'pidfd_send_signal',
  isLeaf: true,
)
external int _pidfdSendSignal(
  int pidfd,
  int signal,
  Pointer<Void> info,
  int flags,
);

/// Whether [pidfdSendSignal] can be called: glibc 2.36 and later.
final bool pidfdSignals =
    !_macos && _process.providesSymbol('pidfd_send_signal');

/// Sends [signal] to the process [pidfd] refers to, and only to it; 0 when
/// it was sent, -1 when it wasn't (the process ended, or no pidfd).
int pidfdSendSignal(int pidfd, int signal) =>
    _pidfdSendSignal(pidfd, signal, nullptr, 0);

const _enosys = 38;

/// posix_spawn, or pidfd_spawn where there is one (glibc 2.39): [pid] gets
/// the child's id, [pidfd] a pidfd for it (made with the child, so it
/// can't miss its end) or -1 (macOS; pidfd_open after posix_spawn on
/// older Linux). The error number, 0 when the program runs.
///
/// After pidfd_spawn, [pid] is -1 when the child ended and was reaped
/// before its id was read (the VM reaps every child while a Process
/// runs): a pid that is not positive names no child, and kill(2) or
/// waitpid(2) with it reaches every process the user owns or any child.
int spawn(
  Pointer<Int> pid,
  Pointer<Int> pidfd,
  Pointer<Char> path,
  Pointer<Void> actions,
  Pointer<Void> attr,
  Pointer<Pointer<Char>> argv,
  Pointer<Pointer<Char>> envp,
) {
  pidfd.value = -1;
  if (!_macos && _process.providesSymbol('pidfd_spawn')) {
    final rc = _pidfdSpawn(pidfd, path, actions, attr, argv, envp);
    if (rc != _enosys) {
      if (rc == 0) {
        pid.value = _pidfdGetpid(pidfd.value);
      }
      return rc;
    }
  }
  final rc = _posixSpawn(pid, path, actions, attr, argv, envp);
  if (rc == 0 && !_macos && _process.providesSymbol('pidfd_open')) {
    final fd = _pidfdOpen(pid.value, 0);
    pidfd.value = fd < 0 ? -1 : fd;
  }
  return rc;
}

/// PIDFD_GET_INFO: `_IOWR(0xFF, 11, struct pidfd_info)`, its first 64
/// bytes.
const _pidfdGetInfo = 0xC040FF0B;
const _pidfdInfoExit = 0x8;

/// The wait status of the ended process [pidfd] refers to, also once
/// somebody else waited for it (PIDFD_INFO_EXIT, Linux 6.15); null where
/// the kernel doesn't keep it.
int? pidfdExitStatus(int pidfd) {
  final info = calloc(1, 64).cast<Uint64>();
  if (info == nullptr) {
    return null;
  }
  try {
    info.value = _pidfdInfoExit;
    if (ioctl(pidfd, _pidfdGetInfo, info.cast()) != 0 ||
        info.value & _pidfdInfoExit == 0) {
      return null;
    }
    return info.cast<Int32>()[15]; // exit_code, after mask, cgroupid, ids
  } finally {
    free(info.cast());
  }
}

/// kqueue(2) (macOS): a new event queue's descriptor, or -1.
@Native<Int Function()>(isLeaf: true)
external int kqueue();

/// kevent(2) (macOS): applies [changes] ([nchanges] of them) to the queue
/// [kq] and takes up to [nevents] events into [events], waiting [timeout]
/// (a `struct timespec`, null for ever). The number of events, or -1.
@Native<
  Int Function(Int, Pointer<Void>, Int, Pointer<Void>, Int, Pointer<Void>)
>(isLeaf: true)
external int kevent(
  int kq,
  Pointer<Void> changes,
  int nchanges,
  Pointer<Void> events,
  int nevents,
  Pointer<Void> timeout,
);

/// `sizeof(struct kevent)` on macOS, arm64 and x86-64 alike: the 64-bit
/// layout of `<sys/event.h>`, not kevent64's 48 bytes.
const _keventBytes = 32;

// struct kevent, byte offsets (sys/event.h, LP64):
//   0  uintptr_t ident   the pid
//   8  int16_t   filter  EVFILT_PROC
//  10  uint16_t  flags   EV_ADD, ...
//  12  uint32_t  fflags  NOTE_EXIT | NOTE_EXITSTATUS
//  16  intptr_t  data    in an event, the wait status
//  24  void*     udata   unused
const _keventIdent = 0;
const _keventFilter = 8;
const _keventFlags = 10;
const _keventFflags = 12;
const _keventData = 16;

const _evfiltProc = -5; // EVFILT_PROC: events of a process
const _evAdd = 0x1; // EV_ADD: add the event to the queue
const _evOneshot = 0x10; // EV_ONESHOT: report once
const _noteExit = 0x80000000; // NOTE_EXIT: the process ended
// NOTE_EXITSTATUS (with NOTE_EXIT): data is the wait status, also where
// somebody else waited for the process
const _noteExitstatus = 0x04000000;

/// Watches the end of the process [pid] in a new kqueue (macOS), whoever
/// waits for it: the queue's descriptor, or -1 where it could not be made
/// (ESRCH where the process was gone and reaped already).
int watchExit(int pid) {
  final kq = kqueue();
  if (kq < 0) {
    return -1;
  }
  final change = calloc(1, _keventBytes);
  if (change == nullptr) {
    close(kq);
    return -1;
  }
  try {
    final bytes = change.cast<Uint8>().asTypedList(_keventBytes);
    ByteData.view(bytes.buffer, bytes.offsetInBytes, _keventBytes)
      ..setUint64(_keventIdent, pid, Endian.host)
      ..setInt16(_keventFilter, _evfiltProc, Endian.host)
      ..setUint16(_keventFlags, _evAdd | _evOneshot, Endian.host)
      ..setUint32(_keventFflags, _noteExit | _noteExitstatus, Endian.host);
    // no event list: a change that fails makes the call return -1
    if (kevent(kq, change.cast(), 1, nullptr, 0, nullptr) < 0) {
      close(kq);
      return -1;
    }
    return kq;
  } finally {
    free(change);
  }
}

/// The wait status of the process the queue [kq] of [watchExit] watches,
/// null while it runs. Does not wait.
int? exitStatusFrom(int kq) {
  final event = calloc(1, _keventBytes + 16); // the event, a zero timespec
  if (event == nullptr) {
    return null;
  }
  try {
    final timeout = (event.cast<Uint8>() + _keventBytes).cast<Void>();
    if (kevent(kq, nullptr, 0, event.cast(), 1, timeout) != 1) {
      return null;
    }
    final bytes = event.cast<Uint8>().asTypedList(_keventBytes);
    final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, _keventBytes);
    if (view.getInt16(_keventFilter, Endian.host) != _evfiltProc ||
        view.getUint32(_keventFflags, Endian.host) & _noteExit == 0) {
      return null;
    }
    return view.getInt64(_keventData, Endian.host);
  } finally {
    free(event.cast());
  }
}

/// posix_spawnattr_init(3): initializes the spawn attributes [attr].
@Native<Int Function(Pointer<Void>)>(
  symbol: 'posix_spawnattr_init',
  isLeaf: true,
)
external int spawnattrInit(Pointer<Void> attr);

/// posix_spawnattr_destroy(3): frees what [attr] holds.
@Native<Int Function(Pointer<Void>)>(
  symbol: 'posix_spawnattr_destroy',
  isLeaf: true,
)
external int spawnattrDestroy(Pointer<Void> attr);

/// posix_spawnattr_setflags(3): sets the flags of [attr]
/// ([spawnSetsid], [spawnSetSigMask], …).
@Native<Int Function(Pointer<Void>, Short)>(
  symbol: 'posix_spawnattr_setflags',
  isLeaf: true,
)
external int spawnattrSetflags(Pointer<Void> attr, int flags);

/// posix_spawnattr_setsigmask(3): the child's signal mask, with
/// [spawnSetSigMask].
@Native<Int Function(Pointer<Void>, Pointer<Void>)>(
  symbol: 'posix_spawnattr_setsigmask',
  isLeaf: true,
)
external int spawnattrSetsigmask(Pointer<Void> attr, Pointer<Void> set);

/// posix_spawnattr_setsigdefault(3): the signals reset to their
/// default action in the child, with [spawnSetSigDef].
@Native<Int Function(Pointer<Void>, Pointer<Void>)>(
  symbol: 'posix_spawnattr_setsigdefault',
  isLeaf: true,
)
external int spawnattrSetsigdefault(Pointer<Void> attr, Pointer<Void> set);

/// posix_spawn_file_actions_init(3): initializes the file actions
/// [actions].
@Native<Int Function(Pointer<Void>)>(
  symbol: 'posix_spawn_file_actions_init',
  isLeaf: true,
)
external int actionsInit(Pointer<Void> actions);

/// posix_spawn_file_actions_destroy(3): frees what [actions] holds.
@Native<Int Function(Pointer<Void>)>(
  symbol: 'posix_spawn_file_actions_destroy',
  isLeaf: true,
)
external int actionsDestroy(Pointer<Void> actions);

/// posix_spawn_file_actions_addopen(3): the child opens [path] with
/// [flags] and [mode] as its descriptor [fd].
@Native<Int Function(Pointer<Void>, Int, Pointer<Char>, Int, UnsignedInt)>(
  symbol: 'posix_spawn_file_actions_addopen',
  isLeaf: true,
)
external int actionsAddopen(
  Pointer<Void> actions,
  int fd,
  Pointer<Char> path,
  int flags,
  int mode,
);

/// posix_spawn_file_actions_adddup2(3): the child's descriptor [to] is
/// a copy of its [fd].
@Native<Int Function(Pointer<Void>, Int, Int)>(
  symbol: 'posix_spawn_file_actions_adddup2',
  isLeaf: true,
)
external int actionsAdddup2(Pointer<Void> actions, int fd, int to);

@Native<Int Function(Pointer<Void>, Pointer<Char>)>(
  symbol: 'posix_spawn_file_actions_addchdir_np',
  isLeaf: true,
)
external int _actionsAddchdir(Pointer<Void> actions, Pointer<Char> path);

/// posix_spawn_file_actions_addchdir_np (glibc 2.29, macOS 10.15); null
/// where it is missing.
int Function(Pointer<Void>, Pointer<Char>)? get actionsAddchdir =>
    _process.providesSymbol('posix_spawn_file_actions_addchdir_np')
    ? _actionsAddchdir
    : null;

@Native<Int Function(Pointer<Void>, Int)>(
  symbol: 'posix_spawn_file_actions_addclosefrom_np',
  isLeaf: true,
)
external int _actionsAddclosefrom(Pointer<Void> actions, int from);

/// posix_spawn_file_actions_addclosefrom_np (glibc 2.34); null where it is
/// missing or not needed (macOS has [spawnCloexecDefault]).
int Function(Pointer<Void>, int)? get actionsAddclosefrom =>
    !_macos &&
        _process.providesSymbol('posix_spawn_file_actions_addclosefrom_np')
    ? _actionsAddclosefrom
    : null;

/// The slave's path of the pseudo-terminal whose master is [fd].
String ptsName(int fd, NativeScope scope) {
  if (_process.providesSymbol('ptsname_r')) {
    final buf = scope.alloc<Char>(256);
    final rc = _ptsnameR(fd, buf, 256);
    return rc == 0 ? string(buf) : throw OSError('ptsname_r', rc);
  }
  final name = _ptsname(fd);
  return name == nullptr ? throw OSError('ptsname', errno) : string(name);
}

/// The C string at [p], as UTF-8.
String string(Pointer<Char> p) =>
    utf8.decode(p.cast<Uint8>().asTypedList(strlen(p)), allowMalformed: true);

/// What [call] failing with [code] says.
String describe(String call, int code) =>
    '$call: ${string(strerror(code))} (errno $code)';

/// Sets FD_CLOEXEC on [fd].
void setCloexec(int fd) => fcntl(fd, fSetfd, fcntl(fd, fGetfd, 0) | fdCloexec);

/// Sets O_NONBLOCK on [fd].
void setNonblocking(int fd) =>
    fcntl(fd, fSetfl, fcntl(fd, fGetfl, 0) | oNonblock);

/// Native memory taken from calloc and freed together.
final class NativeScope {
  final _taken = <Pointer<Void>>[];

  /// [bytes] zeroed bytes.
  Pointer<T> alloc<T extends NativeType>(int bytes) {
    final p = calloc(1, bytes);
    if (p == nullptr) {
      throw const OutOfMemoryError();
    }
    _taken.add(p);
    return p.cast();
  }

  /// [s] as a NUL-terminated UTF-8 string.
  Pointer<Char> string(String s) {
    final bytes = utf8.encode(s);
    if (bytes.contains(0)) {
      throw ArgumentError.value(s, 'string', 'contains NUL');
    }
    final p = alloc<Uint8>(bytes.length + 1);
    p.asTypedList(bytes.length).setAll(0, bytes);
    return p.cast();
  }

  /// [list] as a NULL-terminated array of strings (argv, envp).
  Pointer<Pointer<Char>> strings(List<String> list) {
    final p = alloc<Pointer<Char>>((list.length + 1) * sizeOf<Pointer<Char>>());
    for (var i = 0; i < list.length; i++) {
      p[i] = string(list[i]);
    }
    return p;
  }

  /// Frees all of it.
  void release() {
    for (final p in _taken) {
      free(p);
    }
    _taken.clear();
  }
}
