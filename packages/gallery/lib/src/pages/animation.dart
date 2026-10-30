// The Animation group of the gallery.
import 'dart:async';

import 'package:twk/twk.dart';

import '../motion.dart';
import '../page.dart';
import 'common.dart';

/// The pages of the Animation group that draw.
final animationPages = <GalleryPage>[
  _spinner,
  _progressBar,
  _progressList,
  _skeleton,
  _controller,
  _builder,
  _align,
  _positioned,
  _box,
  _opacity,
  _textStyle,
  _size,
  _tween,
  _switcher,
  _dissolve,
  _effect,
];

// ------------------------------------------------------------ shared

/// The theme colours the Animation pages offer, in the design's order.
const _colors = ['primary', 'accent', 'success', 'warning', 'info'];

/// How long a widget of the group takes to run to a new value.
const _duration = Duration(milliseconds: 600);

/// The timer that gives a widget its next value while the page cycles: a
/// run of [_duration], then as long at rest.
const _cycle = 1200;

/// The curves the pages offer, by name.
const _curves = <String, Curve>{
  'linear': Curves.linear,
  'ease': Curves.ease,
  'easeIn': Curves.easeIn,
  'easeOut': Curves.easeOut,
  'easeInOut': Curves.easeInOut,
  'fastOutSlowIn': Curves.fastOutSlowIn,
  'decelerate': Curves.decelerate,
  'bounceOut': Curves.bounceOut,
  'elasticOut': Curves.elasticOut,
};

/// Each of [Curves], by name.
const _curveOption = ChoiceOption(
  'curve',
  'curve',
  values: [
    'linear',
    'ease',
    'easeIn',
    'easeOut',
    'easeInOut',
    'fastOutSlowIn',
    'decelerate',
    'bounceOut',
    'elasticOut',
  ],
  initial: 'easeInOut',
);

const _cycleOption = SwitchOption('cycle', 'cycle', initial: true);

Curve _curveOf(Options o) => _curves[o.choice<String>('curve')]!;

/// [builder] with the index of the value of option [option] (one of
/// [values]) the widget is given: the option's own, or while the page's
/// `cycle` switch is on, the next one every [_cycle] ms, as the Code's
/// timer gives it, the option moved along with it. The timer runs on the
/// gallery's clock: from when the page was built (0 while the clock
/// stands still, so a still at a route's `t=` has stepped as far as the
/// page would have), from when the switch was turned on; a value chosen
/// by hand while it cycles turns the cycle off, so the pick stays.
final class _Cycled extends StatefulWidget {
  const _Cycled(this.options, this.option, this.values, this.builder);

  final Options options;
  final String option;
  final List<Object?> values;
  final Widget Function(BuildContext context, int i) builder;

  @override
  State<_Cycled> createState() => _CycledState();
}

final class _CycledState extends State<_Cycled> {
  late final _motion = Motion(() {
    if (mounted) {
      setState(() {});
    }
  });

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _motion.begin(context);
    final w = widget;
    final control = PageControl.of(context);
    final kept = control.state;
    final now = _motion.now;
    final n = w.values.length;
    final chosen = w.values.indexOf(w.options[w.option]);
    final c = chosen < 0 ? 0 : chosen;
    var on = w.options.flag('cycle');
    final born = kept['born'] as Duration? ?? (_motion.frozen ? .zero : now);
    kept['born'] = born;
    final name = 'drive:${w.option}';
    var d = kept[name] as Drive?;
    if (on && d != null && d.on && c != d.last) {
      scheduleMicrotask(() => control.setOption('cycle', false));
      on = false;
    }
    if (d == null) {
      d = Drive(on: on, since: born, from: c);
      kept[name] = d;
    } else if (d.on != on) {
      d
        ..on = on
        ..since = now
        ..from = c;
    }
    var i = c;
    if (on) {
      final k = (now - d.since).inMilliseconds ~/ _cycle;
      final steps = k < 0 ? 0 : k;
      i = (d.from + steps) % n;
      _motion.wakeAt(
        d.since + const Duration(milliseconds: _cycle) * (steps + 1),
      );
    }
    d.last = c;
    if (on && i != c) {
      final value = w.values[i];
      scheduleMicrotask(() => control.setOption(w.option, value));
      d.last = i;
    }
    _motion.end();
    return w.builder(context, i);
  }
}

// ------------------------------------------------------------ code

const _dur = 'const Duration(milliseconds: 600)';

