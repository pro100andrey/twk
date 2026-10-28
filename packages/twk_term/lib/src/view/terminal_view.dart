/// A program's terminal as a widget: [TerminalSession], the program and
/// the emulator of its terminal, and [TerminalView], which shows its
/// screen and gives it the keys, the mouse, pastes, focus and its size.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show PipelineOwner, kBlank, kWide;

import '../emulator/buffer.dart';
import '../emulator/emulator.dart';
import '../emulator/events.dart';
import '../emulator/modes.dart';
import '../pty/pty.dart' if (dart.library.js_interop) '../pty/pty_web.dart';

part 'render_terminal.dart';
part 'terminal_session.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// late TerminalSession session;

/// Shows the screen of [session]'s program and gives the program its
/// input, as a terminal window does: the view is the program's terminal,
/// as big as the view (the session is resized to it at each layout,
/// which tells the program, SIGWINCH for a [Pty]).
///
/// While it has the focus, every key goes to the program, encoded as the
/// program's modes want it ([TerminalEmulator.sendKey]: application cursor
/// keys, the kitty keyboard protocol when the program pushed its flags),
/// Tab, Ctrl+C and Escape among them; none goes up to the nodes above its
/// [Focus], but those [ignoredKeys] names (as `KeyBindings` names keys:
/// `'ctrl+q'`, `'alt+1'`) and the releases the program doesn't hear of. A
/// key pressed while the view shows its scrollback brings it back to the
/// screen. A paste goes to the program as typed, bracketed when it asked
/// (mode 2004). The program is told when the view gains or loses the
/// focus, and when the app's terminal does, if it asked (mode 1004).
///
/// A press of the mouse focuses the view. While the program tracks the
/// mouse (modes 9, 1000, 1002, 1003) it is told of presses, releases,
/// the wheel and, as its mode asks, motion, at the cell of the view; the
/// view asks the app's terminal for motion only while the program wants
/// it. Otherwise the wheel scrolls the view [wheelLines] lines through
/// the scrollback, or on the alternate screen (which keeps none) sends as
/// many Up or Down keys, as most terminals do.
///
/// The terminal's cursor shows the program's, in the shape it set
/// (DECSCUSR), while the view has the focus and the program shows it
/// (DECTCEM). While the program draws a frame in synchronized output
/// (mode 2026) the view shows the screen as it was, until the mode is
/// reset or 150 ms passed.
///
/// The program's default text color and background are painted in those
/// of [defaultStyle], by default the theme's text on its background, as
/// the rest of the app is; and they are what the program is told when it
/// asks for them (OSC 10, 11, and the dark or light of CSI ? 996 n) —
/// the view keeps the emulator's [TerminalEmulator.defaultForeground] and
/// [TerminalEmulator.defaultBackground] at the colors it paints, the
/// host terminal's own where those are [Color.defaultColor] and the host
/// told them. Colors the program sets (OSC 10, 11) are reported back to it
/// but not painted.
///
/// What the program asks of its terminal beyond the screen is told to
/// the callbacks: [onTitleChanged], [onBell], [onClipboardWrite],
/// [onClipboardRead], which answers with the text it returns (none for
/// null), and [onEvent] for every [TerminalEvent]. Nothing is done
/// without them.
///
/// A repaint boundary: what the program writes repaints the view alone,
/// only the rows that changed, and rows the program scrolled move on the
/// screen in hardware (`Surface.scrollRect`) where the view is wholly
/// visible, the rows the scroll exposed painted. It takes all the room it
/// gets; along an axis with no bound it is as big as the session's
/// terminal.
///
/// A shell that has the focus from the start, Ctrl+Q left to a
/// `KeyBindings` above it, its title shown above it:
///
/// ```dart
/// Column(
///   children: [
///     ListenableBuilder(
///       listenable: session,
///       builder: (context, _) => Text(session.title),
///     ),
///     Expanded(
///       child: TerminalView(
///         session: session,
///         autofocus: true,
///         ignoredKeys: const ['ctrl+q'],
///       ),
///     ),
///   ],
/// )
/// ```
final class TerminalView extends StatefulWidget {
  /// Shows [session]'s program and gives it the input.
  const TerminalView({
    required this.session,
    super.key,
    this.focusNode,
    this.autofocus = false,
    this.ignoredKeys = const [],
    this.wheelLines = 3,
    this.defaultStyle,
    this.onTitleChanged,
    this.onBell,
    this.onClipboardWrite,
    this.onClipboardRead,
    this.onEvent,
  });

