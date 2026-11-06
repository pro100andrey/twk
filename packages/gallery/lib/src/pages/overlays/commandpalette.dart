// The CommandPalette page.
part of 'overlays.dart';

/// The CommandPalette page's `width` option.
const _commandpaletteWidth = ChoiceOption<int>(
  'width',
  'width',
  values: [40, 60],
  initial: 40,
);

/// The CommandPalette page's `rows` option.
const _commandpaletteRows = ChoiceOption<int>(
  'rows',
  'rows',
  values: [3, 10],
  initial: 10,
);

/// The CommandPalette page's `files` option.
const _commandpaletteFiles = SwitchOption(
  'files',
  'files',
  initial: true,
);

/// The CommandPalette page's `rule` option.
const _commandpaletteRule = SwitchOption('rule', 'rule');

/// The CommandPalette page's `bar` option.
const _commandpaletteBar = SwitchOption('bar', 'bar');

/// The CommandPalette page's `thumb` option.
const _commandpaletteThumb = SwitchOption('thumb', 'thumb');

/// The CommandPalette page's `placeholder` option.
const _commandpalettePlaceholder = SwitchOption('placeholder', 'placeholder');

final _commandpalettePage = GalleryPage(
  group: _group,
  title: 'CommandPalette',
  about:
      'What can be done, found by typing: Tab to a button, then Ctrl+K, '
      'or press Dart files, whose CommandPaletteController opens it with '
      'dart typed; commandsFor adds the files that match. The '
      "gallery's own, Ctrl+P, goes to a page.",
  // an open menu (or palette) takes Tab itself
  modalTab: false,
  options: [
    _commandpaletteWidth,
    _commandpaletteRows,
    _commandpaletteFiles,
    _commandpaletteRule,
    _commandpaletteBar,
    _commandpaletteThumb,
    _commandpalettePlaceholder,
    _lookOption,
  ],
  build: (context, o) => _Palette(
    width: o(_commandpaletteWidth),
    rows: o(_commandpaletteRows),
    files: o(_commandpaletteFiles),
    rule: o(_commandpaletteRule),
    bar: o(_commandpaletteBar),
    thumb: o(_commandpaletteThumb),
    placeholder: o(_commandpalettePlaceholder),
    look: _lookOf(o),
  ),
  code: (o) => [
    'final _palette = CommandPaletteController();',
    'String? _ran;',
    '',
    '@override',
    'void dispose() {',
    '  _palette.dispose();',
    '  super.dispose();',
    '}',
    '',
    'void _run(String what) => setState(() => _ran = what);',
    "void _build() => _run('Build');",
    "void _test() => _run('Run tests');",
    "void _save() => _run('Save');",
    '',
    if (o(_commandpaletteFiles)) ...[
      '// the files whose path matches what is typed, none while nothing is',
      'Iterable<Command> _files(String query) => [',
      '  if (query.isNotEmpty)',
      '    for (final file in const [',
      for (final f in _paletteFiles) "      '$f',",
      '    ])',
      '      if (fuzzyMatch(query, file) != null)',
      r"        Command(file, onSelected: () => _run('open $file')),",
      '];',
      '',
    ],
    '@override',
    'Widget build(BuildContext context) => CommandPalette(',
    '  controller: _palette,',
    "  openKey: 'ctrl+k',",
    '  width: ${o.nameOf(_commandpaletteWidth)},',
    if (o(_commandpaletteRows) != 10)
      '  rows: ${o.nameOf(_commandpaletteRows)},',
    ..._lookLine(o, '  '),
    if (o(_commandpalettePlaceholder)) "  placeholder: 'type a command',",
    if (o(_commandpaletteRule)) '  rule: true,',
    if (o(_commandpaletteBar)) '  bar: true,',
    if (o(_commandpaletteThumb)) '  thumb: true,',
    '  commands: [',
    "    Command('Build', onSelected: _build),",
    "    Command('Run tests', onSelected: _test),",
    "    Command('Format', onSelected: () => _run('Format')),",
    "    Command('Deploy', onSelected: () => _run('Deploy')),",
    '  ],',
    if (o(_commandpaletteFiles)) ...[
      '  // listed after the commands that match',
      '  commandsFor: _files,',
    ],
    '  // listed after the commands: the keys bound with a hint where the',
    "  // focus is, the Button's Enter (press) and Ctrl+S (Save); by each the",
    '  // key bound to what it calls',
    '  child: KeyBindings(',
    "    {'ctrl+b': _build, 'f8': _test, 'ctrl+s': _save},",
    "    hints: {'ctrl+s': 'Save'},",
    '    child: Column(',
    '      mainAxisSize: .min,',
    '      crossAxisAlignment: .start,',
    '      spacing: 1,',
    '      children: [',
    '        Row(',
    '          mainAxisSize: .min,',
    '          spacing: 2,',
    '          children: [',
    "            Button('Focus me', onPressed: () => _run('press')),",
    '            // opens the palette with dart typed',
    '            Button(',
    "              'Dart files',",
    "              onPressed: () => _palette.open(query: 'dart'),",
    '            ),',
    '          ],',
    '        ),',
    '        Text.rich([',
    "          Span('ran: ', Theme.of(context).muted),",
    '          switch (_ran) {',
    "            null => Span('nothing', Theme.of(context).muted),",
    '            final ran => Span(ran),',
    '          },',
    '        ]),',
    '      ],',
    '    ),',
    '  ),',
    ');',
  ].join('\n'),
);

