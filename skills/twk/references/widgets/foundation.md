<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Foundation

Notifiers and listenables that widgets build on.

[All widgets](../widgets.md)

## ListenableBuilder

What is built again each time a listenable notifies; ValueListenableBuilder is given its value.

API: [`ListenableBuilder`](https://pub.dev/documentation/twk/latest/twk/ListenableBuilder-class.html).

### Code

```dart
final _count = ValueNotifier<int>(0);
late final Timer _timer;

@override
void initState() {
  super.initState();
  // one more each second
  _timer = Timer.periodic(
    const Duration(seconds: 1),
    (_) => _count.value++,
  );
}

@override
void dispose() {
  _timer.cancel();
  _count.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    Row(
      mainAxisSize: .min,
      spacing: 2,
      children: [
        Button('Count', onPressed: () => _count.value++),
        // notifies no one when it is 0 already
        Button('Reset', onPressed: () => _count.value = 0),
      ],
    ),
    ListenableBuilder(
      listenable: _count,
      builder: (context, _) => Text('ListenableBuilder: ${_count.value}'),
    ),
    ValueListenableBuilder(
      valueListenable: _count,
      builder: (context, value, _) => Text('ValueListenableBuilder: $value'),
    ),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| timer | on, off | true |

## FutureBuilder, StreamBuilder

What is built from the latest snapshot of a future or a stream: waiting, done, or each event.

API: [`FutureBuilder`](https://pub.dev/documentation/twk/latest/twk/FutureBuilder-class.html), [`StreamBuilder`](https://pub.dev/documentation/twk/latest/twk/StreamBuilder-class.html).

### Code

```dart
Future<String>? _load;
final Stream<int> _ticks = Stream.periodic(
  const Duration(seconds: 1),
  (i) => i + 1,
);

void _start() => setState(
  () => _load = Future.delayed(
    const Duration(seconds: 2),
    () => 'loaded',
  ),
);

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  Widget shown(Widget what, AsyncSnapshot<Object?> snapshot) => Row(
    mainAxisSize: .min,
    spacing: 1,
    children: [
      SizedBox(width: 26, child: what),
      Text(snapshot.connectionState.name, style: theme.muted),
    ],
  );
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      Button('Load', onPressed: _start),
      FutureBuilder<String>(
        future: _load,
        builder: (context, snapshot) => shown(
          switch (snapshot.connectionState) {
            ConnectionState.none => const Text('future: not started'),
            ConnectionState.waiting => Row(
              spacing: 1,
              children: [
                const Text('future:'),
                const Spinner(),
              ],
            ),
            _ when snapshot.hasError => Text(
              'future: ${snapshot.error}',
              style: theme.error,
            ),
            _ => Text('future: ${snapshot.data}', style: theme.success),
          },
          snapshot,
        ),
      ),
      StreamBuilder<int>(
        stream: _ticks,
        builder: (context, snapshot) =>
            shown(Text('stream: ${snapshot.data ?? 0} s'), snapshot),
      ),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| future | value, error | value |
| stream | endless, take(5) | endless |
