// The Skeleton, Skeletonize page.
part of 'animation.dart';

/// The Skeleton, Skeletonize page's `loading` option.
const _skeletonLoading = SwitchOption(
  'loading',
  'loading',
  initial: true,
);

/// The Skeleton, Skeletonize page's `shimmer` option.
const _skeletonShimmer = SwitchOption(
  'shimmer',
  'shimmer',
  initial: true,
);

/// The Skeleton, Skeletonize page's `glyph` option.
const _skeletonGlyph = ChoiceOption<String>(
  'glyph',
  'glyph',
  values: ['░', '▒', '▓'],
);

/// The Skeleton, Skeletonize page's `band` option.
const _skeletonBand = ChoiceOption<int>(
  'band',
  'band',
  values: [8, 4, 16],
  labels: ['8', '4', '16'],
);

// ------------------------------------------------------------ Skeleton

final _skeleton = GalleryPage(
  group: _group,
  title: 'Skeleton, Skeletonize',
  options: const [
    _skeletonLoading,
    _skeletonShimmer,
    _skeletonGlyph,
    _skeletonBand,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final shimmer = o(_skeletonShimmer);
    return SkeletonTheme(
      glyph: o(_skeletonGlyph),
      band: o(_skeletonBand),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 1,
        children: [
          SizedBox(
            width: 40,
            child: Box(
              border: .all(type: .rounded, style: theme.border),
              padding: const .x(1),
              child: Skeletonize(
                enabled: o(_skeletonLoading),
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
            spacing: 1,
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
    final glyph = o(_skeletonGlyph);
    final band = o(_skeletonBand);
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
      '    spacing: 1,',
      '    children: [',
      '      SizedBox(',
      '        width: 40,',
      '        child: Box(',
      '          border: .all(type: .rounded, style: theme.border),',
      '          padding: const .x(1),',
      '          // laid out as it is, drawn as blocks while it loads',
      '          child: Skeletonize(',
      '            enabled: ${o(_skeletonLoading)},',
      if (!o(_skeletonShimmer)) '            shimmer: false,',
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
      '        spacing: 1,',
      '        children: [Skeleton(width: 8), Skeleton(width: 12)],',
      '      ),',
      '    ],',
      '  ),',
      ');',
    ].join('\n');
  },
);
