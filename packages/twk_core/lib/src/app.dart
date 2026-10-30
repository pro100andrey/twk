/// The frame loop: input -> state changes -> what runs before layout (a
/// widget tree's build) -> layout/paint of dirty boundaries -> presenter
/// -> one write per frame -> what runs after it (unmounting what the
/// frame's builds removed), with frame-rate capping and
/// backpressure (a new frame starts only after the previous one reached
/// the OS, so frames never queue up behind a slow connection).
///
/// Both screen modes run here: fullscreen on the alternate screen, and the
/// inline mode (`TerminalOptions(alternateScreen: false)`), a region of the
/// normal screen sized to its content (see [TwkApp]); so does a fixed
/// viewport, a rectangle of the screen the app owns ([TwkApp.viewport]);
/// any of them on output that takes plain text only too
/// ([TerminalInfo.plain]), which gets the last frame as text.
///
/// @docImport 'headless.dart';
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'byte_sink.dart';
import 'canvas.dart';
import 'input/events.dart';
import 'line_encoder.dart';
import 'log.dart';
import 'platform/platform.dart';
import 'platform/platform.dart' as platform show environment;
import 'presenter.dart';
import 'render/render.dart';
import 'screen.dart';
import 'surface.dart';
import 'terminal/sequences.dart' show BidiReordering;
import 'terminal/terminal.dart';

/// The names `TWK_DEBUG`, a comma-separated list, gives in [environment],
/// the empty ones left out.
Set<String> _debugNames(Map<String, String> environment) => {
  for (final n in (environment['TWK_DEBUG'] ?? '').split(','))
    if (n.isNotEmpty) n,
};

/// What a [TwkApp]'s frames cost: how many wrote bytes, how many bytes,
/// and how long the core took for each (what runs before layout, layout,
/// paint and present; the write and the flush not counted).
///
/// [TwkApp.stats] has the app's, updated at the end of each frame.
///
/// See also:
///
///  * [PresentStats], what the presenter compared and wrote in a frame.
final class FrameStats {
  /// Statistics of no frames yet, all zero.
  FrameStats();

  /// How many frames wrote bytes; a frame that changed nothing is not
  /// counted.
  var frames = 0;

  /// The bytes all frames wrote.
  var bytes = 0;

  /// The bytes the last frame wrote, 0 when it changed nothing.
  var lastBytes = 0;

  /// How long the last frame took, in microseconds: the sum of its stages
  /// ([lastBuildMicros] and those after it).
  var lastMicros = 0;

  /// How long all frames took, in microseconds, those that wrote nothing
  /// too.
  var totalMicros = 0;

  /// How long what ran before the last frame's layout (a widget tree's
  /// build) took, in microseconds.
  ///
  /// It and the stages after it, [lastLayoutMicros], [lastPaintMicros] and
  /// [lastPresentMicros], add up to [lastMicros].
  var lastBuildMicros = 0;

  /// How long the last frame's layout took, with the inline region's
  /// sizing, in microseconds.
  var lastLayoutMicros = 0;

  /// How long the last frame's paint took, with the inline mode's commits,
  /// in microseconds.
  var lastPaintMicros = 0;

  /// How long encoding the last frame's bytes took, in microseconds.
  var lastPresentMicros = 0;

  /// The repaint boundaries, the root among them, the last frame
  /// repainted because they were marked for paint
  /// ([PipelineOwner.dirtyBoundaries]): on their own, or with one marked
  /// around them.
  var lastRepaints = 0;

  final _recent = List<int>.filled(128, 0);
  var _n = 0;

  void _record(int micros) => _recent[_n++ % _recent.length] = micros;

  /// The median time, in microseconds, of the last 128 frames that wrote
  /// bytes (what runs before layout, layout, paint and encode); 0 before
  /// the first.
  ///
  /// Unlike the mean it isn't dominated by the JIT warming up.
  int get medianMicros {
    final k = _n < _recent.length ? _n : _recent.length;
    if (k == 0) {
      return 0;
    }
    final sorted = _recent.sublist(0, k)..sort();
    return sorted[k ~/ 2];
  }
}

