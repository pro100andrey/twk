/// [ListView]: a list that builds its items as they come into view, each
/// as tall as it likes, scrolled by rows in hardware; [ListController]
/// moves it to an item.
library;

import 'dart:async';
import 'dart:collection';

import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        Color,
        HitTestBehavior,
        ListItemManager,
        ListParentData,
        PaintContext,
        Pen,
        RenderList,
        RenderObject,
        RenderObjectWithChildMixin,
        StyleTable;

import '../focus/focus.dart';
import '../framework/framework.dart';
import '../layout/basic.dart';
import '../layout/one_child.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import 'scrollable.dart';

// Examples can assume:
// late List<String> names;
// late List<({String id, String text})> messages;

/// Builds item [index] of a list.
typedef IndexedWidgetBuilder = Widget Function(BuildContext context, int index);

/// The index of the item whose widget has [key], null for none.
typedef ChildIndexGetter = int? Function(Key key);

/// A [ScrollController] that also moves its [ListView]s to an item, built
/// or not.
///
/// An index is one of the item builder's, never a separator's. Of a move
/// to an item and a move of the position before the list is next laid
/// out, the later wins. Given to no list, it keeps the last move to an
/// item asked for until it is given to one, which makes that move as it is
/// first laid out, in place of its [initialOffset]; a [jumpTo] meanwhile
/// drops it.
///
/// A list of a thousand items that opens at item 500:
///
/// ```dart
/// final controller = ListController()..jumpToIndex(500);
/// final list = ListView.builder(
///   controller: controller,
///   itemCount: 1000,
///   itemBuilder: (context, index) => Text('item $index'),
/// );
/// ```
final class ListController extends ScrollController {
  /// Moves the lists it is given to, which start at [initialOffset] (0 by
  /// default) and, with [stickToEnd], keep to their end
  /// ([ScrollController.new]).
  ListController({super.initialOffset, super.stickToEnd});

  // the lists of the list views it is given to; the move to an item asked
  // for while there were none, and whether to the top
  final _lists = <_ListElement>[];
  (int, bool)? _pending;

  /// Scrolls each of its lists to show item [index] at the top of the
  /// window, as the list is next laid out; a [ListView.reverse] list, read
  /// from the bottom up, at the bottom.
  void jumpToIndex(int index) => _toIndex(index, atTop: true);

  /// Scrolls each of its lists the least that shows item [index], as the
  /// list is next laid out: to its top when it is taller than the window,
  /// to its bottom in a [ListView.reverse] list.
  void ensureIndexVisible(int index) => _toIndex(index, atTop: false);

  @override
  void jumpTo(int offset) {
    _pending = null;
    super.jumpTo(offset);
  }

  void _toIndex(int index, {required bool atTop}) {
    assert(index >= 0, 'an index of 0 or more');
    if (_lists.isEmpty) {
      _pending = (index, atTop);
    }
    for (final list in _lists) {
      _move(list, index, atTop: atTop);
    }
  }

  /// Takes [list], making the move asked for while it had none.
  void _attach(_ListElement list) {
    _lists.add(list);
    if (_pending case (final index, final atTop)?) {
      _pending = null;
      _move(list, index, atTop: atTop);
    }
  }

  static void _move(_ListElement list, int index, {required bool atTop}) =>
      list._toItem(index, atTop: atTop);
}

