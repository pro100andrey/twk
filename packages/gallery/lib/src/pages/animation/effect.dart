// The Effect page.
part of 'animation.dart';

/// Each effect, as the Code writes it and as twk has it.
final _effects = <String, (String, CellEffect)>{
  'sweep': (
    'CellEffect.sweep(duration: _duration)',
    const CellEffect.sweep(duration: _duration),
  ),
  'dissolve': (
    'CellEffect.dissolve(duration: _duration)',
    const CellEffect.dissolve(duration: _duration),
  ),
  'typewriter': (
    'CellEffect.typewriter(duration: _duration)',
    const CellEffect.typewriter(duration: _duration),
  ),
  'glitch': (
    'CellEffect.glitch(duration: _duration)',
    const CellEffect.glitch(duration: _duration),
  ),
  'dim': (
    'CellEffect.dim(duration: _duration)',
    const CellEffect.dim(duration: _duration),
  ),
  'desaturate': (
    'CellEffect.desaturate(duration: _duration)',
    const CellEffect.desaturate(duration: _duration),
  ),
  'tint': (
    'CellEffect.tint(Color.blue, duration: _duration)',
    const CellEffect.tint(Color.blue, duration: _duration),
  ),
  'scanlines': ('CellEffect.scanlines()', const CellEffect.scanlines()),
  // the colors mapped by a function of the app's
  'grade': (
    'CellEffect.grade(_invert, duration: _duration)',
    const CellEffect.grade(_invert, duration: _duration),
  ),
  'sweep down, glitch': (
    'CellEffect.sequence([\n'
        '  CellEffect.sweep(from: .topCenter, duration: _duration),\n'
        '  CellEffect.glitch(duration: _duration),\n'
        '])',
    const CellEffect.sequence([
      CellEffect.sweep(from: .topCenter, duration: _duration),
      CellEffect.glitch(duration: _duration),
    ]),
  ),
};

final _effect = GalleryPage(
  group: 'Animation',
  title: 'Effect',
  options: [
    ChoiceOption('effect', 'effect', values: _effects.keys.toList()),
    _cycleOption,
  ],
  build: (context, o) => _Cycled(
    o,
    'effect',
    _effects.keys.toList(),
    (context, i) => _Effects(_effects.values.elementAt(i).$2),
  ),
  code: (o) {
    final name = o.choice<String>('effect');
    final effect = _effects[name]!.$1.split('\n');
    List<String> body(List<String> fx) => [
      'final theme = Theme.of(context);',
      'return Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      '    Box(',
      '      style: theme.surface,',
      '      border: .all(type: .rounded, style: theme.border),',
      '      child: Effect(',
      '        key: ValueKey(_runs),',
      ...fx,
      '        child: SizedBox(',
      '          width: 32,',
      '          height: 3,',
      '          child: Column(',
      '            crossAxisAlignment: .start,',
      '            children: [',
      "              Text('Effects over a subtree', style: theme.primary),",
      '              Row(',
      '                gap: 1,',
      '                children: [',
      '                  Spinner(style: theme.accent),',
      "                  const Text('repainting underneath'),",
      '                ],',
      '              ),',
      codeLine([
        "              Text('the cells it paints, filtered', ",
        'style: theme.muted),',
      ]),
      '            ],',
      '          ),',
      '        ),',
      '      ),',
      '    ),',
      '    Row(',
      '      mainAxisSize: .min,',
      '      gap: 2,',
      '      children: [',
      "        Button('Again', onPressed: () => setState(() => _runs++)),",
      "        Text('a new key runs it from its start', style: theme.muted),",
      '      ],',
      '    ),',
      '  ],',
      ');',
    ];
    final top = [
      'const _duration = Duration(milliseconds: 600);',
      '',
      // grade's map: a static method, which a const effect can name
      if (name == 'grade' || o.flag('cycle')) ...[
        '/// Each color as its opposite: the negative of a photograph.',
        'static Color _invert(Color c) =>',
        '    Color.rgb(255 - c.r, 255 - c.g, 255 - c.b);',
        '',
      ],
    ];
    if (!o.flag('cycle')) {
      final fx = [
        '        effect: const ${effect.first}',
        for (final l in effect.skip(1)) '        $l',
      ];
      fx[fx.length - 1] = '${fx.last},';
      return [
        ...top,
        'var _runs = 0;',
        '',
        '@override',
        'Widget build(BuildContext context) {',
        ..._indent(body(fx), 2),
        '}',
      ].join('\n');
    }
    return [
      ...top,
      ..._ticking(
        [
          'static const _effects = <CellEffect>[',
          for (final (dart, _) in _effects.values)
            '${[for (final l in dart.split('\n')) '  $l'].join('\n')},',
          '];',
          'var _i = ${_effects.keys.toList().indexOf(name)};',
          'var _runs = 0;',
        ],
        _nextOf('_effects'),
        'the next effect every 1.2 s, run from its start',
        body(['        effect: _effects[_i],']),
      ),
    ].join('\n');
  },
);

/// Each color as its opposite, as the Code's `_invert` makes it: the map
/// of the Effect page's grade.
Color _invert(Color c) => Color.rgb(255 - c.r, 255 - c.g, 255 - c.b);

/// The Code's State: [effect] over a subtree whose spinner repaints
/// underneath, run again from its start by a new key (Again).
final class _Effects extends StatefulWidget {
  const _Effects(this.effect);

  final CellEffect effect;

  @override
  State<_Effects> createState() => _EffectsState();
}

final class _EffectsState extends State<_Effects> {
  var _runs = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      gap: 1,
      children: [
        Box(
          style: theme.surface,
          border: .all(type: .rounded, style: theme.border),
          child: Effect(
            key: ValueKey(_runs),
            effect: widget.effect,
            child: SizedBox(
              width: 32,
              height: 3,
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text('Effects over a subtree', style: theme.primary),
                  Row(
                    gap: 1,
                    children: [
                      Spinner(style: theme.accent),
                      const Text('repainting underneath'),
                    ],
                  ),
                  Text('the cells it paints, filtered', style: theme.muted),
                ],
              ),
            ),
          ),
        ),
        Row(
          mainAxisSize: .min,
          gap: 2,
          children: [
            Button('Again', onPressed: () => setState(() => _runs++)),
            Text('a new key runs it from its start', style: theme.muted),
          ],
        ),
      ],
    );
  }
}
