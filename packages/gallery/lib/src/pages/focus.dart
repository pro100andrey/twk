// The Focus and keys group of the gallery.
import 'package:twk/twk.dart';

import '../page.dart';
import 'common.dart';

const _bold = Style(attrs: Attr.bold);

/// The Code's lines too long for a line of Dart.
const _focusableArgs =
    '  const _Focusable(this.node, {this.skipTraversal, '
    'this.canRequestFocus});';
const _countLine =
    "Text.rich([Span('count: ', theme.muted), "
    r"Span('$_count')]),";
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

/// The pages of the Focus and keys group that draw.
final focusPages = [
  GalleryPage(
    group: 'Focus and keys',
    title: 'Focus, FocusScope',
    about:
        'Nodes the keys go to: Tab moves the focus from one to the next, a '
        'click takes it; in a scope Tab goes round its nodes, and Tab into '
        'it focuses the one it had last.',
    options: const [
      SwitchOption('scope', 'FocusScope', initial: true),
      ChoiceOption(
        'two',
        'node two',
        values: ['focusable', 'skips Tab', 'unfocusable'],
      ),
    ],
    build: (context, o) =>
        _Nodes(scope: o.flag('scope'), two: o.choice<String>('two')),
    code: _nodesCode,
  ),
  GalleryPage(
    group: 'Focus and keys',
    title: 'ExcludeFocus',
    options: const [SwitchOption('excluding', 'excluding', initial: true)],
    build: (context, o) => _Excluded(excluding: o.flag('excluding')),
    code: _excludedCode,
  ),
  GalleryPage(
    group: 'Focus and keys',
    title: 'KeyBindings, LeaderKey',
    options: const [
      ChoiceOption('leader', 'leader', values: [',', 'space', r'\']),
      ChoiceOption(
        'timeout',
        'sequence timeout',
        values: [1000, null],
        labels: ['1 s', 'none'],
      ),
      ChoiceOption('unmatched', 'unmatched keys', values: ['drop', 'replay']),
    ],
    build: (context, o) {
      final timeout = o.choice<int?>('timeout');
      return _Bindings(
        leader: o.choice('leader'),
        timeout: timeout == null ? null : Duration(milliseconds: timeout),
        unmatched: UnmatchedKeys.values.byName(o.choice('unmatched')),
      );
    },
    code: _bindingsCode,
  ),
  GalleryPage(
    group: 'Focus and keys',
    title: 'Shortcuts, Actions',
    options: const [SwitchOption('actions', 'actions enabled', initial: true)],
    build: (context, o) => _Intents(enabled: o.flag('actions')),
    code: _intentsCode,
  ),
];

/// [node] in a box that takes the focus, by Tab or a click.
final class _Focusable extends StatelessWidget {
  const _Focusable(
    this.node, {
    this.skipTraversal,
    this.canRequestFocus,
    this.muted = false,
  });

  final FocusNode node;
  final bool? skipTraversal;
  final bool? canRequestFocus;

  /// Whether its label is muted, where something else keeps the focus from
  /// it (ExcludeFocus).
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: (_) => node.requestFocus(),
      child: Focus(
        focusNode: node,
        skipTraversal: skipTraversal,
        canRequestFocus: canRequestFocus,
        child: ListenableBuilder(
          listenable: node,
          builder: (context, _) => Box(
            border: Border.all(
              type: node.hasFocus ? BorderType.heavy : BorderType.rounded,
              style: node.hasFocus ? theme.primary : theme.border,
            ),
            padding: const EdgeInsets.x(1),
            child: Text(
              node.debugLabel!,
              style: canRequestFocus == false || muted
                  ? theme.muted
                  : (node.hasFocus ? _bold : const Style()),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Dart of `_Focusable`, with its [args] or not.
List<String> _focusableCode({required bool args}) => [
  '/// [node] in a box that takes the focus, by Tab or a click.',
  'final class _Focusable extends StatelessWidget {',
  if (args) ...[
    _focusableArgs,
    '',
    '  final FocusNode node;',
    '  final bool? skipTraversal;',
    '  final bool? canRequestFocus;',
  ] else ...[
    '  const _Focusable(this.node);',
    '',
    '  final FocusNode node;',
  ],
  '',
  '  @override',
  '  Widget build(BuildContext context) {',
  '    final theme = Theme.of(context);',
  '    return GestureDetector(',
  '      onTap: (_) => node.requestFocus(),',
  '      child: Focus(',
  '        focusNode: node,',
  if (args) ...[
    '        skipTraversal: skipTraversal,',
    '        canRequestFocus: canRequestFocus,',
  ],
  '        child: ListenableBuilder(',
  '          listenable: node,',
  '          builder: (context, _) => Box(',
  '            border: .all(',
  '              type: node.hasFocus ? .heavy : .rounded,',
  '              style: node.hasFocus ? theme.primary : theme.border,',
  '            ),',
  '            padding: const .x(1),',
  '            child: Text(',
  '              node.debugLabel!,',
  if (args) ...[
    '              style: canRequestFocus == false',
    '                  ? theme.muted',
    '                  : (node.hasFocus ? bold : const Style()),',
  ] else
    '              style: node.hasFocus ? bold : const Style(),',
  '            ),',
  '          ),',
  '        ),',
  '      ),',
  '    );',
  '  }',
  '}',
];

const _boldCode = 'const bold = Style(attrs: Attr.bold);';

// -------------------------------------------------------- Focus, FocusScope

/// Four nodes, the last two in a [scope] where it is on; node two
/// focusable, skipped by Tab or unfocusable, as [two] says.
final class _Nodes extends StatefulWidget {
  const _Nodes({required this.scope, required this.two});

  final bool scope;
  final String two;

  @override
  State<_Nodes> createState() => _NodesState();
}

final class _NodesState extends State<_Nodes> {
  final List<FocusNode> _nodes = [
    for (final label in ['one', 'two', 'three', 'four'])
      FocusNode(debugLabel: label),
  ];
  final _scope = FocusScopeNode(debugLabel: 'scope');

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final [one, two, three, four] = _nodes;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          gap: 1,
          children: [
            _Focusable(one),
            switch (widget.two) {
              'skips Tab' => _Focusable(two, skipTraversal: true),
              'unfocusable' => _Focusable(two, canRequestFocus: false),
              _ => _Focusable(two),
            },
            if (widget.scope)
              ListenableBuilder(
                listenable: _scope,
                builder: (context, _) {
                  final inside = _scope.hasFocus;
                  return Box(
                    border: Border.all(
                      type: BorderType.rounded,
                      style: inside ? theme.primary : theme.border,
                    ),
                    titles: [
                      BorderTitle(
                        ' FocusScope ',
                        style: inside ? theme.primary : theme.muted,
                      ),
                    ],
                    child: FocusScope(
                      node: _scope,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [_Focusable(three), _Focusable(four)],
                      ),
                    ),
                  );
                },
              )
            else ...[
              _Focusable(three),
              _Focusable(four),
            ],
          ],
        ),
        ListenableBuilder(
          listenable: Listenable.merge(_nodes),
          builder: (context, _) {
            final focused = [
              for (final node in _nodes)
                if (node.hasPrimaryFocus) node.debugLabel!,
            ];
            return Text.rich([
              Span('focus: ', theme.muted),
              if (focused.isEmpty)
                Span('none', theme.muted)
              else
                Span(focused.first, theme.primary.merge(_bold)),
            ]);
          },
        ),
      ],
    );
  }
}

String _nodesCode(Options o) {
  final scope = o.flag('scope');
  final two = switch (o.choice<String>('two')) {
    'skips Tab' => 'skipTraversal: true',
    'unfocusable' => 'canRequestFocus: false',
    _ => null,
  };
  return [
    'final _nodes = [',
    "  for (final label in ['one', 'two', 'three', 'four'])",
    '    FocusNode(debugLabel: label),',
    '];',
    if (scope) "final _scope = FocusScopeNode(debugLabel: 'scope');",
    '',
    '@override',
    'void dispose() {',
    '  for (final node in _nodes) {',
    '    node.dispose();',
    '  }',
    if (scope) '  _scope.dispose();',
    '  super.dispose();',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  final [one, two, three, four] = _nodes;',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    '      Row(',
    '        mainAxisSize: .min,',
    '        gap: 1,',
    '        children: [',
    '          _Focusable(one),',
    if (two == null)
      '          _Focusable(two),'
    else
      '          _Focusable(two, $two),',
    if (scope) ...[
      '          ListenableBuilder(',
      '            listenable: _scope,',
      '            builder: (context, _) {',
      '              final inside = _scope.hasFocus;',
      '              return Box(',
      '                border: .all(',
      '                  type: .rounded,',
      '                  style: inside ? theme.primary : theme.border,',
      '                ),',
      '                titles: [',
      '                  BorderTitle(',
      "                    ' FocusScope ',",
      '                    style: inside ? theme.primary : theme.muted,',
      '                  ),',
      '                ],',
      '                child: FocusScope(',
      '                  node: _scope,',
      '                  child: Row(',
      '                    mainAxisSize: .min,',
      '                    children: [_Focusable(three), _Focusable(four)],',
      '                  ),',
      '                ),',
      '              );',
      '            },',
      '          ),',
    ] else ...[
      '          _Focusable(three),',
      '          _Focusable(four),',
    ],
    '        ],',
    '      ),',
    '      ListenableBuilder(',
    '        listenable: Listenable.merge(_nodes),',
    '        builder: (context, _) {',
    '          final focused = [',
    '            for (final node in _nodes)',
    '              if (node.hasPrimaryFocus) node.debugLabel!,',
    '          ];',
    '          return Text.rich([',
    "            Span('focus: ', theme.muted),",
    '            if (focused.isEmpty)',
    "              Span('none', theme.muted)",
    '            else',
    '              Span(focused.first, theme.primary.merge(bold)),',
    '          ]);',
    '        },',
    '      ),',
    '    ],',
    '  );',
    '}',
    '',
    ..._focusableCode(args: two != null),
    '',
    _boldCode,
  ].join('\n');
}

// -------------------------------------------------------------- ExcludeFocus

/// Four nodes, the middle two under an [ExcludeFocus] that keeps the focus
/// from them while [excluding].
final class _Excluded extends StatefulWidget {
  const _Excluded({required this.excluding});

  final bool excluding;

  @override
  State<_Excluded> createState() => _ExcludedState();
}

final class _ExcludedState extends State<_Excluded> {
  final List<FocusNode> _nodes = [
    for (final label in ['one', 'two', 'three', 'four'])
      FocusNode(debugLabel: label),
  ];

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final [one, two, three, four] = _nodes;
    final excluding = widget.excluding;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          gap: 1,
          children: [
            _Focusable(one),
            ListenableBuilder(
              listenable: Listenable.merge([two, three]),
              builder: (context, _) {
                final inside = two.hasFocus || three.hasFocus;
                return Box(
                  border: Border.all(
                    type: BorderType.rounded,
                    style: inside ? theme.primary : theme.border,
                  ),
                  titles: [
                    BorderTitle(
                      ' ExcludeFocus ',
                      style: inside ? theme.primary : theme.muted,
                    ),
                  ],
                  child: ExcludeFocus(
                    excluding: excluding,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Focusable(two, muted: excluding),
                        _Focusable(three, muted: excluding),
                      ],
                    ),
                  ),
                );
              },
            ),
            _Focusable(four),
          ],
        ),
        ListenableBuilder(
          listenable: Listenable.merge(_nodes),
          builder: (context, _) {
            final focused = [
              for (final node in _nodes)
                if (node.hasPrimaryFocus) node.debugLabel!,
            ];
            return Text.rich([
              Span('focus: ', theme.muted),
              if (focused.isEmpty)
                Span('none', theme.muted)
              else
                Span(focused.first, theme.primary.merge(_bold)),
            ]);
          },
        ),
      ],
    );
  }
}

