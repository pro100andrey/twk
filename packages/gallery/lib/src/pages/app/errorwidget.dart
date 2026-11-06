// The ErrorWidget page.
part of 'app.dart';

/// The cells of [free] that flexible children of [flexes] take, as twk's
/// Flex shares them: each its part rounded down, the cells left over one
/// each to the first ones.
List<int> _share(int free, List<int> flexes) {
  final total = flexes.fold(0, (n, f) => n + f);
  final out = [for (final f in flexes) free * f ~/ total];
  var left = free - out.fold(0, (n, s) => n + s);
  for (var i = 0; i < out.length && left > 0; i++, left--) {
    out[i]++;
  }
  return out;
}

/// The cards' row.
const _ew = 50;

const _eh = 5;

/// What the weather throws, by the option's name: the Code's expression.
const _errors = {
  'StateError': "StateError('the weather failed to load')",
  'FormatException': "FormatException('not a date', '2026-13-01')",
  'Exception': "Exception('the weather failed to load')",
};

/// A new cpu load this often.
const _loadMs = 600;

/// The loads the cpu card shows, a column each.
final int _loads = _share(_ew - 2, const [1, 2, 1])[0] - 4;

/// The cpu's load at step [i]: a wave and noise, from 4 to 96.
double _loadAt(int i) {
  final s = math.sin(i * 78.233 + 1.7) * 43758.5453;
  final noise = s - s.floorToDouble();
  return (40 + 16 * math.sin(i / 2.3) + 34 * (noise - 0.5))
      .clamp(4, 96)
      .roundToDouble();
}

/// The ErrorWidget page's `fails` option.
const _errorFails = SwitchOption(
  'fails',
  'weather fails',
  initial: true,
);

/// The ErrorWidget page's `error` option.
final _errorError = ChoiceOption<String>(
  'error',
  'what it throws',
  values: _errors.keys.toList(),
);

