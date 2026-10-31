/// Widget tests: [testTwk] and the [TwkTester] it hands the test.
///
/// @docImport 'finders.dart';
/// @docImport 'matchers.dart';
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';

import '../vt.dart';
import 'fake_clock.dart';
import 'fake_stderr.dart';
import 'keys.dart';
import 'recording.dart';
import 'screen_text.dart';

// Examples can assume:
// import 'package:test/test.dart';
// import 'package:twk/twk.dart';
// late TwkTester t;

/// Runs [body] as a test of package:test named [description], with a
/// [TwkTester] for an app it starts with [TwkTester.pumpWidget].
///
/// A field that takes what is typed and gives it up on Enter:
///
/// ```dart
/// testTwk('Enter submits what was typed', (t) async {
///   String? sent;
///   await t.pumpWidget(
///     TextField(autofocus: true, onSubmitted: (text) => sent = text),
///   );
///   await t.type('hello');
///   await t.press('enter');
///   await t.pump();
///   expect(sent, 'hello');
///   expect(t, containsLine('hello'));
/// });
/// ```
///
/// When [body] returns, an app still running is quit, and what it wrote is
/// fed to the emulator: an error the app ended with that no call of the
/// tester has thrown fails the test, as do bytes the emulator does not
/// take (see [Vt]). A test that fails prints the last [framesOnFailure]
/// frames of the app that changed the screen ([TwkTester.frames]), as
/// text, and then the app's log ([TwkTester.logs]), its last 20 records:
/// what it printed, its warnings (a layout that overflowed) and its
/// errors (a build that threw), which its screen shows none of.
@isTest
void testTwk(
  String description,
  FutureOr<void> Function(TwkTester t) body, {
  int framesOnFailure = 3,
  Timeout? timeout,
  Object? skip,
  Object? tags,
}) => test(
  description,
  () async {
    final t = TwkTester._();
    try {
      await runZoned(() => body(t), zoneValues: {_testerKey: t});
    } on Object {
      t._printOnFailure(framesOnFailure);
      try {
        await t._end();
      } on Object {
        // the test failed already: its own error is the one to report
      }
      rethrow;
    }
    try {
      await t._end();
    } on Object {
      t._printOnFailure(framesOnFailure);
      rethrow;
    }
  },
  timeout: timeout,
  skip: skip,
  tags: tags,
);

final _testerKey = Object();

/// The tester of the test running ([testTwk]); null outside one.
@internal
TwkTester? get runningTester => Zone.current[_testerKey] as TwkTester?;

/// Runs an app under test: the real binding on a terminal in memory
/// ([terminal]), the real parser decoding the bytes of the input, the
/// emulator reconstructing the screen from the bytes of the frames.
///
/// Time is a [FakeClock]'s: the app's timers, the frames and the pause
/// after a lone ESC wait until [pump] moves the clock on. Each call of the
/// tester runs the app's microtasks before it returns; an error the app
/// ends with is thrown by the call during which it ended, or by the next
/// one.
///
/// A frame waits for the clock: what a key changes shows once [pump] has
/// moved it on by a frame's gap.
///
/// ```dart
/// testTwk('the screen shows a frame once the clock moves on', (t) async {
///   await t.pumpWidget(const Text('Ready'), size: (20, 2));
///   expect(t.lines.first, 'Ready');
///   expect(t, matchesScreen('Ready'));
///   await t.pump(const Duration(seconds: 1));
///   expect(t.clock.elapsed, greaterThan(const Duration(seconds: 1)));
/// });
/// ```
///
/// See also:
///
///  * [FinderTester], what it reads of the widgets a [Finder] finds.
///  * [containsLine], [matchesScreen] and the other matchers of its
///    screen.
final class TwkTester {
  TwkTester._() {
    clock = IOOverrides.runZoned(FakeClock.new, stderr: () => _stderr)
      ..beforeMove = _stamp;
  }

  /// The time of the app.
  late final FakeClock clock;

