/// What `twk inspect` shows: [InspectorView].
library;

import 'dart:async';

import 'package:twk/twk.dart';

import 'app_client.dart';

/// What `twk inspect` shows of a running app ([AppClient]): its widget
/// tree, or its render tree, in a [TreeView], and the selected node's
/// properties and layout beside it, the node outlined on the app's screen;
/// a status row and the keys below.
///
/// The apps come from [apps], each in place of the one before: a new one
/// starts over, its tree loaded and the node of its app's widget selected
/// (`ext.twk.tree`'s `app`, below the binding's own). While none is there
/// the status says [waiting]; once one has gone, [gone] if given.
///
/// The tree is loaded as the app comes, on `r`, as this terminal gets the
/// focus back (a focus event) and after a pick, and again shortly while
/// the app has drawn no frame; ids keep the nodes expanded and selected
/// across loads, a node not seen before expanded.
/// A node selected has its properties (`ext.twk.properties`) and layout
/// (`ext.twk.layout`) shown, and is outlined on the app's screen
/// (`ext.twk.highlight`) while `h` has it so. `s` has the app pick a node
/// (`ext.twk.flags` `select`): the next click on its screen selects the
/// node there (`ext.twk.select`), its ancestors expanded; `s` again, or
/// Escape in the app, cancels. `t` shows the other tree, the counterpart
/// of the node selected selected; `q` and Ctrl+C take the pick and the
/// outline off the app and quit.
final class InspectorView extends StatefulWidget {
  /// A view of the apps [apps] gives, one after another, showing
  /// [waiting] until the first comes and [gone], if given, when one has
  /// gone.
  const InspectorView({
    required this.apps,
    required this.waiting,
    this.gone,
    super.key,
  });

  /// The apps to inspect, one after another.
  final Stream<AppClient> apps;

  /// What the status says while no app has come.
  final String waiting;

  /// What it says once an app has gone; [waiting] when null.
  final String? gone;

  @override
  State<InspectorView> createState() => _InspectorViewState();
}

/// A node of a tree an app describes (`ext.twk.tree`).
final class _Node {
  _Node(this.json)
    : id = json['id']! as int,
      children = [
        for (final child in json['children'] as List<Object?>? ?? const [])
          _Node(child! as Json),
      ];

  final Json json;
  final int id;
  final List<_Node> children;

  String get name => json['name'] as String? ?? '?';

  /// The id of the node's counterpart in the other tree: an element's
  /// render object, a render object's element.
  int? get counterpart => (json['render'] ?? json['element']) as int?;

  /// The value of its first property without a name, which says most of
  /// it (a text's string).
  String? get summary {
    for (final p in json['properties'] as List<Object?>? ?? const []) {
      if (p case final Json p when p['name'] == null) {
        return p['value'] as String?;
      }
    }
    return null;
  }

  Iterable<_Node> get all sync* {
    yield this;
    for (final c in children) {
      yield* c.all;
    }
  }
}

final class _InspectorViewState extends State<InspectorView> {
  final _controller = TreeController();
  final _split = SplitController(fractions: [0.55, 0.45]);
  StreamSubscription<AppClient>? _apps;
  StreamSubscription<(int, int)?>? _picks;
  AppClient? _app;
  var _wasConnected = false;

  // the render tree is shown, not the element tree
  var _render = false;
  _Node? _root;
  var _ids = <int, _Node>{};
  final _seen = <int>{};

  // the node whose details are shown, and they
  int? _shown;
  Json? _properties;
  Json? _layout;
  String? _detailsError;

  // the controller forgets an app's nodes, which is nothing to show
  var _forgetting = false;

  var _highlight = true;
  var _picking = false;
  var _status = '';

  /// How long after a tree without a root it is loaded again.
  static const _unmounted = Duration(milliseconds: 200);

  Timer? _again;

  // the last load of the tree, and of the details: an answer to an
  // earlier one is dropped
  var _load = 0;
  var _details = 0;

  @override
  void initState() {
    super.initState();
    _status = widget.waiting;
    _controller.addListener(_selected);
    _listen();
  }

  @override
  void didUpdateWidget(InspectorView old) {
    super.didUpdateWidget(old);
    if (!identical(widget.apps, old.apps)) {
      unawaited(_apps?.cancel());
      _listen();
    }
  }

  void _listen() {
    _apps = widget.apps.listen(
      _attach,
      onError: (Object e) => setState(() => _status = '$e'),
    );
  }

  @override
  void dispose() {
    _again?.cancel();
    unawaited(_apps?.cancel());
    unawaited(_picks?.cancel());
    _controller.dispose();
    _split.dispose();
    super.dispose();
  }

