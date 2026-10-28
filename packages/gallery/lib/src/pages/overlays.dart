// The Overlays group of the gallery.
import 'dart:async';

import 'package:twk/twk.dart';

import '../page.dart';
import 'common.dart';

/// The Code's line of the Keep button.
const _keepLine =
    "              Button('Keep', onPressed: () => closeDialog(context, "
    'false)),';

/// The Code's line of the Remove button.
const _removeLine =
    "        Button('Remove one', onPressed: _entries.isEmpty ? null : "
    '_remove),';

/// Where the n-th entry of the Overlay page goes, as its Code writes it.
const _entryAt = {
  'topRight': ['right: 4 * n - 3', 'top: 2 * n - 1'],
  'topLeft': ['left: 4 * n - 3', 'top: 2 * n - 1'],
  'bottomLeft': ['left: 4 * n - 3', 'bottom: 7 - 2 * n'],
};

/// How the panels of a page stand out: PanelLook's names, raised first.
final _lookOption = ChoiceOption(
  'look',
  'look',
  values: [for (final l in PanelLook.values) l.name],
);

/// The look [o] chooses.
PanelLook _lookOf(Options o) => PanelLook.values.byName(o.choice('look'));

/// The Code's line that passes the look [o] chooses, [indent] in; none
/// for the default, raised.
List<String> _lookLine(Options o, String indent) => [
  if (_lookOf(o) != PanelLook.raised) '${indent}look: .${o.label('look')},',
];

