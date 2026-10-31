// The KeyHintsBar page.
part of 'controls.dart';

final _keyhintsbarPage = GalleryPage(
  group: 'Controls',
  title: 'KeyHintsBar',
  options: const [
    SwitchOption('unhinted', 'unhinted keys'),
    SwitchOption('join', 'join keys', initial: true),
    ChoiceOption('keys', 'keys named by', values: ['signs', 'names']),
    ChoiceOption(
      'separator',
      'separator',
      values: _separators,
      labels: ['blanks', 'dot', 'line'],
    ),
  ],
  build: (context, o) => _Hinted(
    unhinted: o.flag('unhinted'),
    joinKeys: o.flag('join'),
    names: o.choice<String>('keys') == 'names',
    separator: o.choice('separator'),
  ),
  code: (o) => [
    'String? _did;',
    'var _autosave = false;',
    '',
    if (o.choice<String>('keys') == 'names') ...[
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
      if (o.flag('unhinted')) 'showUnhinted: true',
      if (o.choice<String>('keys') == 'names') 'keyLabel: _named',
      if (!o.flag('join')) 'joinKeys: false',
      if (o.choice<String>('separator') != _separators.first)
        "separator: '${o.choice<String>('separator')}'",
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
