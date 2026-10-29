// The user's terminal for `twk record` and `twk play`: a pseudo-terminal
// (twk_term's Pty) the command runs in, shown by twk_term's emulator,
// which answers the queries of the app inside as a terminal does, and the
// modes of its tty, read and set as a shell does.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_term/twk_term.dart';
import 'package:twk_test/twk_test.dart' show waitUntil;

import 'twk.dart';

/// How long a test waits for what it waits for: on a machine running the
/// other suites at once (`handover -j`), a program can take tens of
/// seconds to start.
const wait = Duration(seconds: 90);

@Native<Pointer<Void> Function(Size, Size)>(isLeaf: true, symbol: 'calloc')
external Pointer<Void> _calloc(int count, int size);

@Native<Void Function(Pointer<Void>)>(isLeaf: true, symbol: 'free')
external void _free(Pointer<Void> p);

@Native<Int Function(Pointer<Char>, Int)>(symbol: 'open')
external int _open(Pointer<Char> path, int flags);

@Native<Int Function(Int)>(isLeaf: true, symbol: 'close')
external int _close(int fd);

@Native<Int Function(Int, Pointer<Void>)>(isLeaf: true, symbol: 'tcgetattr')
external int _tcgetattr(int fd, Pointer<Void> termios);

@Native<Int Function(Int, Int, Pointer<Void>)>(symbol: 'tcsetattr')
external int _tcsetattr(int fd, int when, Pointer<Void> termios);

final bool _macos = Platform.isMacOS;

/// ICANON, ECHO, ISIG in c_lflag; OPOST in c_oflag.
final icanon = _macos ? 0x100 : 0x2;
const echo = 0x8;
final isig = _macos ? 0x80 : 0x1;
const opost = 0x1;

/// The flags of a tty: c_iflag, c_oflag, c_cflag, c_lflag, and the whole
/// `struct termios` they start.
final class Modes {
  Modes._(this.bytes);

  final Uint8List bytes;

  int _flag(int i) => _macos
      ? ByteData.sublistView(bytes).getUint64(i * 8, Endian.host)
      : ByteData.sublistView(bytes).getUint32(i * 4, Endian.host);

  int get iflag => _flag(0);
  int get oflag => _flag(1);
  int get lflag => _flag(3);

  /// Line editing, echo and the keys' signals off, output unprocessed.
  bool get raw => lflag & (icanon | echo | isig) == 0 && oflag & opost == 0;

  /// The four flag fields are the same.
  bool same(Modes other) => [
    for (var i = 0; i < 4; i++) _flag(i) == other._flag(i),
  ].every((s) => s);

  @override
  String toString() =>
      'iflag 0x${iflag.toRadixString(16)} oflag 0x${oflag.toRadixString(16)} '
      'lflag 0x${lflag.toRadixString(16)}';
}

/// A terminal of a program run in it, killed in the tear-down.
final class Terminal {
  Terminal._(this.pty, this.screen) : _fd = _openTty(pty.ttyName) {
    _output = pty.output.listen((bytes) {
      output.addAll(bytes);
      screen.feed(bytes);
    }, onDone: () => outputDone = true);
    unawaited(pty.exitCode.then((_) => exited = true));
    addTearDown(() async {
      _closeTty();
      pty
        ..kill(ProcessSignal.sigkill)
        ..close();
      await pty.exitCode.timeout(wait, onTimeout: () => null);
      await _output.cancel();
    });
  }

  /// A terminal running `twk` with [arguments]: its kernel, which the
  /// suite compiles in `setUpAll` ([compileTwk]).
  static Future<Terminal> twk(
    List<String> arguments, {
    int width = 60,
    int height = 14,
  }) => start(
    Platform.resolvedExecutable,
    [twkProgram, ...arguments],
    width: width,
    height: height,
  );

  /// A terminal running [executable] with [arguments] in this package's
  /// directory.
  static Future<Terminal> start(
    String executable,
    List<String> arguments, {
    int width = 60,
    int height = 14,
  }) async {
    final screen = TerminalEmulator(width: width, height: height);
    final pty = Pty.start(
      executable,
      arguments,
      width: width,
      height: height,
      workingDirectory: await packageDirectory(),
    );
    screen.onOutput = pty.write;
    return Terminal._(pty, screen);
  }

  final Pty pty;

  /// What the terminal shows.
  final TerminalEmulator screen;

  /// Everything written to the terminal.
  final output = <int>[];