String _excludedCode(Options o) {
  final out = o.flag('excluding');
  final muted = out ? ', muted: true' : '';
  return [
    'final _nodes = [',
    "  for (final label in ['one', 'two', 'three', 'four'])",
    '    FocusNode(debugLabel: label),',
    '];',
    '',
    '@override',
    'void dispose() {',
    '  for (final node in _nodes) {',
    '    node.dispose();',
    '  }',
    '  super.dispose();',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  final [one, two, three, four] = _nodes;',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    '      Row(',
    '        mainAxisSize: .min,',
    '        gap: 1,',
    '        children: [',
    '          _Focusable(one),',
    '          ListenableBuilder(',
    '            listenable: Listenable.merge([two, three]),',
    '            builder: (context, _) {',
    '              final inside = two.hasFocus || three.hasFocus;',
    '              return Box(',
    '                border: .all(',
    '                  type: .rounded,',
    '                  style: inside ? theme.primary : theme.border,',
    '                ),',
    '                titles: [',
    '                  BorderTitle(',
    "                    ' ExcludeFocus ',",
    '                    style: inside ? theme.primary : theme.muted,',
    '                  ),',
    '                ],',
    '                child: ExcludeFocus(',
    '                  excluding: $out,',
    '                  child: Row(',
    '                    mainAxisSize: .min,',
    '                    children: [',
    '                      _Focusable(two$muted),',
    '                      _Focusable(three$muted),',
    '                    ],',
    '                  ),',
    '                ),',
    '              );',
    '            },',
    '          ),',
    '          _Focusable(four),',
    '        ],',
    '      ),',
    '      ListenableBuilder(',
    '        listenable: Listenable.merge(_nodes),',
    '        builder: (context, _) {',
    '          final focused = [',
    '            for (final node in _nodes)',
    '              if (node.hasPrimaryFocus) node.debugLabel!,',
    '          ];',
    '          return Text.rich([',
    "            Span('focus: ', theme.muted),",
    '            if (focused.isEmpty)',
    "              Span('none', theme.muted)",
    '            else',
    '              Span(focused.first, theme.primary.merge(bold)),',
    '          ]);',
    '        },',
    '      ),',
    '    ],',
    '  );',
    '}',
    '',
    ..._focusableMutedCode,
    '',
    _boldCode,
  ].join('\n');
}

/// The Dart of `_Focusable` as the ExcludeFocus page writes it.
const _focusableMutedCode = [
  '/// [node] in a box that takes the focus, by Tab or a click; its label',
  '/// [muted] while it cannot.',
  'final class _Focusable extends StatelessWidget {',
  '  const _Focusable(this.node, {this.muted = false});',
  '',
  '  final FocusNode node;',
  '  final bool muted;',
  '',
  '  @override',
  '  Widget build(BuildContext context) {',
  '    final theme = Theme.of(context);',
  '    return GestureDetector(',
  '      onTap: (_) => node.requestFocus(),',
  '      child: Focus(',
  '        focusNode: node,',
  '        child: ListenableBuilder(',
  '          listenable: node,',
  '          builder: (context, _) => Box(',
  '            border: .all(',
  '              type: node.hasFocus ? .heavy : .rounded,',
  '              style: node.hasFocus ? theme.primary : theme.border,',
  '            ),',
  '            padding: const .x(1),',
  '            child: Text(',
  '              node.debugLabel!,',
  '              style: muted',
  '                  ? theme.muted',
  '                  : (node.hasFocus ? bold : const Style()),',
  '            ),',
  '          ),',
  '        ),',
  '      ),',
  '    );',
  '  }',
  '}',
];

// ------------------------------------------------------ the pages with keys

/// The box and the count by it, lit a moment when [serial] changes.
Widget _counter(FocusNode node, int count, int serial) => Row(
  mainAxisSize: MainAxisSize.min,
  gap: 2,
  children: [
    _Focusable(node),
    LitLine([('count: ', true), ('$count', false)], serial: serial),
  ],
);

/// [counter], then [bar] while the focus is in [counter], then [did]: a
/// Column, as the Code's. The gallery's own: the bar lists the keys of the
/// focus path, which with the focus outside the page are the shell's (its
/// list's, its options'); the design's bar is empty then.
Widget _withBar(Widget counter, Widget bar, [Widget? did]) => FocusBuilder(
  builder: (context, hasFocus, _) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      counter,
      if (hasFocus) bar else const SizedBox(height: 1),
      ?did,
    ],
  ),
);

