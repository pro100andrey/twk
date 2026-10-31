import 'dart:async';
import 'dart:math' as math;

import 'package:twk/twk.dart';

/// The app's name, in its title bar.
const appName = 'dashboard_template';

/// How often a reading is taken.
const interval = Duration(seconds: 1);

/// How many readings the chart shows, the newest at the right.
const kept = 60;

/// The services whose requests are counted.
const services = ['api', 'auth', 'search', 'mail'];

// Made-up readings at second [tick] of the app, which rise and fall: the
// place to read the real ones.

/// The CPU used at [tick], in percent.
double cpuAt(int tick) =>
    (50 + 30 * math.sin(tick / 5) + 12 * math.sin(tick / 1.7)).clamp(0, 100);

/// The share of the memory used at [tick].
double memoryAt(int tick) => .55 + .25 * math.sin(tick / 13);

/// The requests a second to each of [services] at [tick].
List<double> requestsAt(int tick) => [
  for (var i = 0; i < services.length; i++)
    (40 + 30 * math.sin(tick / 4 + i * 1.3)).roundToDouble(),
];

/// Panels of readings taken every [interval]: the CPU in a chart of the
/// last [kept], the memory in a gauge and the requests to each service in
/// bars. `p` pauses and resumes, `q` and Ctrl+Q quit.
final class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

final class _DashboardState extends State<Dashboard> {
  var _tick = 0;

  /// The CPU readings, oldest first, at most [kept].
  final _cpu = <double>[cpuAt(0)];

  /// Takes a reading every [interval]; null while paused.
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = _start();
  }

  Timer _start() => Timer.periodic(interval, (_) => _read());

  void _read() => setState(() {
    _tick++;
    _cpu.add(cpuAt(_tick));
    if (_cpu.length > kept) {
      _cpu.removeAt(0);
    }
  });

  void _pause() => setState(() {
    if (_timer case final timer?) {
      timer.cancel();
      _timer = null;
    } else {
      _timer = _start();
    }
  });

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memory = memoryAt(_tick);
    final requests = requestsAt(_tick);
    void quit() => AppBinding.of(context).quit();
    return KeyBindings(
      {'p': _pause, 'q': quit, 'ctrl+q': quit},
      hints: {'p': _timer == null ? 'resume' : 'pause', 'q': 'quit'},
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          StatusBar(
            left: Text.rich([Span(' $appName ', theme.primary).bold]),
            right: Text(
              _timer == null ? 'paused at ${_tick}s ' : 'live, ${_tick}s ',
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: .stretch,
              children: [
                Expanded(
                  child: _Panel(
                    'CPU ${_cpu.last.round()}%',
                    Chart(
                      datasets: [
                        Dataset(
                          // x: the seconds before the newest reading
                          data: [
                            for (final (i, cpu) in _cpu.indexed)
                              ((i - _cpu.length + 1).toDouble(), cpu),
                          ],
                          type: .line,
                          color: Color.cyan,
                        ),
                      ],
                      xAxis: ChartAxis(
                        bounds: (-kept.toDouble(), 0),
                        labels: const ['${kept}s ago', 'now'],
                        style: theme.muted,
                      ),
                      yAxis: ChartAxis(
                        bounds: (0, 100),
                        labels: const ['0', '50', '100'],
                        style: theme.muted,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Column(
                    crossAxisAlignment: .stretch,
                    children: [
                      _Panel(
                        'Memory',
                        LineGauge(
                          ratio: memory,
                          percentage: true,
                          filledStyle: _levelStyle(theme, memory),
                          unfilledStyle: theme.border,
                        ),
                      ),
                      Expanded(
                        child: _Panel(
                          'Requests a second',
                          BarChart(
                            groups: [
                              BarGroup([
                                for (final (i, service) in services.indexed)
                                  Bar(requests[i], label: service),
                              ]),
                            ],
                            barWidth: 6,
                            max: 100,
                            barStyle: theme.info,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const KeyHintsBar(),
        ],
      ),
    );
  }
}

/// The theme's style for a [ratio] used: success, then warning from 0.7,
/// error from 0.9.
Style _levelStyle(ThemeData theme, double ratio) =>
    ratio < .7 ? theme.success : (ratio < .9 ? theme.warning : theme.error);

/// [child] in a box titled [title].
final class _Panel extends StatelessWidget {
  const _Panel(this.title, this.child);

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Box(
      border: .all(type: .rounded, style: theme.border),
      titles: [BorderTitle(' $title ', style: theme.primary)],
      padding: const .x(1),
      child: child,
    );
  }
}
