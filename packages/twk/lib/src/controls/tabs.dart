/// Tabs: a [TabBar] of their labels, which the keys and the mouse switch
/// and which scrolls when they do not fit, and a [TabView] that shows the
/// selected one's content and keeps the others with their state; the
/// [TabController] they share.
library;

import 'package:twk_core/twk_core.dart'
    show
        Attr,
        BoxConstraints,
        ContainerParentDataMixin,
        ContainerRenderObjectMixin,
        HitTestResult,
        PaintContext,
        ParentData,
        RenderObject,
        TextMode,
        TextSegmenter;

import '../editing/caret.dart' show clearRestCursor, restCursor;
import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../layout/child_list.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';

/// Holds which of [length] tabs is selected: [index], which a [TabBar]
/// sets and a [TabView] shows.
///
/// It notifies its listeners of each change. A bar and a view that share
/// one, the second tab selected at first:
///
/// ```dart
/// final tabs = TabController(length: 3, initialIndex: 1);
/// final page = Column(
///   children: [
///     TabBar(controller: tabs, tabs: const ['Files', 'Search', 'Git']),
///     Expanded(
///       child: TabView(
///         controller: tabs,
///         children: const [Text('files'), Text('search'), Text('git')],
///       ),
///     ),
///   ],
/// );
/// ```
final class TabController extends ChangeNotifier {
  /// A controller of [length] tabs, one at least, [initialIndex] selected;
  /// it asserts both.
  TabController({required int length, int initialIndex = 0})
    : assert(length > 0, 'no tabs'),
      assert(
        initialIndex >= 0 && initialIndex < length,
        'initialIndex out of 0..${length - 1}',
      ),
      _length = length,
      _index = initialIndex;

  int _length;

  /// How many tabs there are, one at least. Set to [index] or fewer, the
  /// last is selected; a change notifies the listeners once.
  int get length => _length;

  set length(int value) {
    if (value < 1) {
      throw RangeError.range(value, 1, null, 'length', 'no tabs');
    }
    if (value != _length) {
      _length = value;
      if (_index >= value) {
        _index = value - 1;
      }
      notifyListeners();
    }
  }

  int _index;

  /// The selected tab, from 0; a [RangeError] set to one of none.
  int get index => _index;

  set index(int value) {
    RangeError.checkValidIndex(value, this, 'index', length);
    if (value != _index) {
      _index = value;
      notifyListeners();
    }
  }
}

/// A row of the labels of the [controller]'s tabs, its selected one marked,
/// which the keys and the mouse switch.
///
/// A tab clicked is selected. While the bar has the focus, Left and Right
/// select the tab before and after the selected one, from the first to
/// the last and back, Home and End the first and the last: a layer of the
/// focus tree whose keys a `KeyHintsBar` shows, Left and Right hinted.
///
/// A tab is its label with a blank on either side. The bar is as wide as
/// its tabs within its constraints, one row tall. When they do not fit, it
/// scrolls to show the selected one whole, with `‹` or `›` at the edge
/// where tabs are cut off: one clicked scrolls the tab cut off there into
/// view, and the wheel scrolls three columns a notch.
///
/// The styles, each merged over those before it: [style] for the row, over
/// the theme's text; [tabStyle] for a tab and the edges' marks;
/// [selectedStyle] for the selected tab, and [focusedStyle] for it while
/// the bar has the focus. One left null is the theme's: [ThemeData.muted],
/// [ThemeData.primary] in bold, and [ThemeData.primary] in bold reversed.
///
/// [TabBar.strip] draws the row as a strip on the theme's surface, the
/// selected tab cut out of it in the background's colour, as the tabs of a
/// `DockArea` are.
///
/// A screen reader reads it as a [SemanticsRole.tabList] of a
/// [SemanticsRole.tab] for each label, the marked one `selected`; while the
/// bar has the focus, that one is the focused node.
///
/// A bar of three tabs above the content of the one selected:
///
/// ```dart
/// final tabs = TabController(length: 3);
/// final page = Column(
///   children: [
///     TabBar.strip(
///       controller: tabs,
///       tabs: const ['One', 'Two', 'Three'],
///       autofocus: true,
///     ),
///     Expanded(
///       child: TabView(
///         controller: tabs,
///         children: const [Text('1'), Text('2'), Text('3')],
///       ),
///     ),
///   ],
/// );
/// ```
///
/// See also:
///
///  * [TabView], which shows the content of the selected tab.
///  * [TabController], which they share.
final class TabBar extends StatefulWidget {
  /// A tab bar of [tabs], marked in the theme's primary color.
  const TabBar({
    required this.controller,
    required this.tabs,
    super.key,
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.tabStyle,
    this.selectedStyle,
    this.focusedStyle,
  }) : _strip = false;

