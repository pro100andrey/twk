// The SegmentedButton page.
part of 'controls.dart';

/// The segments of the SegmentedButton page: a log's records by kind.
const List<Choice<String>> _kinds = [
  Choice('all', 'All'),
  Choice('errors', 'Errors (3)'),
  Choice('warnings', 'Warnings (12)'),
  Choice('info', 'Info', enabled: false),
];

/// What is on at first, one of them or several.
Set<String> _firstShown({required bool multiple}) =>
    multiple ? {'errors', 'warnings'} : {'all'};

final _segmented = GalleryPage(
  group: 'Controls',
  title: 'SegmentedButton',
  options: const [
    SwitchOption('multiple', 'multiple'),
    SwitchOption('empty', 'allow none'),
    SwitchOption('icon', 'selected icon'),
    ChoiceOption('caps', 'caps', values: ['square', 'round']),
  ],
  build: (context, o) => _Segments(
    key: ValueKey(o.flag('multiple')),
    multiple: o.flag('multiple'),
    empty: o.flag('empty'),
    icon: o.flag('icon'),
    round: o.choice<String>('caps') == 'round',
  ),
  code: (o) {
    final multiple = o.flag('multiple');
    final shown = _firstShown(multiple: multiple).map((v) => "'$v'");
    return [
      'var _shown = {${shown.join(', ')}};',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      SegmentedButton<String>(',
      '        segments: const [',
      for (final c in _kinds)
        if (c.enabled)
          "          Choice('${c.value}', '${c.label}'),"
        else
          "          Choice('${c.value}', '${c.label}', enabled: false),",
      '        ],',
      '        selected: _shown,',
      if (multiple) '        multiSelectionEnabled: true,',
      if (o.flag('empty')) '        emptySelectionAllowed: true,',
      if (o.flag('icon')) '        showSelectedIcon: true,',
      if (o.choice<String>('caps') == 'round') "        caps: ('(', ')'),",
      '        onSelectionChanged: (shown) => setState(() => _shown = shown),',
      '      ),',
      '      Text.rich([',
      "        Span('shown: ', theme.muted),",
      '        if (_shown.isEmpty)',
      "          Span('nothing', theme.muted)",
      '        else',
      "          Span(_shown.join(', ')),",
      '      ]),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

/// A log's filter, one kind of record or several, and what it shows.
final class _Segments extends StatefulWidget {
  const _Segments({
    required this.multiple,
    required this.empty,
    required this.icon,
    required this.round,
    super.key,
  });

  final bool multiple;
  final bool empty;
  final bool icon;
  final bool round;

  @override
  State<_Segments> createState() => _SegmentsState();
}

final class _SegmentsState extends State<_Segments> with KeptState {
  @override
  Widget build(BuildContext context) {
    final name = 'shown:${widget.multiple}';
    final shown = keptOr(name, _firstShown(multiple: widget.multiple));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        SegmentedButton<String>(
          segments: _kinds,
          selected: shown,
          multiSelectionEnabled: widget.multiple,
          emptySelectionAllowed: widget.empty,
          showSelectedIcon: widget.icon,
          caps: widget.round ? ('(', ')') : ('[', ']'),
          onSelectionChanged: (shown) => keep(name, shown),
        ),
        LitLine([
          ('shown: ', true),
          if (shown.isEmpty) ('nothing', true) else (shown.join(', '), false),
        ], serial: serial),
      ],
    );
  }
}
