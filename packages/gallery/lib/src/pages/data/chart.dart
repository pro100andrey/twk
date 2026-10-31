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

/// The Chart page's `graph` option.
const _chartGraph = ChoiceOption<String>(
  'graph',
  'graph',
  values: ['scatter', 'line'],
  initial: 'line',
);

/// The Chart page's `marker` option.
final _chartMarker = ChoiceOption<String>(
  'marker',
  'marker',
  values: _markers.keys.toList(),
);

/// The Chart page's `legend` option.
const _chartLegend = ChoiceOption<String?>(
  'legend',
  'legend',
  values: [..._legends, null],
  initial: 'topRight',
);

/// The Chart page's `live` option.
const _chartLive = SwitchOption('live', 'live', initial: true);

final _chart = GalleryPage(
  group: _group,
  title: 'Chart',
  options: [
    _chartGraph,
    _chartMarker,
    _chartLegend,
    _chartLive,
  ],
  build: (context, o) => inRoom(
    (_, room) => Timed((context, ms, wake) {
      // the waves run to the right, two radians a second
      final phase = o(_chartLive) ? _tick(ms, _waveTick, wake) * .1 : 0;
      List<(double, double)> wave(double Function(num) f) => [
        for (var i = 0; i <= 60; i++)
          (i * math.pi / 30, f(i * math.pi / 30 - phase)),
      ];
      final type = GraphType.values.byName(o(_chartGraph));
      final legend = o(_chartLegend);
      return SizedBox(
        width: 50,
        height: math.max(6, math.min(12, room)),
        child: Chart(
          marker: _markers[o(_chartMarker)]!,
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
    final live = o(_chartLive);
    final graph = o.nameOf(_chartGraph);
    final legend = o(_chartLegend);
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
