/// A terminal in memory, [HeadlessTerminal], and a render tree painted
/// once to text, [renderToString]: for tests, snapshots and one-off
/// output.
///
/// @docImport 'app.dart';
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'canvas.dart';
import 'input/coalesce.dart';
import 'input/events.dart';
import 'input/parser.dart';
import 'line_encoder.dart';
import 'log.dart';
import 'presenter.dart';
import 'render/render.dart';
import 'style.dart';
import 'surface.dart';
import 'terminal/sequences.dart';
import 'terminal/terminal.dart';
import 'unicode/unicode.dart';

/// A [TerminalBackend] in memory, of the size and with the capabilities
/// the caller chooses. Input goes in as bytes and is decoded by the same
/// [InputParser] a [Terminal] reads stdin with; every frame written is
/// kept in [frames]. With `TerminalOptions(alternateScreen: false)` an app
/// runs on it in the inline mode, from the line the cursor is on, as on
/// the normal screen of a real terminal. It can be handed to another
/// program and taken back ([suspend], [resume]) as a [Terminal] can.
///
/// It starts no timers. What a terminal resolves after a pause in the
/// input — a lone ESC, a paste whose end marker was lost — waits here for
/// [timeOutInput], which a caller keeping a clock calls once
/// [inputTimeout] has passed without input.
///
/// It starts with no mouse reports on, whatever its options say, and
/// writes nothing for them until they are switched ([mouseTracking]). Its
/// [TerminalInfo.multiplexer] is `multiplexer`: what an app sends the
/// terminal through tmux or screen comes wrapped for it. Its
/// [TerminalInfo.notifications] is `notifications`: [notify] writes in
/// that protocol, nothing for [NotificationProtocol.none]. Its
/// [TerminalInfo.pointerShapes], [TerminalInfo.pointerNames] and
/// [TerminalInfo.progressReports] are `pointerShapes`, `pointerNames` and
/// `progressReports`; the states set on it go to
/// [frames], and are put back there as a [Terminal] puts them back
/// ([TerminalStateBackend]). Its [TerminalInfo.bidi] is `bidi`: by default
/// the app orders right-to-left text, as for a terminal that does no bidi.
/// Its [TerminalInfo.palette] is `palette`: the entries an app blends
/// palette colors with, xterm's where it has none.
///
/// A [TwkApp] on a terminal 20 x 3, a key typed, the frames read back:
///
/// ```dart
/// final terminal = HeadlessTerminal(width: 20, height: 3);
/// final app = TwkApp(terminal);
/// final pen = app.screen.styles.pen(const Pen());
/// final running = app.run(RenderText('hi', pen), (event) => app.quit());
/// terminal.type('q'); // handled once the first frame is drawn
/// await running;
/// print(terminal.frames.length); // 1: the frame drawing "hi"
/// ```
///
/// See also:
///
///  * [renderToString], a render tree painted once, without an app.
///  * package `twk_test`, whose tester runs a widget app on this terminal
///    under a fake clock.
final class HeadlessTerminal
    implements
        SuspendableBackend,
        MouseTrackingBackend,
        TerminalStateBackend,
        WindowBackend {
  /// A terminal [width] x [height] cells, 80 x 24 by default, that tells
  /// an app what the other parameters say: [TerminalInfo.caps] (`caps`),
  /// how it measures text (`textMode`, `ambiguousWidth`), its colors
  /// (`colorMode`, `foregroundRgb`, `backgroundRgb`, `palette`), whether
  /// it speaks the kitty keyboard protocol (`kittyKeyboard`), and the rest
  /// as the class comment says. [options] chooses the screen mode;
  /// `cursorColumn` is where the cursor starts in the inline mode;
  /// `settings` are the app's settings it sets, as a terminal of the
  /// process's sets those of its environment ([TerminalInfo.settings]).
  HeadlessTerminal({
    this.width = 80,
    this.height = 24,
    TerminalCaps caps = const TerminalCaps(),
    TextMode textMode = TextMode.graphemes,
    int ambiguousWidth = 1,
    ColorMode colorMode = ColorMode.trueColor,
    int? foregroundRgb,
    int? backgroundRgb,
    Map<int, int> palette = const {},
    bool kittyKeyboard = false,
    this.options = const TerminalOptions(),
    int cursorColumn = 0,
    NotificationProtocol notifications = NotificationProtocol.none,
    Multiplexer multiplexer = Multiplexer.none,
    bool pointerShapes = false,
    PointerNames pointerNames = PointerNames.css,
    bool progressReports = false,
    BidiReordering bidi = BidiReordering.app,
    Map<String, String> settings = const {},
  }) : info = TerminalInfo(
         caps: caps,
         textMode: textMode,
         ambiguousWidth: ambiguousWidth,
         colorMode: colorMode,
         foregroundRgb: foregroundRgb,
         backgroundRgb: backgroundRgb,
         palette: palette,
         inBandResize: false,
         graphemeMode: false,
         kittyKeyboard: kittyKeyboard,
         answeredQueries: true,
         alternateScreen: options.alternateScreen,
         cursorColumn: options.alternateScreen ? null : cursorColumn,
         notifications: notifications,
         multiplexer: multiplexer,
         pointerShapes: pointerShapes,
         pointerNames: pointerNames,
         progressReports: progressReports,
         bidi: bidi,
         settings: settings,
       );

  /// What a [Terminal] waits for the rest of a sequence that has surely
  /// started (or, with the kitty protocol, after any ESC).
  static const _longEscapeTimeout = Duration(milliseconds: 500);

  /// Only the screen mode, the mouse on the normal screen and the pauses
  /// are used: [TerminalOptions.alternateScreen],
  /// [TerminalOptions.normalScreenMouse], [TerminalOptions.escapeTimeout]
  /// and [TerminalOptions.pasteTimeout]. In the inline mode the cursor starts
  /// in the column `cursorColumn` gives ([TerminalInfo.cursorColumn]): 0 is
  /// the start of a line.
  final TerminalOptions options;

  @override
  final TerminalInfo info;

  @override
  int width;

  @override
  int height;

  final _parser = InputParser();
  final _events = StreamController<InputEvent>();

  /// Decoded input, plus [ResizeEvent]s.
  @override
  Stream<InputEvent> get events => _events.stream;

  /// Every frame written, as written, and the line break [resume] writes
  /// in the inline mode.
  final frames = <Uint8List>[];

  /// How many times [flush] was called.
  var flushes = 0;

  /// Whether [close] was called.
  var closed = false;

  /// While set, [flush] completes only after it does: a slow connection.
  Future<void>? holdFlush;

  /// Delivers [bytes] as one read of the terminal's input; dropped while
  /// [suspended]: the other program reads it. As on a [Terminal], of a
  /// run of motions with no button held and the same modifiers in one
  /// read only the last is delivered.
  void input(List<int> bytes) {
    if (!_suspended) {
      _deliver(_parser.feed(bytes));
    }
  }

  /// Delivers [text], UTF-8 encoded, as the terminal's input.
  void type(String text) => input(utf8.encode(text));

  /// How long a [Terminal] would wait for more input before it resolves
  /// what is pending (see [timeOutInput]); null when nothing waits.
  Duration? get inputTimeout {
    if (_parser.inPaste) {
      return options.pasteTimeout;
    }
    if (!_parser.hasPending) {
      return null;
    }
    return info.kittyKeyboard || _parser.sequenceStarted
        ? _longEscapeTimeout
        : options.escapeTimeout;
  }

  /// Resolves what is pending as a [Terminal] does when [inputTimeout]
  /// passes without input: a lone ESC becomes the Escape key (ESC and a
  /// key, that key with Alt), an open paste is delivered as it is.
  void timeOutInput() =>
      _deliver(_parser.inPaste ? _parser.endPaste() : _parser.flush());

  /// Resizes the terminal to [width] x [height] cells: a [ResizeEvent]
  /// follows, and the size changes with it, unless that is the size
  /// already.
  void resize(int width, int height) {
    if (width != this.width || height != this.height) {
      _deliver([ResizeEvent(width, height)]);
    }
  }

  void _deliver(List<InputEvent> events) =>
      deliverCoalesced(events, _deliverOne);

  // whether the window has the focus, as the last focus report typed said
  var _focused = true;

  void _deliverOne(InputEvent e) {
    if (e is ResizeEvent) {
      width = e.width;
      height = e.height;
    } else if (e is FocusEvent) {
      _focused = e.focused;
    }
    _events.add(e);
  }

  MouseTracking _mouseTracking = MouseTracking.off;

  @override
  MouseTracking get mouseTracking => _mouseTracking;

  /// The modes that switch to [tracking] go to [frames], as a [Terminal]
  /// writes them; also while suspended, when nothing else is written.
  @override
  set mouseTracking(MouseTracking tracking) {
    final from = _mouseTracking;
    if (closed ||
        !(options.alternateScreen || options.normalScreenMouse) ||
        tracking == from) {
      return;
    }
    _mouseTracking = tracking;
    frames.add(ascii.encode(mouseTrackingSequence(from, tracking)));
  }

  /// Keeps a copy of [bytes] in [frames]; dropped once closed.
  @override
  void write(Uint8List bytes) {
    if (!closed) {
      frames.add(Uint8List.fromList(bytes));
    }
  }

  /// Writes the sequence that sets the window's title to [title] to
  /// [frames] ([titleSequence]); nothing once closed. It keeps no title of
  /// the user's to give back, so pushes none, as [Terminal.setTitle] does.
  @override
  void setTitle(String title) {
    if (!closed) {
      frames.add(utf8.encode(titleSequence(title)));
    }
  }

  var _notifications = 0;

  /// Writes a desktop notification of [title] and [body] to [frames] as a
  /// [Terminal] does ([Terminal.notify]), in [TerminalInfo.notifications]
  /// through [TerminalInfo.multiplexer], each under an id of its own, `1`
  /// first; the bell only while the focus report typed last said the
  /// window lost the focus; nothing once closed.
  @override
  void notify(String title, String body) {
    if (closed ||
        (info.notifications == NotificationProtocol.bell && _focused)) {
      return;
    }
    final s = notifySequence(
      title,
      body,
      protocol: info.notifications,
      multiplexer: info.multiplexer,
      id: '${++_notifications}',
    );
    if (s.isNotEmpty) {
      frames.add(utf8.encode(s));
    }
  }

  /// The states set on the terminal, in the order they were first set:
  /// what sets each and what puts it back.
  final _states = <Object, (String, String)>{};

  /// Writes [sequence] to [frames], or, while [suspended], on [resume].
  /// [restore] is written when it is suspended or closed. [refresh] is not
  /// kept: no timer is started.
  @override
  void setTerminalState(
    Object key,
    String sequence,
    String restore, {
    Duration? refresh,
  }) {
    if (closed) {
      return;
    }
    _states[key] = (sequence, restore);
    if (!_suspended) {
      frames.add(ascii.encode(sequence));
    }
  }

  /// Writes what puts the state set under [key] back to [frames] and
  /// forgets it; nothing when none is set, while [suspended] or once
  /// closed.
  @override
  void restoreTerminalState(Object key) {
    final state = _states.remove(key);
    if (state != null && !closed && !_suspended) {
      frames.add(ascii.encode(state.$2));
    }
  }

  /// What puts the states back, the last set first; null when none is set.
  Uint8List? _restores() => _states.isEmpty
      ? null
      : ascii.encode(_states.values.map((s) => s.$2).toList().reversed.join());

  @override
  Future<void> flush() async {
    flushes++;
    await holdFlush;
  }

  var _suspended = false;

  /// Whether the terminal is handed to another program: from [suspend] to
  /// [resume].
  bool get suspended => _suspended;

  /// How many times the terminal was handed over.
  var suspends = 0;

  /// In the inline mode, the column [resume] finds the cursor in: where the
  /// other program left it, 0 being the start of a line.
  var resumeColumn = 0;

  /// Hands the terminal to another program: [input] is dropped until
  /// [resume]. Nothing is written but what puts the states set on it back
  /// ([setTerminalState]). Does nothing once handed over or closed.
  @override
  Future<void> suspend() async {
    if (closed || _suspended) {
      return;
    }
    if (_restores() case final restores?) {
      frames.add(restores);
    }
    _suspended = true;
    suspends++;
  }

  /// Takes the terminal back after [suspend], the states set on it written
  /// again. In the inline mode the cursor is left at the start of a line,
  /// as a [Terminal] leaves it: unless [resumeColumn] is 0 a line break is
  /// written.
  @override
  Future<void> resume() async {
    if (closed || !_suspended) {
      return;
    }
    _suspended = false;
    if (_states.isNotEmpty) {
      frames.add(ascii.encode(_states.values.map((s) => s.$1).join()));
    }
    if (!options.alternateScreen && resumeColumn != 0) {
      write(Uint8List.fromList(const [0x0D, 0x0A]));
    }
  }

  /// Writes what puts the states set on it back, unless [suspended], and
  /// ends [events]. Safe to call more than once.
  @override
  Future<void> close() async {
    if (closed) {
      return;
    }
    if (!_suspended) {
      if (_restores() case final restores?) {
        frames.add(restores);
      }
    }
    closed = true;
    // the done event is only delivered to a listener: without one the
    // future never completes
    final done = _events.close();
    if (_events.hasListener) {
      await done;
    }
  }
}