// --------------------------------------------------- KeyBindings, LeaderKey

/// A count that keys and sequences step, under a [leader].
final class _Bindings extends StatefulWidget {
  const _Bindings({
    required this.leader,
    required this.timeout,
    required this.unmatched,
  });

  /// The leader key's name: `,`, `space` or `\`.
  final String leader;
  final Duration? timeout;
  final UnmatchedKeys unmatched;

  @override
  State<_Bindings> createState() => _BindingsState();
}

final class _BindingsState extends State<_Bindings> {
  final _node = FocusNode(debugLabel: 'focus me');
  var _count = 0;
  var _changes = 0;

  void _add(int n) => setState(() {
    _count += n;
    _changes++;
  });

  void _reset() => setState(() {
    _count = 0;
    _changes++;
  });

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bindings = KeyBindings(
      {
        '+': () => _add(1),
        '-': () => _add(-1),
        'g g': _reset,
        'leader r': _reset,
      },
      hints: const {
        '+': 'more',
        '-': 'less',
        'g g': 'reset',
        'leader r': 'reset',
      },
      sequenceTimeout: widget.timeout,
      unmatched: widget.unmatched,
      // lit by a key that sets it, to where it was too
      child: _withBar(_counter(_node, _count, _changes), const KeyHintsBar()),
    );
    return widget.leader == 'space'
        ? bindings
        : LeaderKey(widget.leader, child: bindings);
  }
}

