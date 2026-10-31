// The StatusBar page.
part of 'controls.dart';

final _statusbarPage = GalleryPage(
  group: 'Controls',
  title: 'StatusBar',
  options: [
    SliderOption(
      'width',
      'width',
      min: 12,
      max: 50,
      initial: 50,
      format: (v) => '$v cells',
    ),
    const ChoiceOption('gap', 'gap', values: [0, 1, 3], initial: 1),
  ],
  build: (context, o) => SizedBox(
    width: o.number('width').toInt(),
    child: StatusBar(
      gap: o.choice('gap'),
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
    '  width: ${o.label('width')},',
    '  child: StatusBar(',
    if (o.choice<int>('gap') != 1) '    gap: ${o.label('gap')},',
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
