// The KeyHintsBar page.
part of 'controls.dart';

/// The KeyHintsBar page's `unhinted` option.
const _keyhintsbarUnhinted = SwitchOption(
  'unhinted',
  'unhinted keys',
);

/// The KeyHintsBar page's `join` option.
const _keyhintsbarJoin = SwitchOption(
  'join',
  'join keys',
  initial: true,
);

/// The KeyHintsBar page's `keys` option.
const _keyhintsbarKeys = ChoiceOption<String>(
  'keys',
  'keys named by',
  values: ['signs', 'names'],
);

/// The KeyHintsBar page's `separator` option.
const _keyhintsbarSeparator = ChoiceOption<String>(
  'separator',
  'separator',
  values: _separators,
  labels: ['blanks', 'dot', 'line'],
);

final _keyhintsbarPage = GalleryPage(
  group: _group,
  title: 'KeyHintsBar',
  options: const [
    _keyhintsbarUnhinted,
    _keyhintsbarJoin,
    _keyhintsbarKeys,
    _keyhintsbarSeparator,
  ],
  build: (context, o) => _Hinted(
    unhinted: o(_keyhintsbarUnhinted),
    joinKeys: o(_keyhintsbarJoin),
    names: o(_keyhintsbarKeys) == 'names',
    separator: o(_keyhintsbarSeparator),
  ),
  code: (o) => [
    'String? _did;',
    'var _autosave = false;',
    '',
    if (o(_keyhintsbarKeys) == 'names') ...[
      '// a key by its name, as KeyCombo writes it: left, escape',
      r"static String _named(KeyCombo combo) => '$combo';",
      '',
    ],
    'void _do(String what) => setState(() => _did = what);',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return KeyBindings(',
    '    {',
    "      'ctrl+s': () => _do('save'),",
    "      'ctrl+x ctrl+o': () => _do('open'),",
    "      'f2': () => _do('rename'),",
    '    },',
    "    hints: const {'ctrl+s': 'save', 'ctrl+x ctrl+o': 'open'},",
    '    child: SizedBox(',
    '      width: 44,',
    '      child: Column(',
    '        mainAxisSize: .min,',
    '        crossAxisAlignment: .stretch,',
    '        gap: 1,',
    '        children: [',
    '          Row(',
    '            gap: 2,',
    '            children: [',
    '              // a field without a box shows the focus on the selection',
    '              Expanded(',
    '                child: TextField(',
    "                  placeholder: 'a field',",
    '                  focusedStyle: theme.selection,',
    '                ),',
    '              ),',
    '              Checkbox(',
    '                value: _autosave,',
    "                label: 'autosave',",
    '                onChanged: (on) => setState(() => _autosave = on),',
    '              ),',
    '            ],',
    '          ),',
    '          Text.rich([',
    "            Span('did: ', theme.muted),",
    '            if (_did case final did?)',
    '              Span(did)',
    '            else',
    "              Span('nothing', theme.muted),",
    '          ]),',
    '          Box(',
    '            border: .all(type: .rounded, style: theme.border),',
    '            padding: const .x(1),',
    ...call(12, 'child: const KeyHintsBar', [
      if (o(_keyhintsbarUnhinted)) 'showUnhinted: true',
      if (o(_keyhintsbarKeys) == 'names') 'keyLabel: _named',
      if (!o(_keyhintsbarJoin)) 'joinKeys: false',
      if (o(_keyhintsbarSeparator) != _separators.first)
        "separator: '${o(_keyhintsbarSeparator)}'",
    ], ','),
    '          ),',
    '        ],',
    '      ),',
    '    ),',
    '  );',
    '}',
  ].join('\n'),
);

/// A field and a checkbox under keys of their own, and the bar of the keys
/// that can be pressed now.
final class _Hinted extends StatefulWidget {
  const _Hinted({
    required this.unhinted,
    required this.joinKeys,
    required this.names,
    required this.separator,
  });

  final bool unhinted;
  final bool joinKeys;

  /// Whether the bar names the keys as [KeyCombo.toString] does, not by
  /// their signs.
  final bool names;
  final String separator;

  @override
  State<_Hinted> createState() => _HintedState();
}

final class _HintedState extends State<_Hinted> with KeptState {
  void _do(String what) => keep('did', what);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final did = keptOr<String?>('did', null);
    return KeyBindings(
      {
        'ctrl+s': () => _do('save'),
        'ctrl+x ctrl+o': () => _do('open'),
        'f2': () => _do('rename'),
      },
      hints: const {'ctrl+s': 'save', 'ctrl+x ctrl+o': 'open'},
      child: SizedBox(
        width: 44,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          gap: 1,
          children: [
            Row(
              gap: 2,
              children: [
                // a field without a box shows the focus on the selection
                Expanded(
                  child: TextField(
                    placeholder: 'a field',
                    focusedStyle: theme.selection,
                  ),
                ),
                Checkbox(
                  value: keptOr('autosave', false),
                  label: 'autosave',
                  onChanged: (on) => keep('autosave', on),
                ),
              ],
            ),
            LitLine([
              ('did: ', true),
              if (did == null) ('nothing', true) else (did, false),
            ], serial: serial),
            Box(
              border: Border.all(type: BorderType.rounded, style: theme.border),
              padding: const EdgeInsets.x(1),
              child: KeyHintsBar(
                showUnhinted: widget.unhinted,
                keyLabel: widget.names ? _named : null,
                joinKeys: widget.joinKeys,
                separator: widget.separator,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the KeyHintsBar page offers between two keys.
const _separators = ['   ', ' · ', ' │ '];

/// [combo] by its name, as [KeyCombo.toString] writes it.
String _named(KeyCombo combo) => '$combo';
