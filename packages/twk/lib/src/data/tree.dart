/// Trees: a [TreeView] of nodes under their parents, which shows the
/// children of those expanded, loading them as they are first shown when
/// they come in a future; a [TreeTable] of them in the columns of a table;
/// the [TreeController] that holds what is expanded and selected, and the
/// [TreeEntry] a node's label is built from.
library;

import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        BorderType,
        BoxConstraints,
        HitTestBehavior,
        KeyEvent,
        KeyKind,
        PaintContext,
        RenderObject,
        RenderObjectWithChildMixin,
        TextAlign,
        TextSegmenter;

import '../animation/spinner.dart';
import '../binding/app_binding.dart';
import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../layout/flex.dart';
import '../layout/one_child.dart';
import '../scroll/list_view.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'chart_glyphs.dart';
import 'table.dart';

part 'tree_table.dart';

// Examples can assume:
// late Map<String, List<String>> folders;
// void open(String path) {}

/// A node of a [TreeView] as it shows, which its label is built from.
@immutable
final class TreeEntry<T> {
  /// The entry of [node], as the view hands it to [TreeView.label].
  const TreeEntry({
    required this.node,
    required this.key,
    required this.depth,
    required this.hasChildren,
    required this.expanded,
    required this.selected,
  });

  /// The node itself, one of [TreeView.roots] or of what
  /// [TreeView.children] gave.
  final T node;

  /// Its key ([TreeView.nodeKey]).
  final Object key;

  /// How far below the roots it is: 0 for a root.
  final int depth;

  /// Whether it shows an expander: it has children, or may have.
  final bool hasChildren;

  /// Whether its children show below it.
  final bool expanded;

  /// Whether it is the node selected.
  final bool selected;
}

/// What a [TreeView] shows: the nodes expanded, by key ([isExpanded]), and
/// the node selected ([selectedKey]). It notifies its listeners of each
/// change.
///
/// Both are keys, not places: a node stays expanded and selected while the
/// nodes around it change, and while it is out of the tree, until it comes
/// back.
///
/// A controller with the root expanded and a folder under it selected,
/// that expands that folder too:
///
/// ```dart
/// final tree = TreeController(selectedKey: '/src', expanded: ['/']);
/// tree.expand('/src');
/// ```
final class TreeController extends ChangeNotifier {
  /// Selects the node with [selectedKey], null for none, and expands those
  /// with the keys in [expanded].
  TreeController({this._selectedKey, Iterable<Object> expanded = const []})
    : _expanded = {...expanded};

  Object? _selectedKey;

  /// The key of the node selected; null for none, and a key no node shown
  /// has selects none.
  Object? get selectedKey => _selectedKey;

  set selectedKey(Object? key) {
    if (key != _selectedKey) {
      _selectedKey = key;
      notifyListeners();
    }
  }

  final Set<Object> _expanded;

  /// The keys of the nodes expanded.
  Set<Object> get expanded => UnmodifiableSetView(_expanded);

  // one more for each change of what is expanded, and for each reload
  var _version = 0;

  /// Whether the node with [key] shows its children.
  bool isExpanded(Object key) => _expanded.contains(key);

  /// Shows the children of the node with [key].
  void expand(Object key) {
    if (_expanded.add(key)) {
      _changed();
    }
  }

  /// Hides the children of the node with [key].
  void collapse(Object key) {
    if (_expanded.remove(key)) {
      _changed();
    }
  }

  /// Expands the node with [key] when it is collapsed, and the other way.
  void toggle(Object key) => isExpanded(key) ? collapse(key) : expand(key);

  /// Expands the nodes with [keys].
  void expandAll(Iterable<Object> keys) {
    final before = _expanded.length;
    _expanded.addAll(keys);
    if (_expanded.length != before) {
      _changed();
    }
  }

  /// Collapses the nodes with [keys]; all of them when null.
  void collapseAll([Iterable<Object>? keys]) {
    final before = _expanded.length;
    if (keys == null) {
      _expanded.clear();
    } else {
      _expanded.removeAll(keys);
    }
    if (_expanded.length != before) {
      _changed();
    }
  }

  // the reloads so far; the last of them for each key, and the last for
  // all of them
  var _reloads = 0;
  final _reloaded = <Object, int>{};
  var _reloadedAll = 0;

  /// Forgets the children of the node with [key], of every node when null,
  /// that came in a future ([TreeView.children]): they are asked for again
  /// as they next show.
  void reload([Object? key]) {
    _reloads++;
    if (key == null) {
      _reloaded.clear();
      _reloadedAll = _reloads;
    } else {
      _reloaded[key] = _reloads;
    }
    _changed();
  }

