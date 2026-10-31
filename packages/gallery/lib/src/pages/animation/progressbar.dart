// The ProgressBar page.
part of 'animation.dart';

// ------------------------------------------------------------ ProgressBar

final _progressBar = GalleryPage(
  group: 'Animation',
  title: 'ProgressBar',
  options: [
    const SwitchOption('known', 'value known', initial: true),
    // no value while it is not known
    SliderOption(
      'value',
      'value',
      min: 0,
      max: 100,
      initial: 33,
      format: (v) => '$v%',
      disabled: (o) => !o.flag('known'),
    ),
    const ColorOption('color', 'style', values: _colors, initial: 'success'),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final known = o.flag('known');
    final value = o.number('value').toInt();
    return Row(
      mainAxisSize: .min,
      gap: 1,
      children: [
        SizedBox(
          width: 40,
          child: ProgressBar(
            value: known ? value / 100 : null,
            style: o
                .colorStyle(context, 'color')
                .merge(.new(bg: theme.surface.bg)),
          ),
        ),
        if (known) Text('${'$value'.padLeft(3)}%'),
      ],
    );
  },
  code: (o) {
    final known = o.flag('known');
    final value = o.number('value').toInt();
    final v = _js(double.parse((value / 100).toStringAsFixed(2)));
    return [
      'final theme = Theme.of(context);',
      'return Row(',
      '  mainAxisSize: .min,',
      '  gap: 1,',
      '  children: [',
      '    SizedBox(',
      '      width: 40,',
      '      child: ProgressBar(',
      if (known) '        value: $v,',
      codeLine([
        '        style: theme.${o.color('color')}',
        '.merge(.new(bg: theme.surface.bg)),',
      ]),
      '      ),',
      '    ),',
      if (known) "    const Text('${'$value'.padLeft(3)}%'),",
      '  ],',
      ');',
    ].join('\n');
  },
);
