// The ConstrainedBox page.
part of 'layout.dart';

/// The ConstrainedBox page's `min` option.
const _constrainedBoxMin = ChoiceOption<int>(
  'min',
  'min width',
  values: [0, 12, 20],
  initial: 12,
);

/// The ConstrainedBox page's `max` option.
const _constrainedBoxMax = ChoiceOption<int>(
  'max',
  'max width',
  values: [20, 32, 48],
  initial: 32,
);

// ------------------------------------------------------------ ConstrainedBox

final _constrainedBox = GalleryPage(
  group: _group,
  title: 'ConstrainedBox',
  options: const [
    _constrainedBoxMin,
    _constrainedBoxMax,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    Widget bounded(String text) => ConstrainedBox(
      constraints: BoxConstraints(
        minW: o(_constrainedBoxMin),
        maxW: o(_constrainedBoxMax),
        minH: 1,
        maxH: 3,
      ),
      child: Box(
        style: theme.selection,
        padding: const EdgeInsets.x(1),
        child: Text(text),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 1,
      children: [
        bounded('short'),
        bounded('A child as wide as its text, within the bounds.'),
      ],
    );
  },
  code: (o) => [
    'final theme = Theme.of(context);',
    'Widget bounded(String text) => ConstrainedBox(',
    codeLine([
      '  constraints: const BoxConstraints(minW: ',
      '${o.nameOf(_constrainedBoxMin)}, maxW: ',
      '${o.nameOf(_constrainedBoxMax)}, minH: 1, maxH: 3),',
    ]),
    '  child: Box(',
    '    style: theme.selection,',
    '    padding: const .x(1),',
    '    child: Text(text),',
    '  ),',
    ');',
    'return Column(',
    '  mainAxisSize: .min,',
    '  crossAxisAlignment: .start,',
    '  spacing: 1,',
    '  children: [',
    "    bounded('short'),",
    "    bounded('A child as wide as its text, within the bounds.'),",
    '  ],',
    ');',
  ].join('\n'),
);
