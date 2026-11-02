// The AnimatedBuilder page.
part of 'animation.dart';

// ------------------------------------------------------------ AnimatedBuilder

// the chip's column at the end of the track: a box 42 wide, a chip 5
const _slide = 35;

/// The AnimatedBuilder page's `reverse` option.
const _builderReverse = SwitchOption(
  'reverse',
  'reverse',
  initial: true,
);

/// The AnimatedBuilder page's `duration` option.
const _builderDuration = ChoiceOption<int>(
  'duration',
  'duration',
  values: [1, 2, 4],
  labels: ['1 s', '2 s', '4 s'],
  initial: 2,
);

final _builder = GalleryPage(
  group: _group,
  title: 'AnimatedBuilder',
  options: [
    _curveOption,
    _builderReverse,
    _builderDuration,
  ],
  build: (context, o) => _Slide(
    curve: _curveOf(o),
    reverse: o(_builderReverse),
    seconds: o(_builderDuration),
  ),
  code: (o) {
    final repeat = o(_builderReverse) ? 'repeat(reverse: true)' : 'repeat()';
    return [
      'final class _SlideState extends State<_Slide>',
      '    with TickerProviderStateMixin {',
      ..._indent([
        'late final _controller = AnimationController(',
        '  vsync: this,',
        '  duration: const Duration(seconds: ${o(_builderDuration)}),',
        ')..$repeat;',
        '',
        'static final _across = IntTween(begin: 0, end: $_slide).chain(',
        '  Curves.${o(_curveOption)},',
        ');',
        '',
        '@override',
        'void dispose() {',
        '  _controller.dispose();',
        '  super.dispose();',
        '}',
        '',
        '@override',
        'Widget build(BuildContext context) {',
        '  final theme = Theme.of(context);',
        '  return SizedBox(',
        '    width: 42,',
        '    child: Box(',
        '      border: .all(type: .rounded, style: theme.border),',
        '      child: AnimatedBuilder(',
        '        animation: _controller,',
        '        // at each tick: the chip moved along the track',
        '        builder: (context, child) => Row(',
        '          children: [',
        '            SizedBox(width: _across.evaluate(_controller)),',
        '            child!,',
        '          ],',
        '        ),',
        '        // built once, here, and handed to the builder at each tick',
        '        child: Box(',
        '          style: theme.selection,',
        '          padding: const .x(1),',
        "          child: const Text('twk'),",
        '        ),',
        '      ),',
        '    ),',
        '  );',
        '}',
      ], 2),
      '}',
    ].join('\n');
  },
);

/// The Code's `_Slide`: a controller from 0 to 1 and on round, and an
/// [AnimatedBuilder] that moves a chip, built once, along a track with it.
/// A new duration or way round runs it again from where it is, as
/// `repeat()` does.
final class _Slide extends StatefulWidget {
  const _Slide({
    required this.curve,
    required this.reverse,
    required this.seconds,
  });

  final Curve curve;
  final bool reverse;
  final int seconds;

  @override
  State<_Slide> createState() => _SlideState();
}

final class _SlideState extends State<_Slide> with TickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.seconds),
  )..repeat(reverse: widget.reverse);

  @override
  void didUpdateWidget(_Slide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.seconds != oldWidget.seconds ||
        widget.reverse != oldWidget.reverse) {
      _controller.duration = Duration(seconds: widget.seconds);
      if (_controller.isAnimating) {
        _controller.repeat(reverse: widget.reverse);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final across = const IntTween(begin: 0, end: _slide).chain(widget.curve);
    return SizedBox(
      width: 42,
      child: Box(
        border: .all(type: .rounded, style: theme.border),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Row(
            children: [
              SizedBox(width: across.evaluate(_controller)),
              child!,
            ],
          ),
          child: Box(
            style: theme.selection,
            padding: const .x(1),
            child: const Text('twk'),
          ),
        ),
      ),
    );
  }
}
