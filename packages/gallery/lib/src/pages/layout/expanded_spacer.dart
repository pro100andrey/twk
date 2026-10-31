// The Expanded, Spacer page.
part of 'layout.dart';

// ------------------------------------------------------------ Expanded, Spacer

final _expanded = GalleryPage(
  group: 'Layout',
  title: 'Expanded, Spacer',
  options: [
    const ChoiceOption('flex', 'Expanded flex', values: [1, 2, 3]),
    const ChoiceOption('fit', 'Flexible fit', values: ['loose', 'tight']),
    SliderOption(
      'width',
      'width',
      min: 20,
      max: 50,
      initial: 48,
      format: (v) => '$v cells',
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final flex = o.choice<int>('flex');
    return SizedBox(
      width: o.number('width').toInt(),
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
            fit: FlexFit.values.byName(o.choice('fit')),
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
    '  width: ${o.label('width')},',
    '  height: 3,',
    '  child: Row(',
    '    crossAxisAlignment: .stretch,',
    '    children: [',
    '      Expanded(',
    if (o['flex'] != 1) '        flex: ${o.label('flex')},',
    '        child: Box(',
    '          border: .all(type: .rounded, style: theme.accent),',
    "          child: const Text('Expanded ${o.label('flex')}', wrap: .none),",
    '        ),',
    '      ),',
    '      Flexible(',
    if (o['fit'] != 'loose') '        fit: .${o.label('fit')},',
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
