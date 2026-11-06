// The StatusBar page.
part of 'controls.dart';

/// The StatusBar page's `width` option.
final _statusbarWidth = SliderOption(
  'width',
  'width',
  min: 12,
  max: 50,
  initial: 50,
  format: (v) => '$v cells',
);

/// The StatusBar page's `spacing` option.
const _statusbarSpacing = ChoiceOption<int>(
  'spacing',
  'spacing',
  values: [0, 1, 3],
  initial: 1,
);

final _statusbarPage = GalleryPage(
  group: _group,
  title: 'StatusBar',
  options: [
    _statusbarWidth,
    _statusbarSpacing,
  ],
  build: (context, o) => SizedBox(
    width: o(_statusbarWidth).toInt(),
    child: StatusBar(
      spacing: o(_statusbarSpacing),
      left: const Badge('NORMAL'),
      center: const Text(
        'example/widgets/main.dart',
        wrap: TextWrap.none,
        overflow: TextOverflow.ellipsis,
      ),
      right: Text('Ln 12, Col 4', style: Theme.of(context).muted),
    ),
  ),
  code: (o) => [
    'return SizedBox(',
    '  width: ${o.nameOf(_statusbarWidth)},',
    '  child: StatusBar(',
    if (o(_statusbarSpacing) != 1)
      '    spacing: ${o.nameOf(_statusbarSpacing)},',
    "    left: const Badge('NORMAL'),",
    '    center: const Text(',
    "      'example/widgets/main.dart',",
    '      wrap: .none,',
    '      overflow: .ellipsis,',
    '    ),',
    "    right: Text('Ln 12, Col 4', style: Theme.of(context).muted),",
    '  ),',
    ');',
  ].join('\n'),
);
