// The AnimationController page.
part of 'animation.dart';

/// The dot's column in a box 42 wide.
const _across = 39;

/// The AnimationController page's `reverse` option.
const _controllerReverse = SwitchOption(
  'reverse',
  'reverse',
  initial: true,
);

/// The AnimationController page's `duration` option.
const _controllerDuration = ChoiceOption<int>(
  'duration',
  'duration',
  values: [1, 2, 4],
  labels: ['1 s', '2 s', '4 s'],
  initial: 2,
);

final _controller = GalleryPage(
  group: _group,
  title: 'AnimationController',
  options: [
    _curveOption,
    _controllerReverse,
    _controllerDuration,
  ],
  build: (context, o) => _Pulse(
    curve: _curveOf(o),
    reverse: o(_controllerReverse),
    seconds: o(_controllerDuration),
  ),
  code: (o) {
    final curve = 'Curves.${o(_curveOption)}';
    final repeat = o(_controllerReverse) ? 'repeat(reverse: true)' : 'repeat()';
    return [
      'final class _PulseState extends State<_Pulse>',
      '    with TickerProviderStateMixin {',
      ..._indent([
        'late final _controller = AnimationController(',
        '  vsync: this,',
        '  duration: const Duration(seconds: ${o(_controllerDuration)}),',
        ')..$repeat;',
        '',
        'static const _across = IntTween(begin: 0, end: $_across);',
        '',
        '@override',
        'void dispose() {',
        '  _controller.dispose();',
        '  super.dispose();',
        '}',
        '',
        'void _toggle() => setState(() {',
        '  if (_controller.isAnimating) {',
        '    _controller.stop();',
        '  } else {',
        '    _controller.$repeat;',
        '  }',
        '});',
        '',
        '@override',
        'Widget build(BuildContext context) {',
        '  final theme = Theme.of(context);',
        '  LineGauge gauge(double ratio, String label) => LineGauge(',
        '    ratio: ratio,',
        '    label: label,',
        '    type: .heavy,',
        '    filledStyle: theme.primary,',
        '    unfilledStyle: theme.border,',
        '  );',
        '  return ListenableBuilder(',
        '    listenable: _controller,',
        '    builder: (context, _) {',
        '      final value = _controller.value;',
        '      final curved = $curve.transform(value);',
        '      final x = _across.chain($curve).evaluate(_controller);',
        '      return SizedBox(',
        '        width: 42,',
        '        // the track as wide as the column: the dot runs across it',
        '        child: Column(',
        '          mainAxisSize: .min,',
        '          crossAxisAlignment: .stretch,',
        '          spacing: 1,',
        '          children: [',
        '            Box(',
        '              border: .all(type: .rounded, style: theme.border),',
        '              child: Text(',
        "                '\${' ' * x.clamp(0, $_across)}●',",
        '                style: theme.primary,',
        '              ),',
        '            ),',
        '            Column(',
        '              mainAxisSize: .min,',
        '              children: [',
        r"                gauge(value, 'value  ${value.toStringAsFixed(2)}'),",
        codeLine([
          '                gauge(curved, ',
          r"'curved ${curved.toStringAsFixed(2)}'),",
        ]),
        '              ],',
        '            ),',
        '            Row(',
        '              spacing: 2,',
        '              children: [',
        '                Button(',
        "                  _controller.isAnimating ? 'Stop' : 'Run',",
        '                  onPressed: _toggle,',
        '                ),',
        '                Text(_controller.status.name, style: theme.muted),',
        '              ],',
        '            ),',
        '          ],',
        '        ),',
        '      );',
        '    },',
        '  );',
        '}',
      ], 2),
      '}',
    ].join('\n');
  },
);

/// The Code's `_Pulse`: a controller from 0 to 1 and on round, a dot that
/// runs across a track with it, its value and curved value, and a button
/// that stops and runs it. A new duration or way round runs it again from
/// where it is, as `repeat()` does.
final class _Pulse extends StatefulWidget {
  const _Pulse({
    required this.curve,
    required this.reverse,
    required this.seconds,
  });

  final Curve curve;
  final bool reverse;
  final int seconds;

  @override
  State<_Pulse> createState() => _PulseState();
}

final class _PulseState extends State<_Pulse> with TickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.seconds),
  )..repeat(reverse: widget.reverse);

  static const _track = IntTween(begin: 0, end: _across);

  @override
  void didUpdateWidget(_Pulse oldWidget) {
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

  void _toggle() => setState(() {
    if (_controller.isAnimating) {
      _controller.stop();
    } else {
      _controller.repeat(reverse: widget.reverse);
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final curve = widget.curve;
    LineGauge gauge(double ratio, String label) => LineGauge(
      ratio: ratio,
      label: label,
      type: .heavy,
      filledStyle: theme.primary,
      unfilledStyle: theme.border,
    );
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final value = _controller.value;
        final curved = curve.transform(value);
        final x = _track.chain(curve).evaluate(_controller);
        return SizedBox(
          width: 42,
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: 1,
            children: [
              Box(
                border: .all(type: .rounded, style: theme.border),
                child: Text(
                  '${' ' * x.clamp(0, _across)}●',
                  style: theme.primary,
                ),
              ),
              Column(
                mainAxisSize: .min,
                children: [
                  gauge(value, 'value  ${value.toStringAsFixed(2)}'),
                  gauge(curved, 'curved ${curved.toStringAsFixed(2)}'),
                ],
              ),
              Row(
                spacing: 2,
                children: [
                  Button(
                    _controller.isAnimating ? 'Stop' : 'Run',
                    onPressed: _toggle,
                  ),
                  Text(_controller.status.name, style: theme.muted),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
