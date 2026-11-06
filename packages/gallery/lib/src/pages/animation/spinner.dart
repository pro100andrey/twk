// The Spinner page.
part of 'animation.dart';

// ------------------------------------------------------------ Spinner

const _tasks = ['Resolving packages…', 'Compiling…', 'Running 214 tests…'];

/// The Spinner page's `frames` option.
final _spinnerFrames = ChoiceOption<String>(
  'frames',
  'frames',
  values: _frames.keys.toList(),
);

/// The Spinner page's `color` option.
const _spinnerColor = ColorOption(
  'color',
  'style',
  values: _colors,
  initial: 'primary',
);

final _spinner = GalleryPage(
  group: _group,
  title: 'Spinner',
  options: [
    _spinnerFrames,
    _spinnerColor,
  ],
  build: (context, o) {
    final style = o.styleOf(context, _spinnerColor);
    final frames = _frames[o(_spinnerFrames)]!;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 1,
      children: [
        for (final task in _tasks)
          Row(
            mainAxisSize: .min,
            spacing: 1,
            children: [
              Spinner(frames: frames, style: style),
              Text(task),
            ],
          ),
      ],
    );
  },
  code: (o) {
    final frames = o(_spinnerFrames);
    final color = o(_spinnerColor);
    return [
      'final theme = Theme.of(context);',
      codeLine([
        "const tasks = ['Resolving packages…', 'Compiling…', ",
        "'Running 214 tests…'];",
      ]),
      'return Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  spacing: 1,',
      '  children: [',
      '    for (final task in tasks)',
      '      Row(',
      '        mainAxisSize: .min,',
      '        spacing: 1,',
      '        children: [',
      if (frames == 'dots')
        '          Spinner(style: theme.$color),'
      else
        codeLine([
          '          Spinner(frames: SpinnerFrames.$frames, ',
          'style: theme.$color),',
        ]),
      '          Text(task),',
      '        ],',
      '      ),',
      '  ],',
      ');',
    ].join('\n');
  },
);