/// The app on a terminal. On the alternate screen ([TerminalInfo] says
/// which) the tree is laid out at the terminal's size. In the inline mode
/// it is laid out in a region of the normal screen that starts on the line
/// the cursor was on (the next one if text was on it) and is as tall as the
/// root's max intrinsic height at the terminal's width, at least 1 row and
/// at most [maxInlineRows] or the terminal's height: it grows as the
/// content does, scrolling the history up into the scrollback once it
/// reaches the bottom of the screen, and shrinks only when asked
/// ([shrinkRegion]). Rows above it are never written, except by [commit],
/// which puts finished content in above it as lines of the terminal's
/// history. A resize repaints it from scratch at the new width. When [run]
/// ends the region stays on the screen with the cursor on the line below
/// it, or with [clearInlineOnExit] is erased.
///
/// With a [viewport] the tree is laid out in that rectangle of the screen
/// instead, whichever screen the terminal is on (the normal one with
/// `TerminalOptions(alternateScreen: false)`), and nothing outside it is
/// written: no clear, no scroll of the screen, autowrap off only while
/// a frame draws, the cursor put back where the app found it after each
/// frame that hides it and when [run] ends, and the viewport left as it
/// is then (see [Presenter.viewport]). The part of it the screen has is
/// what is laid out: a resize cuts it at the screen's edges, or gives
/// back what an earlier one cut, and repaints it. Mouse events come
/// relative to it; those outside it are dropped, but the drags and the
/// release of a button pressed in it, which come on its nearest cell.
///
/// On output that takes plain text only ([TerminalInfo.plain]: a pipe, a
/// file, CI) frames are laid out and painted as they come, but none is
/// written: when [run] ends the last one is, as lines of text (styles left
/// out, a wide glyph once, without the blanks that end a row or the blank
/// rows that end the frame), each ending in LF; with [clearInlineOnExit]
/// in the inline mode it isn't. What is committed ([commit]) is written as
/// such lines as it is committed. A [viewport] is laid out at its own
/// size there, and its rows are the lines, with no blanks before them to
/// put them where it is: such output has no screen to place it on or cut
/// it at.
///
/// A render tree on the terminal, until q is pressed:
///
/// ```dart
/// Future<void> main() async {
///   final app = TwkApp(await Terminal.open());
///   final pen = app.screen.styles.pen(const Pen(fg: Color.green));
///   await app.run(RenderText('Press q to quit', pen), (event) {
///     if (event is KeyEvent && event.char == 'q') {
///       app.quit();
///     }
///   });
/// }
/// ```
///
/// See also:
///
///  * [HeadlessTerminal], a terminal in memory to run an app on in a test.
///  * [renderToString], a render tree painted once to text, with no app.
///  * [Screen], the frame's cells and the bytes that draw them, without a
///    render tree.
final class TwkApp {
  /// An app on [terminal], drawn at most [maxFps] frames a second, 60 by
  /// default.
  ///
  /// [logs] is where [log], `print` and uncaught errors go while [run]
  /// runs, by default a [LogSink] that also appends to the file `TWK_LOG`
  /// names. [maxInlineRows] and [clearInlineOnExit] are for the inline
  /// mode, [viewport] makes the app a fixed rectangle of the screen (see
  /// [TwkApp]). [framesInRow], [timeline] and [serveLogs] are debug aids,
  /// by default on when `TWK_DEBUG` names `frames`, `timeline` or `logs`.
  /// [clock] spaces the frames, by default a [Stopwatch] started here.
  ///
  /// [environment] is where those defaults are read from, `TWK_LOG` and
  /// `TWK_DEBUG` ([debugNames]), here and nowhere else. Null, the default,
  /// for the process's, in which the terminal's settings
  /// ([TerminalInfo.settings]: `TWK_SCREEN_READER` and `TWK_DEBUG` of the
  /// environment of a terminal of the process's, such as the `twk shell`
  /// an editor serves the app with) take the place of the process's
  /// values: the terminal the app is on switches them, set empty too.
  /// Given, it is the whole of it, the terminal's settings not read: a
  /// test passes `const {}`, so that what the shell that runs it exports
  /// changes nothing, and asks for a debug aid by its parameter; a server
  /// of apps to others (twk_ssh's) passes `const {}` too.
  ///
  /// The screen starts as [terminal] says ([TerminalBackend.info]): its
  /// size, capabilities, colors and how it measures text.
  factory TwkApp(
    TerminalBackend terminal, {
    int maxFps = 60,
    LogSink? logs,
    int? maxInlineRows,
    bool clearInlineOnExit = false,
    Viewport? viewport,
    bool? framesInRow,
    bool? timeline,
    bool? serveLogs,
    Stopwatch? clock,
    Map<String, String>? environment,
  }) {
    final on = environment ?? _environmentOn(terminal);
    return TwkApp._(
      terminal,
      on,
      _debugNames(on),
      maxFps: maxFps,
      logs: logs,
      maxInlineRows: maxInlineRows,
      clearInlineOnExit: clearInlineOnExit,
      viewport: viewport,
      framesInRow: framesInRow,
      timeline: timeline,
      serveLogs: serveLogs,
      clock: clock,
    );
  }

  TwkApp._(
    this.terminal,
    this.environment,
    this.debugNames, {
    required this.maxFps,
    required LogSink? logs,
    required this.maxInlineRows,
    required this.clearInlineOnExit,
    required this.viewport,
    required bool? framesInRow,
    required bool? timeline,
    required bool? serveLogs,
    required Stopwatch? clock,
  }) : clock = clock ?? (Stopwatch()..start()),
       logs = logs ?? LogSink(path: environment['TWK_LOG']),
       _plain = terminal.info.plain,
       framesInRow =
           !terminal.info.plain &&
           (framesInRow ?? debugNames.contains('frames')),
       timeline = timeline ?? debugNames.contains('timeline'),
       serveLogs = serveLogs ?? debugNames.contains('logs') {
    final info = terminal.info;
    final inline = viewport == null && !info.alternateScreen;
    final (width, height) = viewport == null
        ? (terminal.width, inline ? 0 : terminal.height)
        : _viewportSize(terminal.width, terminal.height);
    screen = Screen(
      width,
      height,
      caps: info.caps,
      textMode: info.textMode,
      ambiguousWidth: info.ambiguousWidth,
      colorMode: info.colorMode,
      inline: inline,
      viewport: viewport,
      atLineStart: info.cursorColumn == 0,
    );
    screen.presenter.screenWidth = terminal.width;
    screen.styles.defaultForegroundRgb = info.foregroundRgb;
    if (info.backgroundRgb != null) {
      screen.styles.defaultBackgroundRgb = info.backgroundRgb!;
    }
    for (final MapEntry(:key, :value) in info.palette.entries) {
      screen.styles.setPaletteRgb(key, value);
    }
    // layout measures text with the segmenter the canvas draws it with,
    // and orders it as the terminal needs
    owner = PipelineOwner(_needFrame, segmenter: screen.canvas.segmenter)
      ..onLog = this.logs.add
      ..textOrder = info.bidi == BidiReordering.app
          ? TextOrder.visual
          : TextOrder.logical
      ..debugRepaintRainbow = debugNames.contains('rainbow')
      ..debugRelayoutHighlight = debugNames.contains('relayout');
  }

