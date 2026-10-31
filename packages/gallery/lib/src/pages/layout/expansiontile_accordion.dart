// The ExpansionTile, Accordion page.
part of 'layout.dart';

/// The sections: a title, a subtitle, and what each holds as the Code
/// writes it, but the last, which holds a checkbox.
const _sections = [
  ('General', 'Name and theme', r'Name: twk\nTheme: dark'),
  ('Network', 'Proxy and timeouts', r'Proxy: none\nTimeout: 30 s'),
  ('Security', 'TLS and certificates', ''),
];

const _sectionsW = 40;

final _expansion = GalleryPage(
  group: 'Layout',
  title: 'ExpansionTile, Accordion',
  options: [
    const SwitchOption('accordion', 'in an accordion', initial: true),
    SwitchOption(
      'multiple',
      'several open',
      disabled: (o) => !o.flag('accordion'),
    ),
    const SwitchOption('subtitle', 'subtitles', initial: true),
    const ChoiceOption(
      'duration',
      'duration',
      values: [150, 400, 0],
      labels: ['150 ms', '400 ms', 'none'],
    ),
  ],
  build: (context, o) => _Sections(
    accordion: o.flag('accordion'),
    multiple: o.flag('multiple'),
    subtitle: o.flag('subtitle'),
    duration: Duration(milliseconds: o.choice<int>('duration')),
  ),
  code: (o) {
    final accordion = o.flag('accordion');
    final subtitle = o.flag('subtitle');
    final ms = o.choice<int>('duration');
    final [general, network, security] = [
      for (final (title, sub, _) in _sections)
        ["'$title'", if (subtitle) "'$sub'"].join(', '),
    ];
    return [
      'var _verify = true;',
      "var _did = '';",
      '',
      '/// A section of [title] that holds [child], and says when it opens or',
      '/// closes.',
      'ExpansionTile _section(',
      '  String title,',
      if (subtitle) '  String subtitle,',
      '  Widget child, {',
      '  bool open = false,',
      '}) => ExpansionTile(',
      '  title: Text(title),',
      if (subtitle) '  subtitle: Text(subtitle),',
      '  initiallyExpanded: open,',
      if (ms == 0)
        '  duration: Duration.zero,'
      else if (ms != 150)
        '  duration: const Duration(milliseconds: $ms),',
      '  onExpansionChanged: (expanded) => setState(',
      r"    () => _did = '${expanded ? 'opened' : 'closed'} $title',",
      '  ),',
      '  child: child,',
      ');',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  final sections = [',
      '    _section(',
      '      $general,',
      "      const Text('${_sections[0].$3}'),",
      '      open: true,',
      '    ),',
      "    _section($network, const Text('${_sections[1].$3}')),",
      '    _section(',
      '      $security,',
      '      Column(',
      '        mainAxisSize: .min,',
      '        crossAxisAlignment: .start,',
      '        children: [',
      "          const Text('TLS: 1.3'),",
      '          Checkbox(',
      '            value: _verify,',
      "            label: 'verify certificates',",
      '            onChanged: (value) => setState(() => _verify = value),',
      '          ),',
      '        ],',
      '      ),',
      '    ),',
      '  ];',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      SizedBox(',
      '        width: $_sectionsW,',
      if (!accordion) ...[
        '        child: Column(',
        '          mainAxisSize: .min,',
        '          crossAxisAlignment: .start,',
        '          children: sections,',
        '        ),',
      ] else if (o.flag('multiple'))
        '        child: Accordion(allowMultiple: true, children: sections),'
      else
        '        child: Accordion(children: sections),',
      '      ),',
      '      Text.rich([',
      "        Span('did: ', theme.muted),",
      '        if (_did.isEmpty)',
      "          Span('nothing', theme.muted)",
      '        else',
      '          Span(_did),',
      '      ]),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

/// Three sections of settings, in an accordion or apart, and what was
/// done to them last.
final class _Sections extends StatefulWidget {
  const _Sections({
    required this.accordion,
    required this.multiple,
    required this.subtitle,
    required this.duration,
  });

  final bool accordion;
  final bool multiple;
  final bool subtitle;
  final Duration duration;

  @override
  State<_Sections> createState() => _SectionsState();
}

final class _SectionsState extends State<_Sections> with KeptState {
  bool get _verify => kept['verify'] as bool? ?? true;
  String get _did => kept['did'] as String? ?? '';
  int get _serial => kept['serial'] as int? ?? 0;

  ExpansionTile _section(
    String title,
    String subtitle,
    Widget child, {
    bool open = false,
  }) => ExpansionTile(
    title: Text(title),
    subtitle: widget.subtitle ? Text(subtitle) : null,
    initiallyExpanded: open,
    duration: widget.duration,
    onExpansionChanged: (expanded) => setState(() {
      kept['did'] = '${expanded ? 'opened' : 'closed'} $title';
      kept['serial'] = _serial + 1;
    }),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final [(g, gs, _), (n, ns, _), (s, ss, _)] = _sections;
    final sections = [
      _section(g, gs, const Text('Name: twk\nTheme: dark'), open: true),
      _section(n, ns, const Text('Proxy: none\nTimeout: 30 s')),
      _section(
        s,
        ss,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TLS: 1.3'),
            Checkbox(
              value: _verify,
              label: 'verify certificates',
              onChanged: (value) => setState(() => kept['verify'] = value),
            ),
          ],
        ),
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        SizedBox(
          width: _sectionsW,
          child: widget.accordion
              ? Accordion(allowMultiple: widget.multiple, children: sections)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: sections,
                ),
        ),
        LitLine([
          ('did: ', true),
          if (_did.isEmpty) ('nothing', true) else (_did, false),
        ], serial: _serial),
      ],
    );
  }
}