/// A button under a command palette that Ctrl+K opens, and what ran.
final class _Palette extends StatefulWidget {
  const _Palette({
    required this.width,
    required this.rows,
    required this.files,
    required this.rule,
    required this.bar,
    required this.thumb,
    required this.placeholder,
    required this.look,
  });

  final int width;
  final int rows;
  final PanelLook look;

  /// The palette's rule, bar, thumb and placeholder.
  final bool rule;
  final bool bar;
  final bool thumb;
  final bool placeholder;

  /// Whether commandsFor finds the files that match.
  final bool files;

  @override
  State<_Palette> createState() => _PaletteState();
}

final class _PaletteState extends State<_Palette> with KeptState {
  String? get _ran => kept['ran'] as String?;
  int get _serial => kept['serial'] as int? ?? 0;

  void _run(String what) => setState(() {
    kept
      ..['ran'] = what
      ..['serial'] = _serial + 1;
  });
  void _build() => _run('Build');
  void _test() => _run('Run tests');
  void _save() => _run('Save');

  final _palette = CommandPaletteController();

  @override
  void dispose() {
    _palette.dispose();
    super.dispose();
  }

  /// The files whose path matches [query], none while nothing is typed.
  Iterable<Command> _files(String query) => [
    if (query.isNotEmpty)
      for (final file in _paletteFiles)
        if (fuzzyMatch(query, file) != null)
          Command(file, onSelected: () => _run('open $file')),
  ];

  @override
  Widget build(BuildContext context) => CommandPalette(
    controller: _palette,
    openKey: 'ctrl+k',
    width: widget.width,
    rows: widget.rows,
    look: widget.look,
    placeholder: widget.placeholder ? 'type a command' : null,
    rule: widget.rule,
    bar: widget.bar,
    thumb: widget.thumb,
    commands: [
      Command('Build', onSelected: _build),
      Command('Run tests', onSelected: _test),
      Command('Format', onSelected: () => _run('Format')),
      Command('Deploy', onSelected: () => _run('Deploy')),
    ],
    commandsFor: widget.files ? _files : null,
    child: KeyBindings(
      {'ctrl+b': _build, 'f8': _test, 'ctrl+s': _save},
      hints: const {'ctrl+s': 'Save'},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 1,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 2,
            children: [
              Button('Focus me', onPressed: () => _run('press')),
              Button(
                'Dart files',
                onPressed: () => _palette.open(query: 'dart'),
              ),
            ],
          ),
          LitLine([
            ('ran: ', true),
            (_ran ?? 'nothing', _ran == null),
          ], serial: _serial),
        ],
      ),
    ),
  );
}

/// The files the CommandPalette page's commandsFor finds.
const _paletteFiles = [
  'lib/main.dart',
  'lib/src/app.dart',
  'lib/src/theme.dart',
  'test/app_test.dart',
  'README.md',
  'pubspec.yaml',
];
