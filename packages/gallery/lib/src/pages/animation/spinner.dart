// The Spinner page.
part of 'animation.dart';

// ------------------------------------------------------------ Spinner

const _tasks = ['Resolving packages…', 'Compiling…', 'Running 214 tests…'];

final _spinner = GalleryPage(
  group: 'Animation',
  title: 'Spinner',
  options: [
    ChoiceOption('frames', 'frames', values: _frames.keys.toList()),
    const ColorOption('color', 'style', values: _colors, initial: 'primary'),
  ],
  build: (context, o) {
    final style = o.colorStyle(context, 'color');
    final frames = _frames[o.choice<String>('frames')]!;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      gap: 1,
      children: [
        for (final task in _tasks)
          Row(
            mainAxisSize: .min,
            gap: 1,
            children: [
              Spinner(frames: frames, style: style),
              Text(task),
            ],
          ),
      ],
    );
  },
  code: (o) {
    final frames = o.choice<String>('frames');
    final color = o.color('color');
    return [
      'final theme = Theme.of(context);',
      codeLine([
        "const tasks = ['Resolving packages…', 'Compiling…', ",
        "'Running 214 tests…'];",
      ]),
      'return Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      '    for (final task in tasks)',
      '      Row(',
      '        mainAxisSize: .min,',
      '        gap: 1,',
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
