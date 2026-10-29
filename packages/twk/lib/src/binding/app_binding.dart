/// Running a widget tree as an app: [runApp] and the [AppBinding] between
/// the tree and the core's `TwkApp`, which routes the keys through the
/// focus tree and the mouse by hit test, the [InputListener]s the rest of
/// the input goes to, the [WidgetError] a fatal error in a widget's code
/// ends it with, and the app's [DebugAids] and service extensions, which
/// tools inspect and hot reload it by.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer show extensionStreamHasListener, postEvent;
import 'dart:developer'
    show ServiceExtensionHandler, ServiceExtensionResponse, registerExtension;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Attr,
        BidiReordering,
        BoxConstraints,
        Brightness,
        ClusterScan,
        Color,
        ColorReport,
        ColorSchemeReport,
        CursorShape,
        HeadlessTerminal,
        InputEvent,
        KeyCode,
        KeyEvent,
        KeyKind,
        LogLevel,
        LogRecord,
        LogSink,
        Mod,
        MouseEvent,
        MouseKind,
        MouseTracking,
        MouseTrackingBackend,
        PaintContext,
        Pen,
        PipelineTextOrder,
        RenderObject,
        RenderObjectWithChildMixin,
        RenderPhase,
        Terminal,
        TerminalBackend,
        TerminalOptions,
        TextOrder,
        TextSegmenter,
        TwkApp,
        Viewport,
        WindowBackend,
        log;

import '../debug/console.dart';
import '../debug/editor.dart';
import '../debug/frame_overlay.dart';
import '../debug/inspector.dart';
import '../debug/key_hint.dart';
import '../editing/caret.dart' show restingCell;
import '../focus/focus.dart';
import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../layout/one_child.dart';
import '../platform/platform.dart'
    show environment, processId, runOnTerminal, startApart, tempFile;
import '../semantics/semantics.dart';
import '../style/theme.dart';
import 'error_widget.dart';
import 'source_excerpt.dart';
import 'terminal_status.dart' show TerminalStatus;

// Examples can assume:
// late BuildContext context;
// late ValueNotifier<(int, int)> size;
// final class Counter extends StatelessWidget {
//   const Counter({super.key});
//   @override
//   Widget build(BuildContext context) => const Text('0');
// }

/// Where an app draws: the whole terminal or a region of its normal
/// screen.
enum ScreenMode {
  /// The alternate screen, all of it at the terminal's size; what the
  /// terminal showed before comes back when the app ends.
  fullscreen,

  /// A region of the normal screen from the line the cursor is on down, as
  /// tall as the app asks to be; it stays in the terminal's history when
  /// the app ends (see `TwkApp`).
  inline,
}

/// What [AppBinding.scheduleFrameCallback] calls: [time] is the frame's on
/// the app's clock ([AppBinding.frameTime]).
typedef FrameCallback = void Function(Duration time);

/// Whether the program runs in product mode, as `dart compile exe`
/// compiles it, without a VM service.
// ignore: do_not_use_environment, the VM's own, not one an app is built with
const _product = bool.fromEnvironment('dart.vm.product');

/// Runs [app] in [mode] on the process's terminal, or on [terminal], which
/// has to be in that mode (an [ArgumentError] if not), until the app quits
/// ([AppBinding.quit]); see [AppBinding] for the rest. With [screenReader]
/// (by default whether `TWK_SCREEN_READER` is 1) the app is read out as
/// lines of text ([AppBinding.screenReader]), on the process's terminal on
/// the normal screen whatever [mode] says: inline, or in [viewport]. Null,
/// the default, it is the binding's to say ([AppBinding.new]), as the
/// terminal's settings may set it (`TerminalInfo.settings`); the screen is
/// chosen before the terminal is opened, by the process's environment, so
/// a terminal that turns it on has the app read out on the alternate
/// screen, and one that turns it off for a process that asked for it has
/// a full-screen app drawn on the normal screen.
///
/// With [viewport] the app draws in that rectangle of the screen [mode]
/// puts it on instead, the normal one for [ScreenMode.inline], and writes
/// nothing outside it (the core's `TwkApp.viewport`): beside a shell's
/// output, a status panel in a corner. The process's terminal is opened
/// to report the mouse on the normal screen too
/// (`TerminalOptions.normalScreenMouse`), the events relative to the
/// rectangle; a given [terminal] reports it there only where it was
/// opened so.
///
/// [bidi] says who puts right-to-left text in the order it reads, the app
/// or the terminal (`TerminalOptions.bidi`, [AppBinding.textOrder]); null,
/// the default, for what the process's terminal is found to do. A given
/// [terminal] has to be ordered so (an [ArgumentError] if not).
///
/// [maxFps] frames a second at most, 60 by default; [maxInlineRows] the
/// most rows the inline region grows to, null for the terminal's height,
/// and [clearInlineOnExit] clears the region when the app ends instead of
/// leaving it in the history; [logs] is where `log()` and `print` go (the
/// core's `TwkApp.logs`); [exitOnCtrlC] is [AppBinding.exitOnCtrlC].
/// [clock] is the app's clock, which spaces its frames (`TwkApp.clock`),
/// a stopwatch started here by default: a test hands it the stopwatch of
/// a fake clock it moves, and runs the app in that clock's zone.
///
/// ```dart
/// Future<void> main() => runApp(const Counter());
/// ```
///
/// Inline, below the shell's prompt, as a prompt or a progress display
/// is:
///
/// ```dart
/// Future<void> main() => runApp(const Counter(), mode: ScreenMode.inline);
/// ```
Future<void> runApp(
  Widget app, {
  ScreenMode mode = ScreenMode.fullscreen,
  Viewport? viewport,
  TerminalBackend? terminal,
  int maxFps = 60,
  int? maxInlineRows,
  bool clearInlineOnExit = false,
  LogSink? logs,
  bool exitOnCtrlC = true,
  bool? screenReader,
  BidiReordering? bidi,
  Stopwatch? clock,
}) async {
  final fullscreen = mode == ScreenMode.fullscreen;
  if (terminal != null && terminal.info.alternateScreen != fullscreen) {
    throw ArgumentError.value(
      terminal,
      'terminal',
      'not in the ${mode.name} mode',
    );
  }
  if (terminal != null && bidi != null && terminal.info.bidi != bidi) {
    throw ArgumentError.value(
      terminal,
      'terminal',
      'not ordered by the ${bidi.name}',
    );
  }
  final reader = screenReader ?? AppBinding._readerAsked(environment);
  final term =
      terminal ??
      await Terminal.open(
        TerminalOptions(
          alternateScreen: fullscreen && !reader,
          mouse: false,
          normalScreenMouse: viewport != null,
          bidi: bidi,
        ),
      );
  await AppBinding(
    term,
    viewport: viewport,
    maxFps: maxFps,
    maxInlineRows: maxInlineRows,
    clearInlineOnExit: clearInlineOnExit,
    logs: logs,
    exitOnCtrlC: exitOnCtrlC,
    clock: clock,
    screenReader: screenReader,
  ).run(app);
}

/// A widget tree run as an app on a terminal by a `TwkApp` ([twkApp]),
/// whose options are the constructor's: the tree is built, laid out,
/// painted and written by its frames, in its zone, so `print` and `log()`
/// in a build go to its log sink.
///
/// Each frame starts with the frame callbacks due ([scheduleFrameCallback]:
/// the ticks of the app's animations, at the frame's time, [frameTime]),
/// then a build of what changed since the frame before, what they changed
/// included, which it then lays out: any number of `setState` calls
/// between two frames make one build, and there are at most `maxFps`
/// builds a second. While no callback waits and nothing changes, the
/// binding asks for no frame and starts no timer.
/// The focus nodes whose focus changed since are told first, and again
/// after the build when it moved the focus (an autofocus, a focused widget
/// removed), which is built in the same frame ([FocusManager.flush]).
/// What the frame's builds removed, in the layout ([LayoutBuilder]) too,
/// is unmounted once the frame is written, its states disposed. The first
/// frame mounts the app; input waits for it. A build that throws
/// shows an [ErrorWidget] in place of what the widget builds, logs the
/// error at [LogLevel.error] with the widget's path in the tree and its
/// stack, and the app goes on; so does what a widget's child throws as it
/// is created or updated (see [BuildOwner.onBuildError]). A render object
/// whose layout or paint throws shows the message in white on red in its
/// place, and the error is logged with the path of its widget, once while
/// it throws the same one. An error that ends the app, which [run]
/// completes with once the terminal is restored, is a [WidgetError] when
/// the code of a widget threw it ([InputListener.onEvent]).
///
/// The app is under a [TerminalBrightness]: the brightness of the
/// terminal's background (`TerminalInfo.brightness`, dark when not known)
/// at first, that of each [ColorSchemeReport] from then on.
///
/// The app is under the [FocusManager.rootScope] of its [focusManager]. A
/// key goes first to the [debug] aids, which take the debug keys while
/// debugging is on ([DebugAids]). Then it goes to the nodes of the
/// [FocusManager.keyPath] in turn until one handles it
/// ([FocusNode.onKeyEvent]): the node with the primary focus and the nodes
/// above it, or, while no node has the focus or a scope has it itself, the
/// layers around the whole app or that scope (a `KeyBindings` around the
/// app); as many calls as there are [Focus] and [FocusScope] widgets on
/// the path, the widget tree itself not walked. A key none of them
/// handles, and every other event, goes to the [InputListener]s. Tab and
/// Shift+Tab that none of those takes move the focus to the next or the
/// previous node of its scope ([FocusNode.nextFocus]); Ctrl+C that none
/// takes quits, unless [exitOnCtrlC] is false.
///
/// A mouse event goes to the [Listener]s and [MouseRegion]s a hit test of
/// the last frame finds at its cell (see both), then, when no [Listener]
/// took it, to the [InputListener]s. The binding has the terminal report
/// the mouse as the [Listener]s and [MouseRegion]s mounted need it, from
/// the frame that mounts the first of them to the one that unmounts the
/// last, and no more ([MouseTrackingBackend.mouseTracking]), whatever the
/// terminal was opened with: an app that uses no mouse leaves the
/// terminal's selection and wheel working, but while a tool picks a node
/// on its screen ([DebugAids.select]).
///
/// With a `viewport` the app is laid out at that rectangle of the screen
/// and drawn in it alone (`TwkApp.viewport`), as full screen at its size
/// whichever screen it is on: the debug panels over it, the items of a
/// `Static` in place, the mouse events relative to it.
///
/// Tools inspect the app over the VM service by the `ext.twk.*` service
/// extensions ([callServiceExtension]), registered by the first app run
/// in a program not compiled in product mode, and hot reload it by them
/// (`twk run`, [reassemble]).
///
/// With [screenReader] on, by default whether `TWK_SCREEN_READER` is 1, the
/// app is read out as lines of text instead (see [screenReader]).
///
/// A widget reaches the binding of its app with [AppBinding.of]: to quit,
/// to schedule work for the next frame, to notify:
///
/// ```dart
/// KeyBindings(
///   {'q': () => AppBinding.of(context).quit()},
///   child: const Text('q quits'),
/// )
/// ```
final class AppBinding {
  /// A binding of a `TwkApp` on [terminal], made with [viewport], [maxFps],
  /// [maxInlineRows], [clearInlineOnExit], [logs] and [clock] (the app's
  /// clock, a new stopwatch by default); [exitOnCtrlC] and [screenReader]
  /// are as [runApp] takes them. [run] runs an app on it.
  ///
  /// [environment] is what the app reads its variables from, null (the
  /// default) for the process's: given to its `TwkApp` (`TWK_LOG`,
  /// `TWK_DEBUG`'s `frames`, `timeline`, `logs`, `rainbow`, `relayout`),
  /// and here `TWK_SCREEN_READER` (when [screenReader] is null), the rest
  /// of `TWK_DEBUG` ([DebugAids]) and the editor's `TWK_EDITOR`, `VISUAL`
  /// and `EDITOR`, all of them from `TwkApp.environment`. Null, the
  /// terminal's settings (`TerminalInfo.settings`: `TWK_SCREEN_READER`
  /// and `TWK_DEBUG` of a terminal of the process's, such as an editor's
  /// `twk shell`) take the place of the process's values, so the terminal
  /// switches the screen reader and the debug aids; given, it is the
  /// whole of it. A test passes `const {}`, and turns a debug aid on
  /// through [debug] or [screenReader]; so does a server of apps to
  /// others, as twk_ssh's `serveSsh` does, whose clients are not to turn
  /// the server's debug aids on.
  AppBinding(
    TerminalBackend terminal, {
    Viewport? viewport,
    int maxFps = 60,
    int? maxInlineRows,
    bool clearInlineOnExit = false,
    LogSink? logs,
    this.exitOnCtrlC = true,
    Stopwatch? clock,
    bool? screenReader,
    Map<String, String>? environment,
  }) : twkApp = TwkApp(
         terminal,
         viewport: viewport,
         maxFps: maxFps,
         maxInlineRows: maxInlineRows,
         clearInlineOnExit: clearInlineOnExit,
         logs: logs,
         clock: clock,
         environment: environment,
       ),
       _screenReader = screenReader ?? false {
    if (screenReader == null) {
      _screenReader = _readerAsked(twkApp.environment);
    }
    twkApp.owner.onError = _renderFailed;
    debug = DebugAids._(this);
  }

