/// Output that is finished once shown: [Static], whose items an app in the
/// inline mode writes to the terminal's history.
library;

import 'package:twk_core/twk_core.dart'
    show
        Axis,
        BoxConstraints,
        CrossAxisAlignment,
        MainAxisSize,
        PaintContext,
        RenderFlex,
        RenderObject,
        RenderObjectWithChildMixin,
        TwkApp;

import '../framework/framework.dart';
import 'app_binding.dart';

// Examples can assume:
// late List<String> sent;
// void setState(void Function() fn) {}

/// Shows each of [items] once, as output that is finished: finished
/// messages, the lines of a log, the results of the steps of a task. In
/// the inline mode ([ScreenMode.inline]) each item goes to
/// the terminal's history above the app's region (`TwkApp.commit`), where
/// the terminal scrolls and selects it like anything printed.
///
/// An item is built once, by [builder], when the list first has it: at the
/// first build for the items there are then, and at a rebuild for those
/// appended since. Items are told apart by their index: a change to an
/// item already built, or a list made shorter, shows nothing, and an item
/// at an index past those built is new.
///
/// In the inline mode the widget an item is built into is mounted below
/// this one, where it finds the inherited widgets above it, and its render
/// object, out of the region's render tree, is laid out at the terminal's
/// width, as tall as its max intrinsic height there, and painted; its rows
/// are written above the region by the frame that built it (the next ones
/// after a burst of more than 256 rows), in the order of the items. Once
/// they are written its widgets are unmounted, their states disposed.
/// What the Static built before it leaves the tree is still written. The
/// Static itself takes no room in the region.
///
/// A build that commits an item also has the region fit what the app
/// shows, even when that is less than it has (`TwkApp.shrinkRegion`;
/// without a commit it only grows): what the same build took out of the
/// region, such as the finished part of an answer that streams in, gives
/// back its rows. The frame that builds the item erases them in the
/// update of the screen that writes it, and its rows take their place
/// before the history scrolls up.
///
/// In the fullscreen mode and in a fixed viewport (`TwkApp.viewport`),
/// which have no history, and outside an app run by [runApp], the items
/// are shown in place, one below another as in a `Column` whose children
/// stretch to its width, and it is as tall as they are. Their widgets stay
/// mounted: they are rebuilt when what they depend on changes, as any
/// widget is, not when the Static is.
///
/// A prompt whose sent lines go to the history above it, the field alone
/// staying in the app's region:
///
/// ```dart
/// Column(
///   children: [
///     Static(items: sent, builder: (context, line) => Text('> $line')),
///     TextField(onSubmitted: (line) => setState(() => sent.add(line))),
///   ],
/// )
/// ```
final class Static<T> extends RenderObjectWidget {
  /// Shows each of [items] once, as [builder] builds it.
  const Static({required this.items, required this.builder, super.key});

  /// What is shown, oldest first.
  final List<T> items;

  /// Builds the widget that shows an item.
  // called with the items, whose T is the widget's own
  // ignore: unsafe_variance
  final Widget Function(BuildContext context, T item) builder;

  @override
  RenderObjectElement createElement() => _StaticElement<T>(this);

  /// What shows the items in place; in the inline mode it has none.
  @override
  RenderFlex createRenderObject(BuildContext context) => RenderFlex(
    direction: Axis.vertical,
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
  );
}

/// The element of a [Static]: the elements of its items are its children,
/// each at its index as slot. In the inline mode their render objects go
/// to the app's history, each in a [_RenderCommit]; in the fullscreen mode
/// into its own render object, in order.
final class _StaticElement<T> extends RenderObjectElement {
  _StaticElement(Static<T> super.widget);

  @override
  Static<T> get widget => super.widget as Static<T>;

  @override
  RenderFlex get renderObject => super.renderObject as RenderFlex;

  // inline mode: the app whose history the items go to
  TwkApp? _app;

  // how many items were built
  var _built = 0;

  // the elements of the items still mounted, by index, in order
  final _items = <int, Element>{};

  // inline mode: what holds the render object of each item whose rows are
  // not written yet, by index
  final _commits = <int, _RenderCommit>{};

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    final binding = AppBinding.maybeOf(this);
    if (binding != null &&
        binding.mode == ScreenMode.inline &&
        binding.twkApp.viewport == null) {
      _app = binding.twkApp;
    }
    _buildNew();
  }

  @override
  void update(Static<T> newWidget) {
    super.update(newWidget);
    _buildNew();
  }

  /// Builds the items past those built, and in the inline mode commits
  /// them and has the region fit what it shows.
  void _buildNew() {
    final items = widget.items;
    final app = _app;
    final from = _built;
    for (; _built < items.length; _built++) {
      final i = _built;
      final commit = app == null
          ? null
          : _commits[i] = _RenderCommit(() => _written(i));
      _items[i] = updateChild(null, _Item<T>(widget.builder, items[i]), i)!;
      if (commit != null) {
        app!.commit(commit);
      }
    }
    if (app != null && _built > from) {
      app.shrinkRegion();
    }
  }

  /// Inline mode: the rows of item [i] are written; its widgets leave the
  /// tree.
  void _written(int i) {
    _commits.remove(i)?.child = null;
    final child = _items.remove(i);
    if (child != null && mounted) {
      deactivateChild(child);
    }
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    for (final child in _items.values) {
      visitor(child);
    }
  }

  @override
  void forgetChild(Element child) =>
      _items.removeWhere((_, e) => identical(e, child));

  @override
  void insertRenderObjectChild(RenderObject child, int slot) {
    if (_app != null) {
      _commits[slot]?.child = child;
    } else {
      renderObject.insert(child, after: _renderObjectBefore(slot));
    }
  }

  /// Fullscreen mode: the render object of the nearest item before item
  /// [i] that has one in place.
  RenderObject? _renderObjectBefore(int i) {
    for (var j = i - 1; j >= 0; j--) {
      final o = _items[j]?.renderObject;
      if (o != null && identical(o.parent, renderObject)) {
        return o;
      }
    }
    return null;
  }

  @override
  void moveRenderObjectChild(
    RenderObject child,
    Object? oldSlot,
    Object? newSlot,
  ) => throw UnsupportedError('the items of a Static do not move: $this');

  @override
  void removeRenderObjectChild(RenderObject child, int slot) {
    if (_app == null) {
      renderObject.remove(child);
    } else if (_commits[slot] case final commit?
        when identical(commit.child, child)) {
      commit.child = null;
    }
  }
}

/// The widget of an item: what the builder builds for it.
final class _Item<T> extends StatelessWidget {
  const _Item(this.builder, this.item);

  // called with the item, whose T is the widget's own
  // ignore: unsafe_variance
  final Widget Function(BuildContext context, T item) builder;

  final T item;

  @override
  Widget build(BuildContext context) => builder(context, item);
}

/// Inline mode: what the render object of a [Static]'s item is committed
/// in: its child at its size, and its sizes the child's. The app attaches
/// it while it writes its rows and detaches it once they are written,
/// which calls [onWritten].
final class _RenderCommit extends RenderObject with RenderObjectWithChildMixin {
  _RenderCommit(this.onWritten);

  final void Function() onWritten;

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void performLayout(BoxConstraints c) {
    child?.layout(c);
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }

  @override
  void detach() {
    final written = owner != null;
    super.detach();
    if (written) {
      onWritten();
    }
  }
}
