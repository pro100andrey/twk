// The FractionallySizedBox page.
part of 'layout.dart';

// ----------------------------------------------------- FractionallySizedBox

const _factors = [0.25, 0.5, 0.75, 1.0];

const _factorLabels = ['¼', '½', '¾', '1'];

final _fractionallySizedBox = GalleryPage(
  group: 'Layout',
  title: 'FractionallySizedBox',
  options: [
    const ChoiceOption(
      'wf',
      'width factor',
      values: _factors,
      labels: _factorLabels,
      initial: 0.5,
    ),
    const ChoiceOption(
      'hf',
      'height factor',
      values: _factors,
      labels: _factorLabels,
      initial: 0.5,
    ),
    const ChoiceOption(
      'alignment',
      'alignment',
      values: ['center', 'topLeft', 'bottomRight'],
    ),
    SliderOption(
      'room',
      'room',
      min: 16,
      max: 48,
      initial: 40,
      format: (v) => '$v cells',
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final wf = o.choice<double>('wf');
    final hf = o.choice<double>('hf');
    return SizedBox(
      width: o.number('room').toInt(),
      height: 9,
      child: Box(
        border: _rounded(theme),
        child: FractionallySizedBox(
          alignment: alignmentByName[o.choice<String>('alignment')]!,
          widthFactor: wf,
          heightFactor: hf,
          child: Box(
            style: theme.selection,
            child: Center(child: Text('$wf × $hf')),
          ),
        ),
      ),
    );
  },
  code: (o) {
    final wf = o.choice<double>('wf');
    final hf = o.choice<double>('hf');
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: ${o.label('room')},',
      '  height: 9,',
      '  child: Box(',
      '    border: .all(type: .rounded, style: theme.border),',
      '    child: FractionallySizedBox(',
      if (o['alignment'] != 'center')
        '      alignment: .${o.label('alignment')},',
      '      widthFactor: $wf,',
      '      heightFactor: $hf,',
      '      child: Box(',
      '        style: theme.selection,',
      "        child: const Center(child: Text('$wf × $hf')),",
      '      ),',
      '    ),',
      '  ),',
      ');',
    ].join('\n');
  },
);
