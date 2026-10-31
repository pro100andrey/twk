// The AnimatedAlign, AnimatedPadding page.
part of 'animation.dart';

// ---------------------------------------------- AnimatedAlign, AnimatedPadding

const _aligns = <(String, Alignment)>[
  ('centerLeft', .centerLeft),
  ('center', .center),
  ('centerRight', .centerRight),
  ('bottomRight', .bottomRight),
];

final _align = GalleryPage(
  group: 'Animation',
  title: 'AnimatedAlign, AnimatedPadding',
  options: [
    ChoiceOption(
      'alignment',
      'alignment',
      values: [for (final a in _aligns) a.$1],
    ),
    _curveOption,
    _cycleOption,
  ],
  build: (context, o) =>
      _Cycled(o, 'alignment', [for (final a in _aligns) a.$1], (
        context,
        i,
      ) {
        final theme = Theme.of(context);
        final alignment = _aligns[i].$2;
        final curve = _curveOf(o);
        return SizedBox(
          width: 34,
          height: 7,
          child: Box(
            border: .all(type: .rounded, style: theme.border),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Expanded(
                  child: AnimatedAlign(
                    alignment: alignment,
                    duration: _duration,
                    curve: curve,
                    child: Text('◆ aligned', style: theme.primary),
                  ),
                ),
                AnimatedPadding(
                  padding: .only(left: alignment.x * 10 + 10),
                  duration: _duration,
                  curve: curve,
                  child: Text('◇ padded', style: theme.accent),
                ),
              ],
            ),
          ),
        );
      }),
  code: (o) {
    final i = _aligns.indexWhere((a) => a.$1 == o.choice<String>('alignment'));
    final a = _aligns[i];
    List<String> body(String alignment, String left) => [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 34,',
      '  height: 7,',
      '  child: Box(',
      '    border: .all(type: .rounded, style: theme.border),',
      '    child: Column(',
      '      crossAxisAlignment: .start,',
      '      children: [',
      '        Expanded(',
      '          child: AnimatedAlign(',
      '            alignment: $alignment,',
      '            duration: $_dur,',
      ..._curveLine(o, 12),
      "            child: Text('◆ aligned', style: theme.primary),",
      '          ),',
      '        ),',
      '        AnimatedPadding(',
      '          padding: $left,',
      '          duration: $_dur,',
      ..._curveLine(o, 10),
      "          child: Text('◇ padded', style: theme.accent),",
      '        ),',
      '      ],',
      '    ),',
      '  ),',
      ');',
    ];
    if (!o.flag('cycle')) {
      final left = a.$2.x * 10 + 10;
      return body(
        '.${a.$1}',
        left != 0 ? 'const .only(left: $left)' : '.zero',
      ).join('\n');
    }
    return _ticking(
      [
        'static const _alignments = <Alignment>[',
        for (final x in _aligns) '  .${x.$1},',
        '];',
        'var _i = $i;',
      ],
      _nextOf('_alignments'),
      'the next alignment every 1.2 s',
      [
        'final alignment = _alignments[_i];',
        ...body('alignment', '.only(left: alignment.x * 10 + 10)'),
      ],
    ).join('\n');
  },
);