/// Lays [root] out at [width] x [height] cells, paints it once and returns
/// the screen as text: one line per row, without the blanks that end it,
/// a wide glyph once for its two cells, styles left out ([LineEncoder]).
/// With [ansi], the bytes the presenter writes for that frame instead.
///
/// The pens in the tree are ids in [styles]. [root] is painted in full,
/// whatever it painted before, and is left detached.
///
/// [onLog] is where the tree's own warnings go, such as a [RenderFlex]
/// whose children overflow it, in debug ([PipelineOwner.onLog]): the sink
/// of the tool that renders it. Null, they go to [log], as from any tree
/// whose owner has no route of its own.
///
/// ```dart
/// final styles = StyleTable();
/// final text = RenderText('Hello', styles.pen(const Pen()));
/// print(renderToString(text, 10, 1, styles: styles)); // Hello
/// ```
///
/// See also:
///
///  * [HeadlessTerminal], a terminal in memory a [TwkApp] runs on, for
///    frames after the first.
String renderToString(
  RenderObject root,
  int width,
  int height, {
  required StyleTable styles,
  bool ansi = false,
  void Function(LogRecord record)? onLog,
}) {
  final glyphs = GlyphTable();
  final surface = Surface(width, height);
  final canvas = Canvas(surface, styles, glyphs);
  final presenter = Presenter(width, height, styles, glyphs);
  final owner = PipelineOwner(() {}, segmenter: canvas.segmenter)
    ..onLog = onLog
    ..root = root
    ..markAllDirty();
  try {
    owner
      ..flushLayout(width, height)
      ..flushPaint(PaintContext(canvas, surface, presenter));
  } finally {
    root.detach();
  }
  if (ansi) {
    presenter.present(surface);
    return utf8.decode(presenter.out.view);
  }
  final lines = LineEncoder(styles, ansi: false);
  for (var y = 0; y < height; y++) {
    if (y > 0) {
      lines.out.byte(0x0a);
    }
    lines.row(surface, glyphs, y);
  }
  return lines.take();
}
