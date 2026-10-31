// The SizedBox page.
part of 'layout.dart';

/// The SizedBox page's `kind` option.
const _sizedBoxKind = ChoiceOption<String>(
  'kind',
  'constructor',
  values: ['sized', 'expand', 'shrink'],
  labels: ['width, height', '.expand', '.shrink'],
);

/// The SizedBox page's `width` option.
final _sizedBoxWidth = SliderOption(
  'width',
  'width',
  min: 0,
  max: 44,
  initial: 16,
  format: (v) => '$v cells',
  disabled: (o) => o(_sizedBoxKind) != 'sized',
);

/// The SizedBox page's `height` option.
final _sizedBoxHeight = SliderOption(
  'height',
  'height',
  min: 0,
  max: 9,
  initial: 3,
  format: (v) => '$v rows',
  disabled: (o) => o(_sizedBoxKind) != 'sized',
);

// ------------------------------------------------------------ SizedBox

final _sizedBox = GalleryPage(
  group: _group,
  title: 'SizedBox',
  options: [
    _sizedBoxKind,
    _sizedBoxWidth,
    _sizedBoxHeight,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    Widget child(String label) =>
        Box(style: theme.selection, child: Text(label));
    final w = o(_sizedBoxWidth).toInt();
    final h = o(_sizedBoxHeight).toInt();
    return SizedBox(
      width: 40,
      height: 9,
      child: Box(
        border: _rounded(theme),
        child: Center(
          child: switch (o(_sizedBoxKind)) {
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
    final w = o.nameOf(_sizedBoxWidth);
    final h = o.nameOf(_sizedBoxHeight);
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 40,',
      '  height: 9,',
      '  child: Box(',
      '    border: .all(type: .rounded, style: theme.border),',
      '    child: Center(',
      ...switch (o(_sizedBoxKind)) {
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