  /// Whether the children of [key] asked for at reload [at] were reloaded
  /// since.
  bool _reloadedSince(Object key, int at) =>
      _reloadedAll > at || (_reloaded[key] ?? 0) > at;

  void _changed() {
    _version++;
    notifyListeners();
  }
}

/// [roots] and their descendants, each node a row below its parent and
/// indented a level more, those whose parent [controller] expands; a node
/// with children shows `▸` before its label, `▾` while expanded. With
/// [showGuides], lines join each node to its parent, `├─` or `└─` for the
/// last child, `│` down past the children between them; box drawing where
/// the terminal draws it a column wide, [BorderType.ascii] where not.
///
/// A node's children are what [children] gives for it, asked for as the
/// rows are worked out. A list shows at once; a future shows a spinner row
/// below the node until it ends, then its list, which is kept by the
/// node's key until [TreeController.reload], or a row with the error it
/// failed with, which is forgotten as the node collapses. [hasChildren]
/// tells which nodes have children without asking for them; without it,
/// [children] is asked for the children of every node shown, so that a
/// node with none shows no expander, and a future of them starts loading
/// then.
///
/// The rows are a [ListView]'s items: of a tree of a hundred thousand
/// nodes only those in view and a few rows past them are built, a row
/// each, [label] building what shows of the node after its guides and
/// expander, as wide as the rest of the row; scrolled by the wheel, the
/// rows that stay in view moved by a hardware scroll, as the list's are.
/// The nodes shown are walked again as the expanded nodes change, as a
/// load ends, and as the view is built with a new widget, so a new list
/// of roots or of children shows then.
/// A node's key ([nodeKey], by default the node itself) keeps its label's
/// [State] while the rows around it come and go, and is what the
/// controller expands and selects: no two nodes have the same.
///
/// A click on a node selects it and gives the view the focus; a click on
/// its expander expands or collapses it. While the view has the focus, Up
/// and Down select the node above and below, Page Up and Page Down a
/// window's rows away, Home and End the first and the last; Right expands
/// the node selected, or selects its first child when it is expanded, and
/// Left collapses it, or selects its parent when it is collapsed; `+`
/// expands it, `-` collapses it and `*` expands it and every node below it,
/// those whose children come in a future as they come. Enter calls
/// [onActivated] with the node selected, or without one expands or
/// collapses it. A node collapsed by a key or a click is selected when the
/// node selected was below it. A key that does nothing there goes on to
/// the nodes above. The view scrolls the least that shows the node
/// selected after each of them, and as the controller selects another;
/// it shows the one selected from the first frame.
///
/// The styles, each merged over those before it: [style] for every row,
/// over the theme's background and text; [guideStyle] for the guides;
/// for the row of the node selected, its label's text included
/// ([DefaultTextStyle]), [selectedStyle] while the view has the focus and
/// [unfocusedSelectedStyle] while it has not. One left null is the
/// theme's: [ThemeData.border], [ThemeData.selection] and
/// [ThemeData.selectionIdle] (or [selectedStyle] where that is given). A
/// failed load's error is in [ThemeData.error], its spinner in
/// [ThemeData.primary].
///
/// It takes all the room it is given, which must be bounded.
///
/// Folders under a root, their paths the nodes, each opened by Enter:
///
/// ```dart
/// TreeView<String>(
///   roots: const ['/'],
///   children: (path) => folders[path] ?? const [],
///   label: (context, entry) => Text(entry.node),
///   onActivated: open,
/// )
/// ```
///
/// See also:
///
///  * [TreeTable], the same nodes in the columns of a table.
///  * [TreeController], what expands and selects the nodes.
///  * [ListView], what the rows are items of.
final class TreeView<T> extends StatefulWidget {
  /// Shows [roots] and the children of those [controller] expands, each
  /// labelled by [label].
  const TreeView({
    required this.roots,
    required this.children,
    required this.label,
    super.key,
    this.hasChildren,
    this.nodeKey,
    this.controller,
    this.onActivated,
    this.showGuides = true,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus,
    this.style,
    this.guideStyle,
    this.selectedStyle,
    this.unfocusedSelectedStyle,
  });

  /// The nodes at the top, in order.
  final List<T> roots;

  /// The children of a node, in order: a list, or a future of one.
  // called with the nodes, whose T is the view's own
  // ignore: unsafe_variance
  final FutureOr<List<T>> Function(T node) children;

  /// What shows of a node after its guides and expander: laid out a row
  /// tall and as wide as the rest of the row, so a [Text] that wraps shows
  /// its first line there.
  // ignore: unsafe_variance
  final Widget Function(BuildContext context, TreeEntry<T> entry) label;