  /// Whether `TWK_SCREEN_READER` in [environment] asks for the
  /// screen-reader mode.
  static bool _readerAsked(Map<String, String> environment) =>
      environment['TWK_SCREEN_READER'] == '1';

  /// The binding of the app [context] is in; a [StateError] if there is
  /// none.
  static AppBinding of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError(
        'no app above ${context.widget.runtimeType}: runApp runs one',
      ));

  /// The binding of the app [context] is in, if it is in one.
  static AppBinding? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_Scope>()?.binding;

  /// What runs the frames.
  final TwkApp twkApp;

  /// Ctrl+C that no focus node or [InputListener] takes quits.
  final bool exitOnCtrlC;

  /// The focus of the app: which node gets the keys first.
  late final focusManager = FocusManager(onFlushScheduled: _focusChanged);

  /// The debug aids: the frame overlay, the log console, the repaint
  /// rainbow and the relayout highlight, and the keys that turn them on.
  late final DebugAids debug;

  /// The screen mode of the terminal: with a viewport (`TwkApp.viewport`)
  /// the screen it is on.
  ScreenMode get mode => twkApp.terminal.info.alternateScreen
      ? ScreenMode.fullscreen
      : ScreenMode.inline;

  /// The order the app's text is drawn in (`PipelineOwner.textOrder`):
  /// [TextOrder.visual] where the app puts right-to-left text in the order
  /// it reads, [TextOrder.logical] where the terminal reorders it itself,
  /// as the terminal was opened with or found to need (`TerminalInfo.bidi`:
  /// visual for a terminal that does no bidi or was put in its explicit
  /// mode, logical for Konsole, mlterm, Terminal.app, PuTTY and plain
  /// output; [runApp]'s `bidi` chooses).
  TextOrder get textOrder => twkApp.owner.textOrder;

  /// Whether the app is read out as lines of text, for a screen reader,
  /// instead of drawn: no boxes, borders or columns, a line of plain text
  /// for each node of its [semantics] (`button OK`, `checkbox Remember me,
  /// checked`, see [SemanticsNode.lines]), from the top of the screen or
  /// the region, a line longer than the screen's width broken at a blank
  /// where it has one that fits. The focused node's line is in reverse
  /// video, the terminal's cursor at its end, or at the end of the last
  /// line when no node is focused. A frame whose build or layout changed
  /// the lines or moved the focus writes those that changed; a line is
  /// not written again while it stays the same. In the inline mode the
  /// region is as tall as the lines, within its limits; with more lines
  /// than it has rows, it shows those around the focused line. The app is
  /// laid out as it would be, as tall as the region would be in the inline
  /// mode, but not painted; the terminal keeps the mouse, and the debug
  /// panels are drawn over the lines as over the app.
  ///
  /// Set from the next frame on: turned off, the app is laid out and
  /// painted again, all of it.
  bool get screenReader => _screenReader;
  bool _screenReader;

  set screenReader(bool on) {
    if (on == _screenReader) {
      return;
    }
    _screenReader = on;
    if (!on) {
      // the view lays the app out and paints it again, all of it
      _view.read(null);
      twkApp.screen.presenter.cursorVisible = false;
    }
    _trackMouse();
    // the region fits what it shows now; this asks for a frame too
    twkApp.shrinkRegion();
  }

  /// The semantics of the app as its widgets are now, the primary focus's
  /// node focused ([SemanticsNode.of]); none before the first frame.
  SemanticsNode get semantics {
    final root = _root;
    return root == null
        ? const SemanticsNode()
        : SemanticsNode.of(root, focus: focusManager.primaryFocus);
  }

  /// Reads the app out for the frame ([screenReader]): lays it out first,
  /// so that what its layout builds (the items of a list) is read too.
  void _read() {
    final app = twkApp;
    final screen = app.screen;
    final info = app.terminal.info;
    final max = app.maxInlineRows;
    final rows = app.terminal.height;
    _view.appRows = app.viewport != null
        ? screen.height
        : info.alternateScreen || max == null || max > rows
        ? rows
        : max;
    app.owner.flushLayout(screen.width, screen.height);
    final semantics = this.semantics;
    final fewer = _view.read(
      semantics.lines,
      focused: semantics.focusedLine,
      width: screen.width,
      segmenter: app.owner.segmenter,
    );
    if (fewer) {
      app.shrinkRegion();
    }
  }

  // routes the mouse, and counts what it is to report
  late final _mouse = MouseTracker(twkApp.owner.hitTest, _mouseFailed);

  late final _owner = BuildOwner(
    onBuildScheduled: _scheduleBuild,
    onBuildError: _buildFailed,
  );

  // the root of the render tree, which the app's render objects go under
  late final _view = _RenderView(
    inline: mode == ScreenMode.inline && twkApp.viewport == null,
  );

  // the elements built so far, as of the end of the last frame, and in it
  var _rebuildsSeen = 0;
  var _rebuilt = 0;

  RootElement? _root;

  // what the first build mounts
  Widget? _first;

  // the next frame builds
  var _buildScheduled = false;

  // a build runs, which settles the focus when it is done
  var _building = false;

  // the listeners in the order they were mounted; while an event goes
  // through them ([_listenersShared]) a change replaces the list instead
  var _listeners = <_InputListenerState>[];
  var _listenersShared = false;

  /// [_listeners], to be changed.
  List<_InputListenerState> get _ownListeners {
    if (_listenersShared) {
      _listeners = List.of(_listeners);
      _listenersShared = false;
    }
    return _listeners;
  }

  // what the app is under, and what shows it
  // (COLORFGBG's guess where the terminal tells nothing, not known: it
  // picks the terminal theme's greys, never twk's own theme)
  late Brightness _brightness =
      twkApp.terminal.info.brightness ??
      twkApp.terminal.info.declaredBrightness ??
      Brightness.dark;

  // whether the terminal said what its background is
  late var _brightnessKnown = twkApp.terminal.info.brightness != null;

  // the default background and text color the terminal told, 0xRRGGBB
  late int? _background = twkApp.terminal.info.backgroundRgb;
  late int? _foreground = twkApp.terminal.info.foregroundRgb;

  // the entries of the 16 colors the terminal told, RGB by index; a new
  // map at each report, so that TerminalBrightness tells it changed
  late Map<int, int> _palette = twkApp.terminal.info.palette;
  _BrightnessState? _brightnessState;

  // what the debug panels are painted in
  ThemeData get _theme => switch (_background) {
    final background? => ThemeData.terminalOn(
      background,
      foreground: _foreground,
      palette: _palette,
    ),
    null => ThemeData.terminal(_brightness),
  };

  /// Runs [app] until [quit], then unmounts it: the states of its widgets
  /// are disposed, and the frame callbacks still waiting are dropped. An
  /// error that ends the app first unmounts it the same way, once the
  /// terminal is restored, and is then thrown; one a state's dispose
  /// throws meanwhile goes to the log of [twkApp] (`TwkApp.logs`), the
  /// first error being the one thrown.
  Future<void> run(Widget app) async {
    attachRootWidget(app);
    _zone = Zone.current;
    _running = true;
    _runningApps.add(this);
    if (!_registered) {
      _registered = true;
      registerServiceExtensions();
    }
    try {
      await twkApp.run(
        _view,
        _dispatch,
        beforeLayout: _beforeLayout,
        beforePresent: _beforePresent,
        afterPresent: _afterPresent,
      );
    } on Object {
      _ended();
      try {
        _unmount();
      } on Object catch (error, stack) {
        // outside the app's zone now: into its log by hand
        twkApp.logs.add(
          LogRecord(
            DateTime.now(),
            LogLevel.error,
            'a state failed to dispose as the app ended with an error',
            error: error,
            stack: stack,
          ),
        );
      }
      rethrow;
    }
    _ended();
    _unmount();
  }

  // run has ended, whichever way: no frame callback is called any more
  void _ended() {
    _running = false;
    _runningApps.remove(this);
    _callbacks.clear();
    _waitForDue();
    debug._dispose();
  }

  // the tree after run: unmounted, its states disposed
  void _unmount() {
    if (_root != null) {
      _show(null);
      _build();
      _owner.finalizeTree();
    }
  }

  /// Shows [app] in place of the app shown before from the next frame on:
  /// elements whose widgets match keep their state, as in any rebuild.
  void attachRootWidget(Widget app) {
    final scope = _Brightness(
      this,
      child: _mouse.scope(
        FocusScope(
          node: focusManager.rootScope,
          child: _Scope(this, child: app),
        ),
      ),
    );
    if (_root == null) {
      _first = scope;
      _buildScheduled = true;
    } else {
      _show(scope);
    }
  }

  /// Ends [run].
  void quit() => twkApp.quit();

  /// Shows a desktop notification of [title] and [body] where the terminal
  /// is known to show one (`TerminalInfo.notifications`), through tmux or
  /// screen: [WindowBackend.notify] of the terminal ([Terminal.notify], or
  /// [HeadlessTerminal.notify] in a test, or a backend that wraps one and
  /// passes it on). Does nothing on a backend that is no [WindowBackend].
  void notify(String title, String body) {
    if (twkApp.terminal case final WindowBackend terminal) {
      terminal.notify(title, body);
    }
  }

  /// Has the app take up its code as a hot reload changed it (`twk run`,
  /// `ext.twk.reassemble`): the next frame rebuilds every element, each
  /// state kept as in any rebuild, lays out and paints every render object
  /// again and writes all of the screen again.
  void reassemble() {
    void rebuild(Element e) {
      e
        ..markNeedsBuild()
        ..visitChildren(rebuild);
    }

    void relayout(RenderObject o) {
      o
        ..markNeedsLayout()
        ..visitChildren(relayout);
    }

    final root = _root;
    if (root != null) {
      rebuild(root);
    }
    // each object laid out repaints
    relayout(_view);
    twkApp.screen.presenter.invalidate();
  }

  /// The service extensions the app answers ([callServiceExtension]).
  static const serviceExtensions = [
    'ext.twk.tree',
    'ext.twk.properties',
    'ext.twk.layout',
    'ext.twk.select',
    'ext.twk.highlight',
    'ext.twk.flags',
    'ext.twk.reassemble',
    'ext.twk.log',
  ];

  /// The version of the shape of what [callServiceExtension] answers: an
  /// answer that a client reading this one would misread comes with
  /// another.
  static const int serviceExtensionsVersion = Inspector.version;

  /// Answers the service extension [method], one of [serviceExtensions],
  /// called with [parameters] (strings, as the VM service passes them),
  /// about this app: a JSON object whose `version` is
  /// [serviceExtensionsVersion]. Or an error whose details are a JSON
  /// object with a `message`: [ServiceExtensionResponse.invalidParams] for
  /// a parameter missing or malformed,
  /// [ServiceExtensionResponse.extensionError] for an id that names no
  /// node of the app.
  ///
  /// A node of the trees, an element or a render object, is named by its
  /// id: a positive int given to it the first time an answer names it, and
  /// kept by it while it is in the tree, an element through its rebuilds;
  /// one sequence for both kinds, never given twice in a run.
  ///
  /// * `ext.twk.tree`: the element tree, or with `tree=render` the render
  ///   tree, from its root: `tree` (`element` or `render`), `root` (null
  ///   before the first frame) and, in the element tree, `app`, the id of
  ///   the element of the app's widget, below the binding's own. A node,
  ///   as [Element.describe] and `RenderObject.describe` describe it:
  ///   `id`; `name`, the type of its widget or render object; `key`, if
  ///   any; `properties`, each a `value` after its `name`, if any; `size`
  ///   (`width`, `height`) once laid out; `flags`, by [DiagnosticsFlag]
  ///   name; an element's `render`, the id of its render object or of the
  ///   nearest below it, a render object's `element`, the id of the element
  ///   whose it is, if any; an element's `build`, the type whose `build`
  ///   method makes its child, for that of a [StatelessWidget] (the
  ///   widget's type) or of a [StatefulWidget] (its [State]'s): what a
  ///   tool looks for in the app's code to find where a widget was made,
  ///   as twk keeps no creation locations (its widgets' constructors are
  ///   `const`, and run no code); and `children`.
  /// * `ext.twk.properties`, `id`: that node as the tree has it, without
  ///   `children`.
  /// * `ext.twk.layout`, `id`: the layout of its render object, an
  ///   element's as in the tree: `id`, `render` and `name`, its type; once
  ///   laid out, its `constraints` (`minWidth`, `maxWidth`, `minHeight`,
  ///   `maxHeight`, null for no limit) and `size`; `offset` (`x`, `y`) in
  ///   its parent and `global`, on the screen (of the inline region).
  /// * `ext.twk.select`, `x`, `y`: what is at that cell of the screen (of
  ///   the inline region) by a hit test of the last frame: `id`, the
  ///   deepest element whose render object is hit there, null for none;
  ///   `path`, the ids of the elements from the root down to it; `render`,
  ///   those of the render objects hit, the deepest first. With `cursorY`,
  ///   the row of the terminal's cursor in the rows `y` counts, `y` is a
  ///   row of the terminal's screen, for a tool that sees that screen but
  ///   not where the inline region is on it: the row that far from the
  ///   cursor's in the region (`Presenter.cursorRow`), or `y` itself where
  ///   the app does not know where its cursor is.
  /// * `ext.twk.highlight`, `id`: has the render object of that node, as
  ///   in `ext.twk.layout`, outlined ([DebugAids.highlight]), or, without
  ///   `id`, none: `id`, null for none, and `render`.
  /// * `ext.twk.flags`: the debug aids ([DebugAids]) `overlay`, `console`
  ///   (open), `rainbow`, `relayout`, `keys`, `select` (a pick of a node
  ///   on the screen, whose cell comes as the event `twk.select`),
  ///   `selectMany` (the pick going on after a cell picked,
  ///   [DebugAids.selectMany]) and `treeEvents` (the event
  ///   `twk.treeChanged` after each frame that built,
  ///   [DebugAids.treeEvents]), and `framesInRow` (`TwkApp.framesInRow`,
  ///   which the app is built with), each true or false; any of the first
  ///   eight passed as a parameter, `true` or `false`, is set first.
  /// * `ext.twk.reassemble`: [reassemble]s the app, after a hot reload of
  ///   its code; nothing else.
  /// * `ext.twk.log`, `message`, `level` (`debug`, `info`, the default,
  ///   `warning` or `error`) and `error`, if any: adds that record to the
  ///   app's log (`TwkApp.logs`), where a tool that runs the app says what
  ///   it did (`twk run`), the console ([DebugAids.console]) opening on an
  ///   error; nothing else.
  Future<ServiceExtensionResponse> callServiceExtension(
    String method,
    Map<String, String> parameters,
  ) async {
    try {
      final answer = _answer(method, parameters);
      return ServiceExtensionResponse.result(
        jsonEncode({'version': serviceExtensionsVersion, ...answer}),
      );
    } on _ExtensionError catch (e) {
      return e.response;
    }
  }

  /// Registers [serviceExtensions] with [register], each answering about
  /// the app that started last of those running ([callServiceExtension]),
  /// or with an error while none runs; none in [product] mode, which a
  /// program compiled by `dart compile exe` runs in, without a VM service.
  /// The first app [run] in an isolate calls it.
  @visibleForTesting
  static void registerServiceExtensions({
    bool product = _product,
    void Function(String method, ServiceExtensionHandler handler) register =
        registerExtension,
  }) {
    if (product) {
      return;
    }
    // whatever zone the app runs in, the answers go out from the root
    Zone.root.run(() {
      for (final name in serviceExtensions) {
        register(name, _answerLast);
      }
    });
  }

  /// Posts an event of the kind given, with the data given, on the VM
  /// service's `Extension` stream, for a tool: `twk.reload` and
  /// `twk.restart` for the one that runs the app (`twk run`), `twk.select`
  /// for the one that picks a node ([DebugAids.select]), `twk.treeChanged`
  /// for one that follows the tree ([DebugAids.treeEvents]); false, posting
  /// nothing, while no client listens to that stream, as in product mode.
  /// What the hot reload keys call ([DebugAids]).
  @visibleForTesting
  static bool Function(String kind, [Map<String, Object?> data]) postEvent =
      _postEvent;

  static bool _postEvent(
    String kind, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) {
    if (!developer.extensionStreamHasListener) {
      return false;
    }
    developer.postEvent(kind, data);
    return true;
  }

  // the apps running, the one started last last; the extensions are
  // registered in this isolate
  static final _runningApps = <AppBinding>[];
  static var _registered = false;

  static Future<ServiceExtensionResponse> _answerLast(
    String method,
    Map<String, String> parameters,
  ) async {
    if (_runningApps.isEmpty) {
      return const _ExtensionError.gone('no app runs').response;
    }
    return _runningApps.last.callServiceExtension(method, parameters);
  }

  late final _inspector = Inspector(
    root: () => _root,
    app: _appElement,
    hitTest: (result, x, y) => twkApp.owner.hitTest(result, x, y),
  );

  Map<String, Object?> _answer(String method, Map<String, String> params) {
    final inspector = _inspector;
    switch (method) {
      case 'ext.twk.tree':
        final tree = params['tree'] ?? 'element';
        if (tree != 'element' && tree != 'render') {
          throw _ExtensionError.params('tree: element or render, not $tree');
        }
        return inspector.tree(render: tree == 'render');
      case 'ext.twk.properties':
        return inspector.properties(_node(params));
      case 'ext.twk.layout':
        return inspector.layout(_node(params));
      case 'ext.twk.select':
        return inspector.select(_int(params, 'x'), _selectedRow(params));
      case 'ext.twk.highlight':
        final node = params.containsKey('id') ? _node(params) : null;
        final o = debug.highlight = node == null
            ? null
            : inspector.renderObjectOf(node);
        return {
          'id': node == null ? null : inspector.idOf(node),
          if (o != null) 'render': inspector.idOf(o),
        };
      case 'ext.twk.flags':
        return debug._flags(params);
      case 'ext.twk.reassemble':
        reassemble();
        return const {};
      case 'ext.twk.log':
        final record = _record(params);
        // the console, made now if it wasn't, opens on an error
        debug.console.sink.add(record);
        return const {};
    }
    throw ArgumentError.value(method, 'method', 'not a service extension');
  }

  /// The record `ext.twk.log` adds.
  static LogRecord _record(Map<String, String> params) {
    final message =
        params['message'] ?? (throw const _ExtensionError.params('no message'));
    final level = switch (params['level']) {
      null => LogLevel.info,
      final name =>
        LogLevel.values.asNameMap()[name] ??
            (throw _ExtensionError.params(
              'level: debug, info, warning or error, not $name',
            )),
    };
    return LogRecord(DateTime.now(), level, message, error: params['error']);
  }

  /// The row of the app's screen `ext.twk.select` names: `y`, or with
  /// `cursorY` the row that far from the cursor's.
  int _selectedRow(Map<String, String> params) {
    final y = _int(params, 'y');
    if (!params.containsKey('cursorY')) {
      return y;
    }
    final cursor = _int(params, 'cursorY');
    final row = twkApp.screen.presenter.cursorRow;
    return row < 0 ? y : y - cursor + row;
  }

  /// The node the `id` parameter names.
  Object _node(Map<String, String> params) {
    final id = _int(params, 'id');
    return _inspector.nodeOf(id) ??
        (throw _ExtensionError.gone('no node $id in the app'));
  }

  static int _int(Map<String, String> params, String name) {
    final value = params[name];
    if (value == null) {
      throw _ExtensionError.params('no $name');
    }
    return int.tryParse(value) ??
        (throw _ExtensionError.params('$name: an int, not $value'));
  }

  /// The element of the app's widget, below the binding's own.
  Element? _appElement() {
    Element? e = _root;
    while (e != null && e.widget is! _Scope) {
      Element? next;
      e.visitChildren((c) => next ??= c);
      e = next;
    }
    Element? app;
    e?.visitChildren((c) => app ??= c);
    return app;
  }

  /// The time of the frame running, or of the last one between frames, on
  /// the app's clock ([TwkApp.clock]) as it started; zero before the first.
  Duration get frameTime => _frameTime;
  Duration _frameTime = Duration.zero;

  /// Calls [callback] once, at the start of a frame before its build, with
  /// the frame's time ([frameTime]), and asks for that frame: the next one,
  /// or with [at] the first at or after that time on the app's clock. A
  /// timer asks for it then: one for all the callbacks that wait for a
  /// time, none while none does. A callback scheduled while they are
  /// called waits for the next frame, and one scheduled once [run] has
  /// ended is never called. Returns the id [cancelFrameCallback] takes.
  int scheduleFrameCallback(FrameCallback callback, {Duration? at}) {
    final id = ++_lastCallback;
    final due = at?.inMicroseconds;
    _callbacks[id] = (callback, due);
    // before run, the first frame calls it or starts its timer
    if (_running) {
      if (due == null || due <= twkApp.clock.elapsedMicroseconds) {
        twkApp.requestFrame();
      } else if (_dueTimer == null || due < _dueAt) {
        _waitForDue();
      }
    }
    return id;
  }

  /// Calls the callback [id] names ([scheduleFrameCallback]) at no frame;
  /// an id called already or cancelled is ignored.
  void cancelFrameCallback(int id) {
    if (_callbacks.remove(id)?.$2 != null) {
      _waitForDue();
    }
  }

  // the frame callbacks waiting by id, in the order they were scheduled,
  // each with the time it waits for, in microseconds
  final _callbacks = <int, (FrameCallback, int?)>{};
  var _lastCallback = 0;

  // asks for the frame of the earliest callback that waits for a time, at
  // _dueAt
  Timer? _dueTimer;
  var _dueAt = 0;

  // the frame callbacks are being called
  var _callingBack = false;

  // run runs: the zone the app runs in, where the timer starts
  var _running = false;
  Zone _zone = Zone.current;

  /// Calls the callbacks due at [now], the frame's time.
  void _callFrameCallbacks(int now) {
    final due = [
      for (final MapEntry(:key, value: (_, at)) in _callbacks.entries)
        if (at == null || at <= now) key,
    ];
    final time = _frameTime;
    // what they change is built by this frame
    _callingBack = true;
    try {
      for (final id in due) {
        // one called before may have cancelled it
        _callbacks.remove(id)?.$1(time);
      }
    } finally {
      _callingBack = false;
    }
    _waitForDue();
  }

  /// Has the timer ask for a frame at the earliest time a callback waits
  /// for; stops it while none waits.
  void _waitForDue() {
    int? first;
    if (_running) {
      for (final (_, at) in _callbacks.values) {
        if (at != null && (first == null || at < first)) {
          first = at;
        }
      }
    }
    if (_dueTimer != null && first == _dueAt) {
      return;
    }
    _dueTimer?.cancel();
    _dueTimer = null;
    if (first != null) {
      _dueAt = first;
      final wait = first - twkApp.clock.elapsedMicroseconds;
      _dueTimer = _zone.createTimer(
        Duration(microseconds: wait > 0 ? wait : 0),
        _due,
      );
    }
  }

  void _due() {
    _dueTimer = null;
    twkApp.requestFrame();
  }

  void _show(Widget? scope) {
    _root = RootWidget(child: _View(this, child: scope)).attach(_owner, _root);
  }

  void _scheduleBuild() {
    _buildScheduled = true;
    if (!_callingBack) {
      twkApp.requestFrame();
    }
  }

  // the TwkApp runs it at the start of each frame
  void _beforeLayout() {
    final now = twkApp.clock.elapsed;
    _frameTime = now;
    if (_callbacks.isNotEmpty) {
      _callFrameCallbacks(now.inMicroseconds);
    }
    if (_buildScheduled) {
      _buildScheduled = false;
      _build();
    }
    if (_screenReader) {
      _read();
    }
  }

  void _focusChanged() {
    if (!_building) {
      _scheduleBuild();
    }
  }

  // the builds after the first in a frame that settle the focus; what is
  // left waits for the next frame
  static const _focusBuilds = 3;

  void _build() {
    _building = true;
    try {
      final first = _first;
      if (first != null) {
        _first = null;
        _show(first);
      }
      final focus = focusManager;
      _owner.buildScope(focus.flush);
      for (var i = 0; i < _focusBuilds && focus.needsFlush; i++) {
        _owner.buildScope(focus.flush);
      }
    } finally {
      _building = false;
    }
    if (focusManager.needsFlush) {
      _scheduleBuild();
    }
    _trackMouse();
  }

  // the TwkApp runs it once each frame is painted, before it is written:
  // the hidden cursor rests on what has the focus ([restCursor]), where a
  // terminal that marks its row (iTerm2's cursor guide) or follows it
  // (macOS zoom) shows the focus, not where the frame wrote last
  void _beforePresent() {
    final presenter = twkApp.screen.presenter;
    if (presenter.cursorVisible) {
      return;
    }
    final focused = focusManager.primaryFocus?.context?.findRenderObject();
    if (restingCell(presenter, focused) case (final x, final y)) {
      presenter
        ..cursorX = x
        ..cursorY = y;
    }
  }

  // the TwkApp runs it at the end of each frame
  void _afterPresent() {
    _owner.finalizeTree();
    _trackMouse();
    _mouse.afterFrame();
    TerminalStatus.ofBinding(this).showPointer();
    final rebuilds = _owner.rebuilds;
    _rebuilt = rebuilds - _rebuildsSeen;
    _rebuildsSeen = rebuilds;
    final overlay = debug._overlay;
    if (overlay != null) {
      debug._afterFrame(overlay);
    }
    if (_rebuilt > 0 && debug.treeEvents) {
      postEvent('twk.treeChanged', {
        'version': serviceExtensionsVersion,
        'rebuilds': _rebuilt,
      });
    }
  }

  /// Has the terminal report the mouse as the mounted listeners need, all
  /// of it while a node is picked, and none of it while the app is read
  /// out.
  void _trackMouse() {
    if (twkApp.terminal case final MouseTrackingBackend terminal) {
      terminal.mouseTracking = debug.select
          ? MouseTracking.motion
          : _screenReader
          ? MouseTracking.off
          : _mouse.tracking;
    }
  }

  Never _mouseFailed(RenderObject target, Object error, StackTrace stack) =>
      Error.throwWithStackTrace(
        WidgetError(error, _renderPathOf(target)),
        stack,
      );

  Widget _buildFailed(Element element, Object error, StackTrace stack) {
    log(
      '${_pathOf(element)} failed to build',
      level: LogLevel.error,
      error: error,
      stack: stack,
    );
    return ErrorWidget(error);
  }

  void _renderFailed(
    RenderObject object,
    RenderPhase phase,
    Object error,
    StackTrace stack,
  ) {
    final doing = phase == RenderPhase.layout ? 'lay out' : 'paint';
    log(
      '${_renderPathOf(object)} failed to $doing',
      level: LogLevel.error,
      error: error,
      stack: stack,
    );
  }

  /// The path of the widget whose render object [object] is; of the one
  /// whose render object it is inside, followed by its type, if none; of
  /// the one whose render object is its child, if none, for a commit that
  /// holds one of the tree's (`Static`).
  String _renderPathOf(RenderObject object) {
    final elements = Map<RenderObject, Element>.identity();
    void visit(Element e) {
      if (e is RenderObjectElement) {
        elements[e.renderObject] = e;
      }
      e.visitChildren(visit);
    }

    _root?.visitChildren(visit);
    for (RenderObject? o = object; o != null; o = o.parent) {
      final element = elements[o];
      if (element != null) {
        final path = _pathOf(element);
        return identical(o, object) ? path : '$path → ${object.runtimeType}';
      }
    }
    Element? held;
    object.visitChildren((child) => held ??= elements[child]);
    return held == null ? '${object.runtimeType}' : _pathOf(held!);
  }

  void _dispatch(InputEvent event) {
    if (event case ColorSchemeReport(:final brightness)
        when brightness != _brightness || !_brightnessKnown) {
      _brightness = brightness;
      _brightnessKnown = true;
      _brightnessState?._changed();
    }
    if (event case ColorReport(which: 10, :final rgb) when rgb != _foreground) {
      _foreground = rgb;
      _brightnessState?._changed();
    }
    if (event case ColorReport(which: 4, :final index, :final rgb)
        when index < 16 && _palette[index] != rgb) {
      _palette = {..._palette, index: rgb};
      _brightnessState?._changed();
    }
    if (event case ColorReport(which: 11, :final rgb) when rgb != _background) {
      _background = rgb;
      _brightness = Brightness.ofRgb(rgb);
      _brightnessKnown = true;
      _brightnessState?._changed();
    }
    if (debug._pick != _Pick.off && debug._takePick(event)) {
      return;
    }
    if (event is KeyEvent && debug.keys && debug._takeKey(event)) {
      return;
    }
    if (event is KeyEvent && _sendToFocus(event)) {
      return;
    }
    if (event is MouseEvent && debug._takeMouse(event)) {
      return;
    }
    if (event is MouseEvent && _mouse.dispatch(event)) {
      return;
    }
    // the listeners mounted as the event came, the last first
    final listeners = _listeners;
    final shared = _listenersShared;
    _listenersShared = true;
    try {
      for (var i = listeners.length - 1; i >= 0; i--) {
        final listener = listeners[i];
        final bool taken;
        try {
          taken = listener.widget.onEvent(event);
        } on Object catch (error, stack) {
          Error.throwWithStackTrace(
            WidgetError(error, _pathOf(listener.context)),
            stack,
          );
        }
        if (taken) {
          return;
        }
      }
    } finally {
      if (identical(_listeners, listeners)) {
        _listenersShared = shared;
      }
    }
    if (event case KeyEvent(code: KeyCode.tab, :final modifiers, :final kind)
        when kind != KeyKind.release &&
            (modifiers == 0 || modifiers == Mod.shift)) {
      final from = focusManager.primaryFocus ?? focusManager.rootScope;
      if (modifiers == 0) {
        from.nextFocus();
      } else {
        from.previousFocus();
      }
    } else if (event
        case KeyEvent(char: 'c', modifiers: Mod.ctrl, kind: KeyKind.press)
        when exitOnCtrlC) {
      quit();
    }
  }

  /// Gives [event] to the nodes of [FocusManager.keyPath] in turn;
  /// returns whether one of them handled it.
  bool _sendToFocus(KeyEvent event) {
    for (final node in focusManager.keyPath) {
      final onKeyEvent = node.onKeyEvent;
      if (onKeyEvent == null) {
        continue;
      }
      final KeyEventResult result;
      try {
        result = onKeyEvent(node, event);
      } on Object catch (error, stack) {
        final context = node.context;
        Error.throwWithStackTrace(
          WidgetError(error, context == null ? '$node' : _pathOf(context)),
          stack,
        );
      }
      if (result == KeyEventResult.handled) {
        return true;
      }
    }
    return false;
  }
}

