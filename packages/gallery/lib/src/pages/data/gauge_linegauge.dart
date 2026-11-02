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

/// The Gauge, LineGauge page's `live` option.
const _gaugeLive = SwitchOption('live', 'live', initial: true);

/// The Gauge, LineGauge page's `ratio` option.
final _gaugeRatio = SliderOption(
  'ratio',
  'ratio',
  min: 0,
  max: 100,
  initial: 75,
  format: (v) => '$v%',
);

/// The Gauge, LineGauge page's `line` option.
const _gaugeLine = ChoiceOption<String>(
  'line',
  'line',
  values: ['single', 'heavy', 'double', 'ascii'],
  initial: 'heavy',
);

/// The Gauge, LineGauge page's `label` option.
const _gaugeLabel = ChoiceOption<String>(
  'label',
  'label',
  values: ['own', 'percent', 'none'],
);

/// The Gauge, LineGauge page's `color` option.
const _gaugeColor = ColorOption(
  'color',
  'style',
  values: _colors,
  initial: 'primary',
);

/// The Gauge, LineGauge page's `segmented` option.
const _gaugeSegmented = SwitchOption('segmented', 'segmented');

final _gauge = GalleryPage(
  group: _group,
  title: 'Gauge, LineGauge',
  options: [
    _gaugeLive,
    _gaugeRatio,
    _gaugeLine,
    _gaugeLabel,
    _gaugeColor,
    _gaugeSegmented,
  ],
  build: (context, o) => Timed((context, ms, wake) {
    final control = PageControl.of(context);
    final kept = control.state;
    final ratio = o(_gaugeRatio);
    // the ratio moved stops the timer: the gauges show the ratio chosen
    final moved = kept['ratio'] != null && kept['ratio'] != ratio;
    kept['ratio'] = ratio;
    final live = o(_gaugeLive);
    if (moved && live) {
      scheduleMicrotask(() => control.setOption(_gaugeLive, false));
    }
    var r = ratio / 100;
    if (live && !moved) {
      final at = _tick(ms, _gaugeTick, wake) * _gaugeTick % (_fillMs + _holdMs);
      r = at < _fillMs ? at / _fillMs : 1;
    }
    final theme = Theme.of(context);
    final percent = '${(r * 100).round()}%';
    // a label of its own, the percentage the gauges write, or none
    final label = o(_gaugeLabel);
    final (gaugeLabel, lineLabel) = label == 'own'
        ? (percent, 'used $percent')
        : (null, null);
    final percentage = label == 'percent';
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
              showPercentage: percentage,
              style: o
                  .styleOf(context, _gaugeColor)
                  .merge(Style(bg: theme.surface.bg)),
              labelStyle: const Style(attrs: Attr.bold),
            ),
          ),
          LineGauge(
            ratio: r,
            label: lineLabel,
            showPercentage: percentage,
            type: BorderType.values.byName(o(_gaugeLine)),
            segmented: o(_gaugeSegmented),
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
    final state = o(_gaugeLive)
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
        : ['final _ratio = ${_ratioLiteral(o(_gaugeRatio))};', ''];
    final label = o(_gaugeLabel);
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
      if (label == 'percent') '            showPercentage: true,',
      codeLine([
        '            style: theme.${o(_gaugeColor)}',
        '.merge(.new(bg: theme.surface.bg)),',
      ]),
      '            labelStyle: const .new(attrs: Attr.bold),',
      '          ),',
      '        ),',
      '        LineGauge(',
      '          ratio: _ratio,',
      if (label == 'own') r"          label: 'used $percent',",
      if (label == 'percent') '          showPercentage: true,',
      '          type: .${o.nameOf(_gaugeLine)},',
      if (o(_gaugeSegmented)) '          segmented: true,',
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