/// A list of [itemCount] items one below another, each as wide as the
/// list and as tall as it likes, or [itemExtent] rows, in a window that
/// scrolls (a [Scrollable]: keys, the wheel, [controller]).
///
/// Only the items in the window and [cacheExtent] rows past its edges are
/// built, by [itemBuilder] as they come into view, and removed as they
/// leave it; near either end, those up to a window past the edge. A list of a
/// hundred thousand items builds a window's worth. Its items are built
/// again when it is, and when an inherited widget the builder depended on
/// changes.
///
/// The items never built are taken to be as tall as those built are on
/// average: the offset and the extent of the content its [ScrollPosition]
/// has are estimates where the list has not been, which change as it
/// builds items, while what it shows stays where it is. A move of a window
/// or less is exact; a longer one goes where the estimate puts it; Home
/// and End go to the ends. [ListController] moves it to an item.
///
/// An item whose widget has a key keeps its element, and with it its
/// [State], when it is scrolled out of view, and has it back when the
/// builder builds a widget with that key again, at whatever index; the
/// most it keeps is [maxKept], letting go first of the item that left the
/// view longest ago. An item without a key is built anew.
///
/// Scrolled away from its start, and not stuck to its end, it keeps what
/// it shows in place as items are inserted or removed before it: the first
/// item in the window whose widget has a key stays on its row, found among
/// the items built, or by [findItemIndexCallback]
/// (`findChildIndexCallback` of [ListView.builder]), or else as many items
/// on as the count changed by, which the builder is asked for to read its
/// key, and it may not show. A list whose items have no keys keeps its
/// offset instead, and what it shows moves.
///
/// While [stickToBottom] is set, or its [controller] sticks to the end
/// ([ScrollController.stickToEnd]), and the window shows the end, it keeps
/// showing the end as items are added or grow, as a log or a chat does;
/// such a list starts at the end.
///
/// [ListView.separated] builds a separator between each two items, as the
/// items are built: as they come into view.
///
/// A [reverse] list shows item 0 at the bottom and the others above it,
/// as a chat shows its messages, the newest first: offset 0 shows the
/// bottom, Up, PageUp and the wheel up scroll on to the items after it,
/// Home to the last item and End to item 0, and a scrollbar's thumb is
/// at the bottom of its track at offset 0. While the window shows the
/// bottom it keeps showing it as items come at index 0; scrolled up, it
/// stays on the items it shows. Items that do not fill the window are at
/// its bottom. [ListController.jumpToIndex] puts an item at the bottom of
/// the window, the edge the list reads from, and an item taller than the
/// window shows its bottom. The end a controller that sticks to the end
/// keeps is the bottom, offset 0, where End goes and item 0 is: a reverse
/// list keeps it whether its controller sticks or not.
///
/// It takes all the room it is given, which must be bounded, filled with
/// [style] over the theme's background and text under the items. Scrolled
/// while all of it is on the screen, it has the terminal move the rows
/// that stay in view (a hardware scroll), and paints those the scroll
/// brought in and those of the items that changed.
///
/// A screen reader reads it as a [SemanticsRole.list] of [itemCount]
/// items (`list 3 items`), and each item built as a
/// [SemanticsRole.listItem]: its text, or the nodes in it.
///
/// A list of names, built a window's worth at a time, scrolled by the keys
/// once it has the focus:
///
/// ```dart
/// ListView.builder(
///   autofocus: true,
///   itemCount: names.length,
///   itemBuilder: (context, index) => Text(names[index]),
/// )
/// ```
///
/// See also:
///
///  * [ListController], which moves it to an item.
///  * `LogView`, a list of log lines that follows its end.
///  * `SingleChildScrollView`, for content short enough to build whole.
///  * `Scrollbar`, which shows where the list is.
final class ListView extends StatelessWidget {
  /// A list of [children], for a short list: the widgets are made at
  /// once, by the caller, and built as they come into view:
  ///
  /// ```dart
  /// ListView(children: const [Text('one'), Text('two'), Text('three')])
  /// ```
  ListView({
    super.key,
    List<Widget> children = const [],
    this.itemExtent,
    this.cacheExtent = defaultCacheExtent,
    this.maxKept = defaultMaxKept,
    this.stickToBottom = false,
    this.controller,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus,
    this.wheelAcceleration = WheelAcceleration.none,
    this.keyHints = true,
    this.reverse = false,
  }) : itemCount = children.length,
       itemBuilder = ((_, index) => children[index]),
       separatorBuilder = null,
       findItemIndexCallback = null;

