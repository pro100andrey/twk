<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Data

Tables, trees, charts, gauges, sparklines and calendars.

[All widgets](../widgets.md)

## Sparkline

A series of values as bars an eighth of a cell fine, the newest on the right.

API: [`Sparkline`](https://pub.dev/documentation/twk/latest/twk/Sparkline-class.html).

### Code

```dart
var _i = 48;
var _data = [for (var i = 0; i < 48; i++) 4 + 3 * sin(i / 4)];

// a value every 150 ms, the oldest dropped
late final Timer _timer;

@override
void initState() {
  super.initState();
  _timer = Timer.periodic(
    const Duration(milliseconds: 150),
    (_) => setState(() {
      final i = _i++;
      _data = [..._data.skip(1), 4 + 3 * sin(i / 4)];
    }),
  );
}

@override
void dispose() {
  _timer.cancel();
  super.dispose();
}

@override
Widget build(BuildContext context) => SizedBox(
  width: 48,
  height: 4,
  child: Sparkline(data: _data, style: Theme.of(context).info),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| data | wave, ramp, steps, noise | wave |
| rows | 1, 2, 4 | 4 |
| max | largest, 10 | largest |
| live | on, off | true |
| style | info, primary, accent, success, warning | info |

## Gauge, LineGauge

How much of something there is: a block filled to a ratio, or a line.

API: [`Gauge`](https://pub.dev/documentation/twk/latest/twk/Gauge-class.html), [`LineGauge`](https://pub.dev/documentation/twk/latest/twk/LineGauge-class.html).

### Code

```dart
var _ratio = 0.0;

// from empty to full in 7 s, full for 2 s, and again
late final Timer _timer;

@override
void initState() {
  super.initState();
  _timer = Timer.periodic(
    const Duration(milliseconds: 25),
    (timer) {
      final ms = timer.tick * 25 % 9000;
      setState(() => _ratio = ms < 7000 ? ms / 7000 : 1);
    },
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
  final percent = '${(_ratio * 100).round()}%';
  return SizedBox(
    width: 40,
    child: Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 1,
      children: [
        SizedBox(
          height: 3,
          child: Gauge(
            ratio: _ratio,
            label: percent,
            style: theme.primary.merge(.new(bg: theme.surface.bg)),
            labelStyle: const .new(attrs: Attr.bold),
          ),
        ),
        LineGauge(
          ratio: _ratio,
          label: 'used $percent',
          type: .heavy,
          filledStyle: _ratio > .9
              ? theme.error
              : _ratio > .75
              ? theme.warning
              : theme.success,
          unfilledStyle: theme.border,
        ),
      ],
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| live | on, off | true |
| ratio | 0% to 100% | 75 |
| line | single, heavy, double, ascii | heavy |
| label | own, percent, none | own |
| style | primary, accent, success, warning, info | primary |
| segmented | on, off | false |

## BarChart

Bars in groups, up or across, their values on them and their labels under them.

API: [`BarChart`](https://pub.dev/documentation/twk/latest/twk/BarChart-class.html).

### Code

```dart
const _base = [4.0, 7.0, 6.0, 9.0, 3.0, 5.0];
var _t = 0.0; // seconds

late final Timer _timer;

@override
void initState() {
  super.initState();
  _timer = Timer.periodic(
    const Duration(milliseconds: 100),
    (_) => setState(() => _t += .1),
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
  final values = [
    for (final (k, v) in _base.indexed) v + sin(_t * 1.3 + k * 1.7),
  ];
  Bar bar(int k, String label, [Style style = const Style()]) =>
      Bar(values[k], label: label, text: '${values[k].round()}', style: style);
  return SizedBox(
    width: 25,
    height: 10,
    child: BarChart(
      direction: .vertical,
      barWidth: 3,
      groupGap: 2,
      max: 10,
      barStyle: theme.primary,
      valueStyle: const .new(attrs: Attr.bold),
      labelStyle: theme.muted,
      groups: [
        for (final (g, label) in ['Q1', 'Q2', 'Q3'].indexed)
          BarGroup(
            [bar(2 * g, 'a'), bar(2 * g + 1, 'b', theme.accent)],
            label: label,
          ),
      ],
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| direction | vertical, horizontal | vertical |
| bar width | 1, 2, 3 | 3 |
| bars | grouped, single | grouped |
| live | on, off | true |

## Chart

Datasets of points on two axes, as lines or dots, with a legend.

API: [`Chart`](https://pub.dev/documentation/twk/latest/twk/Chart-class.html).

### Code

```dart
var _phase = 0.0;

// the waves run to the right
late final Timer _timer;

@override
void initState() {
  super.initState();
  _timer = Timer.periodic(
    const Duration(milliseconds: 50),
    (_) => setState(() => _phase += .1),
  );
}

@override
void dispose() {
  _timer.cancel();
  super.dispose();
}

/// [f] at 61 points from 0 to 2π.
List<(double, double)> _wave(double Function(num) f) => [
  for (var i = 0; i <= 60; i++) (i * pi / 30, f(i * pi / 30 - _phase)),
];

@override
Widget build(BuildContext context) => SizedBox(
  width: 50,
  height: 12,
  child: Chart(
    marker: .braille,
    legendPosition: .topRight,
    style: Theme.of(context).muted,
    datasets: [
      Dataset(data: _wave(sin), name: 'sin', type: .line, color: .cyan),
      Dataset(data: _wave(cos), name: 'cos', type: .line, color: .yellow),
    ],
    xAxis: const ChartAxis(
      bounds: (0, 2 * pi),
      title: 'x',
      labels: ['0', 'π', '2π'],
    ),
    yAxis: const ChartAxis(bounds: (-1, 1), labels: ['-1', '0', '1']),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| graph | scatter, line | line |
| marker | braille, halfBlock, quadrant, sextant, octant, block, dot, bar, custom | braille |
| legend | topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight, none | topRight |
| live | on, off | true |

## DotCanvas

Shapes drawn finer than the cells, in data coordinates, with labels over them.

API: [`DotCanvas`](https://pub.dev/documentation/twk/latest/twk/DotCanvas-class.html).

### Code

```dart
var _t = 0.0; // seconds

late final Timer _timer;

@override
void initState() {
  super.initState();
  _timer = Timer.periodic(
    const Duration(milliseconds: 50),
    (_) => setState(() => _t += .05),
  );
}

@override
void dispose() {
  _timer.cancel();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final hand = pi / 2 - 2 * pi * _t / 6; // a turn in 6 s
  final wave = [
    for (var i = 0; i <= 24; i++)
      (24.5 + i / 2, 10.5 + 5 * sin(i / 3 - 4 * _t)),
  ];
  return SizedBox(
    width: 40,
    height: 12,
    child: DotCanvas(
      xBounds: (0, 40),
      yBounds: (0, 24),
      marker: .braille,
      draw: (dots) => dots
        ..draw(const Shape.circle(12, 12, 9, color: .cyan))
        ..draw(
          Shape.line(
            12,
            12,
            12 + 8 * cos(hand),
            12 + 8 * sin(hand),
            color: .magenta,
          ),
        )
        ..draw(const Shape.rectangle(24, 3, 13, 15, color: .yellow))
        ..draw(Shape.polyline(wave, color: .green))
        ..layer()
        ..label(11.5, 22.6, '12')
        ..label(28, 20, 'dots'),
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| marker | braille, halfBlock, quadrant, sextant, octant, block, dot, bar, custom | braille |
| live | on, off | true |

## Calendar

A month to pick a day of: the arrows move the cursor, PageUp and PageDown a month, Enter or a click picks the day.

API: [`Calendar`](https://pub.dev/documentation/twk/latest/twk/Calendar-class.html).

### Code

```dart
DateTime? _selected;

@override
Widget build(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    Calendar(
      today: DateTime(2026, 10, 19),
      onSelected: (date) => setState(() => _selected = date),
    ),
    Text.rich([
      Span('selected: ', Theme.of(context).muted),
      switch (_selected) {
        null => Span('nothing', Theme.of(context).muted),
        final date => Span(date.toIso8601String().substring(0, 10)),
      },
    ]),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| first day | monday, sunday | monday |
| week numbers | on, off | false |
| outside days | on, off | false |
| marked days | on, off | false |

## Heatmap, ActivityHeatmap

Values over a grid as shades or colors, its rows and columns labelled; counts by day over weeks, a column a week. The arrows move a cursor, its tooltip saying what is there.

API: [`Heatmap`](https://pub.dev/documentation/twk/latest/twk/Heatmap-class.html), [`ActivityHeatmap`](https://pub.dev/documentation/twk/latest/twk/ActivityHeatmap-class.html).

### Code

```dart
/// The commits of each day of the last 20 weeks: fewer at
/// the weekends.
static final _commits = {
  for (var i = 0; i < 140; i++)
    DateTime(2026, 10, 19 - i): _count(i),
};

static int _count(int i) {
  final weekend = DateTime(2026, 10, 19 - i).weekday > DateTime.friday;
  return (_noise(i) * (weekend ? 3 : 9)).floor();
}

/// A value from 0 to 1 that looks random and is the same for the same [i].
static double _noise(int i) {
  final s = sin(i * 91.345 + 3.1) * 43758.5453;
  return s - s.floorToDouble();
}

var _selected = '';

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      ActivityHeatmap(
        counts: _commits,
        end: DateTime(2026, 10, 19),
        weeks: 20,
        showLegend: true,
        onSelected: (day) => setState(
          () => _selected = day.toIso8601String().substring(0, 10),
        ),
      ),
      Text.rich([
        Span('selected: ', theme.muted),
        if (_selected.isEmpty)
          Span('nothing', theme.muted)
        else
          Span(_selected),
      ]),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| widget | ActivityHeatmap, Heatmap | ActivityHeatmap |
| first day | monday, sunday | monday |
| scale | shades, colors | shades |
| legend | on, off | true |
| cell width | 2 columns, 1 column | 2 columns |

## Table

Rows in columns that size by their content or a share, sorted by a click on a title; the arrows select a row or a cell.

API: [`Table`](https://pub.dev/documentation/twk/latest/twk/Table-class.html).

### Code

```dart
final _controller = TableController(selectedKey: 'box.dart');

@override
void dispose() {
  _controller.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) => SizedBox(
  width: 50,
  height: 7,
  child: Table<(String, int, double)>(
    rows: _files,
    rowKey: (row) => row.$1,
    controller: _controller,
    selection: .row,
    border: .single,
    columnGap: 3,
    onActivated: (row) =>
        showToast(context: context, message: 'Activated ${row.$1}'),
    columns: [
      TableColumn(
        title: 'name',
        cell: (row) => TableCell(row.$1),
        compare: (a, b) => a.$1.compareTo(b.$1),
      ),
      TableColumn(
        title: 'lines',
        align: .right,
        cell: (row) => TableCell.rich(['${row.$2}'.bold]),
        compare: (a, b) => a.$2.compareTo(b.$2),
      ),
      TableColumn(
        title: 'covered',
        width: const .fr(1),
        cell: (row) => TableCell.widget(_Covered(row.$3)),
      ),
    ],
  ),
);

const _files = [
  ('box.dart', 412, .9),
  ('text.dart', 230, .75),
  ('flex.dart', 388, .6),
  ('grid.dart', 520, .4),
  ('stack.dart', 145, 1.0),
];

/// How much of a file its tests cover, as a line in the colours of its
/// row: the selection's and the cursor's, which the table gives a
/// widget cell's text (DefaultTextStyle).
final class _Covered extends StatelessWidget {
  const _Covered(this.ratio);

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LineGauge(
      ratio: ratio,
      label: '${(ratio * 100).round()}%'.padLeft(4),
      type: .heavy,
      style: DefaultTextStyle.of(context),
      filledStyle: theme.primary,
      unfilledStyle: theme.border,
    );
  }
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| selection | none, row, cell | row |
| border | none, single, rounded, double, heavy, ascii | single |
| header | on, off | true |
| rows | 5, 10 000 | 5 |

## DescriptionList

Terms and their values, the values in a column of their own, aligned group by group; a long value wraps under itself, and on a narrow screen each goes under its term.

API: [`DescriptionList`](https://pub.dev/documentation/twk/latest/twk/DescriptionList-class.html).

### Code

```dart
final theme = Theme.of(context);
return SizedBox(
  width: 44,
  child: DescriptionList(
    items: [
      DescriptionItem(
        'Status',
        Text.rich([
          Span('● ', theme.success),
          const Span('Running (healthy)'),
        ]),
      ),
      DescriptionItem.text('IP Address', '192.168.1.42'),
      DescriptionItem.text('Uptime', '3 days, 4 hours'),
      DescriptionItem.text('Image', 'twk/server:0.1.0'),
      const DescriptionItem.group('Limits'),
      DescriptionItem.text('CPU', '2 cores'),
      const DescriptionItem('Memory', ProgressBar(value: 0.25)),
      DescriptionItem.text(
        'Restart policy',
        'unless stopped, 5 times at most in a minute',
      ),
    ],
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| width | 20 cells to 60 cells | 44 |
| terms | left, center, right | left |
| separator | colon, none | colon |
| groups | on, off | true |

## TreeView

Nodes under their parents: the arrows move and expand, Enter or a click on the expander opens one; test/ loads a while.

API: [`TreeView`](https://pub.dev/documentation/twk/latest/twk/TreeView-class.html).

### Code

```dart
final _controller = TreeController(
  expanded: ['lib', 'lib/src'],
  selectedKey: 'lib/src/table.dart',
);

@override
Widget build(BuildContext context) => SizedBox(
  width: 40,
  height: 12,
  child: TreeView<String>(
    roots: const ['lib', 'test', 'README.md', 'pubspec.yaml'],
    controller: _controller,
    hasChildren: (path) => !path.contains('.'),
    children: (path) => switch (path) {
      'lib' => const ['lib/src', 'lib/twk.dart'],
      'lib/src' => const [
        'lib/src/box.dart',
        'lib/src/flex.dart',
        'lib/src/table.dart',
        'lib/src/text.dart',
      ],
      'test' => Future.delayed(
        const Duration(seconds: 1),
        () => const ['test/box_test.dart', 'test/table_test.dart'],
      ),
      _ => const [],
    },
    label: (context, entry) => Text(entry.node.split('/').last),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| guides | on, off | true |
| separate roots | on, off | false |
| max indent | none, 2 | none |
| test/ | loads, fails | loads |

## TreeTable

A tree in the first column of a table: rows that expand and collapse, sorted within their parents, selected one or many at a time.

API: [`TreeTable`](https://pub.dev/documentation/twk/latest/twk/TreeTable-class.html).

### Code

```dart
final _controller = TreeController(
  expanded: ['lib', 'lib/src'],
  selectedKey: 'lib/src/table.dart',
);

@override
void dispose() {
  _controller.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) => SizedBox(
  width: 40,
  height: 12,
  child: TreeTable<String>(
    roots: const ['lib', 'test', 'README.md', 'pubspec.yaml'],
    controller: _controller,
    selection: .row,
    border: .single,
    columnGap: 3,
    hasChildren: (path) => !path.contains('.'),
    children: (path) => _children[path] ?? const [],
    columns: [
      TableColumn(
        title: 'name',
        width: const .fr(1),
        cell: (path) => TableCell(path.split('/').last),
        compare: (a, b) => a.compareTo(b),
      ),
      TableColumn(
        title: 'lines',
        align: .right,
        cell: (path) => TableCell('${_lines(path)}'),
        compare: (a, b) => _lines(a).compareTo(_lines(b)),
      ),
    ],
  ),
);

const _children = {
  'lib': ['lib/src', 'lib/twk.dart'],
  'lib/src': [
    'lib/src/box.dart',
    'lib/src/flex.dart',
    'lib/src/table.dart',
    'lib/src/text.dart',
  ],
  'test': ['test/box_test.dart', 'test/table_test.dart'],
};

const _sizes = {
  'lib/src/box.dart': 412,
  'lib/src/flex.dart': 388,
  'lib/src/table.dart': 960,
  'lib/src/text.dart': 230,
  'lib/twk.dart': 48,
  'test/box_test.dart': 310,
  'test/table_test.dart': 655,
  'README.md': 120,
  'pubspec.yaml': 22,
};

/// A file's lines, or those of the files under a directory.
int _lines(String path) =>
    _sizes[path] ??
    (_children[path] ?? const []).fold(0, (n, p) => n + _lines(p));
```

### Options

| option | values | starts at |
| --- | --- | --- |
| selection | none, row, cell | row |
| border | none, single, rounded, double, heavy, ascii | single |
| guides | on, off | true |

## DirectoryTree

The files under a directory as a tree for a side panel: each directory listed as it is opened and again as it changes, what .gitignore ignores left out.

API: [`DirectoryTree`](https://pub.dev/documentation/twk/latest/twk/DirectoryTree-class.html).

### Code

```dart
/// A project of files as many bytes as they are big; a directory that
/// cannot be read, and what the .gitignore leaves out.
static final _files = InMemoryFileSystem(
  const ['/home/user/twk/'],
  contents: {
    '/home/user/twk/.gitignore': 'build/\n*.log\n',
    for (final (path, bytes) in const [
      ('lib/twk.dart', 312),
      ('lib/src/box.dart', 4210),
      ('lib/src/flex.dart', 9874),
      ('lib/src/table.dart', 18130),
      ('lib/src/text.dart', 2305),
      ('test/box_test.dart', 3102),
      ('test/table_test.dart', 6550),
      ('build/twk.js', 120400),
      ('.dart_tool/package_config.json', 2210),
      ('debug.log', 51200),
      ('README.md', 1204),
      ('pubspec.yaml', 220),
    ])
      '/home/user/twk/$path': 'x' * bytes,
  },
  unreadable: const ['/home/user/twk/private'],
);

final _tree = DirectoryTreeController()
  ..expand('/home/user/twk/lib')
  ..expand('/home/user/twk/lib/src');
var _opened = '';

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      SizedBox(
        width: 36,
        height: 12,
        child: DirectoryTree(
          root: '/home/user/twk',
          fileSystem: _files,
          controller: _tree,
          onOpened: (path) => setState(
            () => _opened = path.substring('/home/user/twk/'.length),
          ),
        ),
      ),
      Text.rich([
        Span('opened: ', theme.muted),
        if (_opened.isEmpty)
          Span('nothing', theme.muted)
        else
          Span(_opened),
      ]),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| hidden files | on, off | false |
| .gitignore | on, off | true |
| sizes | on, off | false |
| guides | on, off | false |
| icons | none, glyphs | none |

## TaskList

Tasks and how far they have got: pending, running with a spinner and the time it has run, done, failed or skipped; their steps below.

API: [`TaskList`](https://pub.dev/documentation/twk/latest/twk/TaskList-class.html).

### Code

```dart
// what runs: 0 fetch, 1 and 2 compile, 3 test, 4 deploy, 5 done
var _step = 0;

@override
void initState() {
  super.initState();
  unawaited(_run());
}

/// The build, again and again: each step a while, then the next.
Future<void> _run() async {
  const ms = [1400, 1200, 1600, 2400, 1200, 3000];
  while (mounted) {
    for (var step = 0; step < ms.length && mounted; step++) {
      setState(() => _step = step);
      await Future<void>.delayed(Duration(milliseconds: ms[step]));
    }
  }
}

List<TaskItem> get _tasks {
  // a task that runs from step [from] to step [to]
  TaskItemStatus at(int from, int to) =>
      _step < from ? .pending : (_step < to ? .running : .done);
  return [
    TaskItem('Fetch dependencies', status: at(0, 1)),
    TaskItem(
      'Compile',
      status: at(1, 3),
      children: [
        TaskItem('lib/core.dart', status: at(1, 2)),
        TaskItem('lib/widgets.dart', status: at(2, 3)),
      ],
    ),
    TaskItem('Run the tests', status: at(3, 4)),
    TaskItem('Deploy', status: at(4, 5)),
  ];
}

@override
Widget build(BuildContext context) => SizedBox(
  width: 40,
  child: TaskList(
    tasks: _tasks,
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| step | live, fetch, compile, test, deploy, done | live |
| failed | on, off | false |
| elapsed | on, off | true |
| spinner | dots, line, arc | dots |
