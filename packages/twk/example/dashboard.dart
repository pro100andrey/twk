// An operations dashboard, live: a header with how the services are and
// the time, four tiles of figures with how they moved and their last
// minute as a sparkline, the latency as a chart, the services, the deploys
// of the last weeks as a heatmap and a log that follows. The panels are
// in a grid and share their borders; the theme is dark or light as the
// terminal's background is, switched as soon as the terminal reports a
// new color scheme.
//
// The heatmap has the focus: the arrows move its cursor, Enter shows what
// was deployed that day in a toast and logs it; Tab takes the focus to the
// log, which the arrows scroll. Ctrl+G shows the debug keys over the bottom
// row until the next key: then o shows the frame overlay, r the repaint
// rainbow (the whole screen tinted once, then each repaint), c the log
// console; q quits.
//
//   cd packages/twk && dart run example/dashboard.dart
import 'dart:async';
import 'dart:math' show sin;

import 'package:twk/twk.dart';

Future<void> main() => runApp(const Dashboard());

/// When the dashboard starts: the figures are of the seconds after it.
final started = DateTime(2026, 10, 19, 14, 30);

/// The versions deployed, by day: on some weekdays of the last 16 weeks,
/// one to three a day.
final Map<DateTime, List<String>> deploys = {
  for (var day = 0; day < 16 * 7; day++)
    if (_noise(day) > .45 && DateTime(2026, 10, 19 - day).weekday < 6)
      DateTime(2026, 10, 19 - day): [
        for (var n = 0; n < 1 + _noise(day + 500) * 3 ~/ 1; n++)
          'v1.${40 - day ~/ 3}.$n',
      ],
};

/// A figure of the tiles: what it is, how it reads, its value at each
/// second, and whether more of it is better.
final class Metric {
  const Metric(
    this.title,
    this.format,
    this.at, {
    required this.better,
    required this.style,
  });

  final String title;
  final String Function(double value) format;
  final double Function(int second) at;

  /// Whether a rise is good news (requests) or bad (errors).
  final bool better;

  /// The sparkline's color from the theme.
  final Style Function(ThemeData theme) style;

  /// The values of the [count] seconds up to [now], oldest first.
  List<double> last(int count, int now) => [
    for (var s = now - count + 1; s <= now; s++) at(s),
  ];
}

/// The tiles' figures.
final metrics = [
  Metric(
    'Requests',
    (v) => '${_thousands(v.round())}/min',
    (s) => 1200 + 260 * sin(s / 9) + 90 * _noise(s),
    better: true,
    style: (theme) => theme.info,
  ),
  Metric(
    'Errors',
    (v) => '${v.toStringAsFixed(2)}%',
    (s) => .45 + .06 * sin(s / 7 + 1) + .04 * _noise(s + 50),
    better: false,
    style: (theme) => theme.error,
  ),
  Metric(
    'Latency p95',
    (v) => '${v.round()} ms',
    _p95,
    better: false,
    style: (theme) => theme.warning,
  ),
  Metric(
    'Users',
    (v) => _thousands(v.round()),
    (s) => 3300 + 180 * sin(s / 23) + 40 * _noise(s + 99),
    better: true,
    style: (theme) => theme.accent,
  ),
];

/// The latency's median at second [s], in milliseconds.
double _p50(int s) => 60 + 12 * sin(s / 5) + 10 * _noise(s + 7);

/// The latency's 95th percentile at second [s], in milliseconds.
double _p95(int s) => 170 + 40 * sin(s / 11) + 30 * _noise(s + 3);

/// How each service is: up, slow or down.
enum Health { up, slow, down }

/// The services and how each is.
const List<(String, Health)> services = [
  ('api', Health.up),
  ('auth', Health.up),
  ('search', Health.slow),
  ('billing', Health.up),
  ('mail', Health.down),
];

/// What the log says each few seconds, in turn.
const List<(LogLevel, String)> said = [
  (LogLevel.info, 'GET /api/orders 200 38 ms'),
  (LogLevel.info, 'POST /api/sessions 201 21 ms'),
  (LogLevel.warning, 'search: slow query took 640 ms'),
  (LogLevel.info, 'GET /api/items/381 200 12 ms'),
  (LogLevel.error, 'mail: connection refused (smtp:587)'),
  (LogLevel.debug, 'cache hit items/381'),
];

final class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

final class _DashboardState extends State<Dashboard> {
  /// The seconds since the dashboard started.
  var _now = 0;
  late final Timer _clock;
  final _log = LogController();

