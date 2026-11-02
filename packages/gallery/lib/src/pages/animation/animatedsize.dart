// The AnimatedSize page.
part of 'animation.dart';

// ------------------------------------------------------------ AnimatedSize

const _lines = [
  'one line',
  'a second, longer line',
  'a third',
  'a fourth, the longest of them',
  'and a fifth',
];

const _counts = [1, 3, 5];

/// The alignments the AnimatedSize page offers, topLeft its default.
const _sizeAligns = <(String, Alignment)>[
  ('topLeft', .topLeft),
  ('center', .center),
  ('bottomRight', .bottomRight),
];

/// The AnimatedSize page's `lines` option.
const _sizeLines = ChoiceOption<int>(
  'lines',
  'lines',
  values: _counts,
);

/// The AnimatedSize page's `alignment` option.
final _sizeAlignment = ChoiceOption<String>(
  'alignment',
  'alignment',
  values: [for (final a in _sizeAligns) a.$1],
);

final _size = GalleryPage(
  group: _group,
  title: 'AnimatedSize',
  options: [
    _sizeLines,
    // where the child is in the size shown while it runs
    _sizeAlignment,
    _curveOption,
    _cycleOption,
  ],
  build: (context, o) => _Cycled(o, _sizeLines, _counts, (context, i) {
    final theme = Theme.of(context);
    return _inFrame(
      _sizeRoom(o),
      Box(
        border: .all(type: .rounded, style: theme.border),
        child: AnimatedSize(
          duration: _duration,
          curve: _curveOf(o),
          alignment: _sizeAligns
              .firstWhere((a) => a.$1 == o(_sizeAlignment))
              .$2,
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [for (final line in _lines.take(_counts[i])) Text(line)],
          ),
        ),
      ),
    );
  }),
  code: (o) {
    List<String> body(String count) => [
      'final theme = Theme.of(context);',
      ..._framed(o, _sizeRoom(o), 'all five lines', [
        'Box(',
        '  border: .all(type: .rounded, style: theme.border),',
        '  child: AnimatedSize(',
        '    duration: $_dur,',
        ..._curveLine(o, 4),
        if (o(_sizeAlignment) case final a when a != 'topLeft')
          '    alignment: .$a,',
        '    child: Column(',
        '      mainAxisSize: .min,',
        '      crossAxisAlignment: .start,',
        '      children: [for (final line in _lines.take($count)) Text(line)],',
        '    ),',
        '  ),',
        ')',
      ]),
    ];
    final lines = [
      'static const _lines = [',
      for (final l in _lines) "  '$l',",
      '];',
    ];
    final count = o(_sizeLines);
    if (!o(_cycleOption)) {
      return [
        ...lines,
        '',
        '@override',
        'Widget build(BuildContext context) {',
        ..._indent(body('$count'), 2),
        '}',
      ].join('\n');
    }
    return _ticking(
      [
        ...lines,
        'static const _counts = [1, 3, 5];',
        'var _i = ${_counts.indexOf(count)};',
      ],
      _nextOf('_counts'),
      'more lines, or fewer, every 1.2 s',
      body('_counts[_i]'),
    ).join('\n');
  },
);

/// The room AnimatedSize grows in: all five lines in the border.
(int, int) _sizeRoom(Options o) => _overshoot(
  o,
  _lines.map(stringWidth).reduce((a, b) => a > b ? a : b) + 2,
  7,
  5,
  1,
);