  /// A list of [itemCount] items that [itemBuilder] builds as they come
  /// into view; [findChildIndexCallback] finds where a keyed item went
  /// ([findItemIndexCallback]).
  ///
  /// A chat, its messages keyed so that the one in view stays on its row as
  /// others come in above:
  ///
  /// ```dart
  /// ListView.builder(
  ///   itemCount: messages.length,
  ///   itemBuilder: (context, index) => Text(
  ///     messages[index].text,
  ///     key: ValueKey(messages[index].id),
  ///   ),
  /// )
  /// ```
  ///
  /// Each of [itemCount], [cacheExtent] and [maxKept] below 0, and an
  /// [itemExtent] below 1, asserts.
  const ListView.builder({
    required this.itemCount,
    required this.itemBuilder,
    super.key,
    this.itemExtent,
    this.cacheExtent = defaultCacheExtent,
    this.maxKept = defaultMaxKept,
    this.stickToBottom = false,
    this.controller,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus,
    this.wheelAcceleration = WheelAcceleration.none,
    this.keyHints = true,
    this.reverse = false,
    ChildIndexGetter? findChildIndexCallback,
  }) : separatorBuilder = null,
       findItemIndexCallback = findChildIndexCallback,
       assert(itemCount >= 0, 'a count of 0 items or more'),
       assert((itemExtent ?? 1) > 0, 'an item extent of 1 row or more'),
       assert(cacheExtent >= 0, 'a cache of 0 rows or more'),
       assert(maxKept >= 0, 'none kept or more');

  /// A list whose items [itemBuilder] builds, with a separator that
  /// [separatorBuilder] builds between each two: separator `i` between
  /// item `i` and item `i + 1`, built as it comes into view, as the items
  /// are. A screen reader leaves the separators out.
  ///
  /// ```dart
  /// ListView.separated(
  ///   itemCount: names.length,
  ///   itemBuilder: (context, index) => Text(names[index]),
  ///   separatorBuilder: (context, index) => const Divider(),
  /// )
  /// ```
  const ListView.separated({
    required this.itemCount,
    required this.itemBuilder,
    required IndexedWidgetBuilder this.separatorBuilder,
    super.key,
    this.cacheExtent = defaultCacheExtent,
    this.maxKept = defaultMaxKept,
    this.stickToBottom = false,
    this.controller,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus,
    this.wheelAcceleration = WheelAcceleration.none,
    this.keyHints = true,
    this.reverse = false,
    this.findItemIndexCallback,
  }) : itemExtent = null,
       assert(itemCount >= 0, 'a count of 0 items or more'),
       assert(cacheExtent >= 0, 'a cache of 0 rows or more'),
       assert(maxKept >= 0, 'none kept or more');

  /// The rows past either edge of the window whose items are built too: a
  /// notch of the wheel.
  static const int defaultCacheExtent = Scrollable.wheelStep;

  /// The keyed items scrolled out of view that a list keeps.
  static const defaultMaxKept = 64;

  /// How many items the list has, not counting the separators.
  final int itemCount;

  /// Builds an item as it comes into view, its context the list's.
  final IndexedWidgetBuilder itemBuilder;

  /// Builds the separator after an item, as it comes into view; null for
  /// none ([ListView.separated]).
  final IndexedWidgetBuilder? separatorBuilder;

  /// Whether item 0 is at the bottom, the others above it.
  final bool reverse;

  /// The index the item whose widget has a key has now, null for none:
  /// where the item a scrolled list keeps in place went when it is not
  /// among the items built, nor as many items on as the count changed by
  /// ([ListView.builder]'s `findChildIndexCallback`); null to look there
  /// only.
  final ChildIndexGetter? findItemIndexCallback;

  /// The rows of every item, laid out that tall; null for items as tall as
  /// they like.
  final int? itemExtent;

  /// The rows past either edge of the window whose items are built too.
  final int cacheExtent;

  /// How many keyed items scrolled out of view it keeps, the [State] and
  /// all; 0 keeps none.
  final int maxKept;

  /// Keeps showing the end, as items are added or grow, while the window
  /// shows it. What a [reverse] list does at its bottom whether set or not.
  final bool stickToBottom;

  /// See [Scrollable.controller]; a [ListController] moves it to an item
  /// too.
  final ScrollController? controller;

  /// What fills the window under the items, over [ThemeData.background]
  /// and [ThemeData.text].
  final Style? style;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// See [FocusNode.canRequestFocus].
  final bool? canRequestFocus;

  /// See [Scrollable.wheelAcceleration].
  final WheelAcceleration wheelAcceleration;

  /// Whether the keys that would scroll it carry their hints, for a
  /// `KeyHintsBar`, true by default: none while all of it is in the window
  /// ([Scrollable.keyHints]).
  final bool keyHints;

