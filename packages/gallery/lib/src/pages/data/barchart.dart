// The BarChart page.
part of 'data.dart';

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
  build: (context, o) => inRoom(
    (_, room) => Timed((context, ms, wake) {
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