  /// A tab bar on a strip: the styles left null are the theme's surface
  /// for the row, [ThemeData.muted] for a tab, [ThemeData.primary] in bold
  /// on the theme's background for the selected tab, and
  /// [ThemeData.onPrimary] in bold on a [ThemeData.primary] fill for it
  /// while the bar has the focus.
  const TabBar.strip({
    required this.controller,
    required this.tabs,
    super.key,
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.tabStyle,
    this.selectedStyle,
    this.focusedStyle,
  }) : _strip = true;

  /// The tabs and the selected one.
  final TabController controller;

  /// The label of each tab, one per tab of the [controller]. While they
  /// are fewer, as before the controller is told of a tab gone, the last
  /// is marked for a tab selected past them; the keys and the mouse
  /// select only the tabs both have.
  final List<String> tabs;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// The row, the theme's text under it.
  final Style? style;

  /// A tab, and the marks of the edges; [ThemeData.muted] when null.
  final Style? tabStyle;

  /// The selected tab; [ThemeData.primary] in bold when null.
  final Style? selectedStyle;

  /// The selected tab while the bar has the focus; [ThemeData.primary] in
  /// bold reversed when null.
  final Style? focusedStyle;

  // made by TabBar.strip
  final bool _strip;

  @override
  State<TabBar> createState() => _TabBarState();
}

final class _TabBarState extends State<TabBar> {
  final GlobalKey _strip = GlobalKey();
  FocusNode? _own;

  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(TabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.focusNode, oldWidget.focusNode)) {
      // the Focus below lets an own node go after this build: it is
      // disposed with this state
      (oldWidget.focusNode ?? _own)?.removeListener(_changed);
      _node.addListener(_changed);
    }
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _node.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  // the tab marked: the selected one, or the last label before it
  int get _marked {
    final last = widget.tabs.length - 1;
    final index = widget.controller.index;
    return index < last ? index : last;
  }

  // the tabs that have a label and that the controller has
  int get _count {
    final labels = widget.tabs.length;
    final tabs = widget.controller.length;
    return labels < tabs ? labels : tabs;
  }

  void _select(int index) {
    if (index >= 0 && index < _count) {
      widget.controller.index = index;
    }
  }

  void _step(int by) {
    if (_count case final n when n > 0) {
      _select((_marked + by) % n);
    }
  }

  void _previous() => _step(-1);

  void _next() => _step(1);

  void _first() => _select(0);

  void _last() => _select(_count - 1);

  late final Map<String, VoidCallback> _keys = {
    'left': _previous,
    'right': _next,
    'home': _first,
    'end': _last,
  };

  _RenderTabBar? get _bar =>
      _strip.currentContext?.findRenderObject() as _RenderTabBar?;

  void _down(PointerEvent event) {
    final bar = _bar;
    if (bar == null || event.button != 0) {
      return;
    }
    if (bar.edgeAt(event.x) case final edge when edge != 0) {
      bar.scrollTab(edge);
    } else if (bar.tabAt(event.x) case final tab?) {
      _select(tab);
    }
  }

  void _scroll(PointerEvent event) =>
      _bar?.scrollBy(3 * (event.scrollX + event.scrollY));

  @override
  Widget build(BuildContext context) {
    final focused = _node.hasFocus;
    final theme = Theme.of(context);
    const bold = Style(attrs: Attr.bold);
    final marked = _marked;
    final strip = widget._strip;
    final Style row;
    final Style selected;
    final Style lit;
    if (strip) {
      row = theme.surface;
      selected = theme.primary
          .merge(bold)
          .merge(Style(bg: theme.background.bg));
      lit = theme.onPrimary.merge(
        Style(bg: theme.primary.fg, attrs: Attr.bold),
      );
    } else {
      row = const Style();
      selected = theme.primary.merge(bold);
      lit = theme.fill(theme.primary.fg).merge(bold);
    }
    final bar = Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      child: KeyBindings(
        _keys,
        hints: _hints,
        child: Listener(
          onDown: _down,
          onScroll: _scroll,
          child: _Strip(
            key: _strip,
            tabs: widget.tabs,
            selected: marked,
            focused: focused,
            style: theme.text.merge(widget.style ?? row),
            tabStyle: widget.tabStyle ?? theme.muted,
            selectedStyle: widget.selectedStyle ?? selected,
            focusedStyle: widget.focusedStyle ?? lit,
          ),
        ),
      ),
    );
    return Semantics(
      role: SemanticsRole.tabList,
      nodes: [
        for (final (i, label) in widget.tabs.indexed)
          SemanticsNode(
            role: SemanticsRole.tab,
            label: label,
            state: SemanticsState(selected: i == marked),
            focused: i == marked,
          ),
      ],
      child: bar,
    );
  }

  static const _hints = {'left': 'previous tab', 'right': 'next tab'};
}

