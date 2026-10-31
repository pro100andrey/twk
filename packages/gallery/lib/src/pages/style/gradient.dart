// What the two gradient pages share: the colour sets, the stops, the
// colours flowing, and their Code.
part of 'style.dart';

/// A set of a gradient's colours: [colors] in the theme, and the Dart
/// that gives them, a line a colour ([dart]) or one expression ([expr]).
final class _ColorSet {
  const _ColorSet.rgb(List<Color> this._colors) : expr = null;
  const _ColorSet.palette(List<Color> this._colors) : expr = null;
  const _ColorSet.theme() : _colors = null, expr = _themeColors;

  final List<Color>? _colors;
  final String? expr;

  List<Color> colors(ThemeData theme) =>
      _colors ?? [theme.primary.fg!, theme.accent.fg!];

  List<String> get dart => [
    for (final c in _colors ?? const <Color>[]) _dartOf(c),
  ];
}

const _themeColors = '[theme.primary.fg!, theme.accent.fg!]';

/// The Dart of [c]: `Color.rgb(0xff, 0x5f, 0x6d)`, or a palette colour by
/// name.
String _dartOf(Color c) {
  if (!c.isRgb) {
    return switch (c) {
      Color.blue => 'Color.blue',
      Color.magenta => 'Color.magenta',
      Color.red => 'Color.red',
      _ => 'Color.indexed(${c.value})',
    };
  }
  String hex(int v) => '0x${v.toRadixString(16).padLeft(2, '0')}';
  return 'Color.rgb(${hex(c.r)}, ${hex(c.g)}, ${hex(c.b)})';
}

/// A set, or one for a dark background and one for a light one.
typedef _Sets = Map<String, (_ColorSet, _ColorSet?)>;

/// The colours of each set: the Dart gallery's three and the theme's own.
const _Sets _sets = {
  'theme': (_ColorSet.theme(), null),
  'sunset': (
    _ColorSet.rgb([Color.rgb(0xff, 0x5f, 0x6d), Color.rgb(0xff, 0xc3, 0x71)]),
    null,
  ),
  'ocean': (
    _ColorSet.rgb([
      Color.rgb(0x2b, 0x58, 0x76),
      Color.rgb(0x4e, 0xcd, 0xc4),
      Color.rgb(0xf7, 0xff, 0xf7),
    ]),
    null,
  ),
  'palette': (
    _ColorSet.palette([Color.blue, Color.magenta, Color.red]),
    null,
  ),
};

/// A turn of the colours round their loop, while they flow.
const _turn = 4000;

List<PageOption> _gradientOptions(String initial) => [
  ChoiceOption(
    'colors',
    'colors',
    values: _sets.keys.toList(),
    initial: initial,
  ),
  const ChoiceOption('direction', 'direction', values: ['columns', 'rows']),
  const ChoiceOption('stops', 'stops', values: ['even', 'inset', 'early']),
  const SwitchOption('flow', 'flow', initial: true),
];

/// The stops of [n] colours that the stops option [name] says: none for
/// `even`, from ¼ to ¾ of the way for `inset`, in the first half for
/// `early`.
List<double>? _stopsOf(String name, int n) {
  final step = n < 2 ? 0.0 : 1 / (n - 1);
  return switch (name) {
    'inset' => [for (var i = 0; i < n; i++) 0.25 + i * step / 2],
    'early' => [for (var i = 0; i < n; i++) i * step / 2],
    _ => null,
  };
}

/// [stops] as the Code writes them: `stops: const [0.25, 0.75]`.
String _stopsDart(List<double> stops) =>
    'stops: const [${stops.map(_fraction).join(', ')}]';

String _fraction(double s) => s == 0 ? '0' : '$s';

/// The gradient of [options] (colours of [sets], direction, flow) for
/// [build]: standing, or turning round its loop once every [_turn] ms on
/// the gallery's clock.
final class _Flowing extends StatefulWidget {
  const _Flowing({
    required this.options,
    required this.sets,
    required this.build,
  });

  final Options options;
  final _Sets sets;
  final Widget Function(BuildContext context, Gradient gradient) build;

