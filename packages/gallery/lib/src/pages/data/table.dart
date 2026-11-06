// The Table page.
part of 'data.dart';

const _many = 10000;

const _tableW = 50;

const _gap = 3;

/// 10 000 files, each made as the table reads it.
final class _ManyFiles extends TableSource<_File> {
  @override
  int get rowCount => _many;

  @override
  _File rowAt(int index) => (
    'file_${'$index'.padLeft(4, '0')}.dart',
    index * 7919 % 900 + 20,
    index * 37 % 101 / 100,
  );
}

/// How much of a file its tests cover, as a line in the colours of its
/// row: the selection's and the cursor's, which the table gives a widget
/// cell's text (DefaultTextStyle).
final class _Covered extends StatelessWidget {
  const _Covered(this.ratio);

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LineGauge(
      ratio: ratio,
      label: '${(ratio * 100).round()}%'.padLeft(4),
      type: BorderType.heavy,
      style: DefaultTextStyle.of(context),
      filledStyle: theme.primary,
      unfilledStyle: theme.border,
    );
  }
}

/// The SizedBox's height: the files under the header and its line, or 12
/// rows where the room has them.
int _tableHeight(Options o, int room) => o(_tableRows) == _many
    ? math.max(5, math.min(12, room))
    : _files.length +
          (!o(_tableHeader)
              ? 0
              : o(_tableBorder) == 'none'
              ? 1
              : 2);

/// The Code's data: the files as a const list, the 10 000 as a source.
String _fraction(double v) => v == v.roundToDouble()
    ? v.toStringAsFixed(1)
    : '$v'.replaceFirst('0.', '.');

final List<String> _tableCode = [
  'const _files = [',
  for (final (name, lines, covered) in _files)
    "  ('$name', $lines, ${_fraction(covered)}),",
  '];',
];

const _manyCode = [
  '/// 10 000 files, each made as the table reads it.',
  'final class _ManyFiles extends TableSource<(String, int, double)> {',
  '  @override',
  '  int get rowCount => $_many;',
  '',
  '  @override',
  '  (String, int, double) rowAt(int index) => (',
  r"    'file_${'$index'.padLeft(4, '0')}.dart',",
  '    index * 7919 % 900 + 20,',
  '    index * 37 % 101 / 100,',
  '  );',
  '}',
];

const _coveredCode = [
  '/// How much of a file its tests cover, as a line in the colours of its',
  "/// row: the selection's and the cursor's, which the table gives a",
  "/// widget cell's text (DefaultTextStyle).",
  'final class _Covered extends StatelessWidget {',
  '  const _Covered(this.ratio);',
  '',
  '  final double ratio;',
  '',
  '  @override',
  '  Widget build(BuildContext context) {',
  '    final theme = Theme.of(context);',
  '    return LineGauge(',
  '      ratio: ratio,',
  r"      label: '${(ratio * 100).round()}%'.padLeft(4),",
  '      type: .heavy,',
  '      style: DefaultTextStyle.of(context),',
  '      filledStyle: theme.primary,',
  '      unfilledStyle: theme.border,',
  '    );',
  '  }',
  '}',
];

/// The Table page's `selection` option.
const _tableSelection = ChoiceOption<String>(
  'selection',
  'selection',
  values: ['none', 'row', 'cell'],
  initial: 'row',
);

/// The Table page's `border` option.
const _tableBorder = ChoiceOption<String>(
  'border',
  'border',
  values: _borders,
  initial: 'single',
);

/// The Table page's `header` option.
const _tableHeader = SwitchOption(
  'header',
  'header',
  initial: true,
);

/// The Table page's `rows` option.
const _tableRows = ChoiceOption<int>(
  'rows',
  'rows',
  values: [5, _many],
  labels: ['5', '10 000'],
);