  void _attach(AppClient app) {
    unawaited(_picks?.cancel());
    _picks = app.picks.listen(_picked);
    unawaited(
      app.done.then((_) {
        if (mounted && identical(_app, app)) {
          setState(() {
            _app = null;
            _picking = false;
            _status = widget.gone ?? widget.waiting;
          });
        }
      }),
    );
    setState(() {
      _app = app;
      _wasConnected = true;
      _root = null;
      _ids = {};
      _seen.clear();
      _shown = null;
      _properties = null;
      _layout = null;
      _detailsError = null;
      _picking = false;
      _status = 'inspecting ${app.name}';
    });
    // the old app's nodes, which the new one's ids do not name
    _forgetting = true;
    _controller
      ..collapseAll()
      ..selectedKey = null;
    _forgetting = false;
    unawaited(_refresh());
  }

  /// Calls [method] of the app, saying in the status why it failed; null
  /// then, and without an app.
  Future<Json?> _call(
    String method, [
    Map<String, String> params = const {},
  ]) async {
    final app = _app;
    if (app == null) {
      return null;
    }
    try {
      return await app.call(method, params);
    } on AppError catch (e) {
      if (mounted && identical(app, _app)) {
        setState(() => _status = e.message);
      }
      return null;
    }
  }

  /// Loads the tree shown, then selects [select] when it is in it, the node
  /// selected before when that is, else the top one.
  Future<void> _refresh({int? select}) async {
    final load = ++_load;
    final json = await _call('tree', {if (_render) 'tree': 'render'});
    if (json == null || load != _load || !mounted) {
      return;
    }
    final top = json['root'] as Json?;
    _again?.cancel();
    if (top == null) {
      // the app has drawn no frame, which mounts its tree
      _again = Timer(_unmounted, () => unawaited(_refresh(select: select)));
    }
    final all = top == null ? null : _Node(top);
    final app = json['app'] as int?;
    final ids = {for (final n in all?.all ?? const <_Node>[]) n.id: n};
    final root = ids[app] ?? all;
    final fresh = [
      for (final id in ids.keys)
        if (_seen.add(id)) id,
    ];
    setState(() {
      _root = root;
      _ids = ids;
    });
    _controller.expandAll(fresh);
    final before = _controller.selectedKey;
    final shown = {for (final n in root?.all ?? const <_Node>[]) n.id};
    // the node may be the same, its details not
    _shown = null;
    _controller.selectedKey = shown.contains(select)
        ? select
        : shown.contains(before)
        ? before
        : root?.id;
    _selected();
  }

  /// Shows the details of the node selected, and outlines it.
  void _selected() {
    final id = _controller.selectedKey as int?;
    if (_forgetting || id == _shown) {
      return;
    }
    _shown = id;
    unawaited(_showDetails(id));
    if (_highlight) {
      unawaited(_call('highlight', {if (id != null) 'id': '$id'}));
    }
  }

  Future<void> _showDetails(int? id) async {
    final load = ++_details;
    if (id == null) {
      setState(() {
        _properties = null;
        _layout = null;
        _detailsError = null;
      });
      return;
    }
    final app = _app;
    if (app == null) {
      return;
    }
    Json? properties;
    Json? layout;
    String? error;
    try {
      properties = await app.call('properties', {'id': '$id'});
      layout = await app.call('layout', {'id': '$id'});
    } on AppError catch (e) {
      error = e.message;
    }
    if (load != _details || !mounted) {
      return;
    }
    setState(() {
      _properties = properties;
      _layout = layout;
      _detailsError = error;
    });
  }

  void _toggleHighlight() {
    setState(() => _highlight = !_highlight);
    final id = _controller.selectedKey;
    unawaited(
      _call('highlight', {if (_highlight && id != null) 'id': '$id'}),
    );
  }

  void _toggleTree() {
    final counterpart = _ids[_controller.selectedKey]?.counterpart;
    setState(() => _render = !_render);
    unawaited(_refresh(select: counterpart));
  }

  Future<void> _togglePick() async {
    final pick = !_picking;
    final json = await _call('flags', {'select': '$pick'});
    if (json == null || !mounted) {
      return;
    }
    final picking = json['select'] == true;
    setState(() {
      _picking = picking;
      _status = picking
          ? 'click a node on the app’s screen; Escape there cancels'
          : pick
          ? 'the app runs inline, where its terminal keeps the mouse'
          : 'nothing picked';
    });
  }

