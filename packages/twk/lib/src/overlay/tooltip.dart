/// Tooltips: a [Tooltip] shows a message by its child while the mouse
/// rests on it or the focus is in it, or while a [TooltipController] says.
///
/// @docImport 'popover.dart';
library;

import 'dart:async';

import 'package:twk_core/twk_core.dart'
    show Brightness, EdgeInsets, KeyCode, KeyEvent, KeyKind;

import '../focus/focus_tree.dart';
import '../foundation/change_notifier.dart';
import '../foundation/controller_host.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../layout/box.dart';
import '../semantics/semantics.dart';
import '../style/color_mix.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'anchor.dart';
import 'layer.dart';
import 'panel.dart';

// Examples can assume:
// void openHelp() {}

/// Whether the [Tooltip] it is given to shows its message: [show] and
/// [hide] for an app or a route to open and close it, [isShown] for what
/// the mouse and the focus did as well. It notifies its listeners each
/// time [isShown] changes.
///
/// It serves one tooltip at a time. Shown before that tooltip is built,
/// the tooltip shows once it is; given to another tooltip, it no longer
/// shows this one; given to one built in place of its tooltip (a key
/// changed), that one shows the message on.
///
/// A tooltip that only the app shows, as a first-run hint:
///
/// ```dart
/// final hint = TooltipController();
/// final help = Tooltip(
///   message: 'Press ? for the keys',
///   controller: hint,
///   showOnHover: false,
///   showOnFocus: false,
///   child: Text('?'),
/// );
/// hint.show();
/// ```
final class TooltipController extends ChangeNotifier {
  final _hosts = ControllerHost<_TooltipState>();
  var _shown = false;

  /// Whether the message shows.
  bool get isShown => _shown;

  /// Shows the message at once, without [Tooltip.wait], until [hide], or
  /// Escape while the focus is in the child: neither the mouse nor the
  /// focus leaving hides it.
  void show() {
    if (_hosts.host case final tooltip?) {
      tooltip._pin();
    } else {
      _set(shown: true);
    }
  }

  /// Hides the message, however it was shown; the mouse entering the child
  /// again, or the focus, shows it again.
  void hide() {
    if (_hosts.host case final tooltip?) {
      tooltip._hide();
    } else {
      _set(shown: false);
    }
  }

  void _set({required bool shown}) {
    if (shown != _shown) {
      _shown = shown;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _hosts.dispose();
    super.dispose();
  }
}

/// Shows [message] by [child] once the mouse has rested on it for [wait]
/// ([showOnHover]), until it leaves, or once the keyboard focus has rested
/// in it as long ([showOnFocus]), until the focus leaves or Escape is
/// pressed, which goes no further then; [controller] shows and hides it
/// too. It shows on a chip that stands out of what it is over, a blank
/// either side of the message (light on a dark theme: the theme's surface
/// a fifth of the way to its text, in its text; dark on a light one: the
/// text a little towards the background, in the background's color), in
/// an entry of the [Overlay] above it, centred under the child, above it
/// when there is no room below, and moved in from the sides of the overlay
/// as far as it fits. It fades in over [fadeIn]. With [look]
/// [PanelLook.bordered], it is in a box of the theme's surface with a
/// border instead.
///
/// While one of the mouse and the focus holds it, the other leaving does
/// not hide it. A screen reader reads [message] as the hint of [child]
/// ([Semantics.hint]), shown or not: `button Help, Opens help`; the chip
/// is not read.
///
/// The mouse is on it where a [MouseRegion] around [child] is hit; as the
/// mouse only gets there when the terminal reports it, an app in the
/// inline mode shows no tooltips.
///
/// Without an [Overlay] above it the build fails with a [StateError] that
/// says where to place one.
///
/// A button whose tooltip says what it does:
///
/// ```dart
/// Tooltip(
///   message: 'Opens help',
///   child: Button('Help', onPressed: openHelp),
/// )
/// ```
///
/// See also:
///
///  * [Popover], for more than a message, open while the app says.
final class Tooltip extends StatefulWidget {
  /// Shows [message] by [child] after the mouse or the focus has rested on
  /// it for [wait], half a second by default.
  const Tooltip({
    required this.message,
    required this.child,
    super.key,
    this.wait = const Duration(milliseconds: 500),
    this.look = PanelLook.raised,
    this.fadeIn = const Duration(milliseconds: 100),
    this.showOnHover = true,
    this.showOnFocus = true,
    this.controller,
  });

  /// What the tooltip says.
  final String message;

  /// What the message shows by, and the mouse and the focus rest on.
  final Widget child;

  /// Whether the mouse resting on [child] shows the message.
  final bool showOnHover;

  /// Whether the keyboard focus resting in [child] (on it or on a node
  /// below it) shows the message.
  final bool showOnFocus;

  /// Shows and hides the message, and says whether it shows; with
  /// [showOnHover] and [showOnFocus] off, the only one that does.
  final TooltipController? controller;

  /// How long the mouse, or the focus, rests on [child] before the message
  /// shows.
  final Duration wait;

  /// The chip ([PanelLook.raised]) or a bordered box.
  final PanelLook look;

  /// How long the message takes to fade in; zero for at once.
  final Duration fadeIn;

  /// The style of a tooltip's chip in [theme]: on a dark theme the
  /// surface a fifth of the way to the text, in the text; on a light one
  /// the text 8 % of the way to the background, in the background's color.
  /// Where those are not RGB, the theme's selection and text.
  static Style chipStyleOf(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    final bg = dark
        ? mixRgb(theme.surface.bg, theme.text.fg, 0.2)
        : mixRgb(theme.text.fg, theme.background.bg, 0.08);
    final fg = dark ? theme.text.fg : theme.background.bg;
    if (bg == null || fg == null) {
      return theme.selection.merge(theme.text);
    }
    return Style(fg: fg, bg: bg);
  }