  /// Whether a node has children, without asking for them; null asks
  /// [children].
  // ignore: unsafe_variance
  final bool Function(T node)? hasChildren;

  /// The key of a node, which the controller expands and selects and its
  /// label keeps its [State] by; null for the node itself.
  // ignore: unsafe_variance
  final Object Function(T node)? nodeKey;

  /// What is expanded and selected; null for one of its own.
  final TreeController? controller;

  /// Called with the node selected when Enter is pressed.
  // ignore: unsafe_variance
  final void Function(T node)? onActivated;

  /// Whether lines join the nodes to their parents.
  final bool showGuides;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// See [FocusNode.canRequestFocus].
  final bool? canRequestFocus;

  /// Every row, over the theme's background and text.
  final Style? style;

  /// The guides; [ThemeData.border] when null.
  final Style? guideStyle;

  /// The row of the node selected while the view has the focus;
  /// [ThemeData.selection] when null.
  final Style? selectedStyle;

  /// The row of the node selected while the view has not the focus; when
  /// null, [selectedStyle] where that is given, else
  /// [ThemeData.selectionIdle]. [ThemeData.selection] keeps the row as it
  /// is with the focus.
  final Style? unfocusedSelectedStyle;

  @override
  State<TreeView<T>> createState() => _TreeViewState<T>();
}

/// What a row of a [TreeView] shows in the place of an expander.
enum _Mark {
  /// A node without children: the guide goes on to the label.
  leaf,

  /// A node whose children are hidden: `▸`.
  collapsed,

  /// A node whose children show: `▾`.
  expanded,

  /// The row of a load: a spinner.
  loading,

  /// The row of a failed load: the error, as a leaf.
  failed,
}

/// The children of a node that [TreeView.children] gave in a future: none
/// while it runs, then its list or its error; [at] is the reload it was
/// asked for at.
final class _Load<T> {
  _Load(this.at);

  final int at;
  List<T>? children;
  Object? error;
  var failed = false;

  /// Whether its error was shown, below the node expanded.
  var shown = false;
}

/// The key of the row of a load below the node with [key].
@immutable
final class _LoadKey {
  const _LoadKey(this.key);

  final Object key;

  @override
  bool operator ==(Object other) => other is _LoadKey && other.key == key;

  @override
  int get hashCode => Object.hash(_LoadKey, key);
}

/// The rows of a [TreeView], the nodes shown in order: for each its node
/// (of the row of a load, the node loading) and key, and in one number its
/// depth, the row of its parent (-1 for a root), its mark and whether it
/// is the last of its parent's rows; the errors of the rows of failed
/// loads.
final class _Rows<T> {
  final nodes = <T>[];
  final keys = <Object>[];
  // (parent + 1) << 24 | depth << 4 | mark << 1 | last, a depth below 2^20
  // levels
  final _info = <int>[];
  final errors = <int, Object>{};

  int get length => keys.length;

  /// Whether [other] has the same rows: the same nodes, keys and places.
  bool same(_Rows<T> other) {
    final n = length;
    if (other.length != n || errors.length != other.errors.length) {
      return false;
    }
    for (var i = 0; i < n; i++) {
      if (!identical(nodes[i], other.nodes[i]) ||
          keys[i] != other.keys[i] ||
          _info[i] != other._info[i]) {
        return false;
      }
    }
    return errors.entries.every((e) => other.errors[e.key] == e.value);
  }

  /// Adds a row; its index.
  int add(
    T node,
    Object key,
    int depth,
    int parent,
    _Mark mark, {
    required bool last,
  }) {
    nodes.add(node);
    keys.add(key);
    _info.add(
      (parent + 1) << 24 | depth << 4 | mark.index << 1 | (last ? 1 : 0),
    );
    return keys.length - 1;
  }

  int depth(int i) => (_info[i] >> 4) & 0xFFFFF;

  /// The row of the parent of row [i]; -1 for a root.
  int parent(int i) => (_info[i] >> 24) - 1;

  _Mark mark(int i) => _Mark.values[(_info[i] >> 1) & 7];

  /// Whether row [i] is the last of its parent's.
  bool last(int i) => _info[i] & 1 != 0;

  /// Whether row [i] is a node's, not a load's.
  bool isNode(int i) {
    final mark = this.mark(i);
    return mark != _Mark.loading && mark != _Mark.failed;
  }

  /// The row after the last of those below row [i].
  int end(int i) {
    final d = depth(i);
    var j = i + 1;
    while (j < length && depth(j) > d) {
      j++;
    }
    return j;
  }

