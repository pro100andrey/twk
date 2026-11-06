<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Framework

Stateful and inherited widgets, builders, keys and the element tree.

[All widgets](../widgets.md)

## LayoutBuilder

What is built by the constraints it is laid out within: side by side when wide, one under another when narrow.

API: [`LayoutBuilder`](https://pub.dev/documentation/twk/latest/twk/LayoutBuilder-class.html).

### Code

```dart
final theme = Theme.of(context);
return SizedBox(
  width: 40,
  height: 8,
  // a render object widget: its builder runs in the layout, with the
  // constraints the SizedBox gives, and again when they change
  child: LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 30;
      final panes = [
        for (final name in const ['one', 'two'])
          Expanded(
            child: Box(
              border: .all(type: .rounded, style: theme.border),
              titles: [BorderTitle(' $name ')],
              // what each pane is given in turn
              child: LayoutBuilder(
                builder: (context, constraints) => Center(
                  child: Text(
                    describeConstraints(constraints),
                    style: theme.muted,
                  ),
                ),
              ),
            ),
          ),
      ];
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          Text.rich([
            Span('${describeConstraints(constraints)}: '),
            Span(wide ? 'wide' : 'narrow', theme.primary),
          ]),
          Expanded(
            child: wide
                ? Row(crossAxisAlignment: .stretch, children: panes)
                : Column(crossAxisAlignment: .stretch, children: panes),
          ),
        ],
      );
    },
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| width | 12 cells to 50 cells | 40 |
| wide from | 24, 30, 36 | 30 |

## NotificationListener

The notifications that bubble up to it from below, such as those of a list as it scrolls: the wheel over it, or Tab to it and the arrows.

API: [`NotificationListener`](https://pub.dev/documentation/twk/latest/twk/NotificationListener-class.html).

### Code

```dart
/// What became of a notification on its way up the tree.
final class _Sent {
  _Sent(this.notification);

  final ScrollNotification notification;

  // what the inner and the outer listener did with it
  var inner = 'past';
  String? _outer;

  String get outer => _outer ?? (inner == 'stops' ? '–' : 'past');
  set outer(String what) => _outer = what;
}

final _trace = <_Sent>[];
String? _heard;

// the list's, so that its box shows where the focus is
final _list = FocusNode();

@override
void dispose() {
  _list.dispose();
  super.dispose();
}

// nearest the list: hears each one first, and lets it go on up
bool _onSent(ScrollNotification notification) {
  setState(() => _trace.add(_Sent(notification)));
  return false;
}

bool _onInner(ScrollUpdateNotification notification) {
  _trace.last.inner = 'heard';
  return false; // lets it go on up
}

bool _onOuter(ScrollNotification notification) {
  final ScrollMetrics(:pixels, :maxScrollExtent) =
      notification.metrics;
  setState(() {
    _trace.last.outer = 'heard';
    _heard = switch (notification) {
      ScrollUpdateNotification(:final scrollDelta) =>
        'scrolled $scrollDelta to $pixels of $maxScrollExtent',
      OverscrollNotification(:final overscroll) =>
        'overscrolled $overscroll at $pixels of $maxScrollExtent',
      _ => '$notification',
    };
  });
  return false;
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return SizedBox(
    width: 50,
    child: Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 1,
      children: [
        Row(
          crossAxisAlignment: .start,
          spacing: 2,
          children: [
            SizedBox(
              width: 16,
              height: 8,
              // proxy widgets: they draw nothing, and hear what bubbles up
              child: NotificationListener<ScrollNotification>(
                onNotification: _onOuter,
                child: NotificationListener<ScrollUpdateNotification>(
                  onNotification: _onInner,
                  child: ListenableBuilder(
                    listenable: _list,
                    builder: (context, list) => Box(
                      border: .all(
                        type: .rounded,
                        style: _list.hasFocus ? theme.primary : theme.border,
                      ),
                      padding: const .x(1),
                      child: list,
                    ),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onSent,
                      child: ListView.builder(
                        focusNode: _list,
                        itemCount: 100,
                        itemBuilder: (context, i) => Text('item ${i + 1}'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _Trace([..._trace.reversed.take(4)].reversed),
            ),
          ],
        ),
        Text.rich([
          Span('heard: ', theme.muted),
          switch (_heard) {
            null => Span('nothing', theme.muted),
            final heard => Span(heard),
          },
        ]),
      ],
    ),
  );
}

/// The notifications sent up, newest last: their kind, how far, and
/// what the inner and the outer listener did with them.
final class _Trace extends StatelessWidget {
  const _Trace(this.sent);

  final Iterable<_Sent> sent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Style mark(String what) => switch (what) {
      'heard' => theme.success,
      'stops' => theme.warning,
      _ => theme.muted,
    };
    String signed(int n) => (n > 0 ? '+$n' : '$n').padLeft(3);
    return SizedBox(
      height: 8,
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Text('             Δ  inner  outer', style: theme.muted),
          if (sent.isEmpty) Text('nothing yet', style: theme.muted),
          for (final s in sent)
            Text.rich([
              Span(switch (s.notification) {
                ScrollUpdateNotification(:final scrollDelta) =>
                  'update     ${signed(scrollDelta)}',
                OverscrollNotification(:final overscroll) =>
                  'overscroll ${signed(overscroll)}',
                _ => '',
              }),
              Span('  ${s.inner.padRight(7)}', mark(s.inner)),
              Span(s.outer, mark(s.outer)),
            ]),
          const Spacer(),
          Text.rich([
            Span('inner ', theme.muted),
            const Span('ScrollUpdateNotification'),
          ]),
          Text.rich([
            Span('outer ', theme.muted),
            const Span('ScrollNotification'),
          ]),
        ],
      ),
    );
  }
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| outer hears | Scroll, ScrollUpdate, Overscroll | Scroll |
| inner stops them | on, off | false |

## Slot, SlotScope

Places the app names that plugins fill with the entries of a SlotRegistry: Tab to a plugin, then Space puts its entry in the status bar or takes it out.

API: [`Slot`](https://pub.dev/documentation/twk/latest/twk/Slot-class.html), [`SlotScope`](https://pub.dev/documentation/twk/latest/twk/SlotScope-class.html).

### Code

```dart
/// A status bar item: its name muted, then its value.
static Widget _item(BuildContext context, String name, String value) =>
    Text.rich([Span('$name ', Theme.of(context).muted), Span(value)]);

/// What the plugins put in the slots named 'status', in order.
static final _plugins = [
  SlotEntry(
    slot: 'status',
    id: 'git',
    builder: (context) => _item(context, 'git', 'main'),
  ),
  SlotEntry(
    slot: 'status',
    id: 'lint',
    order: 1,
    builder: (context) => _item(context, 'lint', '0 problems'),
  ),
  SlotEntry(
    slot: 'status',
    id: 'words',
    order: 2,
    builder: (context) => _item(context, 'words', '120'),
  ),
];

final _registry = SlotRegistry()
  ..register(_plugins[0])
  ..register(_plugins[2]);

void _turn(SlotEntry plugin, {required bool on}) => setState(() {
  if (on) {
    _registry.register(plugin);
  } else {
    _registry.unregister(plugin.slot, plugin.id);
  }
});

@override
void dispose() {
  _registry.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  // an InheritedWidget: the Slots below find the registry through it
  return SlotScope(
    registry: _registry,
    child: Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 1,
      children: [
        Row(
          mainAxisSize: .min,
          spacing: 2,
          children: [
            for (final plugin in _plugins)
              Checkbox(
                value: _registry.entriesOf('status').contains(plugin),
                onChanged: (on) => _turn(plugin, on: on),
                label: plugin.id,
              ),
          ],
        ),
        SizedBox(
          width: 44,
          child: Box(
            border: .all(type: .rounded, style: theme.border),
            titles: const [BorderTitle(' status ')],
            padding: const .x(1),
            // built again when the entries of 'status' change, and then only
            child: Slot(
              'status',
              layout: (context, children) => Row(spacing: 2, children: children),
              placeholder: Text('no plugins', style: theme.muted),
            ),
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
| lint order | -1, first, 1, between, 3, last | 1, between |
| placeholder | on, off | true |
