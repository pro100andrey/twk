/// Popovers: a [Popover] shows a widget by another while the app says so.
///
/// @docImport 'menu.dart';
/// @docImport 'tooltip.dart';
library;

import 'dart:async';

import 'package:twk_core/twk_core.dart' show HitTestBehavior;

import '../animation/animation_controller.dart';
import '../animation/curves.dart';
import '../animation/switcher.dart' show Opacity;
import '../animation/ticker.dart';
import '../focus/focus_tree.dart';
import '../focus/shortcuts.dart';
import '../foundation/change_notifier.dart' show ChangeNotifier, VoidCallback;
import '../foundation/listenable_builder.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../layout/basic.dart';
import '../layout/stack.dart';
import 'anchor.dart';
import 'layer.dart';

// Examples can assume:
// var open = false;
// void setState(void Function() change) {}

/// Shows [popover] by [child] while [open], in an entry of the [Overlay]
/// above: under the child from its left edge; where it does not fit
/// there, on the side with more room, above the child, ending at its right
/// edge; moved in from the edges of the overlay as far as it has to. It
/// follows the child as that is laid out or scrolled somewhere else, from
/// the frame it moves in. With the overlay it repaints the rows it covers
/// only, and those between them and what else repaints.
///
/// [onDismiss] is called when the popover is to close: the focus went from
/// a node in [child] or in [popover] to one in neither, Escape was pressed
/// while it was in either (bound in a `KeyBindings` with the hint `close`,
/// which a `KeyHintsBar` lists while it is open), or a button was pressed
/// outside both. The app closes it by building it with [open] false; with
/// no [onDismiss] it stays open until then.
///
/// It fades in from what is under it over [fadeIn] as it opens and out
/// over [fadeOut] as it closes, easing out; zero, the default, shows it
/// and takes it away at once.
///
/// The popover takes no focus of its own: the keys go where the focus is.
/// Its nodes are under the node above the overlay, not under the child's,
/// so the keys it leaves go to the nodes above the overlay. Its entry is
/// inserted once the popover is first built, so one built open shows from
/// the frame after. Without an [Overlay] above it the build fails with a
/// [StateError] that says where to place one.
///
/// A button that opens a list of choices under it, closed again by
/// Escape, a click outside or the focus leaving:
///
/// ```dart
/// Popover(
///   open: open,
///   onDismiss: () => setState(() => open = false),
///   fadeIn: const Duration(milliseconds: 120),
///   fadeOut: const Duration(milliseconds: 100),
///   popover: Panel(
///     look: PanelLook.bordered,
///     child: Column(children: [Text('Copy'), Text('Paste')]),
///   ),
///   child: Button('Edit', onPressed: () => setState(() => open = true)),
/// )
/// ```
///
/// See also:
///
///  * [Tooltip], a message shown by its child while the mouse is over it.
///  * [Menu] and [ContextMenu], for a list of commands.
final class Popover extends StatefulWidget {
  /// Shows [popover] by [child] while [open], calling [onDismiss] when it
  /// is to close.
  const Popover({
    required this.open,
    required this.popover,
    required this.child,
    super.key,
    this.onDismiss,
    this.fadeIn = Duration.zero,
    this.fadeOut = Duration.zero,
    this.matchAnchorWidth = false,
  });

  /// Whether [popover] is at least as wide as [child], as far as the
  /// overlay is: a list under a field, the width of the field, following
  /// it in the frame it changes.
  final bool matchAnchorWidth;

  /// How long it takes to fade in as it opens; zero for at once.
  final Duration fadeIn;

  /// How long it takes to fade out as it closes; zero for at once.
  final Duration fadeOut;

  /// Whether [popover] shows.
  final bool open;

  /// What shows by [child].
  final Widget popover;

  /// What the popover shows by.
  final Widget child;

  /// Called when the popover is to close; null for one that does not.
  final VoidCallback? onDismiss;

  @override
  State<Popover> createState() => _PopoverState();
}

