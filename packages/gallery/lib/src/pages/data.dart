// The Data group of the gallery.
import 'dart:async';
import 'dart:math' as math;

import 'package:twk/twk.dart';

import '../page.dart';
import 'common.dart';

// ------------------------------------------------------------ shared

/// The theme colours the Data pages offer, in the design's order.
const _colors = ['primary', 'accent', 'success', 'warning', 'info'];

/// The rows a widget takes in [room]: [want]
/// rows, or the room's where it is lower, [least] at least.
int _rowsIn(StageRoom room, int want, int least) =>
    math.max(least, math.min(want, room.height));

/// [build] with the rows of the stage's room; the Code is given the same
/// ([GalleryPage.codeIn]).
Widget _inRoom(Widget Function(int room) build) => LayoutBuilder(
  builder: (context, c) =>
      build(c.maxH < BoxConstraints.unbounded ? c.maxH : 1 << 20),
);

/// The lines of a State whose timer calls [body] every [ms], and a blank.
List<String> _timer(int ms, List<String> body) => [
  ...timerLines(ms, body),
  '',
];

/// The step of [step] ms that [ms] is in; asks for a build at the next.
int _tick(int ms, int step, void Function(int) wake) {
  final k = ms ~/ step;
  wake((k + 1) * step);
  return k;
}

// ------------------------------------------------------------ Sparkline

/// A new value this often while the sparkline is live.
const _step = 150;

/// A value from 0 to 1 that looks random and is the same for the same [i],
/// as the Code's `_noise` computes it.
double _noise(int i) {
  final s = math.sin(i * 91.345 + 3.1) * 43758.5453;
  return s - s.floorToDouble();
}

/// Each series as the stage computes it, and as the Code writes it.
final _series = <String, (double Function(int i), String)>{
  'wave': ((i) => 4 + 3 * math.sin(i / 4), '4 + 3 * sin(i / 4)'),
  'ramp': ((i) => (i % 48).toDouble(), '(i % 48).toDouble()'),
  'steps': ((i) => (i ~/ 8 % 3).toDouble(), '(i ~/ 8 % 3).toDouble()'),
  'noise': (
    (i) => 1 + _noise(i) * 6 + (_noise(i >> 3) > 0.7 ? 3 : 0),
    '_value(i)',
  ),
};

/// The Code's line of what `_noise` gives.
const _noiseDoc =
    '/// A value from 0 to 1 that looks random and is the same for the same '
    '[i].';

final _sparkline = GalleryPage(
  group: 'Data',
  title: 'Sparkline',
  options: [
    ChoiceOption('data', 'data', values: _series.keys.toList()),
    const ChoiceOption('rows', 'rows', values: [1, 2, 4], initial: 4),
    const ChoiceOption(
      'max',
      'max',
      values: [null, 10.0],
      labels: ['largest', '10'],
    ),
    const SwitchOption('live', 'live', initial: true),
    const ColorOption(
      'color',
      'style',
      values: ['info', 'primary', 'accent', 'success', 'warning'],
      initial: 'info',
    ),
  ],
  build: (context, o) => Timed((context, ms, wake) {
    final k = o.flag('live') ? _tick(ms, _step, wake) : 0;
    final f = _series[o.choice<String>('data')]!.$1;
    return SizedBox(
      width: 48,
      height: o.choice('rows'),
      child: Sparkline(
        data: [for (var i = 0; i < 48; i++) f(i + k)],
        max: o.choice('max'),
        style: o.colorStyle(context, 'color'),
      ),
    );
  }),
  code: (o) {
    final gen = _series[o.choice<String>('data')]!.$2;
    final build = [
      '@override',
      'Widget build(BuildContext context) => SizedBox(',
      '  width: 48,',
      '  height: ${o.label('rows')},',
      if (o.choice<double?>('max') == null)
        codeLine([
          '  child: Sparkline(data: _data, style: ',
          'Theme.of(context).${o.color('color')}),',
        ])
      else ...[
        '  child: Sparkline(',
        '    data: _data,',
        '    max: ${o.label('max')},',
        '    style: Theme.of(context).${o.color('color')},',
        '  ),',
      ],
      ');',
    ];
    final helper = o.choice<String>('data') == 'noise'
        ? [
            '',
            '/// The value at [i]: from 1 to 7, 3 more in some runs of 8.',
            'static double _value(int i) =>',
            '    1 + _noise(i) * 6 + (_noise(i >> 3) > .7 ? 3 : 0);',
            '',
            _noiseDoc,
            'static double _noise(int i) {',
            '  final s = sin(i * 91.345 + 3.1) * 43758.5453;',
            '  return s - s.floorToDouble();',
            '}',
          ]
        : const <String>[];
    if (!o.flag('live')) {
      return [
        'final _data = [for (var i = 0; i < 48; i++) $gen];',
        '',
        ...build,
        ...helper,
      ].join('\n');
    }
    return [
      'var _i = 48;',
      'var _data = [for (var i = 0; i < 48; i++) $gen];',
      '',
      '// a value every $_step ms, the oldest dropped',
      ..._timer(_step, [
        '(_) => setState(() {',
        '  final i = _i++;',
        '  _data = [..._data.skip(1), $gen];',
        '}),',
      ]),
      ...build,
      ...helper,
    ].join('\n');
  },
);

// ------------------------------------------------------------ Gauge, LineGauge

const _gaugeW = 40;
const _fillMs = 7000;
const _holdMs = 2000;
const _gaugeTick = 25;

/// The ratio as the Code writes it while it stands still: `0.75`, `0.5`.
String _ratioLiteral(num percent) {
  final s = (percent / 100).toStringAsFixed(2);
  return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
}

final _gauge = GalleryPage(
  group: 'Data',
  title: 'Gauge, LineGauge',
  options: [
    const SwitchOption('live', 'live', initial: true),
    SliderOption(
      'ratio',
      'ratio',
      min: 0,
      max: 100,
      initial: 75,
      format: (v) => '$v%',
    ),
    const ChoiceOption(
      'line',
      'line',
      values: ['single', 'heavy', 'double', 'ascii'],
      initial: 'heavy',
    ),
    const ChoiceOption(
      'label',
      'label',
      values: ['own', 'ratio', 'none'],
    ),
    const ColorOption('color', 'style', values: _colors, initial: 'primary'),
    const SwitchOption('segmented', 'segmented'),
  ],
  build: (context, o) => Timed((context, ms, wake) {
    final control = PageControl.of(context);
    final kept = control.state;
    final ratio = o.number('ratio');
    // the ratio moved stops the timer: the gauges show the ratio chosen
    final moved = kept['ratio'] != null && kept['ratio'] != ratio;
    kept['ratio'] = ratio;
    final live = o.flag('live');
    if (moved && live) {
      scheduleMicrotask(() => control.setOption('live', false));
    }
    var r = ratio / 100;
    if (live && !moved) {
      final at = _tick(ms, _gaugeTick, wake) * _gaugeTick % (_fillMs + _holdMs);
      r = at < _fillMs ? at / _fillMs : 1;
    }
    final theme = Theme.of(context);
    final percent = '${(r * 100).round()}%';
    // a label of its own, the ratio the gauges write (null), or none
    final (gaugeLabel, lineLabel) = switch (o.choice<String>('label')) {
      'own' => (percent, 'used $percent'),
      'ratio' => (null, null),
      _ => ('', ''),
    };
    return SizedBox(
      width: _gaugeW,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        gap: 1,
        children: [
          SizedBox(
            height: 3,
            child: Gauge(
              ratio: r,
              label: gaugeLabel,
              style: o
                  .colorStyle(context, 'color')
                  .merge(Style(bg: theme.surface.bg)),
              labelStyle: const Style(attrs: Attr.bold),
            ),
          ),
          LineGauge(
            ratio: r,
            label: lineLabel,
            type: BorderType.values.byName(o.choice('line')),
            segmented: o.flag('segmented'),
            filledStyle: r > .9
                ? theme.error
                : r > .75
                ? theme.warning
                : theme.success,
            unfilledStyle: theme.border,
          ),
        ],
      ),
    );
  }),
  code: (o) {
    final state = o.flag('live')
        ? [
            'var _ratio = 0.0;',
            '',
            codeLine([
              '// from empty to full in ${_fillMs ~/ 1000} s, full for ',
              '${_holdMs ~/ 1000} s, and again',
            ]),
            ..._timer(_gaugeTick, [
              '(timer) {',
              codeLine([
                '  final ms = timer.tick * $_gaugeTick % ',
                '${_fillMs + _holdMs};',
              ]),
              '  setState(() => _ratio = ms < $_fillMs ? ms / $_fillMs : 1);',
              '},',
            ]),
          ]
        : ['final _ratio = ${_ratioLiteral(o.number('ratio'))};', ''];
    final label = o.choice<String>('label');
    return [
      ...state,
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      if (label == 'own') r"  final percent = '${(_ratio * 100).round()}%';",
      '  return SizedBox(',
      '    width: $_gaugeW,',
      '    child: Column(',
      '      mainAxisSize: .min,',
      '      crossAxisAlignment: .stretch,',
      '      gap: 1,',
      '      children: [',
      '        SizedBox(',
      '          height: 3,',
      '          child: Gauge(',
      '            ratio: _ratio,',
      if (label == 'own') '            label: percent,',
      if (label == 'none') "            label: '',",
      codeLine([
        '            style: theme.${o.color('color')}',
        '.merge(.new(bg: theme.surface.bg)),',
      ]),
      '            labelStyle: const .new(attrs: Attr.bold),',
      '          ),',
      '        ),',
      '        LineGauge(',
      '          ratio: _ratio,',
      if (label == 'own') r"          label: 'used $percent',",
      if (label == 'none') "          label: '',",
      '          type: .${o.label('line')},',
      if (o.flag('segmented')) '          segmented: true,',
      '          filledStyle: _ratio > .9',
      '              ? theme.error',
      '              : _ratio > .75',
      '              ? theme.warning',
      '              : theme.success,',
      '          unfilledStyle: theme.border,',
      '        ),',
      '      ],',
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);

// ------------------------------------------------------------ BarChart

/// Q1 a, Q1 b, Q2 a, …; or one group of the months, January first.
const _base = [4.0, 7.0, 6.0, 9.0, 3.0, 5.0];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];
const _barTick = 100;

