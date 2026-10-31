// The Focus, FocusScope page.
part of 'focus.dart';

final _focusFocusscopePage = GalleryPage(
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
);

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
                Span(focused.first, theme.primary.merge(bold)),
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
