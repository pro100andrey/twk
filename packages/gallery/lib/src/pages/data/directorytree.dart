// The DirectoryTree page.
part of 'data.dart';

/// The project the tree shows.
const _project = '/home/user/twk';

/// The files of the project and their sizes in bytes.
const _projectFiles = [
  ('lib/twk.dart', 312),
  ('lib/src/box.dart', 4210),
  ('lib/src/flex.dart', 9874),
  ('lib/src/table.dart', 18130),
  ('lib/src/text.dart', 2305),
  ('test/box_test.dart', 3102),
  ('test/table_test.dart', 6550),
  ('build/twk.js', 120400),
  ('.dart_tool/package_config.json', 2210),
  ('debug.log', 51200),
  ('README.md', 1204),
  ('pubspec.yaml', 220),
];

const _gitignore = r'build/\n*.log\n';

const _dirTreeW = 36;

/// The glyphs before a directory's name and a file's.
const _dirIcon = '📁';

const _fileIcon = '📄';

/// The rows of the tree in a room [room] rows high: 12, or those it has
/// but the two of the line under it, 2 at least.
int _treeRows(int room) => math.max(2, math.min(12, room - 2));

/// The DirectoryTree page's `hidden` option.
const _directoryTreeHidden = SwitchOption(
  'hidden',
  'hidden files',
);

/// The DirectoryTree page's `gitignore` option.
const _directoryTreeGitignore = SwitchOption(
  'gitignore',
  '.gitignore',
  initial: true,
);

/// The DirectoryTree page's `sizes` option.
const _directoryTreeSizes = SwitchOption('sizes', 'sizes');

/// The DirectoryTree page's `guides` option.
const _directoryTreeGuides = SwitchOption('guides', 'guides');

/// The DirectoryTree page's `icon` option.
const _directoryTreeIcon = ChoiceOption<String>(
  'icon',
  'icons',
  values: ['none', 'glyphs'],
);

final _directoryTree = GalleryPage(
  group: _group,
  title: 'DirectoryTree',
  options: const [
    _directoryTreeHidden,
    _directoryTreeGitignore,
    _directoryTreeSizes,
    _directoryTreeGuides,
    _directoryTreeIcon,
  ],
  build: (context, o) => inRoom(
    (_, room) => _Files(
      height: _treeRows(room),
      hidden: o(_directoryTreeHidden),
      gitignore: o(_directoryTreeGitignore),
      sizes: o(_directoryTreeSizes),
      guides: o(_directoryTreeGuides),
      icons: o(_directoryTreeIcon) == 'glyphs',
    ),
  ),
  // the tree, and the line under it
  heightIn: (o, room) => _treeRows(room.height) + 2,
  codeIn: (o, room) => [
    '/// A project of files as many bytes as they are big; a directory that',
    '/// cannot be read, and what the .gitignore leaves out.',
    'static final _files = InMemoryFileSystem(',
    "  const ['$_project/'],",
    '  contents: {',
    "    '$_project/.gitignore': '$_gitignore',",
    '    for (final (path, bytes) in const [',
    for (final (path, bytes) in _projectFiles) "      ('$path', $bytes),",
    '    ])',
    "      '$_project/\$path': 'x' * bytes,",
    '  },',
    "  unreadable: const ['$_project/private'],",
    ');',
    '',
    'final _tree = DirectoryTreeController()',
    "  ..expand('$_project/lib')",
    "  ..expand('$_project/lib/src');",
    "var _opened = '';",
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    spacing: 1,',
    '    children: [',
    '      SizedBox(',
    '        width: $_dirTreeW,',
    '        height: ${_treeRows(room.height)},',
    '        child: DirectoryTree(',
    "          root: '$_project',",
    '          fileSystem: _files,',
    '          controller: _tree,',
    if (o(_directoryTreeHidden)) '          showHidden: true,',
    if (!o(_directoryTreeGitignore)) '          gitignore: false,',
    if (o(_directoryTreeSizes)) '          showSizes: true,',
    if (o(_directoryTreeGuides)) '          showGuides: true,',
    if (o(_directoryTreeIcon) == 'glyphs')
      codeLine([
        "          icon: (entry) => entry.isDirectory ? '$_dirIcon' ",
        ": '$_fileIcon',",
      ]),
    '          onOpened: (path) => setState(',
    "            () => _opened = path.substring('$_project/'.length),",
    '          ),',
    '        ),',
    '      ),',
    '      Text.rich([',
    "        Span('opened: ', theme.muted),",
    '        if (_opened.isEmpty)',
    "          Span('nothing', theme.muted)",
    '        else',
    '          Span(_opened),',
    '      ]),',
    '    ],',
    '  );',
    '}',
  ].join('\n'),
);

/// The project's tree, [height] rows, and the file opened last.
final class _Files extends StatefulWidget {
  const _Files({
    required this.height,
    required this.hidden,
    required this.gitignore,
    required this.sizes,
    required this.guides,
    required this.icons,
  });

  final int height;
  final bool hidden;
  final bool gitignore;
  final bool sizes;
  final bool guides;
  final bool icons;

  @override
  State<_Files> createState() => _FilesState();
}

final class _FilesState extends State<_Files> with KeptState {
  static final _files = InMemoryFileSystem(
    const ['$_project/'],
    contents: {
      '$_project/.gitignore': 'build/\n*.log\n',
      for (final (path, bytes) in _projectFiles) '$_project/$path': 'x' * bytes,
    },
    unreadable: const ['$_project/private'],
  );

  // kept while the gallery runs: what is expanded and selected
  late final _tree =
      (kept['tree'] ??= DirectoryTreeController()
            ..expand('$_project/lib')
            ..expand('$_project/lib/src'))
          as DirectoryTreeController;

  String get _opened => kept['opened'] as String? ?? '';
  int get _serial => kept['serial'] as int? ?? 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 1,
    children: [
      SizedBox(
        width: _dirTreeW,
        height: widget.height,
        child: DirectoryTree(
          root: _project,
          fileSystem: _files,
          controller: _tree,
          showHidden: widget.hidden,
          gitignore: widget.gitignore,
          showSizes: widget.sizes,
          showGuides: widget.guides,
          icon: widget.icons
              ? (entry) => entry.isDirectory ? _dirIcon : _fileIcon
              : null,
          onOpened: (path) => setState(() {
            kept['opened'] = path.substring('$_project/'.length);
            kept['serial'] = _serial + 1;
          }),
        ),
      ),
      LitLine([
        ('opened: ', true),
        if (_opened.isEmpty) ('nothing', true) else (_opened, false),
      ], serial: _serial),
    ],
  );
}
