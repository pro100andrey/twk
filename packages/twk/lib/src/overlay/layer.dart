/// The layer over a part of the tree: an [Overlay] shows the widgets of its
/// [OverlayEntry]s over its child, the dialogs, toasts and tooltips of the
/// widgets below it.
library;

import '../animation/animation_controller.dart';
import '../animation/curves.dart';
import '../animation/switcher.dart' show Opacity;
import '../animation/ticker.dart';
import '../foundation/listenable_builder.dart';
import '../framework/framework.dart';
import '../layout/basic.dart';
import '../layout/stack.dart';

// Examples can assume:
// late BuildContext context;

/// Shows [child], and over it the widgets its entries build, each entry
/// over those inserted below it ([OverlayState.insert]); the widgets below
/// find the nearest one with [Overlay.of] and put their dialogs
/// (`showDialog`), toasts (`showToast`) and tooltips (`Tooltip`) in it.
///
/// It is as big as [child], which it lays out as if it were not there. An
/// entry's widget is laid out at its size, over all of it, unless it is a
/// [Positioned], which places it as in a [Stack]; what sticks out is cut
/// off. What an entry paints covers what is under it: [child] and the
/// entries below, also where those repaint on their own.
///
/// An app places one itself, as a rule around all of it and under its
/// `Theme`, so that what goes in it sees the theme, and with it the cells
/// it may cover: `Theme(data: …, child: Overlay(child: Home()))`. A
/// `Navigator` holds one of its own over its routes.
///
/// An app whose dialogs, toasts and tooltips show over all of it, in its
/// theme:
///
/// ```dart
/// Theme(
///   data: ThemeData.dark,
///   child: Overlay(child: Text('the app')),
/// )
/// ```
final class Overlay extends StatefulWidget {
  /// Shows [child] under the entries inserted in it.
  const Overlay({required this.child, super.key});

  /// What the entries are shown over.
  final Widget child;

  /// The state of the nearest [Overlay] above [context]; a [StateError]
  /// that says where to place one if there is none.
  static OverlayState of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError(
        'no Overlay above ${context.widget.runtimeType}: place an Overlay '
        'above it, as around the whole app: Overlay(child: …)',
      ));

  /// The state of the nearest [Overlay] above [context], if there is one.
  static OverlayState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_OverlayScope>()?.overlay;

  @override
  State<Overlay> createState() => OverlayState();
}

/// The entries an [Overlay] shows, in the order it paints them.
///
/// The widgets below the overlay reach it with [Overlay.of]. A banner put
/// under the entries shown, as a backdrop of theirs:
///
/// ```dart
/// final overlay = Overlay.of(context);
/// final banner = OverlayEntry(builder: (context) => Text('offline'));
/// overlay.insert(banner, below: overlay.entries.firstOrNull);
/// ```
final class OverlayState extends State<Overlay> {
  // the entries shown, and those fading out, in the order they paint
  final _slots = <_Slot>[];

  /// The entries shown, the bottom one first; not those fading out.
  List<OverlayEntry> get entries => List.unmodifiable([
    for (final slot in _slots)
      if (!slot.leaving) slot.entry,
  ]);

  /// Shows [entry] over the entries shown, or right over [above] or right
  /// under [below], an entry shown; from the next build of the app on. An
  /// entry is in one overlay at a time, and inserted outside a build: from
  /// input, a timer, a future. An entry inserted while it fades out of
  /// this overlay fades back in from where it is.
  void insert(OverlayEntry entry, {OverlayEntry? above, OverlayEntry? below}) {
    assert(entry._overlay == null, '$entry is in an overlay already');
    assert(above == null || below == null, 'above or below, not both');
    final at = above ?? below;
    final i = at == null ? -1 : _indexOf(at);
    if (at != null && i < 0) {
      throw ArgumentError.value(
        at,
        above != null ? 'above' : 'below',
        'not shown in this overlay',
      );
    }
    setState(() {
      _slots.removeWhere((slot) => identical(slot.entry, entry));
      final index = at == null
          ? _slots.length
          : _indexOf(at) + (above != null ? 1 : 0);
      final slot = _Slot(entry);
      entry
        .._overlay = this
        .._slot = slot;
      _slots.insert(index, slot);
    });
  }

