<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Scrolling

Lists, scroll views and scrollbars, built as they scroll into view.

[All widgets](../widgets.md)

## SingleChildScrollView

One child scrolled in the room it is given: Tab to it, then the arrows, PageUp and PageDown, or the wheel over it.

API: [`SingleChildScrollView`](https://pub.dev/documentation/twk/latest/twk/SingleChildScrollView-class.html).

### Code

```dart
const _paragraphs = [
  'A scroll view lays its child out as long as it likes along the axis, and '
      'shows a window of it.',
  'The arrows move it a cell, PageUp and PageDown a window, Home and End to '
      'the ends.',
  'A notch of the wheel over it scrolls three cells.',
  'Scrolled while all of it is on the screen, it has the terminal move the '
      'rows that stay.',
  'A Column in it is as tall as its children, whatever its mainAxisSize.',
  'Its controller reads the offset and moves it; the line under the box '
      'listens to it.',
];

final _controller = ScrollController();
final _keys = [for (final _ in _paragraphs) GlobalKey()];
var _shown = -1;

@override
void dispose() {
  _controller.dispose();
  super.dispose();
}

/// Lights the next paragraph and scrolls the least that shows it.
void _showNext() {
  setState(() => _shown = (_shown + 1) % _paragraphs.length);
  _controller.ensureVisible(_keys[_shown].currentContext!);
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  final paragraphs = [
    for (final (i, text) in _paragraphs.indexed)
      Text(
        text,
        key: _keys[i],
        style: i == _shown ? theme.primary : const Style(),
      ),
  ];
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      SizedBox(
        width: 34,
        height: 8,
        // the border primary while the focus is in it
        child: FocusBuilder(
          builder: (context, hasFocus, child) => Box(
            border: .all(
              type: .rounded,
              style: hasFocus ? theme.primary : theme.border,
            ),
            child: child,
          ),
          child: ScrollConfiguration(
            behavior: const ScrollBehavior(),
            child: SingleChildScrollView(
              controller: _controller,
              child: Column(
                crossAxisAlignment: .start,
                spacing: 1,
                children: paragraphs,
              ),
            ),
          ),
        ),
      ),
      Button('next paragraph', onPressed: _showNext),
      ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Text.rich([
          Span('offset ', theme.muted),
          Span('${_controller.offset}'),
          Span(' of ', theme.muted),
          Span('${_controller.position.maxScrollExtent}'),
        ]),
      ),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| direction | vertical, horizontal | vertical |

## Scrollable

What scrolls a viewport: here one of the page's own, a ruler that tells the scrollable how long it is as it is laid out.

API: [`Scrollable`](https://pub.dev/documentation/twk/latest/twk/Scrollable-class.html).

### Code

```dart
final _controller = ScrollController();

@override
void dispose() {
  _controller.dispose();
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
      SizedBox(
        width: 34,
        height: 8,
        // the border primary while the focus is in it
        child: FocusBuilder(
          builder: (context, hasFocus, child) => Box(
            border: .all(
              type: .rounded,
              style: hasFocus ? theme.primary : theme.border,
            ),
            child: child,
          ),
          child: Scrollable(
            controller: _controller,
            viewportBuilder: (context, position) => ListenableBuilder(
              listenable: position,
              builder: (_, _) =>
                  _Ruler(position, offset: position.pixels, length: 100),
            ),
          ),
        ),
      ),
      ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Text.rich([
          Span('offset ', theme.muted),
          Span('${_controller.offset}'),
          Span(' of ', theme.muted),
          Span('${_controller.position.maxScrollExtent}'),
        ]),
      ),
    ],
  );
}

/// A viewport of [length] numbered rows from [offset] on, which tells
/// [position] its extents as it is laid out.
final class _Ruler extends LeafRenderObjectWidget {
  const _Ruler(this.position, {required this.offset, required this.length});

  final ScrollPosition position;
  final int offset;
  final int length;

  @override
  _RenderRuler createRenderObject(BuildContext context) =>
      _RenderRuler(position, offset, length);

  @override
  void updateRenderObject(BuildContext context, _RenderRuler renderObject) =>
      renderObject
        ..position = position
        ..offset = offset
        ..length = length;
}

final class _RenderRuler extends RenderObject {
  _RenderRuler(this._position, this._offset, this._length);

  ScrollPosition _position;
  int _offset;
  int _length;

  ScrollPosition get position => _position;
  set position(ScrollPosition value) {
    if (value != _position) {
      _position = value;
      markNeedsLayout();
    }
  }

  int get offset => _offset;
  set offset(int value) {
    if (value != _offset) {
      _offset = value;
      markNeedsPaint();
    }
  }