/// The debug aids of an app ([AppBinding.debug]), all off by default: the
/// frame overlay ([overlay]), the log console ([console]), the repaint
/// rainbow ([rainbow]), the relayout highlight ([relayout]), the outline
/// over a render object ([highlight]) and the pick of a node on the screen
/// for a tool ([select]). The app turns them on and off, or the debug
/// keys do, or a tool by the service extensions
/// ([AppBinding.callServiceExtension]); each of the first four is on from
/// the start when `TWK_DEBUG`, a comma-separated list, names it:
/// `overlay`, `console`, `rainbow`, `relayout`, read from the names the
/// app's `TwkApp` parsed of its environment (`TwkApp.debugNames`, see
/// [AppBinding.new]'s `environment`). A name neither this nor the core's
/// `TwkApp` reads (`TwkApp.debugNamesRead`: `frames`, `timeline`, `logs`,
/// and the two paints) turns nothing on and is said in the log, as a
/// warning.
///
/// The debug keys are taken while [keys] is on, from the start when
/// `TWK_DEBUG` names `keys` or any of the aids: Ctrl+G, then
///
/// * `o` shows or hides the frame overlay, `c` opens or closes the
///   console, `r` turns the rainbow on or off, `l` the relayout highlight;
/// * `f` lists the console's next level and above (debug, info, warning,
///   error, then debug again), `y` copies its selected record to the
///   clipboard, `s` saves the records it lists to a file in the system's
///   temporary directory and logs where, `x` clears it (the records logged
///   so far listed no more, the log keeping them);
/// * `h` asks the tool that runs the app, `twk run`, for a hot reload,
///   `H` for a hot restart ([AppBinding.postEvent]: `twk.reload`,
///   `twk.restart`); without one, a warning says so in the log;
/// * Ctrl+G gives the app a Ctrl+G; any other key is dropped.
///
/// While Ctrl+G waits for its key, a line over the bottom row of the
/// screen, or of the inline region, lists these keys and what each does,
/// as many as fit, until the next key: drawn like the panels below, it
/// changes nothing in the app's layout.
///
/// While the console is open, Up and Down select the record before or
/// after, Page Up and Page Down scroll it a page, End goes back to the
/// newest record, Enter shows the selected record whole (its message and
/// error line by line and its stack, a frame a line, in twice the rows;
/// there Up, Down, Page Up, Page Down, Home and End move through its
/// lines, Enter on a frame of the stack opens its file at its line in an
/// editor (`TWK_EDITOR`, `VISUAL`, `EDITOR`: `editorCommand`) and Escape
/// goes back to the list), and Escape deselects the
/// record, or closes the console when none is selected. These keys go to
/// the debug aids before the focus nodes and the [InputListener]s; with
/// [keys] off, none is. Ctrl+G is the
/// prefix because every terminal sends it, as one byte without the kitty
/// keyboard protocol, neither the tty nor the terminal takes it, and few
/// apps bind it (Emacs' cancel, nano's help); F12 is the terminal's own key
/// in some (Guake, Yakuake, Tilda).
///
/// The overlay and the console are panels over the app, in the colors of
/// the terminal's theme ([ThemeData.terminal]): the overlay at the top
/// right, the console over the bottom rows of the screen, or in the inline
/// mode below the app, the region growing by it. Full screen, a panel shown
/// is painted on its own, and one hidden repaints only the smallest repaint
/// boundary of the app that holds its cells; in the inline mode either
/// lays the region out again. The overlay takes no mouse events; the
/// console takes those over it, which the app below gets none of: the wheel
/// scrolls it, a press selects the row's record or line. Off, the aids add
/// nothing to a frame's work.
///
/// An app that shows its frame overlay from the start, and lets the debug
/// keys turn the rest on:
///
/// ```dart
/// final debug = AppBinding.of(context).debug
///   ..overlay = true
///   ..keys = true;
/// ```
final class DebugAids {
  DebugAids._(this._binding) {
    final names = _binding.twkApp.debugNames;
    _keys = names.any(_names.contains);
    if (names.contains('overlay')) {
      overlay = true;
    }
    if (names.contains('console')) {
      console.open();
    }
    final unknown = [
      for (final n in names)
        if (!_names.contains(n) && !TwkApp.debugNamesRead.contains(n)) "'$n'",
    ];
    if (unknown.isNotEmpty) {
      // in the app's log, as the binding is made outside the app's zone
      _binding.twkApp.logs.add(
        LogRecord(
          DateTime.now(),
          LogLevel.warning,
          'TWK_DEBUG names nothing it knows as ${unknown.join(', ')}: it '
          'takes ${{..._names, ...TwkApp.debugNamesRead}.join(', ')}, '
          'comma-separated',
        ),
      );
    }
  }

