// The FilePicker page.
part of 'controls.dart';

final _filepickerPage = GalleryPage(
  group: 'Controls',
  title: 'FilePicker',
  options: const [
    ChoiceOption(
      'mode',
      'mode',
      values: ['open', 'several', 'save', 'directory'],
      labels: ['open', 'open several', 'save', 'directory'],
    ),
    SwitchOption('hidden', 'show hidden'),
  ],
  // a picker for each mode and showHidden, which it reads once, and its
  // controller with it
  build: (context, o) => _Files(
    key: ValueKey((o.choice<String>('mode'), o.flag('hidden'))),
    mode: o.choice('mode'),
    showHidden: o.flag('hidden'),
  ),
  code: (o) {
    final (mode, multiple) = _modes[o.choice<String>('mode')]!;
    final args = [
      if (mode != FilePickerMode.open) 'mode: .${mode.name}',
      if (multiple) 'multiple: true',
      if (o.flag('hidden')) 'showHidden: true',
    ];
    final key = "key: const ValueKey('${o.choice<String>('mode')}')";
    return [
      'final _files = FilePickerController();',
      'String? _picked;',
      '',
      '@override',
      'void dispose() {',
      '  _files.dispose();',
      '  super.dispose();',
      '}',
      '',
      'static const _filters = [',
      "  FileFilter('Dart', ['dart']),",
      "  FileFilter('All files'),",
      '];',
      '',
      'void _show(List<String>? paths) {',
      '  if (mounted && paths != null) {',
      "    setState(() => _picked = paths.join(', '));",
      '  }',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return SizedBox(',
      '    width: 50,',
      '    child: Column(',
      '      mainAxisSize: .min,',
      '      crossAxisAlignment: .stretch,',
      '      gap: 1,',
      '      children: [',
      '        SizedBox(',
      '          height: 8,',
      '          // a picker for each mode: it reads its mode once',
      ...call(10, 'child: FilePicker', [
        key,
        ...args,
        'controller: _files',
        'filters: _filters',
        'onPicked: _show',
      ], ','),
      '        ),',
      '        Row(',
      '          crossAxisAlignment: .start,',
      '          gap: 2,',
      '          children: [',
      '            Button(',
      "              'In a dialog',",
      '              onPressed: () => unawaited(',
      ...call(16, 'showFilePicker', [
        'context',
        ...args,
        'filters: _filters',
      ], '.then(_show),'),
      '              ),',
      '            ),',
      '            // the picker above gone there, the name typed kept',
      "            Button('lib/src', onPressed: () => _files.goTo('~/twk/lib/src')),",
      '            Expanded(',
      '              child: Text.rich(',
      '                [',
      "                  Span('picked: ', theme.muted),",
      '                  if (_picked case final picked?)',
      '                    Span(picked)',
      '                  else',
      "                    Span('nothing', theme.muted),",
      '                ],',
      '                maxLines: 2,',
      '                overflow: .ellipsis,',
      '              ),',
      '            ),',
      '          ],',
      '        ),',
      '      ],',
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);

/// The FilePicker page's modes: what the picker picks, and whether
/// several.
const Map<String, (FilePickerMode, bool)> _modes = {
  'open': (FilePickerMode.open, false),
  'several': (FilePickerMode.open, true),
  'save': (FilePickerMode.save, false),
  'directory': (FilePickerMode.directory, false),
};

const _filters = [
  FileFilter('Dart', ['dart']),
  FileFilter('All files'),
];

/// The gallery's file system of its own, which the pickers list in
/// place of the machine's: the same on every machine, and nothing of it
/// shown.
final _files = PickerFileSystem.memory(
  [
    '/home/user/.cache/dart/',
    '/home/user/.bashrc',
    '/home/user/notes.md',
    '/home/user/todo.txt',
    for (final name in [
      '.dart_tool/package_config.json',
      for (final f in ['chat_demo', 'counter', 'hello']) 'example/$f.dart',
      for (final f in ['controls', 'data', 'main', 'page', 'text'])
        'example/widgets/$f.dart',
      'lib/twk.dart',
      'lib/src/app.dart',
      'lib/src/theme.dart',
      for (final f in [
        'button',
        'choice',
        'select',
        'slider',
        'tabs',
        'toggle',
      ])
        'lib/src/controls/$f.dart',
      'lib/src/editing/text_area.dart',
      'lib/src/editing/text_field.dart',
      for (final f in ['box', 'flex', 'grid']) 'lib/src/layout/$f.dart',
      for (final f in ['app', 'button', 'select', 'slider'])
        'test/${f}_test.dart',
      '.gitignore',
      'analysis_options.yaml',
      'CHANGELOG.md',
      'pubspec.yaml',
      'README.md',
    ])
      '/home/user/twk/$name',
    '/tmp/build.log',
  ],
  currentDirectory: '/home/user/twk',
  homeDirectory: '/home/user',
);

/// A file picker, the same in a dialog, and what was picked.
final class _Files extends StatefulWidget {
  const _Files({required this.mode, required this.showHidden, super.key});

  final String mode;

  /// Whether the pickers show the files whose names start with a dot at
  /// first.
  final bool showHidden;

  @override
  State<_Files> createState() => _FilesState();
}

final class _FilesState extends State<_Files> with KeptState {
  final _picker = FilePickerController();

  @override
  void dispose() {
    _picker.dispose();
    super.dispose();
  }

  void _show(List<String>? paths) {
    if (mounted && paths != null) {
      keep('picked', paths.join(', '));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (mode, multiple) = _modes[widget.mode]!;
    final picked = keptOr<String?>('picked', null);
    return SizedBox(
      width: 50,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        gap: 1,
        children: [
          SizedBox(
            height: 8,
            // a picker for each mode: it reads its mode once
            child: FilePicker(
              key: ValueKey(widget.mode),
              fileSystem: _files,
              mode: mode,
              multiple: multiple,
              showHidden: widget.showHidden,
              controller: _picker,
              filters: _filters,
              onPicked: _show,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            gap: 2,
            children: [
              Button(
                'In a dialog',
                onPressed: () => unawaited(
                  showFilePicker(
                    context,
                    fileSystem: _files,
                    mode: mode,
                    multiple: multiple,
                    showHidden: widget.showHidden,
                    filters: _filters,
                  ).then(_show),
                ),
              ),
              Button(
                'lib/src',
                onPressed: () => _picker.goTo('~/twk/lib/src'),
              ),
              Expanded(
                child: LitLine(
                  [
                    ('picked: ', true),
                    if (picked == null) ('nothing', true) else (picked, false),
                  ],
                  serial: serial,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
