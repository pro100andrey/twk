part of 'terminal_view.dart';

// Examples can assume:
// import 'dart:io';

/// A program and the emulator of its terminal: what the program writes is
/// fed to [emulator], and what the emulator sends — its answers, the keys,
/// mouse reports and pastes a [TerminalView] gives it — goes to the
/// program. The listeners are told after each piece of output is fed and
/// once the output [ended].
///
/// [dispose] hangs a [Pty] up (SIGHUP for the program) and stops reading
/// the output; a program that ignores SIGHUP is the app's to [Pty.kill].
///
/// A shell for a [TerminalView], started at the view's size, and told
/// when the shell ends:
///
/// ```dart
/// final session = TerminalSession.start('bash', const []);
/// session.exitCode.then((code) => print('bash ended: $code')).ignore();
/// // shown by TerminalView(session: session) until the app disposes it
/// ```
final class TerminalSession with ChangeNotifier {
  /// A program at the other end of any byte link: [output] is what it
  /// writes, [input] takes what is sent to it, [onResize] is told each new
  /// size of its terminal. [exitCode] completes with null when [output]
  /// ends.
  ///
  /// A program started by `dart:io`, without a terminal of its own:
  ///
  /// ```dart
  /// final process = await Process.start('cat', const []);
  /// final session = TerminalSession(
  ///   output: process.stdout,
  ///   input: process.stdin.add,
  /// );
  /// ```
  factory TerminalSession({
    required Stream<List<int>> output,
    required void Function(Uint8List bytes) input,
    void Function(int width, int height)? onResize,
    int width = 80,
    int height = 24,
    int scrollbackLimit = 1000,
    TextMode textMode = TextMode.legacy,
  }) => TerminalSession._(
    width,
    height,
    scrollbackLimit,
    textMode,
    null,
  ).._connect(output, input, onResize);

  /// Runs [executable] with [arguments] in a new pseudo-terminal
  /// ([Pty.start], which says what the program gets and what it throws
  /// when it can't start it), with an emulator keeping [scrollbackLimit]
  /// lines and splitting text into cells as [textMode] says.
  ///
  /// Given a [width] and a [height], the program starts at once, in a
  /// terminal of that size. Without them, it starts at the first [resize],
  /// at that size: a [TerminalView] showing the session resizes it at its
  /// first layout, so the program never sees another size. What it threw
  /// then is [error], logged, and the session has [ended].
  factory TerminalSession.start(
    String executable,
    List<String> arguments, {
    int? width,
    int? height,
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    int scrollbackLimit = 1000,
    TextMode textMode = TextMode.legacy,
  }) {
    Pty start(int width, int height) => Pty.start(
      executable,
      arguments,
      width: width,
      height: height,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
    );
    if (width == null || height == null) {
      return TerminalSession._(80, 24, scrollbackLimit, textMode, start);
    }
    return TerminalSession._(
      width,
      height,
      scrollbackLimit,
      textMode,
      null,
    ).._run(start(width, height));
  }

  TerminalSession._(
    int width,
    int height,
    int scrollbackLimit,
    TextMode textMode,
    this._start,
  ) : emulator = TerminalEmulator(
        width: width,
        height: height,
        scrollbackLimit: scrollbackLimit,
        textMode: textMode,
      ) {
    emulator
      ..onEvent = _event
      ..onScrolled = _scrolled;
  }

  /// The program's terminal.
  final TerminalEmulator emulator;

  /// The pseudo-terminal the program runs in; null for a session over
  /// another link, and until a program started late has started.
  Pty? get pty => _pty;
  Pty? _pty;

  /// What starting a program late threw.
  Object? get error => _error;
  Object? _error;

  // starts the program, until the first resize does
  Pty Function(int width, int height)? _start;

  void Function(int width, int height)? _onResize;
  StreamSubscription<List<int>>? _output;
  final _events = StreamController<TerminalEvent>.broadcast();
  final _exit = Completer<int?>();
  final _views = <_RenderTerminal>{};
  var _ended = false;
  var _disposed = false;

  /// What the program asks of its terminal ([TerminalEmulator.onEvent]),
  /// told after the piece of output that asked for it was fed.
  Stream<TerminalEvent> get events => _events.stream;

  /// Whether the output ended: the terminal hung up (the program and what
  /// it left running closed it), the link ended, or the program could not
  /// start.
  bool get ended => _ended;

  /// The program's exit code ([Pty.exitCode]); null over another link and
  /// for a program that could not start.
  Future<int?> get exitCode => _exit.future;

  /// The program's title (OSC 0, 2).
  String get title => emulator.title;

  void _connect(
    Stream<List<int>> output,
    void Function(Uint8List bytes) input,
    void Function(int width, int height)? onResize,
  ) {
    emulator.onOutput = input;
    _onResize = onResize;
    _output = output.listen(_fed, onDone: _done, onError: _failed);
  }

  void _run(Pty pty) {
    _pty = pty;
    _connect(pty.output, pty.write, pty.resize);
    unawaited(pty.exitCode.then(_exit.complete));
  }

  /// Resizes the terminal ([TerminalEmulator.resize]) and tells the
  /// program ([Pty.resize]), or starts a program started late; a
  /// [TerminalView] does at each layout.
  void resize(int width, int height) {
    final start = _start;
    if (start != null && !_disposed) {
      _start = null;
      emulator.resize(width, height);
      try {
        _run(start(width, height));
      } on Object catch (error, stack) {
        _error = error;
        log(
          'the terminal could not start its program',
          level: LogLevel.error,
          error: error,
          stack: stack,
        );
        // told after the layout that resized it
        scheduleMicrotask(_done);
      }
      return;
    }
    if (width == emulator.width && height == emulator.height) {
      return;
    }
    emulator.resize(width, height);
    _onResize?.call(width, height);
  }

  void _fed(List<int> bytes) {
    emulator.feed(bytes);
    for (final view in _views) {
      view._fed();
    }
    notifyListeners();
  }

  void _done() {
    _ended = true;
    if (!_exit.isCompleted && _pty == null) {
      _exit.complete(null);
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _failed(Object error, StackTrace stack) {
    log(
      "the terminal's output failed",
      level: LogLevel.error,
      error: error,
      stack: stack,
    );
    _done();
  }

  void _event(TerminalEvent event) {
    for (final view in _views) {
      view._event(event);
    }
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  void _scrolled(int top, int bottom, int n) {
    for (final view in _views) {
      view._scrolled(top, bottom, n);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _start = null;
    _pty?.close();
    unawaited(_output?.cancel());
    unawaited(_events.close());
    super.dispose();
  }
}
