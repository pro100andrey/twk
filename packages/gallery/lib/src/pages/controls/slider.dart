// The Slider page.
part of 'controls.dart';

/// The Slider page's `divisions` option.
const _sliderDivisions = ChoiceOption<int?>(
  'divisions',
  'divisions',
  values: [null, 10, 4],
  labels: ['none', '10', '4'],
);

/// The Slider page's `width` option.
final _sliderWidth = SliderOption(
  'width',
  'width',
  min: 10,
  max: 40,
  initial: 30,
  format: (v) => '$v cells',
);

final _sliderPage = GalleryPage(
  group: _group,
  title: 'Slider',
  options: [
    _sliderDivisions,
    _sliderWidth,
  ],
  build: (context, o) => _Volume(
    width: o(_sliderWidth).toInt(),
    divisions: o(_sliderDivisions),
  ),
  code: (o) => [
    'var _volume = 0.5;',
    '',
    '@override',
    'Widget build(BuildContext context) => Column(',
    '  mainAxisSize: .min,',
    '  crossAxisAlignment: .start,',
    '  spacing: 1,',
    '  children: [',
    '    SizedBox(',
    '      width: ${o.nameOf(_sliderWidth)},',
    '      child: Slider(',
    '        value: _volume,',
    "        semanticsLabel: 'Volume',",
    if (o(_sliderDivisions) != null)
      '        divisions: ${o.nameOf(_sliderDivisions)},',
    '        onChanged: (value) => setState(() => _volume = value),',
    '      ),',
    '    ),',
    '    Text.rich([',
    "      Span('volume: ', Theme.of(context).muted),",
    r"      Span('${(_volume * 100).round()}%'),",
    '    ]),',
    '  ],',
    ');',
  ].join('\n'),
);

/// A volume on a slider.
final class _Volume extends StatefulWidget {
  const _Volume({required this.width, required this.divisions});

  final int width;
  final int? divisions;

  @override
  State<_Volume> createState() => _VolumeState();
}

final class _VolumeState extends State<_Volume> with KeptState {
  @override
  Widget build(BuildContext context) {
    final volume = keptOr('volume', 0.5);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 1,
      children: [
        SizedBox(
          width: widget.width,
          child: Slider(
            value: volume,
            semanticsLabel: 'Volume',
            divisions: widget.divisions,
            onChanged: (value) => keep('volume', value),
          ),
        ),
        LitLine([
          ('volume: ', true),
          ('${(volume * 100).round()}%', false),
        ], serial: serial),
      ],
    );
  }
}