/// Whether the bars are in one group, the months', not in three of two.
bool _single(Options o) => o.choice<String>('groups') == 'single';

/// The bars' width: the option's up, across the widest whose six bars
/// fit [room], with the three groups' labels unless [_single].
int _barWidth(Options o, int room) => o.choice<String>('direction') == 'up'
    ? o.choice<int>('barWidth')
    : math.max(
        1,
        math.min(o.choice<int>('barWidth'), (room - (_single(o) ? 0 : 3)) ~/ 6),
      );

/// The chart's size in [room].
(int, int) _barSize(Options o, int room) {
  final bw = _barWidth(o, room);
  if (o.choice<String>('direction') == 'up') {
    return (
      _single(o) ? 6 * bw + 5 : 3 * (2 * bw + 1) + 2 * 2,
      math.max(5, math.min(10, room)),
    );
  }
  return (40, _single(o) ? 6 * bw : 3 * 2 * bw + 3);
}

final _barChart = GalleryPage(
  group: 'Data',
  title: 'BarChart',
  options: const [
    ChoiceOption(
      'direction',
      'direction',
      values: ['up', 'across'],
      labels: ['vertical', 'horizontal'],
    ),
    ChoiceOption('barWidth', 'bar width', values: [1, 2, 3], initial: 3),
    ChoiceOption('groups', 'bars', values: ['grouped', 'single']),
    SwitchOption('live', 'live', initial: true),
  ],
  build: (context, o) => _inRoom(
    (room) => Timed((context, ms, wake) {
      final theme = Theme.of(context);
      final t = o.flag('live')
          ? _tick(ms, _barTick, wake) * _barTick / 1000
          : 0;
      final values = o.flag('live')
          ? [
              for (final (k, v) in _base.indexed)
                v + math.sin(t * 1.3 + k * 1.7),
            ]
          : _base;
      Bar bar(int k, String label, [Style style = const Style()]) => Bar(
        values[k],
        label: label,
        text: '${values[k].round()}',
        style: style,
      );
      final up = o.choice<String>('direction') == 'up';
      final (w, h) = _barSize(o, room);
      return SizedBox(
        width: w,
        height: h,
        child: BarChart(
          direction: up ? Axis.vertical : Axis.horizontal,
          barWidth: _barWidth(o, room),
          barGap: up ? 1 : 0,
          groupGap: up ? 2 : 1,
          max: 10,
          barStyle: theme.primary,
          valueStyle: const Style(attrs: Attr.bold),
          labelStyle: theme.muted,
          groups: _single(o)
              ? [
                  BarGroup([
                    for (final (k, month) in _months.indexed) bar(k, month),
                  ]),
                ]
              : [
                  for (final (g, label) in ['Q1', 'Q2', 'Q3'].indexed)
                    BarGroup([
                      bar(2 * g, 'a'),
                      bar(2 * g + 1, 'b', theme.accent),
                    ], label: label),
                ],
        ),
      );
    }),
  ),
  codeIn: (o, room) {
    final up = o.choice<String>('direction') == 'up';
    final (w, h) = _barSize(o, room.height);
    final live = o.flag('live');
    final single = _single(o);
    return [
      'const _base = [${_base.map((v) => v.toStringAsFixed(1)).join(', ')}];',
      if (single) 'const _months = [${_months.map((m) => "'$m'").join(', ')}];',
      if (live) ...[
        'var _t = 0.0; // seconds',
        '',
        ..._timer(_barTick, ['(_) => setState(() => _t += .1),']),
      ] else
        '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      if (live) ...[
        '  final values = [',
        '    for (final (k, v) in _base.indexed) v + sin(_t * 1.3 + k * 1.7),',
        '  ];',
      ] else
        '  const values = _base;',
      '  Bar bar(int k, String label, [Style style = const Style()]) =>',
      codeLine([
        r"      Bar(values[k], label: label, text: '${values[k].round()}', ",
        'style: style);',
      ]),
      '  return SizedBox(',
      '    width: $w,',
      '    height: $h,',
      '    child: BarChart(',
      '      direction: .${up ? 'vertical' : 'horizontal'},',
      '      barWidth: ${_barWidth(o, room.height)},',
      if (!up) '      barGap: 0,',
      if (!single) '      groupGap: ${up ? 2 : 1},',
      '      max: 10,',
      '      barStyle: theme.primary,',
      '      valueStyle: const .new(attrs: Attr.bold),',
      '      labelStyle: theme.muted,',
      '      groups: [',
      if (single) ...[
        '        BarGroup([',
        '          for (final (k, month) in _months.indexed) bar(k, month),',
        '        ]),',
      ] else ...[
        "        for (final (g, label) in ['Q1', 'Q2', 'Q3'].indexed)",
        '          BarGroup(',
        "            [bar(2 * g, 'a'), bar(2 * g + 1, 'b', theme.accent)],",
        '            label: label,',
        '          ),',
      ],
      '      ],',
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);

// ------------------------------------------------------------ Chart

/// The glyph of the custom marker.
const _customMarker = '*';

/// twk's markers, by the name the options give them, and one of a glyph's
/// own.
final _markers = <String, Marker>{
  'braille': Marker.braille,
  'halfBlock': Marker.halfBlock,
  'quadrant': Marker.quadrant,
  'sextant': Marker.sextant,
  'octant': Marker.octant,
  'block': Marker.block,
  'dot': Marker.dot,
  'bar': Marker.bar,
  'custom': Marker.custom(_customMarker),
};

/// The Code's marker of the options [o]: `.braille`, `.custom('*')`.
String _markerCode(Options o) => o.label('marker') == 'custom'
    ? ".custom('$_customMarker')"
    : '.${o.label('marker')}';

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
const _waveTick = 50;

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
  build: (context, o) => _inRoom(
    (room) => Timed((context, ms, wake) {
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

// ------------------------------------------------------------ DotCanvas

/// A turn of the hand, in ms.
const _spinMs = 6000;

final _dotCanvas = GalleryPage(
  group: 'Data',
  title: 'DotCanvas',
  options: [
    ChoiceOption('marker', 'marker', values: _markers.keys.toList()),
    const SwitchOption('live', 'live', initial: true),
  ],
  build: (context, o) => _inRoom(
    (room) => Timed((context, ms, wake) {
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

// ------------------------------------------------------------ Calendar

final _today = DateTime(2026, 10, 19);

/// The days of October 2026 with a meeting, which the marked days show.
const _meetings = {6, 13, 22, 27};

/// Whether [date] has a meeting.
bool _meeting(DateTime date) =>
    date.year == 2026 && date.month == 10 && _meetings.contains(date.day);

final _calendar = GalleryPage(
  group: 'Data',
  title: 'Calendar',
  options: const [
    ChoiceOption(
      'firstWeekday',
      'first day',
      values: [DateTime.monday, DateTime.sunday],
      labels: ['monday', 'sunday'],
    ),
    SwitchOption('weeks', 'week numbers'),
    SwitchOption('outside', 'outside days'),
    SwitchOption('marked', 'marked days'),
  ],
  build: (context, o) => _Month(
    firstWeekday: o.choice('firstWeekday'),
    weeks: o.flag('weeks'),
    outside: o.flag('outside'),
    marked: o.flag('marked'),
  ),
  // the title, the weekdays, six weeks, a gap and the line under it,
  // whatever the month
  heightIn: (o, room) => 10,
  code: (o) => [
    'DateTime? _selected;',
    '',
    if (o.flag('marked')) ...[
      '/// The days of October 2026 with a meeting.',
      'static const _meetings = {${_meetings.join(', ')}};',
      '',
      'static bool _meeting(DateTime date) =>',
      codeLine([
        '    date.year == 2026 && date.month == 10 && ',
        '_meetings.contains(date.day);',
      ]),
      '',
    ],
    '@override',
    'Widget build(BuildContext context) => Column(',
    '  mainAxisSize: .min,',
    '  crossAxisAlignment: .start,',
    '  gap: 1,',
    '  children: [',
    '    Calendar(',
    '      today: DateTime(2026, 10, 19),',
    if (o.choice<int>('firstWeekday') == DateTime.sunday)
      '      firstWeekday: DateTime.sunday,',
    if (o.flag('weeks')) '      showWeekNumbers: true,',
    if (o.flag('outside')) '      showOutsideDays: true,',
    if (o.flag('marked')) ...[
      '      dayStyle: (date) =>',
      '          _meeting(date) ? Theme.of(context).warning : null,',
    ],
    '      onSelected: (date) => setState(() => _selected = date),',
    '    ),',
    '    Text.rich([',
    "      Span('selected: ', Theme.of(context).muted),",
    '      switch (_selected) {',
    "        null => Span('nothing', Theme.of(context).muted),",
    '        final date => Span(date.toIso8601String().substring(0, 10)),',
    '      },',
    '    ]),',
    '  ],',
    ');',
  ].join('\n'),
);

/// A month to pick a day of, and the day picked.
final class _Month extends StatefulWidget {
  const _Month({
    required this.firstWeekday,
    required this.weeks,
    required this.outside,
    required this.marked,
  });

  final int firstWeekday;
  final bool weeks;
  final bool outside;
  final bool marked;

  @override
  State<_Month> createState() => _MonthState();
}

final class _MonthState extends State<_Month> {
  // kept in the page's state while the gallery runs
  late final Map<String, Object?> _kept = PageControl.of(context).state;
  late final _controller =
      (_kept['calendar'] ??= CalendarController(cursor: _today))
          as CalendarController;
  int get _picked => _kept['picked'] as int? ?? 0;

  @override
  Widget build(BuildContext context) {
    final selected = _controller.selected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Calendar(
          controller: _controller,
          today: _today,
          firstWeekday: widget.firstWeekday,
          showWeekNumbers: widget.weeks,
          showOutsideDays: widget.outside,
          dayStyle: widget.marked
              ? (date) => _meeting(date) ? Theme.of(context).warning : null
              : null,
          onSelected: (date) => setState(() => _kept['picked'] = _picked + 1),
        ),
        LitLine([
          ('selected: ', true),
          (
            selected?.toIso8601String().substring(0, 10) ?? 'nothing',
            selected == null,
          ),
        ], serial: _picked),
      ],
    );
  }
}

// ------------------------------------------------------------ Table

typedef _File = (String, int, double);

/// The five files.
const _files = <_File>[
  ('box.dart', 412, .9),
  ('text.dart', 230, .75),
  ('flex.dart', 388, .6),
  ('grid.dart', 520, .4),
  ('stack.dart', 145, 1.0),
];

const _many = 10000;

/// The lines a table draws between its columns and under its header.
const _borders = ['none', 'single', 'rounded', 'double', 'heavy', 'ascii'];
const _tableW = 50;
const _gap = 3;

/// 10 000 files, each made as the table reads it.
final class _ManyFiles extends TableSource<_File> {
  @override
  int get rowCount => _many;

  @override
  _File rowAt(int index) => (
    'file_${'$index'.padLeft(4, '0')}.dart',
    index * 7919 % 900 + 20,
    index * 37 % 101 / 100,
  );
}

/// How much of a file its tests cover, as a line in the colours of its
/// row: the selection's and the cursor's, which the table gives a widget
/// cell's text (DefaultTextStyle).
final class _Covered extends StatelessWidget {
  const _Covered(this.ratio);

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LineGauge(
      ratio: ratio,
      label: '${(ratio * 100).round()}%'.padLeft(4),
      type: BorderType.heavy,
      style: DefaultTextStyle.of(context),
      filledStyle: theme.primary,
      unfilledStyle: theme.border,
    );
  }
}

/// The SizedBox's height: the files under the header and its line, or 12
/// rows where the room has them.
int _tableHeight(Options o, int room) => o.choice<int>('rows') == _many
    ? math.max(5, math.min(12, room))
    : _files.length +
          (!o.flag('header')
              ? 0
              : o.choice<String>('border') == 'none'
              ? 1
              : 2);

/// The Code's data: the files as a const list, the 10 000 as a source.
String _fraction(double v) => v == v.roundToDouble()
    ? v.toStringAsFixed(1)
    : '$v'.replaceFirst('0.', '.');

final List<String> _tableCode = [
  'const _files = [',
  for (final (name, lines, covered) in _files)
    "  ('$name', $lines, ${_fraction(covered)}),",
  '];',
];

const _manyCode = [
  '/// 10 000 files, each made as the table reads it.',
  'final class _ManyFiles extends TableSource<(String, int, double)> {',
  '  @override',
  '  int get rowCount => $_many;',
  '',
  '  @override',
  '  (String, int, double) rowAt(int index) => (',
  r"    'file_${'$index'.padLeft(4, '0')}.dart',",
  '    index * 7919 % 900 + 20,',
  '    index * 37 % 101 / 100,',
  '  );',
  '}',
];

const _coveredCode = [
  '/// How much of a file its tests cover, as a line in the colours of its',
  "/// row: the selection's and the cursor's, which the table gives a",
  "/// widget cell's text (DefaultTextStyle).",
  'final class _Covered extends StatelessWidget {',
  '  const _Covered(this.ratio);',
  '',
  '  final double ratio;',
  '',
  '  @override',
  '  Widget build(BuildContext context) {',
  '    final theme = Theme.of(context);',
  '    return LineGauge(',
  '      ratio: ratio,',
  r"      label: '${(ratio * 100).round()}%'.padLeft(4),",
  '      type: .heavy,',
  '      style: DefaultTextStyle.of(context),',
  '      filledStyle: theme.primary,',
  '      unfilledStyle: theme.border,',
  '    );',
  '  }',
  '}',
];

final _table = GalleryPage(
  group: 'Data',
  title: 'Table',
  options: const [
    ChoiceOption(
      'selection',
      'selection',
      values: ['none', 'row', 'cell'],
      initial: 'row',
    ),
    ChoiceOption('border', 'border', values: _borders, initial: 'single'),
    SwitchOption('header', 'header', initial: true),
    ChoiceOption(
      'rows',
      'rows',
      values: [5, _many],
      labels: ['5', '10 000'],
    ),
  ],
  build: (context, o) => _inRoom((room) {
    final control = PageControl.of(context);
    final kept = control.state;
    final many = o.choice<int>('rows') == _many;
    // a controller for each kind of rows, kept while the gallery runs: the
    // row selected, the order, the widths
    final controller =
        (kept[many ? 'many' : 'files'] ??= TableController(
              selectedKey: many ? 0 : 'box.dart',
            ))
            as TableController;
    final columns = [
      TableColumn<_File>(
        title: 'name',
        cell: (row) => TableCell(row.$1),
        compare: (a, b) => a.$1.compareTo(b.$1),
      ),
      TableColumn<_File>(
        title: 'lines',
        align: TextAlign.right,
        cell: (row) => TableCell.rich(['${row.$2}'.bold]),
        compare: (a, b) => a.$2.compareTo(b.$2),
      ),
      TableColumn<_File>(
        title: 'covered',
        width: const GridTrack.fr(1),
        cell: (row) => TableCell.widget(_Covered(row.$3)),
      ),
    ];
    final selection = TableSelection.values.byName(o.choice('selection'));
    final border = BorderType.values.byName(o.choice('border'));
    void activated(_File row) => control.toast('Activated ${row.$1}');
    return SizedBox(
      width: _tableW,
      height: _tableHeight(o, room),
      child: many
          ? Table<_File>.source(
              key: const ValueKey('many'),
              source: (kept['source'] ??= _ManyFiles()) as _ManyFiles,
              controller: controller,
              selection: selection,
              border: border,
              showHeader: o.flag('header'),
              columnGap: _gap,
              onActivated: activated,
              columns: columns,
            )
          : Table<_File>(
              key: const ValueKey('files'),
              rows: _files,
              rowKey: (row) => row.$1,
              controller: controller,
              selection: selection,
              border: border,
              showHeader: o.flag('header'),
              columnGap: _gap,
              onActivated: activated,
              columns: columns,
            ),
    );
  }),
  codeIn: (o, room) {
    final many = o.choice<int>('rows') == _many;
    final none = o.choice<String>('selection') == 'none';
    // the row selected at first, which none has not
    final own = [
      if (many) 'final _files = _ManyFiles();',
      if (!none)
        codeLine([
          'final _controller = TableController(selectedKey: ',
          "${many ? '0' : "'box.dart'"});",
        ]),
    ];
    final disposed = [
      if (many) '  _files.dispose();',
      if (!none) '  _controller.dispose();',
    ];
    return [
      ...own,
      if (disposed.isNotEmpty) ...[
        '',
        '@override',
        'void dispose() {',
        ...disposed,
        '  super.dispose();',
        '}',
      ],
      if (own.isNotEmpty) '',
      '@override',
      'Widget build(BuildContext context) => SizedBox(',
      '  width: $_tableW,',
      '  height: ${_tableHeight(o, room.height)},',
      '  child: Table<(String, int, double)>${many ? '.source' : ''}(',
      '    ${many ? 'source' : 'rows'}: _files,',
      if (!many) r'    rowKey: (row) => row.$1,',
      if (!none) '    controller: _controller,',
      '    selection: .${o.label('selection')},',
      '    border: .${o.label('border')},',
      if (!o.flag('header')) '    showHeader: false,',
      '    columnGap: $_gap,',
      r"    onActivated: (row) => showToast(context, 'Activated ${row.$1}'),",
      '    columns: [',
      '      TableColumn(',
      "        title: 'name',",
      r'        cell: (row) => TableCell(row.$1),',
      r'        compare: (a, b) => a.$1.compareTo(b.$1),',
      '      ),',
      '      TableColumn(',
      "        title: 'lines',",
      '        align: .right,',
      r"        cell: (row) => TableCell.rich(['${row.$2}'.bold]),",
      r'        compare: (a, b) => a.$2.compareTo(b.$2),',
      '      ),',
      '      TableColumn(',
      "        title: 'covered',",
      '        width: const .fr(1),',
      r'        cell: (row) => TableCell.widget(_Covered(row.$3)),',
      '      ),',
      '    ],',
      '  ),',
      ');',
      '',
      ...(many ? _manyCode : _tableCode),
      '',
      ..._coveredCode,
    ].join('\n');
  },
);

// ------------------------------------------------------------ TreeView

const _roots = ['lib', 'test', 'README.md', 'pubspec.yaml'];
const _src = [
  'lib/src/box.dart',
  'lib/src/flex.dart',
  'lib/src/table.dart',
  'lib/src/text.dart',
];
const _treeW = 40;

final _treeView = GalleryPage(
  group: 'Data',
  title: 'TreeView',
  options: const [
    SwitchOption('guides', 'guides', initial: true),
    ChoiceOption('load', 'test/', values: ['loads', 'fails']),
  ],
  build: (context, o) => _inRoom((room) {
    final kept = PageControl.of(context).state;
    // kept while the gallery runs: what is expanded and selected
    final controller =
        (kept['tree'] ??= TreeController(
              expanded: ['lib', 'lib/src'],
              selectedKey: 'lib/src/table.dart',
            ))
            as TreeController;
    final fails = o.choice<String>('load') == 'fails';
    return SizedBox(
      width: _treeW,
      height: math.max(4, math.min(12, room)),
      child: TreeView<String>(
        roots: _roots,
        controller: controller,
        showGuides: o.flag('guides'),
        hasChildren: (path) => !path.contains('.'),
        children: (path) => switch (path) {
          'lib' => const ['lib/src', 'lib/twk.dart'],
          'lib/src' => _src,
          'test' => Future.delayed(
            const Duration(seconds: 1),
            () => fails
                ? throw StateError('test/ is not readable')
                : const ['test/box_test.dart', 'test/table_test.dart'],
          ),
          _ => const [],
        },
        label: (context, entry) => Text(entry.node.split('/').last),
      ),
    );
  }),
  codeIn: (o, room) => [
    'final _controller = TreeController(',
    "  expanded: ['lib', 'lib/src'],",
    "  selectedKey: 'lib/src/table.dart',",
    ');',
    '',
    '@override',
    'Widget build(BuildContext context) => SizedBox(',
    '  width: $_treeW,',
    '  height: ${_rowsIn(room, 12, 4)},',
    '  child: TreeView<String>(',
    '    roots: const [${_roots.map((r) => "'$r'").join(', ')}],',
    '    controller: _controller,',
    if (!o.flag('guides')) '    showGuides: false,',
    "    hasChildren: (path) => !path.contains('.'),",
    '    children: (path) => switch (path) {',
    "      'lib' => const ['lib/src', 'lib/twk.dart'],",
    "      'lib/src' => const [",
    for (final f in _src) "        '$f',",
    '      ],',
    "      'test' => Future.delayed(",
    '        const Duration(seconds: 1),',
    if (o.choice<String>('load') == 'fails')
      "        () => throw StateError('test/ is not readable'),"
    else
      "        () => const ['test/box_test.dart', 'test/table_test.dart'],",
    '      ),',
    '      _ => const [],',
    '    },',
    "    label: (context, entry) => Text(entry.node.split('/').last),",
    '  ),',
    ');',
  ].join('\n'),
);

// ------------------------------------------------------------ TreeTable

const _ttRoots = ['lib', 'test', 'README.md', 'pubspec.yaml'];
const _ttChildren = {
  'lib': ['lib/src', 'lib/twk.dart'],
  'lib/src': [
    'lib/src/box.dart',
    'lib/src/flex.dart',
    'lib/src/table.dart',
    'lib/src/text.dart',
  ],
  'test': ['test/box_test.dart', 'test/table_test.dart'],
};
const _ttSizes = {
  'lib/src/box.dart': 412,
  'lib/src/flex.dart': 388,
  'lib/src/table.dart': 960,
  'lib/src/text.dart': 230,
  'lib/twk.dart': 48,
  'test/box_test.dart': 310,
  'test/table_test.dart': 655,
  'README.md': 120,
  'pubspec.yaml': 22,
};
const _ttW = 40;
const _ttGap = 3;

/// A file's lines, or those of the files under a directory.
int _ttLines(String path) =>
    _ttSizes[path] ??
    (_ttChildren[path] ?? const []).fold(0, (n, p) => n + _ttLines(p));

String _quoted(List<String> list) => list.map((f) => "'$f'").join(', ');

final _treeTable = GalleryPage(
  group: 'Data',
  title: 'TreeTable',
  options: const [
    ChoiceOption(
      'selection',
      'selection',
      values: ['none', 'row', 'cell'],
      initial: 'row',
    ),
    ChoiceOption('border', 'border', values: _borders, initial: 'single'),
    SwitchOption('guides', 'guides', initial: true),
  ],
  build: (context, o) => _inRoom((room) {
    final kept = PageControl.of(context).state;
    // kept while the gallery runs: what is expanded and selected, the
    // order and the widths
    final controller =
        (kept['tree'] ??= TreeController(
              expanded: ['lib', 'lib/src'],
              selectedKey: 'lib/src/table.dart',
            ))
            as TreeController;
    final table = (kept['table'] ??= TableController()) as TableController;
    final selection = TableSelection.values.byName(o.choice('selection'));
    final cell = selection == TableSelection.cell;
    return PageHints(
      hints: selection == TableSelection.none
          ? const [('↑↓', 'scroll'), ('s < >', 'sort'), ('shift+←→', 'width')]
          : [
              (cell ? '←↑↓→' : '↑↓', 'select'),
              if (!cell) ('←→', 'collapse, expand'),
              ('enter', 'toggle'),
              ('s < >', 'sort'),
              ('shift+←→', 'width'),
            ],
      child: SizedBox(
        width: _ttW,
        height: math.max(4, math.min(12, room)),
        child: TreeTable<String>(
          roots: _ttRoots,
          controller: controller,
          tableController: table,
          selection: selection,
          border: BorderType.values.byName(o.choice('border')),
          columnGap: _ttGap,
          showGuides: o.flag('guides'),
          hasChildren: (path) => !path.contains('.'),
          children: (path) => _ttChildren[path] ?? const [],
          columns: [
            TableColumn(
              title: 'name',
              width: const GridTrack.fr(1),
              cell: (path) => TableCell(path.split('/').last),
              compare: (a, b) => a.compareTo(b),
            ),
            TableColumn(
              title: 'lines',
              align: TextAlign.right,
              cell: (path) => TableCell('${_ttLines(path)}'),
              compare: (a, b) => _ttLines(a).compareTo(_ttLines(b)),
            ),
          ],
        ),
      ),
    );
  }),
  codeIn: (o, room) => [
    'final _controller = TreeController(',
    "  expanded: ['lib', 'lib/src'],",
    "  selectedKey: 'lib/src/table.dart',",
    ');',
    '',
    '@override',
    'void dispose() {',
    '  _controller.dispose();',
    '  super.dispose();',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) => SizedBox(',
    '  width: $_ttW,',
    '  height: ${_rowsIn(room, 12, 4)},',
    '  child: TreeTable<String>(',
    '    roots: const [${_quoted(_ttRoots)}],',
    '    controller: _controller,',
    '    selection: .${o.label('selection')},',
    if (o.choice<String>('border') != 'none')
      '    border: .${o.label('border')},',
    '    columnGap: $_ttGap,',
    if (!o.flag('guides')) '    showGuides: false,',
    "    hasChildren: (path) => !path.contains('.'),",
    '    children: (path) => _children[path] ?? const [],',
    '    columns: [',
    '      TableColumn(',
    "        title: 'name',",
    '        width: const .fr(1),',
    "        cell: (path) => TableCell(path.split('/').last),",
    '        compare: (a, b) => a.compareTo(b),',
    '      ),',
    '      TableColumn(',
    "        title: 'lines',",
    '        align: .right,',
    r"        cell: (path) => TableCell('${_lines(path)}'),",
    '        compare: (a, b) => _lines(a).compareTo(_lines(b)),',
    '      ),',
    '    ],',
    '  ),',
    ');',
    '',
    'const _children = {',
    "  'lib': ['lib/src', 'lib/twk.dart'],",
    "  'lib/src': [",
    for (final f in _ttChildren['lib/src']!) "    '$f',",
    '  ],',
    "  'test': [${_quoted(_ttChildren['test']!)}],",
    '};',
    '',
    'const _sizes = {',
    for (final MapEntry(:key, :value) in _ttSizes.entries) "  '$key': $value,",
    '};',
    '',
    "/// A file's lines, or those of the files under a directory.",
    'int _lines(String path) =>',
    '    _sizes[path] ??',
    '    (_children[path] ?? const []).fold(0, (n, p) => n + _lines(p));',
  ].join('\n'),
);

// ------------------------------------------------------------ TaskList

/// What each step of the build takes: fetch, core, widgets, tests, deploy.
const _buildMs = [1400, 1200, 1600, 2400, 1200];

/// The tests, failing.
const _failMs = 1500;

/// Done, before it runs again.
const _restMs = 3000;

/// What each step of a run takes, its rest the last: 0 fetch, 1 and 2
/// compile, 3 test, 4 deploy, then the rest (failed: no deploy).
List<int> _runMs({required bool failed}) => [
  for (final (i, ms) in _buildMs.indexed)
    if (!failed || i < 4) ...[if (failed && i == 3) _failMs else ms],
  _restMs,
];

/// The steps each task of the run goes from and to: the fetch, the
/// compile, its two files, the tests and the deploy.
const _taskSpans = [(0, 1), (1, 3), (1, 2), (2, 3), (3, 4), (4, 5)];

/// The tasks of the Code's `_tasks` at [step]: 0 fetch, 1 and 2 compile, 3
/// test, 4 deploy, 5 done; [into] ms into the run whose steps start at
/// [starts]. Each is given its time on the gallery's clock, which a route's
/// `t=` stops: the list's own, from the frame it saw a task running, would
/// go on.
List<TaskItem> _liveTasks(
  int step,
  int into,
  List<int> starts, {
  required bool failed,
}) {
  // a task that runs from step [from] to step [to], failing with [fails]
  TaskItem task(
    String label,
    int from,
    int to, {
    bool fails = false,
    List<TaskItem> children = const [],
  }) {
    final (status, ms) = step < from
        ? (TaskStatus.pending, null)
        : step < to
        ? (TaskStatus.running, into - starts[from])
        : (
            fails ? TaskStatus.failed : TaskStatus.done,
            starts[to] - starts[from],
          );
    return TaskItem(
      label,
      status: status,
      elapsed: ms == null ? null : Duration(milliseconds: ms),
      children: children,
    );
  }

  return [
    task('Fetch dependencies', 0, 1),
    task(
      'Compile',
      1,
      3,
      children: [
        task('lib/core.dart', 1, 2),
        task('lib/widgets.dart', 2, 3),
      ],
    ),
    if (failed) ...[
      task('Run the tests', 3, 4, fails: true),
      TaskItem(
        'Deploy',
        status: step < 4 ? TaskStatus.pending : TaskStatus.skipped,
      ),
    ] else ...[
      task('Run the tests', 3, 4),
      task('Deploy', 4, 5),
    ],
  ];
}

/// The tasks of a build at [step]: those before it done, it running, or
/// failed and those after it skipped, and those after it pending; the task
/// running has run [ran].
List<TaskItem> _stepTasks(int step, Duration ran, {required bool failed}) {
  TaskStatus at(int i) => i < step
      ? TaskStatus.done
      : i > step
      ? (failed ? TaskStatus.skipped : TaskStatus.pending)
      : (failed ? TaskStatus.failed : TaskStatus.running);
  Duration? time(int i) => at(i) == TaskStatus.running ? ran : null;
  return [
    TaskItem('Fetch dependencies', status: at(0), elapsed: time(0)),
    TaskItem(
      'Compile',
      status: at(1),
      elapsed: time(1),
      children: [
        TaskItem(
          'lib/core.dart',
          status: step > 0 ? TaskStatus.done : TaskStatus.pending,
        ),
        TaskItem('lib/widgets.dart', status: at(1), elapsed: time(1)),
      ],
    ),
    TaskItem('Run the tests', status: at(2), elapsed: time(2)),
    TaskItem('Deploy', status: at(3), elapsed: time(3)),
  ];
}

/// Asks [wake] for the gallery time at which a task running since [since]
/// has run a second more than at [ms], as the list moves its time on.
void _wakeAtSecond(int since, int ms, void Function(int) wake) =>
    wake(since + ((ms - since) ~/ 1000 + 1) * 1000);

/// The stage of the TaskList page, which keeps the gallery time the step
/// it shows was chosen at, as the design's state does.
final class _TaskStage extends StatefulWidget {
  const _TaskStage(this.o);

  final Options o;

  @override
  State<_TaskStage> createState() => _TaskStageState();
}

final class _TaskStageState extends State<_TaskStage> {
  // the step shown and failed, and the gallery time it was chosen at
  Object? _stepKey;
  var _since = 0;

  @override
  Widget build(BuildContext context) => Timed((context, ms, wake) {
    final o = widget.o;
    final step = o.choice<Object>('step');
    final failed = o.flag('failed');
    List<TaskItem> tasks;
    if (step is int) {
      // the task it runs has run since the step was chosen
      final key = (step, failed);
      if (_stepKey != key) {
        _stepKey = key;
        _since = ms;
      }
      tasks = _stepTasks(
        step,
        Duration(milliseconds: ms - _since),
        failed: failed,
      );
      if (!failed && step < 4) {
        _wakeAtSecond(_since, ms, wake);
      }
    } else {
      // the run, again and again, on the gallery's clock: the step it is
      // at, and a build at the next
      final run = _runMs(failed: failed);
      // where each step starts, ms into the run, and where it ends
      final starts = [0];
      for (final d in run) {
        starts.add(starts.last + d);
      }
      final into = ms % starts.last;
      final i = starts.lastIndexWhere((s) => s <= into);
      wake(ms - into + starts[i + 1]);
      final step = failed && i >= 4 ? 5 : i;
      tasks = _liveTasks(step, into, starts, failed: failed);
      // what runs moves its time on at each second from its start
      for (final (from, to) in _taskSpans) {
        if (from <= step && step < to) {
          _wakeAtSecond(ms - into + starts[from], ms, wake);
        }
      }
    }
    return SizedBox(
      width: 40,
      child: TaskList(
        // a list of its own for each step: its tasks done show no time
        key: step is int ? ValueKey((step, failed)) : null,
        spinner: _spinners[o.choice<String>('spinner')]!,
        showElapsed: o.flag('elapsed'),
        tasks: tasks,
      ),
    );
  });
}

const Map<String, SpinnerFrames> _spinners = {
  'dots': SpinnerFrames.dots,
  'line': SpinnerFrames.line,
  'arc': SpinnerFrames.arc,
};

final _taskList = GalleryPage(
  group: 'Data',
  title: 'TaskList',
  options: const [
    ChoiceOption(
      'step',
      'step',
      values: ['live', 0, 1, 2, 3, 4],
      labels: ['live', 'fetch', 'compile', 'test', 'deploy', 'done'],
    ),
    SwitchOption('failed', 'failed'),
    SwitchOption('elapsed', 'elapsed', initial: true),
    ChoiceOption('spinner', 'spinner', values: ['dots', 'line', 'arc']),
  ],
  build: (context, o) => _TaskStage(o),
  code: (o) {
    final step = o.choice<Object>('step');
    final failed = o.flag('failed');
    final spinner = o.choice<String>('spinner');
    final tasks = step is int ? '_build($step, failed: $failed)' : '_tasks';
    final list = [
      '@override',
      'Widget build(BuildContext context) => SizedBox(',
      '  width: 40,',
      '  child: TaskList(',
      if (step is int) ...[
        '    // a list of its own for each step: its tasks done show no time',
        '    key: const ValueKey(($step, $failed)),',
      ],
      if (spinner != 'dots') '    spinner: SpinnerFrames.$spinner,',
      if (!o.flag('elapsed')) '    showElapsed: false,',
      '    tasks: $tasks,',
      '  ),',
      ');',
    ];
    if (step is int) {
      return [
        ...list,
        '',
        codeLine([
          '/// The tasks of a build at [step]: those before it done, it ',
          'running, or',
        ]),
        '/// failed and those after it skipped, and those after it pending.',
        'List<TaskItem> _build(int step, {required bool failed}) {',
        '  TaskStatus at(int i) => i < step',
        '      ? .done',
        '      : i > step',
        '      ? (failed ? .skipped : .pending)',
        '      : (failed ? .failed : .running);',
        '  return [',
        "    TaskItem('Fetch dependencies', status: at(0)),",
        '    TaskItem(',
        "      'Compile',",
        '      status: at(1),',
        '      children: [',
        codeLine([
          "        TaskItem('lib/core.dart', status: step > 0 ? .done : ",
          '.pending),',
        ]),
        "        TaskItem('lib/widgets.dart', status: at(1)),",
        '      ],',
        '    ),',
        "    TaskItem('Run the tests', status: at(2)),",
        "    TaskItem('Deploy', status: at(3)),",
        '  ];',
        '}',
      ].join('\n');
    }
    final next = failed ? 'step < 4 ? step : 5' : 'step';
    return [
      '// what runs: 0 fetch, 1 and 2 compile, 3 test, 4 deploy, 5 done',
      'var _step = 0;',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  unawaited(_run());',
      '}',
      '',
      '/// The build, again and again: each step a while, then the next.',
      'Future<void> _run() async {',
      '  const ms = [${_runMs(failed: failed).join(', ')}];',
      '  while (mounted) {',
      '    for (var step = 0; step < ms.length && mounted; step++) {',
      '      setState(() => _step = $next);',
      '      await Future<void>.delayed(Duration(milliseconds: ms[step]));',
      '    }',
      '  }',
      '}',
      '',
      'List<TaskItem> get _tasks {',
      '  // a task that runs from step [from] to step [to]',
      '  TaskStatus at(int from, int to) =>',
      '      _step < from ? .pending : (_step < to ? .running : .done);',
      '  return [',
      "    TaskItem('Fetch dependencies', status: at(0, 1)),",
      '    TaskItem(',
      "      'Compile',",
      '      status: at(1, 3),',
      '      children: [',
      "        TaskItem('lib/core.dart', status: at(1, 2)),",
      "        TaskItem('lib/widgets.dart', status: at(2, 3)),",
      '      ],',
      '    ),',
      if (failed) ...[
        '    TaskItem(',
        "      'Run the tests',",
        codeLine([
          '      status: _step < 3 ? .pending : (_step < 4 ? .running : ',
          '.failed),',
        ]),
        '    ),',
        "    TaskItem('Deploy', status: _step < 4 ? .pending : .skipped),",
      ] else ...[
        "    TaskItem('Run the tests', status: at(3, 4)),",
        "    TaskItem('Deploy', status: at(4, 5)),",
      ],
      '  ];',
      '}',
      '',
      ...list,
    ].join('\n');
  },
);

/// The pages of the Data group that draw, in the catalog's order.
final List<GalleryPage> dataPages = [
  _sparkline,
  _gauge,
  _barChart,
  _chart,
  _dotCanvas,
  _heatmap,
  _calendar,
  _table,
  _descriptionList,
  _treeView,
  _treeTable,
  _directoryTree,
  _taskList,
];

// ------------------------------------------------------------ DescriptionList

/// The rows of the DescriptionList page, as the Code writes them: a term
/// and its value, a group's title (no value), or the term of the status
/// and of the memory, whose values are widgets.
const List<(String, String?)> _described = [
  ('Status', null),
  ('IP Address', '192.168.1.42'),
  ('Uptime', '3 days, 4 hours'),
  ('Image', 'twk/server:0.1.0'),
  ('Limits', ''),
  ('CPU', '2 cores'),
  ('Memory', null),
  ('Restart policy', 'unless stopped, 5 times at most in a minute'),
];

final _descriptionList = GalleryPage(
  group: 'Data',
  title: 'DescriptionList',
  options: [
    SliderOption(
      'width',
      'width',
      min: 20,
      max: 60,
      initial: 44,
      format: (v) => '$v cells',
    ),
    const ChoiceOption('align', 'terms', values: ['left', 'center', 'right']),
    const ChoiceOption(
      'separator',
      'separator',
      values: [':', ''],
      labels: ['colon', 'none'],
    ),
    const SwitchOption('groups', 'groups', initial: true),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final groups = o.flag('groups');
    return SizedBox(
      width: o.number('width').toInt(),
      child: DescriptionList(
        termAlign: TextAlign.values.byName(o.choice('align')),
        separator: o.choice('separator'),
        items: [
          for (final (term, value) in _described)
            switch ((term, value)) {
              ('Status', _) => DescriptionItem(
                'Status',
                Text.rich([
                  Span('● ', theme.success),
                  const Span('Running (healthy)'),
                ]),
              ),
              ('Memory', _) => const DescriptionItem(
                'Memory',
                ProgressBar(value: 0.25),
              ),
              (_, '') when groups => DescriptionItem.group(term),
              (_, '') => null,
              (_, final String v) => DescriptionItem.text(term, v),
              _ => null,
            },
        ].nonNulls.toList(),
      ),
    );
  },
  code: (o) {
    final align = o.choice<String>('align');
    final separator = o.choice<String>('separator');
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: ${o.label('width')},',
      '  child: DescriptionList(',
      if (align != 'left') '    termAlign: .$align,',
      if (separator != ':') "    separator: '$separator',",
      '    items: [',
      for (final (term, value) in _described)
        ...switch ((term, value)) {
          ('Status', _) => [
            '      DescriptionItem(',
            "        'Status',",
            '        Text.rich([',
            "          Span('● ', theme.success),",
            "          const Span('Running (healthy)'),",
            '        ]),',
            '      ),',
          ],
          ('Memory', _) => [
            "      const DescriptionItem('Memory', ProgressBar(value: 0.25)),",
          ],
          (_, '') when o.flag('groups') => [
            "      const DescriptionItem.group('$term'),",
          ],
          (_, '') => const <String>[],
          (_, final String v) => _call(6, 'DescriptionItem.text', [
            "'$term'",
            "'$v'",
          ]),
          _ => const <String>[],
        },
      '    ],',
      '  ),',
      ');',
    ].join('\n');
  },
);

/// The lines of the call [head]([args]) at [indent], a comma after it: on
/// one line where it fits in 80 columns, else an argument a line.
List<String> _call(int indent, String head, List<String> args) {
  final pad = ' ' * indent;
  final one = '$pad$head(${args.join(', ')}),';
  if (one.length <= 80) {
    return [one];
  }
  return ['$pad$head(', for (final a in args) '$pad  $a,', '$pad),'];
}

// ------------------------------------------------------------ Heatmap

/// The last day the heatmaps show: the gallery's today.
final _heatEnd = DateTime(2026, 10, 19);

/// The weeks the activity heatmap shows.
const _heatWeeks = 20;

/// The commits of the day [i] days before [_heatEnd], as the Code's
/// `_commits` counts them: fewer at the weekends.
int _commitsOn(int i) {
  final weekend = DateTime(2026, 10, 19 - i).weekday > DateTime.friday;
  return (_noise(i) * (weekend ? 3 : 9)).floor();
}

/// How busy a server is in the hour [hour] of the day [day] of a week, from
/// 0 to 1, as the Code's `_load` says: more in the hours of work.
double _loadAt(int day, int hour) {
  final work = day < 5 && hour >= 9 && hour < 18;
  return (work ? .5 : .05) + _noise(day * 24 + hour) * (work ? .5 : .25);
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The dark green to light green of the colored scale.
const _greens = Gradient([Color.rgb(14, 68, 41), Color.rgb(57, 211, 83)]);

final _heatmap = GalleryPage(
  group: 'Data',
  title: 'Heatmap, ActivityHeatmap',
  options: [
    const ChoiceOption(
      'kind',
      'widget',
      values: ['activity', 'grid'],
      labels: ['ActivityHeatmap', 'Heatmap'],
    ),
    ChoiceOption(
      'firstWeekday',
      'first day',
      values: const [DateTime.monday, DateTime.sunday],
      labels: const ['monday', 'sunday'],
      disabled: (o) => o['kind'] != 'activity',
    ),
    const ChoiceOption('scale', 'scale', values: ['shades', 'colors']),
    const SwitchOption('legend', 'legend', initial: true),
    const ChoiceOption(
      'cell',
      'cell width',
      values: [2, 1],
      labels: ['2 columns', '1 column'],
    ),
  ],
  build: (context, o) => _Heat(
    activity: o.choice<String>('kind') == 'activity',
    firstWeekday: o.choice('firstWeekday'),
    colors: o.choice<String>('scale') == 'colors',
    legend: o.flag('legend'),
    cellWidth: o.choice('cell'),
  ),
  code: (o) {
    final activity = o.choice<String>('kind') == 'activity';
    final colors = o.choice<String>('scale') == 'colors';
    final cell = o.choice<int>('cell');
    final noise = [
      '',
      _noiseDoc,
      'static double _noise(int i) {',
      '  final s = sin(i * 91.345 + 3.1) * 43758.5453;',
      '  return s - s.floorToDouble();',
      '}',
    ];
    final scale = [
      if (colors) ...[
        '      scale: const .colors(',
        '        Gradient([Color.rgb(14, 68, 41), Color.rgb(57, 211, 83)]),',
        '      ),',
      ],
    ];
    final line = [
      '      Text.rich([',
      "        Span('selected: ', theme.muted),",
      '        if (_selected.isEmpty)',
      "          Span('nothing', theme.muted)",
      '        else',
      '          Span(_selected),',
      '      ]),',
    ];
    if (activity) {
      return [
        '/// The commits of each day of the last $_heatWeeks weeks: fewer at',
        '/// the weekends.',
        'static final _commits = {',
        '  for (var i = 0; i < ${_heatWeeks * 7}; i++)',
        '    DateTime(2026, 10, 19 - i): _count(i),',
        '};',
        '',
        'static int _count(int i) {',
        codeLine([
          '  final weekend = DateTime(2026, 10, 19 - i).weekday > ',
          'DateTime.friday;',
        ]),
        '  return (_noise(i) * (weekend ? 3 : 9)).floor();',
        '}',
        ...noise,
        '',
        "var _selected = '';",
        '',
        '@override',
        'Widget build(BuildContext context) {',
        '  final theme = Theme.of(context);',
        '  return Column(',
        '    mainAxisSize: .min,',
        '    crossAxisAlignment: .start,',
        '    gap: 1,',
        '    children: [',
        '      ActivityHeatmap(',
        '        counts: _commits,',
        '        end: DateTime(2026, 10, 19),',
        '        weeks: $_heatWeeks,',
        if (o.choice<int>('firstWeekday') == DateTime.sunday)
          '        firstWeekday: DateTime.sunday,',
        ..._indented(scale, 2),
        if (o.flag('legend')) '        showLegend: true,',
        if (cell != 2) '        cellWidth: $cell,',
        '        onSelected: (day) => setState(',
        '          () => _selected = day.toIso8601String().substring(0, 10),',
        '        ),',
        '      ),',
        ...line,
        '    ],',
        '  );',
        '}',
      ].join('\n');
    }
    return [
      'static const _days = [${_weekdays.map((d) => "'$d'").join(', ')}];',
      '',
      '/// How busy the server is in [hour] of [day], from 0 to 1: more in',
      '/// the hours of work.',
      'static double _load(int day, int hour) {',
      '  final work = day < 5 && hour >= 9 && hour < 18;',
      codeLine([
        '  return (work ? .5 : .05) + _noise(day * 24 + hour) * ',
        '(work ? .5 : .25);',
      ]),
      '}',
      ...noise,
      '',
      "var _selected = '';",
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      Heatmap(',
      '        rows: 7,',
      '        columns: 24,',
      '        value: _load,',
      '        min: 0,',
      '        max: 1,',
      ..._indented(scale, 2),
      '        rowLabels: _days,',
      '        columnLabels: [',
      '          for (var hour = 0; hour < 24; hour++)',
      r"            if (hour % 6 == 0) '$hour h' else '',",
      '        ],',
      if (cell != 2) '        cellWidth: $cell,',
      if (o.flag('legend')) '        showLegend: true,',
      '        tooltip: (day, hour) {',
      '          final percent = (_load(day, hour) * 100).round();',
      r"          return '${_days[day]} $hour:00, $percent %';",
      '        },',
      '        onSelected: (cell) => setState(',
      r"          () => _selected = '${_days[cell.$1]} ${cell.$2}:00',",
      '        ),',
      '      ),',
      ...line,
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

/// [lines], each [n] blanks further in.
List<String> _indented(List<String> lines, int n) => [
  for (final l in lines) '${' ' * n}$l',
];

/// The activity heatmap or the heatmap of a week's load, and the cell
/// selected last.
final class _Heat extends StatefulWidget {
  const _Heat({
    required this.activity,
    required this.firstWeekday,
    required this.colors,
    required this.legend,
    required this.cellWidth,
  });

  final bool activity;
  final int firstWeekday;
  final bool colors;
  final bool legend;
  final int cellWidth;

  @override
  State<_Heat> createState() => _HeatState();
}

final class _HeatState extends State<_Heat> {
  static final Map<DateTime, int> _commits = {
    for (var i = 0; i < _heatWeeks * 7; i++)
      DateTime(2026, 10, 19 - i): _commitsOn(i),
  };

  late final Map<String, Object?> _kept = PageControl.of(context).state;

  String get _selected => _kept['selected'] as String? ?? '';
  int get _serial => _kept['serial'] as int? ?? 0;

  void _select(String what) => setState(() {
    _kept['selected'] = what;
    _kept['serial'] = _serial + 1;
  });

  @override
  Widget build(BuildContext context) {
    final scale = widget.colors ? const HeatmapScale.colors(_greens) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        if (widget.activity)
          ActivityHeatmap(
            counts: _commits,
            end: _heatEnd,
            weeks: _heatWeeks,
            firstWeekday: widget.firstWeekday,
            scale: scale ?? ActivityHeatmap.defaultScale,
            showLegend: widget.legend,
            cellWidth: widget.cellWidth,
            onSelected: (day) =>
                _select(day.toIso8601String().substring(0, 10)),
          )
        else
          Heatmap(
            rows: 7,
            columns: 24,
            value: _loadAt,
            min: 0,
            max: 1,
            scale: scale ?? const HeatmapScale.shades(),
            rowLabels: _weekdays,
            columnLabels: [
              for (var hour = 0; hour < 24; hour++)
                if (hour % 6 == 0) '$hour h' else '',
            ],
            cellWidth: widget.cellWidth,
            showLegend: widget.legend,
            tooltip: (day, hour) {
              final percent = (_loadAt(day, hour) * 100).round();
              return '${_weekdays[day]} $hour:00, $percent %';
            },
            onSelected: (cell) =>
                _select('${_weekdays[cell.$1]} ${cell.$2}:00'),
          ),
        LitLine([
          ('selected: ', true),
          if (_selected.isEmpty) ('nothing', true) else (_selected, false),
        ], serial: _serial),
      ],
    );
  }
}

// ------------------------------------------------------------ DirectoryTree

/// The project the tree shows.
const _project = '/home/user/twk';

/// The files of the project and their sizes in bytes.
const _projectFiles = [
  ('lib/twk.dart', 312),
  ('lib/src/box.dart', 4210),
  ('lib/src/flex.dart', 9874),
  ('lib/src/table.dart', 18130),
  ('lib/src/text.dart', 2305),
  ('test/box_test.dart', 3102),
  ('test/table_test.dart', 6550),
  ('build/twk.js', 120400),
  ('.dart_tool/package_config.json', 2210),
  ('debug.log', 51200),
  ('README.md', 1204),
  ('pubspec.yaml', 220),
];

const _gitignore = r'build/\n*.log\n';

const _dirTreeW = 36;

/// The glyphs before a directory's name and a file's.
const _dirIcon = '📁';
const _fileIcon = '📄';

/// The rows of the tree in a room [room] rows high: 12, or those it has
/// but the two of the line under it, 2 at least.
int _treeRows(int room) => math.max(2, math.min(12, room - 2));

final _directoryTree = GalleryPage(
  group: 'Data',
  title: 'DirectoryTree',
  options: const [
    SwitchOption('hidden', 'hidden files'),
    SwitchOption('gitignore', '.gitignore', initial: true),
    SwitchOption('sizes', 'sizes'),
    SwitchOption('guides', 'guides'),
    ChoiceOption('icon', 'icons', values: ['none', 'glyphs']),
  ],
  build: (context, o) => _inRoom(
    (room) => _Files(
      height: _treeRows(room),
      hidden: o.flag('hidden'),
      gitignore: o.flag('gitignore'),
      sizes: o.flag('sizes'),
      guides: o.flag('guides'),
      icons: o.choice<String>('icon') == 'glyphs',
    ),
  ),
  // the tree, and the line under it
  heightIn: (o, room) => _treeRows(room.height) + 2,
  codeIn: (o, room) => [
    '/// A project of files as many bytes as they are big; a directory that',
    '/// cannot be read, and what the .gitignore leaves out.',
    'static final _files = InMemoryFileSystem(',
    "  const ['$_project/'],",
    '  contents: {',
    "    '$_project/.gitignore': '$_gitignore',",
    '    for (final (path, bytes) in const [',
    for (final (path, bytes) in _projectFiles) "      ('$path', $bytes),",
    '    ])',
    "      '$_project/\$path': 'x' * bytes,",
    '  },',
    "  unreadable: const ['$_project/private'],",
    ');',
    '',
    'final _tree = DirectoryTreeController()',
    "  ..expand('$_project/lib')",
    "  ..expand('$_project/lib/src');",
    "var _opened = '';",
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    '      SizedBox(',
    '        width: $_dirTreeW,',
    '        height: ${_treeRows(room.height)},',
    '        child: DirectoryTree(',
    "          root: '$_project',",
    '          fileSystem: _files,',
    '          controller: _tree,',
    if (o.flag('hidden')) '          showHidden: true,',
    if (!o.flag('gitignore')) '          gitignore: false,',
    if (o.flag('sizes')) '          showSizes: true,',
    if (o.flag('guides')) '          showGuides: true,',
    if (o.choice<String>('icon') == 'glyphs')
      codeLine([
        "          icon: (entry) => entry.isDirectory ? '$_dirIcon' ",
        ": '$_fileIcon',",
      ]),
    '          onOpened: (path) => setState(',
    "            () => _opened = path.substring('$_project/'.length),",
    '          ),',
    '        ),',
    '      ),',
    '      Text.rich([',
    "        Span('opened: ', theme.muted),",
    '        if (_opened.isEmpty)',
    "          Span('nothing', theme.muted)",
    '        else',
    '          Span(_opened),',
    '      ]),',
    '    ],',
    '  );',
    '}',
  ].join('\n'),
);

/// The project's tree, [height] rows, and the file opened last.
final class _Files extends StatefulWidget {
  const _Files({
    required this.height,
    required this.hidden,
    required this.gitignore,
    required this.sizes,
    required this.guides,
    required this.icons,
  });

  final int height;
  final bool hidden;
  final bool gitignore;
  final bool sizes;
  final bool guides;
  final bool icons;

  @override
  State<_Files> createState() => _FilesState();
}

final class _FilesState extends State<_Files> {
  static final _files = InMemoryFileSystem(
    const ['$_project/'],
    contents: {
      '$_project/.gitignore': 'build/\n*.log\n',
      for (final (path, bytes) in _projectFiles) '$_project/$path': 'x' * bytes,
    },
    unreadable: const ['$_project/private'],
  );

  late final Map<String, Object?> _kept = PageControl.of(context).state;

  // kept while the gallery runs: what is expanded and selected
  late final _tree =
      (_kept['tree'] ??= DirectoryTreeController()
            ..expand('$_project/lib')
            ..expand('$_project/lib/src'))
          as DirectoryTreeController;

  String get _opened => _kept['opened'] as String? ?? '';
  int get _serial => _kept['serial'] as int? ?? 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      SizedBox(
        width: _dirTreeW,
        height: widget.height,
        child: DirectoryTree(
          root: _project,
          fileSystem: _files,
          controller: _tree,
          showHidden: widget.hidden,
          gitignore: widget.gitignore,
          showSizes: widget.sizes,
          showGuides: widget.guides,
          icon: widget.icons
              ? (entry) => entry.isDirectory ? _dirIcon : _fileIcon
              : null,
          onOpened: (path) => setState(() {
            _kept['opened'] = path.substring('$_project/'.length);
            _kept['serial'] = _serial + 1;
          }),
        ),
      ),
      LitLine([
        ('opened: ', true),
        if (_opened.isEmpty) ('nothing', true) else (_opened, false),
      ], serial: _serial),
    ],
  );
}