/// The row of a [TabBar].
final class _Strip extends LeafRenderObjectWidget {
  const _Strip({
    required this.tabs,
    required this.selected,
    required this.focused,
    required this.style,
    required this.tabStyle,
    required this.selectedStyle,
    required this.focusedStyle,
    super.key,
  });

  final List<String> tabs;
  final int selected;
  final bool focused;
  final Style style;
  final Style tabStyle;
  final Style selectedStyle;
  final Style focusedStyle;

  @override
  _RenderTabBar createRenderObject(BuildContext context) =>
      _RenderTabBar(tabs, selected).._configure(this);

  @override
  void updateRenderObject(BuildContext context, _RenderTabBar renderObject) =>
      renderObject
        ..tabs = tabs
        ..selected = selected
        .._configure(this);
}

/// What a [TabBar] lays out and paints: the tabs from the column
/// [_offset] of the row they make, which moves to show the selected one
/// when it changes and as the wheel and the edges' marks scroll it.
final class _RenderTabBar extends RenderObject {
  _RenderTabBar(this._tabs, this._selected);

  List<String> _tabs;
  int _selected;
  var _focused = false;
  var _style = const Style();
  var _tabStyle = const Style();
  var _selectedStyle = const Style();
  var _focusedStyle = const Style();

  // the first column of each tab and the end of the last, in the row they
  // make; measured for the text mode and ambiguous width of _measuredIn
  var _starts = const <int>[0];
  (TextMode, int)? _measuredIn;

  // the first column of that row shown, and whether it is to move to show
  // the selected tab at the next layout
  var _offset = 0;
  var _reveal = true;

  List<String> get tabs => _tabs;
  set tabs(List<String> tabs) {
    if (!sameList(tabs, _tabs)) {
      _tabs = tabs;
      _measuredIn = null;
      _reveal = true;
      markNeedsLayout();
    }
  }

  int get selected => _selected;
  set selected(int index) {
    if (index != _selected) {
      _selected = index;
      _reveal = true;
      markNeedsLayout();
    }
  }

  void _configure(_Strip strip) {
    if (strip.focused != _focused ||
        strip.style != _style ||
        strip.tabStyle != _tabStyle ||
        strip.selectedStyle != _selectedStyle ||
        strip.focusedStyle != _focusedStyle) {
      _focused = strip.focused;
      _style = strip.style;
      _tabStyle = strip.tabStyle;
      _selectedStyle = strip.selectedStyle;
      _focusedStyle = strip.focusedStyle;
      markNeedsPaint();
    }
  }

  int get _total => _starts.last;

