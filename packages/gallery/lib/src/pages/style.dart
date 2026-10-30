// The Style group of the gallery.
import 'dart:async';

import 'package:twk/twk.dart';

import '../motion.dart';
import '../page.dart';
import 'common.dart';

/// The pages of the Style group that draw.
final stylePages = [
  GalleryPage(
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
  ),
  GalleryPage(
    group: 'Style',
    title: 'TerminalBrightness',
    options: [
      const ChoiceOption(
        'brightness',
        'brightness',
        values: [null, 'dark', 'light'],
        labels: ["the terminal's", 'dark', 'light'],
      ),
      ChoiceOption('dark', 'dark theme', values: _darks.keys.toList()),
      ChoiceOption('light', 'light theme', values: _lights.keys.toList()),
    ],
    build: (context, o) {
      final adaptive = _Adaptive(
        dark: _darks[o.choice<String>('dark')]!,
        light: _lights[o.choice<String>('light')]!,
      );
      // the gallery's theme stands in for the terminal's colours
      return TerminalBrightness(
        brightness: switch (o.choice<String?>('brightness')) {
          'dark' => Brightness.dark,
          'light' => Brightness.light,
          _ => Theme.of(context).brightness,
        },
        child: adaptive,
      );
    },
    code: _brightnessCode,
  ),
  GalleryPage(
    group: 'Style',
    title: 'GradientBackground',
    options: _gradientOptions('sunset'),
    build: (context, o) => _Flowing(
      options: o,
      sets: _sets,
      build: (context, gradient) => GradientBackground(
        gradient: gradient,
        child: SizedBox(
          width: _bgWidth,
          height: _bgHeight,
          child: Center(
            child: Box(
              style: Theme.of(context).surface,
              padding: const EdgeInsets.only(
                left: 2,
                top: 1,
                right: 2,
                bottom: 1,
              ),
              child: const Text(_bgText),
            ),
          ),
        ),
      ),
    ),
    code: (o) => _gradientCode(o, 'Backdrop', _sets, [
      'GradientBackground(',
      '  gradient: gradient,',
      '  child: SizedBox(',
      '    width: $_bgWidth,',
      '    height: $_bgHeight,',
      '    child: Center(',
      '      child: Box(',
      '        style: Theme.of(context).surface,',
      '        padding: const .only(left: 2, top: 1, right: 2, bottom: 1),',
      "        child: const Text('$_bgText'),",
      '      ),',
      '    ),',
      '  ),',
      ')',
    ]),
  ),
  GalleryPage(
    group: 'Style',
    title: 'GradientForeground',
    options: _gradientOptions('theme'),
    build: (context, o) => _Flowing(
      options: o,
      sets: _textSets,
      build: (context, gradient) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 1,
        children: [
          GradientForeground(
            gradient: gradient,
            child: Text(_fgRows.join('\n')),
          ),
          Text.rich([
            Span(_spanLead, Theme.of(context).muted),
            _spanText.gradient(gradient),
          ]),
        ],
      ),
    ),
    code: (o) => _gradientCode(o, 'Lettering', _textSets, [
      'Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      '    GradientForeground(',
      '      gradient: gradient,',
      '      child: const Text(',
      for (final (i, l) in _fgRows.indexed)
        "        '$l${i < _fgRows.length - 1 ? r'\n' : ''}'",
      '      ),',
      '    ),',
      '    Text.rich([',
      "      Span('$_spanLead', Theme.of(context).muted),",
      "      '$_spanText'.gradient(gradient),",
      '    ]),',
      '  ],',
      ')',
    ]),
  ),
];

// ------------------------------------------------------------ themes

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

const _cardWidth = 46;
const _bold = Style(attrs: Attr.bold);

/// twk's _Swatches of the Code: each style of the theme, named in it, on
/// its background, a panel on its surface; with a [name], the name on its
/// border and a Button, a Checkbox and a Switch, live, in it too, their
/// values kept in the page's state.
final class _Swatches extends StatefulWidget {
  const _Swatches([this.name]);

  final String? name;

