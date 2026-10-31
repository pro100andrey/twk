// The TerminalBrightness page.
part of 'style.dart';

/// The TerminalBrightness page's `brightness` option.
const _terminalbrightnessBrightness = ChoiceOption<String?>(
  'brightness',
  'brightness',
  values: [null, 'dark', 'light'],
  labels: ["the terminal's", 'dark', 'light'],
);

/// The TerminalBrightness page's `dark` option.
final _terminalbrightnessDark = ChoiceOption<String>(
  'dark',
  'dark theme',
  values: _darks.keys.toList(),
);

/// The TerminalBrightness page's `light` option.
final _terminalbrightnessLight = ChoiceOption<String>(
  'light',
  'light theme',
  values: _lights.keys.toList(),
);

final _terminalbrightnessPage = GalleryPage(
  group: _group,
  title: 'TerminalBrightness',
  options: [
    _terminalbrightnessBrightness,
    _terminalbrightnessDark,
    _terminalbrightnessLight,
  ],
  build: (context, o) {
    final adaptive = _Adaptive(
      dark: _darks[o(_terminalbrightnessDark)]!,
      light: _lights[o(_terminalbrightnessLight)]!,
    );
    // the gallery's theme stands in for the terminal's colours
    return TerminalBrightness(
      brightness: switch (o(_terminalbrightnessBrightness)) {
        'dark' => Brightness.dark,
        'light' => Brightness.light,
        _ => Theme.of(context).brightness,
      },
      child: adaptive,
    );
  },
  code: _brightnessCode,
);

/// The Code's doc of _Adaptive.
const _adaptiveDoc =
    '/// The brightness found here, and the theme [Theme.adaptive] picks by '
    'it.';

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
  final dark = _darks[o(_terminalbrightnessDark)]!.$1;
  final light = _lights[o(_terminalbrightnessLight)]!.$1;
  final brightness = o(_terminalbrightnessBrightness);
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