  late final StreamSubscription<Uint8List> _output;
  var outputDone = false;
  var exited = false;

  String get text => utf8.decode(output, allowMalformed: true);

  /// The rows the terminal shows, the blanks that end them left out.
  List<String> get lines => [
    for (var y = 0; y < screen.height; y++) screen.lineText(y).trimRight(),
  ];

  /// Types [text].
  void type(String text) => pty.write(utf8.encode(text));

  /// Resizes the terminal; the program in it gets SIGWINCH.
  void resize(int width, int height) {
    screen.resize(width, height);
    pty.resize(width, height);
  }

  /// The modes of the terminal's tty now, or once the program ended as
  /// [ended] found them.
  Modes get modes {
    if (_fd < 0) {
      return _endModes;
    }
    final termios = _calloc(1, 256);
    try {
      expect(_tcgetattr(_fd, termios), 0, reason: 'tcgetattr');
      return Modes._(
        Uint8List.fromList(termios.cast<Uint8>().asTypedList(256)),
      );
    } finally {
      _free(termios);
    }
  }

  /// Sets the modes of the terminal's tty to [modes], as a shell taking
  /// the terminal back does.
  set modes(Modes modes) {
    final termios = _calloc(1, 256);
    try {
      termios.cast<Uint8>().asTypedList(256).setAll(0, modes.bytes);
      expect(_tcsetattr(_fd, 0, termios), 0, reason: 'tcsetattr');
    } finally {
      _free(termios);
    }
  }

  // the tty, held open so that it outlives the program, whose modes can
  // then still be read
  int _fd;
  late final Modes _endModes;

  static int _openTty(String name) {
    final path = utf8.encode(name);
    final memory = _calloc(1, path.length + 1);
    memory.cast<Uint8>().asTypedList(path.length).setAll(0, path);
    // O_RDWR | O_NOCTTY
    final fd = _open(memory.cast(), 2 | (_macos ? 0x20000 : 0x100));
    _free(memory);
    expect(fd, greaterThanOrEqualTo(0), reason: 'open $name');
    return fd;
  }

  void _closeTty() {
    if (_fd >= 0) {
      _close(_fd);
      _fd = -1;
    }
  }

  /// Waits until [done], failing with [what] and the screen after [wait].
  Future<void> until(bool Function() done, String what) async {
    try {
      await waitUntil(done, what, timeout: wait);
    } on TestFailure catch (e) {
      fail(
        '${e.message}; screen:\n${lines.join('\n')}\n'
        'output: ${jsonEncode(text)}',
      );
    }
  }

  /// Whether the program is stopped (by SIGSTOP): its state `T`, read
  /// from /proc on Linux, as running ps there would have the VM wait for
  /// any child.
  bool get stopped {
    final pid = pty.pid;
    if (!Platform.isLinux) {
      final ps = Process.runSync('ps', ['-o', 'stat=', '-p', '$pid']);
      return (ps.stdout as String).trim().startsWith('T');
    }
    try {
      final stat = File('/proc/$pid/stat').readAsStringSync();
      return stat.substring(stat.lastIndexOf(')') + 2).startsWith('T');
    } on FileSystemException {
      return false;
    }
  }

  /// Waits until the screen shows [line].
  Future<void> shows(String line) =>
      until(() => lines.contains(line), 'a row "$line"');

  /// The exit code once the program ended and the output did.
  Future<int?> ended() async {
    final code = await pty.exitCode.timeout(wait);
    // as the pty read them at the end: macOS revokes the terminal of a
    // session whose leader ended, which the tty held here reads no more
    final end = pty.modesAtEnd;
    _endModes = end != null ? Modes._(end) : modes;
    _closeTty();
    await until(() => outputDone, 'the output to end');
    return code;
  }
}

/// Linux 6.15 and later tell how a program ended also when the VM waited
/// for it first, which it does for any child while a `Process` runs (the
/// test runner's compiler does throughout).
final bool _endsKnown = () {
  final version = RegExp(
    r'(\d+)\.(\d+)',
  ).firstMatch(Platform.operatingSystemVersion);
  if (!Platform.isLinux || version == null) {
    return false;
  }
  final [major, minor] = [
    for (final i in [1, 2]) int.parse(version[i]!),
  ];
  return major > 6 || major == 6 && minor >= 15;
}();

/// The exit code [code], or null where the VM may have taken it.
Matcher exits(int code) => _endsKnown ? equals(code) : anyOf(code, isNull);
