// The TreeTable page.
part of 'data.dart';

// ------------------------------------------------------------ TreeTable

const _ttRoots = ['lib', 'test', 'README.md', 'pubspec.yaml'];

const _ttChildren = {
  'lib': ['lib/src', 'lib/twk.dart'],
  'lib/src': [
    'lib/src/box.dart',
    'lib/src/flex.dart',
    'lib/src/table.dart',
    'lib/src/text.dart',
  ],
  'test': ['test/box_test.dart', 'test/table_test.dart'],
};

const _ttSizes = {
  'lib/src/box.dart': 412,
  'lib/src/flex.dart': 388,
  'lib/src/table.dart': 960,
  'lib/src/text.dart': 230,
  'lib/twk.dart': 48,
  'test/box_test.dart': 310,
  'test/table_test.dart': 655,
  'README.md': 120,
  'pubspec.yaml': 22,
};

const _ttW = 40;

const _ttGap = 3;

/// A file's lines, or those of the files under a directory.
int _ttLines(String path) =>
    _ttSizes[path] ??
    (_ttChildren[path] ?? const []).fold(0, (n, p) => n + _ttLines(p));

String _quoted(List<String> list) => list.map((f) => "'$f'").join(', ');

final _treeTable = GalleryPage(
  group: 'Data',
  title: 'TreeTable',
  options: const [
    ChoiceOption(
      'selection',
      'selection',
      values: ['none', 'row', 'cell'],
      initial: 'row',
    ),
    ChoiceOption('border', 'border', values: _borders, initial: 'single'),
    SwitchOption('guides', 'guides', initial: true),
  ],
  build: (context, o) => inRoom((_, room) {
    final kept = PageControl.of(context).state;
    // kept while the gallery runs: what is expanded and selected, the
    // order and the widths
    final controller =
        (kept['tree'] ??= TreeController(
              expanded: ['lib', 'lib/src'],
              selectedKey: 'lib/src/table.dart',
            ))
            as TreeController;
    final table = (kept['table'] ??= TableController()) as TableController;
    final selection = TableSelection.values.byName(o.choice('selection'));
    final cell = selection == TableSelection.cell;
    return PageHints(
      hints: selection == TableSelection.none
          ? const [('↑↓', 'scroll'), ('s < >', 'sort'), ('shift+←→', 'width')]
          : [
              (cell ? '←↑↓→' : '↑↓', 'select'),
              if (!cell) ('←→', 'collapse, expand'),
              ('enter', 'toggle'),
              ('s < >', 'sort'),
              ('shift+←→', 'width'),
            ],
      child: SizedBox(
        width: _ttW,
        height: math.max(4, math.min(12, room)),
        child: TreeTable<String>(
          roots: _ttRoots,
          controller: controller,
          tableController: table,
          selection: selection,
          border: BorderType.values.byName(o.choice('border')),
          columnGap: _ttGap,
          showGuides: o.flag('guides'),
          hasChildren: (path) => !path.contains('.'),
          children: (path) => _ttChildren[path] ?? const [],
          columns: [
            TableColumn(
              title: 'name',
              width: const GridTrack.fr(1),
              cell: (path) => TableCell(path.split('/').last),
              compare: (a, b) => a.compareTo(b),
            ),
            TableColumn(
              title: 'lines',
              align: TextAlign.right,
              cell: (path) => TableCell('${_ttLines(path)}'),
              compare: (a, b) => _ttLines(a).compareTo(_ttLines(b)),
            ),
          ],
        ),
      ),
    );
  }),
  codeIn: (o, room) => [
    'final _controller = TreeController(',
    "  expanded: ['lib', 'lib/src'],",
    "  selectedKey: 'lib/src/table.dart',",
    ');',
    '',
    '@override',
    'void dispose() {',
    '  _controller.dispose();',
    '  super.dispose();',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) => SizedBox(',
    '  width: $_ttW,',
    '  height: ${_rowsIn(room, 12, 4)},',
    '  child: TreeTable<String>(',
    '    roots: const [${_quoted(_ttRoots)}],',
    '    controller: _controller,',
    '    selection: .${o.label('selection')},',
    if (o.choice<String>('border') != 'none')
      '    border: .${o.label('border')},',
    '    columnGap: $_ttGap,',
    if (!o.flag('guides')) '    showGuides: false,',
    "    hasChildren: (path) => !path.contains('.'),",
    '    children: (path) => _children[path] ?? const [],',
    '    columns: [',
    '      TableColumn(',
    "        title: 'name',",
    '        width: const .fr(1),',
    "        cell: (path) => TableCell(path.split('/').last),",
    '        compare: (a, b) => a.compareTo(b),',
    '      ),',
    '      TableColumn(',
    "        title: 'lines',",
    '        align: .right,',
    r"        cell: (path) => TableCell('${_lines(path)}'),",
    '        compare: (a, b) => _lines(a).compareTo(_lines(b)),',
    '      ),',
    '    ],',
    '  ),',
    ');',
    '',
    'const _children = {',
    "  'lib': ['lib/src', 'lib/twk.dart'],",
    "  'lib/src': [",
    for (final f in _ttChildren['lib/src']!) "    '$f',",
    '  ],',
    "  'test': [${_quoted(_ttChildren['test']!)}],",
    '};',
    '',
    'const _sizes = {',
    for (final MapEntry(:key, :value) in _ttSizes.entries) "  '$key': $value,",
    '};',
    '',
    "/// A file's lines, or those of the files under a directory.",
    'int _lines(String path) =>',
    '    _sizes[path] ??',
    '    (_children[path] ?? const []).fold(0, (n, p) => n + _lines(p));',
  ].join('\n'),
);
