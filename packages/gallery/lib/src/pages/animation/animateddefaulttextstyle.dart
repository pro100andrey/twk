// The AnimatedDefaultTextStyle page.
part of 'animation.dart';

// ---------------------------------------------------- AnimatedDefaultTextStyle

const _slots = ['primary', 'error', 'success'];

const _texts = ['Text in the style above it,', 'and a second Text, in step.'];

final _textStyle = GalleryPage(
  group: 'Animation',
  title: 'AnimatedDefaultTextStyle',
  options: [
    const ChoiceOption('style', 'style', values: _slots),
    const SwitchOption('bold', 'bold'),
    _cycleOption,
  ],
  build: (context, o) => _Cycled(o, 'style', _slots, (context, i) {
    final slot = themeColor(Theme.of(context), _slots[i]);
    return AnimatedDefaultTextStyle(
      style: o.flag('bold') ? slot.merge(const .new(attrs: Attr.bold)) : slot,
      duration: _duration,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [for (final l in _texts) Text(l)],
      ),
    );
  }),
  code: (o) {
    String style(String slot) =>
        o.flag('bold') ? '$slot.merge(const .new(attrs: Attr.bold))' : slot;
    List<String> body(String slot) => [
      'final theme = Theme.of(context);',
      'return AnimatedDefaultTextStyle(',
      '  style: ${style(slot)},',
      '  duration: $_dur,',
      '  child: const Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    children: [',
      for (final l in _texts) "      Text('$l'),",
      '    ],',
      '  ),',
      ');',
    ];
    final name = o.choice<String>('style');
    if (!o.flag('cycle')) {
      return body('theme.$name').join('\n');
    }
    return _ticking(
      ['var _i = ${_slots.indexOf(name)};'],
      '() => _i = (_i + 1) % 3',
      'the next style every 1.2 s',
      [
        'final theme = Theme.of(context);',
        'final slot = [theme.primary, theme.error, theme.success][_i];',
        ...body('slot').skip(1),
      ],
    ).join('\n');
  },
);
