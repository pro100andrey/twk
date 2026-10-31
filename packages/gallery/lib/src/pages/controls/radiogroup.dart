// The RadioGroup page.
part of 'controls.dart';

final _radiogroupPage = GalleryPage(
  group: 'Controls',
  title: 'RadioGroup',
  options: const [
    ChoiceOption(
      'direction',
      'direction',
      values: ['vertical', 'horizontal'],
    ),
  ],
  build: (context, o) =>
      _Radios(direction: Axis.values.byName(o.choice('direction'))),
  code: (o) => [
    'const _fruit = [',
    "  Choice('apple', 'apple'),",
    "  Choice('banana', 'banana'),",
    "  Choice('cherry', 'cherry'),",
    "  Choice('durian', 'durian', enabled: false),",
    '];',
    '',
    'String? _chosen;',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    '      RadioGroup<String>(',
    '        choices: _fruit,',
    '        value: _chosen,',
    '        direction: .${o.label('direction')},',
    '        onChanged: (value) => setState(() => _chosen = value),',
    '      ),',
    '      Text.rich([',
    "        Span('chosen: ', theme.muted),",
    '        if (_chosen case final chosen?)',
    '          Span(chosen)',
    '        else',
    "          Span('nothing', theme.muted),",
    '      ]),',
    '    ],',
    '  );',
    '}',
  ].join('\n'),
);

const List<Choice<String>> _fruit = [
  Choice('apple', 'apple'),
  Choice('banana', 'banana'),
  Choice('cherry', 'cherry'),
  Choice('durian', 'durian', enabled: false),
];

/// A fruit chosen in a radio group.
final class _Radios extends StatefulWidget {
  const _Radios({required this.direction});

  final Axis direction;

  @override
  State<_Radios> createState() => _RadiosState();
}

final class _RadiosState extends State<_Radios> with KeptState {
  @override
  Widget build(BuildContext context) {
    final chosen = keptOr<String?>('chosen', null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        RadioGroup<String>(
          choices: _fruit,
          value: chosen,
          direction: widget.direction,
          onChanged: (value) => keep('chosen', value),
        ),
        LitLine([
          ('chosen: ', true),
          if (chosen == null) ('nothing', true) else (chosen, false),
        ], serial: serial),
      ],
    );
  }
}