String _bindingsCode(Options o) {
  final leader = o.choice<String>('leader');
  final lead = leader == 'space' ? null : leader;
  final leaderName = lead == r'\' ? r"r'\'" : "'$lead'";
  final args = [
    if (o.choice<int?>('timeout') == null) '  sequenceTimeout: null,',
    if (o.choice<String>('unmatched') == 'replay') '  unmatched: .replay,',
  ];
  final bindings = [
    'KeyBindings(',
    '  {',
    "    '+': () => _add(1),",
    "    '-': () => _add(-1),",
    "    'g g': _reset,",
    "    'leader r': _reset,",
    '  },',
    '  hints: const {',
    "    '+': 'more',",
    "    '-': 'less',",
    "    'g g': 'reset',",
    "    'leader r': 'reset',",
    '  },',
    ...args,
    '  child: Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    '      Row(',
    '        mainAxisSize: .min,',
    '        gap: 2,',
    '        children: [',
    '          _Focusable(_node),',
    '          $_countLine',
    '        ],',
    '      ),',
    '      const KeyHintsBar(),',
    '    ],',
    '  ),',
  ];
  final body = lead != null
      ? [
          '  return LeaderKey(',
          '    $leaderName,',
          '    child: ${bindings.first}',
          for (final l in bindings.skip(1)) '    $l',
          '    ),',
          '  );',
        ]
      : [
          '  // no LeaderKey above: the leader is Space',
          '  return ${bindings.first}',
          for (final l in bindings.skip(1)) '  $l',
          '  );',
        ];
  return [
    "final _node = FocusNode(debugLabel: 'focus me');",
    'var _count = 0;',
    '',
    'void _add(int n) => setState(() => _count += n);',
    '',
    'void _reset() => setState(() => _count = 0);',
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
    ...body,
    '}',
    '',
    ..._focusableCode(args: false),
    '',
    _boldCode,
  ].join('\n');
}

// ------------------------------------------------------ Shortcuts, Actions

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
  final disabled = !o.flag('actions');
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
