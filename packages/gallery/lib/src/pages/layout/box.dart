// The Box page.
part of 'layout.dart';

// ------------------------------------------------------------ Box

const _u = 1;

const _r = 2;

const _d = 4;

const _l = 8;

const Map<String, int> _sides = {
  'all': _u | _r | _d | _l,
  'top bottom': _u | _d,
  'top left': _u | _l,
  'left': _l,
};

const List<(int, String)> _sideNames = [
  (_u, 'top'),
  (_r, 'right'),
  (_d, 'bottom'),
  (_l, 'left'),
];

const _build =
    'Compiling 14 libraries…\n'
    'lib/src/layout    0.4 s\n'
    'lib/src/render    0.9 s';

final _box = GalleryPage(
  group: 'Layout',
  title: 'Box',
  options: [
    const ChoiceOption(
      'border',
      'border',
      values: ['single', 'rounded', 'double', 'heavy', 'ascii', 'none'],
      initial: 'rounded',
    ),
    ChoiceOption('sides', 'sides', values: _sides.keys.toList()),
    const SwitchOption('titles', 'titles', initial: true),
    ChoiceOption(
      'at',
      'title at',
      values: const [
        'topLeft',
        'topCenter',
        'topRight',
        'bottomLeft',
        'bottomCenter',
      ],
      disabled: (o) => !o.flag('titles'),
    ),
    const ChoiceOption('padding', 'padding', values: [0, 1, 2], initial: 1),
    const SwitchOption('surface', 'surface'),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final type = BorderType.values.byName(o.choice('border'));
    final sides = _sides[o.choice<String>('sides')]!;
    Style? side(int bit) => sides & bit != 0 ? theme.border : null;
    return SizedBox(
      width: 36,
      height: 8,
      child: Box(
        style: o.flag('surface') ? theme.surface : null,
        border: sides == _sides['all']
            ? Border.all(type: type, style: theme.border)
            : Border(
                type: type,
                top: side(_u),
                right: side(_r),
                bottom: side(_d),
                left: side(_l),
              ),
        titles: [
          if (o.flag('titles')) ...[
            BorderTitle(
              ' build ',
              style: theme.text.merge(const Style(attrs: Attr.bold)),
              alignment: alignmentByName[o.choice<String>('at')]!,
            ),
            BorderTitle(
              ' 2 warnings ',
              style: theme.warning,
              alignment: Alignment.bottomRight,
            ),
          ],
        ],
        padding: EdgeInsets.all(o.choice<int>('padding')),
        child: const Text(_build),
      ),
    );
  },
  code: (o) {
    final border = o.label('border');
    final type = border == 'single' ? <String>[] : ['type: .$border'];
    final sides = _sides[o.choice<String>('sides')]!;
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 36,',
      '  height: 8,',
      '  child: Box(',
      if (o.flag('surface')) '    style: theme.surface,',
      if (sides == _sides['all'])
        '    border: .all(${[...type, 'style: theme.border'].join(', ')}),'
      else
        ..._call(4, 'border: Border', [
          ...type,
          for (final (bit, name) in _sideNames)
            if (sides & bit != 0) '$name: theme.border',
        ], ','),
      if (o.flag('titles')) ...[
        '    titles: [',
        '      BorderTitle(',
        "        ' build ',",
        '        style: theme.text.merge(const .new(attrs: Attr.bold)),',
        if (o['at'] != 'topLeft') '        alignment: .${o.label('at')},',
        '      ),',
        '      BorderTitle(',
        "        ' 2 warnings ',",
        '        style: theme.warning,',
        '        alignment: .bottomRight,',
        '      ),',
        '    ],',
      ],
      if (o['padding'] != 0) '    padding: const .all(${o.label('padding')}),',
      '    child: const Text(',
      r"      'Compiling 14 libraries…\n'",
      r"      'lib/src/layout    0.4 s\n'",
      "      'lib/src/render    0.9 s',",
      '    ),',
      '  ),',
      ');',
    ].join('\n');
  },
);
