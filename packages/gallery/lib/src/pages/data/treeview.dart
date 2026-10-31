// The TreeView page.
part of 'data.dart';

// ------------------------------------------------------------ TreeView

const _roots = ['lib', 'test', 'README.md', 'pubspec.yaml'];

const _src = [
  'lib/src/box.dart',
  'lib/src/flex.dart',
  'lib/src/table.dart',
  'lib/src/text.dart',
];

const _treeW = 40;

final _treeView = GalleryPage(
  group: 'Data',
  title: 'TreeView',
  options: const [
    SwitchOption('guides', 'guides', initial: true),
    ChoiceOption('load', 'test/', values: ['loads', 'fails']),
  ],
  build: (context, o) => inRoom((_, room) {
    final kept = PageControl.of(context).state;
    // kept while the gallery runs: what is expanded and selected
    final controller =
        (kept['tree'] ??= TreeController(
              expanded: ['lib', 'lib/src'],
              selectedKey: 'lib/src/table.dart',
            ))
            as TreeController;
    final fails = o.choice<String>('load') == 'fails';
    return SizedBox(
      width: _treeW,
      height: math.max(4, math.min(12, room)),
      child: TreeView<String>(
        roots: _roots,
        controller: controller,
        showGuides: o.flag('guides'),
        hasChildren: (path) => !path.contains('.'),
        children: (path) => switch (path) {
          'lib' => const ['lib/src', 'lib/twk.dart'],
          'lib/src' => _src,
          'test' => Future.delayed(
            const Duration(seconds: 1),
            () => fails
                ? throw StateError('test/ is not readable')
                : const ['test/box_test.dart', 'test/table_test.dart'],
          ),
          _ => const [],
        },
        label: (context, entry) => Text(entry.node.split('/').last),
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
    'Widget build(BuildContext context) => SizedBox(',
    '  width: $_treeW,',
    '  height: ${_rowsIn(room, 12, 4)},',
    '  child: TreeView<String>(',
    '    roots: const [${_roots.map((r) => "'$r'").join(', ')}],',
    '    controller: _controller,',
    if (!o.flag('guides')) '    showGuides: false,',
    "    hasChildren: (path) => !path.contains('.'),",
    '    children: (path) => switch (path) {',
    "      'lib' => const ['lib/src', 'lib/twk.dart'],",
    "      'lib/src' => const [",
    for (final f in _src) "        '$f',",
    '      ],',
    "      'test' => Future.delayed(",
    '        const Duration(seconds: 1),',
    if (o.choice<String>('load') == 'fails')
      "        () => throw StateError('test/ is not readable'),"
    else
      "        () => const ['test/box_test.dart', 'test/table_test.dart'],",
    '      ),',
    '      _ => const [],',
    '    },',
    "    label: (context, entry) => Text(entry.node.split('/').last),",
    '  ),',
    ');',
  ].join('\n'),
);
