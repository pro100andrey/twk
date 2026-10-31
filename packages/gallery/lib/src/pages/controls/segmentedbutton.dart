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

/// The SegmentedButton page's `multiple` option.
const _segmentedMultiple = SwitchOption('multiple', 'multiple');

/// The SegmentedButton page's `empty` option.
const _segmentedEmpty = SwitchOption('empty', 'allow none');

/// The SegmentedButton page's `icon` option.
const _segmentedIcon = SwitchOption('icon', 'selected icon');

/// The SegmentedButton page's `caps` option.
const _segmentedCaps = ChoiceOption<String>(
  'caps',
  'caps',
  values: ['square', 'round'],
);

final _segmented = GalleryPage(
  group: _group,
  title: 'SegmentedButton',
  options: const [
    _segmentedMultiple,
    _segmentedEmpty,
    _segmentedIcon,
    _segmentedCaps,
  ],
  build: (context, o) => _Segments(
    key: ValueKey(o(_segmentedMultiple)),
    multiple: o(_segmentedMultiple),
    empty: o(_segmentedEmpty),
    icon: o(_segmentedIcon),
    round: o(_segmentedCaps) == 'round',
  ),
  code: (o) {
    final multiple = o(_segmentedMultiple);
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
      if (o(_segmentedEmpty)) '        emptySelectionAllowed: true,',
      if (o(_segmentedIcon)) '        showSelectedIcon: true,',
      if (o(_segmentedCaps) == 'round') "        caps: ('(', ')'),",
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
