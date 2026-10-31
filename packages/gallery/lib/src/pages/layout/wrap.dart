// The Wrap page.
part of 'layout.dart';

// ------------------------------------------------------------ Wrap

// the label and the kind of each badge, null for the box
const List<(String, StatusKind?, bool)> _tags = [
  ('dart', null, true),
  ('terminal', StatusKind.info, true),
  ('a box', null, false),
  ('twk', StatusKind.success, true),
  ('日本語', StatusKind.warning, true),
  ('layout', null, true),
  ('runs', StatusKind.info, true),
];

const List<String> _wrapAlign = _main;

const _wh = 11;

/// The room narrows a cell this often while live.
const _narrow = 120;

final _wrap = GalleryPage(
  group: 'Layout',
  title: 'Wrap',
  options: [
    SliderOption(
      'width',
      'width',
      min: 20,
      max: 48,
      initial: 36,
      format: (v) => '$v cells',
    ),
    const SwitchOption('live', 'narrowing'),
    const ChoiceOption(
      'direction',
      'direction',
      values: ['horizontal', 'vertical'],
    ),
    const ChoiceOption('alignment', 'alignment', values: _wrapAlign),
    const ChoiceOption('runAlignment', 'run alignment', values: _wrapAlign),
    const ChoiceOption(
      'cross',
      'cross axis',
      values: ['start', 'end', 'center'],
      initial: 'center',
    ),
    const ChoiceOption('gap', 'gap', values: [0, 1, 2], initial: 1),
    const ChoiceOption('runGap', 'run gap', values: [0, 1]),
  ],
  build: (context, o) => Timed((context, ms, wake) {
    var width = o.number('width').toInt();
    if (o.flag('live')) {
      // a cell narrower every 120 ms from 48 to 20 and back, the slider
      // following it
      final step = ms ~/ _narrow;
      wake((step + 1) * _narrow);
      final w = 20 + (step % 56 - 28).abs();
      if (w != width) {
        final control = PageControl.of(context);
        scheduleMicrotask(() => control.setOption('width', w));
      }
      width = w;
    }
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      height: _wh,
      child: Box(
        border: _rounded(theme),
        child: Wrap(
          direction: Axis.values.byName(o.choice('direction')),
          alignment: WrapAlignment.values.byName(o.choice('alignment')),
          runAlignment: WrapAlignment.values.byName(o.choice('runAlignment')),
          crossAxisAlignment: WrapCrossAlignment.values.byName(
            o.choice('cross'),
          ),
          gap: o.choice('gap'),
          runGap: o.choice('runGap'),
          children: [
            for (final (label, kind, badge) in _tags)
              if (badge)
                Badge(label, kind: kind)
              else
                Box(border: _rounded(theme), child: Text(label)),
          ],
        ),
      ),
    );
  }),
  code: (o) {
    final wrap = [
      '    child: Wrap(',
      if (o['direction'] != 'horizontal') '      direction: .vertical,',
      if (o['alignment'] != 'start')
        '      alignment: .${o.label('alignment')},',
      if (o['runAlignment'] != 'start')
        '      runAlignment: .${o.label('runAlignment')},',
      if (o['cross'] != 'start')
        '      crossAxisAlignment: .${o.label('cross')},',
      if (o['gap'] != 0) '      gap: ${o.label('gap')},',
      if (o['runGap'] != 0) '      runGap: ${o.label('runGap')},',
      '      children: [',
      for (final (label, kind, badge) in _tags)
        if (!badge) ...[
          '        Box(',
          '          border: .all(type: .rounded, style: theme.border),',
          "          child: const Text('a box'),",
          '        ),',
        ] else if (kind == null)
          "        const Badge('$label'),"
        else
          "        const Badge('$label', kind: .${kind.name}),",
      '      ],',
      '    ),',
    ];
    if (!o.flag('live')) {
      return [
        'final theme = Theme.of(context);',
        'return SizedBox(',
        '  width: ${o.label('width')},',
        '  height: $_wh,',
        '  child: Box(',
        '    border: .all(type: .rounded, style: theme.border),',
        ...wrap,
        '  ),',
        ');',
      ].join('\n');
    }
    return [
      '// the room narrows a cell at a time, from 48 to 20 and back',
      'late final Timer _timer;',
      'var _step = 0;',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  _timer = Timer.periodic(',
      '    const Duration(milliseconds: $_narrow),',
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
      '  final theme = Theme.of(context);',
      '  return SizedBox(',
      '    width: 20 + (_step % 56 - 28).abs(),',
      '    height: $_wh,',
      '    child: Box(',
      '      border: .all(type: .rounded, style: theme.border),',
      for (final l in wrap) '  $l',
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);