  int _indexOf(OverlayEntry entry) =>
      _slots.indexWhere((s) => identical(s.entry, entry) && !s.leaving);

  void _remove(_Slot slot) => _slots.remove(slot);

  /// [slot] has faded out: the overlay builds without it.
  void _gone(_Slot slot) {
    if (mounted && _slots.contains(slot)) {
      setState(() => _slots.remove(slot));
    }
  }

  @override
  void dispose() {
    for (final slot in _slots) {
      if (identical(slot.entry._slot, slot)) {
        slot.entry
          .._overlay = null
          .._slot = null;
      }
    }
    _slots.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _OverlayScope(
    this,
    child: Stack(
      fit: StackFit.passthrough,
      children: [widget.child, for (final slot in _slots) slot.widget],
    ),
  );
}

/// An entry in its overlay's stack: what shows it, new at each insertion,
/// and whether it is fading out.
final class _Slot {
  _Slot(this.entry) {
    widget = _EntryHost(this, key: ObjectKey(entry));
  }

  final OverlayEntry entry;
  late final Widget widget;
  var leaving = false;
}

/// A layer of an [Overlay]: the widget [builder] builds, shown while the
/// entry is inserted ([OverlayState.insert]) until [remove]. It is built
/// when inserted and when [markNeedsBuild] says so, on its own, as a
/// widget's build: the context is the entry's, under the overlay, which
/// sees what is above the overlay.
///
/// It fades in from what is under it as it is inserted, over [fadeIn]
/// ([Opacity], easing out), and fades out over [fadeOut] once removed,
/// still built meanwhile: 160 and 120 ms by default; [Duration.zero] shows
/// it, or takes it away, at once.
///
/// A note in the bottom right corner of the overlay above `context`, taken
/// away again by `note.remove()`:
///
/// ```dart
/// final note = OverlayEntry(
///   builder: (context) => Positioned(
///     right: 1,
///     bottom: 1,
///     child: Box(border: const Border.all(), child: Text('Saved')),
///   ),
/// );
/// Overlay.of(context).insert(note);
/// ```
final class OverlayEntry {
  /// An entry of the widget [builder] builds, which fades in over [fadeIn]
  /// and out over [fadeOut].
  OverlayEntry({
    required this.builder,
    this.fadeIn = const Duration(milliseconds: 160),
    this.fadeOut = const Duration(milliseconds: 120),
  });

  /// Builds the widget of the entry, a [Positioned] to place it.
  final Widget Function(BuildContext context) builder;

  /// How long it takes to fade in once inserted; zero for at once.
  final Duration fadeIn;

  /// How long it takes to fade out once removed; zero for at once.
  final Duration fadeOut;

  OverlayState? _overlay;

  // where its overlay shows it, new at each insertion
  _Slot? _slot;

  // the state of the widget that shows the entry now
  _EntryHostState? _host;

  /// Whether the entry is in an overlay; not while it fades out of one.
  bool get mounted => _overlay != null;

  /// Takes the entry out of its overlay, if it is in one: it fades out
  /// over [fadeOut], then its widget is gone, where it is, the other
  /// entries not built again; with no [fadeOut], from the next build of
  /// the app on. It may be inserted again.
  void remove() {
    final overlay = _overlay;
    final slot = _slot;
    if (overlay == null || slot == null) {
      return;
    }
    _overlay = null;
    _slot = null;
    final host = _host;
    if (host != null && fadeOut > Duration.zero) {
      slot.leaving = true;
      host._leave(() => overlay._gone(slot));
      return;
    }
    overlay._remove(slot);
    _host = null;
    host?._hide();
  }

