// The Shadow page.
part of 'layout.dart';

// ------------------------------------------------------------ Shadow

const _offsets = {'2, 1': (2, 1), '1, 1': (1, 1), '-2, -1': (-2, -1)};

const _shadowed = 'a box with a shadow';

const _wall = 'what is under a shadow keeps its glyphs; their colours darken. ';

/// The Shadow page's `offset` option.
final _shadowOffset = ChoiceOption<String>(
  'offset',
  'offset',
  values: _offsets.keys.toList(),
);

/// The Shadow page's `alpha` option.
const _shadowAlpha = ChoiceOption<int>(
  'alpha',
  'alpha',
  values: [0x40, 0x80, 0xc0],
  labels: ['¼', '½', '¾'],
  initial: 0x80,
);

final _shadow = GalleryPage(
  group: _group,
  title: 'Shadow',
  options: [
    _shadowOffset,
    _shadowAlpha,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final (dx, dy) = _offsets[o(_shadowOffset)]!;
    return SizedBox(
      width: 36,
      height: 8,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Text(_wall * 5, style: theme.muted),
          Positioned(
            left: 5,
            top: 2,
            child: Shadow(
              shadow: BoxShadow(dx: dx, dy: dy, alpha: o(_shadowAlpha)),
              child: Box(
                style: theme.surface.merge(theme.text),
                border: _rounded(theme),
                padding: const EdgeInsets.x(1),
                child: const Text(_shadowed),
              ),
            ),
          ),
        ],
      ),
    );
  },
  code: (o) {
    final (dx, dy) = _offsets[o(_shadowOffset)]!;
    final alpha = o(_shadowAlpha);
    final args = [
      if (dx != 2) 'dx: $dx',
      if (dy != 1) 'dy: $dy',
      if (alpha != 0x80) 'alpha: 0x${alpha.toRadixString(16)}',
    ];
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 36,',
      '  height: 8,',
      '  child: Stack(',
      '    fit: .expand,',
      '    children: [',
      '      Text(',
      "        '$_wall' * 5,",
      '        style: theme.muted,',
      '      ),',
      '      Positioned(',
      '        left: 5,',
      '        top: 2,',
      '        child: Shadow(',
      '          shadow: const BoxShadow(${args.join(', ')}),',
      '          child: Box(',
      '            style: theme.surface.merge(theme.text),',
      '            border: .all(type: .rounded, style: theme.border),',
      '            padding: const .x(1),',
      "            child: const Text('$_shadowed'),",
      '          ),',
      '        ),',
      '      ),',
      '    ],',
      '  ),',
      ');',
    ].join('\n');
  },
);