  @override
  void initState() {
    super.initState();
    // the debug keys, which TWK_DEBUG=keys turns on in any app
    AppBinding.of(context).debug.keys = true;
    for (var s = -12; s < 0; s++) {
      _say(s);
    }
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now++);
      if (_now % 3 == 0) {
        _say(_now ~/ 3);
      }
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    _log.dispose();
    super.dispose();
  }

  /// Logs the [n]th of what the log says.
  void _say(int n) {
    final (level, text) = said[n % said.length];
    _log.add(
      text,
      level: level,
      time: started.add(Duration(seconds: 3 * n)),
    );
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'q': () => AppBinding.of(context).quit()},
    // the toasts go over the panels
    child: Overlay(
      child: _Board(now: _now, log: _log),
    ),
  );
}

/// The header over the panels, in a grid with a track a cell long before,
/// between and after its columns and its rows: a panel's box spans the
/// tracks on its sides, which its neighbours span too, and its border
/// merges with theirs there. A Stack puts the keys over the bottom border.
final class _Board extends StatelessWidget {
  const _Board({required this.now, required this.log});

  /// The seconds since the dashboard started.
  final int now;

  final LogController log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // the sparklines and the chart paint both colors of their cells
    final base = theme.background.merge(theme.text);
    return Box(
      style: base,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          _Header(time: started.add(Duration(seconds: now))),
          Expanded(
            child: Stack(
              children: [
                Grid(
                  columns: _withEdges(const [
                    GridTrack.fr(1),
                    GridTrack.fr(1),
                    GridTrack.fr(1),
                    GridTrack.fr(1),
                  ]),
                  rows: _withEdges(const [
                    GridTrack.content(),
                    GridTrack.fr(1),
                    GridTrack.content(),
                  ]),
                  children: [
                    for (final (i, metric) in metrics.indexed)
                      GridPlacement(
                        row: 0,
                        column: 2 * i,
                        rowSpan: 3,
                        columnSpan: 3,
                        child: _Panel(
                          title: metric.title,
                          child: _Tile(metric: metric, now: now),
                        ),
                      ),
                    GridPlacement(
                      row: 2,
                      column: 0,
                      rowSpan: 3,
                      columnSpan: 7,
                      child: _Panel(
                        title: 'Latency, last minute',
                        child: _Latency(now: now),
                      ),
                    ),
                    const GridPlacement(
                      row: 2,
                      column: 6,
                      rowSpan: 3,
                      columnSpan: 3,
                      child: _Panel(title: 'Services', child: _Services()),
                    ),
                    GridPlacement(
                      row: 4,
                      column: 0,
                      rowSpan: 3,
                      columnSpan: 5,
                      child: _Panel(
                        title: 'Deploys',
                        child: _Deploys(lines: log),
                      ),
                    ),
                    GridPlacement(
                      row: 4,
                      column: 4,
                      rowSpan: 3,
                      columnSpan: 5,
                      child: _Panel(
                        title: 'Log',
                        child: LogView(
                          controller: log,
                          scrollbar: .never,
                          style: base,
                        ),
                      ),
                    ),
                  ],
                ),
                const Positioned(left: 2, right: 2, bottom: 0, child: _Keys()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// [tracks] with a track a cell long before, between and after them.
List<GridTrack> _withEdges(List<GridTrack> tracks) => [
  const GridTrack.fixed(1),
  for (final track in tracks) ...[track, const GridTrack.fixed(1)],
];

/// A panel of the grid: [child] in a box titled [title], its border
/// merged with its neighbours'.
final class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Box(
      border: .all(type: .rounded, style: theme.border, merge: true),
      titles: [BorderTitle(' $title ', style: theme.primary)],
      padding: const .x(1),
      child: child,
    );
  }
}

/// The app's name, how the services are, and the [time].
final class _Header extends StatelessWidget {
  const _Header({required this.time});

  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final down = services.where((s) => s.$2 == Health.down).length;
    final clock = [
      time.hour,
      time.minute,
      time.second,
    ].map((n) => '$n'.padLeft(2, '0')).join(':');
    return Padding(
      padding: const .x(1),
      child: Row(
        gap: 2,
        children: [
          Text.rich([
            Span('◆ ', theme.primary),
            const Span('acme ops').bold,
            Span(' · production', theme.muted),
          ]),
          const Spacer(),
          if (down == 0)
            const Badge('all systems normal', kind: .success)
          else
            Badge('$down of ${services.length} down', kind: .error),
          Text(clock, style: theme.muted),
        ],
      ),
    );
  }
}

/// [metric] [now]: its value, how it moved in the last ten seconds, and
/// its last minute as a sparkline.
final class _Tile extends StatelessWidget {
  const _Tile({required this.metric, required this.now});

  final Metric metric;
  final int now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = metric.at(now);
    // the last ten seconds against the ten before
    double mean(List<double> values) =>
        values.reduce((a, b) => a + b) / values.length;
    final minute = metric.last(60, now);
    final before = mean(minute.sublist(40, 50));
    final change = (mean(minute.sublist(50)) - before) / before * 100;
    final rose = change >= 0;
    final arrow = rose ? '▲' : '▼';
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text.rich(
          [
            Span(metric.format(value)).bold,
            Span(
              '  $arrow ${change.abs().toStringAsFixed(1)}%',
              rose == metric.better ? theme.success : theme.error,
            ),
          ],
          wrap: .none,
          overflow: .ellipsis,
        ),
        SizedBox(
          height: 2,
          child: Sparkline(
            data: minute,
            // the lowest a little above the bottom: the line shows how it moved
            min: minute.reduce((a, b) => a < b ? a : b) * .9,
            style: theme.background.merge(metric.style(theme)),
          ),
        ),
      ],
    );
  }
}