final class _PopoverState extends State<Popover>
    with TickerProviderStateMixin<Popover> {
  final _link = AnchorLink();
  late final _anchor = FocusNode(
    debugLabel: 'popover anchor',
    canRequestFocus: false,
    skipTraversal: true,
  )..addListener(_focusChanged);
  OverlayEntry? _entry;

  // how far it has faded in: 1 open, 0 closed
  late final _fade =
      AnimationController(
          vsync: this,
          duration: widget.fadeIn,
          reverseDuration: widget.fadeOut,
          value: widget.open ? 1 : 0,
        )
        ..addListener(_stepped)
        ..addStatusListener(_faded);

  // The entry is built by the overlay, maybe earlier in the build scope
  // this state is built in than this state, as when a step of the fade
  // marked its opacity: an element marked again in the scope it was built
  // in fails an assert. So this state marks the entry from its build only,
  // once a scope, and what didUpdateWidget does to the fade marks nothing.

  // what the entry's opacity is built again on: each step of _fade but
  // those didUpdateWidget makes, the entry being built again then anyway
  final _steps = _Steps();

  // in didUpdateWidget, starting, reversing or setting the fade
  var _updating = false;

  // what the entry shows changed: the build marks it
  var _entryChanged = false;

  // the node of what the popover shows, while it shows
  FocusNode? _inside;

  @override
  void initState() {
    super.initState();
    _insertSoon();
  }

  @override
  void didUpdateWidget(Popover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fade
      ..duration = widget.fadeIn
      ..reverseDuration = widget.fadeOut;
    if (widget.open != oldWidget.open) {
      _updating = true;
      try {
        if (widget.open && widget.fadeIn > Duration.zero) {
          _fade.forward();
        } else if (!widget.open && widget.fadeOut > Duration.zero) {
          _fade.reverse();
        } else {
          _fade.value = widget.open ? 1 : 0;
        }
      } finally {
        _updating = false;
      }
    }
    if (widget.open || oldWidget.open) {
      _entryChanged = true;
    }
  }

  void _stepped() {
    if (!_updating) {
      _steps.step();
    }
  }

  /// Faded out: what it showed is gone.
  void _faded(AnimationStatus status) {
    // in didUpdateWidget, it was open: the entry is marked changed there
    if (status == AnimationStatus.dismissed && !widget.open && !_updating) {
      setState(() => _entryChanged = true);
    }
  }

  @override
  void activate() {
    super.activate();
    _insertSoon();
  }

  @override
  void deactivate() {
    _entry?.remove();
    _entry = null;
    super.deactivate();
  }

  @override
  void dispose() {
    _entry?.remove();
    _anchor.dispose();
    _fade.dispose();
    _steps.dispose();
    super.dispose();
  }

  /// Inserts the entry after the build, which an overlay is not changed in.
  void _insertSoon() => scheduleMicrotask(() {
    final overlay = mounted ? Overlay.maybeOf(context) : null;
    if (overlay != null && _entry == null) {
      overlay.insert(
        _entry = OverlayEntry(
          builder: _layer,
          fadeIn: Duration.zero,
          fadeOut: Duration.zero,
        ),
      );
    }
  });

  void _dismiss() {
    if (widget.open) {
      widget.onDismiss?.call();
    }
  }

  void _focusChanged() {
    if (mounted && !_anchor.hasFocus && !(_inside?.hasFocus ?? false)) {
      _dismiss();
    }
  }

  /// Escape, bound while it is open and can be dismissed.
  Widget _escape(Widget child) {
    final closes = widget.open && widget.onDismiss != null;
    return KeyBindings(
      closes ? {'escape': _dismiss} : const {},
      hints: closes ? const {'escape': 'close'} : const {},
      debugLabel: 'popover',
      child: child,
    );
  }

  void _pressed(PointerEvent event) {
    if (!_link.covers(event.x, event.y)) {
      _dismiss();
    }
  }

  Widget _layer(BuildContext context) {
    if (!widget.open && _fade.status == AnimationStatus.dismissed) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }
    return _Inside(
      this,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onDown: _pressed,
        child: AnchorFollower(
          link: _link,
          matchTargetWidth: widget.matchAnchorWidth,
          child: ListenableBuilder(
            listenable: _steps,
            builder: (context, child) => Opacity(
              opacity: widget.open
                  ? Curves.easeOut.transform(_fade.value)
                  : 1 - Curves.easeOut.transform(1 - _fade.value),
              child: child,
            ),
            child: _escape(widget.popover),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Overlay.maybeOf(context) == null) {
      throw StateError(
        'Popover: no Overlay above it: place an Overlay above it, as '
        'around the whole app: Overlay(child: …)',
      );
    }
    if (_entryChanged) {
      _entryChanged = false;
      _entry?.markNeedsBuild();
    }
    return AnchorTarget(
      link: _link,
      child: Focus(focusNode: _anchor, child: _escape(widget.child)),
    );
  }
}

/// Tells its listeners of a step of a [Popover]'s fade.
final class _Steps extends ChangeNotifier {
  void step() => notifyListeners();
}

/// What a [Popover] shows, under a node of the focus tree the popover
/// watches while it is there.
final class _Inside extends StatefulWidget {
  const _Inside(this.popover, {required this.child});

  final _PopoverState popover;
  final Widget child;

  @override
  State<_Inside> createState() => _InsideState();
}

final class _InsideState extends State<_Inside> {
  late final _node = FocusNode(
    debugLabel: 'popover',
    canRequestFocus: false,
    skipTraversal: true,
  )..addListener(widget.popover._focusChanged);

  @override
  void initState() {
    super.initState();
    widget.popover._inside = _node;
  }

  @override
  void dispose() {
    if (identical(widget.popover._inside, _node)) {
      widget.popover._inside = null;
    }
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _node, child: widget.child);
}
