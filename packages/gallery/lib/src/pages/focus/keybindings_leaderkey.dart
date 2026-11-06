// The KeyBindings, LeaderKey page.
part of 'focus.dart';

/// The KeyBindings, LeaderKey page's `leader` option.
const _keybindingsLeaderkeyLeader = ChoiceOption<String>(
  'leader',
  'leader',
  values: [',', 'space', r'\'],
);

/// The KeyBindings, LeaderKey page's `timeout` option.
const _keybindingsLeaderkeyTimeout = ChoiceOption<int?>(
  'timeout',
  'sequence timeout',
  values: [1000, null],
  labels: ['1 s', 'none'],
);

/// The KeyBindings, LeaderKey page's `unmatched` option.
const _keybindingsLeaderkeyUnmatched = ChoiceOption<String>(
  'unmatched',
  'unmatched keys',
  values: ['drop', 'replay'],
);

final _keybindingsLeaderkeyPage = GalleryPage(
  group: _group,
  title: 'KeyBindings, LeaderKey',
  options: const [
    _keybindingsLeaderkeyLeader,
    _keybindingsLeaderkeyTimeout,
    _keybindingsLeaderkeyUnmatched,
  ],
  build: (context, o) {
    final timeout = o(_keybindingsLeaderkeyTimeout);
    return _Bindings(
      leader: o(_keybindingsLeaderkeyLeader),
      timeout: timeout == null ? null : Duration(milliseconds: timeout),
      unmatched: UnmatchedKeys.values.byName(o(_keybindingsLeaderkeyUnmatched)),
    );
  },
  code: _bindingsCode,
);

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
  final leader = o(_keybindingsLeaderkeyLeader);
  final lead = leader == 'space' ? null : leader;
  final leaderName = lead == r'\' ? r"r'\'" : "'$lead'";
  final args = [
    if (o(_keybindingsLeaderkeyTimeout) == null) '  sequenceTimeout: null,',
    if (o(_keybindingsLeaderkeyUnmatched) == 'replay') '  unmatched: .replay,',
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
    '    spacing: 1,',
    '    children: [',
    '      Row(',
    '        mainAxisSize: .min,',
    '        spacing: 2,',
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
