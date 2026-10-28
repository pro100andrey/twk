/// [JsonView], JSON and Dart values as a tree that folds, its
/// [JsonViewController], [jsonPath] that names where a value is, and
/// [jsonLines], the same look as lines of spans.
///
/// @docImport '../highlight/code_view.dart';
library;

import 'dart:async';
import 'dart:convert';

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show clipboardSequence;

import '../highlight/syntax_theme.dart';

part 'nodes.dart';

// Examples can assume:
// late Map<String, Object?> config;
// late String response;

/// What a [JsonView] shows: the objects and arrays expanded, and the value
/// selected, both by path ([jsonPath]); it notifies its listeners of each
/// change.
///
/// Those less than [expandedDepth] levels below the top are expanded as
/// it first meets a value; then each stays as the keys, a click or this
/// controller left it, by path, while the value changes around it. Without
/// a view, [expandAll] waits for one, and [selectedValue] is null.
///
/// A view whose controller reveals a value and reads what is selected:
///
/// ```dart
/// final controller = JsonViewController(expandedDepth: 0)
///   ..reveal(r'$.scripts[0]');
/// final view = JsonView(value: config, controller: controller);
/// // later, as the selection changes
/// print('${controller.selectedPath}: ${controller.selectedValue}');
/// ```
final class JsonViewController extends ChangeNotifier {
  /// Expands what is less than [expandedDepth] levels below the top: the
  /// top object or array alone, by default.
  JsonViewController({this.expandedDepth = 1}) {
    _tree.addListener(notifyListeners);
  }

  /// How many levels from the top are expanded as the view first shows a
  /// value: 0 for none.
  final int expandedDepth;

  final _tree = TreeController();

  // the paths of the strings shown whole
  final _whole = <String>{};

  // the view shown with it, and whether a view has shown a value yet
  _JsonViewState? _view;
  var _started = false;
  var _expandAll = false;

  /// The path of the value selected; null for none.
  ///
  /// The row that closes an object or array selects its path.
  String? get selectedPath => switch (_tree.selectedKey) {
    final String path => path,
    _Close(:final path) => path,
    _ => null,
  };

  /// The value selected, as it was given (not its `toJson()`); null for
  /// none, without a view, and for a value that is null.
  Object? get selectedValue {
    final path = selectedPath;
    return path == null ? null : _view?._find(path)?.raw;
  }

  /// Whether the object or array at [path] is expanded.
  bool isExpanded(String path) => _tree.isExpanded(path);

  /// Expands every object and array; without a view, the first value one
  /// shows.
  void expandAll() {
    final root = _view?._root;
    if (root == null) {
      _expandAll = true;
      return;
    }
    _tree.expandAll(_containers(root));
  }

  /// Collapses every object and array; the top one is selected where the
  /// value selected was below it.
  void collapseAll() {
    _expandAll = false;
    final root = _view?._root;
    if (root != null && selectedPath != null && selectedPath != root.path) {
      _tree.selectedKey = root.path;
    }
    _tree.collapseAll();
  }

  /// Selects the value at [path] and expands those above it, so that it
  /// shows; the view scrolls to it.
  void reveal(String path) {
    final root = _view?._rootName ?? path.substring(0, _rootEnd(path));
    _tree
      ..expandAll(_ancestorsOf(path, root))
      ..selectedKey = path;
  }

  /// Where the root name ends in [path]: at its first `.` or `[`.
  static int _rootEnd(String path) {
    for (var i = 0; i < path.length; i++) {
      final c = path.codeUnitAt(i);
      if (c == 0x2E || c == 0x5B) {
        return i;
      }
    }
    return path.length;
  }

