// The Pressable page.
part of 'controls.dart';

final _pressablePage = GalleryPage(
  group: _group,
  title: 'Pressable',
  options: const [
    pageColorOption,
  ],
  build: (context, o) => _Stars(color: o(pageColorOption)),
  code: (o) => [
    "final _starred = {'twk'};",
    '',
    'void _toggle(String name) => setState(() {',
    '  if (!_starred.remove(name)) {',
    '    _starred.add(name);',
    '  }',
    '});',
    '',
    '// A row that stars [name], made of a Pressable: Tab',
    '// stops at it unless it is disabled, its bindings',
    '// are the keys it takes while it has the focus, a',
    '// press focuses it and a tap calls onTap; it',
    '// builds its look by whether it has the focus.',
    'Widget _star(String name, {bool enabled = true}) => Pressable(',
    '  enabled: enabled,',
    "  bindings: {'space': () => _toggle(name)},",
    "  hints: const {'space': 'star'},",
    '  onTap: enabled ? (_) => _toggle(name) : null,',
    '  builder: (context, focused) {',
    '    final theme = Theme.of(context);',
    '    final on = _starred.contains(name);',
    '    return Text.rich(',
    '      [',
    '        Span(',
    "          on ? '★' : '☆',",
    '          on ? ${_markOf(o)} : theme.muted,',
    '        ),',
    r"        Span(' $name'),",
    '      ],',
    '      style: !enabled',
    '          ? theme.muted',
    '          : focused',
    '          ? theme.selection',
    '          : const .new(),',
    '    );',
    '  },',
    ');',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    '      Column(',
    '        mainAxisSize: .min,',
    '        crossAxisAlignment: .start,',
    '        children: [',
    "          _star('twk'),",
    "          _star('gallery'),",
    "          _star('archive', enabled: false),",
    '        ],',
    '      ),',
    '      Text.rich([',
    "        Span('starred: ', theme.muted),",
    '        if (_starred.isEmpty)',
    "          Span('nothing', theme.muted)",
    '        else',
    "          Span(_starred.join(', ')),",
    '      ]),',
    '    ],',
    '  );',
    '}',
  ].join('\n'),
);

/// The style of a star that is on, as the Pressable page's Code writes it.
String _markOf(Options o) =>
    'theme.${o(pageColorOption)}.merge(const .new(attrs: Attr.bold))';

/// The rows of the Pressable page, each a Pressable that stars a name,
/// and the line that says which are starred.
final class _Stars extends StatefulWidget {
  const _Stars({required this.color});

  final String color;

  @override
  State<_Stars> createState() => _StarsState();
}

final class _StarsState extends State<_Stars> with KeptState {
  // kept in the page's state while the gallery runs, in the order starred
  List<String> get _starred =>
      (kept['starred'] as List<String>?) ?? const ['twk'];
  int get _serial => kept['serial'] as int? ?? 0;

  void _toggle(String name) => setState(() {
    final starred = _starred;
    kept['starred'] = starred.contains(name)
        ? [
            for (final n in starred)
              if (n != name) n,
          ]
        : [...starred, name];
    kept['serial'] = _serial + 1;
  });

  Widget _star(String name, {bool enabled = true}) => Pressable(
    enabled: enabled,
    bindings: {'space': () => _toggle(name)},
    hints: const {'space': 'star'},
    onTap: enabled ? (_) => _toggle(name) : null,
    builder: (context, focused) {
      final theme = Theme.of(context);
      final on = _starred.contains(name);
      final mark = themeColor(
        theme,
        widget.color,
      ).merge(const Style(attrs: Attr.bold));
      return Text.rich(
        [
          Span(on ? '★' : '☆', on ? mark : theme.muted),
          Span(' $name'),
        ],
        style: !enabled
            ? theme.muted
            : focused
            ? theme.selection
            : const Style(),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final starred = _starred;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _star('twk'),
            _star('gallery'),
            _star('archive', enabled: false),
          ],
        ),
        LitLine([
          ('starred: ', true),
          if (starred.isEmpty)
            ('nothing', true)
          else
            (starred.join(', '), false),
        ], serial: _serial),
      ],
    );
  }
}