  /// The program and its terminal; the view does not dispose it.
  final TerminalSession session;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// Keys the view leaves to the nodes above it, as `KeyBindings` names
  /// them (`'ctrl+q'`); a [FormatException] for a name that is not one.
  final List<String> ignoredKeys;

  /// The lines a turn of the wheel scrolls the scrollback by, or the Up
  /// and Down keys it sends on the alternate screen.
  final int wheelLines;

  /// The colors the program's default text color ([Style.fg]) and
  /// background ([Style.bg]) are painted in; the rest of the style is not
  /// used, and a color it leaves unset is the theme's. Null for the
  /// [Theme]'s [ThemeData.text] on its [ThemeData.background].
  final Style? defaultStyle;

  /// The program set the window title (OSC 0, 2).
  final void Function(String title)? onTitleChanged;

  /// The program rang the bell.
  final void Function()? onBell;

  /// The program put `text` on the clipboard named by `selection` (OSC
  /// 52; see [ClipboardWrite]).
  final void Function(String selection, String text)? onClipboardWrite;

  /// The program asked for the clipboard named by `selection`; what this
  /// returns, or completes with, is sent to it, null nothing.
  final FutureOr<String?> Function(String selection)? onClipboardRead;

  /// Every event of the program, before the callbacks above.
  final void Function(TerminalEvent event)? onEvent;

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

final class _TerminalViewState extends State<TerminalView> {
  FocusNode? _ownNode;
  StreamSubscription<TerminalEvent>? _events;
  var _ignored = const <KeyCombo>[];
  _RenderTerminal? _render;

  // whether the program was told it has the focus, and whether the app's
  // terminal has it
  var _toldFocus = false;
  var _appFocused = true;

  FocusNode get _node =>
      widget.focusNode ?? (_ownNode ??= FocusNode(debugLabel: 'TerminalView'));

  TerminalEmulator get _emulator => widget.session.emulator;

  @override
  void initState() {
    super.initState();
    _events = widget.session.events.listen(_onEvent);
    _node.addListener(_focusChanged);
    _ignored = _parse(widget.ignoredKeys);
  }