  /// The keys of [root] and the objects and arrays with entries below it,
  /// to [depth] levels below the top when given.
  static List<Object> _containers(_Node root, [int? depth]) {
    final keys = <Object>[];
    final stack = [root];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (!node.hasEntries || (depth != null && node.depth >= depth)) {
        continue;
      }
      keys.add(node.key);
      stack.addAll(node.entries);
    }
    return keys;
  }

  /// [view] shows [root]: the first value shown is expanded to
  /// [expandedDepth] and selected at its top.
  void _shown(_JsonViewState view, _Node root) {
    _view = view;
    if (!_started) {
      _started = true;
      _tree.expandAll(_containers(root, expandedDepth));
      _tree.selectedKey ??= root.path;
    }
    if (_expandAll) {
      _expandAll = false;
      _tree.expandAll(_containers(root));
    }
  }

  void _toggleWhole(String path) {
    if (!_whole.remove(path)) {
      _whole.add(path);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _tree.dispose();
    super.dispose();
  }
}

/// A JSON document or a Dart value as a tree: each object and array a row
/// that folds, its entries below it, indented and joined to it by guides,
/// and a row that closes it; each value in the style of its kind in
/// [theme], keys, strings, numbers, `true`, `false` and `null` and
/// brackets apart.
///
/// ```text
/// ▾ {
/// ├── "name": "twk",
/// ├─▸ "dependencies": { 4 keys },
/// ├─▾ "scripts": [
/// │ ├── "quick",
/// │ ├── "handover"
/// │ └── ]
/// └── }
/// ```
///
/// [value] is a [Map], a [List] (a [Set] shows as one), a [String], a
/// [num], a [bool] or null; any other object shows as what its `toJson()`
/// gives, or else as its `toString()` in a string; a value inside itself
/// shows as `<cycle>`. [JsonView.parse] shows JSON text, or the
/// [FormatException] it fails with and the place in it. A collapsed object
/// shows how many keys it has (`{ 4 keys }`), an array how many items
/// (`[ 2 items ]`). [sortKeys] orders an object's keys, which are
/// otherwise in the map's order; a string longer than [maxStringLength]
/// characters is cut with `…` until Enter shows it whole.
///
/// A [TreeView]'s rows and keys, its node selected the value selected:
/// Up and Down, Left and Right, Page Up and Down, Home and End move
/// through it, `*` expands the value selected and everything below it.
/// Besides, with the focus, hinted for a `KeyHintsBar`:
///
/// * Enter and Space fold the object or array selected, or show a string
///   cut whole and cut it again;
/// * `c` copies the path of the value selected ([jsonPath], from
///   [rootName]) to the clipboard and calls [onPathCopied] with it; `y`
///   copies the value as JSON, indented, to the clipboard (OSC 52, as a
///   `TextField` copies);
/// * `/` opens a field at the bottom whose text filters the keys, as a
///   `CommandPalette` does ([fuzzyMatch]): the objects' entries whose keys
///   match show, with what is below them, and the objects above them,
///   expanded, the characters found standing out; the best match is
///   selected. Enter goes back to the tree, the filter kept, Escape clears
///   it and puts back what was expanded.
///
/// What is expanded and selected is [controller]'s, by path; one of its
/// own when null, which expands the top value only. It takes all the room
/// it is given, which must be bounded.
///
/// An API's response, its keys in order:
///
/// ```dart
/// JsonView.parse(response, sortKeys: true, autofocus: true)
/// ```
///
/// See also:
///
///  * [jsonLines], the same look as lines of text, for a program's output.
///  * [TreeView], what the rows are.
///  * [CodeView], JSON as text, highlighted.
final class JsonView extends StatefulWidget {
  /// Shows [value] as a tree.
  const JsonView({
    required this.value,
    super.key,
    this.controller,
    this.rootName = r'$',
    this.onPathCopied,
    this.theme,
    this.sortKeys = false,
    this.maxStringLength = 200,
    this.focusNode,
    this.autofocus = false,
  }) : source = null;

