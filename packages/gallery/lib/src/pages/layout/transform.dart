// The Transform page.
part of 'layout.dart';

/// The offsets the chip goes round, a step every [_move] ms.
const _round = [
  (0, -2), (5, -2), (9, -1), (10, 0), //
  (9, 1), (5, 2), (0, 2), (-5, 2), //
  (-9, 1), (-10, 0), (-9, -1), (-5, -2),
];

const _move = 200;

/// The Transform page's `move` option.
const _transformMove = ChoiceOption<String>(
  'move',
  'offset',
  values: ['round', 'fixed'],
);

/// The Transform page's `dx` option.
final _transformDx = SliderOption(
  'dx',
  'dx',
  min: -12,
  max: 12,
  initial: 6,
  format: (v) => '$v cells',
  disabled: (o) => o(_transformMove) != 'fixed',
);

/// The Transform page's `dy` option.
final _transformDy = SliderOption(
  'dy',
  'dy',
  min: -2,
  max: 2,
  initial: 1,
  format: (v) => '$v rows',
  disabled: (o) => o(_transformMove) != 'fixed',
);

final _transform = GalleryPage(
  group: _group,
  title: 'Transform',
  options: [
    _transformMove,
    _transformDx,
    _transformDy,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    Widget moved((int, int) offset) => SizedBox(
      width: 32,
      height: 7,
      child: Box(
        border: _rounded(theme),
        child: Transform.translate(
          offset: offset,
          child: Center(
            child: Box(
              style: theme.selection,
              padding: const EdgeInsets.x(1),
              child: const Text('moved'),
            ),
          ),
        ),
      ),
    );
    if (o(_transformMove) == 'fixed') {
      return moved((o(_transformDx).toInt(), o(_transformDy).toInt()));
    }
    return _Ticks(
      ms: _move,
      builder: (context, steps) => moved(_round[steps % _round.length]),
    );
  },
  code: (o) {
    List<String> build(String offset) => [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 32,',
      '  height: 7,',
      '  child: Box(',
      '    border: .all(type: .rounded, style: theme.border),',
      '    child: Transform.translate(',
      '      offset: $offset,',
      '      child: Center(',
      '        child: Box(',
      '          style: theme.selection,',
      '          padding: const .x(1),',
      "          child: const Text('moved'),",
      '        ),',
      '      ),',
      '    ),',
      '  ),',
      ');',
    ];
    if (o(_transformMove) == 'fixed') {
      return build('(${o.nameOf(_transformDx)}, ${o.nameOf(_transformDy)})')
          .join('\n');
    }
    final path = [for (final (x, y) in _round) '($x, $y)'];
    return [
      'const _round = [',
      for (final i in const [0, 4, 8])
        '  ${path.sublist(i, i + 4).join(', ')},',
      '];',
      '',
      'var _step = 0;',
      'late final Timer _timer;',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  _timer = Timer.periodic(',
      '    const Duration(milliseconds: $_move),',
      '    (_) => setState(() => _step++),',
      '  );',
      '}',
      '',
      '@override',
      'void dispose() {',
      '  _timer.cancel();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      for (final l in build('_round[_step % _round.length]')) '  $l',
      '}',
    ].join('\n');
  },
);