/// The pages of the Overlays group that draw.
final overlayPages = [
  GalleryPage(
    group: 'Overlays',
    title: 'Overlay',
    options: [
      ChoiceOption('position', 'positioned', values: _entryAt.keys.toList()),
      const SwitchOption('shadow', 'shadow', initial: true),
      _lookOption,
    ],
    build: (context, o) => _Entries(
      position: o.choice('position'),
      shadow: o.flag('shadow'),
      look: _lookOf(o),
    ),
    code: (o) => [
      'final _entries = <OverlayEntry>[];',
      '',
      '@override',
      'void dispose() {',
      '  for (final entry in _entries) {',
      '    entry.remove();',
      '  }',
      '  super.dispose();',
      '}',
      '',
      'void _insert() {',
      '  final n = _entries.length + 1;',
      '  final entry = OverlayEntry(',
      '    builder: (context) => Positioned(',
      for (final a in _entryAt[o.choice<String>('position')]!) '      $a,',
      '      child: Panel(',
      ..._lookLine(o, '        '),
      '        padding: const .x(1),',
      if (!o.flag('shadow')) '        shadow: false,',
      '        child: Text.rich([',
      r"          'Entry $n'.bold,",
      "          Span(' of the overlay', Theme.of(context).muted),",
      '        ]),',
      '      ),',
      '    ),',
      '  );',
      '  Overlay.of(context).insert(entry);',
      '  setState(() => _entries.add(entry));',
      '}',
      '',
      'void _remove() => setState(() => _entries.removeLast().remove());',
      '',
      '@override',
      'Widget build(BuildContext context) => Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      '    Row(',
      '      mainAxisSize: .min,',
      '      gap: 2,',
      '      children: [',
      '        Button(',
      "          'Insert an entry',",
      '          onPressed: _entries.length < 3 ? _insert : null,',
      '        ),',
      _removeLine,
      '      ],',
      '    ),',
      '    Text.rich([',
      "      Span('entries: ', Theme.of(context).muted),",
      r"      Span('${_entries.length}'),",
      "      Span(' of the overlay', Theme.of(context).muted),",
      '    ]),',
      '  ],',
      ');',
    ].join('\n'),
  ),
  GalleryPage(
    group: 'Overlays',
    title: 'Dialog',
    options: [
      const ChoiceOption(
        'alignment',
        'alignment',
        values: ['center', 'topCenter', 'bottomRight'],
      ),
      const SwitchOption('shadow', 'shadow'),
      _lookOption,
      const SwitchOption('dismissible', 'dismissible', initial: true),
    ],
    build: (context, o) => _Ask(
      alignment: o.choice('alignment'),
      shadow: o.flag('shadow'),
      look: _lookOf(o),
      dismissible: o.flag('dismissible'),
    ),
    code: (o) => [
      'String? _answer;',
      '',
      'void _ask() => unawaited(',
      '  showDialog<bool>(',
      '    context,',
      '    (context) => Dialog(',
      "      title: 'Delete',",
      if (o.flag('shadow')) '      shadow: Panel.shadowOf(Theme.of(context)),',
      ..._lookLine(o, '      '),
      '      child: Column(',
      '        mainAxisSize: .min,',
      '        crossAxisAlignment: .start,',
      '        gap: 1,',
      '        children: [',
      "          const Text('Delete 3 files?'),",
      '          Row(',
      '            mainAxisSize: .min,',
      '            gap: 2,',
      '            children: [',
      '              Button(',
      "                'Delete',",
      '                autofocus: true,',
      '                onPressed: () => closeDialog(context, true),',
      '              ),',
      _keepLine,
      '            ],',
      '          ),',
      '        ],',
      '      ),',
      '    ),',
      if (!o.flag('dismissible')) '    dismissible: false,',
      '    alignment: .${o.label('alignment')},',
      '  ).then(',
      '    (delete) => setState(',
      '      () => _answer = switch (delete) {',
      "        true => 'deleted',",
      "        false => 'kept',",
      "        null => 'dismissed',",
      '      },',
      '    ),',
      '  ),',
      ');',
      '',
      '@override',
      'Widget build(BuildContext context) => Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      "    Button('Ask', onPressed: _ask),",
      '    Text.rich([',
      "      Span('answer: ', Theme.of(context).muted),",
      '      switch (_answer) {',
      "        null => Span('nothing', Theme.of(context).muted),",
      '        final answer => Span(answer),',
      '      },',
      '    ]),',
      '  ],',
      ');',
    ].join('\n'),
  ),
  GalleryPage(
    group: 'Overlays',
    title: 'Toast',
    options: [
      const ChoiceOption(
        'alignment',
        'alignment',
        values: ['bottomRight', 'topRight', 'bottomCenter'],
      ),
      const ChoiceOption(
        'duration',
        'duration',
        values: [1000, 3000, 5000],
        labels: ['1 s', '3 s', '5 s'],
        initial: 3000,
      ),
      _lookOption,
    ],
    build: (context, o) => _Toasts(
      alignment: o.choice('alignment'),
      ms: o.choice('duration'),
      look: _lookOf(o),
    ),
    code: (o) => [
      'var _n = 0;',
      '',
      'void _show() {',
      '  final theme = Theme.of(context);',
      '  final (message, style) = [',
      "    ('Saved 3 files.', theme.success),",
      "    ('Copied the path.', theme.info),",
      "    ('Disk nearly full.', theme.warning),",
      "    ('Upload failed.', theme.error),",
      '  ][_n++ % 4];',
      '  showToast(',
      '    context,',
      '    message,',
      '    alignment: .${o.label('alignment')},',
      if (o.choice<int>('duration') != 3000)
        '    duration: const Duration(seconds: ${_seconds(o)}),',
      '    style: style,',
      ..._lookLine(o, '    '),
      '  );',
      '}',
      '',
      '@override',
      _toastBuildLine,
    ].join('\n'),
  ),
  GalleryPage(
    group: 'Overlays',
    title: 'Tooltip',
    about:
        'A message by a widget while the mouse or the keyboard focus rests '
        'on it, or while a TooltipController says, centred under it by an '
        'AnchorFollower in the overlay; above it where there is no room '
        'below.',
    options: [
      const ChoiceOption(
        'wait',
        'wait',
        values: [100, 500, 1000],
        labels: ['100 ms', '500 ms', '1 s'],
        initial: 500,
      ),
      const SwitchOption('hover', 'on hover', initial: true),
      const SwitchOption('focus', 'on focus', initial: true),
      _lookOption,
    ],
    build: (context, o) => _Tips(
      wait: Duration(milliseconds: o.choice('wait')),
      hover: o.flag('hover'),
      focus: o.flag('focus'),
      look: _lookOf(o),
    ),
    code: (o) => [
      'final _share = TooltipController();',
      '',
      '@override',
      'void dispose() {',
      '  _share.dispose();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) => Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      '    Row(',
      '      mainAxisSize: .min,',
      '      gap: 2,',
      '      children: [',
      '        for (final (label, message, done) in const [',
      for (final (label, message, done) in _tips)
        "          ('$label', '$message', '$done'),",
      '        ])',
      '          Tooltip(',
      '            message: message,',
      if (o.choice<int>('wait') case final ms when ms != 500)
        '            wait: const Duration(milliseconds: $ms),',
      if (!o.flag('hover')) '            showOnHover: false,',
      if (!o.flag('focus')) '            showOnFocus: false,',
      ..._lookLine(o, '            '),
      "            controller: label == 'Share' ? _share : null,",
      '            child: Button(',
      '              label,',
      '              onPressed: () => showToast(',
      '                context,',
      '                done,',
      '                style: Theme.of(context).success,',
      '              ),',
      '            ),',
      '          ),',
      '      ],',
      '    ),',
      '    // shows the Share message at once, until it is pressed again',
      '    ListenableBuilder(',
      '      listenable: _share,',
      '      builder: (context, _) => Button(',
      "        _share.isShown ? 'Hide the tip' : 'Show the tip',",
      '        onPressed: _share.isShown ? _share.hide : _share.show,',
      '      ),',
      '    ),',
      '  ],',
      ');',
    ].join('\n'),
  ),
  GalleryPage(
    group: 'Overlays',
    title: 'Popover',
    about:
        'A widget by another while the app says so, placed by an '
        'AnchorTarget around it and an AnchorFollower in the overlay; Escape '
        'or a click outside closes it.',
    options: [
      const SwitchOption('dismissible', 'dismissible', initial: true),
      _lookOption,
    ],
    build: (context, o) =>
        _Pop(dismissible: o.flag('dismissible'), look: _lookOf(o)),
    code: (o) => [
      'var _open = false;',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return Popover(',
      '    open: _open,',
      if (o.flag('dismissible'))
        '    onDismiss: () => setState(() => _open = false),',
      '    popover: Panel(',
      ..._lookLine(o, '      '),
      '      padding: const .x(1),',
      '      child: Column(',
      '        mainAxisSize: .min,',
      '        crossAxisAlignment: .start,',
      '        children: [',
      "          const Text('${_pop[0]}'),",
      "          Text('${_pop[o.flag('dismissible') ? 1 : 2]}', $_muted),",
      '        ],',
      '      ),',
      '    ),',
      '    child: Button(',
      "      _open ? 'Close' : 'Open',",
      '      onPressed: () => setState(() => _open = !_open),',
      '    ),',
      '  );',
      '}',
    ].join('\n'),
  ),
  GalleryPage(
    group: 'Overlays',
    title: 'MenuBar',
    // an open menu takes Tab itself
    modalTab: false,
    options: [
      const SwitchOption('keys', 'keys bound', initial: true),
      _lookOption,
    ],
    build: (context, o) => _Bar(keys: o.flag('keys'), look: _lookOf(o)),
    code: _menuBarCode,
  ),
  GalleryPage(
    group: 'Overlays',
    title: 'ContextMenu',
    // an open menu (or palette) takes Tab itself
    modalTab: false,
    options: [_lookOption],
    build: (context, o) => _Context(look: _lookOf(o)),
    code: _contextCode,
  ),
  GalleryPage(
    group: 'Overlays',
    title: 'CommandPalette',
    about:
        'What can be done, found by typing: Tab to a button, then Ctrl+K, '
        'or press Dart files, whose CommandPaletteController opens it with '
        'dart typed; commandsFor adds the files that match. The '
        "gallery's own, Ctrl+P, goes to a page.",
    // an open menu (or palette) takes Tab itself
    modalTab: false,
    options: [
      const ChoiceOption('width', 'width', values: [40, 60], initial: 40),
      const ChoiceOption('rows', 'rows', values: [3, 10], initial: 10),
      const SwitchOption('files', 'files', initial: true),
      _lookOption,
    ],
    build: (context, o) => _Palette(
      width: o.choice('width'),
      rows: o.choice('rows'),
      files: o.flag('files'),
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
      if (o.flag('files')) ...[
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
      '  width: ${o.label('width')},',
      if (o.choice<int>('rows') != 10) '  rows: ${o.label('rows')},',
      ..._lookLine(o, '  '),
      '  commands: [',
      "    Command('Build', onSelected: _build),",
      "    Command('Run tests', onSelected: _test),",
      "    Command('Format', onSelected: () => _run('Format')),",
      "    Command('Deploy', onSelected: () => _run('Deploy')),",
      '  ],',
      if (o.flag('files')) ...[
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
      '      gap: 1,',
      '      children: [',
      '        Row(',
      '          mainAxisSize: .min,',
      '          gap: 2,',
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
  ),
  GalleryPage(
    group: 'Overlays',
    title: 'OptionList',
    options: const [
      ChoiceOption(
        'query',
        'marks of',
        values: ['', 'o', 'sa'],
        labels: ['none', 'o', 'sa'],
      ),
      ChoiceOption('rows', 'rows', values: [3, 5, 8], initial: 5),
      SwitchOption('details', 'details', initial: true),
      SwitchOption('bar', 'bar', initial: true),
      SwitchOption('thumb', 'thumb', initial: true),
    ],
    build: (context, o) => _Options(
      query: o.choice('query'),
      rows: o.choice('rows'),
      details: o.flag('details'),
      bar: o.flag('bar'),
      thumb: o.flag('thumb'),
    ),
    code: _optionListCode,
  ),
  GalleryPage(
    group: 'Overlays',
    title: 'ModalBarrier',
    options: [
      const SwitchOption('barrier', 'barrier', initial: true),
      const ChoiceOption(
        'alpha',
        'alpha',
        values: [0x40, 0x80, 0xc0],
        labels: ['¼', '½', '¾'],
        initial: 0x80,
      ),
      // an AnimatedModalBarrier, its shade coming in and going on a
      // controller
      SwitchOption('fade', 'fade', disabled: (o) => !o.flag('barrier')),
    ],
    build: (context, o) => _Barrier(
      barrier: o.flag('barrier'),
      alpha: o.choice('alpha'),
      fade: o.flag('barrier') && o.flag('fade'),
    ),
    code: _barrierCode,
  ),
  GalleryPage(
    group: 'Overlays',
    title: 'WindowLayer',
    options: [
      ChoiceOption(
        'frame',
        'frame',
        values: [for (final f in WindowFrame.values) f.name],
      ),
      const SwitchOption('shadow', 'shadow', initial: true),
      const SwitchOption('resizable', 'resizable', initial: true),
      const SwitchOption('minimisable', 'minimisable', initial: true),
      const SwitchOption('maximisable', 'maximisable', initial: true),
    ],
    build: (context, o) => _Windows(
      frame: WindowFrame.values.byName(o.choice('frame')),
      shadow: o.flag('shadow'),
      resizable: o.flag('resizable'),
      minimisable: o.flag('minimisable'),
      maximisable: o.flag('maximisable'),
    ),
    // the layer's SizedBox
    heightIn: (o, room) => 12,
    code: _windowsCode,
  ),
];

/// What the Notes window says.
/// The commands of the OptionList page: a label and its keys.
const _commands = [
  ('Open file', 'ctrl+o'),
  ('Save', 'ctrl+s'),
  ('Save as…', 'ctrl+shift+s'),
  ('Close tab', 'ctrl+w'),
  ('Find', 'ctrl+f'),
  ('Replace', 'ctrl+h'),
  ('Go to line', 'ctrl+g'),
  ('Toggle theme', 'ctrl+t'),
  ('Quit', 'ctrl+q'),
];

/// The Dart of the OptionList page.
String _optionListCode(Options o) {
  final q = o.choice<String>('query');
  final details = o.flag('details');
  final detail = details ? ', detail: keys' : '';
  return [
    'const _commands = [',
    for (final (l, k) in _commands) "  ('$l', '$k'),",
    '];',
    '',
    'var _highlighted = 0;',
    'String? _ran;',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    if (q.isNotEmpty) ...[
      "  // the commands '$q' matches, its characters marked",
      '  final options = [',
      '    for (final (label, ${details ? 'keys' : '_'}) in _commands)',
      "      if (fuzzyMatch('$q', label) case final match?)",
      '        Option(label, marks: match.positions$detail),',
      '  ];',
    ] else if (details) ...[
      '  final options = [',
      '    for (final (label, keys) in _commands) Option(label, detail: keys),',
      '  ];',
    ] else
      '  final options = [for (final (label, _) in _commands) Option(label)];',
    '  final highlighted = _highlighted.clamp(0, options.length - 1);',
    '  void highlight(int i) => setState(() => _highlighted = i);',
    '  void move(int by) =>',
    '      highlight((highlighted + by).clamp(0, options.length - 1));',
    '  void run(int i) => setState(() => _ran = options[i].label);',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    '      // the list takes no keys: a Pressable around it',
    '      // does, its border primary while it has the focus',
    '      Pressable(',
    '        bindings: {',
    "          'up': () => move(-1),",
    "          'down': () => move(1),",
    "          'enter': () => run(highlighted),",
    '        },',
    "        hints: const {'up': 'select', 'down': 'select', 'enter': 'run'},",
    '        builder: (context, focused) => Box(',
    '          border: .all(',
    '            type: .rounded,',
    '            style: focused ? theme.primary : theme.border,',
    '          ),',
    '          child: OptionList(',
    '            options: options,',
    '            highlighted: highlighted,',
    '            rows: ${o.label('rows')},',
    if (!o.flag('bar')) '            bar: false,',
    if (!o.flag('thumb')) '            thumb: false,',
    '            onHighlight: highlight,',
    '            onSelected: run,',
    '          ),',
    '        ),',
    '      ),',
    '      Text.rich([',
    "        Span('ran: ', theme.muted),",
    '        if (_ran case final ran?)',
    '          Span(ran)',
    '        else',
    "          Span('nothing', theme.muted),",
    '      ]),',
    '    ],',
    '  );',
    '}',
  ].join('\n');
}

/// The OptionList page's widget: the commands [query] matches in an
/// OptionList of [rows] rows, the keys a Pressable's around it, and what
/// ran.
final class _Options extends StatefulWidget {
  const _Options({
    required this.query,
    required this.rows,
    required this.details,
    required this.bar,
    required this.thumb,
  });

  final String query;
  final int rows;
  final bool details;
  final bool bar;
  final bool thumb;

  @override
  State<_Options> createState() => _OptionsState();
}

final class _OptionsState extends State<_Options> {
  // kept in the page's state while the gallery runs
  late final Map<String, Object?> _kept = PageControl.of(context).state;
  int get _highlighted => _kept['highlighted'] as int? ?? 0;
  set _highlighted(int i) => _kept['highlighted'] = i;
  String? get _ran => _kept['ran'] as String?;
  int get _serial => _kept['serial'] as int? ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.query;
    final options = [
      for (final (label, keys) in _commands)
        if (fuzzyMatch(q, label) case final match?)
          Option(
            label,
            marks: match.positions,
            detail: widget.details ? keys : null,
          ),
    ];
    final highlighted = _highlighted.clamp(0, options.length - 1);
    void highlight(int i) => setState(() => _highlighted = i);
    void move(int by) =>
        highlight((highlighted + by).clamp(0, options.length - 1));
    void run(int i) => setState(() {
      _kept['ran'] = options[i].label;
      _kept['serial'] = _serial + 1;
    });
    final ran = _ran;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Pressable(
          bindings: {
            'up': () => move(-1),
            'down': () => move(1),
            'enter': () => run(highlighted),
          },
          hints: const {'up': 'select', 'down': 'select', 'enter': 'run'},
          builder: (context, focused) => Box(
            border: Border.all(
              type: BorderType.rounded,
              style: focused ? theme.primary : theme.border,
            ),
            child: OptionList(
              options: options,
              highlighted: highlighted,
              rows: widget.rows,
              bar: widget.bar,
              thumb: widget.thumb,
              onHighlight: highlight,
              onSelected: run,
            ),
          ),
        ),
        LitLine([
          ('ran: ', true),
          if (ran == null) ('nothing', true) else (ran, false),
        ], serial: _serial),
      ],
    );
  }
}

const _note = 'Drag me by the title bar, or resize me by an edge.';

/// The WindowLayer page's Code.
String _windowsCode(Options o) {
  final extra = [
    if (o.flag('shadow'))
      '          shadow: Panel.shadowOf(Theme.of(context)),',
    if (!o.flag('resizable')) '          resizable: false,',
    if (!o.flag('minimisable')) '          minimisable: false,',
    if (!o.flag('maximisable')) '          maximisable: false,',
  ].map((l) => '$l\n').join();
  final frame = o.choice<String>('frame') == WindowFrame.raised.name
      ? ''
      : '    frame: .${o.label('frame')},\n';
  return '''
final _notes = WindowController(left: 2, top: 3, width: 30, height: 6);
final _counter = WindowController(left: 24, top: 5, width: 26, height: 6);
final _closed = <String>{};
var _count = 0;

@override
void dispose() {
  _notes.dispose();
  _counter.dispose();
  super.dispose();
}

void _close(String title) => setState(() => _closed.add(title));

@override
Widget build(BuildContext context) => SizedBox(
  width: 50,
  height: 12,
  child: WindowLayer(
$frame    windows: [
      if (!_closed.contains('Notes'))
        Window(
          key: const ValueKey('Notes'),
          title: 'Notes',
          controller: _notes,
          onClose: () => _close('Notes'),
$extra          child: const Padding(
            padding: .x(1),
            child: Text('$_note'),
          ),
        ),
      if (!_closed.contains('Counter'))
        Window(
          key: const ValueKey('Counter'),
          title: 'Counter',
          controller: _counter,
          onClose: () => _close('Counter'),
$extra          child: Padding(
            padding: const .x(1),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text('count: \$_count'),
                Button('Add one', onPressed: () => setState(() => _count++)),
              ],
            ),
          ),
        ),
    ],
    child: Column(
      crossAxisAlignment: .start,
      children: [
        const Text('The app, under its windows.'),
        Button(
          'Open the windows closed',
          onPressed: _closed.isEmpty ? null : () => setState(_closed.clear),
        ),
      ],
    ),
  ),
);''';
}

/// Two windows over an app: Notes and a counter, that move, resize,
/// minimise, maximise and close. Where they are, which are closed and the
/// count are kept while the gallery runs.
final class _Windows extends StatefulWidget {
  const _Windows({
    required this.frame,
    required this.shadow,
    required this.resizable,
    required this.minimisable,
    required this.maximisable,
  });

  final WindowFrame frame;
  final bool shadow;
  final bool resizable;
  final bool minimisable;
  final bool maximisable;

  @override
  State<_Windows> createState() => _WindowsState();
}

final class _WindowsState extends State<_Windows> {
  late final Map<String, Object?> _kept = _keptOf(context);
  late final _notes =
      (_kept['notes'] ??= WindowController(
            left: 2,
            top: 3,
            width: 30,
            height: 6,
          ))
          as WindowController;
  late final _counter =
      (_kept['counter'] ??= WindowController(
            left: 24,
            top: 5,
            width: 26,
            height: 6,
          ))
          as WindowController;
  late final _closed = (_kept['closed'] ??= <String>{}) as Set<String>;
  int get _count => _kept['count'] as int? ?? 0;

  void _close(String title) => setState(() => _closed.add(title));

  @override
  Widget build(BuildContext context) {
    final shadow = widget.shadow ? Panel.shadowOf(Theme.of(context)) : null;
    return SizedBox(
      width: 50,
      height: 12,
      child: WindowLayer(
        frame: widget.frame,
        windows: [
          if (!_closed.contains('Notes'))
            Window(
              key: const ValueKey('Notes'),
              title: 'Notes',
              controller: _notes,
              onClose: () => _close('Notes'),
              shadow: shadow,
              resizable: widget.resizable,
              minimisable: widget.minimisable,
              maximisable: widget.maximisable,
              child: const Padding(
                padding: EdgeInsets.x(1),
                child: Text(_note),
              ),
            ),
          if (!_closed.contains('Counter'))
            Window(
              key: const ValueKey('Counter'),
              title: 'Counter',
              controller: _counter,
              onClose: () => _close('Counter'),
              shadow: shadow,
              resizable: widget.resizable,
              minimisable: widget.minimisable,
              maximisable: widget.maximisable,
              child: Padding(
                padding: const EdgeInsets.x(1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('count: $_count'),
                    Button(
                      'Add one',
                      onPressed: () =>
                          setState(() => _kept['count'] = _count + 1),
                    ),
                  ],
                ),
              ),
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The app, under its windows.'),
            Button(
              'Open the windows closed',
              onPressed: _closed.isEmpty ? null : () => setState(_closed.clear),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ModalBarrier page's Code.
String _barrierCode(Options o) {
  final alpha = o.choice<int>('alpha');
  final fade = o.flag('barrier') && o.flag('fade');
  final barrier = !o.flag('barrier')
      ? ''
      : [
          if (fade) ...[
            '      AnimatedModalBarrier(',
            '        animation: _fade,',
          ] else
            '      ModalBarrier(',
          if (alpha != 0x80)
            '        alpha: 0x${alpha.toRadixString(16)}, // ${o.label('alpha')}',
          '        onDismiss: () => setState(() => _dismissed++),',
          '      ),',
          '',
        ].join('\n');
  final controller = !fade
      ? ''
      : '''

// the shade comes in and goes, again and again
late final _fade = AnimationController(
  vsync: this,
  duration: const Duration(seconds: 1),
)..repeat(reverse: true);

@override
void dispose() {
  _fade.dispose();
  super.dispose();
}''';
  return '''
var _pressed = 0;
var _dismissed = 0;$controller

@override
Widget build(BuildContext context) => SizedBox(
  width: 40,
  height: 8,
  child: Stack(
    fit: .expand,
    children: [
      Column(
        crossAxisAlignment: .start,
        gap: 1,
        children: [
          const Text(
            'The text under the barrier, dimmed by it: the mouse does not '
            'reach it.',
          ),
          Button('Press me', onPressed: () => setState(() => _pressed++)),
          Text.rich([
            Span('pressed ', Theme.of(context).muted),
            Span('\$_pressed'),
            Span(', the barrier ', Theme.of(context).muted),
            Span('\$_dismissed'),
          ]),
        ],
      ),
$barrier      const Center(
        child: Panel(
          padding: .x(1),
          shadow: false,
          child: Text('over it'),
        ),
      ),
    ],
  ),
);''';
}

/// Text and a button under a barrier, and a panel over it.
final class _Barrier extends StatefulWidget {
  const _Barrier({
    required this.barrier,
    required this.alpha,
    required this.fade,
  });

  final bool barrier;
  final int alpha;

  /// Whether the barrier is an [AnimatedModalBarrier] whose shade comes in
  /// and goes on a controller of 1 s, repeated both ways.
  final bool fade;

  @override
  State<_Barrier> createState() => _BarrierState();
}

final class _BarrierState extends State<_Barrier>
    with TickerProviderStateMixin {
  late final Map<String, Object?> _kept = _keptOf(context);
  int get _pressed => _kept['pressed'] as int? ?? 0;
  int get _dismissed => _kept['dismissed'] as int? ?? 0;

  // the Code's _fade, from when fade is turned on
  AnimationController? _fade;

  @override
  void dispose() {
    _fade?.dispose();
    super.dispose();
  }

  /// The controller while fade is on: made and run when it is turned on,
  /// thrown away when it is turned off.
  AnimationController? _fadeNow() {
    if (!widget.fade) {
      _fade?.dispose();
      return _fade = null;
    }
    return _fade ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  void _dismiss() => setState(() => _kept['dismissed'] = _dismissed + 1);

  @override
  Widget build(BuildContext context) {
    final fade = _fadeNow();
    final alpha = widget.alpha == 0x80 ? null : widget.alpha;
    return _build(
      context,
      !widget.barrier
          ? null
          : fade != null
          ? AnimatedModalBarrier(
              animation: fade,
              alpha: alpha,
              onDismiss: _dismiss,
            )
          : ModalBarrier(alpha: alpha, onDismiss: _dismiss),
    );
  }

  Widget _build(BuildContext context, Widget? barrier) => SizedBox(
    width: 40,
    height: 8,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          gap: 1,
          children: [
            const Text(
              'The text under the barrier, dimmed by it: the mouse does not '
              'reach it.',
            ),
            Button(
              'Press me',
              onPressed: () => setState(() => _kept['pressed'] = _pressed + 1),
            ),
            Text.rich([
              Span('pressed ', Theme.of(context).muted),
              Span('$_pressed'),
              Span(', the barrier ', Theme.of(context).muted),
              Span('$_dismissed'),
            ]),
          ],
        ),
        ?barrier,
        const Center(
          child: Panel(
            padding: EdgeInsets.x(1),
            shadow: false,
            child: Text('over it'),
          ),
        ),
      ],
    ),
  );
}

/// The MenuBar page's Code.
String _menuBarCode(Options o) {
  final keys = o.flag('keys');
  String on(String fn, String closure) => keys ? fn : closure;
  return [
    'final _menus = MenuController();',
    'String? _chosen;',
    'var _wrap = true;',
    'var _numbers = false;',
    '',
    '@override',
    'void dispose() {',
    '  _menus.dispose();',
    '  super.dispose();',
    '}',
    '',
    'void _choose(String what) => setState(() => _chosen = what);',
    if (keys) ...[
      "void _open() => _choose('Open');",
      "void _save() => _choose('Save');",
      "void _undo() => _choose('Undo');",
    ],
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final child = Padding(',
    '    padding: const .all(1),',
    '    child: Column(',
    '      crossAxisAlignment: .start,',
    '      gap: 1,',
    '      children: [',
    '        Text.rich([',
    "          Span('chosen: ', Theme.of(context).muted),",
    '          switch (_chosen) {',
    "            null => Span('nothing', Theme.of(context).muted),",
    '            final chosen => Span(chosen),',
    '          },',
    '        ]),',
    '        Row(',
    '          gap: 2,',
    '          children: [',
    '            Checkbox(',
    '              value: _wrap,',
    "              label: 'wrap lines',",
    '              onChanged: (value) => setState(() => _wrap = value),',
    '            ),',
    '            // File › Open recent, opened from outside the bar',
    '            Button(',
    "              'Recent files',",
    '              onPressed: () => _menus.open([0, 2]),',
    '            ),',
    '          ],',
    '        ),',
    '      ],',
    '    ),',
    '  );',
    '  return SizedBox(',
    '    width: 48,',
    '    height: 8,',
    '    child: MenuBar(',
    '      controller: _menus,',
    ..._lookLine(o, '      '),
    '      menus: [',
    '        Menu(',
    "          '&File',",
    '          items: [',
    "            MenuItem('&New', onSelected: () => _choose('New')),",
    _item('&Open…', on('_open', "() => _choose('Open')")),
    '            Menu(',
    "              'Open &recent',",
    '              items: [',
    '                for (final file in const [',
    "                  'main.dart',",
    "                  'page.dart',",
    "                  'overlay.dart',",
    '                ])',
    '                  MenuItem(file, onSelected: () => _choose(file)),',
    '              ],',
    '            ),',
    '            const MenuDivider(),',
    _item('&Save', on('_save', "() => _choose('Save')")),
    "            const MenuItem('&Print'),",
    '          ],',
    '        ),',
    '        Menu(',
    "          '&Edit',",
    '          items: [',
    _item('&Undo', on('_undo', "() => _choose('Undo')")),
    "            const MenuItem('&Redo'),",
    '            const MenuDivider(),',
    "            for (final what in const ['Cu&t', '&Copy', '&Paste'])",
    '              MenuItem(',
    '                what,',
    "                onSelected: () => _choose(what.replaceAll('&', '')),",
    '              ),',
    '          ],',
    '        ),',
    '        Menu(',
    "          '&View',",
    '          items: [',
    '            MenuItem(',
    "              '&Wrap lines',",
    '              checked: _wrap,',
    '              onSelected: () => setState(() {',
    '                _wrap = !_wrap;',
    "                _chosen = 'Wrap lines';",
    '              }),',
    '            ),',
    '            MenuItem(',
    "              'Line &numbers',",
    '              checked: _numbers,',
    '              onSelected: () => setState(() {',
    '                _numbers = !_numbers;',
    "                _chosen = 'Line numbers';",
    '              }),',
    '            ),',
    '          ],',
    '        ),',
    '      ],',
    if (keys) ...[
      '      // the items show the keys bound to what they call',
      '      child: KeyBindings(',
      "        {'ctrl+o': _open, 'ctrl+s': _save, 'ctrl+z': _undo},",
      '        child: child,',
      '      ),',
    ] else
      '      child: child,',
    '    ),',
    '  );',
    '}',
  ].join('\n');
}

/// The Code's line of a menu item [label] that calls [call].
String _item(String label, String call) =>
    "            MenuItem('$label', onSelected: $call),";

/// The ContextMenu page's Code.
String _contextCode(Options o) =>
    '''
final _menu = MenuController();
String? _chosen;
var _copied = false;

@override
void dispose() {
  _menu.dispose();
  super.dispose();
}

void _choose(String what) => setState(() {
  _chosen = what;
  _copied |= what == 'Cut' || what == 'Copy';
});

@override
Widget build(BuildContext context) => ContextMenu(
  controller: _menu,
${_lookLine(o, '  ').map((l) => '$l\n').join()}  items: [
    MenuItem('Cu&t', onSelected: () => _choose('Cut')),
    MenuItem('&Copy', onSelected: () => _choose('Copy')),
    MenuItem('&Paste', onSelected: _copied ? () => _choose('Paste') : null),
    const MenuDivider(),
    MenuItem('Select &all', onSelected: () => _choose('Select all')),
  ],
  child: SizedBox(
    width: 40,
    height: 5,
    child: Box(
      border: .all(type: .rounded, style: Theme.of(context).border),
      padding: const .x(1),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          const Text('Right click in here.'),
          Row(
            gap: 2,
            children: [
              Button('Or focus me', onPressed: () {}),
              // at a cell of the child, as a right click there
              Button(
                'Open the menu',
                onPressed: () => _menu.open(null, (22, 1)),
              ),
            ],
          ),
          Text.rich([
            Span('chosen: ', Theme.of(context).muted),
            switch (_chosen) {
              null => Span('nothing', Theme.of(context).muted),
              final chosen => Span(chosen),
            },
          ]),
        ],
      ),
    ),
  ),
);''';

/// The page's state of [context] that outlives a visit to another page.
Map<String, Object?> _keptOf(BuildContext context) =>
    PageControl.of(context).state;

/// A menu bar over what was chosen and a checkbox the View menu flips too.
final class _Bar extends StatefulWidget {
  const _Bar({required this.keys, required this.look});

  final bool keys;
  final PanelLook look;

  @override
  State<_Bar> createState() => _BarState();
}

final class _BarState extends State<_Bar> {
  late final Map<String, Object?> _kept = _keptOf(context);
  String? get _chosen => _kept['chosen'] as String?;
  bool get _wrap => _kept['wrap'] as bool? ?? true;
  bool get _numbers => _kept['numbers'] as bool? ?? false;
  int get _serial => _kept['serial'] as int? ?? 0;

  void _set(void Function() change) => setState(change);

  void _choose(String what) => _set(() {
    _kept['chosen'] = what;
    _kept['serial'] = _serial + 1;
  });
  void _open() => _choose('Open');
  void _save() => _choose('Save');
  void _undo() => _choose('Undo');

  final _menus = MenuController();

  @override
  void dispose() {
    _menus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.keys;
    final child = Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 1,
        children: [
          LitLine([
            ('chosen: ', true),
            (_chosen ?? 'nothing', _chosen == null),
          ], serial: _serial),
          Row(
            gap: 2,
            children: [
              Checkbox(
                value: _wrap,
                label: 'wrap lines',
                onChanged: (value) => _set(() => _kept['wrap'] = value),
              ),
              Button('Recent files', onPressed: () => _menus.open([0, 2])),
            ],
          ),
        ],
      ),
    );
    return SizedBox(
      width: 48,
      height: 8,
      child: MenuBar(
        controller: _menus,
        look: widget.look,
        menus: [
          Menu(
            '&File',
            items: [
              MenuItem('&New', onSelected: () => _choose('New')),
              MenuItem('&Open…', onSelected: _open),
              Menu(
                'Open &recent',
                items: [
                  for (final file in const [
                    'main.dart',
                    'page.dart',
                    'overlay.dart',
                  ])
                    MenuItem(file, onSelected: () => _choose(file)),
                ],
              ),
              const MenuDivider(),
              MenuItem('&Save', onSelected: _save),
              const MenuItem('&Print'),
            ],
          ),
          Menu(
            '&Edit',
            items: [
              MenuItem('&Undo', onSelected: _undo),
              const MenuItem('&Redo'),
              const MenuDivider(),
              for (final what in const ['Cu&t', '&Copy', '&Paste'])
                MenuItem(
                  what,
                  onSelected: () => _choose(what.replaceAll('&', '')),
                ),
            ],
          ),
          Menu(
            '&View',
            items: [
              MenuItem(
                '&Wrap lines',
                checked: _wrap,
                onSelected: () {
                  _kept['wrap'] = !_wrap;
                  _choose('Wrap lines');
                },
              ),
              MenuItem(
                'Line &numbers',
                checked: _numbers,
                onSelected: () {
                  _kept['numbers'] = !_numbers;
                  _choose('Line numbers');
                },
              ),
            ],
          ),
        ],
        child: keys
            ? KeyBindings({
                'ctrl+o': _open,
                'ctrl+s': _save,
                'ctrl+z': _undo,
              }, child: child)
            : child,
      ),
    );
  }
}

/// A box a right click opens a menu in, or Shift+F10 on its button.
final class _Context extends StatefulWidget {
  const _Context({required this.look});

  final PanelLook look;

  @override
  State<_Context> createState() => _ContextState();
}

final class _ContextState extends State<_Context> {
  late final Map<String, Object?> _kept = _keptOf(context);
  String? get _chosen => _kept['chosen'] as String?;
  bool get _copied => _kept['copied'] as bool? ?? false;
  int get _serial => _kept['serial'] as int? ?? 0;

  void _choose(String what) => setState(() {
    _kept
      ..['chosen'] = what
      ..['copied'] = _copied || what == 'Cut' || what == 'Copy'
      ..['serial'] = _serial + 1;
  });

  final _menu = MenuController();

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContextMenu(
    controller: _menu,
    look: widget.look,
    items: [
      MenuItem('Cu&t', onSelected: () => _choose('Cut')),
      MenuItem('&Copy', onSelected: () => _choose('Copy')),
      MenuItem('&Paste', onSelected: _copied ? () => _choose('Paste') : null),
      const MenuDivider(),
      MenuItem('Select &all', onSelected: () => _choose('Select all')),
    ],
    child: SizedBox(
      width: 40,
      height: 5,
      child: Box(
        border: Border.all(
          type: BorderType.rounded,
          style: Theme.of(context).border,
        ),
        padding: const EdgeInsets.x(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Right click in here.'),
            Row(
              gap: 2,
              children: [
                Button('Or focus me', onPressed: () {}),
                Button(
                  'Open the menu',
                  onPressed: () => _menu.open(null, (22, 1)),
                ),
              ],
            ),
            LitLine([
              ('chosen: ', true),
              (_chosen ?? 'nothing', _chosen == null),
            ], serial: _serial),
          ],
        ),
      ),
    ),
  );
}

/// A button under a command palette that Ctrl+K opens, and what ran.
final class _Palette extends StatefulWidget {
  const _Palette({
    required this.width,
    required this.rows,
    required this.files,
    required this.look,
  });

  final int width;
  final int rows;
  final PanelLook look;

  /// Whether commandsFor finds the files that match.
  final bool files;

  @override
  State<_Palette> createState() => _PaletteState();
}

final class _PaletteState extends State<_Palette> {
  late final Map<String, Object?> _kept = _keptOf(context);
  String? get _ran => _kept['ran'] as String?;
  int get _serial => _kept['serial'] as int? ?? 0;

  void _run(String what) => setState(() {
    _kept
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
        gap: 1,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            gap: 2,
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

/// The Tooltip page's buttons: each label, its tooltip, what a press says.
const _tips = [
  ('Save', 'Saves the file', 'Saved'),
  ('Open', 'Opens a file', 'Opened'),
  ('Share', 'Copies a link to it', 'Link copied'),
];

/// The Tooltip page: the three buttons with their tooltips, the Share one
/// served by a controller, and the button that shows and hides it.
final class _Tips extends StatefulWidget {
  const _Tips({
    required this.wait,
    required this.hover,
    required this.focus,
    required this.look,
  });

  final Duration wait;
  final bool hover;
  final bool focus;
  final PanelLook look;

  @override
  State<_Tips> createState() => _TipsState();
}

final class _TipsState extends State<_Tips> {
  final _share = TooltipController();

  @override
  void dispose() {
    _share.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        gap: 2,
        children: [
          for (final (label, message, done) in _tips)
            Tooltip(
              message: message,
              wait: widget.wait,
              showOnHover: widget.hover,
              showOnFocus: widget.focus,
              look: widget.look,
              controller: label == 'Share' ? _share : null,
              child: Button(
                label,
                onPressed: () => showToast(
                  context,
                  done,
                  style: Theme.of(context).success,
                ),
              ),
            ),
        ],
      ),
      ListenableBuilder(
        listenable: _share,
        builder: (context, _) => Button(
          _share.isShown ? 'Hide the tip' : 'Show the tip',
          onPressed: _share.isShown ? _share.hide : _share.show,
        ),
      ),
    ],
  );
}

/// The Toast page's duration in seconds.
int _seconds(Options o) => o.choice<int>('duration') ~/ 1000;

/// The Code's line that builds the Toast page's button.
const _toastBuildLine =
    "Widget build(BuildContext context) => Button('Show a toast', "
    'onPressed: _show);';

/// The muted style argument of the Code.
const _muted = 'style: theme.muted';

/// What the Popover page's popover says.
const _pop = [
  'The popover, by the button.',
  'Escape or a click outside closes it.',
  'Only the button closes it.',
];

/// A button that shows a toast, the next of four each time.
final class _Toasts extends StatefulWidget {
  const _Toasts({
    required this.alignment,
    required this.ms,
    required this.look,
  });

  final String alignment;
  final int ms;
  final PanelLook look;

  @override
  State<_Toasts> createState() => _ToastsState();
}

final class _ToastsState extends State<_Toasts> {
  late final Map<String, Object?> _kept = PageControl.of(context).state;

  static const Map<String, Alignment> _alignments = {
    'bottomRight': Alignment.bottomRight,
    'topRight': Alignment.topRight,
    'bottomCenter': Alignment.bottomCenter,
  };

  void _show() {
    final theme = Theme.of(context);
    final n = _kept['n'] as int? ?? 0;
    _kept['n'] = n + 1;
    final (message, style) = [
      ('Saved 3 files.', theme.success),
      ('Copied the path.', theme.info),
      ('Disk nearly full.', theme.warning),
      ('Upload failed.', theme.error),
    ][n % 4];
    showToast(
      context,
      message,
      alignment: _alignments[widget.alignment] ?? Alignment.bottomRight,
      duration: Duration(milliseconds: widget.ms),
      style: style,
      look: widget.look,
    );
  }

  @override
  Widget build(BuildContext context) =>
      Button('Show a toast', onPressed: _show);
}

/// A button that opens a popover by it and closes it.
final class _Pop extends StatefulWidget {
  const _Pop({required this.dismissible, required this.look});

  final bool dismissible;
  final PanelLook look;

  @override
  State<_Pop> createState() => _PopState();
}

final class _PopState extends State<_Pop> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Popover(
      open: _open,
      onDismiss: widget.dismissible
          ? () => setState(() => _open = false)
          : null,
      popover: Panel(
        look: widget.look,
        padding: const EdgeInsets.x(1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_pop[0]),
            Text(_pop[widget.dismissible ? 1 : 2], style: theme.muted),
          ],
        ),
      ),
      child: Button(
        _open ? 'Close' : 'Open',
        onPressed: () => setState(() => _open = !_open),
      ),
    );
  }
}

/// A button that asks in a dialog, and the answer.
final class _Ask extends StatefulWidget {
  const _Ask({
    required this.alignment,
    required this.shadow,
    required this.look,
    required this.dismissible,
  });

  final String alignment;
  final bool shadow;
  final PanelLook look;

  /// Whether Escape and a click outside dismiss the dialog.
  final bool dismissible;

  @override
  State<_Ask> createState() => _AskState();
}

final class _AskState extends State<_Ask> {
  String? _answer;
  var _asked = 0;

  static const Map<String, Alignment> _alignments = {
    'center': Alignment.center,
    'topCenter': Alignment.topCenter,
    'bottomRight': Alignment.bottomRight,
  };

  void _ask() => unawaited(
    showDialog<bool>(
      context,
      (context) => Dialog(
        title: 'Delete',
        shadow: widget.shadow ? Panel.shadowOf(Theme.of(context)) : null,
        look: widget.look,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          gap: 1,
          children: [
            const Text('Delete 3 files?'),
            Row(
              mainAxisSize: MainAxisSize.min,
              gap: 2,
              children: [
                Button(
                  'Delete',
                  autofocus: true,
                  onPressed: () => closeDialog(context, true),
                ),
                Button('Keep', onPressed: () => closeDialog(context, false)),
              ],
            ),
          ],
        ),
      ),
      dismissible: widget.dismissible,
      alignment: _alignments[widget.alignment] ?? Alignment.center,
    ).then((delete) {
      if (mounted) {
        setState(() {
          _asked++;
          _answer = switch (delete) {
            true => 'deleted',
            false => 'kept',
            null => 'dismissed',
          };
        });
      }
    }),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      Button('Ask', onPressed: _ask),
      LitLine([
        ('answer: ', true),
        (_answer ?? 'nothing', _answer == null),
      ], serial: _asked),
    ],
  );
}