  /// The app's log: `print`, `log()` and the errors it reports.
  final logs = LogSink();

  /// What the app wrote to stderr, line by line: the warnings and errors
  /// of its log, once it ended.
  List<String> get stderrLines => _stderr.lines;

  // ignore: close_sinks, stands in for stderr, which stays open
  final _stderr = FakeStderr();

  HeadlessTerminal? _terminal;
  AppBinding? _binding;
  Vt? _vt;
  FrameRecorder? _recorder;
  var _fed = 0;
  var _kitty = false;
  Duration _frameGap = Duration.zero;
  Timer? _inputTimer;
  var _ended = false;
  Object? _error;
  late StackTrace _stack;
  var _thrown = false;

  /// The terminal the app runs on: [HeadlessTerminal.frames] holds every
  /// frame it wrote.
  HeadlessTerminal get terminal => _terminal ?? (throw _notStarted());

  /// The binding running the app.
  AppBinding get binding => _binding ?? (throw _notStarted());

  /// The screen mode the app runs in.
  ScreenMode get mode => binding.mode;

  /// Whether the app started and has not ended.
  bool get isRunning => _binding != null && !_ended;

  /// The first call starts the app showing [widget], on a terminal of
  /// [size] (columns, rows; 80 × 24 by default) in [mode] (fullscreen by
  /// default); a later one shows [widget] in place of the one shown before
  /// (state is kept where widgets match, as in any rebuild) and, given
  /// another [size], resizes the terminal first ([resize]). Then pumps as
  /// [pump] does for [duration].
  ///
  /// The rest applies when the first call starts the app. In the inline
  /// mode the screen shows [history] first, a line each, which the app must
  /// not write over, and the app starts on the line after it. With
  /// [viewport] the app draws in that rectangle of the screen [mode] puts
  /// it on instead, the normal one for [ScreenMode.inline], as `runApp`'s
  /// `viewport` has it: over [history] where the rectangle covers it, the
  /// mouse reported on the normal screen too ([mouse]); [lines] and [cell]
  /// still read the whole screen, [viewportLines] the rectangle alone. The
  /// terminal has the kitty keyboard protocol on with [kittyKeyboard] (see
  /// [press]) and the default background [backgroundRgb] (unknown when
  /// null), and the app runs inside [multiplexer]
  /// (`TerminalInfo.multiplexer`). The
  /// terminal shows desktop notifications in [notifications]
  /// (`TerminalInfo.notifications`): by default none, and
  /// [AppBinding.notify] writes nothing. It shows images with [graphics]
  /// (`TerminalCaps.graphics`; by default none, their cells left blank),
  /// through [multiplexer] as a terminal's are passed on. Its cells are
  /// [cellPixels] pixels (width, height) as it reports them
  /// (`TerminalCaps.cellPixelWidth` and `cellPixelHeight`), the emulator's
  /// too; when null it reports none, and the emulator's are 10 × 20. The
  /// binding gets [maxFps],
  /// [maxInlineRows], [clearInlineOnExit] and [exitOnCtrlC] (see
  /// [AppBinding]), and [environment] in place of the process's: none by
  /// default, so that what the shell running the tests exports
  /// (`TWK_DEBUG`, `TWK_SCREEN_READER`, `TWK_LOG`, the editor's variables)
  /// changes nothing; a test that wants one gives it here.
  Future<void> pumpWidget(
    Widget widget, {
    (int, int)? size,
    ScreenMode? mode,
    Duration? duration,
    List<String> history = const [],
    Viewport? viewport,
    bool kittyKeyboard = false,
    int? backgroundRgb,
    Multiplexer multiplexer = Multiplexer.none,
    NotificationProtocol notifications = NotificationProtocol.none,
    GraphicsProtocol graphics = GraphicsProtocol.none,
    (int, int)? cellPixels,
    int maxFps = 60,
    int? maxInlineRows,
    bool clearInlineOnExit = false,
    bool exitOnCtrlC = true,
    Map<String, String> environment = const {},
  }) async {
    final binding = _binding;
    if (binding == null) {
      _start(
        widget,
        size: size ?? (80, 24),
        mode: mode ?? ScreenMode.fullscreen,
        history: history,
        viewport: viewport,
        kittyKeyboard: kittyKeyboard,
        backgroundRgb: backgroundRgb,
        multiplexer: multiplexer,
        notifications: notifications,
        graphics: graphics,
        cellPixels: cellPixels,
        maxFps: maxFps,
        maxInlineRows: maxInlineRows,
        clearInlineOnExit: clearInlineOnExit,
        exitOnCtrlC: exitOnCtrlC,
        environment: environment,
      );
    } else {
      final term = _running();
      if (mode != null && mode != binding.mode) {
        throw ArgumentError.value(
          mode,
          'mode',
          'the app runs in the ${binding.mode.name} mode',
        );
      }
      if (size != null && size != (term.width, term.height)) {
        await _resize(term, size.$1, size.$2);
      }
      clock.run(() => binding.attachRootWidget(widget));
    }
    await pump(duration);
  }

