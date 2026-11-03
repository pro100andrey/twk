// The Divider page.
part of 'layout.dart';

/// The Divider page's `type` option.
const _dividerType = ChoiceOption<String>(
  'type',
  'type',
  values: ['single', 'rounded', 'double', 'heavy', 'ascii'],
);

/// The Divider page's `merge` option.
const _dividerMerge = SwitchOption(
  'merge',
  'merge',
  initial: true,
);

// ------------------------------------------------------------ Divider

final _divider = GalleryPage(
  group: _group,
  title: 'Divider',
  options: const [
    _dividerType,
    _dividerMerge,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final type = BorderType.values.byName(o(_dividerType));
    final merge = o(_dividerMerge);
    return SizedBox(
      width: 36,
      height: 7,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Box(
            border: Border.all(type: type, style: theme.border),
          ),
          const Positioned(
            left: 2,
            top: 1,
            child: Text('release 0.4.0', style: Style(attrs: Attr.bold)),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 2,
            child: Divider(type: type, style: theme.border, merge: merge),
          ),
          Positioned(
            left: 17,
            top: 2,
            bottom: 0,
            child: VerticalDivider(
              type: type,
              style: theme.border,
              merge: merge,
            ),
          ),
          Positioned(
            left: 2,
            top: 3,
            child: Text('added', style: theme.muted),
          ),
          const Positioned(
            left: 2,
            top: 4,
            child: Text('Grid tracks\nDockArea'),
          ),
          Positioned(
            left: 19,
            top: 3,
            child: Text('fixed', style: theme.muted),
          ),
          const Positioned(
            left: 19,
            top: 4,
            child: Text('wide glyphs\nwheel scroll'),
          ),
        ],
      ),
    );
  },
  code: (o) {
    final type = o(_dividerType) == 'single'
        ? ''
        : 'type: .${o.nameOf(_dividerType)}, ';
    final args = [
      if (type.isNotEmpty) type.substring(0, type.length - 2),
      'style: theme.border',
      if (o(_dividerMerge)) 'merge: true',
    ];
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 36,',
      '  height: 7,',
      '  child: Stack(',
      '    fit: .expand,',
      '    children: [',
      '      Box(border: .all(${type}style: theme.border)),',
      '      const Positioned(',
      '        left: 2,',
      '        top: 1,',
      "        child: Text('release 0.4.0', style: .new(attrs: Attr.bold)),",
      '      ),',
      '      Positioned(',
      '        left: 0,',
      '        right: 0,',
      '        top: 2,',
      ..._call(8, 'child: Divider', args, ','),
      '      ),',
      '      Positioned(',
      '        left: 17,',
      '        top: 2,',
      '        bottom: 0,',
      ..._call(8, 'child: VerticalDivider', args, ','),
      '      ),',
      codeLine([
        '      Positioned(left: 2, top: 3, ',
        "child: Text('added', style: theme.muted)),",
      ]),
      r"      const Positioned(left: 2, top: 4, child: Text('Grid tracks\nDockArea')),",
      codeLine([
        '      Positioned(left: 19, top: 3, ',
        "child: Text('fixed', style: theme.muted)),",
      ]),
      '      const Positioned(',
      '        left: 19,',
      '        top: 4,',
      r"        child: Text('wide glyphs\nwheel scroll'),",
      '      ),',
      '    ],',
      '  ),',
      ');',
    ].join('\n');
  },
);