  /// The process's environment, in which [terminal]'s settings
  /// ([TerminalInfo.settings]) take the place of the process's values.
  static Map<String, String> _environmentOn(TerminalBackend terminal) {
    final settings = terminal.info.settings;
    return settings.isEmpty
        ? platform.environment
        : Map.unmodifiable({...platform.environment, ...settings});
  }

  /// The names of `TWK_DEBUG` the app reads ([debugNames]): `frames`
  /// ([framesInRow]), `timeline`, `logs` ([serveLogs]), `rainbow` and
  /// `relayout` ([owner]'s debug paints). A layer above that reads more of
  /// them, as twk's debug aids do, takes these as known too.
  static const debugNamesRead = {
    'frames',
    'timeline',
    'logs',
    'rainbow',
    'relayout',
  };

  /// The environment the app's defaults were read from when it was made:
  /// the one given to the constructor, or the process's with the
  /// terminal's settings over it ([TerminalInfo.settings]). A layer above
  /// reads its own variables from it, so that one map decides them all.
  final Map<String, String> environment;

  /// The names `TWK_DEBUG` gives in [environment], a comma-separated list
  /// read once when the app was made, every one of them: those the app
  /// reads ([debugNamesRead]) and any others, for a layer above to read.
  final Set<String> debugNames;

  /// The terminal the app draws on and reads input from.
  final TerminalBackend terminal;

  /// The most frames a second: a frame requested sooner after the last
  /// waits for the gap.
  final int maxFps;

  /// What frames are spaced by: the gap of [maxFps] passes on it. By
  /// default a started [Stopwatch]; a test gives one its fake clock moves.
  final Stopwatch clock;

  /// Inline mode: the most rows the region grows to; null for the
  /// terminal's height (which limits it anyway).
  final int? maxInlineRows;

  /// Inline mode: erase the region when [run] ends instead of leaving it
  /// on the screen.
  final bool clearInlineOnExit;

  /// The rectangle of the screen the app draws in and owns, null for the
  /// terminal's screen mode (see [TwkApp]).
  final Viewport? viewport;

  /// Where `print`, [log] and uncaught errors in [run] go instead of the
  /// screen; by default also appended to the file `TWK_LOG` names, and
  /// served for `twk logs` with [serveLogs].
  final LogSink logs;

  /// Each frame is written in full below the last one, for reading in a
  /// log, instead of the bytes that draw it in place: a line naming it
  /// (`--- frame 3 (412 bytes) ---`, the bytes it took in place; cut to
  /// the width), then its rows as text (styles left out, a wide glyph
  /// once, without the blanks that end a row), each ending in CR LF; in
  /// the inline mode the rows committed with a frame come before it. The
  /// first frame starts at the top of the alternate screen, or on the
  /// normal one on the line after the cursor's (the cursor's own when it
  /// is at the start of one); the inline region is not left at the end.
  /// By default whether `TWK_DEBUG`, a comma-separated list, names
  /// `frames`. Never on plain output ([TerminalInfo.plain]), which gets
  /// the last frame only.
  final bool framesInRow;

  /// The terminal takes plain text only ([TerminalInfo.plain]).
  final bool _plain;

  /// Each frame, and in it the build ([run]'s `beforeLayout`), layout,
  /// paint, commits (inline mode), present and what runs after it ([run]'s
  /// `afterPresent`, the slice `Finalize`), are slices on
  /// dart:developer's [Timeline] (DevTools' Performance tab). Off, the
  /// frame makes no Timeline call: the VM records its Dart stream by
  /// default, at some 150 ns a slice. By default whether `TWK_DEBUG` names
  /// `timeline`.
  final bool timeline;

  /// [logs] is served for `twk logs` while [run] runs ([LogSink.serve], in
  /// the project the current directory is in), and stops being served when
  /// it ends; a log that can't be served is a warning in it. By default
  /// whether `TWK_DEBUG` names `logs`: unasked, an app opens no socket and
  /// writes no address file.
  final bool serveLogs;

  /// The screen the tree is painted on: its [Screen.styles] make the pens
  /// render objects paint with.
  late final Screen screen;

  /// Lays out and paints the tree. Its debug paints are on from the start
  /// when `TWK_DEBUG` names them: `rainbow`
  /// ([PipelineOwner.debugRepaintRainbow]), `relayout`
  /// ([PipelineOwner.debugRelayoutHighlight]). Its text order
  /// ([PipelineTextOrder.textOrder]) starts as the terminal needs it
  /// ([TerminalInfo.bidi]): visual where right-to-left text is left to the
  /// app, logical where the terminal reorders it; what is committed is
  /// laid out in the order it has then.
  late final PipelineOwner owner;