  void _start(
    Widget widget, {
    required (int, int) size,
    required ScreenMode mode,
    required List<String> history,
    required Viewport? viewport,
    required bool kittyKeyboard,
    required int? backgroundRgb,
    required Multiplexer multiplexer,
    required NotificationProtocol notifications,
    required GraphicsProtocol graphics,
    required (int, int)? cellPixels,
    required int maxFps,
    required int? maxInlineRows,
    required bool clearInlineOnExit,
    required bool exitOnCtrlC,
    required Map<String, String> environment,
  }) {
    final (width, height) = size;
    final fullscreen = mode == ScreenMode.fullscreen;
    if (fullscreen && history.isNotEmpty) {
      throw ArgumentError.value(history, 'history', 'is for the inline mode');
    }
    final (cellWidth, cellHeight) = cellPixels ?? (10, 20);
    final vt = fullscreen
        ? Vt(
            width,
            height,
            cellPixelWidth: cellWidth,
            cellPixelHeight: cellHeight,
          )
        : Vt(
            width,
            height,
            scrollback: true,
            allowLineFeed: true,
            // a viewport is where it is on the screen
            relativeOnly: viewport == null,
            cellPixelWidth: cellWidth,
            cellPixelHeight: cellHeight,
          );
    for (final line in history) {
      vt
        ..feed(utf8.encode(line))
        ..feed(const [0x0D, 0x0A]);
    }
    if (viewport == null) {
      vt.guardRows(vt.cy);
    }
    _vt = vt;
    _recorder = FrameRecorder(
      width,
      height,
      inline: !fullscreen,
      history: history,
    );
    _kitty = kittyKeyboard;
    _frameGap = Duration(microseconds: 1000000 ~/ maxFps);
    clock.run(() {
      final term = _terminal = HeadlessTerminal(
        width: width,
        height: height,
        kittyKeyboard: kittyKeyboard,
        backgroundRgb: backgroundRgb,
        multiplexer: multiplexer,
        notifications: notifications,
        caps: TerminalCaps(
          graphics: graphics,
          graphicsMultiplexer: multiplexer,
          cellPixelWidth: cellPixels?.$1 ?? 0,
          cellPixelHeight: cellPixels?.$2 ?? 0,
        ),
        options: TerminalOptions(
          alternateScreen: fullscreen,
          normalScreenMouse: viewport != null,
        ),
      );
      final binding = _binding = AppBinding(
        term,
        viewport: viewport,
        maxFps: maxFps,
        maxInlineRows: maxInlineRows,
        clearInlineOnExit: clearInlineOnExit,
        logs: logs,
        exitOnCtrlC: exitOnCtrlC,
        clock: clock.stopwatch,
        environment: environment,
      );
      unawaited(
        binding
            .run(widget)
            .then<void>(
              (_) => _ended = true,
              onError: (Object error, StackTrace stack) {
                _ended = true;
                _error = error;
                _stack = stack;
              },
            ),
      );
    });
  }

