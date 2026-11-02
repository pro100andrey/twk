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

/// The Box page's `border` option.
const _boxBorder = ChoiceOption<String>(
  'border',
  'border',
  values: ['single', 'rounded', 'double', 'heavy', 'ascii', 'none'],
  initial: 'rounded',
);

/// The Box page's `sides` option.
final _boxSides = ChoiceOption<String>(
  'sides',
  'sides',
  values: _sides.keys.toList(),
);

/// The Box page's `titles` option.
const _boxTitles = SwitchOption('titles', 'titles', initial: true);

/// The Box page's `at` option.
final _boxAt = ChoiceOption<String>(
  'at',
  'title at',
  values: const [
    'topLeft',
    'topCenter',
    'topRight',
    'bottomLeft',
    'bottomCenter',
  ],
  disabled: (o) => !o(_boxTitles),
);

/// The Box page's `padding` option.
const _boxPadding = ChoiceOption<int>(
  'padding',
  'padding',
  values: [0, 1, 2],
  initial: 1,
);

/// The Box page's `surface` option.
const _boxSurface = SwitchOption('surface', 'surface');

final _box = GalleryPage(
  group: _group,
  title: 'Box',
  options: [
    _boxBorder,
    _boxSides,
    _boxTitles,
    _boxAt,
    _boxPadding,
    _boxSurface,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final type = BorderType.values.byName(o(_boxBorder));
    final sides = _sides[o(_boxSides)]!;
    Style? side(int bit) => sides & bit != 0 ? theme.border : null;
    return SizedBox(
      width: 36,
      height: 8,
      child: Box(
        style: o(_boxSurface) ? theme.surface : null,
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
          if (o(_boxTitles)) ...[
            BorderTitle(
              ' build ',
              style: theme.text.merge(const Style(attrs: Attr.bold)),
              alignment: alignmentByName[o(_boxAt)]!,
            ),
            BorderTitle(
              ' 2 warnings ',
              style: theme.warning,
              alignment: Alignment.bottomRight,
            ),
          ],
        ],
        padding: EdgeInsets.all(o(_boxPadding)),
        child: const Text(_build),
      ),
    );
  },
  code: (o) {
    final border = o.nameOf(_boxBorder);
    final type = border == 'single' ? <String>[] : ['type: .$border'];
    final sides = _sides[o(_boxSides)]!;
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 36,',
      '  height: 8,',
      '  child: Box(',
      if (o(_boxSurface)) '    style: theme.surface,',
      if (sides == _sides['all'])
        '    border: .all(${[...type, 'style: theme.border'].join(', ')}),'
      else
        ..._call(4, 'border: Border', [
          ...type,
          for (final (bit, name) in _sideNames)
            if (sides & bit != 0) '$name: theme.border',
        ], ','),
      if (o(_boxTitles)) ...[
        '    titles: [',
        '      BorderTitle(',
        "        ' build ',",
        '        style: theme.text.merge(const .new(attrs: Attr.bold)),',
        if (o(_boxAt) != 'topLeft') '        alignment: .${o.nameOf(_boxAt)},',
        '      ),',
        '      BorderTitle(',
        "        ' 2 warnings ',",
        '        style: theme.warning,',
        '        alignment: .bottomRight,',
        '      ),',
        '    ],',
      ],
      if (o(_boxPadding) != 0)
        '    padding: const .all(${o.nameOf(_boxPadding)}),',
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
