// The Skeleton, Skeletonize page.
part of 'animation.dart';

// ------------------------------------------------------------ Skeleton

final _skeleton = GalleryPage(
  group: 'Animation',
  title: 'Skeleton, Skeletonize',
  options: const [
    SwitchOption('loading', 'loading', initial: true),
    SwitchOption('shimmer', 'shimmer', initial: true),
    ChoiceOption('glyph', 'glyph', values: ['░', '▒', '▓']),
    ChoiceOption('band', 'band', values: [8, 4, 16], labels: ['8', '4', '16']),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final shimmer = o.flag('shimmer');
    return SkeletonTheme(
      glyph: o.choice('glyph'),
      band: o.choice('band'),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        gap: 1,
        children: [
          SizedBox(
            width: 40,
            child: Box(
              border: .all(type: .rounded, style: theme.border),
              padding: const .x(1),
              child: Skeletonize(
                enabled: o.flag('loading'),
                shimmer: shimmer,
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: [
                    Text('user@twk', style: theme.primary),
                    const Text('Maintains twk and its gallery.'),
                    Text('Joined 19 October 2026', style: theme.muted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 40, child: Skeleton.text(lines: 3)),
          const Row(
            mainAxisSize: .min,
            gap: 1,
            children: [
              Skeleton(width: 8),
              Skeleton(width: 12),
            ],
          ),
        ],
      ),
    );
  },
  code: (o) {
    final glyph = o.choice<String>('glyph');
    final band = o.choice<int>('band');
    final args = [
      if (glyph != '░') "glyph: '$glyph'",
      if (band != 8) 'band: $band',
    ];
    return [
      'final theme = Theme.of(context);',
      'return SkeletonTheme(',
      for (final a in args) '  $a,',
      '  child: Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      SizedBox(',
      '        width: 40,',
      '        child: Box(',
      '          border: .all(type: .rounded, style: theme.border),',
      '          padding: const .x(1),',
      '          // laid out as it is, drawn as blocks while it loads',
      '          child: Skeletonize(',
      '            enabled: ${o.flag('loading')},',
      if (!o.flag('shimmer')) '            shimmer: false,',
      '            child: Column(',
      '              mainAxisSize: .min,',
      '              crossAxisAlignment: .start,',
      '              children: [',
      "                Text('user@twk', style: theme.primary),",
      "                const Text('Maintains twk and its gallery.'),",
      "                Text('Joined 19 October 2026', style: theme.muted),",
      '              ],',
      '            ),',
      '          ),',
      '        ),',
      '      ),',
      '      // blocks of their own: three lines, and two words',
      '      const SizedBox(width: 40, child: Skeleton.text(lines: 3)),',
      '      const Row(',
      '        mainAxisSize: .min,',
      '        gap: 1,',
      '        children: [Skeleton(width: 8), Skeleton(width: 12)],',
      '      ),',
      '    ],',
      '  ),',
      ');',
    ].join('\n');
  },
);