  /// For each depth from 1 below that of row [i], whether the guide of the
  /// row's ancestor there goes on down past it: it is not the last child.
  List<bool> lines(int i) {
    final d = depth(i);
    final lines = List<bool>.filled(d > 1 ? d - 1 : 0, false);
    for (var p = parent(i); p >= 0 && depth(p) >= 1; p = parent(p)) {
      lines[depth(p) - 1] = !last(p);
    }
    return lines;
  }
}

/// What the state of a [TreeView] and of a [TreeTable] share: the nodes
/// shown ([_shown]), worked out from the roots and the nodes the
/// controller expands, the children that came in futures, kept by key, and
/// what the keys do to the node selected but move it.
mixin _TreeModel<T, W extends StatefulWidget> on State<W> {
  /// What is expanded and selected.
  TreeController get _controller;

  /// The roots, the children of a node, whether it has any and its key, as
  /// the widget gives them.
  List<T> get _roots;
  // called with the nodes, whose T is the state's own
  // ignore: unsafe_variance
  FutureOr<List<T>> Function(T node) get _childrenOf;
  // as is this
  // ignore: unsafe_variance
  bool Function(T node)? get _hasChildren;
  // as is this
  // ignore: unsafe_variance
  Object Function(T node)? get _nodeKey;

  /// A load of children ended: [_shown] has changed.
  void _loadEnded();

  /// Selects the node of row [i] of [rows] and shows it; whether that is
  /// another node.
  bool _select(_Rows<T> rows, int i);

  // the children that came in futures, by node key; one more for each
  // load that ended
  final _loads = <Object, _Load<T>>{};
  var _loaded = 0;

  // the nodes whose children, once loaded, are expanded with every node
  // below them
  final _deep = <Object>{};

  // the rows, and what they were worked out for
  _Rows<T>? _rows;
  W? _rowsWidget;
  TreeController? _rowsController;
  var _rowsVersion = -1;
  var _rowsLoaded = -1;

  // where the selected key was found in the rows: -1 for nowhere
  Object? _foundKey;
  _Rows<T>? _foundIn;
  var _found = -1;

  Object _keyOf(T node) {
    final key = _nodeKey;
    return key == null ? node as Object : key(node);
  }

  /// The children of [node], whose key is [key]: a list [TreeView.children]
  /// gave, or that a future of it ended with; null while the future runs
  /// and after it failed ([_loads] has it), which is started here when
  /// none is.
  List<T>? _children(T node, Object key) {
    final load = _loads.isEmpty ? null : _loads[key];
    if (load != null) {
      if (!_controller._reloadedSince(key, load.at)) {
        return load.children;
      }
      _loads.remove(key);
    }
    final children = _childrenOf(node);
    if (children is! Future<List<T>>) {
      return children;
    }
    final started = _loads[key] = _Load<T>(_controller._reloads);
    unawaited(
      children.then<void>(
        (list) {
          started.children = list;
          _ended(key, started);
        },
        onError: (Object error, StackTrace stack) {
          started
            ..error = error
            ..failed = true;
          _ended(key, started);
        },
      ),
    );
    return null;
  }

  /// [load] of the children of [key] ended.
  void _ended(Object key, _Load<T> load) {
    if (!mounted || !identical(_loads[key], load)) {
      return;
    }
    _loaded++;
    _loadEnded();
    if (_deep.remove(key)) {
      if (load.children case final children?) {
        _expandBelow(children);
      }
    }
  }

  /// The rows, worked out again when the widget, the nodes expanded or
  /// the loads changed.
  _Rows<T> get _shown {
    final c = _controller;
    final rows = _rows;
    if (rows != null &&
        identical(widget, _rowsWidget) &&
        identical(c, _rowsController) &&
        c._version == _rowsVersion &&
        _loaded == _rowsLoaded) {
      return rows;
    }
    _rowsWidget = widget;
    _rowsController = c;
    _rowsVersion = c._version;
    _rowsLoaded = _loaded;
    return _rows = _walk();
  }

  /// The nodes shown, in order: the roots, and below each node expanded
  /// its children, or the row of their load.
  _Rows<T> _walk() {
    final c = _controller;
    final has = _hasChildren;
    final rows = _Rows<T>();
    // a list of siblings for each depth, the next of them, and the row of
    // their parent
    final lists = <List<T>>[_roots];
    final next = <int>[0];
    final parents = <int>[-1];
    while (lists.isNotEmpty) {
      final depth = lists.length - 1;
      final list = lists[depth];
      final i = next[depth];
      if (i >= list.length) {
        lists.removeLast();
        next.removeLast();
        parents.removeLast();
        continue;
      }
      next[depth] = i + 1;
      final node = list[i];
      final key = _keyOf(node);
      final parent = parents[depth];
      final last = i == list.length - 1;
      final known = has?.call(node);
      if (known == false) {
        rows.add(node, key, depth, parent, _Mark.leaf, last: last);
        continue;
      }
      if (!c.isExpanded(key)) {
        final load = _loads.isEmpty ? null : _loads[key];
        if (load != null && load.failed && load.shown) {
          _loads.remove(key);
        }
        final children = known != null ? null : _children(node, key);
        rows.add(
          node,
          key,
          depth,
          parent,
          children != null && children.isEmpty ? _Mark.leaf : _Mark.collapsed,
          last: last,
        );
        continue;
      }
      final children = _children(node, key);
      if (known == null && children != null && children.isEmpty) {
        rows.add(node, key, depth, parent, _Mark.leaf, last: last);
        continue;
      }
      final row = rows.add(
        node,
        key,
        depth,
        parent,
        _Mark.expanded,
        last: last,
      );
      if (children == null) {
        final load = _loads[key]!;
        if (load.failed) {
          load.shown = true;
          rows.errors[rows.length] = load.error!;
        }
        rows.add(
          node,
          _LoadKey(key),
          depth + 1,
          row,
          load.failed ? _Mark.failed : _Mark.loading,
          last: true,
        );
      } else if (children.isNotEmpty) {
        lists.add(children);
        next.add(0);
        parents.add(row);
      }
    }
    return rows;
  }

  /// The row of the node selected; -1 for none.
  int _selectedRow(_Rows<T> rows) {
    final key = _controller.selectedKey;
    if (key == null) {
      return -1;
    }
    if (key == _foundKey && identical(rows, _foundIn)) {
      return _found;
    }
    var found = -1;
    for (var i = 0; i < rows.length; i++) {
      if (rows.keys[i] == key && rows.isNode(i)) {
        found = i;
        break;
      }
    }
    _foundKey = key;
    _foundIn = rows;
    return _found = found;
  }

  /// Hides the children of the node of row [i]; it is selected when the
  /// node selected was below it.
  void _collapse(_Rows<T> rows, int i) {
    final at = _selectedRow(rows);
    if (at > i && at < rows.end(i)) {
      _select(rows, i);
    }
    _controller.collapse(rows.keys[i]);
  }

  /// Expands the node of row [i] when it is collapsed and the other way;
  /// whether it has children.
  bool _toggle(_Rows<T> rows, int i) {
    switch (rows.mark(i)) {
      case _Mark.collapsed:
        _controller.expand(rows.keys[i]);
        return true;
      case _Mark.expanded:
        _collapse(rows, i);
        return true;
      case _Mark.leaf || _Mark.loading || _Mark.failed:
        return false;
    }
  }

  /// The row of the first child shown of the node of row [at], expanded;
  /// -1 for none, or for the row of a load.
  int _firstChild(_Rows<T> rows, int at) {
    final child = at + 1;
    return child < rows.length && rows.parent(child) == at && rows.isNode(child)
        ? child
        : -1;
  }

  /// Right: expands the node selected, or selects its first child.
  bool _right() {
    final rows = _shown;
    final at = _selectedRow(rows);
    if (at < 0) {
      return false;
    }
    switch (rows.mark(at)) {
      case _Mark.collapsed:
        _controller.expand(rows.keys[at]);
        return true;
      case _Mark.expanded:
        final child = _firstChild(rows, at);
        return child >= 0 && _select(rows, child);
      case _Mark.leaf || _Mark.loading || _Mark.failed:
        return false;
    }
  }

  /// Left: collapses the node selected, or selects its parent.
  bool _left() {
    final rows = _shown;
    final at = _selectedRow(rows);
    if (at < 0) {
      return false;
    }
    if (rows.mark(at) == _Mark.expanded) {
      _collapse(rows, at);
      return true;
    }
    final parent = rows.parent(at);
    return parent >= 0 && _select(rows, parent);
  }

  /// `+` and `-`: expands or collapses the node selected; whether it was
  /// not already.
  bool _expandSelected({required bool expand}) {
    final rows = _shown;
    final at = _selectedRow(rows);
    if (at < 0 ||
        rows.mark(at) != (expand ? _Mark.collapsed : _Mark.expanded)) {
      return false;
    }
    return _toggle(rows, at);
  }

  /// `*`: expands the node selected and every node below it; whether it
  /// has children.
  bool _expandAllSelected() {
    final rows = _shown;
    final at = _selectedRow(rows);
    if (at < 0 || rows.mark(at) == _Mark.leaf || !rows.isNode(at)) {
      return false;
    }
    _expandBelow([rows.nodes[at]]);
    return true;
  }

  /// Expands [nodes] and every node below them that has children: those
  /// whose children come in a future as they come.
  void _expandBelow(List<T> nodes) {
    final has = _hasChildren;
    final keys = <Object>[];
    final stack = [...nodes.reversed];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (has?.call(node) == false) {
        continue;
      }
      final key = _keyOf(node);
      final children = _children(node, key);
      if (children == null) {
        if (!_loads[key]!.failed) {
          _deep.add(key);
        }
        keys.add(key);
      } else if (children.isNotEmpty) {
        keys.add(key);
        stack.addAll(children.reversed);
      }
    }
    _controller.expandAll(keys);
  }
}