  /// Builds the entry again at the next build of the app, and no other
  /// entry, nor what is under them.
  void markNeedsBuild() => _host?._changed();

  @override
  String toString() {
    final hash = identityHashCode(this).toUnsigned(20).toRadixString(16);
    return 'OverlayEntry#${hash.padLeft(5, '0')}';
  }
}

/// Shows an [OverlayEntry] in the stack of its overlay: what its builder
/// builds, filling the overlay unless it is a [Positioned], at the opacity
/// of its fade; nothing once the entry was removed, until the overlay
/// builds without it; nothing either where the entry was removed before
/// the host was built for [slot], as it is in a build the overlay's own
/// already made.
final class _EntryHost extends StatefulWidget {
  const _EntryHost(this.slot, {super.key});

  final _Slot slot;

  OverlayEntry get entry => slot.entry;

  // the entry was removed since it was inserted for this host
  bool get removed => !identical(entry._slot, slot);

  @override
  State<_EntryHost> createState() => _EntryHostState();
}

final class _EntryHostState extends State<_EntryHost>
    with TickerProviderStateMixin<_EntryHost> {
  var _shown = true;

  late final _fade = AnimationController(
    vsync: this,
    duration: widget.entry.fadeIn,
    reverseDuration: widget.entry.fadeOut,
  );

  // called once it has faded out
  void Function()? _out;

  @override
  void initState() {
    super.initState();
    if (widget.removed) {
      _shown = false;
      return;
    }
    widget.entry._host = this;
    _fade.addStatusListener(_faded);
    _fadeIn();
  }

  @override
  void didUpdateWidget(_EntryHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.removed) {
      // and removed again before this build: hidden, or fading out, by
      // remove
      return;
    }
    // inserted again while the overlay still had it, or while it faded out
    _shown = true;
    _out = null;
    widget.entry._host = this;
    _fadeIn();
  }

  @override
  void dispose() {
    if (identical(widget.entry._host, this)) {
      widget.entry._host = null;
    }
    _fade.dispose();
    super.dispose();
  }

  void _fadeIn() {
    if (widget.entry.fadeIn > Duration.zero) {
      _fade.forward();
    } else {
      _fade.value = 1;
    }
  }

  /// Fades out, then calls [out].
  void _leave(void Function() out) {
    _out = out;
    _fade.reverse();
  }

  void _faded(AnimationStatus status) {
    final out = _out;
    if (status == AnimationStatus.dismissed && out != null) {
      _out = null;
      if (identical(widget.entry._host, this)) {
        widget.entry._host = null;
      }
      setState(() => _shown = false);
      out();
    }
  }

  void _hide() => setState(() => _shown = false);

  void _changed() => setState(() {});

  /// How much of the entry shows: easing out of what is under it as it
  /// fades in, easing into it as it fades out.
  double get _opacity {
    final v = _fade.value;
    return _out == null
        ? Curves.easeOut.transform(v)
        : 1 - Curves.easeOut.transform(1 - v);
  }

  @override
  Widget build(BuildContext context) {
    if (!_shown) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }
    final built = widget.entry.builder(context);
    Widget fade(Widget child) => ListenableBuilder(
      listenable: _fade,
      builder: (context, child) => Opacity(opacity: _opacity, child: child),
      child: child,
    );
    if (built is Positioned) {
      return Positioned(
        key: built.key,
        left: built.left,
        top: built.top,
        right: built.right,
        bottom: built.bottom,
        width: built.width,
        height: built.height,
        child: fade(built.child),
      );
    }
    return Positioned.fill(child: fade(built));
  }
}

/// What finds the [OverlayState] from below.
final class _OverlayScope extends InheritedWidget {
  const _OverlayScope(this.overlay, {required super.child});

  final OverlayState overlay;

  @override
  bool updateShouldNotify(_OverlayScope oldWidget) =>
      !identical(overlay, oldWidget.overlay);
}
