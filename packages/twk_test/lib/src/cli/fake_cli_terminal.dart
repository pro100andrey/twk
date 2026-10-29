/// A [CliTerminal] in memory for tests: [FakeCliTerminal].
library;

import 'dart:convert';

import 'package:twk/cli.dart'
    show CliCapabilities, CliClock, CliMode, CliTerminal;
import 'package:twk/twk.dart'
    show
        ColorMode,
        HeadlessTerminal,
        TerminalBackend,
        TerminalCaps,
        TerminalOptions;

import '../../vt.dart';
import '../fake_clock.dart';

// Examples can assume:
// import 'package:test/test.dart';
// import 'package:twk/cli.dart';

/// A [CliTerminal] that captures what is written and replays what is
/// typed, in one of the three modes or with every capability given.
///
/// * `FakeCliTerminal()` is [CliMode.nonInteractive]: a pipe, nobody to
///   answer.
/// * [FakeCliTerminal.plain] is [CliMode.plain]: a terminal without ANSI,
///   whose [readLine] answers its `lines` in turn.
/// * [FakeCliTerminal.interactive] is [CliMode.interactive]: a terminal
///   [width] × [height] cells, whose inline session runs on a terminal in
///   memory ([backend]) that gets its `input`, keys as a terminal sends
///   them (`'\x1B[B'` the down arrow, `'\r'` Enter, `'\x03'` Ctrl+C), and
///   whose [screen] is an emulator fed everything written to it, the
///   session's frames and the lines written around it.
///
/// [out] and [err] keep what was written as lines, outside a session;
/// [interrupts] counts the Ctrl+C the console passed on. [clock] is where
/// the session's time comes from: a [FakeClock] given here moves only as
/// the test moves it, the wall clock without one.
///
/// ```dart
/// test('writes the result to the output', () {
///   final terminal = FakeCliTerminal();
///   Cli(terminal: terminal).info('done');
///   expect(terminal.out.toString(), 'done\n');
/// });
/// ```
final class FakeCliTerminal extends CliTerminal {
  /// A terminal of the capabilities given, all off by default: nobody
  /// answers, the output is a pipe. [lines] answer [readLine], [input] is
  /// typed into the inline session, [columns] is its width (null for
  /// none where output is no terminal), [width] × [height] the screen's
  /// size where it is one; [fakeClock] times the session.
  /// [progressReports] says the terminal shows a program's progress in
  /// its tab (OSC 9;4), which the inline session then writes;
  /// [styledUnderlines] false that it shows no underline styles, as
  /// Terminal.app, and [probedStyledUnderlines] what the inline session's
  /// probe finds of them, [styledUnderlines] by default: false beside a
  /// true one is Terminal.app over ssh, which its environment doesn't
  /// tell.
  FakeCliTerminal({
    bool ansi = false,
    bool interactiveInput = false,
    bool outputIsTerminal = false,
    bool? errorIsTerminal,
    bool? hyperlinks,
    this.colorMode = ColorMode.trueColor,
    bool styledUnderlines = true,
    bool? probedStyledUnderlines,
    int? columns,
    this.width = 80,
    this.height = 24,
    List<String> lines = const [],
    List<String> input = const [],
    FakeClock? fakeClock,
    this.progressReports = false,
  }) : capabilities = CliCapabilities(
         ansi: ansi,
         interactiveInput: interactiveInput,
         outputIsTerminal: outputIsTerminal,
         errorIsTerminal: errorIsTerminal,
         hyperlinks: hyperlinks,
         colorMode: colorMode,
         styledUnderlines: styledUnderlines,
       ),
       _probedUnderlines = probedStyledUnderlines ?? styledUnderlines,
       _columns = columns ?? (outputIsTerminal ? width : null),
       _lines = [...lines],
       _input = [...input],
       clock = fakeClock == null
           ? const CliClock.system()
           : _FakeCliClock(fakeClock),
       screen = Vt(
         width,
         height,
         scrollback: true,
         allowLineFeed: true,
         strict: false,
       );

  /// Somebody answers at a terminal that takes no ANSI (`NO_COLOR`, a
  /// dumb terminal): [readLine] answers [lines] in turn, then null.
  /// [fakeClock] is where the time of a progress comes from.
  FakeCliTerminal.plain({
    List<String> lines = const [],
    int width = 80,
    int height = 24,
    FakeClock? fakeClock,
  }) : this(
         interactiveInput: true,
         outputIsTerminal: true,
         lines: lines,
         width: width,
         height: height,
         fakeClock: fakeClock,
       );

  /// Somebody answers at a terminal that redraws, [width] × [height]
  /// cells: the inline session gets [input] as typed. [fakeClock] times
  /// it, the wall clock without one; [progressReports] as above.
  FakeCliTerminal.interactive({
    List<String> input = const [],
    int width = 80,
    int height = 24,
    FakeClock? fakeClock,
    bool progressReports = false,
  }) : this(
         ansi: true,
         interactiveInput: true,
         outputIsTerminal: true,
         input: input,
         width: width,
         height: height,
         fakeClock: fakeClock,
         progressReports: progressReports,
       );

  @override
  final CliCapabilities capabilities;

  final bool _probedUnderlines;

  /// The colors styled output is written in.
  final ColorMode colorMode;

  /// The screen's width in cells.
  final int width;

  /// The screen's height in cells.
  final int height;

