// The TweenAnimationBuilder page.
part of 'animation.dart';

// ------------------------------------------------------- TweenAnimationBuilder

final _tween = GalleryPage(
  group: 'Animation',
  title: 'TweenAnimationBuilder',
  options: [
    const ChoiceOption(
      'value',
      'value',
      values: _opacities,
      labels: _fractions,
      initial: 0.5,
    ),
    _curveOption,
    _cycleOption,
  ],
  build: (context, o) => _Cycled(
    o,
    'value',
    _opacities,
    (context, i) => TweenAnimationBuilder<double>(
      value: _opacities[i],
      from: 0,
      tween: Tween.new,
      duration: _duration,
      curve: _curveOf(o),
      builder: (context, value, _) {
        final theme = Theme.of(context);
        return Row(
          mainAxisSize: .min,
          gap: 1,
          children: [
            SizedBox(
              width: 30,
              child: ProgressBar(
                value: value,
                style: theme.accent.merge(.new(bg: theme.surface.bg)),
              ),
            ),
            // as wide as 100%
            SizedBox(width: 4, child: Text('${(value * 100).round()}%')),
          ],
        );
      },
    ),
  ),
  code: (o) {
    List<String> body(String value) => [
      'return TweenAnimationBuilder<double>(',
      '  value: $value,',
      '  from: 0,',
      '  tween: Tween.new,',
      '  duration: $_dur,',
      ..._curveLine(o, 2),
      '  builder: (context, value, _) {',
      '    final theme = Theme.of(context);',
      '    return Row(',
      '      mainAxisSize: .min,',
      '      gap: 1,',
      '      children: [',
      '        SizedBox(',
      '          width: 30,',
      '          child: ProgressBar(',
      '            value: value,',
      '            style: theme.accent.merge(.new(bg: theme.surface.bg)),',
      '          ),',
      '        ),',
      '        // as wide as 100%',
      r"        SizedBox(width: 4, child: Text('${(value * 100).round()}%')),",
      '      ],',
      '    );',
      '  },',
      ');',
    ];
    final value = o.choice<double>('value');
    if (!o.flag('cycle')) {
      return body(_js(value)).join('\n');
    }
    return _ticking(
      [
        'static const _values = [0.0, 0.25, 0.5, 0.75, 1.0];',
        'var _i = ${_opacities.indexOf(value)};',
      ],
      _nextOf('_values'),
      'the next value every 1.2 s',
      body('_values[_i]'),
    ).join('\n');
  },
);