  /// The children of its render list: the items, and the separators
  /// between them.
  int get _childCount => separatorBuilder == null
      ? itemCount
      : (itemCount == 0 ? 0 : 2 * itemCount - 1);

  /// Whether its render list keeps showing its end, the bottom, while it
  /// shows it.
  bool get _sticks =>
      reverse || stickToBottom || (controller?.stickToEnd ?? false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = const Style(
      fg: Color.defaultColor,
      bg: Color.defaultColor,
    ).merge(theme.background).merge(theme.text).merge(style ?? const Style());
    final scrollable = Scrollable(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      canRequestFocus: canRequestFocus,
      wheelAcceleration: wheelAcceleration,
      keyHints: keyHints,
      reverse: reverse,
      viewportBuilder: (context, position) {
        final list = _ListViewport(
          view: this,
          position: position,
          background: background,
        );
        return reverse ? _Bottom(background: background, child: list) : list;
      },
    );
    return Semantics(
      role: SemanticsRole.list,
      value: itemCount == 1 ? '1 item' : '$itemCount items',
      child: scrollable,
    );
  }
}

/// The window of a [ListView]: a [RenderList] that follows [position]
/// without a build, tells it where it settled, and whose items the
/// element builds.
final class _ListViewport extends RenderObjectWidget {
  const _ListViewport({
    required this.view,
    required this.position,
    required this.background,
  });

  final ListView view;
  final ScrollPosition position;
  final Style background;

  @override
  _ListElement createElement() => _ListElement(this);

  @override
  RenderList createRenderObject(BuildContext context) {
    final element = context as _ListElement;
    return RenderList(
      items: element,
      itemCount: view._childCount,
      itemExtent: view.itemExtent,
      cacheExtent: view.cacheExtent,
      stickToBottom: view._sticks,
      background: background.pen,
      scrollOffset: view.reverse ? 0 : position.offset,
      onMetrics: element._settled,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderList renderObject) {
    renderObject
      ..itemCount = view._childCount
      ..itemExtent = view.itemExtent
      ..cacheExtent = view.cacheExtent
      ..stickToBottom = view._sticks
      ..background = background.pen;
  }
}

/// The element of a [_ListViewport]: it builds the items the list asks
/// for, each below an [_Item] of its own, keeps the keyed ones the list
/// drops, and moves the list as the position moves.
final class _ListElement extends RenderObjectElement
    implements ListItemManager {
  _ListElement(_ListViewport super.widget);

  // the items built, by index; the keyed items scrolled out, by key, the
  // one that left the view longest ago first, their render objects out of
  // the list
  var _live = SplayTreeMap<int, Element>();
  final _kept = <Key, Element>{};

  ScrollPosition? _position;
  ListController? _controller;

  // the position's offset the list last took or settled at
  var _seen = 0;

  // in a reverse list, the child a move to an item asked the render list
  // for, and whether to put it at the bottom whatever its height, which
  // the list's next settling then does; whether a move to an item was
  // asked for since the position last took the list's extents
  (int, bool)? _toBottom;
  var _movedToItem = false;

  // the child a move to an item asked the render list to put at the top
  // of the window, in a list not reverse, until the list moves otherwise
  // or settles
  int? _toTop;

  // where the render list last settled, and whether at its end; the child
  // a rebuild found the item the window showed first at, which the next
  // settling puts on the row it was on
  var _settledAt = 0;
  var _settledAtEnd = false;
  (int, int)? _anchorTo;

  @override
  _ListViewport get widget => super.widget as _ListViewport;

  @override
  RenderList get renderObject => super.renderObject as RenderList;

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    _follow(widget);
  }

  @override
  void update(_ListViewport newWidget) {
    final was = widget.view._childCount;
    super.update(newWidget);
    _follow(newWidget);
    _rebuildItems(was);
  }

  // an inherited widget the builder depended on changed
  @override
  void performRebuild() {
    super.performRebuild();
    _rebuildItems(widget.view._childCount);
  }

  @override
  void unmount() {
    _position?.removeListener(_moved);
    _position = null;
    _controller?._lists.remove(this);
    _controller = null;
    super.unmount();
  }

