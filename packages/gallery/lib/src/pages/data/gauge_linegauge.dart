// The Gauge, LineGauge page.
part of 'data.dart';

/// The theme colours the Data pages offer, in the design's order.
const _colors = ['primary', 'accent', 'success', 'warning', 'info'];

// ------------------------------------------------------------ Gauge, LineGauge

const _gaugeW = 40;

const _fillMs = 7000;

const _holdMs = 2000;

const _gaugeTick = 25;

/// The ratio as the Code writes it while it stands still: `0.75`, `0.5`.
String _ratioLiteral(num percent) {
  final s = (percent / 100).toStringAsFixed(2);
  return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
}

final _gauge = GalleryPage(
  group: 'Data',
  title: 'Gauge, LineGauge',
  options: [
    const SwitchOption('live', 'live', initial: true),
    SliderOption(
      'ratio',
      'ratio',
      min: 0,
      max: 100,
      initial: 75,
      format: (v) => '$v%',
    ),
    const ChoiceOption(
      'line',
      'line',
      values: ['single', 'heavy', 'double', 'ascii'],
      initial: 'heavy',
    ),
    const ChoiceOption(
      'label',
      'label',
      values: ['own', 'ratio', 'none'],
    ),
    const ColorOption('color', 'style', values: _colors, initial: 'primary'),
    const SwitchOption('segmented', 'segmented'),
  ],
  build: (context, o) => Timed((context, ms, wake) {
    final control = PageControl.of(context);
    final kept = control.state;
    final ratio = o.number('ratio');
    // the ratio moved stops the timer: the gauges show the ratio chosen
    final moved = kept['ratio'] != null && kept['ratio'] != ratio;
    kept['ratio'] = ratio;
    final live = o.flag('live');
    if (moved && live) {
      scheduleMicrotask(() => control.setOption('live', false));
    }
    var r = ratio / 100;
    if (live && !moved) {
      final at = _tick(ms, _gaugeTick, wake) * _gaugeTick % (_fillMs + _holdMs);
      r = at < _fillMs ? at / _fillMs : 1;
    }
    final theme = Theme.of(context);
    final percent = '${(r * 100).round()}%';
    // a label of its own, the ratio the gauges write (null), or none
    final (gaugeLabel, lineLabel) = switch (o.choice<String>('label')) {
      'own' => (percent, 'used $percent'),
      'ratio' => (null, null),
      _ => ('', ''),
    };
    return SizedBox(
      width: _gaugeW,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        gap: 1,
        children: [
          SizedBox(
            height: 3,
            child: Gauge(
              ratio: r,
              label: gaugeLabel,
              style: o
                  .colorStyle(context, 'color')
                  .merge(Style(bg: theme.surface.bg)),
              labelStyle: const Style(attrs: Attr.bold),
            ),
          ),
          LineGauge(
            ratio: r,
            label: lineLabel,
            type: BorderType.values.byName(o.choice('line')),
            segmented: o.flag('segmented'),
            filledStyle: r > .9
                ? theme.error
                : r > .75
                ? theme.warning
                : theme.success,
            unfilledStyle: theme.border,
          ),
        ],
      ),
    );
  }),
  code: (o) {
    final state = o.flag('live')
        ? [
            'var _ratio = 0.0;',
            '',
            codeLine([
              '// from empty to full in ${_fillMs ~/ 1000} s, full for ',
              '${_holdMs ~/ 1000} s, and again',
            ]),
            ..._timer(_gaugeTick, [
              '(timer) {',
              codeLine([
                '  final ms = timer.tick * $_gaugeTick % ',
                '${_fillMs + _holdMs};',
              ]),
              '  setState(() => _ratio = ms < $_fillMs ? ms / $_fillMs : 1);',
              '},',
            ]),
          ]
        : ['final _ratio = ${_ratioLiteral(o.number('ratio'))};', ''];
    final label = o.choice<String>('label');
    return [
      ...state,
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      if (label == 'own') r"  final percent = '${(_ratio * 100).round()}%';",
      '  return SizedBox(',
      '    width: $_gaugeW,',
      '    child: Column(',
      '      mainAxisSize: .min,',
      '      crossAxisAlignment: .stretch,',
      '      gap: 1,',
      '      children: [',
      '        SizedBox(',
      '          height: 3,',
      '          child: Gauge(',
      '            ratio: _ratio,',
      if (label == 'own') '            label: percent,',
      if (label == 'none') "            label: '',",
      codeLine([
        '            style: theme.${o.color('color')}',
        '.merge(.new(bg: theme.surface.bg)),',
      ]),
      '            labelStyle: const .new(attrs: Attr.bold),',
      '          ),',
      '        ),',
      '        LineGauge(',
      '          ratio: _ratio,',
      if (label == 'own') r"          label: 'used $percent',",
      if (label == 'none') "          label: '',",
      '          type: .${o.label('line')},',
      if (o.flag('segmented')) '          segmented: true,',
      '          filledStyle: _ratio > .9',
      '              ? theme.error',
      '              : _ratio > .75',
      '              ? theme.warning',
      '              : theme.success,',
      '          unfilledStyle: theme.border,',
      '        ),',
      '      ],',
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);
