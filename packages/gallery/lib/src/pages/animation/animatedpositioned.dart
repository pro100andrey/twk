// The AnimatedPositioned page.
part of 'animation.dart';

/// Where the chip is pinned: its name, left, top, width and height.
const _pins = <(String, int, int, int, int)>[
  ('topLeft', 1, 1, 12, 1),
  ('bottomLeft', 1, 5, 12, 1),
  ('bottomRight', 21, 5, 12, 1),
  ('topRight', 21, 1, 12, 1),
  ('fill', 1, 1, 32, 5),
];

final _positioned = GalleryPage(
  group: 'Animation',
  title: 'AnimatedPositioned',
  options: [
    ChoiceOption('pin', 'pinned', values: [for (final p in _pins) p.$1]),
    _curveOption,
    _cycleOption,
  ],
  build: (context, o) => _Cycled(o, 'pin', [for (final p in _pins) p.$1], (
    context,
    i,
  ) {
    final theme = Theme.of(context);
    final (_, left, top, width, height) = _pins[i];
    return SizedBox(
      width: 34,
      height: 7,
      child: Stack(
        fit: .expand,
        children: [
          Box(
            border: .all(type: .rounded, style: theme.border),
          ),
          AnimatedPositioned(
            left: left,
            top: top,
            width: width,
            height: height,
            duration: _duration,
            curve: _curveOf(o),
            child: Box(
              style: theme.selection,
              child: const Center(child: Text('▣ pinned')),
            ),
          ),
        ],
      ),
    );
  }),
  code: (o) {
    final i = _pins.indexWhere((p) => p.$1 == o.choice<String>('pin'));
    final p = _pins[i];
    List<String> body(String l, String t, String w, String h) => [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 34,',
      '  height: 7,',
      '  child: Stack(',
      '    fit: .expand,',
      '    children: [',
      '      Box(',
      '        border: .all(type: .rounded, style: theme.border),',
      '      ),',
      '      AnimatedPositioned(',
      '        left: $l,',
      '        top: $t,',
      '        width: $w,',
      '        height: $h,',
      '        duration: $_dur,',
      ..._curveLine(o, 8),
      '        child: Box(',
      '          style: theme.selection,',
      "          child: const Center(child: Text('▣ pinned')),",
      '        ),',
      '      ),',
      '    ],',
      '  ),',
      ');',
    ];
    if (!o.flag('cycle')) {
      return body('${p.$2}', '${p.$3}', '${p.$4}', '${p.$5}').join('\n');
    }
    return _ticking(
      [
        '// left, top, width, height',
        'static const _pins = [',
        for (final q in _pins)
          '  (${q.$2}, ${q.$3}, ${q.$4}, ${q.$5}), // ${q.$1}',
        '];',
        'var _i = $i;',
      ],
      _nextOf('_pins'),
      'pinned elsewhere every 1.2 s',
      [
        'final (left, top, width, height) = _pins[_i];',
        ...body('left', 'top', 'width', 'height'),
      ],
    ).join('\n');
  },
);