  /// What the frames have cost so far.
  final stats = FrameStats();

  var _running = false;
  var _scheduled = false;
  var _inFrame = false;
  var _again = false;
  var _shrink = false;

  /// What [stats] time frames with.
  final _statsClock = Stopwatch()..start();
  var _lastFrameAt = -1000000;
  final _done = Completer<void>();

  /// What [run] runs at the start of each frame.
  void Function()? _beforeLayout;

  /// What [run] runs once each frame is painted, before it is written.
  void Function()? _beforePresent;

  /// What [run] runs at the end of each frame.
  void Function()? _afterPresent;

  /// The input events, held until the first frame (see [run]).
  StreamSubscription<InputEvent>? _input;

  /// Where event handling and frames run (see [run]).
  Zone _zone = Zone.current;

  /// The record of the error [run] completes with: its caller reports it.
  LogRecord? _ending;

  // created once: a frame allocates nothing of its own
  late final _ctx = PaintContext(
    screen.canvas,
    screen.surface,
    screen.presenter,
  );
  late final void Function() _runFrame = _frame;

  /// Inline mode: what was committed and is not written yet, oldest first
  /// ([commit]).
  final _commits = Queue<RenderObject>();

  /// Inline mode: the commit whose rows are being written, painted on
  /// [_commitSurface], and the next of its rows to write.
  RenderObject? _committing;
  var _commitRow = 0;

  /// Inline mode: where commits are laid out, measured as the screen
  /// measures text, and painted.
  late final _commitOwner = PipelineOwner(
    _noFrame,
    segmenter: screen.canvas.segmenter,
  )..onLog = logs.add;
  // what is committed, kept from one frame to the next: its styles too
  late final Surface _commitSurface = () {
    final surface = Surface(0, 0);
    screen.keepStylesOf(surface);
    return surface;
  }();
  late final _commitCtx = PaintContext(
    Canvas(
      _commitSurface,
      screen.styles,
      screen.glyphs,
      segmenter: screen.canvas.segmenter,
    ),
    _commitSurface,
    screen.presenter,
  );

  /// Inline mode: the most committed rows a frame writes.
  static const _commitRowsPerFrame = 256;

  /// Frames in a row ([framesInRow]): the text not written yet, and how
  /// many frames were written.
  ByteSink? _rows;
  var _rowFrames = 0;

  /// Writes the rows of [_textRows] into [_rows], as text alone.
  LineEncoder? _lines;

  /// Timeline slices started and not finished yet ([timeline]).
  var _slices = 0;

  /// Runs until [quit]; [onEvent] receives every input event (resizes and
  /// the terminal's default colors, [ColorReport], are handled here first:
  /// either repaints everything).
  ///
  /// [beforeLayout] runs at the start of every frame, before the tree is
  /// laid out (in the inline mode before the region is sized to the root):
  /// what it changes in the tree is laid out and painted by that frame.
  /// Input waits for the first frame: an event that comes before it is
  /// handled once [beforeLayout] has run.
  ///
  /// [beforePresent] runs in every frame once the tree is laid out and
  /// painted, just before the screen is written: what it sets of the
  /// presenter ([Presenter.cursorX], say) goes with that frame, what it
  /// changes in the tree with the next.
  ///
  /// [afterPresent] runs at the end of every frame, once its bytes are
  /// handed to the terminal (also when it has none) and before they are
  /// flushed: the frame's bytes never wait on it, nor it on a slow
  /// connection, and no input is handled between the paint and it. What it
  /// changes in the tree is laid out and painted by the next frame.
  ///
  /// `print` and [log] while handling an event or producing a frame, or in
  /// anything those callbacks schedule, go to [logs] instead of the screen,
  /// as do errors nothing catches there; with [serveLogs] it is served
  /// meanwhile. Once the terminal is restored, the warnings and errors in
  /// [logs] are written to stderr, oldest first.
  ///
  /// An error thrown while handling an event or producing a frame (layout,
  /// paint, writing), or by anything those callbacks schedule, ends the app:
  /// the terminal is restored first, then [run] completes with that error
  /// (which is left out of what goes to stderr). Errors in layout and paint
  /// go to [owner]'s [PipelineOwner.onError] instead when it is set, and
  /// the frame goes on; so does one thrown while the inline region is sized
  /// (the root's max intrinsic height), reported as the root's in
  /// [RenderPhase.layout] once while it is the same, the region keeping its
  /// height, and one thrown while a commit is sized, laid out or painted
  /// (see [commit]).
  ///
  /// An app runs once: a [StateError] when this was called before.
  Future<void> run(
    RenderObject root,
    void Function(InputEvent e) onEvent, {
    void Function()? beforeLayout,
    void Function()? beforePresent,
    void Function()? afterPresent,
  }) async {
    if (_running) {
      throw StateError('an app runs once: run was called before');
    }
    _beforeLayout = beforeLayout;
    _beforePresent = beforePresent;
    _afterPresent = afterPresent;
    _running = true;
    runZonedGuarded(
      () {
        _zone = Zone.current;
        owner.root = root;
        _input = terminal.events.listen((e) {
          var event = e;
          if (e is ResizeEvent) {
            if (viewport != null) {
              final (w, h) = _viewportSize(e.width, e.height);
              screen.presenter.screenWidth = e.width;
              screen.resize(w, h);
            } else {
              // an inline region keeps its height; the next frame fits it
              screen.resize(
                e.width,
                screen.presenter.inline ? screen.height : e.height,
              );
            }
            owner.markAllDirty();
            requestFrame();
          } else if (e is ColorReport) {
            _setDefaultColor(e);
          } else if (e is MouseEvent && viewport != null) {
            final inside = _inViewport(e);
            if (inside == null) {
              return;
            }
            event = inside;
          }
          onEvent(event);
        })..pause();
        requestFrame();
      },
      _fail,
      zoneValues: {logSinkKey: logs},
      zoneSpecification: ZoneSpecification(print: _print),
    );
    final serving = serveLogs ? _serveLogs() : null;
    // what ends the run: the error that ended the app, else the first of
    // the steps below that failed; the others go to the log, so that one
    // does not take the place of the other and the terminal is restored
    // whatever failed
    Object? failure;
    StackTrace? failureStack;
    Future<void> step(String what, FutureOr<void> Function() body) async {
      try {
        await body();
      } on Object catch (error, stack) {
        if (failure == null) {
          failure = error;
          failureStack = stack;
        } else {
          _log(what, error, stack);
        }
      }
    }

    try {
      await _done.future;
    } on Object catch (error, stack) {
      failure = error;
      failureStack = stack;
    }
    await step('the input was not cancelled', () => _input?.cancel());
    if (!_suspended) {
      await step('the screen was not left', () async {
        await _writeCommits();
        if (_plain) {
          if (!screen.presenter.inline || !clearInlineOnExit) {
            _writeLines(screen.surface, 0, screen.height, last: true);
          }
        } else {
          final leave = framesInRow
              ? null
              : screen.leave(
                  clear: clearInlineOnExit && screen.presenter.inline,
                );
          if (leave != null) {
            terminal.write(leave);
          }
        }
      });
    }
    await step('the terminal was not closed', terminal.close);
    if (serving != null) {
      await step('the log was not closed', () async {
        await serving;
        await logs.close();
      });
    }
    _report();
    if (failure case final error?) {
      Error.throwWithStackTrace(error, failureStack!);
    }
  }

