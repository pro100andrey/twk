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
