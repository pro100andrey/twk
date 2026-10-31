// The Container page.
part of 'layout.dart';

// ------------------------------------------------------------ Container

const Map<String, Alignment> _containerAlignments = {
  'topLeft': Alignment.topLeft,
  'center': Alignment.center,
  'bottomRight': Alignment.bottomRight,
};

final _container = GalleryPage(
  group: 'Layout',
  title: 'Container',
  options: const [
    ChoiceOption('fill', 'fill', values: ['decoration', 'color']),
    ChoiceOption(
      'alignment',
      'alignment',
      values: [null, 'topLeft', 'center', 'bottomRight'],
      labels: ['none', 'topLeft', 'center', 'bottomRight'],
      initial: 'center',
    ),
    ChoiceOption('width', 'width', values: [null, 24, 30, 36], initial: 30),
    ChoiceOption('height', 'height', values: [null, 5, 7, 9], initial: 7),
    ChoiceOption('padding', 'padding', values: [0, 1, 2], initial: 1),
    ChoiceOption('margin', 'margin', values: [0, 1, 2], initial: 1),
    SwitchOption('foreground', 'foreground'),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final margin = o.choice<int>('margin');
    final padding = o.choice<int>('padding');
    final decorated = o['fill'] == 'decoration';
    return Container(
      width: o.choice('width'),
      height: o.choice('height'),
      margin: margin > 0 ? EdgeInsets.all(margin) : null,
      padding: padding > 0 ? EdgeInsets.all(padding) : null,
      alignment: _containerAlignments[o['alignment']],
      decoration: decorated
          ? BoxDecoration(style: theme.surface, border: _rounded(theme))
          : null,
      color: decorated ? null : theme.surface.bg,
      foregroundDecoration: o.flag('foreground')
          ? BoxDecoration(
              border: Border(type: BorderType.heavy, left: theme.warning),
            )
          : null,
      child: const Text('deploy to staging'),
    );
  },
  code: (o) {
    final margin = o.choice<int>('margin');
    final padding = o.choice<int>('padding');
    final alignment = o['alignment'];
    return [
      'final theme = Theme.of(context);',
      'return Container(',
      if (o.choice<int?>('width') case final w?) '  width: $w,',
      if (o.choice<int?>('height') case final h?) '  height: $h,',
      if (margin > 0) '  margin: const .all($margin),',
      if (padding > 0) '  padding: const .all($padding),',
      if (alignment != null) '  alignment: .$alignment,',
      if (o['fill'] == 'decoration') ...[
        '  decoration: BoxDecoration(',
        '    style: theme.surface,',
        '    border: .all(type: .rounded, style: theme.border),',
        '  ),',
      ] else
        '  color: theme.surface.bg,',
      if (o.flag('foreground')) ...[
        '  foregroundDecoration: BoxDecoration(',
        '    border: Border(type: .heavy, left: theme.warning),',
        '  ),',
      ],
      "  child: const Text('deploy to staging'),",
      ');',
    ].join('\n');
  },
);
