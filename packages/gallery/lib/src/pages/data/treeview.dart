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

/// The TreeView page's `guides` option.
const _treeViewGuides = SwitchOption(
  'guides',
  'guides',
  initial: true,
);

/// The TreeView page's `load` option.
const _treeViewLoad = ChoiceOption<String>(
  'load',
  'test/',
  values: ['loads', 'fails'],
);

final _treeView = GalleryPage(
  group: _group,
  title: 'TreeView',
  options: const [
    _treeViewGuides,
    _treeViewLoad,
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
    final fails = o(_treeViewLoad) == 'fails';
    return SizedBox(
      width: _treeW,
      height: math.max(4, math.min(12, room)),
      child: TreeView<String>(
        roots: _roots,
        controller: controller,
        showGuides: o(_treeViewGuides),
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
    if (!o(_treeViewGuides)) '    showGuides: false,',
    "    hasChildren: (path) => !path.contains('.'),",
    '    children: (path) => switch (path) {',
    "      'lib' => const ['lib/src', 'lib/twk.dart'],",
    "      'lib/src' => const [",
    for (final f in _src) "        '$f',",
    '      ],',
    "      'test' => Future.delayed(",
    '        const Duration(seconds: 1),',
    if (o(_treeViewLoad) == 'fails')
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
