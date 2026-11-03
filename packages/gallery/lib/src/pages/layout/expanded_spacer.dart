// The Expanded, Spacer page.
part of 'layout.dart';

/// The Expanded, Spacer page's `flex` option.
const _expandedFlex = ChoiceOption<int>(
  'flex',
  'Expanded flex',
  values: [1, 2, 3],
);

/// The Expanded, Spacer page's `fit` option.
const _expandedFit = ChoiceOption<String>(
  'fit',
  'Flexible fit',
  values: ['loose', 'tight'],
);

/// The Expanded, Spacer page's `width` option.
final _expandedWidth = SliderOption(
  'width',
  'width',
  min: 20,
  max: 50,
  initial: 48,
  format: (v) => '$v cells',
);

// ------------------------------------------------------------ Expanded, Spacer

final _expanded = GalleryPage(
  group: _group,
  title: 'Expanded, Spacer',
  options: [
    _expandedFlex,
    _expandedFit,
    _expandedWidth,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final flex = o(_expandedFlex);
    return SizedBox(
      width: o(_expandedWidth).toInt(),
      height: 3,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: flex,
            child: Box(
              border: Border.all(
                type: BorderType.rounded,
                style: theme.accent,
              ),
              child: Text('Expanded $flex', wrap: TextWrap.none),
            ),
          ),
          Flexible(
            fit: FlexFit.values.byName(o(_expandedFit)),
            child: Box(border: _rounded(theme), child: const Text('Flexible')),
          ),
          const Spacer(),
          Box(border: _rounded(theme), child: const Text('end')),
        ],
      ),
    );
  },
  code: (o) => [
    'final theme = Theme.of(context);',
    'return SizedBox(',
    '  width: ${o.nameOf(_expandedWidth)},',
    '  height: 3,',
    '  child: Row(',
    '    crossAxisAlignment: .stretch,',
    '    children: [',
    '      Expanded(',
    if (o(_expandedFlex) != 1) '        flex: ${o.nameOf(_expandedFlex)},',
    '        child: Box(',
    '          border: .all(type: .rounded, style: theme.accent),',
    codeLine([
      "          child: const Text('Expanded ${o.nameOf(_expandedFlex)}', ",
      'wrap: .none),',
    ]),
    '        ),',
    '      ),',
    '      Flexible(',
    if (o(_expandedFit) != 'loose') '        fit: .${o.nameOf(_expandedFit)},',
    '        child: Box(',
    '          border: .all(type: .rounded, style: theme.border),',
    "          child: const Text('Flexible'),",
    '        ),',
    '      ),',
    '      const Spacer(),',
    '      Box(',
    '        border: .all(type: .rounded, style: theme.border),',
    "        child: const Text('end'),",
    '      ),',
    '    ],',
    '  ),',
    ');',
  ].join('\n'),
);
