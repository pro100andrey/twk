// The ProgressBar page.
part of 'animation.dart';

/// The ProgressBar page's `known` option.
const _progressBarKnown = SwitchOption(
  'known',
  'value known',
  initial: true,
);

/// The ProgressBar page's `value` option.
final _progressBarValue = SliderOption(
  'value',
  'value',
  min: 0,
  max: 100,
  initial: 33,
  format: (v) => '$v%',
  disabled: (o) => !o(_progressBarKnown),
);

/// The ProgressBar page's `color` option.
const _progressBarColor = ColorOption(
  'color',
  'style',
  values: _colors,
  initial: 'success',
);

// ------------------------------------------------------------ ProgressBar

final _progressBar = GalleryPage(
  group: _group,
  title: 'ProgressBar',
  options: [
    _progressBarKnown,
    // no value while it is not known
    _progressBarValue,
    _progressBarColor,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final known = o(_progressBarKnown);
    final value = o(_progressBarValue).toInt();
    return Row(
      mainAxisSize: .min,
      gap: 1,
      children: [
        SizedBox(
          width: 40,
          child: ProgressBar(
            value: known ? value / 100 : null,
            style: o
                .styleOf(context, _progressBarColor)
                .merge(.new(bg: theme.surface.bg)),
          ),
        ),
        if (known) Text('${'$value'.padLeft(3)}%'),
      ],
    );
  },
  code: (o) {
    final known = o(_progressBarKnown);
    final value = o(_progressBarValue).toInt();
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
        '        style: theme.${o(_progressBarColor)}',
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
