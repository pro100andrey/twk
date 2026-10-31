// The DotCanvas page.
part of 'data.dart';

/// A turn of the hand, in ms.
const _spinMs = 6000;

final _dotCanvas = GalleryPage(
  group: 'Data',
  title: 'DotCanvas',
  options: [
    ChoiceOption('marker', 'marker', values: _markers.keys.toList()),
    const SwitchOption('live', 'live', initial: true),
  ],
  build: (context, o) => inRoom(
    (_, room) => Timed((context, ms, wake) {
      final live = o.flag('live');
      final t = live ? _tick(ms, _waveTick, wake) * _waveTick / 1000 : 0;
      final hand = math.pi / 2 - 2 * math.pi * t * 1000 / _spinMs;
      final wave = [
        for (var i = 0; i <= 24; i++)
          (24.5 + i / 2, 10.5 + 5 * math.sin(i / 3 - 4 * t)),
      ];
      return SizedBox(
        width: 40,
        height: math.max(6, math.min(12, room)),
        child: DotCanvas(
          xBounds: (0, 40),
          yBounds: (0, 24),
          marker: _markers[o.choice<String>('marker')]!,
          draw: (dots) => dots
            ..draw(const Shape.circle(12, 12, 9, color: Color.cyan))
            ..draw(
              Shape.line(
                12,
                12,
                12 + 8 * math.cos(hand),
                12 + 8 * math.sin(hand),
                color: Color.magenta,
              ),
            )
            ..draw(const Shape.rectangle(24, 3, 13, 15, color: Color.yellow))
            ..draw(Shape.polyline(wave, color: Color.green))
            ..layer()
            ..label(11.5, 22.6, '12')
            ..label(28, 20, 'dots'),
        ),
      );
    }),
  ),
  codeIn: (o, room) {
    final live = o.flag('live');
    const turn = _spinMs ~/ 1000;
    return [
      if (live) ...[
        'var _t = 0.0; // seconds',
        '',
        ..._timer(_waveTick, ['(_) => setState(() => _t += .05),']),
      ],
      '@override',
      'Widget build(BuildContext context) {',
      if (live)
        '  final hand = pi / 2 - 2 * pi * _t / $turn; // a turn in $turn s'
      else
        '  const hand = pi / 2; // at 12',
      '  final wave = [',
      if (live) ...[
        '    for (var i = 0; i <= 24; i++)',
        '      (24.5 + i / 2, 10.5 + 5 * sin(i / 3 - 4 * _t)),',
      ] else
        '    for (var i = 0; i <= 24; i++) (24.5 + i / 2, 10.5 + 5 * sin(i / 3)),',
      '  ];',
      '  return SizedBox(',
      '    width: 40,',
      '    height: ${_rowsIn(room, 12, 6)},',
      '    child: DotCanvas(',
      '      xBounds: (0, 40),',
      '      yBounds: (0, 24),',
      '      marker: ${_markerCode(o)},',
      '      draw: (dots) => dots',
      '        ..draw(const Shape.circle(12, 12, 9, color: .cyan))',
      '        ..draw(',
      '          Shape.line(',
      '            12,',
      '            12,',
      '            12 + 8 * cos(hand),',
      '            12 + 8 * sin(hand),',
      '            color: .magenta,',
      '          ),',
      '        )',
      '        ..draw(const Shape.rectangle(24, 3, 13, 15, color: .yellow))',
      '        ..draw(Shape.polyline(wave, color: .green))',
      '        ..layer()',
      "        ..label(11.5, 22.6, '12')",
      "        ..label(28, 20, 'dots'),",
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);
