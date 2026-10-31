// The FractionallySizedBox page.
part of 'layout.dart';

// ----------------------------------------------------- FractionallySizedBox

const _factors = [0.25, 0.5, 0.75, 1.0];

const _factorLabels = ['¼', '½', '¾', '1'];

/// The FractionallySizedBox page's `wf` option.
const _fractionallySizedBoxWf = ChoiceOption<double>(
  'wf',
  'width factor',
  values: _factors,
  labels: _factorLabels,
  initial: 0.5,
);

/// The FractionallySizedBox page's `hf` option.
const _fractionallySizedBoxHf = ChoiceOption<double>(
  'hf',
  'height factor',
  values: _factors,
  labels: _factorLabels,
  initial: 0.5,
);

/// The FractionallySizedBox page's `alignment` option.
const _fractionallySizedBoxAlignment = ChoiceOption<String>(
  'alignment',
  'alignment',
  values: ['center', 'topLeft', 'bottomRight'],
);

/// The FractionallySizedBox page's `room` option.
final _fractionallySizedBoxRoom = SliderOption(
  'room',
  'room',
  min: 16,
  max: 48,
  initial: 40,
  format: (v) => '$v cells',
);

final _fractionallySizedBox = GalleryPage(
  group: _group,
  title: 'FractionallySizedBox',
  options: [
    _fractionallySizedBoxWf,
    _fractionallySizedBoxHf,
    _fractionallySizedBoxAlignment,
    _fractionallySizedBoxRoom,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final wf = o(_fractionallySizedBoxWf);
    final hf = o(_fractionallySizedBoxHf);
    return SizedBox(
      width: o(_fractionallySizedBoxRoom).toInt(),
      height: 9,
      child: Box(
        border: _rounded(theme),
        child: FractionallySizedBox(
          alignment: alignmentByName[o(_fractionallySizedBoxAlignment)]!,
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
    final wf = o(_fractionallySizedBoxWf);
    final hf = o(_fractionallySizedBoxHf);
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: ${o.nameOf(_fractionallySizedBoxRoom)},',
      '  height: 9,',
      '  child: Box(',
      '    border: .all(type: .rounded, style: theme.border),',
      '    child: FractionallySizedBox(',
      if (o(_fractionallySizedBoxAlignment) != 'center')
        '      alignment: .${o.nameOf(_fractionallySizedBoxAlignment)},',
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
