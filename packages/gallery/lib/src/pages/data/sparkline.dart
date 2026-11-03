// The Sparkline page.
part of 'data.dart';

/// A new value this often while the sparkline is live.
const _step = 150;

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

/// The Sparkline page's `data` option.
final _sparklineData = ChoiceOption<String>(
  'data',
  'data',
  values: _series.keys.toList(),
);

/// The Sparkline page's `rows` option.
const _sparklineRows = ChoiceOption<int>(
  'rows',
  'rows',
  values: [1, 2, 4],
  initial: 4,
);

/// The Sparkline page's `max` option.
const _sparklineMax = ChoiceOption<double?>(
  'max',
  'max',
  values: [null, 10.0],
  labels: ['largest', '10'],
);

/// The Sparkline page's `live` option.
const _sparklineLive = SwitchOption('live', 'live', initial: true);

/// The Sparkline page's `color` option.
const _sparklineColor = ColorOption(
  'color',
  'style',
  values: ['info', 'primary', 'accent', 'success', 'warning'],
  initial: 'info',
);

final _sparkline = GalleryPage(
  group: _group,
  title: 'Sparkline',
  options: [
    _sparklineData,
    _sparklineRows,
    _sparklineMax,
    _sparklineLive,
    _sparklineColor,
  ],
  build: (context, o) => Timed((context, ms, wake) {
    final k = o(_sparklineLive) ? _tick(ms, _step, wake) : 0;
    final f = _series[o(_sparklineData)]!.$1;
    return SizedBox(
      width: 48,
      height: o(_sparklineRows),
      child: Sparkline(
        data: [for (var i = 0; i < 48; i++) f(i + k)],
        max: o(_sparklineMax),
        style: o.styleOf(context, _sparklineColor),
      ),
    );
  }),
  code: (o) {
    final gen = _series[o(_sparklineData)]!.$2;
    final build = [
      '@override',
      'Widget build(BuildContext context) => SizedBox(',
      '  width: 48,',
      '  height: ${o.nameOf(_sparklineRows)},',
      if (o(_sparklineMax) == null)
        codeLine([
          '  child: Sparkline(data: _data, style: ',
          'Theme.of(context).${o(_sparklineColor)}),',
        ])
      else ...[
        '  child: Sparkline(',
        '    data: _data,',
        '    max: ${o.nameOf(_sparklineMax)},',
        '    style: Theme.of(context).${o(_sparklineColor)},',
        '  ),',
      ],
      ');',
    ];
    final helper = o(_sparklineData) == 'noise'
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
    if (!o(_sparklineLive)) {
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