  /// Whether the terminal shows a program's progress in its tab or
  /// taskbar (OSC 9;4): the inline session's `TerminalProgress` writes it
  /// to [backend]'s frames only then.
  final bool progressReports;

  final int? _columns;
  final List<String> _lines;
  final List<String> _input;

  @override
  final CliClock clock;

  /// The output: its `toString` is everything written to it, outside an
  /// inline session.
  @override
  late final StringSink out = _Sink(_feed);

  /// The error output: its `toString` is everything written to it,
  /// outside an inline session.
  @override
  late final StringSink err = _Sink((text) {
    if (capabilities.errorIsTerminal) {
      _feed(text);
    }
  });

  /// The screen, an emulator fed what reaches the terminal: the lines
  /// written to [out] (and to [err] where it is the terminal) and the
  /// frames of the inline session, in the order they came. Read
  /// [screenLines], which is up to date, rather than this directly.
  final Vt screen;

  /// The terminal in memory the inline session runs on, once it is
  /// opened.
  HeadlessTerminal? get backend => _backend;
  HeadlessTerminal? _backend;

  /// How many times the console passed a Ctrl+C on ([interrupt]).
  int get interrupts => _interrupts;
  var _interrupts = 0;

  /// How many times [readLine] was called: a line read, or the end of
  /// input.
  int get reads => _reads;
  var _reads = 0;

  /// How many times the inline terminal was opened: once at most.
  int get opened => _opened;
  var _opened = 0;

  var _frames = 0;

  /// The lines of the screen, the scrollback first, without the blanks
  /// that end them, the blank lines at the bottom left out.
  List<String> get screenLines {
    _feedFrames();
    final lines = [...screen.lines];
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines;
  }

  @override
  int? get columns => _columns;

  /// Types [keys] into the inline session, as a terminal sends them; kept
  /// for it until it opens.
  void type(String keys) {
    final backend = _backend;
    if (backend == null || backend.closed) {
      _input.add(keys);
    } else {
      backend.type(keys);
    }
  }

  @override
  Future<String?> readLine({bool hidden = false}) async {
    _reads++;
    if (_lines.isEmpty || _closed) {
      return null;
    }
    final line = _lines.removeAt(0);
    if (capabilities.outputIsTerminal && !hidden) {
      // the terminal echoes what is typed
      _feed('$line\n');
    } else if (capabilities.outputIsTerminal) {
      _feed('\n');
    }
    return line;
  }

  @override
  Future<TerminalBackend> openInline() async {
    if (_opened++ > 0) {
      throw StateError(
        'the inline terminal was opened before: stdin is closed',
      );
    }
    _feedFrames();
    screen.guardRows(screen.cy);
    final backend = _backend = HeadlessTerminal(
      width: width,
      height: height,
      caps: TerminalCaps(styledUnderlines: _probedUnderlines),
      options: const TerminalOptions(alternateScreen: false),
      cursorColumn: screen.cx,
      progressReports: progressReports,
    );
    for (final keys in _input) {
      backend.type(keys);
    }
    _input.clear();
    return backend;
  }

  @override
  void interrupt() => _interrupts++;

  @override
  Future<void> flush() async {}

  /// Whether it was closed ([close]); [readLine] answers null since.
  bool get closed => _closed;
  var _closed = false;

  @override
  Future<void> close() async => _closed = true;

  void _feed(String text) {
    _feedFrames();
    screen.feed(utf8.encode(text.replaceAll('\n', '\r\n')));
  }

  void _feedFrames() {
    final frames = _backend?.frames;
    if (frames == null) {
      return;
    }
    for (; _frames < frames.length; _frames++) {
      screen.feed(frames[_frames]);
    }
  }
}

/// A sink that keeps what is written, its `toString`, and passes it to
/// [feed].
final class _Sink implements StringSink {
  _Sink(this.feed);

  final buffer = StringBuffer();
  final void Function(String text) feed;

  @override
  String toString() => buffer.toString();

  @override
  void write(Object? object) {
    final text = '$object';
    buffer.write(text);
    feed(text);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');
}

final class _FakeCliClock implements CliClock {
  _FakeCliClock(this.clock);

  final FakeClock clock;

  @override
  Stopwatch stopwatch() => _ClockStopwatch(clock);

  @override
  R run<R>(R Function() body) => clock.run(body);
}

/// A stopwatch that reads [clock], started when made.
final class _ClockStopwatch implements Stopwatch {
  _ClockStopwatch(this.clock) : _start = clock.elapsed;

  final FakeClock clock;
  Duration _start;
  Duration? _stoppedAt;

  @override
  Duration get elapsed => (_stoppedAt ?? clock.elapsed) - _start;

  @override
  int get elapsedMicroseconds => elapsed.inMicroseconds;

  @override
  int get elapsedMilliseconds => elapsed.inMilliseconds;

  @override
  int get elapsedTicks => elapsedMicroseconds;

  @override
  int get frequency => 1000000;

  @override
  bool get isRunning => _stoppedAt == null;

  @override
  void reset() => _start = _stoppedAt ?? clock.elapsed;

  @override
  void start() {
    final stopped = _stoppedAt;
    if (stopped != null) {
      _start += clock.elapsed - stopped;
      _stoppedAt = null;
    }
  }

  @override
  void stop() => _stoppedAt ??= clock.elapsed;
}
