// The Grid, GridPlacement page.
part of 'layout.dart';

// ------------------------------------------------------ Grid, GridPlacement

// the third column: its track, the Dart and the label of its cell
const _third = {
  'content': (GridTrack.content(), '.content()', 'content()'),
  'fixed': (GridTrack.fixed(14), '.fixed(14)', 'fixed(14)'),
  'fr': (GridTrack.fr(1), '.fr(1)', 'fr(1)'),
};

const _gh = 12;

/// The Grid, GridPlacement page's `third` option.
final _gridThird = ChoiceOption<String>(
  'third',
  'third column',
  values: _third.keys.toList(),
  labels: [for (final t in _third.values) t.$2],
);

/// The Grid, GridPlacement page's `cg` option.
const _gridCg = ChoiceOption<int>(
  'cg',
  'column gap',
  values: [0, 1, 2],
  initial: 1,
);

/// The Grid, GridPlacement page's `rg` option.
const _gridRg = ChoiceOption<int>(
  'rg',
  'row gap',
  values: [0, 1],
);

/// The Grid, GridPlacement page's `width` option.
final _gridWidth = SliderOption(
  'width',
  'width',
  min: 32,
  max: 50,
  initial: 44,
  format: (v) => '$v cells',
);

final _grid = GalleryPage(
  group: _group,
  title: 'Grid, GridPlacement',
  options: [
    _gridThird,
    _gridCg,
    _gridRg,
    _gridWidth,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final third = _third[o(_gridThird)]!;
    Widget cell(String label) =>
        Box(border: _rounded(theme), child: Text(label));
    return SizedBox(
      width: o(_gridWidth).toInt(),
      height: _gh,
      child: Grid(
        columns: [const GridTrack.fixed(12), const GridTrack.fr(1), third.$1],
        rows: const [GridTrack.content(), GridTrack.fr(1), GridTrack.content()],
        columnGap: o(_gridCg),
        rowGap: o(_gridRg),
        children: [
          GridPlacement(
            columnSpan: 3,
            child: cell('header · columnSpan: 3'),
          ),
          cell('fixed(12)'),
          cell('fr(1)'),
          cell(third.$3),
          GridPlacement(
            row: 2,
            column: 1,
            columnSpan: 2,
            child: cell('columnSpan: 2'),
          ),
        ],
      ),
    );
  },
  code: (o) {
    final third = _third[o(_gridThird)]!;
    return [
      'final theme = Theme.of(context);',
      'Widget cell(String label) => Box(',
      '  border: .all(type: .rounded, style: theme.border),',
      '  child: Text(label),',
      ');',
      'return SizedBox(',
      '  width: ${o.nameOf(_gridWidth)},',
      '  height: $_gh,',
      '  child: Grid(',
      '    columns: const [.fixed(12), .fr(1), ${third.$2}],',
      '    rows: const [.content(), .fr(1), .content()],',
      if (o(_gridCg) != 0) '    columnGap: ${o.nameOf(_gridCg)},',
      if (o(_gridRg) != 0) '    rowGap: ${o.nameOf(_gridRg)},',
      '    children: [',
      codeLine([
        '      GridPlacement(columnSpan: 3, ',
        "child: cell('header · columnSpan: 3')),",
      ]),
      "      cell('fixed(12)'),",
      "      cell('fr(1)'),",
      "      cell('${third.$3}'),",
      '      GridPlacement(',
      '        row: 2,',
      '        column: 1,',
      '        columnSpan: 2,',
      "        child: cell('columnSpan: 2'),",
      '      ),',
      '    ],',
      '  ),',
      ');',
    ].join('\n');
  },
);