  static const _names = {'keys', 'overlay', 'console', 'rainbow', 'relayout'};

  final AppBinding _binding;

  /// Whether the debug keys are taken. Turned off while Ctrl+G waits, the
  /// wait ends.
  bool get keys => _keys;
  var _keys = false;

  set keys(bool on) {
    _keys = on;
    if (!on) {
      _endPrefix();
    }
  }

  FrameOverlay? _overlay;

  // the overlay's panel is shown
  var _overlayShown = false;

  /// Whether the frame overlay is shown: a panel with the numbers of the
  /// app's frames as the binding and the core measured them
  /// (`TwkApp.stats`, `Presenter.stats`), each frame's and the median of
  /// the last 128 — the time of its build, layout, paint and present, the
  /// bytes written, the cells written and compared, the rows scrolled, the
  /// repaint boundaries marked for paint (`repaints`) and the elements
  /// built (`rebuilds`, [BuildOwner.rebuilds]) — and the
  /// frames written in the last second. It shows new numbers at most four
  /// times a second, and once more a second after the last frame written;
  /// it counts each frame the app did anything in, those it shows them in
  /// too, less its own layout, paint, mark and the bytes and cells of its
  /// own presented alone: what it shows is the app's. Turned on before the
  /// first frame, it is shown after it.
  bool get overlay => _overlay != null;

