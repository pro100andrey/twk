<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Mouse

Clicks, drags, hovers and the wheel, and where the mouse is let through.

[All widgets](../widgets.md)

## GestureDetector

Taps, double taps, long presses and drags of the mouse over a widget.

API: [`GestureDetector`](https://pub.dev/documentation/twk/latest/twk/GestureDetector-class.html).

### Code

```dart
var _taps = 0, _doubleTaps = 0, _longPresses = 0;
var _dragged = (0, 0);
String? _last;
CellOffset? _from, _at; // the drag: where it started, where it is

void _saw(String what, [CellOffset? at]) =>
    _last = at == null ? what : '$what at ${at.dx}, ${at.dy}';

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      GestureDetector(
        onTap: () => setState(() {
          _taps++;
          _saw('tap');
        }),
        onDoubleTap: () => setState(() {
          _doubleTaps++;
          _saw('double tap');
        }),
        onLongPress: () => setState(() {
          _longPresses++;
          _saw('long press');
        }),
        onPanStart: (drag) => setState(() => _from = drag.localPosition),
        onPanUpdate: (drag) => setState(() {
          _dragged = (
            _dragged.$1 + drag.delta.dx,
            _dragged.$2 + drag.delta.dy,
          );
          _at = drag.localPosition;
          _saw('drag', drag.localPosition);
        }),
        onPanEnd: (drag) => setState(() {
          _from = _at = null;
          _saw('drag ended', drag.localPosition);
        }),
        child: SizedBox(
          width: 36,
          height: 7,
          child: Box(
            border: .all(type: .rounded, style: theme.border),
            child: Box(
              style: theme.surface,
              child: Stack(
                children: [
                  Center(
                    child: Text(
                      _last ?? 'tap, hold or drag me',
                      style: _last == null ? theme.muted : const Style(),
                    ),
                  ),
                  // the detector's cells, less the border
                  if (_from case (dx: final x, dy: final y))
                    Positioned(
                      left: x - 1,
                      top: y - 1,
                      child: Text('○', style: theme.muted),
                    ),
                  if (_at case (dx: final x, dy: final y))
                    Positioned(
                      left: x - 1,
                      top: y - 1,
                      child: Text('●', style: theme.primary),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          Text.rich([
            Span('taps ', theme.muted),
            Span('$_taps'),
            Span(', double ', theme.muted),
            Span('$_doubleTaps'),
            Span(', long ', theme.muted),
            Span('$_longPresses'),
          ]),
          Text.rich([
            Span('dragged ', theme.muted),
            Span('${_dragged.$1} across, ${_dragged.$2} down'),
          ]),
        ],
      ),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| double tap | on, off | true |
| long press after | 500 ms, 1 s | 500 ms |
| buttons | left, right, left, middle, right | left |

## Listener, MouseRegion

The mouse events over a widget as they come: presses, releases, motion and the wheel; the mouse coming in and going out, the pointer a hand over it where the terminal shows that.

API: [`Listener`](https://pub.dev/documentation/twk/latest/twk/Listener-class.html), [`MouseRegion`](https://pub.dev/documentation/twk/latest/twk/MouseRegion-class.html).

### Code

```dart
var _over = false;
final _events = <String>[];

// what came, the newest first
void _saw(String what, PointerEvent event) => setState(() {
  _events.insert(0, '$what at ${event.x}, ${event.y}');
  if (_events.length > 4) _events.removeLast();
});

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      MouseRegion(
        onEnter: (event) {
          _over = true;
          _saw('enter', event);
        },
        onExit: (event) {
          _over = false;
          _saw('exit', event);
        },
        cursor: .pointer,
        child: Listener(
          onPointerDown: (event) => _saw('press of button ${event.button}', event),
          onPointerUp: (event) => _saw('release', event),
          onPointerHover: (event) => _saw('move', event),
          onPointerMove: (event) => _saw('drag', event),
          onScroll: (event) => _saw(event.kind.name, event),
          behavior: .opaque,
          child: SizedBox(
            width: 36,
            height: 7,
            child: Box(
              border: .all(
                type: .rounded,
                style: _over ? theme.primary : theme.border,
              ),
              child: Box(
                style: _over ? theme.selection : theme.surface,
                child: Center(
                  child: Text(_over ? 'the mouse is over me' : 'move over me'),
                ),
              ),
            ),
          ),
        ),
      ),
      Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          if (_events.isEmpty) Text('nothing yet', style: theme.muted),
          for (final (i, event) in _events.indexed)
            Text(event, style: i == 0 ? const Style() : theme.muted),
        ],
      ),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| cursor | pointer, crosshair, text, grab, move, notAllowed, wait, none | pointer |

## IgnorePointer, AbsorbPointer

A subtree the mouse passes by: IgnorePointer lets it through to what is under it, AbsorbPointer stops it there.