  int get length => _length;
  set length(int value) {
    if (value != _length) {
      _length = value;
      markNeedsLayout();
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxWidth;
    height = c.maxHeight;
    _position.applyExtents(height, _length);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final pen = canvas.styles.pen(const Pen());
    final tick = canvas.styles.pen(const Pen(attrs: Attr.dim));
    for (var y = 0; y < height && _offset + y < _length; y++) {
      final row = _offset + y + 1;
      final x = canvas.text(0, y, '${row.toString().padLeft(3)} ', pen);
      canvas.text(
        x,
        y,
        row % 10 == 0 ? '├─────────' : (row % 5 == 0 ? '├────' : '├─'),
        tick,
      );
    }
  }
}
```

## ListView

Items built as they come into view, however many there are; the wheel and the keys scroll it. Separated, reversed as a chat, or kept on what it shows as items come before it.

API: [`ListView`](https://pub.dev/documentation/twk/latest/twk/ListView-class.html).

### Code

```dart
const _count = 100;

final _list = ListController();

@override
void dispose() {
  _list.dispose();
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
      SizedBox(
        width: 34,
        height: 8,
        // the border primary while the focus is in it
        child: FocusBuilder(
          builder: (context, hasFocus, child) => Box(
            border: .all(
              type: .rounded,
              style: hasFocus ? theme.primary : theme.border,
            ),
            child: child,
          ),
          child: ListView.builder(
            itemCount: _count,
            controller: _list,
            itemBuilder: (context, i) => Text('item ${i + 1}'),
          ),
        ),
      ),
      Row(
        mainAxisSize: .min,
        spacing: 1,
        children: [
          Button('top', onPressed: () => _list.jumpTo(0)),
          // the least move that shows it
          Button('item 40', onPressed: () => _list.ensureIndexVisible(39)),
          // at the top, built or not: where the estimate puts it
          Button('middle', onPressed: () => _list.jumpToIndex(_count ~/ 2)),
        ],
      ),
      ListenableBuilder(
        listenable: _list,
        builder: (context, _) => Text.rich([
          Span('offset ', theme.muted),
          Span('${_list.offset}'),
          Span(' of ', theme.muted),
          Span('${_list.position.maxScrollExtent}'),
        ]),
      ),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| items | 100, 10 000, 1 000 000, growing, chat, feed | 100 |
| heights | one row, different | one row |
| separated | on, off | false |
| stuck by | stickToBottom, stickToEnd | stickToBottom |

## LogView

Lines that keep coming, followed at the bottom: levels, a filter and a search, a count of the new lines while it is scrolled up.

API: [`LogView`](https://pub.dev/documentation/twk/latest/twk/LogView-class.html).

### Code

```dart
final _log = LogController();
var _lines = 30;
late final Timer _timer;

@override
void initState() {
  super.initState();
  // the lines logged before it opens
  for (var i = 0; i < 30; i++) {
    _add(i);
  }
  // then one every 400 ms
  _timer = Timer.periodic(
    const Duration(milliseconds: 400),
    (_) => _add(_lines++),
  );
}

@override
void dispose() {
  _timer.cancel();
  _log.dispose();
  super.dispose();
}

/// Line [i]: what it says, at what level, and when.
void _add(int i) {
  final (level, text) = switch (i) {
    _ when i % 13 == 5 => (LogLevel.error, 'POST /api/orders 500 upstream timeout after 5000 ms'),
    _ when i % 7 == 3 => (
      LogLevel.warning,
      'slow query: SELECT * FROM items took ${300 + i * 29 % 900} ms',
    ),
    _ when i % 5 == 1 => (LogLevel.debug, 'cache hit items/${i * 37 % 500}'),
    _ => (LogLevel.info, 'GET /api/items/${i * 37 % 500} 200 ${3 + i * 13 % 90} ms'),
  };
  _log.add(
    text,
    level: level,
    time: DateTime(2026, 10, 19, 12).add(Duration(milliseconds: 400 * i)),
  );
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return SizedBox(
    width: 50,
    height: 12,
    // the border primary while the focus is in it
    child: FocusBuilder(
      builder: (context, hasFocus, child) => Box(
        border: .all(
          type: .rounded,
          style: hasFocus ? theme.primary : theme.border,
        ),
        child: child,
      ),
      child: LogView(controller: _log),
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| level | debug, info, warning, error | debug |
| filter | none, GET, slow | none |
| search | none, items, timeout | none |
| time | on, off | true |
| show level | on, off | true |
| wrap | on, off | true |
| live | on, off | true |
| scrollbar | always, onScroll, never | always |

## Scrollbar

A bar by the scrollable below it, its thumb where the window is; the thumb dragged and the track clicked scroll it.

API: [`Scrollbar`](https://pub.dev/documentation/twk/latest/twk/Scrollbar-class.html).

### Code

```dart
@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return SizedBox(
    width: 34,
    height: 10,
    // the border primary while the focus is in it
    child: FocusBuilder(
      builder: (context, hasFocus, child) => Box(
        border: .all(
          type: .rounded,
          style: hasFocus ? theme.primary : theme.border,
        ),
        child: child,
      ),
      child: Scrollbar(
        child: ListView.builder(
          itemCount: 200,
          itemBuilder: (context, i) => Text('row ${i + 1}'),
        ),
      ),
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| visibility | always, onScroll, never | always |
| bars | vertical, horizontal, both | vertical |
| style | muted, border, primary, accent | muted |
| slim | on, off | false |
| track | faint, border, muted | faint |
