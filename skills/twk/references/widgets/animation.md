<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Animation

Spinners, progress, and widgets that animate as their values change.

[All widgets](../widgets.md)

## Spinner

Frames shown in turn while something goes on; spinners of the same frames step together.

API: [`Spinner`](https://pub.dev/documentation/twk/latest/twk/Spinner-class.html).

### Code

```dart
final theme = Theme.of(context);
const tasks = ['Resolving packages…', 'Compiling…', 'Running 214 tests…'];
return Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    for (final task in tasks)
      Row(
        mainAxisSize: .min,
        spacing: 1,
        children: [
          Spinner(style: theme.primary),
          Text(task),
        ],
      ),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| frames | dots, line, arc | dots |
| style | primary, accent, success, warning, info | primary |

## TickerMode

Whether the animations below tick: off, they ask for no frames and stand still, and go on when it is on again; Offstage and Visibility turn it off for what they hide.

API: [`TickerMode`](https://pub.dev/documentation/twk/latest/twk/TickerMode-class.html).

### Code

```dart
final theme = Theme.of(context);
return TickerMode(
  enabled: true,
  child: Row(
    mainAxisSize: .min,
    spacing: 1,
    children: [
      Spinner(style: theme.primary),
      const Text('Compiling…'),
    ],
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| enabled | on, off | true |

## ProgressBar

A bar filled as far as its value, in eighths of a cell; a block going to and fro while the value is not known.

API: [`ProgressBar`](https://pub.dev/documentation/twk/latest/twk/ProgressBar-class.html).

### Code

```dart
final theme = Theme.of(context);
return Row(
  mainAxisSize: .min,
  spacing: 1,
  children: [
    SizedBox(
      width: 40,
      child: ProgressBar(
        value: 0.33,
        style: theme.success.merge(.new(bg: theme.surface.bg)),
      ),
    ),
    const Text(' 33%'),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| value known | on, off | true |
| value | 0% to 100% | 33 |
| style | primary, accent, success, warning, info | success |

## ProgressList

Many tasks at once, a row each: its mark, a bar, how much is done, its rate and the time it has left, from a ProgressTracker the work counts on.

API: [`ProgressList`](https://pub.dev/documentation/twk/latest/twk/ProgressList-class.html).

### Code

```dart
/// The downloads: a name, a size in bytes, and the bytes a tick brings.
static const _downloads = [
  ('assets.zip', 3400000, 170000),
  ('fonts.tar.gz', 1200000, 140000),
  ('docs.tar.gz', 5600000, 90000),
];

/// On the app's clock, which a test's fake clock moves too.
late final _tracker = ProgressTracker(
  clock: AppBinding.of(context).twkApp.clock,
);
late final Timer _timer;
var _ticks = 0;

@override
void initState() {
  super.initState();
  _start();
  // the bytes that came in, every 300 ms
  _timer = Timer.periodic(
    const Duration(milliseconds: 300),
    (_) => _tick(),
  );
}

@override
void dispose() {
  _timer.cancel();
  _tracker.dispose();
  super.dispose();
}

/// The downloads and the build, from the start.
void _start() {
  for (final task in [..._tracker.tasks]) {
    _tracker.remove(task);
  }
  for (final (name, size, _) in _downloads) {
    _tracker.add(name, total: size, unit: .bytes).start();
  }
  _tracker.add('Building binary').start();
}

void _tick() {
  // and all again, after 12 s
  if (++_ticks % 40 == 0) {
    return _start();
  }
  final tasks = _tracker.tasks;
  for (final (i, (_, _, bytes)) in _downloads.indexed) {
    final task = tasks[i]..advance(bytes);
    if (task.completed >= task.total!) {
      task.done();
    }
  }
  if (_ticks % 40 == 12) {
    tasks[2].fail('connection reset');
  }
  if (_ticks % 40 == 30) {
    tasks[3].done();
  }
}

@override
Widget build(BuildContext context) => SizedBox(
  width: 60,
  child: ProgressList(
    tracker: _tracker,
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| columns | default, count, elapsed | default |
| bar | blocks, line | blocks |
| spinner | dots, line, arc | dots |
| hide finished | on, off | false |
| at most | all, 2 | all |

## Skeleton, Skeletonize

Placeholders while content loads: blocks where it will be, or a subtree drawn as blocks in the layout it has, a shimmer sweeping over them as a SkeletonTheme says.

API: [`Skeleton`](https://pub.dev/documentation/twk/latest/twk/Skeleton-class.html), [`Skeletonize`](https://pub.dev/documentation/twk/latest/twk/Skeletonize-class.html).

### Code

```dart
final theme = Theme.of(context);
return SkeletonTheme(
  child: Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      SizedBox(
        width: 40,
        child: Box(
          border: .all(type: .rounded, style: theme.border),
          padding: const .x(1),
          // laid out as it is, drawn as blocks while it loads
          child: Skeletonize(
            enabled: true,
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
      // blocks of their own: three lines, and two words
      const SizedBox(width: 40, child: Skeleton.text(lines: 3)),
      const Row(
        mainAxisSize: .min,
        spacing: 1,
        children: [Skeleton(width: 8), Skeleton(width: 12)],
      ),
    ],
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| loading | on, off | true |
| shimmer | on, off | true |
| glyph | ░, ▒, ▓ | ░ |
| band | 8, 4, 16 | 8 |

## AnimationController

An animation of the page's own: a controller from 0 to 1 and back, a frame at a time, through a curve and a tween.

API: [`AnimationController`](https://pub.dev/documentation/twk/latest/twk/AnimationController-class.html).

### Code

```dart
final class _PulseState extends State<_Pulse>
    with TickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  static const _across = IntTween(begin: 0, end: 39);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() => setState(() {
    if (_controller.isAnimating) {
      _controller.stop();
    } else {
      _controller.repeat(reverse: true);
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        final curved = Curves.easeInOut.transform(value);
        final x = _across.chain(Curves.easeInOut).evaluate(_controller);
        return SizedBox(
          width: 42,
          // the track as wide as the column: the dot runs across it
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: 1,
            children: [
              Box(
                border: .all(type: .rounded, style: theme.border),
                child: Text(
                  '${' ' * x.clamp(0, 39)}●',
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
```

### Options

| option | values | starts at |
| --- | --- | --- |
| curve | linear, ease, easeIn, easeOut, easeInOut, fastOutSlowIn, decelerate, bounceOut, elasticOut | easeInOut |
| reverse | on, off | true |
| duration | 1 s, 2 s, 4 s | 2 s |

## AnimatedBuilder

A builder run again at each tick of an animation, the part that does not change built once and passed in as its child.

API: [`AnimatedBuilder`](https://pub.dev/documentation/twk/latest/twk/AnimatedBuilder-class.html).

### Code

```dart
final class _SlideState extends State<_Slide>
    with TickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  static final _across = IntTween(begin: 0, end: 35).chain(
    Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 42,
      child: Box(
        border: .all(type: .rounded, style: theme.border),
        child: AnimatedBuilder(
          animation: _controller,
          // at each tick: the chip moved along the track
          builder: (context, child) => Row(
            children: [
              SizedBox(width: _across.evaluate(_controller)),
              child!,
            ],
          ),
          // built once, here, and handed to the builder at each tick
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
```

### Options

| option | values | starts at |
| --- | --- | --- |
| curve | linear, ease, easeIn, easeOut, easeInOut, fastOutSlowIn, decelerate, bounceOut, elasticOut | easeInOut |
| reverse | on, off | true |
| duration | 1 s, 2 s, 4 s | 2 s |

## AnimatedAlign, AnimatedPadding

A child that runs to the place its alignment or its padding gives it, a cell at a time.

API: [`AnimatedAlign`](https://pub.dev/documentation/twk/latest/twk/AnimatedAlign-class.html), [`AnimatedPadding`](https://pub.dev/documentation/twk/latest/twk/AnimatedPadding-class.html).

### Code

```dart
static const _alignments = <Alignment>[
  .centerLeft,
  .center,
  .centerRight,
  .bottomRight,
];
var _i = 0;
late final Timer _timer;

@override
void initState() {
  super.initState();
  // the next alignment every 1.2 s
  _timer = Timer.periodic(
    const Duration(milliseconds: 1200),
    (_) => setState(() => _i = (_i + 1) % _alignments.length),
  );
}

@override
void dispose() {
  _timer.cancel();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final alignment = _alignments[_i];
  final theme = Theme.of(context);
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
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOut,
              child: Text('◆ aligned', style: theme.primary),
            ),
          ),
          AnimatedPadding(
            padding: .only(left: alignment.x * 10 + 10),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
            child: Text('◇ padded', style: theme.accent),
          ),
        ],
      ),
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| alignment | centerLeft, center, centerRight, bottomRight | centerLeft |
| curve | linear, ease, easeIn, easeOut, easeInOut, fastOutSlowIn, decelerate, bounceOut, elasticOut | easeInOut |
| cycle | on, off | true |

## AnimatedPositioned

A child pinned in a stack that runs to the edges it is pinned to.

API: [`AnimatedPositioned`](https://pub.dev/documentation/twk/latest/twk/AnimatedPositioned-class.html).

### Code

```dart
// left, top, width, height
static const _pins = [
  (1, 1, 12, 1), // topLeft
  (1, 5, 12, 1), // bottomLeft
  (21, 5, 12, 1), // bottomRight
  (21, 1, 12, 1), // topRight
  (1, 1, 32, 5), // fill
];
var _i = 0;
late final Timer _timer;

@override
void initState() {
  super.initState();
  // pinned elsewhere every 1.2 s
  _timer = Timer.periodic(
    const Duration(milliseconds: 1200),
    (_) => setState(() => _i = (_i + 1) % _pins.length),
  );
}

@override
void dispose() {
  _timer.cancel();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final (left, top, width, height) = _pins[_i];
  final theme = Theme.of(context);
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
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          child: Box(
            style: theme.selection,
            child: const Center(child: Text('▣ pinned')),
          ),
        ),
      ],
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| pinned | topLeft, bottomLeft, bottomRight, topRight, fill | topLeft |
| curve | linear, ease, easeIn, easeOut, easeInOut, fastOutSlowIn, decelerate, bounceOut, elasticOut | easeInOut |
| cycle | on, off | true |

## AnimatedBox

A box whose size, padding, background and border colors run to the new ones; a border of another type switches halfway.

API: [`AnimatedBox`](https://pub.dev/documentation/twk/latest/twk/AnimatedBox-class.html).

### Code

```dart
var _big = false;
late final Timer _timer;

@override
void initState() {
  super.initState();
  // big, then small again, every 1.2 s
  _timer = Timer.periodic(
    const Duration(milliseconds: 1200),
    (_) => setState(() => _big = !_big),
  );
}

@override
void dispose() {
  _timer.cancel();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final big = _big;
  final theme = Theme.of(context);
  // the room it grows in: the box at its biggest
  return SizedBox(
    width: 34,
    height: 7,
    child: Align(
      alignment: .topLeft,
      child: AnimatedBox(
        width: big ? 34 : 16,
        height: big ? 7 : 3,
        style: big ? theme.selection : theme.surface,
        border: .all(
          type: big ? .double : .rounded,
          style: big ? theme.accent : theme.border,
        ),
        padding: big ? const .only(left: 4, top: 1) : .zero,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        child: const Text('a box'),
      ),
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| big | on, off | false |
| curve | linear, ease, easeIn, easeOut, easeInOut, fastOutSlowIn, decelerate, bounceOut, elasticOut | easeInOut |
| cycle | on, off | true |

## AnimatedOpacity, Opacity

A child shown at an opacity, mixed cell by cell with what is under it; the one on the left runs to the opacity chosen.

API: [`AnimatedOpacity`](https://pub.dev/documentation/twk/latest/twk/AnimatedOpacity-class.html), [`Opacity`](https://pub.dev/documentation/twk/latest/twk/Opacity-class.html).

### Code

```dart
static const _opacities = [0.0, 0.25, 0.5, 0.75, 1.0];
var _i = 2;
late final Timer _timer;

@override
void initState() {
  super.initState();
  // the next opacity every 1.2 s
  _timer = Timer.periodic(
    const Duration(milliseconds: 1200),
    (_) => setState(() => _i = (_i + 1) % _opacities.length),
  );
}

@override
void dispose() {
  _timer.cancel();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final opacity = _opacities[_i];
  final theme = Theme.of(context);
  Widget over(Widget child, String name) => Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      Box(
        style: theme.surface,
        padding: const .all(1),
        child: Stack(
          children: [
            Text('under it, under it', style: theme.muted),
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
    child: Text('the child', style: theme.text),
  );
  return Row(
    mainAxisSize: .min,
    spacing: 2,
    children: [
      over(
        AnimatedOpacity(
          opacity: opacity,
          duration: const Duration(milliseconds: 600),
          child: shown,
        ),
        'AnimatedOpacity',
      ),
      over(Opacity(opacity: opacity, child: shown), 'Opacity'),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| opacity | 0, ¼, ½, ¾, 1 | ½ |
| cycle | on, off | true |

## AnimatedDefaultTextStyle

The style of the text below it, its colors running to the new ones.

API: [`AnimatedDefaultTextStyle`](https://pub.dev/documentation/twk/latest/twk/AnimatedDefaultTextStyle-class.html).

### Code

```dart
var _i = 0;
late final Timer _timer;

@override
void initState() {
  super.initState();
  // the next style every 1.2 s
  _timer = Timer.periodic(
    const Duration(milliseconds: 1200),
    (_) => setState(() => _i = (_i + 1) % 3),
  );
}

@override
void dispose() {
  _timer.cancel();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  final slot = [theme.primary, theme.error, theme.success][_i];
  return AnimatedDefaultTextStyle(
    style: slot,
    duration: const Duration(milliseconds: 600),
    child: const Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        Text('Text in the style above it,'),
        Text('and a second Text, in step.'),
      ],
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| style | primary, error, success | primary |
| bold | on, off | false |
| cycle | on, off | true |

## AnimatedSize

As big as its child, running to the new size when the child grows or shrinks.

API: [`AnimatedSize`](https://pub.dev/documentation/twk/latest/twk/AnimatedSize-class.html).

### Code

```dart
static const _lines = [
  'one line',
  'a second, longer line',
  'a third',
  'a fourth, the longest of them',
  'and a fifth',
];
static const _counts = [1, 3, 5];
var _i = 0;
late final Timer _timer;

@override
void initState() {
  super.initState();
  // more lines, or fewer, every 1.2 s
  _timer = Timer.periodic(
    const Duration(milliseconds: 1200),
    (_) => setState(() => _i = (_i + 1) % _counts.length),
  );
}

@override
void dispose() {
  _timer.cancel();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  // the room it grows in: all five lines
  return SizedBox(
    width: 31,
    height: 7,
    child: Align(
      alignment: .topLeft,
      child: Box(
        border: .all(type: .rounded, style: theme.border),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [for (final line in _lines.take(_counts[_i])) Text(line)],
          ),
        ),
      ),
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| lines | 1, 3, 5 | 1 |
| alignment | topLeft, center, bottomRight | topLeft |
| curve | linear, ease, easeIn, easeOut, easeInOut, fastOutSlowIn, decelerate, bounceOut, elasticOut | easeInOut |
| cycle | on, off | true |

## TweenAnimationBuilder

Builds with a value that runs to the one it is given, through the tweens it makes.

API: [`TweenAnimationBuilder`](https://pub.dev/documentation/twk/latest/twk/TweenAnimationBuilder-class.html).

### Code

```dart
static const _values = [0.0, 0.25, 0.5, 0.75, 1.0];
var _i = 2;
late final Timer _timer;

@override
void initState() {
  super.initState();
  // the next value every 1.2 s
  _timer = Timer.periodic(
    const Duration(milliseconds: 1200),
    (_) => setState(() => _i = (_i + 1) % _values.length),
  );
}

@override
void dispose() {
  _timer.cancel();
  super.dispose();
}

@override
Widget build(BuildContext context) => TweenAnimationBuilder<double>(
  tween: Tween<double>(begin: 0, end: _values[_i]),
  duration: const Duration(milliseconds: 600),
  curve: Curves.easeInOut,
  builder: (context, value, _) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: .min,
      spacing: 1,
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
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| value | 0, ¼, ½, ¾, 1 | ½ |
| curve | linear, ease, easeIn, easeOut, easeInOut, fastOutSlowIn, decelerate, bounceOut, elasticOut | easeInOut |
| cycle | on, off | true |

## AnimatedSwitcher

A child that gives way to another as the transition shows them: faded, slid or dissolved.

API: [`AnimatedSwitcher`](https://pub.dev/documentation/twk/latest/twk/AnimatedSwitcher-class.html).

### Code

```dart
static const _children = [
  'the first child',
  'and now the second one',
  'a third',
];
var _i = 0;
late final Timer _timer;

@override
void initState() {
  super.initState();
  // the next child every 1.2 s
  _timer = Timer.periodic(
    const Duration(milliseconds: 1200),
    (_) => setState(() => _i = (_i + 1) % _children.length),
  );
}

@override
void dispose() {
  _timer.cancel();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final child = _children[_i];
  final theme = Theme.of(context);
  return SizedBox(
    width: 34,
    height: 5,
    child: Box(
      style: theme.surface,
      border: .all(type: .rounded, style: theme.border),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        child: SizedBox(
          key: ValueKey(child),
          width: 32,
          height: 3,
          child: Center(child: Text(child)),
        ),
      ),
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| child | first, second, third | first |
| transition | fade, slide, slide right, slide up, slide down, dissolve | fade |
| cycle | on, off | true |

## Dissolve, FractionalTranslation

What the transitions are made of: a share of the cells of a child, and a child moved a share of its size.

API: [`Dissolve`](https://pub.dev/documentation/twk/latest/twk/Dissolve-class.html), [`FractionalTranslation`](https://pub.dev/documentation/twk/latest/twk/FractionalTranslation-class.html).

### Code

```dart
final class _SharesState extends State<_Shares>
    with TickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
    value: 0.5,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = Box(
      style: theme.selection,
      padding: const .x(1),
      child: const Text('a child, its cells shown or moved'),
    );
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final share = _controller.value;
        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            Text(
              'Dissolve(shown: ${share.toStringAsFixed(2)})',
              style: theme.muted,
            ),
            Dissolve(shown: share, child: shown),
            const SizedBox(height: 1),
            Text(
              'FractionalTranslation(x: ${(share - 1).toStringAsFixed(2)})',
              style: theme.muted,
            ),
            FractionalTranslation(x: share - 1, child: shown),
          ],
        );
      },
    );
  }
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| share | 0, ¼, ½, ¾, 1 | ½ |
| run | on, off | true |
| inverse | on, off | false |

## Effect

A child shown through an effect over its cells, run on the app's clock: recolored, swept, dissolved, typed or glitched in, while the child repaints underneath.

API: [`Effect`](https://pub.dev/documentation/twk/latest/twk/Effect-class.html).

### Code

```dart
const _duration = Duration(milliseconds: 600);

/// Each color as its opposite: the negative of a photograph.
static Color _invert(Color c) =>
    Color.rgb(255 - c.r, 255 - c.g, 255 - c.b);

static const _effects = <CellEffect>[
  CellEffect.sweep(duration: _duration),
  CellEffect.dissolve(duration: _duration),
  CellEffect.typewriter(duration: _duration),
  CellEffect.glitch(duration: _duration),
  CellEffect.dim(duration: _duration),
  CellEffect.desaturate(duration: _duration),
  CellEffect.tint(Color.blue, duration: _duration),
  CellEffect.scanlines(),
  CellEffect.grade(_invert, duration: _duration),
  CellEffect.sequence([
    CellEffect.sweep(from: .topCenter, duration: _duration),
    CellEffect.glitch(duration: _duration),
  ]),
];
var _i = 0;
var _runs = 0;
late final Timer _timer;

@override
void initState() {
  super.initState();
  // the next effect every 1.2 s, run from its start
  _timer = Timer.periodic(
    const Duration(milliseconds: 1200),
    (_) => setState(() => _i = (_i + 1) % _effects.length),
  );
}

@override
void dispose() {
  _timer.cancel();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      Box(
        style: theme.surface,
        border: .all(type: .rounded, style: theme.border),
        child: Effect(
          key: ValueKey(_runs),
          effect: _effects[_i],
          child: SizedBox(
            width: 32,
            height: 3,
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text('Effects over a subtree', style: theme.primary),
                Row(
                  spacing: 1,
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
        spacing: 2,
        children: [
          Button('Again', onPressed: () => setState(() => _runs++)),
          Text('a new key runs it from its start', style: theme.muted),
        ],
      ),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| effect | sweep, dissolve, typewriter, glitch, dim, desaturate, tint, scanlines, grade, sweep down, glitch | sweep |
| cycle | on, off | true |