API: [`IgnorePointer`](https://pub.dev/documentation/twk/latest/twk/IgnorePointer-class.html), [`AbsorbPointer`](https://pub.dev/documentation/twk/latest/twk/AbsorbPointer-class.html).

### Code

```dart
var _over = false;
var _heard = '';

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      Stack(
        children: [
          GestureDetector(
            onTap: () => setState(() => _heard = 'the backdrop'),
            behavior: .opaque,
            child: SizedBox(
              width: 36,
              height: 7,
              child: Box(
                border: .all(type: .rounded, style: theme.border),
                titles: [BorderTitle(' backdrop ', style: theme.muted)],
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: IgnorePointer(
                child: MouseRegion(
                  onEnter: (_) => setState(() => _over = true),
                  onExit: (_) => setState(() => _over = false),
                  child: GestureDetector(
                    onTap: () => setState(() => _heard = 'the button'),
                    child: Box(
                      border: .all(
                        type: .rounded,
                        style: _over ? theme.primary : theme.border,
                      ),
                      padding: const .x(2),
                      child: const Text('click me'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      Text.rich([
        Span('heard: ', theme.muted),
        if (_heard.isEmpty) Span('nothing', theme.muted) else Span(_heard),
      ]),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| around the button | none, IgnorePointer, AbsorbPointer | IgnorePointer |

## SelectionArea

Text selected with the mouse as in a terminal, and copied to the clipboard: drag over it, or click twice or three times; a painted Selectable is selected in too, and a drag past its edge scrolls it.

API: [`SelectionArea`](https://pub.dev/documentation/twk/latest/twk/SelectionArea-class.html).

### Code

```dart
var _copied = '';

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return SizedBox(
    width: 44,
    child: Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 1,
      children: [
        SelectionArea(
          onCopy: (text) => setState(() => _copied = text),
          child: const Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            spacing: 1,
            children: [
              Text(
                'An app that reads the mouse keeps the terminal from '
                'selecting its text, so it selects the text itself.',
              ),
              Text('A drag goes on from one paragraph to the next.'),
            ],
          ),
        ),
        // what was copied, in the width the label leaves
        Row(
          crossAxisAlignment: .start,
          spacing: 1,
          children: [
            Text('copied:', style: theme.muted),
            Expanded(
              child: Text(
                _copied.isEmpty ? 'nothing' : _copied.replaceAll('\n', ' '),
                style: _copied.isEmpty ? theme.muted : const Style(),
                maxLines: 2,
                overflow: .ellipsis,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| selected in | two Texts, a painted log | two Texts |
| copy on release | on, off | true |
| style | the theme's, reverse | the theme's |

## Draggable, DragTarget

Data dragged from a widget with the mouse and dropped on another that accepts it.

API: [`Draggable`](https://pub.dev/documentation/twk/latest/twk/Draggable-class.html), [`DragTarget`](https://pub.dev/documentation/twk/latest/twk/DragTarget-class.html).

### Code

```dart
const _red = {'apple', 'cherry'};
const _colors = {
  'apple': Color.red,
  'banana': Color.yellow,
  'cherry': Color.red,
  'grape': Color.magenta,
};

final _in = {
  'bowl': ['apple', 'banana', 'cherry', 'grape'],
  'basket': <String>[],
  'red only': <String>[],
};
String? _status;

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  const empty = {
    'bowl': 'empty',
    'basket': 'drop here',
    'red only': 'drop here',
  };
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      Row(
        mainAxisSize: .min,
        spacing: 2,
        children: [
          for (final MapEntry(key: name, value: fruits) in _in.entries)
            DragTarget<String>(
              onWillAcceptWithDetails: (drag) =>
                  name != 'red only' || _red.contains(drag.data),
              onAcceptWithDetails: (drop) => setState(() {
                // dropped back on its own box, it stays where it is
                if (!fruits.contains(drop.data)) {
                  for (final list in _in.values) {
                    list.remove(drop.data);
                  }
                  fruits.add(drop.data);
                }
                _status = '${drop.data} → $name';
              }),
              builder: (context, candidate, rejected) {
                final over = candidate != null || rejected != null;
                final style = candidate != null
                    ? theme.primary
                    : rejected != null
                    ? theme.error
                    : theme.border;
                return SizedBox(
                  width: 15,
                  height: 6,
                  child: Box(
                    border: .all(type: .rounded, style: style),
                    titles: [
                      BorderTitle(
                        ' $name ',
                        style: over ? style.merge(bold) : theme.muted,
                      ),
                    ],
                    padding: const .x(1),
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        if (fruits.isEmpty && !over)
                          Text(empty[name]!, style: theme.muted),
                        for (final fruit in fruits)
                          _draggable(fruit, name, theme),
                        if (candidate != null && !fruits.contains(candidate))
                          Text('+ $candidate', style: theme.primary),
                        if (rejected != null)
                          Text('✗ red only', style: theme.error),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      Text.rich([
        Span('dropped: ', theme.muted),
        Span(
          _status ?? 'nothing',
          _status == null ? theme.muted : const Style(),
        ),
      ]),
    ],
  );
}

/// [fruit] in the box [from], dragged with the mouse: the pointer a
/// hand over it, a closed one while it is dragged, no-drop over a box
/// that refuses it (Draggable's pointer shapes).
Widget _draggable(String fruit, String from, ThemeData theme) {
  Widget label([Style style = const Style()]) =>
      Text.rich(['● '.fg(_colors[fruit]!), Span(fruit)], style: style);
  return Draggable<String>(
    data: fruit,
    // what follows the mouse: a chip on the surface, with a shadow
    feedback: Shadow(
      shadow: const BoxShadow(dx: 1),
      child: Box(
        style: theme.surface,
        padding: const .x(1),
        child: label(theme.text.merge(bold)),
      ),
    ),
    childWhenDragging: Text('● $fruit', style: theme.muted),
    onDragCanceled: () => setState(() => _status = '$fruit, back to the $from'),
    child: label(),
  );
}

const bold = Style(attrs: Attr.bold);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| child when dragging | on, off | true |
