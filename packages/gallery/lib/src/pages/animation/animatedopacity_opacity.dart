// The AnimatedOpacity, Opacity page.
part of 'animation.dart';

/// The text under the child, and the child: a Box padded a cell either
/// side (a blank at the end of a Text would hang beyond it, uncounted).
const _under = 'under it, under it';

const _child = 'the child';

/// The AnimatedOpacity, Opacity page's `opacity` option.
const _opacityOpacity = ChoiceOption<double>(
  'opacity',
  'opacity',
  values: _opacities,
  labels: _fractions,
  initial: 0.5,
);

final _opacity = GalleryPage(
  group: _group,
  title: 'AnimatedOpacity, Opacity',
  options: [
    _opacityOpacity,
    _cycleOption,
  ],
  build: (context, o) => _Cycled(o, _opacityOpacity, _opacities, (context, i) {
    final theme = Theme.of(context);
    final opacity = _opacities[i];
    Widget over(Widget child, String name) => Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      gap: 1,
      children: [
        Box(
          style: theme.surface,
          padding: const .all(1),
          child: Stack(
            children: [
              Text(_under, style: theme.muted),
              child,
            ],
          ),
        ),
        Text(name, style: theme.muted),
      ],
    );
    final shown = Box(
      style: theme.selection,
      padding: const .x(1),
      child: Text(_child, style: theme.text),
    );
    return Row(
      mainAxisSize: .min,
      gap: 2,
      children: [
        over(
          AnimatedOpacity(opacity: opacity, duration: _duration, child: shown),
          'AnimatedOpacity',
        ),
        over(Opacity(opacity: opacity, child: shown), 'Opacity'),
      ],
    );
  }),
  code: (o) {
    final value = o(_opacityOpacity);
    List<String> body(String opacity) => [
      'final theme = Theme.of(context);',
      'Widget over(Widget child, String name) => Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      '    Box(',
      '      style: theme.surface,',
      '      padding: const .all(1),',
      '      child: Stack(',
      '        children: [',
      "          Text('$_under', style: theme.muted),",
      '          child,',
      '        ],',
      '      ),',
      '    ),',
      '    Text(name, style: theme.muted),',
      '  ],',
      ');',
      'final shown = Box(',
      '  style: theme.selection,',
      '  padding: const .x(1),',
      "  child: Text('$_child', style: theme.text),",
      ');',
      'return Row(',
      '  mainAxisSize: .min,',
      '  gap: 2,',
      '  children: [',
      '    over(',
      '      AnimatedOpacity(',
      '        opacity: $opacity,',
      '        duration: $_dur,',
      '        child: shown,',
      '      ),',
      "      'AnimatedOpacity',",
      '    ),',
      "    over(Opacity(opacity: $opacity, child: shown), 'Opacity'),",
      '  ],',
      ');',
    ];
    if (!o(_cycleOption)) {
      return body(_js(value)).join('\n');
    }
    return _ticking(
      [
        'static const _opacities = [0.0, 0.25, 0.5, 0.75, 1.0];',
        'var _i = ${_opacities.indexOf(value)};',
      ],
      _nextOf('_opacities'),
      'the next opacity every 1.2 s',
      ['final opacity = _opacities[_i];', ...body('opacity')],
    ).join('\n');
  },
);
