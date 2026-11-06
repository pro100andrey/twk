// The TweenAnimationBuilder page.
part of 'animation.dart';

/// The TweenAnimationBuilder page's `value` option.
const _tweenValue = ChoiceOption<double>(
  'value',
  'value',
  values: _opacities,
  labels: _fractions,
  initial: 0.5,
);

// ------------------------------------------------------- TweenAnimationBuilder

final _tween = GalleryPage(
  group: _group,
  title: 'TweenAnimationBuilder',
  options: [
    _tweenValue,
    _curveOption,
    _cycleOption,
  ],
  build: (context, o) => _Cycled(
    o,
    _tweenValue,
    _opacities,
    (context, i) => TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: _opacities[i]),
      duration: _duration,
      curve: _curveOf(o),
      builder: (context, value, _) {
        final theme = Theme.of(context);
        return Row(
          mainAxisSize: .min,
          spacing: 1,
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
      '  tween: Tween<double>(begin: 0, end: $value),',
      '  duration: $_dur,',
      ..._curveLine(o, 2),
      '  builder: (context, value, _) {',
      '    final theme = Theme.of(context);',
      '    return Row(',
      '      mainAxisSize: .min,',
      '      spacing: 1,',
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
    final value = o(_tweenValue);
    if (!o(_cycleOption)) {
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