  // the list takes a new position's offset, then its moves only, each in
  // place of a move to an item asked for before it, even a move back to
  // where the list is; a build or the list's settling is no move. A new
  // controller's move to an item kept while it had no list comes after
  // the offset
  void _follow(_ListViewport w) {
    final position = w.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_moved);
      _position = position..addListener(_moved);
      _moved();
    }
    final controller = switch (w.view.controller) {
      final ListController c => c,
      _ => null,
    };
    if (!identical(controller, _controller)) {
      _controller?._lists.remove(this);
      _controller = controller?.._attach(this);
    }
  }

  /// Moves the render list to item [index] in its next layout: to the top
  /// of the window (the bottom, in reverse) when [atTop], the least that
  /// shows it otherwise.
  void _toItem(int index, {required bool atTop}) {
    final at = _childOf(index);
    if (atTop && !widget.view.reverse) {
      renderObject.jumpToIndex(at);
    } else {
      renderObject.showIndex(at);
    }
    _toBottom = widget.view.reverse ? (at, atTop) : null;
    _toTop = atTop && !widget.view.reverse ? at : null;
    _movedToItem = true;
  }

  /// Where the render list, settled at [offset] with [viewport] rows of
  /// its [content] in its window, puts the bottom of [child], a child's
  /// index and whether always, at the bottom of the window: always, or
  /// when the child is taller than the window; null where it is, or for a
  /// child it does not have.
  int? _bottomOf(
    (int, bool) child,
    int viewport,
    int content,
    int offset,
  ) {
    final (index, always) = child;
    final item = _live[index]?.renderObject;
    if (item == null || !identical(item.parent, renderObject)) {
      return null;
    }
    final rows = item.height;
    if (!always && rows <= viewport) {
      return null;
    }
    final max = content - viewport > 0 ? content - viewport : 0;
    final to = offset + item.parentData.dy + rows - viewport;
    final clamped = to < 0 ? 0 : (to > max ? max : to);
    return clamped == offset ? null : clamped;
  }

  /// The child of the render list that item [index] is.
  int _childOf(int index) {
    final view = widget.view;
    final at = view.separatorBuilder == null ? index : 2 * index;
    if (!view.reverse) {
      return at;
    }
    final last = view._childCount - 1;
    return last - at < 0 ? 0 : last - at;
  }

  // the offset of a reverse list is the rows below the window: those of
  // the content less the window's less those above it. Before the list
  // settles first, it is at the bottom, where it starts
  void _moved() {
    final p = _position!;
    final int offset;
    if (!widget.view.reverse) {
      offset = p.offset;
    } else if (p.hasExtents) {
      offset = p.maxOffset - p.offset;
    } else {
      return;
    }
    if (offset != _seen) {
      _seen = offset;
      _toBottom = null;
      _toTop = null;
      renderObject.scrollOffset = offset;
    }
  }

  // tells the position where the list settled, which is no move of it;
  // a reverse list settling first at an offset other than 0, and at no
  // item, is moved there. A reverse list's move to an item puts it at the
  // bottom by moving the list on from where it settled, which it settles
  // at in the layout again that the move makes
  void _settled(int viewport, int content, int offset) {
    _seen = offset;
    _settledAt = offset;
    _settledAtEnd = offset >= content - viewport;
    if (renderObject.parent case final _RenderBottom bottom) {
      bottom.content = content;
    }
    if (_anchorTo case (final child, final dy)?) {
      _anchorTo = null;
      final item = _live[child]?.renderObject;
      if (item != null && identical(item.parent, renderObject)) {
        final to = offset + item.parentData.dy - dy;
        if (to != offset) {
          renderObject.scrollOffset = to;
          return;
        }
      }
    }
    if (_toBottom case final child?) {
      _toBottom = null;
      final to = _bottomOf(child, viewport, content, offset);
      if (to != null) {
        renderObject.scrollOffset = to;
        return;
      }
    }
    final toItem = _movedToItem;
    _movedToItem = false;
    _toTop = null;
    final p = _position!;
    if (!widget.view.reverse) {
      p.applyExtents(viewport, content, offset: offset);
    } else if (!p.hasExtents && p.offset > 0 && !toItem) {
      p.applyExtents(viewport, content);
    } else {
      final max = content - viewport > 0 ? content - viewport : 0;
      p.applyExtents(viewport, content, offset: max - offset);
    }
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    for (final e in _live.values) {
      visitor(e);
    }
    for (final e in _kept.values) {
      visitor(e);
    }
  }

  @override
  void forgetChild(Element child) {
    _live.removeWhere((_, e) => identical(e, child));
    _kept.removeWhere((_, e) => identical(e, child));
    super.forgetChild(child);
  }

  /// Removes [item], whose widget a [GlobalKey] took elsewhere.
  void _lost(Element item) {
    _live.removeWhere((_, e) => identical(e, item));
    _kept.removeWhere((_, e) => identical(e, item));
    deactivateChild(item);
  }

  @override
  void buildItem(int index) {
    final widget = _build(index);
    final key = widget.key;
    var item = _live[index];
    if (item == null && key != null) {
      item = _kept.remove(key)?..attachRenderObject(index);
    }
    _live[index] = updateChild(item, _itemOf(widget, index), index)!;
  }

  @override
  void dropItem(RenderObject item) {
    final element = _live.remove((item.parentData as ListParentData).index);
    if (element != null) {
      _drop(element);
    }
  }

  /// Builds the items in the window again: one whose widget has the key of
  /// an item built or kept takes that item's element, at whatever index it
  /// is now; one without a key takes the element at its index, unless that
  /// element's widget had one. The items left over leave the window. The
  /// list had [was] children before.
  ///
  /// The items built are those of the window and past its edges, where the
  /// next layout puts the window: as many children on as a move to an item
  /// at the top asked for since moves it.
  ///
  /// A list scrolled from its start, and not stuck to its end, keeps the
  /// first keyed item it showed that it still has on the row it was on,
  /// found among the items built, else [was] children on from where it
  /// was, else by the view's [ListView.findItemIndexCallback].
  void _rebuildItems(int was) {
    final max = widget.view.maxKept;
    while (_kept.length > max) {
      deactivateChild(_kept.remove(_kept.keys.first)!);
    }
    final live = _live;
    if (live.isEmpty) {
      return;
    }
    final keeps = _keepsShown();
    final moved = _movedBy();
    final from = live.firstKey()! + moved;
    final first = from < 0 ? 0 : from;
    final last = live.lastKey()! + moved;
    final count = widget.view._childCount;
    final byKey = <Key, Element>{};
    for (final e in live.values) {
      final key = _keyOf(e);
      if (key != null) {
        byKey[key] = e;
      }
    }
    final widgets = <Widget>[];
    final items = <Element?>[];
    final unkept = HashSet<Element>.identity();
    final taken = HashSet<Element>.identity();
    for (var i = first; i <= last && i < count; i++) {
      final w = _build(i);
      final key = w.key;
      Element? item;
      if (key == null) {
        final old = live[i];
        if (old != null && _keyOf(old) == null) {
          item = old;
        }
      } else {
        item = byKey.remove(key);
        if (item == null) {
          item = _kept.remove(key);
          if (item != null) {
            unkept.add(item);
          }
        }
      }
      if (item != null) {
        taken.add(item);
      }
      widgets.add(w);
      items.add(item);
    }
    // where the items are, before those left over leave
    if (keeps) {
      _anchor(widgets, first, count - was);
    }
    for (final e in live.values) {
      if (!taken.contains(e)) {
        _drop(e);
      }
    }
    final next = SplayTreeMap<int, Element>();
    for (var k = 0; k < widgets.length; k++) {
      final item = items[k];
      if (item != null && unkept.contains(item)) {
        item.attachRenderObject(first + k);
      }
      next[first + k] = updateChild(
        item,
        _itemOf(widgets[k], first + k),
        first + k,
      )!;
    }
    _live = next;
  }

  /// Whether the list keeps the keyed items in the window in place as
  /// items come or go before them: not with none shown, at its start (the
  /// bottom, in reverse) or stuck to its end, or with a move asked for
  /// since it last settled.
  bool _keepsShown() {
    final list = renderObject;
    return list.firstChild != null &&
        (widget.view.reverse || _settledAt != 0) &&
        !(list.stickToBottom && _settledAtEnd) &&
        list.scrollOffset == _settledAt &&
        !_movedToItem &&
        _toBottom == null &&
        _anchorTo == null;
  }

  /// The children the window moves on in the next layout, as a move to an
  /// item at its top asked for: from the child at its top row, as last laid
  /// out, to that item; 0 for no such move.
  int _movedBy() {
    final to = _toTop;
    if (to == null) {
      return 0;
    }
    final list = renderObject;
    for (var c = list.firstChild; c != null;) {
      final at = c.parentData as ListParentData;
      if (at.dy + c.height > 0) {
        return at.dy < list.height ? to - at.index : 0;
      }
      c = at.nextSibling;
    }
    return 0;
  }

  /// Keeps the first keyed item in the window, as last laid out, that is
  /// still in the list on the row it is on, when it is now another child:
  /// the child of the [built] widgets, children [first] on, with its key,
  /// else the child [shift] on from where it was when its widget has the
  /// key (the children came or went before it, and none after), else the
  /// one the view's [ListView.findItemIndexCallback] finds. Called before
  /// the items built leave the list.
  void _anchor(List<Widget> built, int first, int shift) {
    final view = widget.view;
    final find = view.findItemIndexCallback;
    final list = renderObject;
    final h = list.height;
    for (final e in _live.values) {
      final item = e.renderObject;
      final key = _keyOf(e);
      if (item == null || key == null || !identical(item.parent, list)) {
        continue;
      }
      final dy = item.parentData.dy;
      if (dy >= h) {
        return;
      }
      if (dy + item.height <= 0) {
        continue;
      }
      final was = e.slot! as int;
      final k = was - first;
      if (k >= 0 && k < built.length && built[k].key == key) {
        return;
      }
      var at = -1;
      for (var j = 0; j < built.length; j++) {
        if (built[j].key == key) {
          at = first + j;
          break;
        }
      }
      if (at < 0 && find != null) {
        final index = find(key);
        if (index != null && index >= 0 && index < view.itemCount) {
          at = _childOf(index);
        }
      }
      // the last resort, an item built to read its key: the builder is
      // asked for one it may not show
      final moved = was + shift;
      if (at < 0 &&
          shift != 0 &&
          (moved < first || moved >= first + built.length) &&
          moved >= 0 &&
          moved < view._childCount &&
          _build(moved).key == key) {
        at = moved;
      }
      if (at >= 0) {
        renderObject.jumpToIndex(at);
        _anchorTo = (at, dy);
        return;
      }
    }
  }

  /// Takes [item] out of the window: kept, render object out of the list,
  /// when its widget has a key; removed otherwise.
  void _drop(Element item) {
    final key = _keyOf(item);
    final max = widget.view.maxKept;
    if (key == null || max == 0) {
      deactivateChild(item);
      return;
    }
    item.detachRenderObject();
    final old = _kept.remove(key);
    if (old != null) {
      deactivateChild(old);
    }
    _kept[key] = item;
    if (_kept.length > max) {
      deactivateChild(_kept.remove(_kept.keys.first)!);
    }
  }

  /// What the builders build for child [index] of the render list, an item
  /// or a separator, the latter left out of the semantics; what the owner
  /// shows for an error when it throws.
  Widget _build(int index) {
    final view = widget.view;
    final at = view.reverse ? view._childCount - 1 - index : index;
    try {
      final separator = view.separatorBuilder;
      if (separator == null) {
        return view.itemBuilder(this, at);
      }
      if (at.isEven) {
        return view.itemBuilder(this, at ~/ 2);
      }
      return ExcludeSemantics(child: separator(this, at ~/ 2));
    } on Object catch (error, stack) {
      final report = owner!.onBuildError;
      if (report != null) {
        return report(this, error, stack);
      }
      Zone.current.handleUncaughtError(error, stack);
      return const SizedBox.shrink();
    }
  }

  static Key? _keyOf(Element item) => (item.widget as _Item).child.key;

  /// [built] as child [index] of the render list: an item, or a separator.
  _Item _itemOf(Widget built, int index) {
    final view = widget.view;
    final at = view.reverse ? view._childCount - 1 - index : index;
    return _Item(built, separator: view.separatorBuilder != null && at.isOdd);
  }

  // an item scrolled out has a null slot: its render object stays out
  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) {
    if (slot is int) {
      renderObject.insertItem(child, slot);
    }
  }

  @override
  void moveRenderObjectChild(
    RenderObject child,
    Object? oldSlot,
    Object? newSlot,
  ) {
    if (newSlot is int && identical(child.parent, renderObject)) {
      renderObject.moveItem(child, newSlot);
    }
  }

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {
    if (identical(child.parent, renderObject)) {
      renderObject.remove(child);
    }
  }
}

