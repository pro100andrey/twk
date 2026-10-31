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

/// The Wrap page's `width` option.
final _wrapWidth = SliderOption(
  'width',
  'width',
  min: 20,
  max: 48,
  initial: 36,
  format: (v) => '$v cells',
);

/// The Wrap page's `live` option.
const _wrapLive = SwitchOption('live', 'narrowing');

/// The Wrap page's `direction` option.
const _wrapDirection = ChoiceOption<String>(
  'direction',
  'direction',
  values: ['horizontal', 'vertical'],
);

/// The Wrap page's `alignment` option.
const _wrapAlignment = ChoiceOption<String>(
  'alignment',
  'alignment',
  values: _wrapAlign,
);

/// The Wrap page's `runAlignment` option.
const _wrapRunAlignment = ChoiceOption<String>(
  'runAlignment',
  'run alignment',
  values: _wrapAlign,
);

/// The Wrap page's `cross` option.
const _wrapCross = ChoiceOption<String>(
  'cross',
  'cross axis',
  values: ['start', 'end', 'center'],
  initial: 'center',
);

/// The Wrap page's `gap` option.
const _wrapGap = ChoiceOption<int>(
  'gap',
  'gap',
  values: [0, 1, 2],
  initial: 1,
);

/// The Wrap page's `runGap` option.
const _wrapRunGap = ChoiceOption<int>(
  'runGap',
  'run gap',
  values: [0, 1],
);

final _wrap = GalleryPage(
  group: _group,
  title: 'Wrap',
  options: [
    _wrapWidth,
    _wrapLive,
    _wrapDirection,
    _wrapAlignment,
    _wrapRunAlignment,
    _wrapCross,
    _wrapGap,
    _wrapRunGap,
  ],
  build: (context, o) => Timed((context, ms, wake) {
    var width = o(_wrapWidth).toInt();
    if (o(_wrapLive)) {
      // a cell narrower every 120 ms from 48 to 20 and back, the slider
      // following it
      final step = ms ~/ _narrow;
      wake((step + 1) * _narrow);
      final w = 20 + (step % 56 - 28).abs();
      if (w != width) {
        final control = PageControl.of(context);
        scheduleMicrotask(() => control.setOption(_wrapWidth, w));
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
          direction: Axis.values.byName(o(_wrapDirection)),
          alignment: WrapAlignment.values.byName(o(_wrapAlignment)),
          runAlignment: WrapAlignment.values.byName(o(_wrapRunAlignment)),
          crossAxisAlignment: WrapCrossAlignment.values.byName(
            o(_wrapCross),
          ),
          gap: o(_wrapGap),
          runGap: o(_wrapRunGap),
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
      if (o(_wrapDirection) != 'horizontal') '      direction: .vertical,',
      if (o(_wrapAlignment) != 'start')
        '      alignment: .${o.nameOf(_wrapAlignment)},',
      if (o(_wrapRunAlignment) != 'start')
        '      runAlignment: .${o.nameOf(_wrapRunAlignment)},',
      if (o(_wrapCross) != 'start')
        '      crossAxisAlignment: .${o.nameOf(_wrapCross)},',
      if (o(_wrapGap) != 0) '      gap: ${o.nameOf(_wrapGap)},',
      if (o(_wrapRunGap) != 0) '      runGap: ${o.nameOf(_wrapRunGap)},',
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
    if (!o(_wrapLive)) {
      return [
        'final theme = Theme.of(context);',
        'return SizedBox(',
        '  width: ${o.nameOf(_wrapWidth)},',
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
