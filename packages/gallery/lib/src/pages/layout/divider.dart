// The Divider page.
part of 'layout.dart';

// ------------------------------------------------------------ Divider

final _divider = GalleryPage(
  group: 'Layout',
  title: 'Divider',
  options: const [
    ChoiceOption(
      'type',
      'type',
      values: ['single', 'rounded', 'double', 'heavy', 'ascii'],
    ),
    SwitchOption('merge', 'merge', initial: true),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final type = BorderType.values.byName(o.choice('type'));
    final merge = o.flag('merge');
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
    final type = o['type'] == 'single' ? '' : 'type: .${o.label('type')}, ';
    final args = [
      if (type.isNotEmpty) type.substring(0, type.length - 2),
      'style: theme.border',
      if (o.flag('merge')) 'merge: true',
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