  set overlay(bool on) {
    if (on == overlay) {
      return;
    }
    if (on) {
      final overlay = _overlay = FrameOverlay(_binding.twkApp, _binding._theme);
      if (_binding._view._laidOut) {
        _showOverlay(overlay);
      }
    } else {
      final overlay = _overlay!..dispose();
      _overlay = null;
      if (_overlayShown) {
        _overlayShown = false;
        _binding._view.hide(overlay.panel);
        _shrinkInline();
      }
    }
  }

  void _showOverlay(FrameOverlay overlay) {
    _overlayShown = true;
    overlay.start(_binding._rebuilt);
    _binding._view.show(overlay.panel, _Slot.overlay);
  }

  void _afterFrame(FrameOverlay overlay) {
    if (_overlayShown) {
      overlay.afterFrame(_binding._rebuilt);
    } else {
      _showOverlay(overlay);
    }
  }

  ConsoleController? _console;
  RenderConsolePanel? _consolePanel;

  /// The log console over the app's log sink: shown while it is open
  /// ([ConsoleController.open]), opening by itself on an error
  /// ([ConsoleController.openOnError]). Made the first time it is asked
  /// for, it lists the records the sink keeps then and takes the rest.
  ConsoleController get console =>
      _console ??= ConsoleController(_binding.twkApp.logs, openOnError: true)
        ..addListener(_consoleChanged);

  // how tall the console is
  static const _consoleRows = 10;

  /// Takes [event] when the mouse is over the open console, so that the
  /// app below gets none of it there: the wheel scrolls the list, or the
  /// lines of a record shown whole, a step of three rows; a press of the
  /// left button on a row selects what it shows.
  bool _takeMouse(MouseEvent event) {
    final panel = _consolePanel;
    final console = _console;
    if (panel == null || console == null || panel.owner == null) {
      return false;
    }
    final (left, top) = panel.globalOffset;
    final x = event.x - left;
    final y = event.y - top;
    if (x < 0 || y < 0 || x >= panel.width || y >= panel.height) {
      return false;
    }
    final record = console.shownRecord != null;
    switch (event.kind) {
      case MouseKind.wheelUp:
        record ? console.moveLine(-3) : console.scrollBy(-3);
      case MouseKind.wheelDown:
        record ? console.moveLine(3) : console.scrollBy(3);
      case MouseKind.down when event.button == 0 && y > 0:
        console.selectRow(y - 1);
      case _:
    }
    return true;
  }

  void _consoleChanged() {
    final console = _console!;
    if (console.isOpen == (_consolePanel != null)) {
      return;
    }
    final view = _binding._view;
    if (console.isOpen) {
      view.show(
        _consolePanel = RenderConsolePanel(
          controller: console,
          theme: _binding._theme,
          rows: _consoleRows,
        ),
        _Slot.console,
      );
    } else {
      view.hide(_consolePanel!);
      _consolePanel = null;
      _shrinkInline();
    }
  }

  /// Whether each repaint of a repaint boundary is tinted with the next
  /// color of a cycle (`PipelineOwner.debugRepaintRainbow`).
  bool get rainbow => _binding.twkApp.owner.debugRepaintRainbow;
  set rainbow(bool on) => _binding.twkApp.owner.debugRepaintRainbow = on;