  List<int> _measure() {
    final segmenter = owner?.segmenter ?? TextSegmenter();
    final measure = (segmenter.mode, segmenter.ambiguousWidth);
    if (_measuredIn != measure) {
      final starts = <int>[];
      var x = 0;
      for (final label in _tabs) {
        starts.add(x);
        x += segmenter.width(label) + 2;
      }
      _starts = starts..add(x);
      _measuredIn = measure;
    }
    return _starts;
  }

  @override
  int computeMinIntrinsicWidth(int height) => 0;

  @override
  int computeMaxIntrinsicWidth(int height) => _measure().last;

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    final total = _measure().last;
    width = c.constrainW(total);
    height = c.constrainH(1);
    if (_reveal) {
      _reveal = false;
      _show(_selected);
    }
    _offset = _clamp(_offset);
  }

  int _clamp(int offset) {
    final most = _total - width;
    return offset > most ? (most > 0 ? most : 0) : (offset < 0 ? 0 : offset);
  }

  /// Scrolls the least that shows tab [i] whole, the edges' marks not over
  /// it, its start when it is wider than the room for it.
  void _show(int i) {
    if (i < 0 || i >= _tabs.length) {
      return;
    }
    final start = _starts[i];
    final end = _starts[i + 1];
    final total = _total;
    var offset = _offset;
    // past the right mark, unless the row ends there
    if (end > offset + width - (offset + width < total ? 1 : 0)) {
      offset = end >= total ? total - width : end - width + 1;
    }
    // before the left mark, unless the row starts there
    if (start < offset + (offset > 0 ? 1 : 0)) {
      offset = start <= 1 ? 0 : start - 1;
    }
    _offset = _clamp(offset);
  }

  /// Scrolls the row [columns] columns, to the right when positive.
  void scrollBy(int columns) {
    final offset = _clamp(_offset + columns);
    if (offset != _offset) {
      _offset = offset;
      markNeedsPaint();
    }
  }

  /// Scrolls into view the tab that the mark at the left edge ([edge] -1)
  /// or the right one (1) is over.
  void scrollTab(int edge) {
    final x = _offset + (edge < 0 ? 0 : width - 1);
    for (var i = 0; i < _tabs.length; i++) {
      if (_starts[i] <= x && x < _starts[i + 1]) {
        _show(i);
        markNeedsPaint();
        return;
      }
    }
  }

  /// -1 where the left edge's mark is at column [x], 1 where the right
  /// one's is, 0 elsewhere.
  int edgeAt(int x) {
    if (x == 0 && _offset > 0) {
      return -1;
    }
    if (x == width - 1 && _offset + width < _total) {
      return 1;
    }
    return 0;
  }

  /// The tab at column [x]; null past the last.
  int? tabAt(int x) {
    final at = _offset + x;
    for (var i = 0; i < _tabs.length; i++) {
      if (_starts[i] <= at && at < _starts[i + 1]) {
        return i;
      }
    }
    return null;
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    canvas.fill(0, 0, width, height, _style.penIn(styles));
    // the hidden cursor on the selected tab, as far as it is in view
    final marked = _selected >= 0 && _selected < _tabs.length;
    final from = marked ? _starts[_selected] - _offset : width;
    final to = marked ? _starts[_selected + 1] - _offset : 0;
    if (from < width && to > 0) {
      restCursor(ctx, this, from < 0 ? 0 : from, 0);
    } else {
      clearRestCursor(ctx, this);
    }
    final tab = _style.merge(_tabStyle);
    for (var i = 0; i < _tabs.length; i++) {
      final x = _starts[i] - _offset;
      final w = _starts[i + 1] - _starts[i];
      if (x >= width || x + w <= 0) {
        continue;
      }
      final s = i != _selected
          ? tab
          : tab.merge(_focused ? _focusedStyle : _selectedStyle);
      final pen = s.penIn(styles);
      canvas
        ..fill(x, 0, w, 1, pen)
        ..text(x + 1, 0, _tabs[i], pen);
    }
    final mark = tab.penIn(styles);
    if (_offset > 0) {
      canvas.fill(0, 0, 1, 1, mark, 0x2039);
    }
    if (_offset + width < _total) {
      canvas.fill(width - 1, 0, 1, 1, mark, 0x203A);
    }
  }
}

