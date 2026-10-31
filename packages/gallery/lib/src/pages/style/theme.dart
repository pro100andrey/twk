// The Theme page.
part of 'style.dart';

final _themePage = GalleryPage(
  group: 'Style',
  title: 'Theme',
  options: [
    ChoiceOption(
      'theme',
      'theme',
      values: [for (final p in _presets) p.key],
      initial: 'nord',
    ),
    const SwitchOption('cycle', 'cycle'),
  ],
  build: (context, o) => _ThemePage(
    chosen: _presets.indexWhere((p) => p.key == o.choice<String>('theme')),
    cycle: o.flag('cycle'),
  ),
  code: _themeCode,
);

/// twk's presets: the option's name, the name ThemeData gives it, its
/// Dart, the theme.
const _presets = [
  _Preset(
    'terminal',
    'terminal',
    'ThemeData.terminal(Brightness.dark)',
    ThemeData.terminal(Brightness.dark),
  ),
  _Preset('dark', 'dark', 'ThemeData.dark', ThemeData.dark),
  _Preset('light', 'light', 'ThemeData.light', ThemeData.light),
  _Preset('nord', 'nord', 'ThemeData.nord', ThemeData.nord),
  _Preset(
    'mocha',
    'catppuccinMocha',
    'ThemeData.catppuccinMocha',
    ThemeData.catppuccinMocha,
  ),
  _Preset(
    'latte',
    'catppuccinLatte',
    'ThemeData.catppuccinLatte',
    ThemeData.catppuccinLatte,
  ),
];

final class _Preset {
  const _Preset(this.key, this.name, this.dart, this.data);

  final String key;
  final String name;
  final String dart;
  final ThemeData data;
}

/// The next preset this often while the page cycles.
const _cycle = 2000;

/// The Theme page: the preset [chosen], or while [cycle] is on, the next
/// one every [_cycle] ms, as the Code's timer steps it, the option moved
/// along with it. The timer runs from when the page was built (0 while
/// the clock stands still, so a still at a route's `t=` has stepped as
/// far as the page would have), from when the switch was turned on, and
/// on from a preset chosen by hand, which turns the cycle off.
final class _ThemePage extends StatefulWidget {
  const _ThemePage({required this.chosen, required this.cycle});

  final int chosen;
  final bool cycle;

  @override
  State<_ThemePage> createState() => _ThemePageState();
}

final class _ThemePageState extends State<_ThemePage> with MotionState {
  @override
  Widget build(BuildContext context) {
    motion.begin(context);
    final control = PageControl.of(context);
    final kept = control.state;
    final now = motion.now;
    final n = _presets.length;
    final c = widget.chosen < 0 ? 0 : widget.chosen;
    var on = widget.cycle;
    final born = kept['born'] as Duration? ?? (motion.frozen ? .zero : now);
    kept['born'] = born;
    var d = kept['drive'] as Drive?;
    if (on && d != null && d.on && c != d.last) {
      // a preset chosen by hand while it cycles: the pick stays
      scheduleMicrotask(() => control.setOption('cycle', false));
      on = false;
    }
    if (d == null) {
      d = Drive(on: on, since: born, from: c);
      kept['drive'] = d;
    } else if (d.on != on) {
      d
        ..on = on
        ..since = now
        ..from = c;
    }
    var i = c;
    if (on) {
      final k = (now - d.since).inMilliseconds ~/ _cycle;
      final steps = k < 0 ? 0 : k;
      i = (d.from + steps) % n;
      motion.wakeAt(
        d.since + const Duration(milliseconds: _cycle) * (steps + 1),
      );
    }
    d.last = c;
    if (on && i != c) {
      final key = _presets[i].key;
      scheduleMicrotask(() => control.setOption('theme', key));
      d.last = i;
    }
    motion.end();
    final preset = _presets[i];
    return Theme(data: preset.data, child: _Swatches(preset.name));
  }
}

String _themeCode(Options o) {
  final i = _presets.indexWhere((p) => p.key == o.choice<String>('theme'));
  final list = [
    'const _themes = [',
    for (final p in _presets) "  ('${p.name}', ${p.dart}),",
    '];',
    '',
  ];
  if (!o.flag('cycle')) {
    return [
      ...list,
      'final (name, data) = _themes[$i];',
      'return Theme(data: data, child: _Swatches(name));',
      '',
      ..._swatchesCode(named: true),
    ].join('\n');
  }
  return [
    ...list,
    'var _i = $i;',
    'late final Timer _timer;',
    '',
    '@override',
    'void initState() {',
    '  super.initState();',
    '  // the next theme every two seconds',
    '  _timer = Timer.periodic(',
    '    const Duration(milliseconds: $_cycle),',
    '    (_) => setState(() => _i = (_i + 1) % _themes.length),',
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
    '  final (name, data) = _themes[_i];',
    '  return Theme(data: data, child: _Swatches(name));',
    '}',
    '',
    ..._swatchesCode(named: true),
  ].join('\n');
}
