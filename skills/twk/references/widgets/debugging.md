<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Debugging

The log console, the frame overlay, the repaint rainbow and repaint boundaries.

[All widgets](../widgets.md)

## Console

Log records listed over the app, newest last; the app has one of its own, which Ctrl+G then c opens.

API: [`Console`](https://pub.dev/documentation/twk/latest/twk/Console-class.html).

### Code

```dart
final _sink = LogSink();
late final _console = ConsoleController(_sink)..open();
static const _traffic = [
  (LogLevel.info, 'GET /api/items 200 in 12 ms'),
  (LogLevel.debug, 'cache hit: items?page=2'),
  (LogLevel.info, 'GET /api/user/42 200 in 8 ms'),
  (LogLevel.debug, 'pool: 3 of 8 connections busy'),
  (LogLevel.warning, 'slow query: 412 ms on orders'),
  (LogLevel.info, 'POST /api/orders 201 in 31 ms'),
  (LogLevel.debug, 'cache miss: user:42:prefs'),
  (LogLevel.error, 'upstream timed out after 5 s'),
  (LogLevel.info, 'GET /api/items 200 in 15 ms'),
  (LogLevel.warning, 'retrying upload (2 of 3)'),
];
var _i = 0;
late final Timer _timer;

@override
void initState() {
  super.initState();
  // a small server's traffic, a record every 700 ms
  _timer = Timer.periodic(
    const Duration(milliseconds: 700),
    (_) {
      final (level, message) = _traffic[_i++ % _traffic.length];
      _log(level, message);
    },
  );
}

void _log(LogLevel level, String message) =>
    _sink.add(LogRecord(DateTime.now(), level, message));

@override
void dispose() {
  _timer.cancel();
  _console.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return SizedBox(
    width: 48,
    height: 10,
    child: KeyBindings(
      {
        'up': _console.selectPrevious,
        'down': _console.selectNext,
        'end': _console.scrollToEnd,
      },
      hints: const {'up': 'select', 'down': 'select', 'end': 'newest'},
      child: Console(
        controller: _console,
        rows: 6,
        child: Column(
          crossAxisAlignment: .start,
          spacing: 1,
          children: [
            Row(
              spacing: 1,
              children: [
                Button('Info', onPressed: () => _log(.info, 'all is well')),
                Button(
                  'Warn',
                  onPressed: () => _log(.warning, 'disk nearly full'),
                ),
                Button('Fail', onPressed: () => _log(.error, 'could not save')),
                ListenableBuilder(
                  listenable: _console,
                  builder: (context, _) => Button(
                    _console.isOpen ? 'Close' : 'Open',
                    onPressed: _console.toggle,
                  ),
                ),
              ],
            ),
            Text('The app, under its console.', style: theme.muted),
          ],
        ),
      ),
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| level | debug, info, warning, error | debug |
| rows | 4, 6, 8 | 6 |
| traffic | on, off | true |
| open on error | on, off | false |

## FrameOverlay

Each frame's numbers over the app: the time its build, layout, paint and write took and the bytes it wrote; Ctrl+G then o.

### Code

```dart
import 'dart:async';

import 'package:twk/twk.dart';

// TWK_DEBUG=overlay turns it on in any app as well
void main() => runApp(const Sync());

/// A small app whose parts change at rates of their own: the spinner each
/// 80 ms, the bar each 300 ms, the sparkline each second. Space pauses
/// the copy.
final class Sync extends StatefulWidget {
  const Sync({super.key});

  @override
  State<Sync> createState() => _SyncState();
}

final class _SyncState extends State<Sync> {
  static const _loads = <double>[3, 5, 4, 6, 8, 7, 5, 6, 9, 7, 4, 5];

  var _done = 0;
  var _samples = 0;
  var _paused = false;
  late final Timer _copy;
  late final Timer _sample;

  @override
  void initState() {
    super.initState();
    // the debug keys, Ctrl+G then o showing and hiding the frame
    // overlay
    AppBinding.of(context).debug
      ..keys = true
      ..overlay = true;
    _copy = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!_paused) {
        setState(() => _done = (_done + 1) % 101);
      }
    });
    _sample = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _samples++),
    );
  }

  @override
  void dispose() {
    _copy.cancel();
    _sample.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyBindings(
      {'space': () => setState(() => _paused = !_paused)},
      hints: const {'space': 'pause'},
      child: Padding(
        padding: const .all(1),
        child: Column(
          crossAxisAlignment: .start,
          spacing: 1,
          children: [
            Row(
              spacing: 1,
              children: [
                if (!_paused) const Spinner(),
                Text(_paused ? 'paused' : 'syncing'),
              ],
            ),
            Row(
              spacing: 1,
              children: [
                Text('copy', style: theme.muted),
                SizedBox(width: 16, child: ProgressBar(value: _done / 100)),
              ],
            ),
            Row(
              spacing: 1,
              children: [
                Text('load', style: theme.muted),
                SizedBox(
                  width: 16,
                  child: Sparkline(
                    data: [
                      for (var i = 0; i < 16; i++)
                        _loads[(_samples + i) % _loads.length],
                    ],
                    style: theme.info,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| overlay | on, off | true |

## Repaint rainbow

Each repaint boundary tinted a new colour when it paints, and relayouts marked, to see what a change redraws; Ctrl+G then r, and l.

### Code

```dart
import 'dart:async';

import 'package:twk/twk.dart';

// TWK_DEBUG=rainbow turns it on in any app as well
void main() => runApp(const Sync());

/// A small app whose parts change at rates of their own: the spinner each
/// 80 ms, the bar each 300 ms, the sparkline each second. Space pauses
/// the copy.
final class Sync extends StatefulWidget {
  const Sync({super.key});

  @override
  State<Sync> createState() => _SyncState();
}

final class _SyncState extends State<Sync> {
  static const _loads = <double>[3, 5, 4, 6, 8, 7, 5, 6, 9, 7, 4, 5];

  var _done = 0;
  var _samples = 0;
  var _paused = false;
  late final Timer _copy;
  late final Timer _sample;

  @override
  void initState() {
    super.initState();
    // the debug keys, Ctrl+G then r turning the rainbow on and off,
    // and l the relayout highlight
    AppBinding.of(context).debug
      ..keys = true
      ..rainbow = true;
    _copy = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!_paused) {
        setState(() => _done = (_done + 1) % 101);
      }
    });
    _sample = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _samples++),
    );
  }

  @override
  void dispose() {
    _copy.cancel();
    _sample.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyBindings(
      {'space': () => setState(() => _paused = !_paused)},
      hints: const {'space': 'pause'},
      child: Padding(
        padding: const .all(1),
        child: Column(
          crossAxisAlignment: .start,
          spacing: 1,
          children: [
            Row(
              spacing: 1,
              children: [
                if (!_paused) const Spinner(),
                Text(_paused ? 'paused' : 'syncing'),
              ],
            ),
            Row(
              spacing: 1,
              children: [
                Text('copy', style: theme.muted),
                SizedBox(width: 16, child: ProgressBar(value: _done / 100)),
              ],
            ),
            Row(
              spacing: 1,
              children: [
                Text('load', style: theme.muted),
                SizedBox(
                  width: 16,
                  child: Sparkline(
                    data: [
                      for (var i = 0; i < 16; i++)
                        _loads[(_samples + i) % _loads.length],
                    ],
                    style: theme.info,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| rainbow | on, off | true |
| relayout highlight | on, off | false |

## RepaintBoundary

A subtree painted on its own layer: what changes in it is painted again without what is around it, and the other way round.

API: [`RepaintBoundary`](https://pub.dev/documentation/twk/latest/twk/RepaintBoundary-class.html).

### Code

```dart
import 'dart:async';

import 'package:twk/twk.dart';

void main() => runApp(const Paints());

/// Dots across its cells, counting how often it paints them.
final class _Dots extends CellPainter {
  _Dots(this.style);

  final Style style;
  var paints = 0;

  @override
  void paint(Canvas canvas, int width, int height) {
    paints++;
    canvas.text(0, 0, '·' * width, style.penIn(canvas.styles));
  }

  @override
  bool shouldRepaint(_Dots oldDelegate) => false;
}

/// A dot in the column [at] says, painted again as it moves.
final class _Marker extends CellPainter {
  _Marker(this.at, this.style) : super(repaint: at);

  final ValueNotifier<int> at;
  final Style style;

  @override
  void paint(Canvas canvas, int width, int height) =>
      canvas.text(at.value, 0, '●', style.penIn(canvas.styles));

  @override
  bool shouldRepaint(_Marker oldDelegate) => false;
}

final class Paints extends StatefulWidget {
  const Paints({super.key});

  @override
  State<Paints> createState() => _PaintsState();
}

final class _PaintsState extends State<Paints> {
  final _at = ValueNotifier(0);
  late final Timer _timer;
  late final _dots = _Dots(Theme.of(context).border);

  @override
  void initState() {
    super.initState();
    // the marker a cell on: its painter repaints, no widget is built
    _timer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _at.value = (_at.value + 1) % 20,
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    _at.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // painted on its own, over what is under it: the dots are not
    final marker = RepaintBoundary(
      child: CustomPaint(painter: _Marker(_at, theme.primary)),
    );
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 1,
      children: [
        CustomPaint(
          painter: _dots,
          child: SizedBox(width: 20, height: 1, child: marker),
        ),
        // the count on its own too: in a box of its size, a new one
        // lays nothing else out; in a boundary, repaints nothing else
        RepaintBoundary(
          child: SizedBox(
            width: 20,
            height: 1,
            child: ListenableBuilder(
              listenable: _at,
              builder: (context, _) => Text.rich([
                Span('painted: ', theme.muted),
                Span('${_dots.paints}'),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| RepaintBoundary | on, off | true |
| a step every | 300 ms, 1 s | 300 ms |