/// The window of a reverse [ListView] around its list: the list at its
/// bottom, as tall as its content where that is shorter than the window,
/// [background] above it.
final class _Bottom extends SingleChildRenderObjectWidget {
  const _Bottom({required this.background, super.child});

  final Style background;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderBottom createRenderObject(BuildContext context) =>
      _RenderBottom(background.pen);

  @override
  void updateRenderObject(BuildContext context, _RenderBottom renderObject) {
    renderObject.background = background.pen;
  }
}

/// What a [_Bottom] lays out and paints: all the room it is given, which
/// must be bounded, its child, a [RenderList], at the bottom of it, laid
/// out as tall as the content the child tells of ([content]) where that
/// is less, again until the two agree (the content is partly estimated),
/// three times at most; filled with [background] above it. The list lays
/// itself out again on its own; when the content it then tells of asks
/// for another height, this lays out again.
final class _RenderBottom extends RenderObject with RenderObjectWithChildMixin {
  _RenderBottom(this._background);

  Pen _background;
  Pen get background => _background;
  set background(Pen p) {
    if (p != _background) {
      _background = p;
      _penIn = null;
      markNeedsPaint();
    }
  }

  /// The rows of the list's content, as its last layout told of them.
  int get content => _content;
  var _content = 0;
  set content(int rows) {
    _content = rows;
    final fits = rows < _height ? rows : _height;
    if (!_inLayout && _listHeight >= 0 && fits != _listHeight) {
      markNeedsLayout();
    }
  }

