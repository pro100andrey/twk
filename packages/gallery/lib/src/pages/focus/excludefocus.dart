// The ExcludeFocus page.
part of 'focus.dart';

/// The ExcludeFocus page's `excluding` option.
const _excludefocusExcluding = SwitchOption(
  'excluding',
  'excluding',
  initial: true,
);

final _excludefocusPage = GalleryPage(
  group: _group,
  title: 'ExcludeFocus',
  options: const [_excludefocusExcluding],
  build: (context, o) => _Excluded(excluding: o(_excludefocusExcluding)),
  code: _excludedCode,
);

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
                Span(focused.first, theme.primary.merge(bold)),
            ]);
          },
        ),
      ],
    );
  }
}

String _excludedCode(Options o) {
  final out = o(_excludefocusExcluding);
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
