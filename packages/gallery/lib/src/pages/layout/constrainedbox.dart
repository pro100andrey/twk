// The ConstrainedBox page.
part of 'layout.dart';

// ------------------------------------------------------------ ConstrainedBox

final _constrainedBox = GalleryPage(
  group: 'Layout',
  title: 'ConstrainedBox',
  options: const [
    ChoiceOption('min', 'min width', values: [0, 12, 20], initial: 12),
    ChoiceOption('max', 'max width', values: [20, 32, 48], initial: 32),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    Widget bounded(String text) => ConstrainedBox(
      constraints: BoxConstraints(o.choice('min'), o.choice('max'), 1, 3),
      child: Box(
        style: theme.selection,
        padding: const EdgeInsets.x(1),
        child: Text(text),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
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
      '  constraints: const BoxConstraints(',
      "${o.label('min')}, ${o.label('max')}, 1, 3),",
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
    '  gap: 1,',
    '  children: [',
    "    bounded('short'),",
    "    bounded('A child as wide as its text, within the bounds.'),",
    '  ],',
    ');',
  ].join('\n'),
);