/// The latency's median and 95th percentile over the last minute.
final class _Latency extends StatelessWidget {
  const _Latency({required this.now});

  final int now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    List<(double, double)> series(double Function(int) at) => [
      for (var s = 0; s < 60; s++) (s.toDouble(), at(now - 59 + s)),
    ];
    return Chart(
      style: theme.background.merge(theme.muted),
      datasets: [
        Dataset(
          data: series(_p50),
          name: 'p50',
          type: .line,
          color: theme.info.fg!,
        ),
        Dataset(
          data: series(_p95),
          name: 'p95',
          type: .line,
          color: theme.warning.fg!,
        ),
      ],
      xAxis: const ChartAxis(bounds: (0, 59), labels: ['-60 s', 'now']),
      yAxis: const ChartAxis(bounds: (0, 250), labels: ['0', '250 ms']),
    );
  }
}

/// Each service: a dot and a word of how it is.
final class _Services extends StatelessWidget {
  const _Services();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        for (final (name, health) in services)
          Row(
            children: [
              Text.rich([Span('● ', _healthStyle(theme, health)), Span(name)]),
              const Spacer(),
              Text(health.name, style: _healthStyle(theme, health)),
            ],
          ),
      ],
    );
  }
}

/// The theme's style for a service's [health].
Style _healthStyle(ThemeData theme, Health health) => switch (health) {
  .up => theme.success,
  .slow => theme.warning,
  .down => theme.error,
};

/// The deploys of the last 16 weeks as a heatmap; Enter on a day shows
/// what was deployed then in a toast, and logs it in [lines] and the debug
/// console.
final class _Deploys extends StatelessWidget {
  const _Deploys({required this.lines});

  final LogController lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActivityHeatmap(
      counts: {
        for (final MapEntry(key: day, value: versions) in deploys.entries)
          day: versions.length,
      },
      end: DateTime(started.year, started.month, started.day),
      weeks: 16,
      autofocus: true,
      // from no deploy to the most in a day, in the theme's green
      scale: HeatmapScale.colors(
        Gradient([theme.surface.bg!, theme.success.fg!]),
      ),
      tooltip: (day, count) => deploys[day]?.join(', ') ?? 'nothing deployed',
      onSelected: (day) {
        final deployed =
            '${day.toIso8601String().substring(0, 10)}: '
            '${deploys[day]?.join(', ') ?? 'nothing'} deployed';
        showToast(context, deployed);
        lines.add(deployed);
        log(deployed);
      },
    );
  }
}

/// The keys, over the bottom border.
final class _Keys extends StatelessWidget {
  const _Keys();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      [
        for (final (key, does) in const [
          ('←↑↓→', 'day'),
          ('enter', 'deploys'),
          ('tab', 'log'),
          ('q', 'quit'),
          ('ctrl+g', 'debug'),
        ]) ...[
          Span(' $key ', theme.primary).bold,
          Span('$does ', theme.muted),
        ],
      ],
      wrap: .none,
      overflow: .ellipsis,
    );
  }
}

/// [n] with a space between its thousands: 1 284.
String _thousands(int n) {
  final digits = '$n';
  final head = digits.length % 3;
  return [
    if (head > 0) digits.substring(0, head),
    for (var i = head; i < digits.length; i += 3) digits.substring(i, i + 3),
  ].join(' ');
}

/// A value from 0 to 1 that looks random and is the same for the same [i].
double _noise(int i) {
  final s = sin(i * 91.345 + 3.1) * 43758.5453;
  return s - s.floorToDouble();
}