  /// Whether the binding tells a tool when the element tree changed (as
  /// an inspector that shows it follows it): after each frame in which
  /// elements built ([BuildOwner.rebuilds]: mounted, dirty or updated with
  /// a new widget, which every change of the tree is), at most once a
  /// frame, it posts `twk.treeChanged` with `version`
  /// ([AppBinding.serviceExtensionsVersion]) and `rebuilds`, how many built
  /// in that frame, on the VM service's `Extension` stream
  /// ([AppBinding.postEvent]); nothing for a frame that only laid out or
  /// painted. Off by default (`ext.twk.flags` `treeEvents` sets it): off,
  /// a frame's work gains a test of this flag; on, a post, which does
  /// nothing while no client listens to that stream.
  var treeEvents = false;

  /// Whether what was laid out since the last frame is outlined
  /// (`PipelineOwner.debugRelayoutHighlight`).
  bool get relayout => _binding.twkApp.owner.debugRelayoutHighlight;
  set relayout(bool on) => _binding.twkApp.owner.debugRelayoutHighlight = on;

  /// The render object outlined over the app, null for none: the cells of
  /// it the screen shows, those an ancestor cuts off left out, their
  /// backgrounds blended with blue, its edges' more, their glyphs and text
  /// kept. The outline is painted over the app and under the panels, from
  /// the next frame on, where the object is in each frame; it is null
  /// again while the object is out of the tree. Setting it repaints the
  /// app.
  RenderObject? get highlight => _binding._view.highlight;
  set highlight(RenderObject? o) => _binding._view.highlight = o;

  /// Whether the app picks a node on its screen for a tool (`ext.twk.flags`
  /// `select`, as `twk inspect` sets it): while it does, the terminal
  /// reports all of the mouse, none of which the app gets, and the node
  /// under the mouse is outlined in place of [highlight]. A press of the
  /// left button picks its cell and ends it: the binding posts `twk.select`
  /// with the cell, `version` ([AppBinding.serviceExtensionsVersion]), `x`
  /// and `y`, on the VM service's `Extension` stream
  /// ([AppBinding.postEvent]), and the app gets neither that press nor what
  /// the mouse does until it is released. Escape ends it too, posting
  /// `twk.select` with `x` and `y` null, and the app does not get it; set
  /// off, it posts nothing. Then the highlight it had is back. Full screen
  /// only: in the inline mode the terminal keeps the mouse, and it stays
  /// off. With [selectMany] a cell picked does not end it.
  bool get select => _pick == _Pick.armed || selectMany && _pick == _Pick.held;

  set select(bool on) {
    if (on == select || on && _binding.mode == ScreenMode.inline) {
      return;
    }
    if (on) {
      _highlighted = highlight;
      _pick = _Pick.armed;
    } else {
      highlight = _highlighted;
      _highlighted = null;
      _pick = _Pick.off;
    }
    _binding._trackMouse();
  }

  /// Whether a pick ([select]) goes on after a press picked a cell
  /// (`ext.twk.flags` `selectMany`, as a tool's pick mode that stays on
  /// until it is turned off sets it): each press of the left button posts
  /// its cell, the node under the mouse outlined between them, until
  /// Escape or [select] set off ends it. Off, the default, the first press
  /// ends it.
  var selectMany = false;

  _Pick _pick = _Pick.off;

  // the highlight before the pick, which it gives back
  RenderObject? _highlighted;

  /// Takes [event] when it is the pick's ([select]).
  bool _takePick(InputEvent event) {
    if (_pick == _Pick.held) {
      // what the mouse does until the button that picked is released;
      // picking many, the keys still the pick's (Escape)
      final again = selectMany ? _Pick.armed : _Pick.off;
      switch (event) {
        case MouseEvent(kind: MouseKind.up):
          _pick = again;
          return true;
        case MouseEvent(kind: MouseKind.down):
          // a release the terminal did not report
          _pick = again;
          if (!selectMany) {
            return false;
          }
        case MouseEvent():
          return true;
        case _ when !selectMany:
          return false;
        case _:
      }
    }
    switch (event) {
      case KeyEvent(code: KeyCode.escape, modifiers: 0, :final kind)
          when kind != KeyKind.release:
        _picked(null);
        return true;
      case MouseEvent(kind: MouseKind.down, button: 0, :final x, :final y):
        _picked((x, y));
        _pick = _Pick.held;
        return true;
      case MouseEvent(:final kind, :final x, :final y):
        if (kind == MouseKind.move || kind == MouseKind.drag) {
          highlight = _binding._inspector.elementAt(x, y)?.renderObject;
        }
        return true;
      case _:
        return false;
    }
  }

  /// Ends the pick, posting [cell], null for none.
  void _picked((int, int)? cell) {
    if (cell == null || !selectMany) {
      select = false;
    }
    AppBinding.postEvent('twk.select', {
      'version': AppBinding.serviceExtensionsVersion,
      'x': cell?.$1,
      'y': cell?.$2,
    });
  }

  /// What `ext.twk.flags` answers, once the aids [params] name are set.
  Map<String, Object?> _flags(Map<String, String> params) {
    if (params.containsKey('framesInRow')) {
      throw const _ExtensionError.params('framesInRow: the app is built so');
    }
    bool? asked(String name) => switch (params[name]) {
      null => null,
      'true' => true,
      'false' => false,
      final v => throw _ExtensionError.params('$name: true or false, not $v'),
    };
    final overlay = asked('overlay');
    final console = asked('console');
    final rainbow = asked('rainbow');
    final relayout = asked('relayout');
    final keys = asked('keys');
    final select = asked('select');
    final selectMany = asked('selectMany');
    final treeEvents = asked('treeEvents');
    if (overlay != null) {
      this.overlay = overlay;
    }
    switch (console) {
      case true:
        this.console.open();
      case false:
        _console?.close();
      case null:
    }
    if (rainbow != null) {
      this.rainbow = rainbow;
    }
    if (relayout != null) {
      this.relayout = relayout;
    }
    if (keys != null) {
      this.keys = keys;
    }
    if (selectMany != null) {
      this.selectMany = selectMany;
    }
    if (select != null) {
      this.select = select;
    }
    if (treeEvents != null) {
      this.treeEvents = treeEvents;
    }
    return {
      'overlay': this.overlay,
      'console': _console?.isOpen ?? false,
      'rainbow': this.rainbow,
      'relayout': this.relayout,
      'keys': this.keys,
      'select': this.select,
      'selectMany': this.selectMany,
      'treeEvents': this.treeEvents,
      'framesInRow': _binding.twkApp.framesInRow,
    };
  }

  /// The inline region fits what is left.
  void _shrinkInline() {
    if (_binding._view.inline) {
      _binding.twkApp.shrinkRegion();
    }
  }

  static final _prefix = KeyCombo.char('g', modifiers: Mod.ctrl);
  static final _restart = KeyCombo.char('H');

  // Ctrl+G was pressed: the next key is a command
  var _prefixed = false;

  // the line of the commands shown meanwhile
  RenderKeyHint? _hint;

  /// Takes [event] when it is a debug key.
  bool _takeKey(KeyEvent event) {
    if (_prefixed) {
      _endPrefix();
      if (_prefix.accepts(event)) {
        // for the app
        return false;
      }
      _command(event);
      return true;
    }
    if (_prefix.accepts(event)) {
      _prefixed = true;
      _binding._view.show(_hint = RenderKeyHint(_binding._theme), _Slot.hint);
      return true;
    }
    final console = _console;
    return console != null && console.isOpen && _consoleKey(console, event);
  }

  /// Ctrl+G waits no more: the line of the commands goes. The inline
  /// region, a row at least, was not grown by it, and keeps its rows.
  void _endPrefix() {
    _prefixed = false;
    final hint = _hint;
    if (hint != null) {
      _hint = null;
      _binding._view.hide(hint, painted: hint.painted);
    }
  }

  /// Runs the command of [event], the key after the prefix, if it names
  /// one.
  void _command(KeyEvent event) {
    if (_restart.accepts(event)) {
      _askTool('restart');
      return;
    }
    if (event.code != KeyCode.char || event.modifiers != 0) {
      return;
    }
    switch (event.char) {
      case 'o':
        overlay = !overlay;
      case 'c':
        console.toggle();
      case 'r':
        rainbow = !rainbow;
      case 'l':
        relayout = !relayout;
      case 'f':
        const levels = LogLevel.values;
        console.level = levels[(console.level.index + 1) % levels.length];
      case 'y':
        console.copy(_binding.twkApp.terminal);
      case 's':
        _save(console);
      case 'x':
        console.clear();
      case 'h':
        _askTool('reload');
    }
  }

  /// Asks the tool that runs the app for a hot [what], `reload` or
  /// `restart`, or says in the log that none does.
  void _askTool(String what) {
    if (!AppBinding.postEvent('twk.$what')) {
      log(
        'no hot $what: the app runs without twk run',
        level: LogLevel.warning,
      );
    }
  }

  /// Saves what [console] lists and logs where, or why not.
  void _save(ConsoleController console) {
    final path = tempFile('twk_console_$processId.log');
    unawaited(
      console
          .save(path)
          .then(
            (_) => log('console saved to $path'),
            onError: (Object error, StackTrace stack) => log(
              'console not saved to $path',
              level: LogLevel.warning,
              error: error,
              stack: stack,
            ),
          ),
    );
  }

  /// Takes [event] when it is a key of the open [console].
  bool _consoleKey(ConsoleController console, KeyEvent event) {
    if (event.modifiers != 0) {
      return false;
    }
    // a record shown whole: its lines; Escape back to the list
    if (console.shownRecord != null) {
      const page = 2 * _consoleRows - 2;
      final action = switch (event.code) {
        KeyCode.up => () => console.moveLine(-1),
        KeyCode.down => () => console.moveLine(1),
        KeyCode.pageUp => () => console.moveLine(-page),
        KeyCode.pageDown => () => console.moveLine(page),
        KeyCode.home => () => console.moveLine(-console.lineIndex),
        KeyCode.end => () => console.moveLine(1 << 30),
        KeyCode.enter => () => _openFrame(console.selectedLine?.frame),
        KeyCode.escape => console.hideRecord,
        _ => null,
      };
      action?.call();
      return action != null;
    }
    final action = switch (event.code) {
      KeyCode.up => console.selectPrevious,
      KeyCode.down => console.selectNext,
      KeyCode.pageUp => () => console.scrollBy(1 - _consoleRows),
      KeyCode.pageDown => () => console.scrollBy(_consoleRows - 1),
      KeyCode.end => console.scrollToEnd,
      KeyCode.enter when console.selected != null => console.showSelected,
      KeyCode.escape =>
        console.selected != null ? console.deselect : console.close,
      _ => null,
    };
    action?.call();
    return action != null;
  }

  /// What runs the command that opens a file of a stack ([editorCommand]):
  /// in the app's terminal while the app waits, or apart; returns its exit
  /// code, null for one run apart. Replaced by a test.
  @visibleForTesting
  static Future<int?> Function(EditorCommand command) runEditor = (c) async {
    if (c.inTerminal) {
      return runOnTerminal(c.executable, c.arguments);
    }
    await startApart(c.executable, c.arguments);
    return null;
  };

