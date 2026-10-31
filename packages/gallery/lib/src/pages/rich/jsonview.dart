// The JsonView page.
part of 'rich.dart';

/// What the JsonView page shows: a package's description.
const Map<String, Object?> _package = {
  'name': 'twk',
  'version': '0.1.0',
  'description': 'Widgets for terminal apps, laid out as Flutter lays them',
  'private': true,
  'score': 0.97,
  'homepage': null,
  'environment': {'sdk': '^3.13.5'},
  'dependencies': {'args': '^2.7.0', 'meta': '^1.16.0', 'path': '^1.9.1'},
  'scripts': ['quick', 'handover', 'bench'],
};

/// [value] as the Code writes it in a const map, [indent] blanks in.
List<String> _dartOf(Object? value, int indent) {
  final pad = ' ' * indent;
  String scalar(Object? v) => switch (v) {
    final String s => "'$s'",
    _ => '$v',
  };
  final one = switch (value) {
    final Map<String, Object?> m =>
      '{${m.entries.map((e) => "'${e.key}': ${scalar(e.value)}").join(', ')}}',
    final List<Object?> l => '[${l.map(scalar).join(', ')}]',
    _ => scalar(value),
  };
  return ['$pad$one'];
}

const _jsonW = 50;

/// The rows of the view in a room [room] rows high: 14, or those it has
/// but the two of the line under it, 2 at least.
int _jsonRows(int room) => math.max(2, math.min(14, room - 2));

/// The JsonView page's `depth` option.
const _jsonViewDepth = ChoiceOption<int>(
  'depth',
  'expanded depth',
  values: [1, 2, 0],
);

/// The JsonView page's `sort` option.
const _jsonViewSort = SwitchOption('sort', 'sort keys');

/// The JsonView page's `cut` option.
const _jsonViewCut = ChoiceOption<int>(
  'cut',
  'strings cut at',
  values: [200, 24],
  labels: ['200', '24'],
);

final _jsonView = GalleryPage(
  group: _group,
  title: 'JsonView',
  options: const [
    _jsonViewDepth,
    _jsonViewSort,
    _jsonViewCut,
  ],
  build: (context, o) => inRoom(
    (w, h) => _Json(
      height: _jsonRows(h),
      depth: o(_jsonViewDepth),
      sortKeys: o(_jsonViewSort),
      cut: o(_jsonViewCut),
    ),
  ),
  // the view, and the line under it
  heightIn: (o, room) => _jsonRows(room.height) + 2,
  codeIn: (o, room) {
    final depth = o(_jsonViewDepth);
    final (_, h) = codeRoomOf(room);
    return [
      'static const _package = {',
      for (final MapEntry(:key, :value) in _package.entries)
        ..._dartOf(value, 0).map((v) => "  '$key': $v,"),
      '};',
      '',
      if (depth == 1)
        'final _view = JsonViewController();'
      else
        'final _view = JsonViewController(expandedDepth: $depth);',
      "var _copied = '';",
      '',
      '@override',
      'void dispose() {',
      '  _view.dispose();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      SizedBox(',
      '        width: $_jsonW,',
      '        height: ${_jsonRows(h)},',
      '        child: JsonView(',
      '          value: _package,',
      '          controller: _view,',
      if (o(_jsonViewSort)) '          sortKeys: true,',
      if (o(_jsonViewCut) != 200)
        '          maxStringLength: ${o(_jsonViewCut)},',
      '          onPathCopied: (path) => setState(() => _copied = path),',
      '        ),',
      '      ),',
      '      Text.rich([',
      "        Span('copied: ', theme.muted),",
      '        if (_copied.isEmpty)',
      "          Span('nothing', theme.muted)",
      '        else',
      '          Span(_copied),',
      '      ]),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

/// The package in a JsonView [height] rows tall, and the path copied
/// last.
final class _Json extends StatefulWidget {
  const _Json({
    required this.height,
    required this.depth,
    required this.sortKeys,
    required this.cut,
  });

  final int height;
  final int depth;
  final bool sortKeys;
  final int cut;

  @override
  State<_Json> createState() => _JsonState();
}

final class _JsonState extends State<_Json> with KeptState {
  String get _copied => kept['copied'] as String? ?? '';
  int get _serial => kept['serial'] as int? ?? 0;

  @override
  Widget build(BuildContext context) {
    // kept while the gallery runs, one for each depth
    final view =
        (kept['view:${widget.depth}'] ??= JsonViewController(
              expandedDepth: widget.depth,
            ))
            as JsonViewController;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        SizedBox(
          width: _jsonW,
          height: widget.height,
          child: JsonView(
            key: ValueKey(widget.depth),
            value: _package,
            controller: view,
            sortKeys: widget.sortKeys,
            maxStringLength: widget.cut,
            onPathCopied: (path) => setState(() {
              kept['copied'] = path;
              kept['serial'] = _serial + 1;
            }),
          ),
        ),
        LitLine([
          ('copied: ', true),
          if (_copied.isEmpty) ('nothing', true) else (_copied, false),
        ], serial: _serial),
      ],
    );
  }
}
