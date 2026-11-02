// The RadioGroup page.
part of 'controls.dart';

/// The RadioGroup page's `direction` option.
const _radiogroupDirection = ChoiceOption<String>(
  'direction',
  'direction',
  values: ['vertical', 'horizontal'],
);

/// The RadioGroup page's `mark` option.
const _radiogroupMark = ChoiceOption<String>(
  'mark',
  'mark',
  values: ['●', '*', '✓'],
);

/// The RadioGroup page's `look` option.
const _radiogroupLook = ChoiceOption<String>(
  'look',
  'theme',
  values: ['(●) ( )', '◉ ○'],
);

final _radiogroupPage = GalleryPage(
  group: _group,
  title: 'RadioGroup',
  options: const [
    _radiogroupDirection,
    _radiogroupMark,
    _radiogroupLook,
  ],
  build: (context, o) => _Radios(
    direction: Axis.values.byName(o(_radiogroupDirection)),
    mark: o(_radiogroupMark),
    rings: o(_radiogroupLook) == '◉ ○',
  ),
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
    if (o(_radiogroupLook) == '◉ ○') ...[
      "      // marks and brackets are the theme's glyphs",
      '      Theme(',
      '        data: theme.copyWith(',
      '          glyphs: theme.glyphs.copyWith(',
      "            radioOn: '◉',",
      "            radioOff: '○',",
      "            radioBrackets: ('', ''),",
      '          ),',
      '        ),',
      '        child: RadioGroup<String>(',
      '          choices: _fruit,',
      '          value: _chosen,',
      '          direction: .${o.nameOf(_radiogroupDirection)},',
      if (o(_radiogroupMark) != '●') "          mark: '${o(_radiogroupMark)}',",
      '          onChanged: (value) => setState(() => _chosen = value),',
      '        ),',
      '      ),',
    ] else ...[
      '      RadioGroup<String>(',
      '        choices: _fruit,',
      '        value: _chosen,',
      '        direction: .${o.nameOf(_radiogroupDirection)},',
      if (o(_radiogroupMark) != '●') "        mark: '${o(_radiogroupMark)}',",
      '        onChanged: (value) => setState(() => _chosen = value),',
      '      ),',
    ],
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
  const _Radios({
    required this.direction,
    required this.mark,
    required this.rings,
  });

  final Axis direction;

  /// Whether the theme's glyphs draw `◉ ○`, no parentheses.
  final bool rings;

  /// What is between the parentheses of the choice chosen.
  final String mark;

  @override
  State<_Radios> createState() => _RadiosState();
}

final class _RadiosState extends State<_Radios> with KeptState {
  /// [group] with the marks `◉ ○` and no brackets in the theme, where asked.
  Widget _themed(ThemeData theme, Widget group) => !widget.rings
      ? group
      : Theme(
          data: theme.copyWith(
            glyphs: theme.glyphs.copyWith(
              radioOn: '◉',
              radioOff: '○',
              radioBrackets: ('', ''),
            ),
          ),
          child: group,
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = keptOr<String?>('chosen', null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        _themed(
          theme,
          RadioGroup<String>(
            choices: _fruit,
            value: chosen,
            direction: widget.direction,
            mark: widget.mark == '●' ? null : widget.mark,
            onChanged: (value) => keep('chosen', value),
          ),
        ),
        LitLine([
          ('chosen: ', true),
          if (chosen == null) ('nothing', true) else (chosen, false),
        ], serial: serial),
      ],
    );
  }
}
