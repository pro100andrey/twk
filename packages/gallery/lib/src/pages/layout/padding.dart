// The Padding page.
part of 'layout.dart';

// ------------------------------------------------------------ Padding

// the Dart, and the insets
const _insets = {
  'all 1': ('.all(1)', EdgeInsets.all(1)),
  'x 4': ('.x(4)', EdgeInsets.x(4)),
  'y 2': ('.y(2)', EdgeInsets.y(2)),
  'left 8': ('.only(left: 8)', EdgeInsets.only(left: 8)),
  'left 3, top 1': ('.only(left: 3, top: 1)', EdgeInsets.only(left: 3, top: 1)),
};

final _padding = GalleryPage(
  group: 'Layout',
  title: 'Padding',
  options: [
    ChoiceOption(
      'insets',
      'padding',
      values: _insets.keys.toList(),
      initial: 'x 4',
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    return Box(
      border: _rounded(theme),
      child: Padding(
        padding: _insets[o.choice<String>('insets')]!.$2,
        child: Box(
          style: theme.selection,
          child: const Text('the child,\npadded from the box'),
        ),
      ),
    );
  },
  code: (o) => [
    'final theme = Theme.of(context);',
    'return Box(',
    '  border: .all(type: .rounded, style: theme.border),',
    '  child: Padding(',
    '    padding: const ${_insets[o.choice<String>('insets')]!.$1},',
    '    child: Box(',
    '      style: theme.selection,',
    r"      child: const Text('the child,\npadded from the box'),",
    '    ),',
    '  ),',
    ');',
  ].join('\n'),
);
