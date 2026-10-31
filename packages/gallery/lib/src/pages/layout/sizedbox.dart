// The SizedBox page.
part of 'layout.dart';

// ------------------------------------------------------------ SizedBox

final _sizedBox = GalleryPage(
  group: 'Layout',
  title: 'SizedBox',
  options: [
    const ChoiceOption(
      'kind',
      'constructor',
      values: ['sized', 'expand', 'shrink'],
      labels: ['width, height', '.expand', '.shrink'],
    ),
    SliderOption(
      'width',
      'width',
      min: 0,
      max: 44,
      initial: 16,
      format: (v) => '$v cells',
      disabled: (o) => o['kind'] != 'sized',
    ),
    SliderOption(
      'height',
      'height',
      min: 0,
      max: 9,
      initial: 3,
      format: (v) => '$v rows',
      disabled: (o) => o['kind'] != 'sized',
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    Widget child(String label) =>
        Box(style: theme.selection, child: Text(label));
    final w = o.number('width').toInt();
    final h = o.number('height').toInt();
    return SizedBox(
      width: 40,
      height: 9,
      child: Box(
        border: _rounded(theme),
        child: Center(
          child: switch (o['kind']) {
            'expand' => SizedBox.expand(child: child('SizedBox.expand')),
            'shrink' => SizedBox.shrink(child: child('none of it shows')),
            _ => SizedBox(width: w, height: h, child: child('$w × $h')),
          },
        ),
      ),
    );
  },
  code: (o) {
    List<String> child(String label) => _call(8, 'child: Box', [
      'style: theme.selection',
      "child: const Text('$label')",
    ], ',');
    final w = o.label('width');
    final h = o.label('height');
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 40,',
      '  height: 9,',
      '  child: Box(',
      '    border: .all(type: .rounded, style: theme.border),',
      '    child: Center(',
      ...switch (o['kind']) {
        'expand' => [
          '      child: SizedBox.expand(',
          ...child('SizedBox.expand'),
          '      ),',
        ],
        'shrink' => [
          '      child: SizedBox.shrink(',
          ...child('none of it shows'),
          '      ),',
        ],
        _ => [
          '      child: SizedBox(',
          '        width: $w,',
          '        height: $h,',
          ...child('$w × $h'),
          '      ),',
        ],
      },
      '    ),',
      '  ),',
      ');',
    ].join('\n');
  },
);