final class _TreeViewState<T> extends State<TreeView<T>>
    with _TreeModel<T, TreeView<T>> {
  TreeController? _own;
  FocusNode? _ownNode;
  final _list = ListController();

  @override
  TreeController get _controller =>
      widget.controller ?? (_own ??= TreeController());

  @override
  List<T> get _roots => widget.roots;

  @override
  // called with the nodes, whose T is the state's own
  // ignore: unsafe_variance
  FutureOr<List<T>> Function(T node) get _childrenOf => widget.children;

  @override
  // as is this
  // ignore: unsafe_variance
  bool Function(T node)? get _hasChildren => widget.hasChildren;

  @override
  // as is this
  // ignore: unsafe_variance
  Object Function(T node)? get _nodeKey => widget.nodeKey;

  @override
  void _loadEnded() => setState(() {});

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  // the key selected when the view last followed it; none before the
  // first build
  Object? _followed;

  @override
  void initState() {
    super.initState();
    _node.addListener(_focusChanged);
    _controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(TreeView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.focusNode, oldWidget.focusNode)) {
      // the Focus below lets an own node go after this build: it is
      // disposed with this state
      (oldWidget.focusNode ?? _ownNode)?.removeListener(_focusChanged);
      _node.addListener(_focusChanged);
    }
    if (!identical(widget.controller, oldWidget.controller)) {
      (oldWidget.controller ?? _own)?.removeListener(_changed);
      _controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _node.removeListener(_focusChanged);
    _own?.dispose();
    _ownNode?.dispose();
    _list.dispose();
    super.dispose();
  }

  void _focusChanged() => setState(() {});

  void _changed() => setState(() {});

  /// Selects the node of row [i] and scrolls it into view; whether that is
  /// another node.
  @override
  bool _select(_Rows<T> rows, int i) {
    final key = rows.keys[i];
    final moved = key != _controller.selectedKey;
    _foundKey = key;
    _foundIn = rows;
    _found = i;
    _followed = key;
    _controller.selectedKey = key;
    _list.ensureIndexVisible(i);
    return moved;
  }

  /// Selects the node [by] rows from the one selected, from none the
  /// first; whether that is another node.
  bool _move(int by) {
    final at = _selectedRow(_shown);
    return _selectNear(at < 0 ? 0 : at + by, by);
  }

  /// Selects the node of row [i], within the rows, or of the row past a
  /// load's the way [by] goes; whether that is another node.
  bool _selectNear(int i, int by) {
    final rows = _shown;
    if (rows.length == 0) {
      return false;
    }
    var at = i < 0 ? 0 : (i >= rows.length ? rows.length - 1 : i);
    // a load's row has its node's above it
    while (!rows.isNode(at)) {
      at += by > 0 && at + 1 < rows.length ? 1 : -1;
    }
    return _select(rows, at);
  }

  /// The rows of a window.
  int get _page {
    final rows = _list.hasClients ? _list.position.viewportExtent : 1;
    return rows > 1 ? rows : 1;
  }

  /// Enter: [TreeView.onActivated] with the node selected, or without it
  /// expands or collapses it.
  bool _activate() {
    final rows = _shown;
    final at = _selectedRow(rows);
    if (at < 0) {
      return false;
    }
    final activated = widget.onActivated;
    if (activated == null) {
      return _toggle(rows, at);
    }
    activated(rows.nodes[at]);
    return true;
  }

  static final Map<String, KeyCombo> _combos = {
    for (final key in [
      'up',
      'down',
      'pageup',
      'pagedown',
      'home',
      'end',
      'left',
      'right',
      '+',
      '-',
      '*',
      'enter',
    ])
      key: KeyCombo.parse(key),
  };

  /// What each key does: whether it did anything.
  Map<String, bool Function()> get _keys => {
    'up': () => _move(-1),
    'down': () => _move(1),
    'pageup': () => _move(-_page),
    'pagedown': () => _move(_page),
    'home': () => _selectNear(0, -1),
    'end': () => _selectNear(_shown.length - 1, 1),
    'left': _left,
    'right': _right,
    '+': () => _expandSelected(expand: true),
    '-': () => _expandSelected(expand: false),
    '*': _expandAllSelected,
    'enter': _activate,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // only while it has the focus, whichever keys reach its node
    if (event.kind == KeyKind.release || !node.hasFocus) {
      return KeyEventResult.ignored;
    }
    for (final MapEntry(:key, :value) in _keys.entries) {
      if (_combos[key]!.accepts(event)) {
        return value() ? KeyEventResult.handled : KeyEventResult.ignored;
      }
    }
    return KeyEventResult.ignored;
  }

  /// A press on the row of [key], row [at] when it was built.
  void _rowDown(int at, Object key, PointerEvent event) {
    if (event.button != 0) {
      return;
    }
    if (_node.canRequestFocus) {
      _node.requestFocus();
    }
    final rows = _shown;
    final i = at < rows.length && rows.keys[at] == key
        ? at
        : rows.keys.indexOf(key);
    if (i < 0 || !rows.isNode(i)) {
      return;
    }
    final x = rows.depth(i) * 2;
    if (event.x >= x && event.x < x + 2 && _toggle(rows, i)) {
      return;
    }
    _select(rows, i);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final theme = Theme.of(context);
    final base = opaque(
      theme.background.merge(theme.text).merge(w.style ?? const Style()),
    );
    final selectedStyle = base.merge(
      _node.hasFocus
          ? w.selectedStyle ?? theme.selection
          : w.unfocusedSelectedStyle ?? w.selectedStyle ?? theme.selectionIdle,
    );
    final guideStyle = w.guideStyle ?? theme.border;
    final rows = _shown;
    final selected = _selectedRow(rows);
    if (_controller.selectedKey != _followed) {
      _followed = _controller.selectedKey;
      if (selected >= 0) {
        _list.ensureIndexVisible(selected);
      }
    }
    return Focus(
      focusNode: _node,
      autofocus: w.autofocus,
      canRequestFocus: w.canRequestFocus,
      onKeyEvent: _onKey,
      child: ListView.builder(
        itemCount: rows.length,
        itemExtent: 1,
        controller: _list,
        canRequestFocus: false,
        style: w.style,
        itemBuilder: (context, i) => _row(
          context,
          rows,
          i,
          i == selected ? selectedStyle : base,
          guideStyle,
          theme,
          selected: i == selected,
        ),
      ),
    );
  }

  /// Row [i] of [rows] in [style], its guides in [guideStyle] over it.
  Widget _row(
    BuildContext context,
    _Rows<T> rows,
    int i,
    Style style,
    Style guideStyle,
    ThemeData theme, {
    required bool selected,
  }) {
    final mark = rows.mark(i);
    final Widget child;
    switch (mark) {
      case _Mark.loading:
        child = const Spinner();
      case _Mark.failed:
        child = Text(
          '${rows.errors[i]}',
          style: theme.error,
          wrap: TextWrap.none,
          overflow: TextOverflow.ellipsis,
        );
      case _Mark.leaf || _Mark.collapsed || _Mark.expanded:
        child = widget.label(
          context,
          TreeEntry(
            node: rows.nodes[i],
            key: rows.keys[i],
            depth: rows.depth(i),
            hasChildren: mark != _Mark.leaf,
            expanded: mark == _Mark.expanded,
            selected: selected,
          ),
        );
    }
    final key = rows.keys[i];
    return Listener(
      key: ValueKey<Object>(key),
      onDown: (event) => _rowDown(i, key, event),
      child: DefaultTextStyle(
        style: style,
        child: _TreeRow(
          level: rows.depth(i),
          lines: rows.lines(i),
          last: rows.last(i),
          mark: mark,
          guides: widget.showGuides,
          style: style,
          guideStyle: guideStyle,
          child: child,
        ),
      ),
    );
  }
}