  @override
  State<_Flowing> createState() => _FlowingState();
}

final class _FlowingState extends State<_Flowing> with MotionState {
  @override
  Widget build(BuildContext context) {
    motion.begin(context);
    final o = widget.options;
    final theme = Theme.of(context);
    final (dark, light) = widget.sets[o.choice<String>('colors')]!;
    final set = light != null && theme.brightness == Brightness.light
        ? light
        : dark;
    final colors = set.colors(theme);
    final axis = o.choice<String>('direction') == 'columns'
        ? Axis.horizontal
        : Axis.vertical;
    final stops = _stopsOf(o.choice('stops'), colors.length);
    final Gradient gradient;
    if (o.flag('flow')) {
      final ms = motion.now.inMilliseconds % _turn;
      gradient = Gradient(
        colors,
        stops: stops,
        phase: ms / _turn,
        direction: axis,
      );
      motion.animate();
    } else {
      gradient = Gradient(colors, stops: stops, direction: axis);
    }
    motion.end();
    return widget.build(context, gradient);
  }
}

/// [call] at the line's start, to the whole 80 columns.
List<String> _call(String head, List<String> args, String tail) =>
    call(0, head, args, tail, width: 80);

/// The Dart of a gradient page: [child] lines build the widget from
/// `gradient`, in a State named after [name] that runs a controller while
/// the colours flow; the colours of [sets].
String _gradientCode(
  Options o,
  String name,
  _Sets sets,
  List<String> child,
) {
  final axis = o.choice<String>('direction') == 'columns'
      ? '.horizontal'
      : '.vertical';
  final (dark, light) = sets[o.choice<String>('colors')]!;
  final stops = [
    if (_stopsOf(o.choice('stops'), dark.expr != null ? 2 : dark.dart.length)
        case final s?)
      _stopsDart(s),
  ];
  var head = <String>[];
  var local = <String>[];
  var colors = 'colors';
  if (dark.expr != null) {
    local = [
      'final theme = Theme.of(context);',
      'final colors = ${dark.expr};',
    ];
  } else if (light != null) {
    head = [
      '// for a dark background, and darker for a light one',
      'const _colors = {',
      for (final (b, set) in [('dark', dark), ('light', light)]) ...[
        '  Brightness.$b: [',
        for (final c in set.dart) '    $c,',
        '  ],',
      ],
      '};',
      '',
    ];
    local = ['final colors = _colors[Theme.of(context).brightness]!;'];
  } else {
    head = ['const _colors = [', for (final c in dark.dart) '  $c,', '];', ''];
    colors = '_colors';
  }
  if (!o.flag('flow')) {
    final last = child.length - 1;
    return [
      ...head,
      ...local,
      ..._call('final gradient = Gradient', [
        colors,
        ...stops,
        'direction: $axis',
      ], ';'),
      for (final (i, l) in child.indexed)
        '${i == 0 ? 'return ' : ''}$l${i == last ? ';' : ''}',
    ].join('\n');
  }
  final last = child.length - 1;
  return [
    ...head,
    'final class _${name}State extends State<_$name>',
    '    with TickerProviderStateMixin {',
    '  late final _flow = AnimationController(',
    '    vsync: this,',
    '    duration: const Duration(milliseconds: $_turn),',
    '  )..repeat();',
    '',
    '  @override',
    '  void dispose() {',
    '    _flow.dispose();',
    '    super.dispose();',
    '  }',
    '',
    '  @override',
    '  Widget build(BuildContext context) {',
    for (final l in local) '    $l',
    '    return ListenableBuilder(',
    '      listenable: _flow,',
    '      builder: (context, _) {',
    '        final gradient = Gradient(',
    '          $colors,',
    for (final s in stops) '          $s,',
    '          phase: _flow.value,',
    '          direction: $axis,',
    '        );',
    for (final (i, l) in child.indexed)
      '        ${i == 0 ? 'return ' : ''}$l${i == last ? ';' : ''}',
    '      },',
    '    );',
    '  }',
    '}',
  ].join('\n');
}
