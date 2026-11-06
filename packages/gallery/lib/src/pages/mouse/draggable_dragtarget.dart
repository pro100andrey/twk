// The Draggable, DragTarget page.
part of 'mouse.dart';

/// The Draggable, DragTarget page's `ghost` option.
const _draggableDragtargetGhost = SwitchOption(
  'ghost',
  'child when dragging',
  initial: true,
);

final _draggableDragtargetPage = GalleryPage(
  group: _group,
  title: 'Draggable, DragTarget',
  options: const [
    _draggableDragtargetGhost,
  ],
  build: (context, o) => _Fruit(ghost: o(_draggableDragtargetGhost)),
  code: _fruitCode,
);

/// A fruit box: its width and rows; the gap between two.
const _fruitW = 15;

const _fruitH = 6;

const _fruitGap = 2;

/// The fruit, the colour of each, and those the red box takes.
const Map<String, Color> _fruitColors = {
  'apple': Color.red,
  'banana': Color.yellow,
  'cherry': Color.red,
  'grape': Color.magenta,
};

const _red = {'apple', 'cherry'};

/// What each box shows while it is empty.
const _empty = {
  'bowl': 'empty',
  'basket': 'drop here',
  'red only': 'drop here',
};

const _candidateLine =
    '                        if (candidate != null && '
    '!fruits.contains(candidate))';

const _canceledLine =
    '    onDragCanceled: () => '
    r"setState(() => _status = '$fruit, back to the $from'),";

const _labelLine =
    "      Text.rich(['● '.fg(_colors[fruit]!), Span(fruit)], style: style);";

/// Three boxes of fruit, dragged from one to another.
final class _Fruit extends StatefulWidget {
  const _Fruit({required this.ghost});

  /// Whether a dragged fruit leaves a muted one in its place.
  final bool ghost;

  @override
  State<_Fruit> createState() => _FruitState();
}

