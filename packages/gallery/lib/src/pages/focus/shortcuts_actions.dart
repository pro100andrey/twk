// The Shortcuts, Actions page.
part of 'focus.dart';

/// The Shortcuts, Actions page's `actions` option.
const _shortcutsActionsActions = SwitchOption(
  'actions',
  'actions enabled',
  initial: true,
);

final _shortcutsActionsPage = GalleryPage(
  group: _group,
  title: 'Shortcuts, Actions',
  options: const [_shortcutsActionsActions],
  build: (context, o) => _Intents(enabled: o(_shortcutsActionsActions)),
  code: _intentsCode,
);

const _upPassed =
    "      'up': () => _passed('↑ _Up → passed on to the KeyBindings'),";

const _downPassed =
    "      'down': () => _passed('↓ _Down → passed on to the KeyBindings'),";

const _upInvoke =
    "          onInvoke: (_) => _step(1, '↑ _Up → its action stepped up'),";

const _downInvoke =
    "          onInvoke: (_) => _step(-1, '↓ _Down → its action stepped "
    "down'),";

const _didLine =
    "              if (_did.isEmpty) Span('nothing', theme.muted) else "
    'Span(_did),';

/// Steps up a count.
final class _Up extends Intent {
  const _Up();
}

/// Steps down a count.
final class _Down extends Intent {
  const _Down();
}

/// A count that Up and Down step through Shortcuts and Actions, passed on
/// to KeyBindings while the actions are not [enabled].
final class _Intents extends StatefulWidget {
  const _Intents({required this.enabled});

  final bool enabled;

  @override
  State<_Intents> createState() => _IntentsState();
}

final class _IntentsState extends State<_Intents> {
  final _node = FocusNode(debugLabel: 'focus me');
  var _count = 0;
  var _did = '';
  var _dids = 0;

  void _step(int n, String did) => setState(() {
    _count += n;
    _did = did;
    _dids++;
  });

  void _passed(String did) => setState(() {
    _did = did;
    _dids++;
  });

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'up': () => _passed('↑ _Up → passed on to the KeyBindings'),
      'down': () => _passed('↓ _Down → passed on to the KeyBindings'),
    },
    hints: const {'up': 'passed on', 'down': 'passed on'},
    child: Actions(
      {
        _Up: CallbackAction<_Up>(
          enabled: widget.enabled,
          onInvoke: (_) => _step(1, '↑ _Up → its action stepped up'),
        ),
        _Down: CallbackAction<_Down>(
          enabled: widget.enabled,
          onInvoke: (_) => _step(-1, '↓ _Down → its action stepped down'),
        ),
      },
      child: Shortcuts(
        const {'up': _Up(), 'down': _Down()},
        hints: const {'up': 'step up', 'down': 'step down'},
        child: _withBar(
          _counter(_node, _count, _count),
          KeyHintsBar(
            keyLabel: (key) => switch ('$key') {
              'up' => '↑',
              'down' => '↓',
              final name => name,
            },
          ),
          LitLine([
            ('did: ', true),
            if (_did.isEmpty) ('nothing', true) else (_did, false),
          ], serial: _dids),
        ),
      ),
    ),
  );
}

String _intentsCode(Options o) {
  final disabled = !o(_shortcutsActionsActions);
  return [
    '/// Steps up a count.',
    'final class _Up extends Intent {',
    '  const _Up();',
    '}',
    '',
    '/// Steps down a count.',
    'final class _Down extends Intent {',
    '  const _Down();',
    '}',
    '',
    "final _node = FocusNode(debugLabel: 'focus me');",
    'var _count = 0;',
    "var _did = '';",
    '',
    'void _step(int n, String did) => setState(() {',
    '  _count += n;',
    '  _did = did;',
    '});',
    '',
    'void _passed(String did) => setState(() => _did = did);',
    '',
    '@override',
    'void dispose() {',
    '  _node.dispose();',
    '  super.dispose();',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  // the keys no enabled action takes come here',
    '  return KeyBindings(',
    '    {',
    _upPassed,
    _downPassed,
    '    },',
    "    hints: const {'up': 'passed on', 'down': 'passed on'},",
    '    child: Actions(',
    '      {',
    '        _Up: CallbackAction<_Up>(',
    if (disabled) '          enabled: false,',
    _upInvoke,
    '        ),',
    '        _Down: CallbackAction<_Down>(',
    if (disabled) '          enabled: false,',
    _downInvoke,
    '        ),',
    '      },',
    '      child: Shortcuts(',
    "        const {'up': _Up(), 'down': _Down()},",
    "        hints: const {'up': 'step up', 'down': 'step down'},",
    '        child: Column(',
    '          mainAxisSize: .min,',
    '          crossAxisAlignment: .start,',
    '          gap: 1,',
    '          children: [',
    '            Row(',
    '              mainAxisSize: .min,',
    '              gap: 2,',
    '              children: [',
    '                _Focusable(_node),',
    '                $_countLine',
    '              ],',
    '            ),',
    '            KeyHintsBar(',
    r"              keyLabel: (key) => switch ('$key') {",
    "                'up' => '↑',",
    "                'down' => '↓',",
    '                final name => name,',
    '              },',
    '            ),',
    '            Text.rich([',
    "              Span('did: ', theme.muted),",
    _didLine,
    '            ]),',
    '          ],',
    '        ),',
    '      ),',
    '    ),',
    '  );',
    '}',
    '',
    ..._focusableCode(args: false),
    '',
    _boldCode,
  ].join('\n');
}
