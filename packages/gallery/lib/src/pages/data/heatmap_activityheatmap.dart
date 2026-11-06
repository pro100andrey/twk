// The Heatmap, ActivityHeatmap page.
part of 'data.dart';

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

/// The Heatmap, ActivityHeatmap page's `kind` option.
const _heatmapKind = ChoiceOption<String>(
  'kind',
  'widget',
  values: ['activity', 'grid'],
  labels: ['ActivityHeatmap', 'Heatmap'],
);

/// The Heatmap, ActivityHeatmap page's `firstWeekday` option.
final _heatmapFirstWeekday = ChoiceOption<int>(
  'firstWeekday',
  'first day',
  values: const [DateTime.monday, DateTime.sunday],
  labels: const ['monday', 'sunday'],
  disabled: (o) => o(_heatmapKind) != 'activity',
);

/// The Heatmap, ActivityHeatmap page's `scale` option.
const _heatmapScale = ChoiceOption<String>(
  'scale',
  'scale',
  values: ['shades', 'colors'],
);

/// The Heatmap, ActivityHeatmap page's `legend` option.
const _heatmapLegend = SwitchOption(
  'legend',
  'legend',
  initial: true,
);

/// The Heatmap, ActivityHeatmap page's `cell` option.
const _heatmapCell = ChoiceOption<int>(
  'cell',
  'cell width',
  values: [2, 1],
  labels: ['2 columns', '1 column'],
);

final _heatmap = GalleryPage(
  group: _group,
  title: 'Heatmap, ActivityHeatmap',
  options: [
    _heatmapKind,
    _heatmapFirstWeekday,
    _heatmapScale,
    _heatmapLegend,
    _heatmapCell,
  ],
  build: (context, o) => _Heat(
    activity: o(_heatmapKind) == 'activity',
    firstWeekday: o(_heatmapFirstWeekday),
    colors: o(_heatmapScale) == 'colors',
    legend: o(_heatmapLegend),
    cellWidth: o(_heatmapCell),
  ),
  code: (o) {
    final activity = o(_heatmapKind) == 'activity';
    final colors = o(_heatmapScale) == 'colors';
    final cell = o(_heatmapCell);
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
        '    spacing: 1,',
        '    children: [',
        '      ActivityHeatmap(',
        '        counts: _commits,',
        '        end: DateTime(2026, 10, 19),',
        '        weeks: $_heatWeeks,',
        if (o(_heatmapFirstWeekday) == DateTime.sunday)
          '        firstWeekday: DateTime.sunday,',
        ..._indented(scale, 2),
        if (o(_heatmapLegend)) '        showLegend: true,',
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
      '    spacing: 1,',
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
      if (o(_heatmapLegend)) '        showLegend: true,',
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

final class _HeatState extends State<_Heat> with KeptState {
  static final Map<DateTime, int> _commits = {
    for (var i = 0; i < _heatWeeks * 7; i++)
      DateTime(2026, 10, 19 - i): _commitsOn(i),
  };

  String get _selected => kept['selected'] as String? ?? '';
  int get _serial => kept['serial'] as int? ?? 0;

  void _select(String what) => setState(() {
    kept['selected'] = what;
    kept['serial'] = _serial + 1;
  });

  @override
  Widget build(BuildContext context) {
    final scale = widget.colors ? const HeatmapScale.colors(_greens) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 1,
      children: [
        if (widget.activity)
          ActivityHeatmap(
            counts: _commits,
            end: _heatEnd,
            weeks: _heatWeeks,
            firstWeekday: widget.firstWeekday,
            scale: scale,
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
