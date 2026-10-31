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

/// The StatusBar page's `gap` option.
const _statusbarGap = ChoiceOption<int>(
  'gap',
  'gap',
  values: [0, 1, 3],
  initial: 1,
);

final _statusbarPage = GalleryPage(
  group: _group,
  title: 'StatusBar',
  options: [
    _statusbarWidth,
    _statusbarGap,
  ],
  build: (context, o) => SizedBox(
    width: o(_statusbarWidth).toInt(),
    child: StatusBar(
      gap: o(_statusbarGap),
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
    if (o(_statusbarGap) != 1) '    gap: ${o.nameOf(_statusbarGap)},',
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