/// Two buttons that insert entries into the app's overlay and remove them,
/// and how many there are. The gallery keeps how many while it runs, and
/// shows them again when the page comes back (on the Code tab too, as the
/// design's overlay does).
final class _Entries extends StatefulWidget {
  const _Entries({
    required this.position,
    required this.shadow,
    required this.look,
  });

  final String position;
  final bool shadow;
  final PanelLook look;

  @override
  State<_Entries> createState() => _EntriesState();
}

final class _EntriesState extends State<_Entries> {
  late final Map<String, Object?> _kept = PageControl.of(context).state;
  final _entries = <OverlayEntry>[];
  var _restored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) {
      return;
    }
    _restored = true;
    final n = _kept['entries'] as int? ?? 0;
    if (n > 0) {
      // an entry goes in outside a build
      unawaited(
        Future.microtask(() {
          for (var i = 0; mounted && i < n; i++) {
            _insert(keep: false);
          }
        }),
      );
    }
  }

  @override
  void didUpdateWidget(_Entries oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position ||
        oldWidget.shadow != widget.shadow ||
        oldWidget.look != widget.look) {
      for (final entry in _entries) {
        entry.markNeedsBuild();
      }
    }
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.remove();
    }
    super.dispose();
  }

  Widget _entry(BuildContext context, int n) {
    final theme = Theme.of(context);
    final box = Panel(
      look: widget.look,
      padding: const EdgeInsets.x(1),
      shadow: widget.shadow,
      child: Text.rich([
        'Entry $n'.bold,
        Span(' of the overlay', theme.muted),
      ]),
    );
    return switch (widget.position) {
      'topLeft' => Positioned(left: 4 * n - 3, top: 2 * n - 1, child: box),
      'bottomLeft' => Positioned(
        left: 4 * n - 3,
        bottom: 7 - 2 * n,
        child: box,
      ),
      _ => Positioned(right: 4 * n - 3, top: 2 * n - 1, child: box),
    };
  }

  void _insert({bool keep = true}) {
    final n = _entries.length + 1;
    final entry = OverlayEntry(builder: (context) => _entry(context, n));
    Overlay.of(context).insert(entry);
    setState(() => _entries.add(entry));
    if (keep) {
      _kept['entries'] = _entries.length;
    }
  }

  void _remove() {
    setState(() => _entries.removeLast().remove());
    _kept['entries'] = _entries.length;
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        gap: 2,
        children: [
          Button(
            'Insert an entry',
            onPressed: _entries.length < 3 ? _insert : null,
          ),
          Button('Remove one', onPressed: _entries.isEmpty ? null : _remove),
        ],
      ),
      Text.rich([
        Span('entries: ', Theme.of(context).muted),
        Span('${_entries.length}'),
        Span(' of the overlay', Theme.of(context).muted),
      ]),
    ],
  );
}
