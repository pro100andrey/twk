// The AnimatedSwitcher page.
part of 'animation.dart';

// ------------------------------------------------------------ AnimatedSwitcher

const _items = ['the first child', 'and now the second one', 'a third'];

const _itemLabels = ['first', 'second', 'third'];

/// Each transition, as the Code writes it and as twk has it.
const _transitions = <String, (String, SwitcherTransition)>{
  'fade': ('.fade', SwitcherTransition.fade),
  // in from the side `from` points to
  'slide': ('const .slide()', SwitcherTransition.slide()),
  'slide right': (
    'const .slide(from: .centerLeft)',
    SwitcherTransition.slide(from: .centerLeft),
  ),
  'slide up': (
    'const .slide(from: .bottomCenter)',
    SwitcherTransition.slide(from: .bottomCenter),
  ),
  'slide down': (
    'const .slide(from: .topCenter)',
    SwitcherTransition.slide(from: .topCenter),
  ),
  'dissolve': ('.dissolve', SwitcherTransition.dissolve),
};

/// The AnimatedSwitcher page's `child` option.
const _switcherChild = ChoiceOption<String>(
  'child',
  'child',
  values: _itemLabels,
);

/// The AnimatedSwitcher page's `transition` option.
final _switcherTransition = ChoiceOption<String>(
  'transition',
  'transition',
  values: _transitions.keys.toList(),
);

final _switcher = GalleryPage(
  group: _group,
  title: 'AnimatedSwitcher',
  options: [
    _switcherChild,
    _switcherTransition,
    _cycleOption,
  ],
  build: (context, o) => _Cycled(o, _switcherChild, _itemLabels, (context, i) {
    final theme = Theme.of(context);
    final child = _items[i];
    return SizedBox(
      width: 34,
      height: 5,
      child: Box(
        style: theme.surface,
        border: .all(type: .rounded, style: theme.border),
        child: AnimatedSwitcher(
          duration: _duration,
          transition: _transitions[o(_switcherTransition)]!.$2,
          child: SizedBox(
            key: ValueKey(child),
            width: 32,
            height: 3,
            child: Center(child: Text(child)),
          ),
        ),
      ),
    );
  }),
  code: (o) {
    final name = o(_switcherTransition);
    final tr = _transitions[name]!.$1;
    // all of it const but the key, where a timer gives the child
    final fixed = !o(_cycleOption);
    List<String> body(String child, String key) => [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 34,',
      '  height: 5,',
      '  child: Box(',
      '    style: theme.surface,',
      '    border: .all(type: .rounded, style: theme.border),',
      '    child: ${fixed ? 'const ' : ''}AnimatedSwitcher(',
      '      duration: ${fixed ? _dur.replaceFirst('const ', '') : _dur},',
      if (name != 'fade')
        '      transition: ${fixed ? tr.replaceFirst('const ', '') : tr},',
      '      child: SizedBox(',
      '        key: $key,',
      '        width: 32,',
      '        height: 3,',
      '        child: Center(child: Text($child)),',
      '      ),',
      '    ),',
      '  ),',
      ');',
    ];
    final i = _itemLabels.indexOf(o(_switcherChild));
    if (fixed) {
      final item = _items[i];
      return body("'$item'", "ValueKey('$item')").join('\n');
    }
    return _ticking(
      [
        'static const _children = [',
        for (final x in _items) "  '$x',",
        '];',
        'var _i = $i;',
      ],
      _nextOf('_children'),
      'the next child every 1.2 s',
      ['final child = _children[_i];', ...body('child', 'ValueKey(child)')],
    ).join('\n');
  },
);