  /// Shows the JSON value [source] is the text of, or where it is not one
  /// the [FormatException] [jsonDecode] fails with, and the line and column
  /// where.
  const JsonView.parse(
    String this.source, {
    super.key,
    this.controller,
    this.rootName = r'$',
    this.onPathCopied,
    this.theme,
    this.sortKeys = false,
    this.maxStringLength = 200,
    this.focusNode,
    this.autofocus = false,
  }) : value = null;

  /// The value shown; null for the text of [source].
  final Object? value;

  /// The JSON text shown, given to [JsonView.parse]; null for [value].
  final String? source;

  /// What is expanded and selected; null for one of its own.
  final JsonViewController? controller;

  /// The first segment of the paths: `$` by default.
  final String rootName;

  /// Called with the path `c` copied.
  final void Function(String path)? onPathCopied;

  /// The styles of the kinds of values; null for the one at its place
  /// ([SyntaxTheme.of]).
  final SyntaxTheme? theme;

  /// Whether the keys of objects show in order rather than the map's.
  final bool sortKeys;

  /// How many characters of a string show until Enter shows it whole; null
  /// for all of them.
  final int? maxStringLength;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  @override
  State<JsonView> createState() => _JsonViewState();
}

final class _JsonViewState extends State<JsonView> {
  JsonViewController? _own;
  FocusNode? _ownNode;
  final _field = TextEditingController();
  final _fieldNode = FocusNode();

  JsonViewController get _controller =>
      widget.controller ?? (_own ??= JsonViewController());

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  // the value shown, what it was made from, and the error of a parse
  _Node? _root;
  Object? _madeFrom;
  String? _madeWith;
  bool? _madeSorted;
  FormatException? _error;

  String get _rootName => widget.rootName;

  // the filter: null while there is none; the keys of the rows it keeps,
  // those it matched with the positions of the characters found, and the
  // keys expanded before it
  String? _query;
  Set<Object> _keep = const {};
  Map<Object, List<int>> _matches = const {};
  Set<Object>? _before;

  // whether the field is to take the focus once built
  var _focusField = false;

  @override
  void initState() {
    super.initState();
    _make();
    _controller.addListener(_changed);
    _fieldNode.addListener(_changed);
  }

  @override
  void didUpdateWidget(JsonView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      final old = oldWidget.controller ?? _own;
      old?.removeListener(_changed);
      if (old?._view == this) {
        old?._view = null;
      }
      _controller.addListener(_changed);
      _madeFrom = null;
      _root = null;
    }
    _make();
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (_controller._view == this) {
      _controller._view = null;
    }
    _own?.dispose();
    _ownNode?.dispose();
    _field.dispose();
    _fieldNode.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Makes the tree of the value anew when what it is made from changed.
  void _make() {
    final w = widget;
    final from = w.source ?? w.value;
    if (_root != null || _error != null) {
      if (identical(from, _madeFrom) &&
          w.rootName == _madeWith &&
          w.sortKeys == _madeSorted) {
        return;
      }
    }
    _madeFrom = from;
    _madeWith = w.rootName;
    _madeSorted = w.sortKeys;
    _error = null;
    var value = w.value;
    if (w.source case final source?) {
      try {
        value = jsonDecode(source);
      } on FormatException catch (error) {
        _error = error;
        _root = null;
        return;
      }
    }
    _root = _Node(
      null,
      null,
      value,
      w.rootName,
      last: true,
      sortKeys: w.sortKeys,
    );
    _controller._shown(this, _root!);
    if (_query != null) {
      _filter(_query!);
    }
  }

  /// The node at [path]; null for none.
  _Node? _find(String path) {
    var node = _root;
    if (node == null) {
      return null;
    }
    if (path == node.path) {
      return node;
    }
    final above = _ancestorsOf(path, node.path);
    if (above.isEmpty) {
      return null;
    }
    for (final step in [...above.skip(1), path]) {
      _Node? next;
      for (final child in node!.entries) {
        if (child.path == step) {
          next = child;
          break;
        }
      }
      if (next == null) {
        return null;
      }
      node = next;
    }
    return node;
  }