  // whether it is laying the list out
  var _inLayout = false;

  // the height the list was laid out at, and the one this was then
  var _listHeight = -1;
  var _height = -1;

  // the id of the background's pen in _penIn
  StyleTable? _penIn;
  var _penId = 0;

  /// Opaque: it fills all of its cells.
  @override
  HitTestBehavior get hitTestBehavior => HitTestBehavior.opaque;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    final list = child;
    if (list == null) {
      return;
    }
    final h = height;
    var at = h != _height || _listHeight > h || _listHeight < 0
        ? h
        : _listHeight;
    _inLayout = true;
    try {
      for (var pass = 0; ; pass++) {
        list.layout(BoxConstraints(width, width, at, at), parentUsesSize: true);
        final fits = _content < h ? _content : h;
        if (fits == at || pass == 2) {
          break;
        }
        at = fits;
      }
    } finally {
      _inLayout = false;
    }
    if (at != _listHeight || h != _height) {
      markNeedsPaint();
    }
    _listHeight = at;
    _height = h;
    list.parentData
      ..dx = 0
      ..dy = h - at;
  }

  @override
  void paint(PaintContext ctx) {
    final list = child;
    final gap = list == null ? height : height - list.height;
    if (gap > 0) {
      final canvas = ctx.canvas;
      final styles = canvas.styles;
      if (!identical(styles, _penIn)) {
        _penIn = styles;
        _penId = styles.pen(_background);
      }
      canvas.fill(0, 0, width, gap, _penId);
    }
    if (list != null) {
      paintChild(ctx, list);
    }
  }
}

/// An item of a [ListView]: the widget its builder built, below an element
/// of the list's own, from which a [GlobalKey] on the widget can take it
/// elsewhere; read as a [SemanticsRole.listItem], a separator not read.
final class _Item extends Semantics {
  const _Item(Widget child, {bool separator = false})
    : super(child: child, role: separator ? null : SemanticsRole.listItem);

  @override
  StatelessElement createElement() => _ItemElement(this);
}

/// The element of an [_Item]: when a [GlobalKey] takes the item elsewhere,
/// it leaves the list too, which builds the item anew if it is still in
/// view.
final class _ItemElement extends StatelessElement {
  _ItemElement(_Item super.widget);

  @override
  void forgetChild(Element child) {
    super.forgetChild(child);
    visitAncestorElements((list) {
      (list as _ListElement)._lost(this);
      return false;
    });
  }
}