  /// Opens the file of [frame] at its line and column as `TWK_EDITOR`,
  /// `VISUAL` or `EDITOR` says ([editorCommand]): a terminal editor with
  /// the app suspended until it ends, another apart. What stops it — no
  /// file (a library of the SDK, a package the program does not resolve),
  /// none of the three set, the command failing — is said in the log.
  void _openFrame(RecordFrame? frame) {
    if (frame == null) {
      return;
    }
    final path = frame.path;
    if (path == null) {
      log(
        'no file to open for ${frame.uri}: the program does not say where '
        'it is',
        level: LogLevel.warning,
      );
      return;
    }
    final command = editorCommand(
      _binding.twkApp.environment,
      path,
      frame.line ?? 1,
      frame.column ?? 1,
    );
    if (command == null) {
      log(
        'to open code from the console, set TWK_EDITOR to a command with '
        '{file}, {line} and {column} (code -g {file}:{line}:{column}), or '
        'VISUAL or EDITOR to an editor',
        level: LogLevel.warning,
      );
      return;
    }
    final app = _binding.twkApp;
    final run = command.inTerminal
        ? app.suspend(() => runEditor(command))
        : runEditor(command);
    unawaited(
      run.then(
        (code) {
          if (code != null && code != 0) {
            log(
              '${command.executable} ended with $code',
              level: LogLevel.warning,
            );
          }
        },
        onError: (Object error, StackTrace stack) => log(
          'could not open $path with ${command.executable}',
          level: LogLevel.warning,
          error: error,
          stack: stack,
        ),
      ),
    );
  }

  void _dispose() {
    _overlay?.dispose();
    _console?.dispose();
  }
}

/// An error the code of a widget threw that ended the app: [error], thrown
/// in the widget at [path]. Its [stackTrace] is that of [error].
final class WidgetError extends Error {
  /// The [error] thrown in the widget at [path].
  WidgetError(this.error, this.path);

  /// What the widget's code threw.
  final Object error;

  /// The widgets from the app's down to the one whose code threw, as
  /// `Column → Box → TextField`, a key after the type of a widget with one.
  final String path;

  /// The lines of the app's own code around the one [error] was thrown at,
  /// that line marked, under its file and line: of the first frame of
  /// [stackTrace] in neither the SDK, nor twk, nor a package from the pub
  /// cache, read from its file. Null where that file can't be read (a
  /// package the program doesn't resolve, as an AOT build resolves none;
  /// the web; a missing file), and before the error is thrown.
  String? get source => sourceExcerpt(stackTrace);

  /// The error, on a line of its own the widget it was thrown in, then the
  /// [source] where it can be read: what the VM prints of an error nothing
  /// caught, above the stack, once the app restored the terminal.
  @override
  String toString() => ['$error', 'in $path', ?source].join('\n');
}

/// Where a pick of a node on the screen is ([DebugAids.select]).
enum _Pick {
  off,

  /// The next press of the left button picks.
  armed,

  /// The press that picked is held: what the mouse does until its release
  /// is the pick's.
  held,
}

/// Where the view shows a panel of the debug aids, in the order they are
/// painted.
enum _Slot {
  /// The frame overlay, at the top right.
  overlay,

  /// The console, over the bottom rows, or below the app in the inline
  /// mode.
  console,

  /// The line of the debug keys while Ctrl+G waits, over the bottom row.
  hint,
}

/// What a service extension answers when it cannot answer: [code], one of
/// the errors of [ServiceExtensionResponse], and [message].
final class _ExtensionError implements Exception {
  const _ExtensionError.params(this.message)
    : code = ServiceExtensionResponse.invalidParams;

  const _ExtensionError.gone(this.message)
    : code = ServiceExtensionResponse.extensionError;

  final int code;
  final String message;

  ServiceExtensionResponse get response =>
      ServiceExtensionResponse.error(code, jsonEncode({'message': message}));
}

/// Gives [onEvent] the input events of the app it is in while it is
/// mounted, wherever it is in the tree: the keys that neither the debug
/// aids nor a focus node took ([AppBinding]), the mouse events that no
/// [Listener] took, pastes, focus and resizes. Each event goes to the
/// listener mounted last first, then to the others in turn until one of
/// them returns true, which takes it.
///
/// It gets the mouse events the terminal reports. The binding has a
/// terminal that can switch them ([MouseTrackingBackend], as a [Terminal]
/// is) report what the [Listener]s and [MouseRegion]s mounted with
/// callbacks need, the most any of them needs, and nothing while none is:
/// presses, releases and the wheel, or also drags, or all motion. A
/// terminal that cannot reports what it was opened with.
///
/// An error [onEvent] throws ends the app (a [WidgetError]), as does one an
/// [FocusNode.onKeyEvent], a [Listener] or a [MouseRegion] throws.
///
/// The size of the terminal, kept as it is resized:
///
/// ```dart
/// InputListener(
///   onEvent: (event) {
///     if (event is ResizeEvent) {
///       size.value = (event.width, event.height);
///     }
///     return false;
///   },
///   child: const Text('…'),
/// )
/// ```
///
/// See also:
///
///  * [Focus] and `KeyBindings`, for the keys of a part of the app.
///  * [Listener], for the mouse over a widget.
final class InputListener extends StatefulWidget {
  /// Gives [onEvent] the events of the app; shows [child].
  const InputListener({required this.onEvent, required this.child, super.key});

  /// Called with each event; returns whether it took the event.
  final bool Function(InputEvent event) onEvent;

  /// What is shown: the listener draws nothing of its own.
  final Widget child;

  @override
  State<InputListener> createState() => _InputListenerState();
}

final class _InputListenerState extends State<InputListener> {
  AppBinding? _binding;

  @override
  void initState() {
    super.initState();
    _binding = AppBinding.maybeOf(context)?.._ownListeners.add(this);
  }