  @override
  void didUpdateWidget(TerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, oldWidget.session)) {
      unawaited(_events?.cancel());
      _events = widget.session.events.listen(_onEvent);
      _toldFocus = false;
      _tellFocus();
    }
    final old = oldWidget.focusNode ?? _ownNode;
    if (!identical(old, _node)) {
      old?.removeListener(_focusChanged);
      _node.addListener(_focusChanged);
    }
    if (!_same(widget.ignoredKeys, oldWidget.ignoredKeys)) {
      _ignored = _parse(widget.ignoredKeys);
    }
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    _node.removeListener(_focusChanged);
    _ownNode?.dispose();
    super.dispose();
  }

  static List<KeyCombo> _parse(List<String> keys) => [
    for (final k in keys) KeyCombo.parse(k),
  ];

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  void _focusChanged() {
    _tellFocus();
    setState(() {});
  }

  /// Tells the program of a change of the focus, the view's and the app's
  /// terminal's together.
  void _tellFocus() {
    final focused = _node.hasFocus && _appFocused;
    if (focused != _toldFocus) {
      _toldFocus = focused;
      _emulator.sendFocus(focused: focused);
    }
  }

  void _onEvent(TerminalEvent event) {
    final w = widget;
    w.onEvent?.call(event);
    switch (event) {
      case TitleChanged(:final title):
        w.onTitleChanged?.call(title);
      case BellRang():
        w.onBell?.call();
      case ClipboardWrite(:final selection, :final text):
        w.onClipboardWrite?.call(selection, text);
      case ClipboardRead(:final selection):
        final read = w.onClipboardRead?.call(selection);
        final session = w.session;
        void answer(String? text) {
          if (text != null && !session.ended) {
            session.emulator.answerClipboard(selection, text);
          }
        }

        if (read is Future<String?>) {
          unawaited(read.then(answer));
        } else {
          answer(read);
        }
      case ModeChanged(:final mode) when _mouseModes.contains(mode):
        // the callbacks of the Listener follow the program's mode
        if (mounted) {
          setState(() {});
        }
      default:
        break;
    }
  }

  static const Set<TerminalMode> _mouseModes = {
    TerminalMode.mouseX10,
    TerminalMode.mouseButtons,
    TerminalMode.mouseDrags,
    TerminalMode.mouseMotion,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!node.hasFocus) {
      return KeyEventResult.ignored;
    }
    for (final combo in _ignored) {
      if (combo.accepts(event)) {
        return KeyEventResult.ignored;
      }
    }
    if (!_emulator.sendKey(event)) {
      return KeyEventResult.ignored;
    }
    if (event.kind != KeyKind.release) {
      _render?.scrollBack(-_render!.scrollOffset);
    }
    return KeyEventResult.handled;
  }

  bool _onInput(InputEvent event) {
    switch (event) {
      case PasteEvent(:final text) when _node.hasFocus:
        _emulator.sendPaste(text);
        _render?.scrollBack(-_render!.scrollOffset);
        return true;
      case FocusEvent(:final focused):
        _appFocused = focused;
        _tellFocus();
        return false;
      default:
        return false;
    }
  }

  void _down(PointerEvent event) {
    _node.requestFocus();
    _mouse(event);
  }

  void _mouse(PointerEvent event) => _emulator.sendMouse(
    MouseEvent(
      event.kind,
      event.x,
      event.y,
      button: event.button,
      modifiers: event.modifiers,
    ),
  );

  void _scroll(PointerEvent event) {
    final em = _emulator;
    if (em.mouseProtocol != MouseProtocol.off) {
      _mouse(event);
      return;
    }
    final lines = event.scrollY * widget.wheelLines;
    if (lines == 0) {
      return;
    }
    if (em.alternateScreen) {
      final key = KeyEvent(lines < 0 ? KeyCode.up : KeyCode.down);
      for (var i = 0; i < lines.abs(); i++) {
        em.sendKey(key);
      }
      return;
    }
    _render?.scrollBack(-lines);
  }

  /// The theme's text on its background, [TerminalView.defaultStyle] over
  /// them.
  Style _defaults(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.background.merge(theme.text);
    final own = widget.defaultStyle;
    return own == null ? base : base.merge(own);
  }

  @override
  Widget build(BuildContext context) {
    final protocol = _emulator.mouseProtocol;
    final tracked = protocol != MouseProtocol.off;
    final drags =
        protocol == MouseProtocol.drags || protocol == MouseProtocol.motion;
    return InputListener(
      onEvent: _onInput,
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        onKeyEvent: _onKey,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onDown: _down,
          onUp: tracked ? _mouse : null,
          onDrag: drags ? _mouse : null,
          onMove: protocol == MouseProtocol.motion ? _mouse : null,
          onScroll: _scroll,
          child: _View(
            this,
            widget.session,
            focused: _node.hasFocus,
            defaults: _defaults(context),
          ),
        ),
      ),
    );
  }
}

/// The screen of a [TerminalView]'s session, the cursor shown while
/// [focused], the default colors in those of [defaults].
final class _View extends LeafRenderObjectWidget {
  const _View(
    this.state,
    this.session, {
    required this.focused,
    required this.defaults,
  });

  final _TerminalViewState state;
  final TerminalSession session;
  final bool focused;
  final Style defaults;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      state._render = _RenderTerminal(session)
        ..focused = focused
        ..setDefaultColors(defaults.fg, defaults.bg);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderTerminal renderObject,
  ) {
    state._render = renderObject
      ..session = session
      ..focused = focused
      ..setDefaultColors(defaults.fg, defaults.bg);
  }
}