/// A number as JavaScript's String() writes it: `0.5`, `1`.
String _js(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// A double as Dart writes one: `1.0`, `0.25`.
String _dbl(num v) => v == v.roundToDouble() ? v.toStringAsFixed(1) : '$v';

/// The curve argument at [n] columns, none for Curves.linear, the
/// default.
List<String> _curveLine(Options o, int n) {
  final curve = o.choice<String>('curve');
  return curve == 'linear' ? [] : ['${' ' * n}curve: Curves.$curve,'];
}

List<String> _indent(List<String> lines, int n) => [
  for (final l in lines)
    if (l.isEmpty) l else '${' ' * n}$l',
];

/// The State's members around a build whose value a timer moves on every
/// [_cycle] ms: [fields], the timer, initState and dispose, then the
/// build with [body] in it.
List<String> _ticking(
  List<String> fields,
  String tick,
  String comment,
  List<String> body,
) => [
  ...fields,
  'late final Timer _timer;',
  '',
  '@override',
  'void initState() {',
  '  super.initState();',
  '  // $comment',
  '  _timer = Timer.periodic(',
  '    const Duration(milliseconds: $_cycle),',
  '    (_) => setState($tick),',
  '  );',
  '}',
  '',
  '@override',
  'void dispose() {',
  '  _timer.cancel();',
  '  super.dispose();',
  '}',
  '',
  '@override',
  ..._buildOf(body),
];

/// A build of [body]: an arrow to what it returns where it is just that.
List<String> _buildOf(List<String> body) {
  final top = body.where((l) => l.isNotEmpty && l[0] != ' ').length;
  if (body.first.startsWith('return ') && top == 2) {
    return [
      body.first.replaceFirst(
        'return ',
        'Widget build(BuildContext context) => ',
      ),
      ...body.skip(1),
    ];
  }
  return ['Widget build(BuildContext context) {', ..._indent(body, 2), '}'];
}

String _nextOf(String list) => '() => _i = (_i + 1) % $list.length';

/// `return` [child] at the top left of a SizedBox of [room], the room it
/// grows in ([what], and with elasticOut its overshoot).
List<String> _framed(
  Options o,
  (int, int) room,
  String what,
  List<String> child,
) => [
  codeLine([
    '// the room it grows in: $what',
    if (o.choice<String>('curve') == 'elasticOut') ', and elasticOut beyond it',
  ]),
  'return SizedBox(',
  '  width: ${room.$1},',
  '  height: ${room.$2},',
  '  child: Align(',
  '    alignment: .topLeft,',
  '    child: ${child.first}',
  ..._indent(child.sublist(1, child.length - 1), 4),
  '    ${child.last},',
  '  ),',
  ');',
];

/// The room a widget that grows to [w] × [h] takes: elasticOut overshoots
/// by a quarter, [dw] × [dh] beyond it.
(int, int) _overshoot(Options o, int w, int h, int dw, int dh) =>
    o.choice<String>('curve') == 'elasticOut' ? (w + dw, h + dh) : (w, h);

/// [child] at the top left of a SizedBox of [room].
Widget _inFrame((int, int) room, Widget child) => SizedBox(
  width: room.$1,
  height: room.$2,
  child: Align(alignment: .topLeft, child: child),
);

// ------------------------------------------------------------ Spinner

const _tasks = ['Resolving packages…', 'Compiling…', 'Running 214 tests…'];

const _frames = <String, SpinnerFrames>{
  'dots': SpinnerFrames.dots,
  'line': SpinnerFrames.line,
  'arc': SpinnerFrames.arc,
};

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

// ------------------------------------------------------------ ProgressBar

final _progressBar = GalleryPage(
  group: 'Animation',
  title: 'ProgressBar',
  options: [
    const SwitchOption('known', 'value known', initial: true),
    // no value while it is not known
    SliderOption(
      'value',
      'value',
      min: 0,
      max: 100,
      initial: 33,
      format: (v) => '$v%',
      disabled: (o) => !o.flag('known'),
    ),
    const ColorOption('color', 'style', values: _colors, initial: 'success'),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final known = o.flag('known');
    final value = o.number('value').toInt();
    return Row(
      mainAxisSize: .min,
      gap: 1,
      children: [
        SizedBox(
          width: 40,
          child: ProgressBar(
            value: known ? value / 100 : null,
            style: o
                .colorStyle(context, 'color')
                .merge(.new(bg: theme.surface.bg)),
          ),
        ),
        if (known) Text('${'$value'.padLeft(3)}%'),
      ],
    );
  },
  code: (o) {
    final known = o.flag('known');
    final value = o.number('value').toInt();
    final v = _js(double.parse((value / 100).toStringAsFixed(2)));
    return [
      'final theme = Theme.of(context);',
      'return Row(',
      '  mainAxisSize: .min,',
      '  gap: 1,',
      '  children: [',
      '    SizedBox(',
      '      width: 40,',
      '      child: ProgressBar(',
      if (known) '        value: $v,',
      codeLine([
        '        style: theme.${o.color('color')}',
        '.merge(.new(bg: theme.surface.bg)),',
      ]),
      '      ),',
      '    ),',
      if (known) "    const Text('${'$value'.padLeft(3)}%'),",
      '  ],',
      ');',
    ].join('\n');
  },
);

// --------------------------------------------------------- AnimationController

/// The dot's column in a box 42 wide.
const _across = 39;

final _controller = GalleryPage(
  group: 'Animation',
  title: 'AnimationController',
  options: [
    _curveOption,
    const SwitchOption('reverse', 'reverse', initial: true),
    const ChoiceOption(
      'duration',
      'duration',
      values: [1, 2, 4],
      labels: ['1 s', '2 s', '4 s'],
      initial: 2,
    ),
  ],
  build: (context, o) => _Pulse(
    curve: _curveOf(o),
    reverse: o.flag('reverse'),
    seconds: o.choice<int>('duration'),
  ),
  code: (o) {
    final curve = 'Curves.${o.choice<String>('curve')}';
    final repeat = o.flag('reverse') ? 'repeat(reverse: true)' : 'repeat()';
    return [
      'final class _PulseState extends State<_Pulse>',
      '    with TickerProviderStateMixin {',
      ..._indent([
        'late final _controller = AnimationController(',
        '  vsync: this,',
        '  duration: const Duration(seconds: ${o.choice<int>('duration')}),',
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
        '          gap: 1,',
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
        '              gap: 2,',
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
            gap: 1,
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
                gap: 2,
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

// ------------------------------------------------------------ AnimatedBuilder

// the chip's column at the end of the track: a box 42 wide, a chip 5
const _slide = 35;

final _builder = GalleryPage(
  group: 'Animation',
  title: 'AnimatedBuilder',
  options: [
    _curveOption,
    const SwitchOption('reverse', 'reverse', initial: true),
    const ChoiceOption(
      'duration',
      'duration',
      values: [1, 2, 4],
      labels: ['1 s', '2 s', '4 s'],
      initial: 2,
    ),
  ],
  build: (context, o) => _Slide(
    curve: _curveOf(o),
    reverse: o.flag('reverse'),
    seconds: o.choice<int>('duration'),
  ),
  code: (o) {
    final repeat = o.flag('reverse') ? 'repeat(reverse: true)' : 'repeat()';
    return [
      'final class _SlideState extends State<_Slide>',
      '    with TickerProviderStateMixin {',
      ..._indent([
        'late final _controller = AnimationController(',
        '  vsync: this,',
        '  duration: const Duration(seconds: ${o.choice<int>('duration')}),',
        ')..$repeat;',
        '',
        'static final _across = IntTween(begin: 0, end: $_slide).chain(',
        '  Curves.${o.choice<String>('curve')},',
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

// ---------------------------------------------- AnimatedAlign, AnimatedPadding

const _aligns = <(String, Alignment)>[
  ('centerLeft', .centerLeft),
  ('center', .center),
  ('centerRight', .centerRight),
  ('bottomRight', .bottomRight),
];

final _align = GalleryPage(
  group: 'Animation',
  title: 'AnimatedAlign, AnimatedPadding',
  options: [
    ChoiceOption(
      'alignment',
      'alignment',
      values: [for (final a in _aligns) a.$1],
    ),
    _curveOption,
    _cycleOption,
  ],
  build: (context, o) =>
      _Cycled(o, 'alignment', [for (final a in _aligns) a.$1], (
        context,
        i,
      ) {
        final theme = Theme.of(context);
        final alignment = _aligns[i].$2;
        final curve = _curveOf(o);
        return SizedBox(
          width: 34,
          height: 7,
          child: Box(
            border: .all(type: .rounded, style: theme.border),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Expanded(
                  child: AnimatedAlign(
                    alignment: alignment,
                    duration: _duration,
                    curve: curve,
                    child: Text('◆ aligned', style: theme.primary),
                  ),
                ),
                AnimatedPadding(
                  padding: .only(left: alignment.x * 10 + 10),
                  duration: _duration,
                  curve: curve,
                  child: Text('◇ padded', style: theme.accent),
                ),
              ],
            ),
          ),
        );
      }),
  code: (o) {
    final i = _aligns.indexWhere((a) => a.$1 == o.choice<String>('alignment'));
    final a = _aligns[i];
    List<String> body(String alignment, String left) => [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 34,',
      '  height: 7,',
      '  child: Box(',
      '    border: .all(type: .rounded, style: theme.border),',
      '    child: Column(',
      '      crossAxisAlignment: .start,',
      '      children: [',
      '        Expanded(',
      '          child: AnimatedAlign(',
      '            alignment: $alignment,',
      '            duration: $_dur,',
      ..._curveLine(o, 12),
      "            child: Text('◆ aligned', style: theme.primary),",
      '          ),',
      '        ),',
      '        AnimatedPadding(',
      '          padding: $left,',
      '          duration: $_dur,',
      ..._curveLine(o, 10),
      "          child: Text('◇ padded', style: theme.accent),",
      '        ),',
      '      ],',
      '    ),',
      '  ),',
      ');',
    ];
    if (!o.flag('cycle')) {
      final left = a.$2.x * 10 + 10;
      return body(
        '.${a.$1}',
        left != 0 ? 'const .only(left: $left)' : '.zero',
      ).join('\n');
    }
    return _ticking(
      [
        'static const _alignments = <Alignment>[',
        for (final x in _aligns) '  .${x.$1},',
        '];',
        'var _i = $i;',
      ],
      _nextOf('_alignments'),
      'the next alignment every 1.2 s',
      [
        'final alignment = _alignments[_i];',
        ...body('alignment', '.only(left: alignment.x * 10 + 10)'),
      ],
    ).join('\n');
  },
);

// ---------------------------------------------------------- AnimatedPositioned

/// Where the chip is pinned: its name, left, top, width and height.
const _pins = <(String, int, int, int, int)>[
  ('topLeft', 1, 1, 12, 1),
  ('bottomLeft', 1, 5, 12, 1),
  ('bottomRight', 21, 5, 12, 1),
  ('topRight', 21, 1, 12, 1),
  ('fill', 1, 1, 32, 5),
];

final _positioned = GalleryPage(
  group: 'Animation',
  title: 'AnimatedPositioned',
  options: [
    ChoiceOption('pin', 'pinned', values: [for (final p in _pins) p.$1]),
    _curveOption,
    _cycleOption,
  ],
  build: (context, o) => _Cycled(o, 'pin', [for (final p in _pins) p.$1], (
    context,
    i,
  ) {
    final theme = Theme.of(context);
    final (_, left, top, width, height) = _pins[i];
    return SizedBox(
      width: 34,
      height: 7,
      child: Stack(
        fit: .expand,
        children: [
          Box(
            border: .all(type: .rounded, style: theme.border),
          ),
          AnimatedPositioned(
            left: left,
            top: top,
            width: width,
            height: height,
            duration: _duration,
            curve: _curveOf(o),
            child: Box(
              style: theme.selection,
              child: const Center(child: Text('▣ pinned')),
            ),
          ),
        ],
      ),
    );
  }),
  code: (o) {
    final i = _pins.indexWhere((p) => p.$1 == o.choice<String>('pin'));
    final p = _pins[i];
    List<String> body(String l, String t, String w, String h) => [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 34,',
      '  height: 7,',
      '  child: Stack(',
      '    fit: .expand,',
      '    children: [',
      '      Box(',
      '        border: .all(type: .rounded, style: theme.border),',
      '      ),',
      '      AnimatedPositioned(',
      '        left: $l,',
      '        top: $t,',
      '        width: $w,',
      '        height: $h,',
      '        duration: $_dur,',
      ..._curveLine(o, 8),
      '        child: Box(',
      '          style: theme.selection,',
      "          child: const Center(child: Text('▣ pinned')),",
      '        ),',
      '      ),',
      '    ],',
      '  ),',
      ');',
    ];
    if (!o.flag('cycle')) {
      return body('${p.$2}', '${p.$3}', '${p.$4}', '${p.$5}').join('\n');
    }
    return _ticking(
      [
        '// left, top, width, height',
        'static const _pins = [',
        for (final q in _pins)
          '  (${q.$2}, ${q.$3}, ${q.$4}, ${q.$5}), // ${q.$1}',
        '];',
        'var _i = $i;',
      ],
      _nextOf('_pins'),
      'pinned elsewhere every 1.2 s',
      [
        'final (left, top, width, height) = _pins[_i];',
        ...body('left', 'top', 'width', 'height'),
      ],
    ).join('\n');
  },
);

// ------------------------------------------------------------ AnimatedBox

final _box = GalleryPage(
  group: 'Animation',
  title: 'AnimatedBox',
  options: [
    const SwitchOption('big', 'big'),
    _curveOption,
    _cycleOption,
  ],
  build: (context, o) => _Cycled(o, 'big', const [false, true], (context, i) {
    final theme = Theme.of(context);
    final big = i == 1;
    return _inFrame(
      _overshoot(o, 34, 7, 5, 1),
      AnimatedBox(
        width: big ? 34 : 16,
        height: big ? 7 : 3,
        style: big ? theme.selection : theme.surface,
        border: .all(
          type: big ? .double : .rounded,
          style: big ? theme.accent : theme.border,
        ),
        padding: big ? const .only(left: 4, top: 1) : .zero,
        duration: _duration,
        curve: _curveOf(o),
        child: const Text('a box'),
      ),
    );
  }),
  code: (o) {
    final room = _overshoot(o, 34, 7, 5, 1);
    // the value written, or null for the Code's `big`
    List<String> body(bool? big) {
      String pick(String yes, String no) => switch (big) {
        true => yes,
        false => no,
        null => 'big ? $yes : $no',
      };
      return [
        'final theme = Theme.of(context);',
        ..._framed(o, room, 'the box at its biggest', [
          'AnimatedBox(',
          '  width: ${pick('34', '16')},',
          '  height: ${pick('7', '3')},',
          '  style: ${pick('theme.selection', 'theme.surface')},',
          '  border: .all(',
          '    type: ${pick('.double', '.rounded')},',
          '    style: ${pick('theme.accent', 'theme.border')},',
          '  ),',
          if (big ?? true)
            '  padding: ${pick('const .only(left: 4, top: 1)', '.zero')},',
          '  duration: $_dur,',
          ..._curveLine(o, 2),
          "  child: const Text('a box'),",
          ')',
        ]),
      ];
    }

    if (!o.flag('cycle')) {
      return body(o.flag('big')).join('\n');
    }
    return _ticking(
      ['var _big = ${o.flag('big')};'],
      '() => _big = !_big',
      'big, then small again, every 1.2 s',
      ['final big = _big;', ...body(null)],
    ).join('\n');
  },
);

// ---------------------------------------------------- AnimatedOpacity, Opacity

const _opacities = [0.0, 0.25, 0.5, 0.75, 1.0];
const _fractions = ['0', '¼', '½', '¾', '1'];

/// The text under the child, and the child: a Box padded a cell either
/// side (a blank at the end of a Text would hang beyond it, uncounted).
const _under = 'under it, under it';
const _child = 'the child';

final _opacity = GalleryPage(
  group: 'Animation',
  title: 'AnimatedOpacity, Opacity',
  options: [
    const ChoiceOption(
      'opacity',
      'opacity',
      values: _opacities,
      labels: _fractions,
      initial: 0.5,
    ),
    _cycleOption,
  ],
  build: (context, o) => _Cycled(o, 'opacity', _opacities, (context, i) {
    final theme = Theme.of(context);
    final opacity = _opacities[i];
    Widget over(Widget child, String name) => Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      gap: 1,
      children: [
        Box(
          style: theme.surface,
          padding: const .all(1),
          child: Stack(
            children: [
              Text(_under, style: theme.muted),
              child,
            ],
          ),
        ),
        Text(name, style: theme.muted),
      ],
    );
    final shown = Box(
      style: theme.selection,
      padding: const .x(1),
      child: Text(_child, style: theme.text),
    );
    return Row(
      mainAxisSize: .min,
      gap: 2,
      children: [
        over(
          AnimatedOpacity(opacity: opacity, duration: _duration, child: shown),
          'AnimatedOpacity',
        ),
        over(Opacity(opacity: opacity, child: shown), 'Opacity'),
      ],
    );
  }),
  code: (o) {
    final value = o.choice<double>('opacity');
    List<String> body(String opacity) => [
      'final theme = Theme.of(context);',
      'Widget over(Widget child, String name) => Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      '    Box(',
      '      style: theme.surface,',
      '      padding: const .all(1),',
      '      child: Stack(',
      '        children: [',
      "          Text('$_under', style: theme.muted),",
      '          child,',
      '        ],',
      '      ),',
      '    ),',
      '    Text(name, style: theme.muted),',
      '  ],',
      ');',
      'final shown = Box(',
      '  style: theme.selection,',
      '  padding: const .x(1),',
      "  child: Text('$_child', style: theme.text),",
      ');',
      'return Row(',
      '  mainAxisSize: .min,',
      '  gap: 2,',
      '  children: [',
      '    over(',
      '      AnimatedOpacity(',
      '        opacity: $opacity,',
      '        duration: $_dur,',
      '        child: shown,',
      '      ),',
      "      'AnimatedOpacity',",
      '    ),',
      "    over(Opacity(opacity: $opacity, child: shown), 'Opacity'),",
      '  ],',
      ');',
    ];
    if (!o.flag('cycle')) {
      return body(_js(value)).join('\n');
    }
    return _ticking(
      [
        'static const _opacities = [0.0, 0.25, 0.5, 0.75, 1.0];',
        'var _i = ${_opacities.indexOf(value)};',
      ],
      _nextOf('_opacities'),
      'the next opacity every 1.2 s',
      ['final opacity = _opacities[_i];', ...body('opacity')],
    ).join('\n');
  },
);

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

// ------------------------------------------------------------ AnimatedSize

const _lines = [
  'one line',
  'a second, longer line',
  'a third',
  'a fourth, the longest of them',
  'and a fifth',
];
const _counts = [1, 3, 5];

/// The alignments the AnimatedSize page offers, topLeft its default.
const _sizeAligns = <(String, Alignment)>[
  ('topLeft', .topLeft),
  ('center', .center),
  ('bottomRight', .bottomRight),
];

final _size = GalleryPage(
  group: 'Animation',
  title: 'AnimatedSize',
  options: [
    const ChoiceOption('lines', 'lines', values: _counts),
    // where the child is in the size shown while it runs
    ChoiceOption(
      'alignment',
      'alignment',
      values: [for (final a in _sizeAligns) a.$1],
    ),
    _curveOption,
    _cycleOption,
  ],
  build: (context, o) => _Cycled(o, 'lines', _counts, (context, i) {
    final theme = Theme.of(context);
    return _inFrame(
      _sizeRoom(o),
      Box(
        border: .all(type: .rounded, style: theme.border),
        child: AnimatedSize(
          duration: _duration,
          curve: _curveOf(o),
          alignment: _sizeAligns
              .firstWhere((a) => a.$1 == o.choice<String>('alignment'))
              .$2,
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [for (final line in _lines.take(_counts[i])) Text(line)],
          ),
        ),
      ),
    );
  }),
  code: (o) {
    List<String> body(String count) => [
      'final theme = Theme.of(context);',
      ..._framed(o, _sizeRoom(o), 'all five lines', [
        'Box(',
        '  border: .all(type: .rounded, style: theme.border),',
        '  child: AnimatedSize(',
        '    duration: $_dur,',
        ..._curveLine(o, 4),
        if (o.choice<String>('alignment') case final a when a != 'topLeft')
          '    alignment: .$a,',
        '    child: Column(',
        '      mainAxisSize: .min,',
        '      crossAxisAlignment: .start,',
        '      children: [for (final line in _lines.take($count)) Text(line)],',
        '    ),',
        '  ),',
        ')',
      ]),
    ];
    final lines = [
      'static const _lines = [',
      for (final l in _lines) "  '$l',",
      '];',
    ];
    final count = o.choice<int>('lines');
    if (!o.flag('cycle')) {
      return [
        ...lines,
        '',
        '@override',
        'Widget build(BuildContext context) {',
        ..._indent(body('$count'), 2),
        '}',
      ].join('\n');
    }
    return _ticking(
      [
        ...lines,
        'static const _counts = [1, 3, 5];',
        'var _i = ${_counts.indexOf(count)};',
      ],
      _nextOf('_counts'),
      'more lines, or fewer, every 1.2 s',
      body('_counts[_i]'),
    ).join('\n');
  },
);

/// The room AnimatedSize grows in: all five lines in the border.
(int, int) _sizeRoom(Options o) => _overshoot(
  o,
  _lines.map(stringWidth).reduce((a, b) => a > b ? a : b) + 2,
  7,
  5,
  1,
);

// ------------------------------------------------------- TweenAnimationBuilder

final _tween = GalleryPage(
  group: 'Animation',
  title: 'TweenAnimationBuilder',
  options: [
    const ChoiceOption(
      'value',
      'value',
      values: _opacities,
      labels: _fractions,
      initial: 0.5,
    ),
    _curveOption,
    _cycleOption,
  ],
  build: (context, o) => _Cycled(
    o,
    'value',
    _opacities,
    (context, i) => TweenAnimationBuilder<double>(
      value: _opacities[i],
      from: 0,
      tween: Tween.new,
      duration: _duration,
      curve: _curveOf(o),
      builder: (context, value, _) {
        final theme = Theme.of(context);
        return Row(
          mainAxisSize: .min,
          gap: 1,
          children: [
            SizedBox(
              width: 30,
              child: ProgressBar(
                value: value,
                style: theme.accent.merge(.new(bg: theme.surface.bg)),
              ),
            ),
            // as wide as 100%
            SizedBox(width: 4, child: Text('${(value * 100).round()}%')),
          ],
        );
      },
    ),
  ),
  code: (o) {
    List<String> body(String value) => [
      'return TweenAnimationBuilder<double>(',
      '  value: $value,',
      '  from: 0,',
      '  tween: Tween.new,',
      '  duration: $_dur,',
      ..._curveLine(o, 2),
      '  builder: (context, value, _) {',
      '    final theme = Theme.of(context);',
      '    return Row(',
      '      mainAxisSize: .min,',
      '      gap: 1,',
      '      children: [',
      '        SizedBox(',
      '          width: 30,',
      '          child: ProgressBar(',
      '            value: value,',
      '            style: theme.accent.merge(.new(bg: theme.surface.bg)),',
      '          ),',
      '        ),',
      '        // as wide as 100%',
      r"        SizedBox(width: 4, child: Text('${(value * 100).round()}%')),",
      '      ],',
      '    );',
      '  },',
      ');',
    ];
    final value = o.choice<double>('value');
    if (!o.flag('cycle')) {
      return body(_js(value)).join('\n');
    }
    return _ticking(
      [
        'static const _values = [0.0, 0.25, 0.5, 0.75, 1.0];',
        'var _i = ${_opacities.indexOf(value)};',
      ],
      _nextOf('_values'),
      'the next value every 1.2 s',
      body('_values[_i]'),
    ).join('\n');
  },
);

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

final _switcher = GalleryPage(
  group: 'Animation',
  title: 'AnimatedSwitcher',
  options: [
    const ChoiceOption('child', 'child', values: _itemLabels),
    ChoiceOption(
      'transition',
      'transition',
      values: _transitions.keys.toList(),
    ),
    _cycleOption,
  ],
  build: (context, o) => _Cycled(o, 'child', _itemLabels, (context, i) {
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
          transition: _transitions[o.choice<String>('transition')]!.$2,
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
    final name = o.choice<String>('transition');
    final tr = _transitions[name]!.$1;
    // all of it const but the key, where a timer gives the child
    final fixed = !o.flag('cycle');
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
    final i = _itemLabels.indexOf(o.choice<String>('child'));
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

// --------------------------------------------- Dissolve, FractionalTranslation

/// The child: its text in a Box padded a cell either side.
const _piece = 'a child, its cells shown or moved';

/// The controller's duration while it runs.
const _round = 2000;

final _dissolve = GalleryPage(
  group: 'Animation',
  title: 'Dissolve, FractionalTranslation',
  options: [
    const ChoiceOption(
      'share',
      'share',
      values: _opacities,
      labels: _fractions,
      initial: 0.5,
    ),
    const SwitchOption('run', 'run', initial: true),
    // the cells from the end of their order: exactly the others
    const SwitchOption('inverse', 'inverse'),
  ],
  build: (context, o) {
    final share = o.choice<double>('share');
    final inverse = o.flag('inverse');
    // a new share, or the switch, runs the controller again from it
    return o.flag('run')
        ? _Shares(share, inverse: inverse, key: ValueKey(share))
        : _sharesTree(context, share, inverse: inverse);
  },
  code: (o) {
    final inverse = o.flag('inverse');
    final inv = inverse ? ', inverse: true' : '';
    List<String> tree(String share) => [
      'Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  children: [',
      '    Text(',
      "      'Dissolve(shown: \${$share.toStringAsFixed(2)}$inv)',",
      '      style: theme.muted,',
      '    ),',
      '    Dissolve(shown: $share$inv, child: shown),',
      '    const SizedBox(height: 1),',
      '    Text(',
      "      'FractionalTranslation(x: \${($share - 1).toStringAsFixed(2)})',",
      '      style: theme.muted,',
      '    ),',
      '    FractionalTranslation(x: $share - 1, child: shown),',
      '  ],',
      ')',
    ];
    const shown = [
      'final theme = Theme.of(context);',
      'final shown = Box(',
      '  style: theme.selection,',
      '  padding: const .x(1),',
      "  child: const Text('$_piece'),",
      ');',
    ];
    final share = o.choice<double>('share');
    if (!o.flag('run')) {
      return [
        ...shown,
        'const share = ${_dbl(share)};',
        'return ${tree('share').join('\n')};',
      ].join('\n');
    }
    final t = tree('share');
    return [
      'final class _SharesState extends State<_Shares>',
      '    with TickerProviderStateMixin {',
      ..._indent([
        'late final _controller = AnimationController(',
        '  vsync: this,',
        '  duration: const Duration(milliseconds: $_round),',
        '  value: ${_js(share)},',
        ')..repeat(reverse: true);',
        '',
        '@override',
        'void dispose() {',
        '  _controller.dispose();',
        '  super.dispose();',
        '}',
        '',
        '@override',
        'Widget build(BuildContext context) {',
        ..._indent(shown, 2),
        '  return ListenableBuilder(',
        '    listenable: _controller,',
        '    builder: (context, _) {',
        '      final share = _controller.value;',
        ..._indent([
          'return ${t.first}',
          ...t.sublist(1, t.length - 1),
          ');',
        ], 6),
        '    },',
        '  );',
        '}',
      ], 2),
      '}',
    ].join('\n');
  },
);

/// The Code's tree: the child dissolved to [share] of its cells, and
/// moved left by what is left of it.
Widget _sharesTree(
  BuildContext context,
  double share, {
  required bool inverse,
}) {
  final theme = Theme.of(context);
  final shown = Box(
    style: theme.selection,
    padding: const .x(1),
    child: const Text(_piece),
  );
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    children: [
      Text(
        'Dissolve(shown: ${share.toStringAsFixed(2)}'
        '${inverse ? ', inverse: true' : ''})',
        style: theme.muted,
      ),
      Dissolve(shown: share, inverse: inverse, child: shown),
      const SizedBox(height: 1),
      Text(
        'FractionalTranslation(x: ${(share - 1).toStringAsFixed(2)})',
        style: theme.muted,
      ),
      FractionalTranslation(x: share - 1, child: shown),
    ],
  );
}

/// The Code's `_Shares`: a controller from [share] up to 1 and back, round
/// after round, the tree at its value.
final class _Shares extends StatefulWidget {
  const _Shares(this.share, {required this.inverse, super.key});

  final double share;
  final bool inverse;

  @override
  State<_Shares> createState() => _SharesState();
}

final class _SharesState extends State<_Shares> with TickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _round),
    value: widget.share,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) =>
        _sharesTree(context, _controller.value, inverse: widget.inverse),
  );
}

// ------------------------------------------------------------ Effect

/// Each effect, as the Code writes it and as twk has it.
final _effects = <String, (String, CellEffect)>{
  'sweep': (
    'CellEffect.sweep(duration: _duration)',
    const CellEffect.sweep(duration: _duration),
  ),
  'dissolve': (
    'CellEffect.dissolve(duration: _duration)',
    const CellEffect.dissolve(duration: _duration),
  ),
  'typewriter': (
    'CellEffect.typewriter(duration: _duration)',
    const CellEffect.typewriter(duration: _duration),
  ),
  'glitch': (
    'CellEffect.glitch(duration: _duration)',
    const CellEffect.glitch(duration: _duration),
  ),
  'dim': (
    'CellEffect.dim(duration: _duration)',
    const CellEffect.dim(duration: _duration),
  ),
  'desaturate': (
    'CellEffect.desaturate(duration: _duration)',
    const CellEffect.desaturate(duration: _duration),
  ),
  'tint': (
    'CellEffect.tint(Color.blue, duration: _duration)',
    const CellEffect.tint(Color.blue, duration: _duration),
  ),
  'scanlines': ('CellEffect.scanlines()', const CellEffect.scanlines()),
  // the colors mapped by a function of the app's
  'grade': (
    'CellEffect.grade(_invert, duration: _duration)',
    const CellEffect.grade(_invert, duration: _duration),
  ),
  'sweep down, glitch': (
    'CellEffect.sequence([\n'
        '  CellEffect.sweep(from: .topCenter, duration: _duration),\n'
        '  CellEffect.glitch(duration: _duration),\n'
        '])',
    const CellEffect.sequence([
      CellEffect.sweep(from: .topCenter, duration: _duration),
      CellEffect.glitch(duration: _duration),
    ]),
  ),
};

final _effect = GalleryPage(
  group: 'Animation',
  title: 'Effect',
  options: [
    ChoiceOption('effect', 'effect', values: _effects.keys.toList()),
    _cycleOption,
  ],
  build: (context, o) => _Cycled(
    o,
    'effect',
    _effects.keys.toList(),
    (context, i) => _Effects(_effects.values.elementAt(i).$2),
  ),
  code: (o) {
    final name = o.choice<String>('effect');
    final effect = _effects[name]!.$1.split('\n');
    List<String> body(List<String> fx) => [
      'final theme = Theme.of(context);',
      'return Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      '    Box(',
      '      style: theme.surface,',
      '      border: .all(type: .rounded, style: theme.border),',
      '      child: Effect(',
      '        key: ValueKey(_runs),',
      ...fx,
      '        child: SizedBox(',
      '          width: 32,',
      '          height: 3,',
      '          child: Column(',
      '            crossAxisAlignment: .start,',
      '            children: [',
      "              Text('Effects over a subtree', style: theme.primary),",
      '              Row(',
      '                gap: 1,',
      '                children: [',
      '                  Spinner(style: theme.accent),',
      "                  const Text('repainting underneath'),",
      '                ],',
      '              ),',
      codeLine([
        "              Text('the cells it paints, filtered', ",
        'style: theme.muted),',
      ]),
      '            ],',
      '          ),',
      '        ),',
      '      ),',
      '    ),',
      '    Row(',
      '      mainAxisSize: .min,',
      '      gap: 2,',
      '      children: [',
      "        Button('Again', onPressed: () => setState(() => _runs++)),",
      "        Text('a new key runs it from its start', style: theme.muted),",
      '      ],',
      '    ),',
      '  ],',
      ');',
    ];
    final top = [
      'const _duration = Duration(milliseconds: 600);',
      '',
      // grade's map: a static method, which a const effect can name
      if (name == 'grade' || o.flag('cycle')) ...[
        '/// Each color as its opposite: the negative of a photograph.',
        'static Color _invert(Color c) =>',
        '    Color.rgb(255 - c.r, 255 - c.g, 255 - c.b);',
        '',
      ],
    ];
    if (!o.flag('cycle')) {
      final fx = [
        '        effect: const ${effect.first}',
        for (final l in effect.skip(1)) '        $l',
      ];
      fx[fx.length - 1] = '${fx.last},';
      return [
        ...top,
        'var _runs = 0;',
        '',
        '@override',
        'Widget build(BuildContext context) {',
        ..._indent(body(fx), 2),
        '}',
      ].join('\n');
    }
    return [
      ...top,
      ..._ticking(
        [
          'static const _effects = <CellEffect>[',
          for (final (dart, _) in _effects.values)
            '${[for (final l in dart.split('\n')) '  $l'].join('\n')},',
          '];',
          'var _i = ${_effects.keys.toList().indexOf(name)};',
          'var _runs = 0;',
        ],
        _nextOf('_effects'),
        'the next effect every 1.2 s, run from its start',
        body(['        effect: _effects[_i],']),
      ),
    ].join('\n');
  },
);

/// Each color as its opposite, as the Code's `_invert` makes it: the map
/// of the Effect page's grade.
Color _invert(Color c) => Color.rgb(255 - c.r, 255 - c.g, 255 - c.b);

/// The Code's State: [effect] over a subtree whose spinner repaints
/// underneath, run again from its start by a new key (Again).
final class _Effects extends StatefulWidget {
  const _Effects(this.effect);

  final CellEffect effect;

  @override
  State<_Effects> createState() => _EffectsState();
}

final class _EffectsState extends State<_Effects> {
  var _runs = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      gap: 1,
      children: [
        Box(
          style: theme.surface,
          border: .all(type: .rounded, style: theme.border),
          child: Effect(
            key: ValueKey(_runs),
            effect: widget.effect,
            child: SizedBox(
              width: 32,
              height: 3,
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text('Effects over a subtree', style: theme.primary),
                  Row(
                    gap: 1,
                    children: [
                      Spinner(style: theme.accent),
                      const Text('repainting underneath'),
                    ],
                  ),
                  Text('the cells it paints, filtered', style: theme.muted),
                ],
              ),
            ),
          ),
        ),
        Row(
          mainAxisSize: .min,
          gap: 2,
          children: [
            Button('Again', onPressed: () => setState(() => _runs++)),
            Text('a new key runs it from its start', style: theme.muted),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ ProgressList

/// The downloads of the ProgressList page: a name, a size in bytes, and
/// the bytes each tick brings.
const _downloads = [
  ('assets.zip', 3400000, 170000),
  ('fonts.tar.gz', 1200000, 140000),
  ('docs.tar.gz', 5600000, 90000),
];

/// How often the downloads bring bytes, in ms.
const _progressTick = 300;

/// The ticks after which it all starts again.
const _progressRun = 40;

/// The tick the docs fail at, and the one the build is done at.
const _docsFail = 12;
const _buildDone = 30;

/// The columns the page offers, by name.
const _progressColumns = <String, List<ProgressColumn>>{
  'default': ProgressList.defaultColumns,
  'count': [
    ProgressColumn.mark,
    ProgressColumn.label,
    ProgressColumn.bar,
    ProgressColumn.count,
    ProgressColumn.eta,
  ],
  'elapsed': [
    ProgressColumn.mark,
    ProgressColumn.label,
    ProgressColumn.bar,
    ProgressColumn.percent,
    ProgressColumn.elapsed,
  ],
};

/// Takes [tracker]'s tasks away and adds the downloads and the build, set
/// going, as the Code's `_start` does.
void _startProgress(ProgressTracker tracker) {
  for (final task in [...tracker.tasks]) {
    tracker.remove(task);
  }
  for (final (name, size, _) in _downloads) {
    tracker.add(name, total: size, unit: ProgressUnit.bytes).start();
  }
  tracker.add('Building binary').start();
}

/// The [ticks]th tick of [tracker], as the Code's `_tick` does it.
void _tickProgress(ProgressTracker tracker, int ticks) {
  if (ticks % _progressRun == 0) {
    return _startProgress(tracker);
  }
  final tasks = tracker.tasks;
  for (final (i, (_, _, bytes)) in _downloads.indexed) {
    final task = tasks[i]..advance(bytes);
    if (task.completed >= task.total!) {
      task.done();
    }
  }
  if (ticks % _progressRun == _docsFail) {
    tasks[2].fail('connection reset');
  }
  if (ticks % _progressRun == _buildDone) {
    tasks[3].done();
  }
}

final _progressList = GalleryPage(
  group: 'Animation',
  title: 'ProgressList',
  options: [
    ChoiceOption('columns', 'columns', values: _progressColumns.keys.toList()),
    ChoiceOption(
      'bar',
      'bar',
      values: [for (final s in ProgressBarShape.values) s.name],
    ),
    // a running task's mark, as the Spinner page's frames
    ChoiceOption('spinner', 'spinner', values: _frames.keys.toList()),
    const SwitchOption('hide', 'hide finished'),
    const ChoiceOption(
      'max',
      'at most',
      values: [null, 2],
      labels: ['all', '2'],
    ),
  ],
  build: (context, o) => _Progress(
    columns: _progressColumns[o.choice<String>('columns')]!,
    barShape: ProgressBarShape.values.byName(o.choice('bar')),
    spinner: _frames[o.choice<String>('spinner')]!,
    hideFinished: o.flag('hide'),
    maxVisible: o.choice('max'),
  ),
  code: (o) {
    final columns = o.choice<String>('columns');
    return [
      codeLine([
        '/// The downloads: a name, a size in bytes, and the bytes a tick ',
        'brings.',
      ]),
      'static const _downloads = [',
      for (final (name, size, bytes) in _downloads)
        "  ('$name', $size, $bytes),",
      '];',
      '',
      "/// On the app's clock, which a test's fake clock moves too.",
      'late final _tracker = ProgressTracker(',
      '  clock: AppBinding.of(context).twkApp.clock,',
      ');',
      'late final Timer _timer;',
      'var _ticks = 0;',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  _start();',
      '  // the bytes that came in, every $_progressTick ms',
      '  _timer = Timer.periodic(',
      '    const Duration(milliseconds: $_progressTick),',
      '    (_) => _tick(),',
      '  );',
      '}',
      '',
      '@override',
      'void dispose() {',
      '  _timer.cancel();',
      '  _tracker.dispose();',
      '  super.dispose();',
      '}',
      '',
      '/// The downloads and the build, from the start.',
      'void _start() {',
      '  for (final task in [..._tracker.tasks]) {',
      '    _tracker.remove(task);',
      '  }',
      '  for (final (name, size, _) in _downloads) {',
      '    _tracker.add(name, total: size, unit: .bytes).start();',
      '  }',
      "  _tracker.add('Building binary').start();",
      '}',
      '',
      'void _tick() {',
      '  // and all again, after ${_progressRun * _progressTick ~/ 1000} s',
      '  if (++_ticks % $_progressRun == 0) {',
      '    return _start();',
      '  }',
      '  final tasks = _tracker.tasks;',
      '  for (final (i, (_, _, bytes)) in _downloads.indexed) {',
      '    final task = tasks[i]..advance(bytes);',
      '    if (task.completed >= task.total!) {',
      '      task.done();',
      '    }',
      '  }',
      '  if (_ticks % $_progressRun == $_docsFail) {',
      "    tasks[2].fail('connection reset');",
      '  }',
      '  if (_ticks % $_progressRun == $_buildDone) {',
      '    tasks[3].done();',
      '  }',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) => SizedBox(',
      '  width: 60,',
      '  child: ProgressList(',
      '    tracker: _tracker,',
      if (columns != 'default') ...[
        '    columns: const [',
        for (final c in _progressColumns[columns]!) '      .${c.name},',
        '    ],',
      ],
      if (o.choice<String>('bar') != 'blocks')
        '    barShape: .${o.choice<String>('bar')},',
      if (o.choice<String>('spinner') != 'dots')
        '    spinner: .${o.choice<String>('spinner')},',
      if (o.flag('hide')) '    hideFinished: true,',
      if (o.choice<int?>('max') case final max?) '    maxVisible: $max,',
      '  ),',
      ');',
    ].join('\n');
  },
);

/// A stopwatch at the time it is set to: the gallery's, as the tracker
/// reads it, so that a route's `t=` stills the times it shows.
final class _Watch implements Stopwatch {
  Duration at = Duration.zero;

  @override
  Duration get elapsed => at;

  @override
  int get elapsedMicroseconds => at.inMicroseconds;

  @override
  int get elapsedMilliseconds => at.inMilliseconds;

  @override
  int get elapsedTicks => at.inMicroseconds;

  @override
  int get frequency => 1000000;

  @override
  bool get isRunning => true;

  @override
  void reset() {}

  @override
  void start() {}

  @override
  void stop() {}
}

/// The downloads and the build in a ProgressList, ticked on the gallery's
/// clock from when the page was built: each tick the Code's timer would
/// have run by now is run, the tracker's time at the tick's.
final class _Progress extends StatefulWidget {
  const _Progress({
    required this.columns,
    required this.barShape,
    required this.spinner,
    required this.hideFinished,
    required this.maxVisible,
  });

  final List<ProgressColumn> columns;
  final ProgressBarShape barShape;
  final SpinnerFrames spinner;
  final bool hideFinished;
  final int? maxVisible;

  @override
  State<_Progress> createState() => _ProgressState();
}

final class _ProgressState extends State<_Progress> {
  late final _motion = Motion(() {
    if (mounted) {
      setState(() {});
    }
  });
  final _watch = _Watch();
  late final _tracker = ProgressTracker(clock: _watch);
  Duration? _born;
  var _ticks = 0;

  @override
  void dispose() {
    _motion.dispose();
    _tracker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _motion.begin(context);
    final now = _motion.now;
    final born = _born ??= _motion.frozen ? Duration.zero : now;
    if (_ticks == 0 && _tracker.tasks.isEmpty) {
      _watch.at = Duration.zero;
      _startProgress(_tracker);
    }
    final due = (now - born).inMilliseconds ~/ _progressTick;
    while (_ticks < due) {
      _ticks++;
      _watch.at = Duration(milliseconds: _ticks * _progressTick);
      _tickProgress(_tracker, _ticks);
    }
    _watch.at = now - born;
    _motion
      ..wakeAt(born + Duration(milliseconds: (_ticks + 1) * _progressTick))
      ..end();
    return SizedBox(
      width: 60,
      child: ProgressList(
        tracker: _tracker,
        columns: widget.columns,
        barShape: widget.barShape,
        spinner: widget.spinner,
        hideFinished: widget.hideFinished,
        maxVisible: widget.maxVisible,
      ),
    );
  }
}

// ------------------------------------------------------------ Skeleton

final _skeleton = GalleryPage(
  group: 'Animation',
  title: 'Skeleton, Skeletonize',
  options: const [
    SwitchOption('loading', 'loading', initial: true),
    SwitchOption('shimmer', 'shimmer', initial: true),
    ChoiceOption('glyph', 'glyph', values: ['░', '▒', '▓']),
    ChoiceOption('band', 'band', values: [8, 4, 16], labels: ['8', '4', '16']),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final shimmer = o.flag('shimmer');
    return SkeletonTheme(
      glyph: o.choice('glyph'),
      band: o.choice('band'),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        gap: 1,
        children: [
          SizedBox(
            width: 40,
            child: Box(
              border: .all(type: .rounded, style: theme.border),
              padding: const .x(1),
              child: Skeletonize(
                enabled: o.flag('loading'),
                shimmer: shimmer,
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: [
                    Text('user@twk', style: theme.primary),
                    const Text('Maintains twk and its gallery.'),
                    Text('Joined 19 October 2026', style: theme.muted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 40, child: Skeleton.text(lines: 3)),
          const Row(
            mainAxisSize: .min,
            gap: 1,
            children: [
              Skeleton(width: 8),
              Skeleton(width: 12),
            ],
          ),
        ],
      ),
    );
  },
  code: (o) {
    final glyph = o.choice<String>('glyph');
    final band = o.choice<int>('band');
    final args = [
      if (glyph != '░') "glyph: '$glyph'",
      if (band != 8) 'band: $band',
    ];
    return [
      'final theme = Theme.of(context);',
      'return SkeletonTheme(',
      for (final a in args) '  $a,',
      '  child: Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      SizedBox(',
      '        width: 40,',
      '        child: Box(',
      '          border: .all(type: .rounded, style: theme.border),',
      '          padding: const .x(1),',
      '          // laid out as it is, drawn as blocks while it loads',
      '          child: Skeletonize(',
      '            enabled: ${o.flag('loading')},',
      if (!o.flag('shimmer')) '            shimmer: false,',
      '            child: Column(',
      '              mainAxisSize: .min,',
      '              crossAxisAlignment: .start,',
      '              children: [',
      "                Text('user@twk', style: theme.primary),",
      "                const Text('Maintains twk and its gallery.'),",
      "                Text('Joined 19 October 2026', style: theme.muted),",
      '              ],',
      '            ),',
      '          ),',
      '        ),',
      '      ),',
      '      // blocks of their own: three lines, and two words',
      '      const SizedBox(width: 40, child: Skeleton.text(lines: 3)),',
      '      const Row(',
      '        mainAxisSize: .min,',
      '        gap: 1,',
      '        children: [Skeleton(width: 8), Skeleton(width: 12)],',
      '      ),',
      '    ],',
      '  ),',
      ');',
    ].join('\n');
  },
);