  @override
  void dispose() {
    _binding?._ownListeners.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The widgets from the app's down to [context]'s, a key after the type of
/// a widget with one.
String _pathOf(BuildContext context) {
  final names = [_nameOf(context.widget)];
  context.visitAncestorElements((e) {
    if (e.widget is _Scope) {
      return false;
    }
    names.add(_nameOf(e.widget));
    return true;
  });
  return names.reversed.join(' → ');
}

String _nameOf(Widget widget) => switch (widget) {
  Widget(key: null, :final runtimeType) => '$runtimeType',
  Widget(:final key, :final runtimeType) => '$runtimeType-$key',
};

/// What finds the binding from below.
final class _Scope extends InheritedWidget {
  const _Scope(this.binding, {required super.child});

  final AppBinding binding;

  @override
  bool updateShouldNotify(_Scope oldWidget) =>
      !identical(binding, oldWidget.binding);
}

/// Puts the app under a [TerminalBrightness] of the binding's brightness.
final class _Brightness extends StatefulWidget {
  const _Brightness(this.binding, {required this.child});

  final AppBinding binding;

  final Widget child;

  @override
  State<_Brightness> createState() => _BrightnessState();
}

final class _BrightnessState extends State<_Brightness> {
  @override
  void initState() {
    super.initState();
    widget.binding._brightnessState = this;
  }

  @override
  void dispose() {
    if (identical(widget.binding._brightnessState, this)) {
      widget.binding._brightnessState = null;
    }
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) => TerminalBrightness(
    brightness: widget.binding._brightness,
    known: widget.binding._brightnessKnown,
    background: widget.binding._background,
    foreground: widget.binding._foreground,
    palette: widget.binding._palette,
    child: widget.child,
  );
}

/// The widget of the binding's root render object.
final class _View extends SingleChildRenderObjectWidget {
  const _View(this.binding, {super.child});

  final AppBinding binding;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => binding._view;
}

/// The root of the render tree: its child at the size of the screen, or
/// of the inline region, which is as tall as the child asks to be; and
/// over it the outline of [highlight] and the debug panels the
/// [DebugAids] show, painted after it in this order: the frame overlay at
/// the top right, the console over the bottom rows, or in the inline mode
/// below the child, the region growing by it, and the line of the debug
/// keys over the bottom row ([_Slot]).
///
/// Full screen, a panel shown is laid out and painted on its own, and one
/// hidden has the smallest repaint boundary of the child that holds its
/// cells repaint: the rest of the app is left as it is. In the inline
/// mode either lays the region out again. Panels take no mouse events
/// here: the binding gives those over the console to it
/// (`DebugAids._takeMouse`) before the app's hit test.
///
/// While the app is read out ([read]) it shows the lines read in place of
/// the child, which is laid out [appRows] tall, or as tall as it asks to
/// be within them in the inline mode, and placed below the view, out of
/// its cells: what in it repaints on its own paints nothing.
final class _RenderView extends RenderObject with RenderObjectWithChildMixin {
  _RenderView({required this.inline});

  final bool inline;

  // the panels shown; whether the view has been laid out
  RenderObject? _overlay;
  RenderObject? _console;
  RenderObject? _hint;
  var _laidOut = false;

  /// The rows the child has while the app is read out.
  var appRows = 0;

  // the lines read, broken into rows of the screen's width; null while the
  // app is not read out
  List<String>? _lines;
  List<String>? _rows;
  // the width of each row; the rows of the focused line, [from, to), and
  // the first row shown
  final _widths = <int>[];
  var _focusFrom = 0;
  var _focusTo = 0;
  var _top = 0;
  final _scan = ClusterScan();

  /// Shows [lines], [focused] the index of the focused one, broken into
  /// rows of [width] cells measured by [segmenter]; or with [lines] null
  /// the child again. Returns whether they take fewer rows than before.
  bool read(
    List<String>? lines, {
    int? focused,
    int width = 0,
    TextSegmenter? segmenter,
  }) {
    final before = _rows?.length;
    if (lines == null) {
      if (_lines != null) {
        _lines = _rows = null;
        markNeedsLayout();
      }
      return false;
    }
    final old = _lines;
    final rows = <String>[];
    final widths = <int>[];
    var from = 0;
    var to = 0;
    for (var i = 0; i < lines.length; i++) {
      if (i == focused) {
        from = rows.length;
      }
      _wrap(lines[i], width, segmenter!, rows, widths);
      if (i == focused) {
        to = rows.length;
      }
    }
    final same = old != null && sameList(old, lines) && sameList(_rows!, rows);
    if (same && from == _focusFrom && to == _focusTo) {
      return false;
    }
    _lines = lines;
    _rows = rows;
    _widths
      ..clear()
      ..addAll(widths);
    _focusFrom = from;
    _focusTo = to;
    if (same) {
      markNeedsPaint();
    } else {
      markNeedsLayout();
    }
    return before != null && rows.length < before;
  }

  /// Adds [line] to [rows] as rows of at most [width] cells, each one's
  /// width to [widths]: broken at the blank that does not fit, or after
  /// the last one that does, or where it has none at the last cluster that
  /// fits.
  void _wrap(
    String line,
    int width,
    TextSegmenter segmenter,
    List<String> rows,
    List<int> widths,
  ) {
    final scan = _scan;
    var start = 0;
    var w = 0;
    // the last blank in the row, and the width before it
    var blank = -1;
    var beforeBlank = 0;
    var i = 0;
    while (i < line.length) {
      segmenter.scan(line, i, scan);
      final cw = scan.width;
      if (w + cw > width && i > start) {
        if (scan.first == 0x20) {
          rows.add(line.substring(start, i));
          widths.add(w);
          i = start = scan.end;
        } else if (blank > start) {
          rows.add(line.substring(start, blank));
          widths.add(beforeBlank);
          i = start = blank + 1;
        } else {
          rows.add(line.substring(start, i));
          widths.add(w);
          start = i;
        }
        w = 0;
        blank = -1;
        continue;
      }
      if (scan.first == 0x20) {
        blank = i;
        beforeBlank = w;
      }
      w += cw;
      i = scan.end;
    }
    rows.add(line.substring(start));
    widths.add(w);
  }

  /// The rows of the lines the view shows.
  int get _shownRows {
    final console = _console;
    return inline && console != null
        ? height - _heightOf(console, height)
        : height;
  }

  /// Moves the rows shown as little as it takes to show the focused line's
  /// first row, and as many of its others as fit.
  void _follow(int shown) {
    final rows = _rows!.length;
    if (_focusTo > _focusFrom) {
      if (_focusFrom < _top) {
        _top = _focusFrom;
      } else if (_focusTo > _top + shown) {
        final top = _focusTo - shown;
        _top = top < _focusFrom ? top : _focusFrom;
      }
    }
    if (_top > rows - shown) {
      _top = rows - shown;
    }
    if (_top < 0) {
      _top = 0;
    }
  }

  void _paintLines(PaintContext ctx) {
    final rows = _rows!;
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    const plain = Pen(fg: Color.defaultColor, bg: Color.defaultColor);
    final pen = styles.pen(plain);
    final marked = styles.pen(
      const Pen(
        fg: Color.defaultColor,
        bg: Color.defaultColor,
        attrs: Attr.reverse,
      ),
    );
    final shown = _shownRows;
    _follow(shown);
    for (var y = 0; y < shown && _top + y < rows.length; y++) {
      final r = _top + y;
      canvas.text(
        0,
        y,
        rows[r],
        r >= _focusFrom && r < _focusTo ? marked : pen,
      );
    }
    // the cursor at the end of the focused line, or of the last one
    final last = _focusTo > _focusFrom ? _focusTo - 1 : rows.length - 1;
    final row = last - _top;
    final x = last < 0 ? 0 : _widths[last];
    ctx.presenter
      ..cursorVisible = true
      ..cursorX = x < width ? x : width - 1
      ..cursorY = row < 0 ? 0 : (row < shown ? row : shown - 1)
      ..cursorShape = CursorShape.terminalDefault;
  }

  RenderObject? _highlight;

  /// What is outlined over the child ([DebugAids.highlight]); null for
  /// none, and while it is detached.
  RenderObject? get highlight {
    final o = _highlight;
    return o?.owner == null ? null : o;
  }

  set highlight(RenderObject? o) {
    if (!identical(o, _highlight)) {
      _highlight = o;
      markNeedsPaint();
    }
  }

  /// Shows [panel] in [slot].
  void show(RenderObject panel, _Slot slot) {
    switch (slot) {
      case _Slot.overlay:
        _overlay = panel;
      case _Slot.console:
        _console = panel;
      case _Slot.hint:
        _hint = panel;
    }
    panel.parent = this;
    final o = owner;
    if (o != null) {
      panel.attach(o);
    }
    if (inline || !_laidOut) {
      markNeedsLayout();
    } else {
      _place(panel);
    }
  }

  /// Hides [panel], a panel shown; with [painted] false one not painted
  /// since it was shown, whose cells still hold what was under it.
  void hide(RenderObject panel, {bool painted = true}) {
    final at = panel.parentData;
    final (x, y, w, h) = (at.dx, at.dy, panel.width, panel.height);
    if (identical(panel, _overlay)) {
      _overlay = null;
    } else if (identical(panel, _console)) {
      _console = null;
    } else {
      _hint = null;
    }
    panel
      ..parent = null
      ..detach();
    if (inline || !_laidOut) {
      markNeedsLayout();
    } else if (painted) {
      _under(x, y, w, h).markNeedsPaint();
    }
  }

  @override
  void visitChildren(void Function(RenderObject child) visit) {
    super.visitChildren(visit);
    final overlay = _overlay;
    if (overlay != null) {
      visit(overlay);
    }
    final console = _console;
    if (console != null) {
      visit(console);
    }
    final hint = _hint;
    if (hint != null) {
      visit(hint);
    }
  }

  /// What the inline region asks: as tall as the child asks to be, or the
  /// lines read, or the overlay, or the line of the debug keys, and the
  /// console below.
  @override
  int computeMaxIntrinsicHeight(int width) {
    var h = _rows?.length ?? child?.getMaxIntrinsicHeight(width) ?? 0;
    final overlay = _overlay;
    if (overlay != null) {
      final o = overlay.getMaxIntrinsicHeight(width);
      h = o > h ? o : h;
    }
    final hint = _hint;
    if (hint != null) {
      final o = hint.getMaxIntrinsicHeight(width);
      h = o > h ? o : h;
    }
    final console = _console;
    return console == null ? h : h + console.getMaxIntrinsicHeight(width);
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    final console = _console;
    final child = this.child;
    if (child != null && _rows != null) {
      var h = appRows;
      if (inline) {
        final asks = child.getMaxIntrinsicHeight(width);
        h = asks < 1 ? 1 : (asks < h ? asks : h);
      }
      child
        ..layout(BoxConstraints.tight(width, h))
        ..parentData.dy = height;
    } else if (inline && console != null) {
      final h = _heightOf(console, height);
      child?.layout(BoxConstraints.tight(width, height - h));
      child?.parentData.dy = 0;
    } else {
      child?.layout(c);
      child?.parentData.dy = 0;
    }
    _laidOut = true;
    final overlay = _overlay;
    if (overlay != null) {
      _place(overlay);
    }
    if (console != null) {
      _place(console);
    }
    final hint = _hint;
    if (hint != null) {
      _place(hint);
    }
  }

  /// Lays [panel] out and puts it in its place.
  void _place(RenderObject panel) {
    final at = panel.parentData;
    if (!identical(panel, _overlay)) {
      // the console or the line of the debug keys, at the bottom
      final h = _heightOf(panel, height);
      panel.layout(BoxConstraints.tight(width, h));
      at
        ..dx = 0
        ..dy = height - h;
    } else {
      final w = panel.getMaxIntrinsicWidth(height);
      final fits = w < width ? w : width;
      panel.layout(BoxConstraints.tight(fits, _heightOf(panel, height)));
      at
        ..dx = width - fits
        ..dy = 0;
    }
  }

  /// As tall as [panel] asks to be, at most [most].
  int _heightOf(RenderObject panel, int most) {
    final h = panel.getMaxIntrinsicHeight(width);
    return h < most ? h : most;
  }

  /// The deepest repaint boundary of the child that holds the cells [x],
  /// [y], [w] × [h] of this view; the view when none does.
  RenderObject _under(int x, int y, int w, int h) {
    RenderObject found = this;
    var o = child;
    var ox = 0;
    var oy = 0;
    while (o != null) {
      final at = o.parentData;
      ox += at.dx;
      oy += at.dy;
      if (x < ox || y < oy || x + w > ox + o.width || y + h > oy + o.height) {
        break;
      }
      if (o.isRepaintBoundary) {
        found = o;
      }
      RenderObject? next;
      final (px, py) = (ox, oy);
      o.visitChildren((c) {
        final at = c.parentData;
        final cx = px + at.dx;
        final cy = py + at.dy;
        if (next == null &&
            x >= cx &&
            y >= cy &&
            x + w <= cx + c.width &&
            y + h <= cy + c.height) {
          next = c;
        }
      });
      o = next;
    }
    return found;
  }

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (_rows != null) {
      _paintLines(ctx);
    } else if (child != null) {
      paintChild(ctx, child);
    }
    final highlight = _highlight;
    if (highlight != null && _rows == null) {
      paintHighlight(ctx, highlight);
    }
    final overlay = _overlay;
    if (overlay != null) {
      paintChild(ctx, overlay);
    }
    final console = _console;
    if (console != null) {
      paintChild(ctx, console);
    }
    final hint = _hint;
    if (hint != null) {
      paintChild(ctx, hint);
    }
  }

  /// Whether the outline or a panel painted after [child] reaches the
  /// cells.
  @override
  bool paintsOver(RenderObject child, int x, int y, int w, int h) {
    if (identical(child, this.child)) {
      return _rows == null &&
          (_outlines(x, y, w, h) ||
              _reaches(_overlay, x, y, w, h) ||
              _reaches(_console, x, y, w, h) ||
              _reaches(_hint, x, y, w, h));
    }
    return identical(child, _overlay) && _reaches(_console, x, y, w, h) ||
        !identical(child, _hint) && _reaches(_hint, x, y, w, h);
  }

  /// Paints the outline and the panels after [child] that reach the cells.
  @override
  void paintOver(
    PaintContext ctx,
    RenderObject child,
    int x,
    int y,
    int w,
    int h,
  ) {
    final app = identical(child, this.child);
    final highlight = _highlight;
    if (app && _outlines(x, y, w, h)) {
      paintHighlight(ctx, highlight!);
    }
    final overlay = _overlay;
    if (app && _reaches(overlay, x, y, w, h)) {
      paintChild(ctx, overlay!);
    }
    final console = _console;
    if ((app || identical(child, overlay)) && _reaches(console, x, y, w, h)) {
      paintChild(ctx, console!);
    }
    final hint = _hint;
    if (!identical(child, hint) && _reaches(hint, x, y, w, h)) {
      paintChild(ctx, hint!);
    }
  }

  /// Whether the outline of [highlight] reaches the cells [x], [y], [w] ×
  /// [h].
  bool _outlines(int x, int y, int w, int h) {
    final o = _highlight;
    return o != null && highlightReaches(o, x, y, w, h);
  }

  /// Whether [panel], when shown, reaches the cells [x], [y], [w] × [h].
  static bool _reaches(RenderObject? panel, int x, int y, int w, int h) {
    if (panel == null) {
      return false;
    }
    final at = panel.parentData;
    return at.dx < x + w &&
        x < at.dx + panel.width &&
        at.dy < y + h &&
        y < at.dy + panel.height;
  }
}