final _table = GalleryPage(
  group: _group,
  title: 'Table',
  options: const [
    _tableSelection,
    _tableBorder,
    _tableHeader,
    _tableRows,
  ],
  build: (context, o) => inRoom((_, room) {
    final control = PageControl.of(context);
    final kept = control.state;
    final many = o(_tableRows) == _many;
    // a controller for each kind of rows, kept while the gallery runs: the
    // row selected, the order, the widths
    final controller =
        (kept[many ? 'many' : 'files'] ??= TableController(
              selectedKey: many ? 0 : 'box.dart',
            ))
            as TableController;
    final columns = [
      TableColumn<_File>(
        title: 'name',
        cell: (row) => TableCell(row.$1),
        compare: (a, b) => a.$1.compareTo(b.$1),
      ),
      TableColumn<_File>(
        title: 'lines',
        align: TextAlign.right,
        cell: (row) => TableCell.rich(['${row.$2}'.bold]),
        compare: (a, b) => a.$2.compareTo(b.$2),
      ),
      TableColumn<_File>(
        title: 'covered',
        width: const GridTrack.fr(1),
        cell: (row) => TableCell.widget(_Covered(row.$3)),
      ),
    ];
    final selection = TableSelection.values.byName(o(_tableSelection));
    final border = BorderType.values.byName(o(_tableBorder));
    void activated(_File row) => control.toast('Activated ${row.$1}');
    return SizedBox(
      width: _tableW,
      height: _tableHeight(o, room),
      child: many
          ? Table<_File>.source(
              key: const ValueKey('many'),
              source: (kept['source'] ??= _ManyFiles()) as _ManyFiles,
              controller: controller,
              selection: selection,
              border: border,
              showHeader: o(_tableHeader),
              columnGap: _gap,
              onActivated: activated,
              columns: columns,
            )
          : Table<_File>(
              key: const ValueKey('files'),
              rows: _files,
              rowKey: (row) => row.$1,
              controller: controller,
              selection: selection,
              border: border,
              showHeader: o(_tableHeader),
              columnGap: _gap,
              onActivated: activated,
              columns: columns,
            ),
    );
  }),
  codeIn: (o, room) {
    final many = o(_tableRows) == _many;
    final none = o(_tableSelection) == 'none';
    // the row selected at first, which none has not
    final own = [
      if (many) 'final _files = _ManyFiles();',
      if (!none)
        codeLine([
          'final _controller = TableController(selectedKey: ',
          "${many ? '0' : "'box.dart'"});",
        ]),
    ];
    final disposed = [
      if (many) '  _files.dispose();',
      if (!none) '  _controller.dispose();',
    ];
    return [
      ...own,
      if (disposed.isNotEmpty) ...[
        '',
        '@override',
        'void dispose() {',
        ...disposed,
        '  super.dispose();',
        '}',
      ],
      if (own.isNotEmpty) '',
      '@override',
      'Widget build(BuildContext context) => SizedBox(',
      '  width: $_tableW,',
      '  height: ${_tableHeight(o, room.height)},',
      '  child: Table<(String, int, double)>${many ? '.source' : ''}(',
      '    ${many ? 'source' : 'rows'}: _files,',
      if (!many) r'    rowKey: (row) => row.$1,',
      if (!none) '    controller: _controller,',
      '    selection: .${o.nameOf(_tableSelection)},',
      '    border: .${o.nameOf(_tableBorder)},',
      if (!o(_tableHeader)) '    showHeader: false,',
      '    columnGap: $_gap,',
      '    onActivated: (row) =>',
      r"        showToast(context: context, message: 'Activated ${row.$1}'),",
      '    columns: [',
      '      TableColumn(',
      "        title: 'name',",
      r'        cell: (row) => TableCell(row.$1),',
      r'        compare: (a, b) => a.$1.compareTo(b.$1),',
      '      ),',
      '      TableColumn(',
      "        title: 'lines',",
      '        align: .right,',
      r"        cell: (row) => TableCell.rich(['${row.$2}'.bold]),",
      r'        compare: (a, b) => a.$2.compareTo(b.$2),',
      '      ),',
      '      TableColumn(',
      "        title: 'covered',",
      '        width: const .fr(1),',
      r'        cell: (row) => TableCell.widget(_Covered(row.$3)),',
      '      ),',
      '    ],',
      '  ),',
      ');',
      '',
      ...(many ? _manyCode : _tableCode),
      '',
      ..._coveredCode,
    ].join('\n');
  },
);
