<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Layout

Boxes, rows and columns, stacks, grids and wraps: where a child goes and how much room it gets.

[All widgets](../widgets.md)

## Box

A border, titles on it, padding and a background around a child.

API: [`Box`](https://pub.dev/documentation/twk/latest/twk/Box-class.html).

### Code

```dart
final theme = Theme.of(context);
return SizedBox(
  width: 36,
  height: 8,
  child: Box(
    border: .all(type: .rounded, style: theme.border),
    titles: [
      BorderTitle(
        ' build ',
        style: theme.text.merge(const .new(attrs: Attr.bold)),
      ),
      BorderTitle(
        ' 2 warnings ',
        style: theme.warning,
        alignment: .bottomRight,
      ),
    ],
    padding: const .all(1),
    child: const Text(
      'Compiling 14 libraries…\n'
      'lib/src/layout    0.4 s\n'
      'lib/src/render    0.9 s',
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| border | single, rounded, double, heavy, ascii, none | rounded |
| sides | all, top bottom, top left, left | all |
| titles | on, off | true |
| title at | topLeft, topCenter, topRight, bottomLeft, bottomCenter | topLeft |
| padding | 0, 1, 2 | 1 |
| surface | on, off | false |

## ColoredBox, DecoratedBox

A child's cells filled with a color, and a BoxDecoration (a fill, a border, titles) drawn under the child or over its edges.

API: [`ColoredBox`](https://pub.dev/documentation/twk/latest/twk/ColoredBox-class.html), [`DecoratedBox`](https://pub.dev/documentation/twk/latest/twk/DecoratedBox-class.html).

### Code

```dart
final theme = Theme.of(context);
return DecoratedBox(
  decoration: BoxDecoration(
    border: .all(type: .rounded, style: theme.border),
    titles: [BorderTitle(' notes ', style: theme.muted)],
  ),
  child: ColoredBox(
    color: theme.selection.bg!,
    child: const Padding(
      padding: .all(1),
      child: Text('release 0.4.0\n3 commits, 2 fixes'),
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| position | background, foreground | background |
| fill | ColoredBox, gradient | ColoredBox |
| border | single, rounded, double, heavy, ascii | rounded |
| titles | on, off | true |

## Container

Align, Padding, a color or a decoration, a size and a margin put together around one child, as Flutter's Container puts them.

API: [`Container`](https://pub.dev/documentation/twk/latest/twk/Container-class.html).

### Code

```dart
final theme = Theme.of(context);
return Container(
  width: 30,
  height: 7,
  margin: const .all(1),
  padding: const .all(1),
  alignment: .center,
  decoration: BoxDecoration(
    style: theme.surface,
    border: .all(type: .rounded, style: theme.border),
  ),
  child: const Text('deploy to staging'),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| fill | decoration, color | decoration |
| alignment | none, topLeft, center, bottomRight | center |
| width | none, 24, 30, 36 | 30 |
| height | none, 5, 7, 9 | 7 |
| padding | 0, 1, 2 | 1 |
| margin | 0, 1, 2 | 1 |
| foreground | on, off | false |

## Divider

A line across, and a VerticalDivider down; merged, they join the lines drawn before them where they meet.

API: [`Divider`](https://pub.dev/documentation/twk/latest/twk/Divider-class.html).

### Code

```dart
final theme = Theme.of(context);
return SizedBox(
  width: 36,
  height: 7,
  child: Stack(
    fit: .expand,
    children: [
      Box(border: .all(style: theme.border)),
      const Positioned(
        left: 2,
        top: 1,
        child: Text('release 0.4.0', style: .new(attrs: Attr.bold)),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: 2,
        child: Divider(style: theme.border, merge: true),
      ),
      Positioned(
        left: 17,
        top: 2,
        bottom: 0,
        child: VerticalDivider(style: theme.border, merge: true),
      ),
      Positioned(left: 2, top: 3, child: Text('added', style: theme.muted)),
      const Positioned(left: 2, top: 4, child: Text('Grid tracks\nDockArea')),
      Positioned(left: 19, top: 3, child: Text('fixed', style: theme.muted)),
      const Positioned(
        left: 19,
        top: 4,
        child: Text('wide glyphs\nwheel scroll'),
      ),
    ],
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| type | single, rounded, double, heavy, ascii | single |
| merge | on, off | true |

## Shadow

A drop shadow: the cells beside and below a child, moved by its offset, what is under them darkened.

API: [`Shadow`](https://pub.dev/documentation/twk/latest/twk/Shadow-class.html).

### Code

```dart
final theme = Theme.of(context);
return SizedBox(
  width: 36,
  height: 8,
  child: Stack(
    fit: .expand,
    children: [
      Text(
        'what is under a shadow keeps its glyphs; their colours darken. ' * 5,
        style: theme.muted,
      ),
      Positioned(
        left: 5,
        top: 2,
        child: Shadow(
          shadow: const BoxShadow(),
          child: Box(
            style: theme.surface.merge(theme.text),
            border: .all(type: .rounded, style: theme.border),
            padding: const .x(1),
            child: const Text('a box with a shadow'),
          ),
        ),
      ),
    ],
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| offset | 2, 1, 1, 1, -2, -1 | 2, 1 |
| alpha | ¼, ½, ¾ | ½ |

## Padding

Empty cells around a child.

API: [`Padding`](https://pub.dev/documentation/twk/latest/twk/Padding-class.html).

### Code

```dart
final theme = Theme.of(context);
return Box(
  border: .all(type: .rounded, style: theme.border),
  child: Padding(
    padding: const .x(4),
    child: Box(
      style: theme.selection,
      child: const Text('the child,\npadded from the box'),
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| padding | all 1, x 4, y 2, left 8, left 3, top 1 | x 4 |

## Align, Center

A child placed in the room it is given; Center in the middle of it.

API: [`Align`](https://pub.dev/documentation/twk/latest/twk/Align-class.html), [`Center`](https://pub.dev/documentation/twk/latest/twk/Center-class.html).

### Code

```dart
final theme = Theme.of(context);
Widget room(String title, Widget child) => SizedBox(
  width: 30,
  height: 5,
  child: Box(
    border: .all(type: .rounded, style: theme.border),
    titles: [BorderTitle(' $title ', style: theme.muted)],
    child: child,
  ),
);
return Column(
  mainAxisSize: .min,
  spacing: 1,
  children: [
    room('.bottomRight', const Align(
      alignment: .bottomRight,
      child: Text('aligned'),
    )),
    room('Center', const Center(child: Text('centred'))),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| alignment x | left, center, right | right |
| alignment y | top, center, bottom | bottom |
| width factor | none, 1, 2, 3 | none |
| height factor | none, 1, 2, 3 | none |

## SizedBox

A child of a size: SizedBox.expand fills the room, SizedBox.shrink takes none.

API: [`SizedBox`](https://pub.dev/documentation/twk/latest/twk/SizedBox-class.html).

### Code

```dart
final theme = Theme.of(context);
return SizedBox(
  width: 40,
  height: 9,
  child: Box(
    border: .all(type: .rounded, style: theme.border),
    child: Center(
      child: SizedBox(
        width: 16,
        height: 3,
        child: Box(style: theme.selection, child: const Text('16 × 3')),
      ),
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| constructor | width, height, .expand, .shrink | width, height |
| width | 0 cells to 44 cells | 16 |
| height | 0 rows to 9 rows | 3 |

## ConstrainedBox

Constraints a child is laid out within, merged with those it is given.

API: [`ConstrainedBox`](https://pub.dev/documentation/twk/latest/twk/ConstrainedBox-class.html).

### Code

```dart
final theme = Theme.of(context);
Widget bounded(String text) => ConstrainedBox(
  constraints: const BoxConstraints(
    minWidth: 12,
    maxWidth: 32,
    minHeight: 1,
    maxHeight: 3,
  ),
  child: Box(
    style: theme.selection,
    padding: const .x(1),
    child: Text(text),
  ),
);
return Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    bounded('short'),
    bounded('A child as wide as its text, within the bounds.'),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| min width | 0, 12, 20 | 12 |
| max width | 20, 32, 48 | 32 |

## LimitedBox, OverflowBox

Other constraints than the room gives: LimitedBox limits a child only where the room has no limit, OverflowBox and SizedOverflowBox give it others in its place, cut off where it sticks out.

API: [`LimitedBox`](https://pub.dev/documentation/twk/latest/twk/LimitedBox-class.html), [`OverflowBox`](https://pub.dev/documentation/twk/latest/twk/OverflowBox-class.html).

### Code

```dart
final theme = Theme.of(context);
return SizedBox(
  width: 30,
  height: 5,
  child: Box(
    border: .all(type: .rounded, style: theme.border),
    titles: [BorderTitle(' 28 × 3 ', style: theme.muted)],
    child: OverflowBox(
      maxWidth: 48,
      child: Text(
        'a line wider than the box, cut off at its edges',
        style: theme.selection,
      ),
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| widget | OverflowBox, SizedOverflowBox, LimitedBox | OverflowBox |
| alignment | centerLeft, center, centerRight | center |

## FractionallySizedBox

A child a fraction of the room it is given.

API: [`FractionallySizedBox`](https://pub.dev/documentation/twk/latest/twk/FractionallySizedBox-class.html).

### Code

```dart
final theme = Theme.of(context);
return SizedBox(
  width: 40,
  height: 9,
  child: Box(
    border: .all(type: .rounded, style: theme.border),
    child: FractionallySizedBox(
      widthFactor: 0.5,
      heightFactor: 0.5,
      child: Box(
        style: theme.selection,
        child: const Center(child: Text('0.5 × 0.5')),
      ),
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| width factor | ¼, ½, ¾, 1 | ½ |
| height factor | ¼, ½, ¾, 1 | ½ |
| alignment | center, topLeft, bottomRight | center |
| room | 16 cells to 48 cells | 40 |

## IntrinsicWidth/Height

A child as wide or as tall as it would like to be: stretched items all as wide as the widest, boxes all as tall as the tallest.

### Code

```dart
final theme = Theme.of(context);
final menu = Column(
  crossAxisAlignment: .stretch,
  children: [
    for (final (i, label) in ['Open…', 'Save as…', 'Close window'].indexed)
      Box(
        style: i == 0 ? theme.selection : theme.surface,
        padding: const .x(1),
        child: Text(label),
      ),
  ],
);
final cards = Row(
  mainAxisSize: .min,
  crossAxisAlignment: .stretch,
  spacing: 1,
  children: [
    for (final text in ['one', 'three lines here'])
      SizedBox(
        width: 10,
        child: Box(
          border: .all(type: .rounded, style: theme.border),
          child: Text(text),
        ),
      ),
  ],
);
return SizedBox(
  width: 44,
  height: 7,
  child: Row(
    crossAxisAlignment: .start,
    spacing: 4,
    children: [
      IntrinsicWidth(child: menu),
      IntrinsicHeight(child: cards),
    ],
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| IntrinsicWidth | on, off | true |
| IntrinsicHeight | on, off | true |

## Row, Column, Flex

Children one after another along an axis, aligned along and across it.

API: [`Row`](https://pub.dev/documentation/twk/latest/twk/Row-class.html), [`Column`](https://pub.dev/documentation/twk/latest/twk/Column-class.html), [`Flex`](https://pub.dev/documentation/twk/latest/twk/Flex-class.html).

### Code

```dart
final theme = Theme.of(context);
// the text reversed too, as Badge has it: a Box gives its child its
// colours, not its attributes
Widget chip(String label, Style color, [EdgeInsets padding = const .x(1)]) {
  final reversed = color.merge(const .new(attrs: Attr.reverse));
  return Box(
    style: reversed,
    padding: padding,
    child: Text(label, style: reversed),
  );
}
return SizedBox(
  width: 44,
  height: 11,
  child: Box(
    border: .all(type: .rounded, style: theme.border),
    child: Row(
      mainAxisAlignment: .spaceBetween,
      spacing: 1,
      children: [
        chip('one', theme.primary),
        chip('two', theme.accent, const .all(1)),
        chip('three', theme.success),
      ],
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| direction | row, column | row |
| main axis | start, end, center, spaceBetween, spaceAround, spaceEvenly | spaceBetween |
| cross axis | start, end, center, stretch | center |
| spacing | 0, 1, 2 | 1 |
| main axis size | max, min | max |

## Expanded, Spacer

Children of a Row or Column that share the room the others leave by their flex factors: Expanded fills its share, a Flexible may take less, a Spacer is empty.

API: [`Expanded`](https://pub.dev/documentation/twk/latest/twk/Expanded-class.html), [`Spacer`](https://pub.dev/documentation/twk/latest/twk/Spacer-class.html).

### Code

```dart
final theme = Theme.of(context);
return SizedBox(
  width: 48,
  height: 3,
  child: Row(
    crossAxisAlignment: .stretch,
    children: [
      Expanded(
        child: Box(
          border: .all(type: .rounded, style: theme.accent),
          child: const Text('Expanded 1', wrap: .none),
        ),
      ),
      Flexible(
        child: Box(
          border: .all(type: .rounded, style: theme.border),
          child: const Text('Flexible'),
        ),
      ),
      const Spacer(),
      Box(
        border: .all(type: .rounded, style: theme.border),
        child: const Text('end'),
      ),
    ],
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| Expanded flex | 1, 2, 3 | 1 |
| Flexible fit | loose, tight | loose |
| width | 20 cells to 50 cells | 48 |

## Stack, Positioned

Children over one another, pinned to the edges or aligned.

API: [`Stack`](https://pub.dev/documentation/twk/latest/twk/Stack-class.html), [`Positioned`](https://pub.dev/documentation/twk/latest/twk/Positioned-class.html).

### Code

```dart
final theme = Theme.of(context);
return ConstrainedBox(
  // tight across, loose down: each fit lays the child out otherwise
  constraints: const BoxConstraints(
    minWidth: 38,
    maxWidth: 38,
    maxHeight: 9,
  ),
  child: Box(
    border: .all(type: .rounded, style: theme.border),
    child: Stack(
      alignment: .center,
      children: [
        // the room the others are placed in: the stack as big as it may be
        const SizedBox.expand(),
        Box(
          style: theme.selection,
          padding: const .x(1),
          child: const Text('not positioned'),
        ),
        const Positioned(right: 0, top: 0, child: Badge('top right')),
        Positioned(
          left: 0,
          bottom: 0,
          child: Text('bottom left', style: theme.muted),
        ),
      ],
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| alignment x | left, center, right | center |
| alignment y | top, center, bottom | center |
| fit | loose, expand, passthrough | loose |

## Transform

A child shown moved by whole cells, laid out where it was: Transform.translate, the one transform a terminal has.

API: [`Transform`](https://pub.dev/documentation/twk/latest/twk/Transform-class.html).

### Code

```dart
const _round = [
  (0, -2), (5, -2), (9, -1), (10, 0),
  (9, 1), (5, 2), (0, 2), (-5, 2),
  (-9, 1), (-10, 0), (-9, -1), (-5, -2),
];

var _step = 0;
late final Timer _timer;

@override
void initState() {
  super.initState();
  _timer = Timer.periodic(
    const Duration(milliseconds: 200),
    (_) => setState(() => _step++),
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
  return SizedBox(
    width: 32,
    height: 7,
    child: Box(
      border: .all(type: .rounded, style: theme.border),
      child: Transform.translate(
        offset: _round[_step % _round.length],
        child: Center(
          child: Box(
            style: theme.selection,
            padding: const .x(1),
            child: const Text('moved'),
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
| offset | round, fixed | round |
| dx | -12 cells to 12 cells | 6 |
| dy | -2 rows to 2 rows | 1 |

## Visibility, Offstage

A child hidden: Offstage keeps it laid out and running without painting it; Visibility takes its room away too, or keeps it.

API: [`Visibility`](https://pub.dev/documentation/twk/latest/twk/Visibility-class.html), [`Offstage`](https://pub.dev/documentation/twk/latest/twk/Offstage-class.html).

### Code

```dart
final theme = Theme.of(context);
return Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  children: [
    const Text('above the child'),
    Visibility(
      visible: false,
      child: Box(
        border: .all(type: .rounded, style: theme.border),
        padding: const .x(1),
        child: const Text('the child'),
      ),
    ),
    const Text('below the child'),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| widget | Visibility, Offstage | Visibility |
| hidden | on, off | true |
| keeps | nothing, state, size | nothing |
| replacement | on, off | false |

## ExpansionTile, Accordion

Sections that fold under their headers: Enter, Space or a click opens one, Right and Left open and close it; in an accordion one is open at a time, Up and Down go from header to header.

API: [`ExpansionTile`](https://pub.dev/documentation/twk/latest/twk/ExpansionTile-class.html), [`Accordion`](https://pub.dev/documentation/twk/latest/twk/Accordion-class.html).

### Code

```dart
var _verify = true;
var _did = '';

/// A section of [title] that holds [child], and says when it opens or
/// closes.
ExpansionTile _section(
  String title,
  String subtitle,
  Widget child, {
  bool open = false,
}) => ExpansionTile(
  title: Text(title),
  subtitle: Text(subtitle),
  initiallyExpanded: open,
  onExpansionChanged: (expanded) => setState(
    () => _did = '${expanded ? 'opened' : 'closed'} $title',
  ),
  child: child,
);

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  final sections = [
    _section(
      'General', 'Name and theme',
      const Text('Name: twk\nTheme: dark'),
      open: true,
    ),
    _section('Network', 'Proxy and timeouts', const Text('Proxy: none\nTimeout: 30 s')),
    _section(
      'Security', 'TLS and certificates',
      Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          const Text('TLS: 1.3'),
          Checkbox(
            value: _verify,
            label: 'verify certificates',
            onChanged: (value) => setState(() => _verify = value),
          ),
        ],
      ),
    ),
  ];
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      SizedBox(
        width: 40,
        child: Accordion(children: sections),
      ),
      Text.rich([
        Span('did: ', theme.muted),
        if (_did.isEmpty)
          Span('nothing', theme.muted)
        else
          Span(_did),
      ]),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| in an accordion | on, off | true |
| several open | on, off | false |
| subtitles | on, off | true |
| duration | 150 ms, 400 ms, none | 150 ms |

## Grid, GridPlacement

Children in the cells of tracks: fixed, a share of the rest, or as long as their content; a child may span several.

API: [`Grid`](https://pub.dev/documentation/twk/latest/twk/Grid-class.html), [`GridPlacement`](https://pub.dev/documentation/twk/latest/twk/GridPlacement-class.html).

### Code

```dart
final theme = Theme.of(context);
Widget cell(String label) => Box(
  border: .all(type: .rounded, style: theme.border),
  child: Text(label),
);
return SizedBox(
  width: 44,
  height: 12,
  child: Grid(
    columns: const [.fixed(12), .fr(1), .content()],
    rows: const [.content(), .fr(1), .content()],
    columnGap: 1,
    children: [
      GridPlacement(columnSpan: 3, child: cell('header · columnSpan: 3')),
      cell('fixed(12)'),
      cell('fr(1)'),
      cell('content()'),
      GridPlacement(
        row: 2,
        column: 1,
        columnSpan: 2,
        child: cell('columnSpan: 2'),
      ),
    ],
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| third column | .content(), .fixed(14), .fr(1) | .content() |
| column gap | 0, 1, 2 | 1 |
| row gap | 0, 1 | 0 |
| width | 32 cells to 50 cells | 44 |

## Wrap

Children in runs that go on in the next run where they would not fit: tags, buttons and key hints on a terminal that narrows.

API: [`Wrap`](https://pub.dev/documentation/twk/latest/twk/Wrap-class.html).

### Code

```dart
final theme = Theme.of(context);
return SizedBox(
  width: 36,
  height: 11,
  child: Box(
    border: .all(type: .rounded, style: theme.border),
    child: Wrap(
      crossAxisAlignment: .center,
      spacing: 1,
      children: [
        const Badge('dart'),
        const Badge('terminal', kind: .info),
        Box(
          border: .all(type: .rounded, style: theme.border),
          child: const Text('a box'),
        ),
        const Badge('twk', kind: .success),
        const Badge('日本語', kind: .warning),
        const Badge('layout'),
        const Badge('runs', kind: .info),
      ],
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| width | 20 cells to 48 cells | 36 |
| narrowing | on, off | false |
| direction | horizontal, vertical | horizontal |
| alignment | start, end, center, spaceBetween, spaceAround, spaceEvenly | start |
| run alignment | start, end, center, spaceBetween, spaceAround, spaceEvenly | start |
| cross axis | start, end, center | center |
| spacing | 0, 1, 2 | 1 |
| run spacing | 0, 1 | 0 |

## CustomPaint

Cells a CellPainter draws itself, under the child or over it, painted again when what it paints changes.

API: [`CustomPaint`](https://pub.dev/documentation/twk/latest/twk/CustomPaint-class.html).

### Code

```dart
final _phase = ValueNotifier(0);
late final Timer _timer;

@override
void initState() {
  super.initState();
  _timer = Timer.periodic(
    const Duration(milliseconds: 100),
    (_) => _phase.value++,
  );
}

@override
void dispose() {
  _timer.cancel();
  _phase.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return CustomPaint(
    painter: WavePainter(_phase, theme.primary),
    child: SizedBox(
      width: 36,
      height: 6,
      child: Center(
        child: Text(
          'cells of its own',
          style: theme.text.merge(const .new(attrs: Attr.bold)),
        ),
      ),
    ),
  );
}

/// Blocks as high as a wave 24 columns long, moved along by [phase]
/// with no widget built again.
final class WavePainter extends CellPainter {
  WavePainter(this.phase, this.style) : super(repaint: phase);

  final ValueNotifier<int> phase;
  final Style style;

  @override
  void paint(Canvas canvas, int width, int height) {
    final pen = style.penIn(canvas.styles);
    for (var x = 0; x < width; x++) {
      final u = (x + phase.value) % 24;
      final eighths = 4 + 3 * (u < 12 ? u : 24 - u);
      for (var row = 0; row < height; row++) {
        final left = eighths - 8 * row;
        if (left > 0) {
          canvas.text(x, height - 1 - row, ' ▁▂▃▄▅▆▇█'[min(left, 8)], pen);
        }
      }
    }
  }

  @override
  bool shouldRepaint(WavePainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.style != style;
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| painter | painter, foregroundPainter | painter |
| moving | on, off | true |
| style | primary, accent, success | primary |

## SplitView

Panes the mouse or the arrows resize by their dividers; Tab focuses one. The last one collapses.

API: [`SplitView`](https://pub.dev/documentation/twk/latest/twk/SplitView-class.html).

### Code

```dart
final _split = SplitController(fractions: [1, 2, 1]);

@override
void dispose() {
  _split.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  Widget pane(String title, String text) => Box(
    border: .all(type: .rounded, style: theme.border, merge: true),
    // no blanks around the title: a divider over the edge would
    // draw its line in them
    titles: [BorderTitle(title, style: theme.muted)],
    padding: const .only(left: 1),
    child: Text(text),
  );
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      // as tall as the room leaves it, at most 11
      Flexible(
        child: SizedBox(
          width: 48,
          height: 11,
          child: SplitView(
            controller: _split,
            shareEdges: true,
            style: theme.border,
            panes: [
              SplitPane(
                minSize: 8,
                child: pane(
                  'files',
                  'box.dart\nflex.dart\ngrid.dart\nwrap.dart',
                ),
              ),
              SplitPane(
                minSize: 8,
                child: pane(
                  'editor',
                  'Drag a divider, or Tab to one and press the arrows.',
                ),
              ),
              SplitPane(
                minSize: 8,
                collapsible: true,
                child: pane('outline', 'Drag its divider to the edge.'),
              ),
            ],
          ),
        ),
      ),
      ListenableBuilder(
        listenable: _split,
        builder: (context, _) {
          final fractions = _split.fractions.map((f) => f.toStringAsFixed(2));
          final collapsed = _split.collapsed;
          return Text.rich([
            Span('fractions: ', theme.muted),
            Span(fractions.join('  ')),
            if (collapsed.isNotEmpty) ...[
              Span('  collapsed: ', theme.muted),
              Span('$collapsed'),
            ],
          ]);
        },
      ),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| direction | horizontal, vertical | horizontal |
| share edges | on, off | true |
| dividers | single, rounded, double, heavy, ascii | single |

## DockArea

Panels in splits and tabs: a tab dragged onto a target of a group docks its panel there, and dropped elsewhere floats it; a window's title bar dragged onto one docks it again.

API: [`DockArea`](https://pub.dev/documentation/twk/latest/twk/DockArea-class.html).

### Code

```dart
final _dock = DockController(_docked());

static DockLayout _docked() => DockLayout(
  root: DockSplit(
    .horizontal,
    [
      DockTabs(['files', 'find']),
      DockTabs(['editor']),
    ],
    fractions: [1, 2],
  ),
  windows: const [DockWindow('log', left: 23, top: 4, width: 26, height: 6)],
);

@override
void dispose() {
  _dock.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    SizedBox(
      width: 50,
      height: 10,
      child: DockArea(
        controller: _dock,
        panels: const [
          DockPanel(
            id: 'files',
            title: 'Files',
            child: Padding(
              padding: .x(1),
              child: Text('Drag a tab onto a target to dock it there.'),
            ),
          ),
          DockPanel(
            id: 'find',
            title: 'Find',
            child: Padding(padding: .x(1), child: Text('Find in files.')),
          ),
          DockPanel(
            id: 'editor',
            title: 'Editor',
            child: Padding(padding: .x(1), child: _Clicks()),
          ),
          DockPanel(
            id: 'log',
            title: 'Log',
            child: Padding(
              padding: .x(1),
              child: Text('Drop a tab off the targets to float it.'),
            ),
          ),
        ],
      ),
    ),
    Button(
      'Dock them as they were',
      onPressed: () => _dock.layout = _docked(),
    ),
  ],
);

/// A count and a button that adds to it: kept as its panel moves.
final class _Clicks extends StatefulWidget {
  const _Clicks();

  @override
  State<_Clicks> createState() => _ClicksState();
}

final class _ClicksState extends State<_Clicks> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text.rich([Span('count: ', theme.muted), Span('$_count')]),
        Button('Add one', onPressed: () => setState(() => _count++)),
      ],
    );
  }
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| tab strip | on, off | true |
| window frame | by the theme, raised, bordered | by the theme |

## Scaffold

An app's frame: a header, a sidebar beside the body, a status bar and the key hints, each part a zone of the focus; the sidebar collapsed on a narrow screen and resized by a drag.

API: [`Scaffold`](https://pub.dev/documentation/twk/latest/twk/Scaffold-class.html).

### Code

```dart
final _controller = ScaffoldController(sidebarWidth: 14);
var _inbox = true;
var _archive = false;
var _notes = 3;

@override
void dispose() {
  _controller.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return SizedBox(
    width: 48,
    height: 12,
    child: Scaffold(
      controller: _controller,
      collapsedBelow: 40,
      resizableSidebar: true,
      header: const Text('notes'),
      sidebar: Padding(
        padding: const .all(1),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Checkbox(
              value: _inbox,
              label: 'inbox',
              onChanged: (v) => setState(() => _inbox = v),
            ),
            Checkbox(
              value: _archive,
              label: 'archive',
              onChanged: (v) => setState(() => _archive = v),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const .all(1),
        child: Column(
          crossAxisAlignment: .start,
          spacing: 1,
          children: [
            Button('New note', onPressed: () => setState(() => _notes++)),
            Text.rich([Span('notes: ', theme.muted), Span('$_notes')]),
          ],
        ),
      ),
      statusBar: StatusBar(
        left: Text('$_notes notes'),
        right: const Text('saved'),
      ),
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| width | 30 cells to 48 cells | 48 |
| sidebar side | left, right | left |
| resizable | on, off | true |
| key hints | on, off | true |
| header | on, off | true |
| status bar | on, off | true |
| collapsed below | none, 36, 40, 44 | 40 |