final _error = GalleryPage(
  group: _group,
  title: 'ErrorWidget',
  options: [
    _errorFails,
    _errorError,
  ],
  build: (context, o) => _Cards(fails: o(_errorFails), error: o(_errorError)),
  code: (o) {
    final thrown = _errors[o(_errorError)]!;
    final build = o(_errorFails)
        ? [
            '  // throws: the app shows an ErrorWidget in its place, as',
            '  // ErrorWidget($thrown) would,',
            codeLine([
              '  // and logs the error with the path of the widget ',
              'at LogLevel.error',
            ]),
            '  @override',
            '  Widget build(BuildContext context) =>',
            '      throw $thrown;',
          ]
        : [
            '  @override',
            '  Widget build(BuildContext context) => Column(',
            '    crossAxisAlignment: .start,',
            '    children: [',
            "      const Text('12°C', style: Style(attrs: Attr.bold)),",
            "      const Text('light rain'),",
            "      Text('wind 14 km/h', style: Theme.of(context).muted),",
            '    ],',
            '  );',
          ];
    return [
      "/// The weather card's content.",
      'final class _Weather extends StatelessWidget {',
      '  const _Weather();',
      '',
      ...build,
      '}',
      '',
      "/// The cpu's load at step [i]: a wave and noise, from 4 to 96.",
      'static double _loadAt(int i) {',
      '  final s = sin(i * 78.233 + 1.7) * 43758.5453;',
      '  final noise = s - s.floorToDouble();',
      '  return (40 + 16 * sin(i / 2.3) + 34 * (noise - 0.5))',
      '      .clamp(4, 96)',
      '      .roundToDouble();',
      '}',
      '',
      '// the last $_loads loads, a new one every $_loadMs ms',
      'var _step = 0;',
      'var _load = [for (var i = ${1 - _loads}; i <= 0; i++) _loadAt(i)];',
      'late final Timer _timer;',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  _timer = Timer.periodic(',
      '    const Duration(milliseconds: $_loadMs),',
      codeLine([
        '    (_) => ',
        'setState(() => _load = [..._load.skip(1), _loadAt(++_step)]),',
      ]),
      '  );',
      '}',
      '',
      '@override',
      'void dispose() {',
      '  _timer.cancel();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  const bold = Style(attrs: Attr.bold);',
      codeLine([
        '  Widget card(String title, Widget child, {int flex = 1}) => ',
        'Expanded(',
      ]),
      '    flex: flex,',
      '    child: Box(',
      '      border: .all(type: .rounded, style: theme.border),',
      r"      titles: [BorderTitle(' $title ')],",
      '      padding: const .x(1),',
      '      child: child,',
      '    ),',
      '  );',
      '  return SizedBox(',
      '    width: $_ew,',
      '    height: $_eh,',
      '    child: Row(',
      '      crossAxisAlignment: .stretch,',
      '      spacing: 1,',
      '      children: [',
      '        card(',
      "          'cpu',",
      '          Column(',
      '            crossAxisAlignment: .stretch,',
      '            children: [',
      r"              Text('${_load.last.round()}%', style: bold),",
      '              Expanded(',
      codeLine([
        '                child: ',
        'Sparkline(data: _load, max: 100, style: theme.primary),',
      ]),
      '              ),',
      '            ],',
      '          ),',
      '        ),',
      "        card('weather', const _Weather(), flex: 2),",
      '        card(',
      "          'disk',",
      '          Column(',
      '            crossAxisAlignment: .stretch,',
      '            children: [',
      "              const Text('61%', style: bold),",
      '              LineGauge(',
      '                ratio: 0.61,',
      '                type: .heavy,',
      '                filledStyle: theme.primary,',
      '                unfilledStyle: theme.border,',
      '              ),',
      "              Text('512 GB', style: theme.muted),",
      '            ],',
      '          ),',
      '        ),',
      '      ],',
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);

/// The weather card's content: what the Code's builds, or a throw of
/// [error] (its option's name) when [fails].
final class _Weather extends StatelessWidget {
  const _Weather({required this.fails, required this.error});

  final bool fails;
  final String error;

  @override
  Widget build(BuildContext context) {
    if (fails) {
      // throws: the app shows an ErrorWidget in its place
      switch (error) {
        case 'FormatException':
          throw const FormatException('not a date', '2026-13-01');
        case 'Exception':
          throw Exception('the weather failed to load');
        default:
          throw StateError('the weather failed to load');
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('12°C', style: Style(attrs: Attr.bold)),
        const Text('light rain'),
        Text('wind 14 km/h', style: Theme.of(context).muted),
      ],
    );
  }
}

/// The Code's three cards, the cpu's load on the gallery's clock.
final class _Cards extends StatefulWidget {
  const _Cards({required this.fails, required this.error});

  final bool fails;
  final String error;

  @override
  State<_Cards> createState() => _CardsState();
}

final class _CardsState extends TimedState<_Cards> {
  @override
  Widget buildTimed(BuildContext context) {
    final theme = Theme.of(context);
    const bold = Style(attrs: Attr.bold);
    final step = now ~/ _loadMs;
    wake((step + 1) * _loadMs);
    final load = [for (var i = step + 1 - _loads; i <= step; i++) _loadAt(i)];
    Widget card(String title, Widget child, {int flex = 1}) => Expanded(
      flex: flex,
      child: Box(
        border: Border.all(type: BorderType.rounded, style: theme.border),
        titles: [BorderTitle(' $title ')],
        padding: const EdgeInsets.x(1),
        child: child,
      ),
    );
    return SizedBox(
      width: _ew,
      height: _eh,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 1,
        children: [
          card(
            'cpu',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${load.last.round()}%', style: bold),
                Expanded(
                  child: Sparkline(data: load, max: 100, style: theme.primary),
                ),
              ],
            ),
          ),
          card(
            'weather',
            _Weather(fails: widget.fails, error: widget.error),
            flex: 2,
          ),
          card(
            'disk',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('61%', style: bold),
                LineGauge(
                  ratio: 0.61,
                  type: BorderType.heavy,
                  filledStyle: theme.primary,
                  unfilledStyle: theme.border,
                ),
                Text('512 GB', style: theme.muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