  /// Moves the clock on by [duration], by default the gap between two
  /// frames (a second over the binding's `maxFps`): what is due by then
  /// runs — timers, frames, a lone ESC resolved — in order, so a frame
  /// asked for before the call has run when it returns.
  Future<void> pump([Duration? duration]) async {
    if (_binding == null) {
      throw _notStarted();
    }
    await clock.elapse(duration ?? _frameGap);
    _throwError();
  }

  /// Pumps frame gap after frame gap, as [pump] does, until the app is
  /// idle: a gap passed without a frame written and none of the app's
  /// timers waits (a frame asked for is one, the next tick of an animation
  /// another). A [TestFailure] once the clock has moved on by [timeout]
  /// and the app is still busy: it says how many frames the app wrote and
  /// when the next of its timers is due, and shows the screen and the
  /// render tree, as a failing matcher does.
  Future<void> pumpUntilIdle({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final term = terminal;
    final end = clock.elapsed + timeout;
    var written = 0;
    for (;;) {
      final before = term.frames.length;
      final left = end - clock.elapsed;
      await pump(left < _frameGap ? left : _frameGap);
      final wrote = term.frames.length - before;
      if (wrote == 0 && clock.pendingTimers == 0) {
        return;
      }
      written += wrote;
      if (clock.elapsed >= end) {
        throw TestFailure(_stillBusy(timeout, written));
      }
    }
  }

  String _stillBusy(Duration timeout, int written) {
    final frames = switch (written) {
      0 => 'no frame',
      1 => '1 frame',
      _ => '$written frames',
    };
    final count = clock.pendingTimers;
    final next = clock.nextTimerDue;
    final timers = next == null
        ? 'no timer waits'
        : '${count == 1 ? '1 timer waits' : '$count timers wait'}, the next '
              'due in ${_seconds(next - clock.elapsed)}';
    final which = count == 0 ? '' : ':\n${clock.describeTimers()}';
    return 'pumpUntilIdle: the app is still busy after ${_seconds(timeout)}: '
        'it wrote $frames, and $timers$which\n\n'
        '${describeApp(vt, binding.twkApp.owner.root)}';
  }

  static String _seconds(Duration d) =>
      '${(d.inMicroseconds / 1e6).toStringAsFixed(3)} s';

  /// Runs [fn] in the app's zone, as the app's own code runs, then pumps
  /// a frame ([pump]): how a test changes what the app listens to (a
  /// controller, a notifier, a cubit) and sees the frame that follows.
  ///
  /// ```dart
  /// testTwk('a change of the notifier shows', (t) async {
  ///   final count = ValueNotifier(0);
  ///   await t.pumpWidget(
  ///     ValueListenableBuilder(
  ///       valueListenable: count,
  ///       builder: (context, value, _) => Text('$value'),
  ///     ),
  ///   );
  ///   await t.act(() => count.value = 1);
  ///   expect(t.lines.first, '1');
  /// });
  /// ```
  ///
  /// What [fn] prints and logs goes to [logs], as the app's own `print`
  /// and `log` do. What [fn] throws, it throws, before the frame. An async
  /// [fn] is awaited before the frame, the clock moved on as far as it waits
  /// ([FakeClock.elapseUntil]; not at all where it waits for no timer),
  /// and what it completes with an error with is thrown.
  Future<void> act(FutureOr<void> Function() fn) async {
    _running();
    // print and log go to the app's log, as the app's own do; not in the
    // app's zone itself, whose errors stay in it instead of reaching the
    // test
    final result = clock.run(() => logs.run(fn));
    if (result is Future<void>) {
      await clock.elapseUntil(result);
    }
    await pump();
  }

  /// Delivers [bytes] as one read of the terminal's input. As a terminal
  /// does, what the parser holds after them — a lone ESC, an open paste —
  /// is resolved once the clock has moved on by
  /// [HeadlessTerminal.inputTimeout] without more input.
  Future<void> input(List<int> bytes) async {
    await _send(bytes);
    _throwError();
  }

  /// Delivers [text] as typed: its UTF-8 bytes as one read ([input]),
  /// which the parser makes a key of each character.
  Future<void> type(String text) => input(utf8.encode(text));

  /// Presses each key of [keys] in turn, as the bytes the terminal sends
  /// for it, a read each: keys named as key bindings name them, apart by
  /// spaces ([KeyCombo.parseSequence]): `ctrl+s`, `shift+tab`, `A`, `g g`,
  /// `ctrl+x ctrl+s`. A [FormatException] names a typo.
  ///
  /// The event is what the parser makes of the bytes: `ctrl+i` is Tab, as
  /// on a real terminal. Without the kitty keyboard protocol some keys
  /// have no bytes of their own (Ctrl+Shift and a letter, Ctrl+Enter,
  /// Super): an [ArgumentError] names them. A key the parser tells apart
  /// only after a pause (Escape without the protocol) is delivered after
  /// it: the clock moves on by [HeadlessTerminal.inputTimeout].
  Future<void> press(String keys) async {
    final term = _running();
    for (final bytes in keyBytes(keys, kitty: _kitty)) {
      await _send(bytes);
      final wait = term.inputTimeout;
      if (wait != null) {
        await clock.elapse(wait);
      }
      _throwError();
    }
  }

  /// Pastes [text] as a terminal with bracketed paste does: between its
  /// start and end markers, in one read.
  Future<void> paste(String text) => input([
    ...ascii.encode('\x1b[200~'),
    ...utf8.encode(text),
    ...ascii.encode('\x1b[201~'),
  ]);

  /// Delivers the mouse report (SGR, mode 1006) of [kind] at the cell
  /// ([x], [y]), 0-based, with [button] (0 left, 1 middle, 2 right, 8 to 11
  /// the side buttons) for a press, release or drag, and [modifiers]
  /// ([Mod]'s Shift, Alt and Ctrl). A [StateError] in the inline mode,
  /// where the terminal keeps the mouse for itself, but in a viewport
  /// (see [pumpWidget]), whose app gets the events in its own cells.
  Future<void> mouse(
    MouseKind kind,
    int x,
    int y, {
    int button = 0,
    int modifiers = 0,
  }) async {
    final term = _running();
    if (mode == ScreenMode.inline && binding.twkApp.viewport == null) {
      throw StateError('the inline mode gets no mouse reports');
    }
    RangeError.checkValueInInterval(x, 0, term.width - 1, 'x');
    RangeError.checkValueInInterval(y, 0, term.height - 1, 'y');
    await _send(mouseBytes(kind, x, y, button, modifiers));
    _throwError();
  }

  /// Presses [button] at the cell ([x], [y]) and releases it there.
  Future<void> click(int x, int y, {int button = 0}) async {
    await mouse(MouseKind.down, x, y, button: button);
    await mouse(MouseKind.up, x, y, button: button);
  }

  /// The terminal becomes [width] × [height] cells, and the app gets a
  /// [ResizeEvent]. On the alternate screen the emulator fills the cells
  /// with junk, which the app has to paint over; the normal screen of the
  /// inline mode keeps what it shows (see [Vt.resizeKeeping]).
  Future<void> resize(int width, int height) async {
    await _resize(_running(), width, height);
    _throwError();
  }

  Future<void> _resize(HeadlessTerminal term, int width, int height) async {
    final vt = this.vt;
    _recorder!.resized(term.frames.length, width, height);
    if (mode == ScreenMode.fullscreen) {
      vt.resize(width, height);
    } else {
      vt.resizeKeeping(width, height);
    }
    clock.run(() => term.resize(width, height));
    await clock.flushMicrotasks();
  }

  /// Quits the app, unless it has ended, and runs it until it has: the
  /// terminal is restored, the tree unmounted. Throws the error it ended
  /// with, unless a call threw it already.
  Future<void> quit() async {
    final binding = this.binding;
    for (var i = 0; !_ended; i++) {
      if (i == 0) {
        clock.run(binding.quit);
        await clock.flushMicrotasks();
      } else if (i < 100) {
        await clock.elapse(_frameGap);
      } else {
        throw StateError('the app did not end within 100 frames of quit');
      }
    }
    _throwError();
  }

  /// The emulator, fed every frame written so far.
  Vt get vt {
    final vt = _vt ?? (throw _notStarted());
    _feed(vt);
    return vt;
  }

  void _feed(Vt vt) {
    final frames = terminal.frames;
    for (; _fed < frames.length; _fed++) {
      vt.feed(frames[_fed]);
    }
  }

  /// The rows of the screen as text, without the blanks that end them, a
  /// wide glyph once.
  List<String> get lines {
    final vt = this.vt;
    return vt.lines.sublist(vt.history.length);
  }

  /// Inline mode: the lines scrolled off the top of the screen, oldest
  /// first, as [lines] gives rows.
  List<String> get scrollback {
    final vt = this.vt;
    return vt.lines.sublist(0, vt.history.length);
  }

  /// The rows of the app's viewport (see [pumpWidget]) as [lines] gives the
  /// screen's, from its first column: as many of its rows and columns as
  /// the screen has. A [StateError] for an app in none.
  List<String> get viewportLines {
    final v =
        binding.twkApp.viewport ??
        (throw StateError('the app has no viewport'));
    final vt = this.vt;
    final right = v.left + v.width < vt.width ? v.left + v.width : vt.width;
    final bottom = v.top + v.height < vt.height ? v.top + v.height : vt.height;
    return [
      for (var y = v.top; y < bottom; y++)
        [
          for (var x = v.left; x < right; x++)
            if (vt.cell(x, y) case VtCell(:final text, role: != -1)) text,
        ].join().trimRight(),
    ];
  }

  /// The rows of [region], a rectangle of the screen as [FinderTester.rect]
  /// gives one, as [lines] gives the screen's: the text of its cells, a
  /// wide glyph once, from the region's first column and without the
  /// blanks that end a row; as many of its rows and columns as the screen
  /// has. A wide glyph cut by the region's left edge is left out.
  ///
  /// ```dart
  /// expect(t.linesIn((x: 10, y: 0, width: 8, height: 2)), ['list', 'one']);
  /// ```
  List<String> linesIn(({int x, int y, int width, int height}) region) {
    final vt = this.vt;
    final left = region.x < 0 ? 0 : region.x;
    final top = region.y < 0 ? 0 : region.y;
    final right = region.x + region.width < vt.width
        ? region.x + region.width
        : vt.width;
    final bottom = region.y + region.height < vt.height
        ? region.y + region.height
        : vt.height;
    return [
      for (var y = top; y < bottom; y++)
        [
          for (var x = left; x < right; x++)
            if (vt.cell(x, y) case VtCell(:final text, role: != -1)) text,
        ].join().trimRight(),
    ];
  }

  /// The cell of the screen at column [x] and row [y]: its text, colors
  /// and attributes, which are numbers as [Color] and [Attr] are (`0` for
  /// the terminal's default color).
  VtCell cell(int x, int y) => vt.cell(x, y);

  /// Where the cursor is: column and row of the screen.
  (int, int) get cursor {
    final vt = this.vt;
    return (vt.cx, vt.cy);
  }

  /// Whether the terminal shows the cursor.
  bool get cursorVisible => vt.cursorVisible;

  /// The frames the app wrote so far, in order: each write to the
  /// terminal ([HeadlessTerminal.frames]) with its time on the [clock] and
  /// the screen it left, replayed on an emulator of its own that resizes
  /// where the terminal did.
  List<RecordedFrame> get frames {
    final recorder = _recorder ?? (throw _notStarted());
    _stamp();
    return recorder.replay(terminal.frames);
  }

  /// What the app wrote to the terminal, as text: the bytes of the frames
  /// ([HeadlessTerminal.frames]) from frame [since] on, by default all of
  /// them, decoded as UTF-8, a byte that is not as U+FFFD. What a test
  /// looks for in it is a sequence the screen does not show: a mode set,
  /// the clipboard written (OSC 52), a notification, a scroll.
  ///
  /// ```dart
  /// testTwk('a frame that changes nothing writes nothing', (t) async {
  ///   await t.pumpWidget(const Text('hello'));
  ///   expect(t.written(), contains('hello'));
  ///   final from = t.terminal.frames.length;
  ///   await t.pump();
  ///   expect(t.written(since: from), isEmpty);
  /// });
  /// ```
  String written({int since = 0}) => utf8.decode([
    for (final f in terminal.frames.skip(since)) ...f,
  ], allowMalformed: true);

  /// Writes the frames so far to the file at [path] as an output trace
  /// (`Trace` in twk_core), each at its time on the [clock], which
  /// `dart run tool/replay.dart --trace` plays. Its size is the terminal's
  /// when the app started; it has no resizes, nor the inline mode's
  /// history. `addTearDown(() => t.writeTrace(path))` keeps the frames of
  /// a test that fails.
  void writeTrace(String path) {
    final recorder = _recorder ?? (throw _notStarted());
    _stamp();
    File(path).writeAsBytesSync(recorder.trace(terminal.frames));
  }

  // the frames written since the clock moved last were written now
  void _stamp() => _recorder?.stamp(_terminal!.frames.length, clock.elapsed);

  // the last [count] frames that changed the screen, then the app's log
  void _printOnFailure(int count) {
    final recorder = _recorder;
    if (recorder == null) {
      return;
    }
    if (count > 0) {
      _stamp();
      final last = recorder.last(terminal.frames, count);
      if (last != null) {
        printOnFailure(last);
      }
    }
    final records = logs.records;
    if (records.isNotEmpty) {
      final shown = records.length > _logOnFailure
          ? records.sublist(records.length - _logOnFailure)
          : records;
      final which = shown.length == records.length
          ? records.length == 1
                ? '1 record'
                : '${records.length} records'
          : 'the last ${shown.length} of ${records.length} records';
      printOnFailure("the app's log, $which:\n${shown.join('\n')}");
    }
  }

  /// How many of the app's log records a test that fails prints.
  static const _logOnFailure = 20;

  /// The app's screen mode and the terminal's size, `fullscreen, 80×24`,
  /// and whether it has ended; `no app` before [pumpWidget].
  @override
  String toString() {
    final term = _terminal;
    if (term == null) {
      return 'no app';
    }
    final ended = _ended ? ', ended' : '';
    return '${mode.name}, ${term.width}×${term.height}$ended';
  }

  HeadlessTerminal _running() {
    final term = terminal;
    if (_ended) {
      throw StateError('the app has ended');
    }
    return term;
  }

  Future<void> _send(List<int> bytes) async {
    final term = _running();
    clock.run(() {
      _inputTimer?.cancel();
      term.input(bytes);
      final wait = term.inputTimeout;
      _inputTimer = wait == null
          ? null
          : Timer(wait, () {
              if (!_ended) {
                term.timeOutInput();
              }
            });
    });
    await clock.flushMicrotasks();
  }

  void _throwError() {
    final error = _error;
    if (error != null && !_thrown) {
      _thrown = true;
      Error.throwWithStackTrace(error, _stack);
    }
  }

  static StateError _notStarted() =>
      StateError('no app: pumpWidget starts one');

  /// Ends the test's app, if it started: quits it, throws an error it
  /// ended with that was not thrown yet, feeds the emulator the rest.
  Future<void> _end() async {
    final vt = _vt;
    if (vt != null) {
      await quit();
      _feed(vt);
    }
  }
}