/// Shows the content of the [controller]'s selected tab, and keeps the
/// others with their state.
///
/// Of [children], one per tab in order, it shows the one at the
/// controller's index. While they are fewer, as before the controller is
/// told of a tab gone, it shows the last; with none, it shows nothing.
///
/// The others stay mounted, with their state, but are not laid out,
/// painted or hit by the mouse, and none of their nodes can take the
/// focus ([FocusNode.descendantsAreFocusable]), so Tab passes them by.
/// When another child is shown while the focus is in the one shown, it
/// moves to the node the new one had it on when it was left, or else to
/// its first node, as Tab from before it does ([FocusNode.nextFocus]). A
/// child with a key keeps its state and that node as the children before
/// it come and go.
///
/// It fills the room it gets; along an axis with no bound, it is as long
/// as the child shown.
///
/// The pages of a settings screen, the one shown kept with the tab bar's
/// controller:
///
/// ```dart
/// final tabs = TabController(length: 2);
/// final pages = TabView(
///   controller: tabs,
///   children: const [Text('General'), Text('Advanced')],
/// );
/// ```
///
/// See [TabController] for one under a [TabBar].
final class TabView extends StatefulWidget {
  /// A view of the [children] of the [controller]'s tabs.
  const TabView({required this.controller, required this.children, super.key});

  /// The tabs and the selected one.
  final TabController controller;

  /// The content of each tab, one per tab of the [controller]; no two
  /// with one key.
  final List<Widget> children;

  @override
  State<TabView> createState() => _TabViewState();
}

final class _TabViewState extends State<TabView> {
  // the tab of each child, in order
  var _tabs = const <_Tab>[];

  // the tab shown and its index, -1 for none
  _Tab? _shownTab;
  var _shown = -1;