  @override
  State<Tooltip> createState() => _TooltipState();
}

final class _TooltipState extends State<Tooltip> {
  final _link = AnchorLink();
  late final _anchor = FocusNode(
    debugLabel: 'tooltip',
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _key,
  )..addListener(_focusChanged);
  Timer? _timer;
  OverlayEntry? _entry;

  // the mouse is on the child; the focus is in it, as last told
  var _hovered = false;
  var _focused = false;

  // shown by the controller: only it, and Escape, hide it
  var _pinned = false;

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
  }

  @override
  void didUpdateWidget(Tooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message != oldWidget.message) {
      _entry?.markNeedsBuild();
    }
    if (widget.controller != oldWidget.controller) {
      _detach(oldWidget.controller);
      _unpin();
      _attach(widget.controller);
    }
  }

  // out of the tree, the message goes; the controller still says it
  // shows, for the tooltip built in this one's place to show it, or this
  // one put back
  @override
  void deactivate() {
    _hide(tell: false);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _pinAfterBuild(widget.controller);
  }

  @override
  void dispose() {
    _hide(tell: false);
    _detach(widget.controller);
    _anchor.dispose();
    super.dispose();
  }

  /// Serves [controller], in place of the tooltip that did, showing the
  /// message after this build where it was shown before.
  void _attach(TooltipController? controller) {
    controller?._hosts.attach(this);
    _pinAfterBuild(controller);
  }

  /// Shows the message after this build where [controller], served by
  /// this tooltip, says it shows: an overlay is not changed in a build.
  void _pinAfterBuild(TooltipController? controller) {
    if (controller != null && controller.isShown) {
      controller._hosts.afterBuild(() {
        if (mounted &&
            controller._hosts.isHost(this) &&
            controller.isShown &&
            !_pinned) {
          _pin();
        }
      });
    }
  }

  /// Lets go of [controller]: where no tooltip takes it over, it says the
  /// message no longer shows, after the build.
  void _detach(TooltipController? controller) =>
      controller?._hosts.detach(this, () => controller._set(shown: false));

  // what holds the message there, as the triggers are on
  bool get _byMouse => _hovered && widget.showOnHover;
  bool get _byFocus => _focused && widget.showOnFocus;

  void _enter(PointerEvent event) {
    _hovered = true;
    if (widget.showOnHover) {
      _wait();
    }
  }

  void _exit(PointerEvent event) {
    _hovered = false;
    if (!_pinned && !_byFocus) {
      _hide();
    }
  }

  void _focusChanged() {
    final focused = _anchor.hasFocus;
    if (!mounted || focused == _focused) {
      return;
    }
    _focused = focused;
    if (focused) {
      if (widget.showOnFocus) {
        _wait();
      }
    } else if (!_pinned && !_byMouse) {
      _hide();
    }
  }

  /// Escape, from the child or below it: hides the message, if it shows.
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event
        case KeyEvent(
          code: KeyCode.escape,
          modifiers: 0,
          :final kind,
        )
        when kind != KeyKind.release) {
      final shown = _entry != null;
      _hide();
      if (shown) {
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Shows the message after [Tooltip.wait], unless it shows.
  void _wait() {
    if (_entry != null) {
      return;
    }
    _timer?.cancel();
    _timer = Timer(widget.wait, _show);
  }

  /// Shows the message until the controller or Escape hides it.
  void _pin() {
    _pinned = true;
    _show();
  }

  /// What the old controller showed goes, unless the mouse or the focus
  /// holds it.
  void _unpin() {
    if (!_pinned) {
      return;
    }
    _pinned = false;
    if (!_byMouse && !_byFocus) {
      _hide();
    }
  }

  void _show() {
    _timer?.cancel();
    _timer = null;
    if (_entry == null) {
      final entry = _entry = OverlayEntry(
        builder: (context) => AnchorFollower(
          link: _link,
          centred: true,
          // the child's hint says it
          child: ExcludeSemantics(
            child: _box(context, widget.message, widget.look),
          ),
        ),
        fadeIn: widget.fadeIn,
        fadeOut: Duration.zero,
      );
      Overlay.of(context).insert(entry);
    }
    if (widget.controller case final controller?
        when controller._hosts.isHost(this)) {
      controller._set(shown: true);
    }
  }

  /// Hides the message, telling the controller unless not to [tell].
  void _hide({bool tell = true}) {
    _timer?.cancel();
    _timer = null;
    _pinned = false;
    _entry?.remove();
    _entry = null;
    if (widget.controller case final controller?
        when tell && controller._hosts.isHost(this)) {
      controller._set(shown: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Overlay.maybeOf(context) == null) {
      throw StateError(
        'Tooltip: no Overlay above it: place an Overlay above it, as App does '
        'around the whole app: App(child: …)',
      );
    }
    return AnchorTarget(
      link: _link,
      child: Semantics(
        hint: widget.message,
        child: Focus(
          focusNode: _anchor,
          child: MouseRegion(
            onEnter: _enter,
            onExit: _exit,
            child: widget.child,
          ),
        ),
      ),
    );
  }

  static Widget _box(BuildContext context, String message, PanelLook look) {
    final theme = Theme.of(context);
    if (look == PanelLook.bordered) {
      return Box(
        style: theme.surface.merge(theme.text),
        border: Border.all(style: theme.border),
        padding: const EdgeInsets.x(1),
        child: Text(message),
      );
    }
    return Box(
      style: Tooltip.chipStyleOf(theme),
      padding: const EdgeInsets.x(1),
      child: Text(message),
    );
  }
}