  /// Adds a record of [error] to [logs], which may fail itself.
  void _log(String message, Object error, StackTrace stack) {
    try {
      logs.add(
        LogRecord(
          DateTime.now(),
          LogLevel.error,
          message,
          error: error,
          stack: stack,
        ),
      );
    } on Object {
      // a failing sink is not to end the run before the rest is done
    }
  }

  /// Serves [logs] for `twk logs` ([serveLogs]); what fails is a warning.
  Future<void> _serveLogs() async {
    try {
      await logs.serve();
    } on Object catch (error) {
      logs.add(
        LogRecord(
          DateTime.now(),
          LogLevel.warning,
          'the log is not served for twk logs',
          error: error,
        ),
      );
    }
  }

  /// Ends [run]: no frame starts after it, and [run] completes once the
  /// terminal is handed back. Calling it again does nothing.
  void quit() {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  /// A default color or palette entry the terminal reported (OSC 10, 11
  /// or 4, asked again after its color scheme changed) is what colors with
  /// alpha are blended with from then on: everything is repainted, unless
  /// it is the color known already.
  void _setDefaultColor(ColorReport e) {
    final styles = screen.styles;
    switch (e.which) {
      case 10 when e.rgb != styles.defaultForegroundRgb:
        styles.defaultForegroundRgb = e.rgb;
      case 11 when e.rgb != styles.defaultBackgroundRgb:
        styles.defaultBackgroundRgb = e.rgb;
      case 4 when e.rgb != styles.paletteRgb(e.index):
        styles.setPaletteRgb(e.index, e.rgb);
      default:
        return;
    }
    owner.markAllDirty();
    requestFrame();
  }

  /// The terminal is handed to another program ([suspend]): frames wait.
  var _suspended = false;

  /// Hands the terminal to another program while [run] runs (`$EDITOR`, a
  /// pager, a shell started with `ProcessStartMode.inheritStdio`) and
  /// takes it back when [run] completes; returns what [run] returns, or
  /// throws what it throws, once the terminal is back.
  ///
  /// Frames wait meanwhile. The terminal goes back as it was before the
  /// app took it (see [Terminal.suspend]); in the inline mode the region
  /// stays on the screen with the cursor on the line below it, as when
  /// [run] ends. Taken back, all of the screen is repainted, the inline
  /// region from a fresh start below whatever the other program printed.
  /// On a backend that isn't a [SuspendableBackend] only the frames wait.
  /// Throws [StateError] while the terminal is handed over.
  Future<T> suspend<T>(Future<T> Function() run) async {
    if (_suspended) {
      throw StateError('the terminal is already handed over');
    }
    _suspended = true;
    final term = terminal;
    try {
      final park = framesInRow || _plain ? null : screen.leave();
      if (park != null) {
        term.write(park);
      }
      if (term is SuspendableBackend) {
        await term.suspend();
      }
      return await run();
    } finally {
      // after quit() the terminal is being closed: it stays handed over
      if (!_done.isCompleted) {
        if (term is SuspendableBackend) {
          try {
            await term.resume();
          } on Object catch (error, stack) {
            // the terminal not taken back, the app can't go on, also when
            // what called this catches the error: it ends with it
            _fail(error, stack);
            rethrow;
          }
        }
        final presenter = screen.presenter;
        if (presenter.inline) {
          // the cursor is where the region starts again: its first row
          presenter.leave(clear: true);
        }
        presenter.invalidate();
      }
      _suspended = false;
      requestFrame();
    }
  }

  /// What Ctrl+Z does with terminal-generated signals on (here it is a
  /// key): the shell the app was started from has the terminal until it
  /// continues the app (`fg`), see [Terminal.stopForShell]; then the app
  /// takes it back as after [suspend]. POSIX only: throws
  /// [UnsupportedError] on Windows.
  Future<void> suspendToShell() {
    if (isWindows) {
      throw UnsupportedError('no job control on Windows');
    }
    return suspend(Terminal.stopForShell);
  }

  /// Inline mode: [content] goes to the terminal's history, above the
  /// region, as lines of the terminal's own: never repainted, scrolled and
  /// selected by the terminal like anything printed (finished messages, a
  /// log, results). When its turn comes it is
  /// laid out at the terminal's width, as tall as its max intrinsic height
  /// there (a [RenderParagraph] has its lines wrapped at that width),
  /// painted, and its rows are written by the next frames, in the order of
  /// the commits and in the synchronized update of the region's frame (see
  /// [Screen.commit]). A frame writes at most 256 committed rows, so a
  /// burst of them holds neither input nor the region up; what is still
  /// waiting when [run] ends is written before the region is left.
  ///
  /// [content] is an object of its own, not one in the tree, and it is
  /// detached once its rows are written. A resize while they are being
  /// written cuts or pads the rest to the new width. Throws [StateError]
  /// in the fullscreen mode and in a [viewport].
  ///
  /// What its sizing, layout or paint throws ends [run], unless [owner]
  /// has [PipelineOwner.onError]: then it is reported there once, as
  /// [content]'s, in the phase it threw in (sizing is [RenderPhase.layout]),
  /// and a [RenderErrorBox] with its message, at the terminal's width and
  /// as tall as the message there, goes to the history in its place.
  void commit(RenderObject content) {
    if (!screen.presenter.inline) {
      throw StateError('only the inline mode commits to the history');
    }
    _commits.add(content);
    if (_running) {
      requestFrame();
    }
  }

  /// Inline mode: hands a frame's worth of committed rows to the screen,
  /// oldest first, laying out and painting each commit when its turn
  /// comes ([_paintCommit]).
  void _takeCommits() {
    screen.presenter.screenHeight = terminal.height;
    final surface = _commitSurface;
    var left = _commitRowsPerFrame;
    while (left > 0) {
      var content = _committing;
      if (content == null) {
        if (_commits.isEmpty) {
          return;
        }
        content = _committing = _paintCommit(_commits.removeFirst());
        _commitRow = 0;
      }
      final rest = surface.height - _commitRow;
      final n = rest < left ? rest : left;
      if (_plain) {
        _writeLines(surface, _commitRow, _commitRow + n);
      } else {
        screen.commit(surface, _commitRow, _commitRow + n);
        if (framesInRow) {
          _textRows(surface, _commitRow, _commitRow + n);
        }
      }
      _commitRow += n;
      left -= n;
      if (_commitRow == surface.height) {
        content.detach();
        _committing = null;
      }
    }
  }

  /// Inline mode: lays [content] out at the screen's width, as tall as its
  /// max intrinsic height there, and paints it on [_commitSurface]; returns
  /// what was painted. What that throws goes to [owner]'s
  /// [PipelineOwner.onError] as [content]'s, in the phase it threw in, and
  /// a [RenderErrorBox] with its message is painted in its place; without
  /// onError it is thrown.
  RenderObject _paintCommit(RenderObject content) {
    final w = screen.width;
    var phase = RenderPhase.layout;
    try {
      final h = _layOutCommit(content, w);
      phase = RenderPhase.paint;
      _paintCommitted(w, h);
      return content;
    } on Object catch (error, stack) {
      final report = owner.onError;
      if (report == null) {
        rethrow;
      }
      report(content, phase, error, stack);
      final box = RenderErrorBox('$error');
      _paintCommitted(w, _layOutCommit(box, w));
      return box;
    }
  }

  /// Inline mode: lays [content] out at [w] columns, as tall as its max
  /// intrinsic height there, which is returned.
  int _layOutCommit(RenderObject content, int w) {
    _commitOwner
      ..textOrder = owner.textOrder
      ..root = content;
    final h = content.getMaxIntrinsicHeight(w);
    _commitOwner.flushLayout(w, h);
    return h;
  }

  /// Inline mode: paints the commit laid out at [w] × [h] on
  /// [_commitSurface].
  void _paintCommitted(int w, int h) {
    _commitSurface
      ..resize(w, h)
      ..clear();
    _commitOwner.flushPaint(_commitCtx);
  }

  /// Writes what is committed and not written yet, a frame's worth at a
  /// time, as [run] ends; an error is recorded, not thrown, so that the
  /// terminal is still handed back.
  Future<void> _writeCommits() async {
    try {
      while (_committing != null || _commits.isNotEmpty) {
        _takeCommits();
        final bytes = screen.render();
        if (bytes != null) {
          _write(bytes);
        }
        if (bytes != null || _plain) {
          await terminal.flush();
        }
      }
    } on Object catch (e, s) {
      _fail(e, s);
    }
  }

  static void _noFrame() {}

  /// Writes a frame's [bytes], or with [framesInRow] the frame as text;
  /// nothing on plain output.
  void _write(Uint8List bytes) {
    if (framesInRow) {
      _writeInRow(bytes.length);
    } else if (!_plain) {
      terminal.write(bytes);
    }
  }

  /// Plain output: writes rows [from, to) of [surface] as lines of text
  /// ([_textRows]); for the [last] frame without the blank lines that end
  /// them.
  void _writeLines(Surface surface, int from, int to, {bool last = false}) {
    final rows = _rows ??= ByteSink();
    _textRows(surface, from, to);
    final text = rows.view;
    var n = text.length;
    while (last &&
        n > 0 &&
        text[n - 1] == 0x0a &&
        (n == 1 || text[n - 2] == 0x0a)) {
      n--;
    }
    if (n > 0) {
      terminal.write(Uint8List.sublistView(text, 0, n));
    }
    rows.reset();
  }

  /// Writes the screen below the last frame written, after what
  /// [_textRows] held back (see [framesInRow]); [bytes] is what the frame
  /// took in place.
  void _writeInRow(int bytes) {
    final out = BytesBuilder(copy: false);
    if (_rowFrames++ == 0) {
      if (terminal.info.alternateScreen) {
        out.add(const [0x1b, 0x5b, 0x48]); // CSI H
      } else if (terminal.info.cursorColumn != 0) {
        out.add(const [0x0d, 0x0a]);
      }
    }
    final rows = _rows ??= ByteSink();
    var name = '--- frame $_rowFrames ($bytes bytes) ---';
    if (name.length > screen.width) {
      name = name.substring(0, screen.width).trimRight();
    }
    out
      ..add(rows.takeCopy())
      ..add(ascii.encode(name))
      ..add(const [0x0d, 0x0a]);
    rows.reset();
    _textRows(screen.surface, 0, screen.height);
    out.add(rows.takeCopy());
    rows.reset();
    terminal.write(out.takeBytes());
  }

  /// Rows [from, to) of [surface] as text lines, held back for the next
  /// frame in a row: a wide glyph once, the blanks that end a row left
  /// out, each ending in CR LF; in LF on plain output, for [_writeLines].
  void _textRows(Surface surface, int from, int to) {
    final lines = _lines ??= LineEncoder(
      screen.styles,
      ansi: false,
      out: _rows ??= ByteSink(),
    );
    final out = lines.out;
    final glyphs = screen.glyphs;
    for (var y = from; y < to; y++) {
      lines.row(surface, glyphs, y);
      if (!_plain) {
        out.byte(0x0d);
      }
      out.byte(0x0a);
    }
  }

  /// Starts a [timeline] slice.
  @pragma('vm:prefer-inline')
  void _begin(String name) {
    if (timeline) {
      Timeline.startSync(name);
      _slices++;
    }
  }

  /// Finishes the last [timeline] slice started.
  @pragma('vm:prefer-inline')
  void _end() {
    if (timeline) {
      Timeline.finishSync();
      _slices--;
    }
  }

  /// Inline mode: the next frame sizes the region to its content even when
  /// that is less than it has. By itself it only grows, so content that
  /// comes and goes (a spinner line, a hint) doesn't make it jump.
  void shrinkRegion() {
    _shrink = true;
    requestFrame();
  }

  /// Fixed viewport: a button pressed in it is held (see [_inViewport]).
  var _held = false;

  /// Fixed viewport: the width and height of the part of [viewport] a
  /// screen of [width] x [height] cells has; on plain output all of it.
  (int, int) _viewportSize(int width, int height) {
    final v = viewport!;
    if (_plain) {
      return (v.width, v.height);
    }
    final cols = width - v.left;
    final rows = height - v.top;
    return (
      v.width < cols ? v.width : (cols > 0 ? cols : 0),
      v.height < rows ? v.height : (rows > 0 ? rows : 0),
    );
  }

  /// Fixed viewport: [e] with its cell counted from the viewport's first,
  /// or null when it is outside the viewport, to drop. While a button
  /// pressed in it is held, a drag or a release outside it goes to its
  /// nearest cell instead; a release ends the hold.
  MouseEvent? _inViewport(MouseEvent e) {
    final v = viewport!;
    final w = screen.width;
    final h = screen.height;
    final kind = e.kind;
    var x = e.x - v.left;
    var y = e.y - v.top;
    if (x < 0 || y < 0 || x >= w || y >= h) {
      if (!_held ||
          (kind != MouseKind.drag && kind != MouseKind.up) ||
          w == 0 ||
          h == 0) {
        return null;
      }
      x = x < 0 ? 0 : (x < w ? x : w - 1);
      y = y < 0 ? 0 : (y < h ? y : h - 1);
    }
    if (kind == MouseKind.down) {
      _held = true;
    } else if (kind == MouseKind.up) {
      _held = false;
    }
    return MouseEvent(kind, x, y, button: e.button, modifiers: e.modifiers);
  }

  /// Inline mode: the most rows the region may have now.
  int get _regionLimit {
    final max = maxInlineRows;
    final h = terminal.height;
    return max != null && max < h ? max : h;
  }

  /// Inline mode: makes the region as tall as the root asks to be at the
  /// screen's width, within its limits (see [TwkApp]). When asking throws,
  /// the region keeps its height within them and a shrink asked for waits
  /// ([_sizingFailed]).
  void _sizeRegion() {
    final h = screen.height;
    var shrink = false;
    int n;
    try {
      n = owner.root.getMaxIntrinsicHeight(screen.width);
      _sizeError = null;
      shrink = _shrink;
      _shrink = false;
    } on Object catch (error, stack) {
      _sizingFailed(error, stack);
      n = h;
    }
    final limit = _regionLimit;
    if (n < 1) {
      n = 1;
    }
    if (n > limit) {
      n = limit;
    }
    if (n > h || (n < h && (shrink || h > limit))) {
      screen.resizeRegion(n);
      owner.markAllDirty();
    }
  }

  /// Inline mode: the message of what sizing the region threw last; null
  /// once it is sized without an error.
  String? _sizeError;

  /// Inline mode: the root's max intrinsic height threw [error] while the
  /// region was sized. It goes to [PipelineOwner.onError] as the root's, in
  /// [RenderPhase.layout], unless the last sizing threw the same; without
  /// onError it is thrown.
  void _sizingFailed(Object error, StackTrace stack) {
    final report = owner.onError;
    if (report == null) {
      Error.throwWithStackTrace(error, stack);
    }
    final message = '$error';
    if (message != _sizeError) {
      _sizeError = message;
      report(owner.root, RenderPhase.layout, error, stack);
    }
  }

  void _print(Zone self, ZoneDelegate parent, Zone zone, String line) =>
      logs.add(LogRecord(DateTime.now(), LogLevel.info, line));

  void _fail(Object error, StackTrace stack) {
    final record = LogRecord(
      DateTime.now(),
      LogLevel.error,
      'uncaught error',
      error: error,
      stack: stack,
    );
    if (!_done.isCompleted) {
      _ending = record;
      _done.completeError(error, stack);
    }
    try {
      logs.add(record);
    } on Object {
      // a failing sink (its file, a listener) would end the process here,
      // before the terminal is restored
    }
  }

  void _report() {
    for (final r in logs.records) {
      if (r.level.index >= LogLevel.warning.index && !identical(r, _ending)) {
        printError(r);
      }
    }
  }

  /// What the render tree's marks ask for: a frame, unless one runs, which
  /// looks for work left when it ends.
  void _needFrame() {
    if (!_inFrame) {
      requestFrame();
    }
  }

  /// Schedules a frame, as soon as [maxFps] allows; frames requested
  /// together are one.
  ///
  /// Requested while a frame runs, another follows it. The render tree's
  /// marks ([RenderObject.markNeedsLayout] and the like) request frames by
  /// themselves; this is for what changes outside the tree.
  void requestFrame() {
    if (_inFrame) {
      _again = true;
      return;
    }
    if (_scheduled) {
      return;
    }
    _scheduled = true;
    final minGap = 1000000 ~/ maxFps;
    final wait = _lastFrameAt + minGap - clock.elapsedMicroseconds;
    // frames run in the app's zone even when requested from outside it
    _zone.createTimer(
      wait > 0 ? Duration(microseconds: wait) : Duration.zero,
      _runFrame,
    );
  }

  Future<void> _frame() async {
    _scheduled = false;
    if (_done.isCompleted || _suspended) {
      return;
    }
    _inFrame = true;
    try {
      _lastFrameAt = clock.elapsedMicroseconds;
      final t0 = _statsClock.elapsedMicroseconds;
      _begin('Frame');
      _begin('Build');
      _beforeLayout?.call();
      _end();
      final input = _input;
      if (input != null && input.isPaused) {
        // what came before the first frame goes to what it built
        input.resume();
      }
      final built = _statsClock.elapsedMicroseconds;
      _begin('Layout');
      if (screen.presenter.inline) {
        _sizeRegion();
      }
      owner.flushLayout(screen.width, screen.height);
      _end();
      final laidOut = _statsClock.elapsedMicroseconds;
      final repaints = owner.dirtyBoundaries;
      _begin('Paint');
      owner.flushPaint(_ctx);
      _end();
      if (_committing != null || _commits.isNotEmpty) {
        _begin('Commit');
        _takeCommits();
        _end();
      }
      _beforePresent?.call();
      final painted = _statsClock.elapsedMicroseconds;
      _begin('Present');
      final bytes = screen.render();
      final t1 = _statsClock.elapsedMicroseconds;
      stats
        ..lastMicros = t1 - t0
        ..totalMicros += t1 - t0
        ..lastBuildMicros = built - t0
        ..lastLayoutMicros = laidOut - built
        ..lastPaintMicros = painted - laidOut
        ..lastPresentMicros = t1 - painted
        ..lastRepaints = repaints
        ..lastBytes = bytes?.length ?? 0;
      if (bytes != null) {
        stats._record(t1 - t0);
        stats.frames++;
        stats.bytes += bytes.length;
        _write(bytes);
      }
      _end();
      _begin('Finalize');
      _afterPresent?.call();
      _end();
      _end();
      if (bytes != null || _plain) {
        await terminal.flush();
      }
    } finally {
      _inFrame = false;
      // slices an error cut short end here: none may outlive the frame
      while (_slices > 0) {
        Timeline.finishSync();
        _slices--;
      }
    }
    if (_again || owner.hasWork || _committing != null || _commits.isNotEmpty) {
      _again = false;
      requestFrame();
    }
  }
}