/// A row of a [TreeView]: its guides and expander, then [child].
final class _TreeRow extends SingleChildRenderObjectWidget {
  const _TreeRow({
    required this.level,
    required this.lines,
    required this.last,
    required this.mark,
    required this.guides,
    required this.style,
    required this.guideStyle,
    super.child,
  });

  final int level;
  final List<bool> lines;
  final bool last;
  final _Mark mark;
  final bool guides;
  final Style style;
  final Style guideStyle;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderTreeRow createRenderObject(BuildContext context) => _RenderTreeRow(
    level: level,
    lines: lines,
    last: last,
    mark: mark,
    guides: guides,
    style: style,
    guideStyle: guideStyle,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderTreeRow renderObject) {
    renderObject
      ..level = level
      ..lines = lines
      ..last = last
      ..mark = mark
      ..guides = guides
      ..style = style
      ..guideStyle = guideStyle;
  }
}

// the glyphs of the guides, as the canvas draws them
final _glyphs = ChartGlyphs();

/// What a row of a [TreeView] lays out and paints: [level] levels of
/// guides two cells each, the expander [mark] in two more but for a
/// spinner's row, then its child, as wide as the rest of the row. It fills
/// the row with [style] and, with [guides], draws in [guideStyle] over it
/// the line of each ancestor that [lines] says goes on down and `├─`, or
/// `└─` when [last], to the node; the guide on to a leaf's label.
final class _RenderTreeRow extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderTreeRow({
    required this._level,
    required this._lines,
    required this._last,
    required this._mark,
    required this._guides,
    required this._style,
    required this._guideStyle,
  });

  int _level;
  int get level => _level;
  set level(int l) {
    if (l != _level) {
      _level = l;
      markNeedsLayout();
    }
  }

  List<bool> _lines;
  List<bool> get lines => _lines;
  set lines(List<bool> l) {
    if (!sameList(l, _lines)) {
      _lines = l;
      markNeedsPaint();
    }
  }

  bool _last;
  bool get last => _last;
  set last(bool l) {
    if (l != _last) {
      _last = l;
      markNeedsPaint();
    }
  }

  _Mark _mark;
  _Mark get mark => _mark;
  set mark(_Mark m) {
    if (m != _mark) {
      // a spinner's row has no expander before its child
      if ((m == _Mark.loading) != (_mark == _Mark.loading)) {
        markNeedsLayout();
      }
      _mark = m;
      markNeedsPaint();
    }
  }

  bool _guides;
  bool get guides => _guides;
  set guides(bool g) {
    if (g != _guides) {
      _guides = g;
      markNeedsPaint();
    }
  }

  Style _style;
  Style get style => _style;
  set style(Style s) {
    if (s != _style) {
      _style = s;
      markNeedsPaint();
    }
  }

  Style _guideStyle;
  Style get guideStyle => _guideStyle;
  set guideStyle(Style s) {
    if (s != _guideStyle) {
      _guideStyle = s;
      markNeedsPaint();
    }
  }

  /// Where the child starts.
  int get _indent => _level * 2 + (_mark == _Mark.loading ? 0 : 2);

  /// Hit wherever it is: it paints all of its cells.
  @override
  HitTestBehavior get hitTestBehavior => HitTestBehavior.opaque;

  @override
  int computeMinIntrinsicWidth(int height) =>
      _indent + (child?.getMinIntrinsicWidth(height) ?? 0);

  @override
  int computeMaxIntrinsicWidth(int height) =>
      _indent + (child?.getMaxIntrinsicWidth(height) ?? 0);

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    final indent = _indent;
    var w = indent;
    if (child case final child?) {
      final room = c.maxW >= BoxConstraints.unbounded
          ? c.maxW
          : (c.maxW > indent ? c.maxW - indent : 0);
      child.layout(
        room >= BoxConstraints.unbounded
            ? BoxConstraints(0, room, 0, 1)
            : BoxConstraints(room, room, 0, 1),
        parentUsesSize: true,
      );
      child.parentData
        ..dx = indent
        ..dy = 0;
      w += child.width;
    }
    width = c.constrainW(w);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    canvas.fill(0, 0, width, height, _style.penIn(styles));
    final level = _level;
    final mark = _mark;
    if (_guides && level > 0) {
      _glyphs.use(canvas.segmenter);
      final type = _glyphs.lines(BorderType.single);
      final pen = _style.merge(_guideStyle).penIn(styles);
      final down = type.glyph(up: true, down: true);
      for (var j = 0; j < _lines.length; j++) {
        if (_lines[j]) {
          canvas.fill(j * 2, 0, 1, 1, pen, down);
        }
      }
      final across = type.glyph(left: true, right: true);
      final x = (level - 1) * 2;
      canvas
        ..fill(
          x,
          0,
          1,
          1,
          pen,
          type.glyph(up: true, down: !_last, right: true),
        )
        ..fill(x + 1, 0, 1, 1, pen, across);
      if (mark == _Mark.leaf || mark == _Mark.failed) {
        canvas.fill(x + 2, 0, 1, 1, pen, across);
      }
    }
    if (mark == _Mark.collapsed || mark == _Mark.expanded) {
      canvas.fill(
        level * 2,
        0,
        1,
        1,
        _style.penIn(styles),
        mark == _Mark.expanded ? 0x25BE : 0x25B8,
      );
    }
    if (child case final child?) {
      paintChild(ctx, child);
    }
  }
}
