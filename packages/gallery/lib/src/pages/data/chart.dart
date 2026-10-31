// The Chart page.
part of 'data.dart';

const _legends = [
  'topLeft',
  'top',
  'topRight',
  'left',
  'right',
  'bottomLeft',
  'bottom',
  'bottomRight',
];

final _chart = GalleryPage(
  group: 'Data',
  title: 'Chart',
  options: [
    const ChoiceOption(
      'graph',
      'graph',
      values: ['scatter', 'line'],
      initial: 'line',
    ),
    ChoiceOption('marker', 'marker', values: _markers.keys.toList()),
    const ChoiceOption(
      'legend',
      'legend',
      values: [..._legends, null],
      initial: 'topRight',
    ),
    const SwitchOption('live', 'live', initial: true),
  ],
  build: (context, o) => inRoom(
    (_, room) => Timed((context, ms, wake) {
      // the waves run to the right, two radians a second
      final phase = o.flag('live') ? _tick(ms, _waveTick, wake) * .1 : 0;
      List<(double, double)> wave(double Function(num) f) => [
        for (var i = 0; i <= 60; i++)
          (i * math.pi / 30, f(i * math.pi / 30 - phase)),
      ];
      final type = GraphType.values.byName(o.choice('graph'));
      final legend = o.choice<String?>('legend');
      return SizedBox(
        width: 50,
        height: math.max(6, math.min(12, room)),
        child: Chart(
          marker: _markers[o.choice<String>('marker')]!,
          legendPosition: legend == null
              ? null
              : LegendPosition.values.byName(legend),
          style: Theme.of(context).muted,
          datasets: [
            Dataset(
              data: wave(math.sin),
              name: 'sin',
              type: type,
              color: Color.cyan,
            ),
            Dataset(
              data: wave(math.cos),
              name: 'cos',
              type: type,
              color: Color.yellow,
            ),
          ],
          xAxis: const ChartAxis(
            bounds: (0, 2 * math.pi),
            title: 'x',
            labels: ['0', 'π', '2π'],
          ),
          yAxis: const ChartAxis(bounds: (-1, 1), labels: ['-1', '0', '1']),
        ),
      );
    }),
  ),
  codeIn: (o, room) {
    final live = o.flag('live');
    final graph = o.label('graph');
    final legend = o.choice<String?>('legend');
    return [
      if (live) ...[
        'var _phase = 0.0;',
        '',
        '// the waves run to the right',
        ..._timer(_waveTick, ['(_) => setState(() => _phase += .1),']),
      ],
      '/// [f] at 61 points from 0 to 2π.',
      'List<(double, double)> _wave(double Function(num) f) => [',
      codeLine([
        '  for (var i = 0; i <= 60; i++) (i * pi / 30, f(i * pi / 30',
        "${live ? ' - _phase' : ''})),",
      ]),
      '];',
      '',
      '@override',
      'Widget build(BuildContext context) => SizedBox(',
      '  width: 50,',
      '  height: ${_rowsIn(room, 12, 6)},',
      '  child: Chart(',
      '    marker: ${_markerCode(o)},',
      "    legendPosition: ${legend == null ? 'null' : '.$legend'},",
      '    style: Theme.of(context).muted,',
      '    datasets: [',
      codeLine([
        "      Dataset(data: _wave(sin), name: 'sin', type: .$graph, ",
        'color: .cyan),',
      ]),
      codeLine([
        "      Dataset(data: _wave(cos), name: 'cos', type: .$graph, ",
        'color: .yellow),',
      ]),
      '    ],',
      '    xAxis: const ChartAxis(',
      '      bounds: (0, 2 * pi),',
      "      title: 'x',",
      "      labels: ['0', 'π', '2π'],",
      '    ),',
      "    yAxis: const ChartAxis(bounds: (-1, 1), labels: ['-1', '0', '1']),",
      '  ),',
      ');',
    ].join('\n');
  },
);
