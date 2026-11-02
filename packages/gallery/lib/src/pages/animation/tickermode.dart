// The TickerMode page.
part of 'animation.dart';

/// The TickerMode page's `enabled` option.
const _tickerEnabled = SwitchOption('enabled', 'enabled', initial: true);

// ------------------------------------------------------------ TickerMode

final _tickerMode = GalleryPage(
  group: _group,
  title: 'TickerMode',
  options: [_tickerEnabled],
  build: (context, o) => TickerMode(
    enabled: o(_tickerEnabled),
    child: Row(
      mainAxisSize: .min,
      gap: 1,
      children: [
        Spinner(style: Theme.of(context).primary),
        const Text('Compiling…'),
      ],
    ),
  ),
  code: (o) => [
    'final theme = Theme.of(context);',
    'return TickerMode(',
    '  enabled: ${o(_tickerEnabled)},',
    '  child: Row(',
    '    mainAxisSize: .min,',
    '    gap: 1,',
    '    children: [',
    '      Spinner(style: theme.primary),',
    "      const Text('Compiling…'),",
    '    ],',
    '  ),',
    ');',
  ].join('\n'),
);