  @override
  void initState() {
    super.initState();
    _fit();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(TabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    _fit();
  }

  @override
  void dispose() {
    // the pages dispose the nodes as they go
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  /// A tab for each child, kept by the child's key, or else by its index,
  /// and the one shown among them.
  void _fit() {
    final children = widget.children;
    final kept = {for (final tab in _tabs) tab.id: tab};
    _tabs = [
      for (var i = 0; i < children.length; i++)
        kept[children[i].key ?? i] ?? _Tab(children[i].key ?? i),
    ];
    assert(
      {for (final tab in _tabs) tab.id}.length == _tabs.length,
      'two children of a TabView share a key',
    );
    _show(_target);
  }

  /// The controller's tab, or the last child while there are fewer.
  int get _target {
    final last = _tabs.length - 1;
    final index = widget.controller.index;
    return index < last ? index : last;
  }

  void _changed() {
    final index = _target;
    if (index != _shown) {
      setState(() => _show(index));
    }
  }

  /// Shows the child at [index], none at -1, the focus moving to it from
  /// the one shown.
  void _show(int index) {
    final from = _shownTab;
    final to = index < 0 ? null : _tabs[index];
    _shown = index;
    if (identical(from, to)) {
      return;
    }
    _shownTab = to;
    final focused = from != null && from.node.hasFocus
        ? from.node.manager?.primaryFocus
        : null;
    if (from != null) {
      from
        ..last = focused ?? from.last
        ..node.descendantsAreFocusable = false;
    }
    if (to == null) {
      return;
    }
    to.node.descendantsAreFocusable = true;
    if (focused != null) {
      final last = to.last;
      if (last != null && last.canRequestFocus && _isBelow(last, to.node)) {
        last.requestFocus();
      } else {
        to.node.nextFocus();
      }
    }
  }

  static bool _isBelow(FocusNode node, FocusNode above) {
    for (var n = node.parent; n != null; n = n.parent) {
      if (identical(n, above)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.children;
    return _Pages(
      shown: _shown,
      children: [
        for (var i = 0; i < children.length; i++)
          _Page(
            key: ValueKey<Object>(_tabs[i].id),
            node: _tabs[i].node,
            child: children[i],
          ),
      ],
    );
  }
}

/// A child of a [TabView]: what tells it apart, the node above it, which
/// keeps the focus from it while it is hidden, and the node below that
/// had the focus when another child was shown.
final class _Tab {
  _Tab(this.id);

  final Object id;

  final node = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
    descendantsAreFocusable: false,
  );

  FocusNode? last;
}

/// A child of a [TabView] under the node of its tab, which it disposes as
/// it goes: at the end of the build, once what moved out from under it,
/// by a [GlobalKey], is attached elsewhere.
final class _Page extends StatefulWidget {
  const _Page({required this.node, required this.child, super.key});

  final FocusNode node;
  final Widget child;

  @override
  State<_Page> createState() => _PageState();
}

final class _PageState extends State<_Page> {
  @override
  void dispose() {
    widget.node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: widget.node, child: widget.child);
}

/// The children of a [TabView], the one at [shown] laid out and painted.
final class _Pages extends MultiChildRenderObjectWidget {
  const _Pages({required this.shown, super.children});

  final int shown;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  _RenderPages createRenderObject(BuildContext context) => _RenderPages(shown);

  @override
  void updateRenderObject(BuildContext context, _RenderPages renderObject) =>
      renderObject.shown = shown;
}

final class _PageData extends ParentData with ContainerParentDataMixin {}

/// What a [TabView] lays out and paints: the child at [shown]. The others
/// are detached from the pipeline, so that what changes in them is not
/// laid out or painted, nor marks this object; laid out last within tight
/// constraints, each is a relayout boundary, where a mark inside it stops.
final class _RenderPages extends RenderObject
    with ContainerRenderObjectMixin<_PageData> {
  _RenderPages(this._shown);

  int _shown;

  int get shown => _shown;
  set shown(int index) {
    if (index == _shown) {
      return;
    }
    final o = owner;
    final before = _child;
    _shown = index;
    final after = _child;
    if (o != null) {
      if (before != null && before.owner != null) {
        before.detach();
      }
      if (after != null && after.owner == null) {
        after.attach(o);
      }
    }
    markNeedsLayout();
  }

  /// The child shown.
  RenderObject? get _child {
    var i = 0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      if (i++ == _shown) {
        return c;
      }
    }
    return null;
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _PageData) {
      child.parentData = _PageData();
    }
  }

  /// The child shown alone: the others are not in the pipeline, nor
  /// painted, described or outlined.
  @override
  void visitChildren(void Function(RenderObject child) visit) {
    if (_child case final child?) {
      visit(child);
    }
  }

  @override
  void detach() {
    super.detach();
    // a child adopted since the last layout may be attached too
    for (var c = firstChild; c != null; c = childAfter(c)) {
      if (c.owner != null) {
        c.detach();
      }
    }
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      _child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      _child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      _child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void performLayout(BoxConstraints c) {
    final o = owner;
    RenderObject? shown;
    var i = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (i++ == _shown) {
        shown = child;
        if (o != null && child.owner == null) {
          child.attach(o);
        }
      } else if (child.owner != null) {
        child.detach();
      }
    }
    const unbounded = BoxConstraints.unbounded;
    final wide = c.maxW < unbounded;
    final tall = c.maxH < unbounded;
    if (shown == null) {
      width = wide ? c.maxW : c.minW;
      height = tall ? c.maxH : c.minH;
      return;
    }
    if (wide && tall) {
      shown.layout(BoxConstraints.tight(c.maxW, c.maxH));
    } else {
      shown.layout(
        BoxConstraints(
          wide ? c.maxW : c.minW,
          c.maxW,
          tall ? c.maxH : c.minH,
          c.maxH,
        ),
        parentUsesSize: true,
      );
    }
    shown.parentData
      ..dx = 0
      ..dy = 0;
    width = c.constrainW(shown.width);
    height = c.constrainH(shown.height);
  }

  @override
  void paint(PaintContext ctx) {
    if (_child case final child?) {
      paintChild(ctx, child);
    }
  }

  @override
  bool hitTestChildren(HitTestResult result, int x, int y) =>
      _child?.hitTest(result, x, y) ?? false;
}
