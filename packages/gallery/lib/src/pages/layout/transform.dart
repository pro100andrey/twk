// The Transform page.
part of 'layout.dart';

/// The offsets the chip goes round, a step every [_move] ms.
const _round = [
  (0, -2), (5, -2), (9, -1), (10, 0), //
  (9, 1), (5, 2), (0, 2), (-5, 2), //
  (-9, 1), (-10, 0), (-9, -1), (-5, -2),
];

const _move = 200;

final _transform = GalleryPage(
  group: 'Layout',
  title: 'Transform',
  options: [
    const ChoiceOption('move', 'offset', values: ['round', 'fixed']),
    SliderOption(
      'dx',
      'dx',
      min: -12,
      max: 12,
      initial: 6,
      format: (v) => '$v cells',
      disabled: (o) => o['move'] != 'fixed',
    ),
    SliderOption(
      'dy',
      'dy',
      min: -2,
      max: 2,
      initial: 1,
      format: (v) => '$v rows',
      disabled: (o) => o['move'] != 'fixed',
    ),
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
    if (o['move'] == 'fixed') {
      return moved((o.number('dx').toInt(), o.number('dy').toInt()));
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
    if (o['move'] == 'fixed') {
      return build('(${o.label('dx')}, ${o.label('dy')})').join('\n');
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