final class _FruitState extends State<_Fruit> {
  final _in = {
    'bowl': ['apple', 'banana', 'cherry', 'grape'],
    'basket': <String>[],
    'red only': <String>[],
  };
  String? _status;
  var _drops = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 1,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: _fruitGap,
          children: [
            for (final MapEntry(key: name, value: fruits) in _in.entries)
              DragTarget<String>(
                onWillAccept: (drag) =>
                    name != 'red only' || _red.contains(drag.data),
                onAccept: (drop) => setState(() {
                  if (!fruits.contains(drop.data)) {
                    for (final list in _in.values) {
                      list.remove(drop.data);
                    }
                    fruits.add(drop.data);
                  }
                  _status = '${drop.data} → $name';
                  _drops++;
                }),
                builder: (context, candidate, rejected) {
                  final over = candidate != null || rejected != null;
                  final style = candidate != null
                      ? theme.primary
                      : rejected != null
                      ? theme.error
                      : theme.border;
                  return SizedBox(
                    width: _fruitW,
                    height: _fruitH,
                    child: Box(
                      border: Border.all(
                        type: BorderType.rounded,
                        style: style,
                      ),
                      titles: [
                        BorderTitle(
                          ' $name ',
                          style: over ? style.merge(bold) : theme.muted,
                        ),
                      ],
                      padding: const EdgeInsets.x(1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (fruits.isEmpty && !over)
                            Text(_empty[name]!, style: theme.muted),
                          for (final fruit in fruits)
                            _draggable(fruit, name, theme),
                          if (candidate != null && !fruits.contains(candidate))
                            Text('+ $candidate', style: theme.primary),
                          if (rejected != null)
                            Text('✗ red only', style: theme.error),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        LitLine([
          ('dropped: ', true),
          (_status ?? 'nothing', _status == null),
        ], serial: _drops),
      ],
    );
  }

  Widget _draggable(String fruit, String from, ThemeData theme) {
    Widget label([Style style = const Style()]) =>
        Text.rich(['● '.fg(_fruitColors[fruit]!), Span(fruit)], style: style);
    return Draggable<String>(
      data: fruit,
      feedback: Shadow(
        shadow: const BoxShadow(dx: 1),
        child: Box(
          style: theme.surface,
          padding: const EdgeInsets.x(1),
          child: label(theme.text.merge(bold)),
        ),
      ),
      childWhenDragging: widget.ghost
          ? Text('● $fruit', style: theme.muted)
          : null,
      onDragCanceled: () => setState(() {
        _status = '$fruit, back to the $from';
        _drops++;
      }),
      child: label(),
    );
  }
}

String _fruitCode(Options o) => [
  "const _red = {'apple', 'cherry'};",
  'const _colors = {',
  "  'apple': Color.red,",
  "  'banana': Color.yellow,",
  "  'cherry': Color.red,",
  "  'grape': Color.magenta,",
  '};',
  '',
  'final _in = {',
  "  'bowl': ['apple', 'banana', 'cherry', 'grape'],",
  "  'basket': <String>[],",
  "  'red only': <String>[],",
  '};',
  'String? _status;',
  '',
  '@override',
  'Widget build(BuildContext context) {',
  '  final theme = Theme.of(context);',
  '  const empty = {',
  "    'bowl': 'empty',",
  "    'basket': 'drop here',",
  "    'red only': 'drop here',",
  '  };',
  '  return Column(',
  '    mainAxisSize: .min,',
  '    crossAxisAlignment: .start,',
  '    spacing: 1,',
  '    children: [',
  '      Row(',
  '        mainAxisSize: .min,',
  '        spacing: $_fruitGap,',
  '        children: [',
  '          for (final MapEntry(key: name, value: fruits) in _in.entries)',
  '            DragTarget<String>(',
  '              onWillAccept: (drag) =>',
  "                  name != 'red only' || _red.contains(drag.data),",
  '              onAccept: (drop) => setState(() {',
  '                // dropped back on its own box, it stays where it is',
  '                if (!fruits.contains(drop.data)) {',
  '                  for (final list in _in.values) {',
  '                    list.remove(drop.data);',
  '                  }',
  '                  fruits.add(drop.data);',
  '                }',
  r"                _status = '${drop.data} → $name';",
  '              }),',
  '              builder: (context, candidate, rejected) {',
  '                final over = candidate != null || rejected != null;',
  '                final style = candidate != null',
  '                    ? theme.primary',
  '                    : rejected != null',
  '                    ? theme.error',
  '                    : theme.border;',
  '                return SizedBox(',
  '                  width: $_fruitW,',
  '                  height: $_fruitH,',
  '                  child: Box(',
  '                    border: .all(type: .rounded, style: style),',
  '                    titles: [',
  '                      BorderTitle(',
  r"                        ' $name ',",
  '                        style: over ? style.merge(bold) : theme.muted,',
  '                      ),',
  '                    ],',
  '                    padding: const .x(1),',
  '                    child: Column(',
  '                      crossAxisAlignment: .start,',
  '                      children: [',
  '                        if (fruits.isEmpty && !over)',
  '                          Text(empty[name]!, style: theme.muted),',
  '                        for (final fruit in fruits)',
  '                          _draggable(fruit, name, theme),',
  _candidateLine,
  r"                          Text('+ $candidate', style: theme.primary),",
  '                        if (rejected != null)',
  "                          Text('✗ red only', style: theme.error),",
  '                      ],',
  '                    ),',
  '                  ),',
  '                );',
  '              },',
  '            ),',
  '        ],',
  '      ),',
  '      Text.rich([',
  "        Span('dropped: ', theme.muted),",
  '        Span(',
  "          _status ?? 'nothing',",
  '          _status == null ? theme.muted : const Style(),',
  '        ),',
  '      ]),',
  '    ],',
  '  );',
  '}',
  '',
  '/// [fruit] in the box [from], dragged with the mouse: the pointer a',
  '/// hand over it, a closed one while it is dragged, no-drop over a box',
  "/// that refuses it (Draggable's pointer shapes).",
  'Widget _draggable(String fruit, String from, ThemeData theme) {',
  '  Widget label([Style style = const Style()]) =>',
  _labelLine,
  '  return Draggable<String>(',
  '    data: fruit,',
  '    // what follows the mouse: a chip on the surface, with a shadow',
  '    feedback: Shadow(',
  '      shadow: const BoxShadow(dx: 1),',
  '      child: Box(',
  '        style: theme.surface,',
  '        padding: const .x(1),',
  '        child: label(theme.text.merge(bold)),',
  '      ),',
  '    ),',
  if (o(_draggableDragtargetGhost))
    r"    childWhenDragging: Text('● $fruit', style: theme.muted),",
  _canceledLine,
  '    child: label(),',
  '  );',
  '}',
  '',
  'const bold = Style(attrs: Attr.bold);',
].join('\n');
