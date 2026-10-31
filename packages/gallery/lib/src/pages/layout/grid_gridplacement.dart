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

final _grid = GalleryPage(
  group: 'Layout',
  title: 'Grid, GridPlacement',
  options: [
    ChoiceOption(
      'third',
      'third column',
      values: _third.keys.toList(),
      labels: [for (final t in _third.values) t.$2],
    ),
    const ChoiceOption('cg', 'column gap', values: [0, 1, 2], initial: 1),
    const ChoiceOption('rg', 'row gap', values: [0, 1]),
    SliderOption(
      'width',
      'width',
      min: 32,
      max: 50,
      initial: 44,
      format: (v) => '$v cells',
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final third = _third[o.choice<String>('third')]!;
    Widget cell(String label) =>
        Box(border: _rounded(theme), child: Text(label));
    return SizedBox(
      width: o.number('width').toInt(),
      height: _gh,
      child: Grid(
        columns: [const GridTrack.fixed(12), const GridTrack.fr(1), third.$1],
        rows: const [GridTrack.content(), GridTrack.fr(1), GridTrack.content()],
        columnGap: o.choice('cg'),
        rowGap: o.choice('rg'),
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
    final third = _third[o.choice<String>('third')]!;
    return [
      'final theme = Theme.of(context);',
      'Widget cell(String label) => Box(',
      '  border: .all(type: .rounded, style: theme.border),',
      '  child: Text(label),',
      ');',
      'return SizedBox(',
      '  width: ${o.label('width')},',
      '  height: $_gh,',
      '  child: Grid(',
      '    columns: const [.fixed(12), .fr(1), ${third.$2}],',
      '    rows: const [.content(), .fr(1), .content()],',
      if (o['cg'] != 0) '    columnGap: ${o.label('cg')},',
      if (o['rg'] != 0) '    rowGap: ${o.label('rg')},',
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