  /// The node selected; null for none.
  _Node? get _selected {
    final key = _controller._tree.selectedKey;
    return switch (key) {
      final String path => _find(path),
      _Close(:final path) => switch (_find(path)) {
        final container? => container.children.last,
        null => null,
      },
      _ => null,
    };
  }

  /// The children of [node] the filter keeps.
  List<_Node> _childrenOf(_Node node) {
    final children = node.children;
    if ((_query?.isEmpty ?? true) || _below(node)) {
      return children;
    }
    return [
      for (final child in children)
        if (child.closes != null || _keep.contains(child.key)) child,
    ];
  }

  /// Whether [node] is a match of the filter or below one.
  bool _below(_Node node) {
    for (_Node? n = node; n != null; n = n.parent) {
      if (_matches.containsKey(n.key)) {
        return true;
      }
    }
    return false;
  }

  /// Filters the keys by [query]: keeps those that match and those above
  /// them, expanded, and selects the best match.
  void _filter(String query) {
    final root = _root;
    if (root == null) {
      return;
    }
    final tree = _controller._tree;
    _before ??= {...tree.expanded};
    final keep = <Object>{};
    final matches = <Object, List<int>>{};
    _Node? best;
    var bestScore = -1;
    if (query.isNotEmpty) {
      final stack = [root];
      while (stack.isNotEmpty) {
        final node = stack.removeLast();
        if (node.keyText case final key?) {
          if (fuzzyMatch(query, key) case final match?) {
            matches[node.key] = match.positions;
            if (match.score > bestScore) {
              bestScore = match.score;
              best = node;
            }
            for (_Node? n = node; n != null && keep.add(n.key); n = n.parent) {}
          }
        }
        stack.addAll(node.entries.toList().reversed);
      }
    }
    _keep = keep;
    _matches = matches;
    tree.expandAll([
      for (final key in keep)
        if (!matches.containsKey(key)) key,
    ]);
    if (best != null) {
      tree.selectedKey = best.key;
    }
  }

  /// Opens the filter's field, or gives it the focus.
  void _openFilter() {
    if (_query == null) {
      setState(() {
        _query = '';
        _focusField = true;
      });
      _filter('');
    } else {
      _fieldNode.requestFocus();
    }
  }

  /// Takes the filter away and puts back what was expanded, the value
  /// selected showing.
  void _closeFilter() {
    final before = _before;
    final selected = _controller.selectedPath;
    setState(() {
      _query = null;
      _keep = const {};
      _matches = const {};
      _before = null;
    });
    _field.clear();
    if (before != null) {
      _controller._tree
        ..collapseAll()
        ..expandAll(before);
    }
    if (selected != null) {
      _controller.reveal(selected);
    }
    if (_node.canRequestFocus) {
      _node.requestFocus();
    }
  }

  void _typed(String text) {
    setState(() => _query = text);
    _filter(text);
  }

  void _submitted(String text) {
    if (text.isEmpty) {
      _closeFilter();
    } else {
      _node.requestFocus();
    }
  }

  /// Enter and Space: fold the object or array selected, or show a string
  /// whole or cut.
  void _activate([_Node? at]) {
    final node = at ?? _selected;
    if (node == null) {
      return;
    }
    final container = node.closes ?? node;
    final tree = _controller._tree;
    if (container.hasEntries) {
      if (node.closes != null) {
        tree.selectedKey = container.key;
      }
      tree.toggle(container.key);
    } else if (node.cut(widget.maxStringLength)) {
      _controller._toggleWhole(node.path);
    }
  }

  /// Copies [text] to the clipboard of the terminal the app runs in.
  void _copy(String text) {
    final terminal = AppBinding.maybeOf(context)?.twkApp.terminal;
    if (terminal == null) {
      return;
    }
    terminal.write(
      ascii.encode(
        clipboardSequence(text, multiplexer: terminal.info.multiplexer),
      ),
    );
  }

