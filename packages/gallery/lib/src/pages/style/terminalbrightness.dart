// The TerminalBrightness page.
part of 'style.dart';

final _terminalbrightnessPage = GalleryPage(
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