  @override
  State<_Swatches> createState() => _SwatchesState();
}

final class _SwatchesState extends State<_Swatches> {
  late final Map<String, Object?> _kept = PageControl.of(context).state;

  bool get _checked => _kept['check'] as bool? ?? true;
  set _checked(bool v) => _kept['check'] = v;
  bool get _on => _kept['on'] as bool? ?? true;
  set _on(bool v) => _kept['on'] = v;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.name;
    final text = [
      ('text', theme.text),
      ('muted', theme.muted),
      ('primary', theme.primary),
      ('accent', theme.accent),
      ('border', theme.border),
    ];
    final status = [
      ('error', theme.error),
      ('warning', theme.warning),
      ('success', theme.success),
      ('info', theme.info),
    ];
    return SizedBox(
      width: _cardWidth,
      child: Box(
        style: theme.background.merge(theme.text),
        border: Border.all(type: BorderType.rounded, style: theme.border),
        titles: [
          if (name != null)
            BorderTitle(' $name ', style: theme.text.merge(_bold)),
        ],
        padding: const EdgeInsets.x(2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.rich([for (final (n, style) in text) Span('$n  ', style)]),
            Text.rich([for (final (n, style) in status) Span('$n  ', style)]),
            const SizedBox(height: 1),
            Box(
              style: theme.surface,
              border: Border.all(type: BorderType.rounded, style: theme.border),
              titles: [BorderTitle(' surface ', style: theme.muted)],
              padding: const EdgeInsets.x(1),
              child: Text.rich([
                const Span('a panel, with '),
                Span(' selection ', theme.selection),
                const Span(' in it'),
              ]),
            ),
            if (name != null) ...[
              const SizedBox(height: 1),
              Row(
                gap: 3,
                children: [
                  Button('Button', onPressed: () {}),
                  Checkbox(
                    value: _checked,
                    label: 'Checkbox',
                    onChanged: (value) => setState(() => _checked = value),
                  ),
                  Switch(
                    value: _on,
                    label: 'Switch',
                    onChanged: (value) => setState(() => _on = value),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Code's line of the name on the border of _Swatches.
const _titleLine =
    r"          BorderTitle(' ${widget.name} ', "
    'style: theme.text.merge(bold)),';

/// The Code's doc of _Adaptive.
const _adaptiveDoc =
    '/// The brightness found here, and the theme [Theme.adaptive] picks by '
    'it.';

/// The Dart of _Swatches: with [named], its name and controls.
List<String> _swatchesCode({required bool named}) => [
  '/// Each style of the theme, named in it, on its background.',
  if (named) ...[
    'final class _Swatches extends StatefulWidget {',
    '  const _Swatches(this.name);',
    '',
    '  final String name;',
    '',
    '  @override',
    '  State<_Swatches> createState() => _SwatchesState();',
    '}',
    '',
    'final class _SwatchesState extends State<_Swatches> {',
    '  var _checked = true;',
    '  var _on = true;',
    '',
  ] else ...[
    'final class _Swatches extends StatelessWidget {',
    '  const _Swatches();',
    '',
  ],
  '  @override',
  '  Widget build(BuildContext context) {',
  '    final theme = Theme.of(context);',
  '    final text = [',
  "      ('text', theme.text),",
  "      ('muted', theme.muted),",
  "      ('primary', theme.primary),",
  "      ('accent', theme.accent),",
  "      ('border', theme.border),",
  '    ];',
  '    final status = [',
  "      ('error', theme.error),",
  "      ('warning', theme.warning),",
  "      ('success', theme.success),",
  "      ('info', theme.info),",
  '    ];',
  '    return SizedBox(',
  '      width: $_cardWidth,',
  '      child: Box(',
  '        style: theme.background.merge(theme.text),',
  '        border: .all(type: .rounded, style: theme.border),',
  if (named) ...[
    '        titles: [',
    _titleLine,
    '        ],',
  ],
  '        padding: const .x(2),',
  '        child: Column(',
  '          mainAxisSize: .min,',
  '          crossAxisAlignment: .stretch,',
  '          children: [',
  '            Text.rich([',
  r"              for (final (name, style) in text) Span('$name  ', style),",
  '            ]),',
  '            Text.rich([',
  r"              for (final (name, style) in status) Span('$name  ', style),",
  '            ]),',
  '            const SizedBox(height: 1),',
  '            Box(',
  '              style: theme.surface,',
  '              border: .all(type: .rounded, style: theme.border),',
  "              titles: [BorderTitle(' surface ', style: theme.muted)],",
  '              padding: const .x(1),',
  '              child: Text.rich([',
  "                const Span('a panel, with '),",
  "                Span(' selection ', theme.selection),",
  "                const Span(' in it'),",
  '              ]),',
  '            ),',
  if (named) ...[
    '            const SizedBox(height: 1),',
    '            Row(',
    '              gap: 3,',
    '              children: [',
    "                Button('Button', onPressed: () {}),",
    '                Checkbox(',
    '                  value: _checked,',
    "                  label: 'Checkbox',",
    '                  onChanged: (value) => setState(() => _checked = value),',
    '                ),',
    '                Switch(',
    '                  value: _on,',
    "                  label: 'Switch',",
    '                  onChanged: (value) => setState(() => _on = value),',
    '                ),',
    '              ],',
    '            ),',
  ],
  '          ],',
  '        ),',
  '      ),',
  '    );',
  '  }',
  '}',
  if (named) ...['', 'const bold = Style(attrs: Attr.bold);'],
];

// ------------------------------------------------------------ Theme

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

final class _ThemePageState extends State<_ThemePage> {
  late final _motion = Motion(() {
    if (mounted) {
      setState(() {});
    }
  });

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _motion.begin(context);
    final control = PageControl.of(context);
    final kept = control.state;
    final now = _motion.now;
    final n = _presets.length;
    final c = widget.chosen < 0 ? 0 : widget.chosen;
    var on = widget.cycle;
    final born = kept['born'] as Duration? ?? (_motion.frozen ? .zero : now);
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
      _motion.wakeAt(
        d.since + const Duration(milliseconds: _cycle) * (steps + 1),
      );
    }
    d.last = c;
    if (on && i != c) {
      final key = _presets[i].key;
      scheduleMicrotask(() => control.setOption('theme', key));
      d.last = i;
    }
    _motion.end();
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

// ------------------------------------------------------ TerminalBrightness

const Map<String, (String, ThemeData)> _darks = {
  'nord': ('nord', ThemeData.nord),
  'dark': ('dark', ThemeData.dark),
  'mocha': ('catppuccinMocha', ThemeData.catppuccinMocha),
};
const Map<String, (String, ThemeData)> _lights = {
  'latte': ('catppuccinLatte', ThemeData.catppuccinLatte),
  'light': ('light', ThemeData.light),
};

/// The brightness found here, and the theme [Theme.adaptive] picks by it:
/// [dark] or [light], each its name and its theme.
final class _Adaptive extends StatelessWidget {
  const _Adaptive({required this.dark, required this.light});

  final (String, ThemeData) dark;
  final (String, ThemeData) light;

  @override
  Widget build(BuildContext context) {
    final brightness = TerminalBrightness.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich([
          const Span('The terminal is '),
          brightness.name.bold,
          const Span('.'),
        ]),
        Text.rich([
          const Span('Theme.adaptive picks '),
          switch (brightness) {
            Brightness.dark => dark.$1.bold,
            Brightness.light => light.$1.bold,
          },
        ], style: Theme.of(context).muted),
        Theme.adaptive(
          dark: dark.$2,
          light: light.$2,
          child: const _Swatches(),
        ),
      ],
    );
  }
}

String _brightnessCode(Options o) {
  final dark = _darks[o.choice<String>('dark')]!.$1;
  final light = _lights[o.choice<String>('light')]!.$1;
  final brightness = o.choice<String?>('brightness');
  return [
    if (brightness == null) ...[
      '// the brightness the terminal reports, which the app puts at its top',
      'return const _Adaptive();',
    ] else ...[
      'return const TerminalBrightness(',
      '  brightness: Brightness.$brightness,',
      '  child: _Adaptive(),',
      ');',
    ],
    '',
    _adaptiveDoc,
    'final class _Adaptive extends StatelessWidget {',
    '  const _Adaptive();',
    '',
    '  @override',
    '  Widget build(BuildContext context) {',
    '    final brightness = TerminalBrightness.of(context);',
    '    return Column(',
    '      mainAxisSize: .min,',
    '      crossAxisAlignment: .start,',
    '      children: [',
    '        Text.rich([',
    "          const Span('The terminal is '),",
    '          brightness.name.bold,',
    "          const Span('.'),",
    '        ]),',
    '        Text.rich([',
    "          const Span('Theme.adaptive picks '),",
    '          switch (brightness) {',
    "            Brightness.dark => '$dark'.bold,",
    "            Brightness.light => '$light'.bold,",
    '          },',
    '        ], style: Theme.of(context).muted),',
    '        const Theme.adaptive(',
    '          dark: ThemeData.$dark,',
    '          light: ThemeData.$light,',
    '          child: _Swatches(),',
    '        ),',
    '      ],',
    '    );',
    '  }',
    '}',
    '',
    ..._swatchesCode(named: false),
  ].join('\n');
}

// ------------------------------------------------------------ gradients

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

/// The sets of the lettering: sunset's and ocean's light colours read only
/// on a dark background, so the text takes them, a little lighter, on a
/// dark theme, and darker ones on a light theme.
const _Sets _textSets = {
  'theme': (_ColorSet.theme(), null),
  'sunset': (
    _ColorSet.rgb([Color.rgb(0xff, 0x5f, 0x6d), Color.rgb(0xff, 0xc3, 0x71)]),
    _ColorSet.rgb([Color.rgb(0xc8, 0x30, 0x4f), Color.rgb(0xb0, 0x5c, 0x00)]),
  ),
  'ocean': (
    _ColorSet.rgb([
      Color.rgb(0x5a, 0xa9, 0xe6),
      Color.rgb(0x4e, 0xcd, 0xc4),
      Color.rgb(0xc8, 0xf7, 0xe8),
    ]),
    _ColorSet.rgb([
      Color.rgb(0x1f, 0x5f, 0x99),
      Color.rgb(0x0f, 0x7f, 0x78),
      Color.rgb(0x2e, 0x7d, 0x4f),
    ]),
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

final class _FlowingState extends State<_Flowing> {
  late final _motion = Motion(() {
    if (mounted) {
      setState(() {});
    }
  });

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _motion.begin(context);
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
      final ms = _motion.now.inMilliseconds % _turn;
      gradient = Gradient(
        colors,
        stops: stops,
        phase: ms / _turn,
        direction: axis,
      );
      _motion.animate();
    } else {
      gradient = Gradient(colors, stops: stops, direction: axis);
    }
    _motion.end();
    return widget.build(context, gradient);
  }
}

/// The lines of the call [head]([args]) and [tail]: on one line where it
/// fits in 80 columns, else an argument a line with a comma after each.
List<String> _call(String head, List<String> args, String tail) {
  final one = '$head(${args.join(', ')})$tail';
  if (one.length <= 80) {
    return [one];
  }
  return ['$head(', for (final a in args) '  $a,', ')$tail'];
}

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

// --------------------------------------------------- the gradients' widgets

const _bgWidth = 44;
const _bgHeight = 9;
const _bgText = 'a box over a gradient';

/// "twk" in big letters, of block elements and box lines, a blank line and
/// two of text: what GradientForeground colours.
const _fgRows = [
  '████████╗██╗   ██╗██╗',
  '╚══██╔══╝██║   ██║██║',
  '   ██║   ██║   ██║██║',
  '   ██║   ██║   ██║██║',
  '   ██║   ╚██████╔╝██║',
  '   ╚═╝    ╚═════╝ ╚═╝',
  '',
  'Colors that change from glyph to glyph',
  'along each line, or down the rows.',
];
const _spanLead = 'a span: ';
const _spanText = 'Span.gradient, glyph by glyph';