  void _copyPath() {
    final path = _controller.selectedPath;
    if (path == null) {
      return;
    }
    _copy(path);
    widget.onPathCopied?.call(path);
  }

  void _copyValue() {
    final node = _selected;
    if (node == null) {
      return;
    }
    _copy((node.closes ?? node).encoded);
  }

  /// What Enter does to [node], for its hint; null for nothing.
  String? _enterHint(_Node? node) {
    if (node == null) {
      return null;
    }
    final container = node.closes ?? node;
    if (container.hasEntries) {
      return _controller.isExpanded(container.path) ? 'collapse' : 'expand';
    }
    if (node.cut(widget.maxStringLength)) {
      return _controller._whole.contains(node.path) ? 'cut' : 'show whole';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final syntax = widget.theme ?? SyntaxTheme.of(context);
    final root = _root;
    if (root == null) {
      return _failed(theme);
    }
    final typing = _fieldNode.hasFocus;
    final selected = _selected;
    final enter = typing ? null : _enterHint(selected);
    final whole = _controller._whole;
    final max = widget.maxStringLength;
    final tree = TreeView<_Node>(
      roots: [root],
      children: _childrenOf,
      hasChildren: (node) => node.hasEntries,
      nodeKey: (node) => node.key,
      controller: _controller._tree,
      focusNode: _node,
      autofocus: widget.autofocus,
      onActivated: _activate,
      label: (context, entry) => Text.rich(
        _rowSpans(
          entry.node,
          syntax,
          expanded: entry.expanded,
          whole: whole.contains(entry.node.path),
          maxStringLength: max,
          marks: _matches[entry.key] ?? const [],
        ),
        wrap: TextWrap.none,
      ),
    );
    final filtering = _query != null;
    if (_focusField) {
      // once the field is in the tree
      _focusField = false;
      scheduleMicrotask(() {
        if (mounted) {
          _fieldNode.requestFocus();
        }
      });
    }
    return KeyBindings(
      {
        if (!typing) ...{
          if (enter != null) ...{'enter': _activate, 'space': _activate},
          'c': _copyPath,
          'y': _copyValue,
          '/': _openFilter,
        },
        if (filtering) 'escape': _closeFilter,
      },
      hints: {
        if (!typing) ...{
          if (enter != null) ...{'enter': enter, 'space': enter},
          'c': 'copy path',
          'y': 'copy value',
          '/': 'filter keys',
        },
        if (filtering) 'escape': 'clear filter',
      },
      // the tree keeps its place as the field comes and goes
      child: Column(
        children: [
          Expanded(child: tree),
          if (filtering)
            Row(
              children: [
                SizedBox(width: 2, child: Text('/', style: theme.muted)),
                Expanded(
                  child: TextField(
                    controller: _field,
                    focusNode: _fieldNode,
                    placeholder: 'filter keys',
                    onChanged: _typed,
                    onSubmitted: _submitted,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// The error of a parse: its message, then the line it failed in with a
  /// caret under the place.
  Widget _failed(ThemeData theme) {
    final error = _error;
    final source = widget.source ?? '';
    final offset = error?.offset;
    final lines = <Widget>[];
    var message = error?.message ?? 'Not JSON';
    if (offset != null && offset >= 0 && offset <= source.length) {
      final before = source.substring(0, offset);
      final line = '\n'.allMatches(before).length + 1;
      final start = before.lastIndexOf('\n') + 1;
      var end = source.indexOf('\n', offset);
      if (end < 0) {
        end = source.length;
      }
      final column = offset - start + 1;
      message = '$message at line $line, column $column';
      lines
        ..add(Text(source.substring(start, end), wrap: TextWrap.none))
        ..add(Text('${' ' * (column - 1)}^', style: theme.error));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: theme.error, wrap: TextWrap.none),
        ...lines,
      ],
    );
  }
}
