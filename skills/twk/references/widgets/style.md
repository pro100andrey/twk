<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Style

Themes, the terminal’s brightness, and colors that run across a background or text.

[All widgets](../widgets.md)

## Theme

The styles of an app by what they are for, which the widgets below it draw in: a preset, or the terminal's own colors.

API: [`Theme`](https://pub.dev/documentation/twk/latest/twk/Theme-class.html).

### Code

```dart
const _themes = [
  ('terminal', ThemeData.terminal(Brightness.dark)),
  ('dark', ThemeData.dark),
  ('light', ThemeData.light),
  ('nord', ThemeData.nord),
  ('catppuccinMocha', ThemeData.catppuccinMocha),
  ('catppuccinLatte', ThemeData.catppuccinLatte),
];

final (name, data) = _themes[3];
return Theme(data: data, child: _Swatches(name));

/// Each style of the theme, named in it, on its background.
final class _Swatches extends StatefulWidget {
  const _Swatches(this.name);

  final String name;

  @override
  State<_Swatches> createState() => _SwatchesState();
}

final class _SwatchesState extends State<_Swatches> {
  var _checked = true;
  var _on = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
      width: 46,
      child: Box(
        style: theme.background.merge(theme.text),
        border: .all(type: .rounded, style: theme.border),
        titles: [
          BorderTitle(' ${widget.name} ', style: theme.text.merge(bold)),
        ],
        padding: const .x(2),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Text.rich([
              for (final (name, style) in text) Span('$name  ', style),
            ]),
            Text.rich([
              for (final (name, style) in status) Span('$name  ', style),
            ]),
            const SizedBox(height: 1),
            Box(
              style: theme.surface,
              border: .all(type: .rounded, style: theme.border),
              titles: [BorderTitle(' surface ', style: theme.muted)],
              padding: const .x(1),
              child: Text.rich([
                const Span('a panel, with '),
                Span(' selection ', theme.selection),
                const Span(' in it'),
              ]),
            ),
            const SizedBox(height: 1),
            Row(
              spacing: 3,
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
            const SizedBox(height: 1),
            const Row(
              spacing: 2,
              children: [
                StatusMessage('Saved', kind: StatusKind.success),
                Expanded(
                  child: LineGauge(
                    ratio: 0.6,
                    unfilledStyle: Style(attrs: Attr.dim),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const bold = Style(attrs: Attr.bold);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| theme | terminal, dark, light, nord, mocha, latte | nord |
| cycle | on, off | false |
| glyphs | unicode, ascii | unicode |

## TerminalBrightness

Whether the terminal is dark or light, as it reports it; Theme.adaptive picks a dark or a light theme by it.

API: [`TerminalBrightness`](https://pub.dev/documentation/twk/latest/twk/TerminalBrightness-class.html).

### Code

```dart
// the brightness the terminal reports, which the app puts at its top
return const _Adaptive();

/// The brightness found here, and the theme [Theme.adaptive] picks by it.
final class _Adaptive extends StatelessWidget {
  const _Adaptive();

  @override
  Widget build(BuildContext context) {
    final brightness = TerminalBrightness.of(context);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        Text.rich([
          const Span('The terminal is '),
          brightness.name.bold,
          const Span('.'),
        ]),
        Text.rich([
          const Span('Theme.adaptive picks '),
          switch (brightness) {
            Brightness.dark => 'nord'.bold,
            Brightness.light => 'catppuccinLatte'.bold,
          },
        ], style: Theme.of(context).muted),
        const Theme.adaptive(
          dark: ThemeData.nord,
          light: ThemeData.catppuccinLatte,
          child: _Swatches(),
        ),
      ],
    );
  }
}

/// Each style of the theme, named in it, on its background.
final class _Swatches extends StatelessWidget {
  const _Swatches();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
      width: 46,
      child: Box(
        style: theme.background.merge(theme.text),
        border: .all(type: .rounded, style: theme.border),
        padding: const .x(2),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Text.rich([
              for (final (name, style) in text) Span('$name  ', style),
            ]),
            Text.rich([
              for (final (name, style) in status) Span('$name  ', style),
            ]),
            const SizedBox(height: 1),
            Box(
              style: theme.surface,
              border: .all(type: .rounded, style: theme.border),
              titles: [BorderTitle(' surface ', style: theme.muted)],
              padding: const .x(1),
              child: Text.rich([
                const Span('a panel, with '),
                Span(' selection ', theme.selection),
                const Span(' in it'),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| brightness | the terminal's, dark, light | the terminal's |
| dark theme | nord, dark, mocha | nord |
| light theme | latte, light | latte |

## GradientBackground

A background whose color changes from cell to cell, along the columns or down the rows, from stop to stop.

API: [`GradientBackground`](https://pub.dev/documentation/twk/latest/twk/GradientBackground-class.html).

### Code

```dart
const _colors = [
  Color.rgb(0xff, 0x5f, 0x6d),
  Color.rgb(0xff, 0xc3, 0x71),
];

final class _BackdropState extends State<_Backdrop>
    with TickerProviderStateMixin {
  late final _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  )..repeat();

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _flow,
      builder: (context, _) {
        final gradient = Gradient(
          _colors,
          phase: _flow.value,
          direction: .horizontal,
        );
        return GradientBackground(
          gradient: gradient,
          child: SizedBox(
            width: 44,
            height: 9,
            child: Center(
              child: Box(
                style: Theme.of(context).surface,
                padding: const .only(left: 2, top: 1, right: 2, bottom: 1),
                child: const Text('a box over a gradient'),
              ),
            ),
          ),
        );
      },
    );
  }
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| colors | theme, sunset, ocean, palette | sunset |
| direction | columns, rows | columns |
| stops | even, inset, early | even |
| flow | on, off | true |

## GradientForeground

Text whose color changes from glyph to glyph along each line, or from line to line down the rows.

API: [`GradientForeground`](https://pub.dev/documentation/twk/latest/twk/GradientForeground-class.html).

### Code

```dart
final class _LetteringState extends State<_Lettering>
    with TickerProviderStateMixin {
  late final _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  )..repeat();

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = [theme.primary.fg!, theme.accent.fg!];
    return ListenableBuilder(
      listenable: _flow,
      builder: (context, _) {
        final gradient = Gradient(
          colors,
          phase: _flow.value,
          direction: .horizontal,
        );
        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          spacing: 1,
          children: [
            GradientForeground(
              gradient: gradient,
              child: const Text(
                '████████╗██╗   ██╗██╗\n'
                '╚══██╔══╝██║   ██║██║\n'
                '   ██║   ██║   ██║██║\n'
                '   ██║   ██║   ██║██║\n'
                '   ██║   ╚██████╔╝██║\n'
                '   ╚═╝    ╚═════╝ ╚═╝\n'
                '\n'
                'Colors that change from glyph to glyph\n'
                'along each line, or down the rows.'
              ),
            ),
            Text.rich([
              Span('a span: ', Theme.of(context).muted),
              'Span.gradient, glyph by glyph'.gradient(gradient),
            ]),
          ],
        );
      },
    );
  }
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| colors | theme, sunset, ocean, palette | theme |
| direction | columns, rows | columns |
| stops | even, inset, early | even |
| flow | on, off | true |