  Future<void> _picked((int, int)? cell) async {
    setState(() => _picking = false);
    if (cell == null) {
      setState(() => _status = 'nothing picked');
      return;
    }
    final (x, y) = cell;
    final json = await _call('select', {'x': '$x', 'y': '$y'});
    if (json == null || !mounted) {
      return;
    }
    final id = json['id'] as int?;
    if (id == null) {
      setState(() => _status = 'nothing at $x, $y');
      return;
    }
    _controller.expandAll([
      for (final i in json['path'] as List<Object?>? ?? const []) i! as int,
    ]);
    if (_render) {
      setState(() => _render = false);
    }
    await _refresh(select: id);
    if (mounted) {
      setState(() => _status = 'picked ${_ids[id]?.name ?? '#$id'} at $x, $y');
    }
  }

  /// Takes the pick and the outline off the app, and quits; without
  /// waiting more than [_patience] for an app that does not answer (one
  /// paused at a breakpoint).
  Future<void> _quit() async {
    final binding = AppBinding.of(context);
    Future<void> leave(String method, [Map<String, String>? params]) => _call(
      method,
      params ?? const {},
    ).timeout(_patience, onTimeout: () => null);
    if (_picking) {
      await leave('flags', {'select': 'false'});
    }
    if (_highlight && _shown != null) {
      await leave('highlight');
    }
    binding.quit();
  }

  static const _patience = Duration(seconds: 1);

  bool _onEvent(InputEvent event) {
    if (event is FocusEvent && event.focused && _app != null) {
      unawaited(_refresh());
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final root = _root;
    final title = _render ? ' render tree ' : ' widget tree ';
    return InputListener(
      onEvent: _onEvent,
      child: KeyBindings(
        {
          'r': () => unawaited(_refresh()),
          's': () => unawaited(_togglePick()),
          'h': _toggleHighlight,
          't': _toggleTree,
          'q': () => unawaited(_quit()),
          'ctrl+c': () => unawaited(_quit()),
        },
        hints: {
          'r': 'refresh',
          's': _picking ? 'stop picking' : 'select on screen',
          'h': _highlight ? 'highlight off' : 'highlight on',
          't': _render ? 'widget tree' : 'render tree',
          'q': 'quit',
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SplitView(
                controller: _split,
                panes: [
                  SplitPane(
                    minSize: 16,
                    child: Box(
                      border: const Border.all(type: BorderType.rounded),
                      titles: [BorderTitle(title)],
                      child: root == null
                          ? Text(
                              _wasConnected ? '' : 'no app yet',
                              style: theme.muted,
                            )
                          : TreeView<_Node>(
                              roots: [root],
                              children: (n) => n.children,
                              hasChildren: (n) => n.children.isNotEmpty,
                              nodeKey: (n) => n.id,
                              controller: _controller,
                              autofocus: true,
                              label: (context, entry) =>
                                  _label(entry.node, theme),
                            ),
                    ),
                  ),
                  SplitPane(
                    minSize: 16,
                    child: Box(
                      border: const Border.all(type: BorderType.rounded),
                      titles: const [BorderTitle(' properties ')],
                      padding: const EdgeInsets.x(1),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _detailRows(theme),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Text(_status, style: theme.muted, maxLines: 1),
            const KeyHintsBar(),
          ],
        ),
      ),
    );
  }

  static Widget _label(_Node node, ThemeData theme) {
    final key = node.json['key'] as String?;
    final summary = node.summary;
    final flags = node.json['flags'] as List<Object?>? ?? const [];
    return Text.rich([
      Span(node.name),
      if (key != null) Span(' $key', theme.muted),
      if (summary != null) Span(' $summary', theme.muted),
      for (final flag in ['error', 'overflow'])
        if (flags.contains(flag)) Span(' $flag', theme.error),
    ], maxLines: 1);
  }

  List<Widget> _detailRows(ThemeData theme) {
    Widget row(String name, String value) => Text.rich([
      Span(name.padRight(12), theme.muted),
      Span(value),
    ]);
    // a property, after its name if it has one
    Widget described(Json property) => switch (property['name']) {
      null => Text('${property['value']}'),
      final name => row('$name', '${property['value']}'),
    };
    final error = _detailsError;
    if (error != null) {
      return [Text(error, style: theme.error)];
    }
    final p = _properties;
    if (p == null) {
      return const [];
    }
    final link = p['render'] != null
        ? ('render', p['render'])
        : p['element'] != null
        ? ('element', p['element'])
        : null;
    final flags = p['flags'] as List<Object?>? ?? const [];
    final l = _layout;
    return [
      Text.rich([
        Span('${p['name']}').bold,
        Span('  #${p['id']}', theme.muted),
      ]),
      if (p['key'] != null) row('key', '${p['key']}'),
      if (link != null) row(link.$1, '#${link.$2}'),
      for (final property in p['properties'] as List<Object?>? ?? const [])
        if (property case final Json property) described(property),
      if (flags.isNotEmpty) row('flags', flags.join(', ')),
      if (l != null) ...[
        const Text(''),
        Text('layout', style: theme.muted.merge(const Style(attrs: Attr.bold))),
        if (l['constraints'] case final Json c)
          row('constraints', _constraints(c)),
        if (l['size'] case final Json s) row('size', _size(s)),
        if (l['offset'] case final Json o) row('offset', _point(o)),
        if (l['global'] case final Json g) row('on screen', _point(g)),
      ],
    ];
  }

  static String _size(Json s) => '${s['width']} x ${s['height']}';

  static String _point(Json p) => '${p['x']}, ${p['y']}';

  /// `w 0..80, h 24`: each axis's least and most, one number when they
  /// are the same, `inf` for no most.
  static String _constraints(Json c) {
    String axis(String name, Object? min, Object? max) =>
        min == max ? '$name $min' : '$name $min..${max ?? 'inf'}';
    return '${axis('w', c['minWidth'], c['maxWidth'])}, '
        '${axis('h', c['minHeight'], c['maxHeight'])}';
  }
}
