// The Container page.
part of 'layout.dart';

// ------------------------------------------------------------ Container

const Map<String, Alignment> _containerAlignments = {
  'topLeft': Alignment.topLeft,
  'center': Alignment.center,
  'bottomRight': Alignment.bottomRight,
};

/// The Container page's `fill` option.
const _containerFill = ChoiceOption<String>(
  'fill',
  'fill',
  values: ['decoration', 'color'],
);

/// The Container page's `alignment` option.
const _containerAlignment = ChoiceOption<String?>(
  'alignment',
  'alignment',
  values: [null, 'topLeft', 'center', 'bottomRight'],
  labels: ['none', 'topLeft', 'center', 'bottomRight'],
  initial: 'center',
);

/// The Container page's `width` option.
const _containerWidth = ChoiceOption<int?>(
  'width',
  'width',
  values: [null, 24, 30, 36],
  initial: 30,
);

/// The Container page's `height` option.
const _containerHeight = ChoiceOption<int?>(
  'height',
  'height',
  values: [null, 5, 7, 9],
  initial: 7,
);

/// The Container page's `padding` option.
const _containerPadding = ChoiceOption<int>(
  'padding',
  'padding',
  values: [0, 1, 2],
  initial: 1,
);

/// The Container page's `margin` option.
const _containerMargin = ChoiceOption<int>(
  'margin',
  'margin',
  values: [0, 1, 2],
  initial: 1,
);

/// The Container page's `foreground` option.
const _containerForeground = SwitchOption(
  'foreground',
  'foreground',
);

final _container = GalleryPage(
  group: _group,
  title: 'Container',
  options: const [
    _containerFill,
    _containerAlignment,
    _containerWidth,
    _containerHeight,
    _containerPadding,
    _containerMargin,
    _containerForeground,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final margin = o(_containerMargin);
    final padding = o(_containerPadding);
    final decorated = o(_containerFill) == 'decoration';
    return Container(
      width: o(_containerWidth),
      height: o(_containerHeight),
      margin: margin > 0 ? EdgeInsets.all(margin) : null,
      padding: padding > 0 ? EdgeInsets.all(padding) : null,
      alignment: _containerAlignments[o(_containerAlignment)],
      decoration: decorated
          ? BoxDecoration(style: theme.surface, border: _rounded(theme))
          : null,
      color: decorated ? null : theme.surface.bg,
      foregroundDecoration: o(_containerForeground)
          ? BoxDecoration(
              border: Border(type: BorderType.heavy, left: theme.warning),
            )
          : null,
      child: const Text('deploy to staging'),
    );
  },
  code: (o) {
    final margin = o(_containerMargin);
    final padding = o(_containerPadding);
    final alignment = o(_containerAlignment);
    return [
      'final theme = Theme.of(context);',
      'return Container(',
      if (o(_containerWidth) case final w?) '  width: $w,',
      if (o(_containerHeight) case final h?) '  height: $h,',
      if (margin > 0) '  margin: const .all($margin),',
      if (padding > 0) '  padding: const .all($padding),',
      if (alignment != null) '  alignment: .$alignment,',
      if (o(_containerFill) == 'decoration') ...[
        '  decoration: BoxDecoration(',
        '    style: theme.surface,',
        '    border: .all(type: .rounded, style: theme.border),',
        '  ),',
      ] else
        '  color: theme.surface.bg,',
      if (o(_containerForeground)) ...[
        '  foregroundDecoration: BoxDecoration(',
        '    border: Border(type: .heavy, left: theme.warning),',
        '  ),',
      ],
      "  child: const Text('deploy to staging'),",
      ');',
    ].join('\n');
  },
);
