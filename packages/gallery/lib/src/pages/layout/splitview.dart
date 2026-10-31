// The SplitView page.
part of 'layout.dart';

// ------------------------------------------------------------ SplitView

const _panes = [
  ('files', 'box.dart\nflex.dart\ngrid.dart\nwrap.dart'),
  ('editor', 'Drag a divider, or Tab to one and press the arrows.'),
  ('outline', 'Drag its divider to the edge.'),
];

// room for three panes of three rows and the two dividers between them,
// edges shared or not
const _spw = 48;

const _sph = 11;

final _splitView = GalleryPage(
  group: 'Layout',
  title: 'SplitView',
  options: const [
    ChoiceOption('dir', 'direction', values: ['horizontal', 'vertical']),
    SwitchOption('share', 'share edges', initial: true),
    ChoiceOption(
      'type',
      'dividers',
      values: ['single', 'rounded', 'double', 'heavy', 'ascii'],
    ),
  ],
  build: (context, o) => _Split(
    vertical: o['dir'] == 'vertical',
    share: o.flag('share'),
    type: BorderType.values.byName(o.choice('type')),
  ),
  code: (o) {
    final min = o['dir'] == 'horizontal' ? 8 : 3;
    List<String> pane((String, String) p, {required bool last}) => [
      '              SplitPane(',
      '                minSize: $min,',
      if (last) '                collapsible: true,',
      ..._call(16, 'child: pane', [
        "'${p.$1}'",
        "'${p.$2.replaceAll('\n', r'\n')}'",
      ], ','),
      '              ),',
    ];
    final share = o.flag('share');
    return [
      'final _split = SplitController(fractions: [1, 2, 1]);',
      '',
      '@override',
      'void dispose() {',
      '  _split.dispose();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  Widget pane(String title, String text) => Box(',
      codeLine([
        '    border: .all(type: .rounded, style: theme.border',
        "${share ? ', merge: true' : ''}),",
      ]),
      '    // no blanks around the title: a divider over the edge would',
      '    // draw its line in them',
      '    titles: [BorderTitle(title, style: theme.muted)],',
      '    padding: const .only(left: 1),',
      '    child: Text(text),',
      '  );',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      // as tall as the room leaves it, at most $_sph',
      '      Flexible(',
      '        child: SizedBox(',
      '          width: $_spw,',
      '          height: $_sph,',
      '          child: SplitView(',
      '            controller: _split,',
      if (o['dir'] != 'horizontal') '            direction: .vertical,',
      if (share) '            shareEdges: true,',
      if (o['type'] != 'single') '            type: .${o['type']},',
      '            style: theme.border,',
      '            panes: [',
      for (final (i, p) in _panes.indexed)
        ...pane(p, last: i == _panes.length - 1),
      '            ],',
      '          ),',
      '        ),',
      '      ),',
      '      ListenableBuilder(',
      '        listenable: _split,',
      '        builder: (context, _) {',
      codeLine([
        '          final fractions = ',
        '_split.fractions.map((f) => f.toStringAsFixed(2));',
      ]),
      '          final collapsed = _split.collapsed;',
      '          return Text.rich([',
      "            Span('fractions: ', theme.muted),",
      "            Span(fractions.join('  ')),",
      '            if (collapsed.isNotEmpty) ...[',
      "              Span('  collapsed: ', theme.muted),",
      r"              Span('$collapsed'),",
      '            ],',
      '          ]);',
      '        },',
      '      ),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

/// The SplitView page's widget: its controller kept in the page's state,
/// so that the panes keep their sizes over a visit to another page.
final class _Split extends StatelessWidget {
  const _Split({
    required this.vertical,
    required this.share,
    required this.type,
  });

  final bool vertical;
  final bool share;
  final BorderType type;

  @override
  Widget build(BuildContext context) {
    final split = keptAt(
      context,
      'split',
      () => SplitController(fractions: [1, 2, 1]),
    );
    final theme = Theme.of(context);
    Widget pane(String title, String text) => Box(
      border: _rounded(theme, merge: share),
      // no blanks around the title: a divider over the edge would draw its
      // line in them
      titles: [BorderTitle(title, style: theme.muted)],
      padding: const EdgeInsets.only(left: 1),
      child: Text(text),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        // as tall as the room leaves it, at most 11
        Flexible(
          child: SizedBox(
            width: _spw,
            height: _sph,
            child: SplitView(
              controller: split,
              direction: vertical ? Axis.vertical : Axis.horizontal,
              shareEdges: share,
              type: type,
              style: theme.border,
              panes: [
                for (final (i, (title, text)) in _panes.indexed)
                  SplitPane(
                    minSize: vertical ? 3 : 8,
                    collapsible: i == _panes.length - 1,
                    child: pane(title, text),
                  ),
              ],
            ),
          ),
        ),
        ListenableBuilder(
          listenable: split,
          builder: (context, _) {
            final fractions = split.fractions.map(
              (f) => f.toStringAsFixed(2),
            );
            final collapsed = split.collapsed;
            return Text.rich([
              Span('fractions: ', theme.muted),
              Span(fractions.join('  ')),
              if (collapsed.isNotEmpty) ...[
                Span('  collapsed: ', theme.muted),
                Span('$collapsed'),
              ],
            ]);
          },
        ),
      ],
    );
  }
}
