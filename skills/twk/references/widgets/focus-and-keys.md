<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Focus and keys

The focus, moved by Tab and the mouse, and the keys bound where it is.

[All widgets](../widgets.md)

## Focus, FocusScope

Nodes the keys go to: Tab moves the focus from one to the next, a click takes it; in a scope Tab goes round its nodes, and Tab into it focuses the one it had last.

API: [`Focus`](https://pub.dev/documentation/twk/latest/twk/Focus-class.html), [`FocusScope`](https://pub.dev/documentation/twk/latest/twk/FocusScope-class.html).

### Code

```dart
final _nodes = [
  for (final label in ['one', 'two', 'three', 'four'])
    FocusNode(debugLabel: label),
];
final _scope = FocusScopeNode(debugLabel: 'scope');

@override
void dispose() {
  for (final node in _nodes) {
    node.dispose();
  }
  _scope.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  final [one, two, three, four] = _nodes;
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      Row(
        mainAxisSize: .min,
        spacing: 1,
        children: [
          _Focusable(one),
          _Focusable(two),
          ListenableBuilder(
            listenable: _scope,
            builder: (context, _) {
              final inside = _scope.hasFocus;
              return Box(
                border: .all(
                  type: .rounded,
                  style: inside ? theme.primary : theme.border,
                ),
                titles: [
                  BorderTitle(
                    ' FocusScope ',
                    style: inside ? theme.primary : theme.muted,
                  ),
                ],
                child: FocusScope(
                  node: _scope,
                  child: Row(
                    mainAxisSize: .min,
                    children: [_Focusable(three), _Focusable(four)],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      ListenableBuilder(
        listenable: Listenable.merge(_nodes),
        builder: (context, _) {
          final focused = [
            for (final node in _nodes)
              if (node.hasPrimaryFocus) node.debugLabel!,
          ];
          return Text.rich([
            Span('focus: ', theme.muted),
            if (focused.isEmpty)
              Span('none', theme.muted)
            else
              Span(focused.first, theme.primary.merge(bold)),
          ]);
        },
      ),
    ],
  );
}

/// [node] in a box that takes the focus, by Tab or a click.
final class _Focusable extends StatelessWidget {
  const _Focusable(this.node);

  final FocusNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: node.requestFocus,
      child: Focus(
        focusNode: node,
        child: ListenableBuilder(
          listenable: node,
          builder: (context, _) => Box(
            border: .all(
              type: node.hasFocus ? .heavy : .rounded,
              style: node.hasFocus ? theme.primary : theme.border,
            ),
            padding: const .x(1),
            child: Text(
              node.debugLabel!,
              style: node.hasFocus ? bold : const Style(),
            ),
          ),
        ),
      ),
    );
  }
}

const bold = Style(attrs: Attr.bold);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| FocusScope | on, off | true |
| node two | focusable, skips Tab, unfocusable | focusable |

## ActiveItem

The item a focused list's keys act on: the terminal's hidden cursor rests on it, which iTerm2's cursor guide marks and macOS zoom, a screen reader or a braille display follows.

API: [`ActiveItem`](https://pub.dev/documentation/twk/latest/twk/ActiveItem-class.html).

### Code

```dart
static const _fruits = ['apple', 'banana', 'cherry', 'damson', 'elder'];

var _cursor = 0;

void _move(int by) =>
    setState(() => _cursor = (_cursor + by).clamp(0, _fruits.length - 1));

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return KeyBindings(
    {'up': () => _move(-1), 'down': () => _move(1)},
    child: Focus(
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          for (var i = 0; i < _fruits.length; i++)
            // the hidden cursor on the cursor's row
            ActiveItem(
              active: i == _cursor,
              child: Text(
                i == _cursor ? '› ${_fruits[i]}' : '  ${_fruits[i]}',
                style: i == _cursor ? theme.selection : const Style(),
              ),
            ),
        ],
      ),
    ),
  );
}
```

## ExcludeFocus

A subtree Tab passes by: its nodes take no focus while it excludes them, and give it up when it starts to.

API: [`ExcludeFocus`](https://pub.dev/documentation/twk/latest/twk/ExcludeFocus-class.html).

### Code

```dart
final _nodes = [
  for (final label in ['one', 'two', 'three', 'four'])
    FocusNode(debugLabel: label),
];

@override
void dispose() {
  for (final node in _nodes) {
    node.dispose();
  }
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  final [one, two, three, four] = _nodes;
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      Row(
        mainAxisSize: .min,
        spacing: 1,
        children: [
          _Focusable(one),
          ListenableBuilder(
            listenable: Listenable.merge([two, three]),
            builder: (context, _) {
              final inside = two.hasFocus || three.hasFocus;
              return Box(
                border: .all(
                  type: .rounded,
                  style: inside ? theme.primary : theme.border,
                ),
                titles: [
                  BorderTitle(
                    ' ExcludeFocus ',
                    style: inside ? theme.primary : theme.muted,
                  ),
                ],
                child: ExcludeFocus(
                  excluding: true,
                  child: Row(
                    mainAxisSize: .min,
                    children: [
                      _Focusable(two, muted: true),
                      _Focusable(three, muted: true),
                    ],
                  ),
                ),
              );
            },
          ),
          _Focusable(four),
        ],
      ),
      ListenableBuilder(
        listenable: Listenable.merge(_nodes),
        builder: (context, _) {
          final focused = [
            for (final node in _nodes)
              if (node.hasPrimaryFocus) node.debugLabel!,
          ];
          return Text.rich([
            Span('focus: ', theme.muted),
            if (focused.isEmpty)
              Span('none', theme.muted)
            else
              Span(focused.first, theme.primary.merge(bold)),
          ]);
        },
      ),
    ],
  );
}

/// [node] in a box that takes the focus, by Tab or a click; its label
/// [muted] while it cannot.
final class _Focusable extends StatelessWidget {
  const _Focusable(this.node, {this.muted = false});

  final FocusNode node;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => node.requestFocus(),
      child: Focus(
        focusNode: node,
        child: ListenableBuilder(
          listenable: node,
          builder: (context, _) => Box(
            border: .all(
              type: node.hasFocus ? .heavy : .rounded,
              style: node.hasFocus ? theme.primary : theme.border,
            ),
            padding: const .x(1),
            child: Text(
              node.debugLabel!,
              style: muted
                  ? theme.muted
                  : (node.hasFocus ? bold : const Style()),
            ),
          ),
        ),
      ),
    );
  }
}

const bold = Style(attrs: Attr.bold);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| excluding | on, off | true |

## KeyBindings, LeaderKey

Keys and sequences bound to callbacks while the focus is below them: Tab to the box, then +, -, g g or the leader , and r.

API: [`KeyBindings`](https://pub.dev/documentation/twk/latest/twk/KeyBindings-class.html), [`LeaderKey`](https://pub.dev/documentation/twk/latest/twk/LeaderKey-class.html).

### Code

```dart
final _node = FocusNode(debugLabel: 'focus me');
var _count = 0;

void _add(int n) => setState(() => _count += n);

void _reset() => setState(() => _count = 0);

@override
void dispose() {
  _node.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return LeaderKey(
    ',',
    child: KeyBindings(
      {
        '+': () => _add(1),
        '-': () => _add(-1),
        'g g': _reset,
        'leader r': _reset,
      },
      hints: const {
        '+': 'more',
        '-': 'less',
        'g g': 'reset',
        'leader r': 'reset',
      },
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 1,
        children: [
          Row(
            mainAxisSize: .min,
            spacing: 2,
            children: [
              _Focusable(_node),
              Text.rich([Span('count: ', theme.muted), Span('$_count')]),
            ],
          ),
          const KeyHintsBar(),
        ],
      ),
    ),
  );
}

/// [node] in a box that takes the focus, by Tab or a click.
final class _Focusable extends StatelessWidget {
  const _Focusable(this.node);

  final FocusNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: node.requestFocus,
      child: Focus(
        focusNode: node,
        child: ListenableBuilder(
          listenable: node,
          builder: (context, _) => Box(
            border: .all(
              type: node.hasFocus ? .heavy : .rounded,
              style: node.hasFocus ? theme.primary : theme.border,
            ),
            padding: const .x(1),
            child: Text(
              node.debugLabel!,
              style: node.hasFocus ? bold : const Style(),
            ),
          ),
        ),
      ),
    );
  }
}

const bold = Style(attrs: Attr.bold);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| leader | ,, space, \ | , |
| sequence timeout | 1 s, none | 1 s |
| unmatched keys | drop, replay | drop |

## Shortcuts, Actions

Keys bound to intents, which the nearest action for them does: Tab to the box, then Up or Down; a key whose action is off passes on.

API: [`Shortcuts`](https://pub.dev/documentation/twk/latest/twk/Shortcuts-class.html), [`Actions`](https://pub.dev/documentation/twk/latest/twk/Actions-class.html).

### Code

```dart
/// Steps up a count.
final class _Up extends Intent {
  const _Up();
}

/// Steps down a count.
final class _Down extends Intent {
  const _Down();
}

final _node = FocusNode(debugLabel: 'focus me');
var _count = 0;
var _did = '';

void _step(int n, String did) => setState(() {
  _count += n;
  _did = did;
});

void _passed(String did) => setState(() => _did = did);

@override
void dispose() {
  _node.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  // the keys no enabled action takes come here
  return KeyBindings(
    {
      'up': () => _passed('↑ _Up → passed on to the KeyBindings'),
      'down': () => _passed('↓ _Down → passed on to the KeyBindings'),
    },
    hints: const {'up': 'passed on', 'down': 'passed on'},
    child: Actions(
      actions: {
        _Up: CallbackAction<_Up>(
          onInvoke: (_) => _step(1, '↑ _Up → its action stepped up'),
        ),
        _Down: CallbackAction<_Down>(
          onInvoke: (_) => _step(-1, '↓ _Down → its action stepped down'),
        ),
      },
      child: Shortcuts(
        shortcuts: const {'up': _Up(), 'down': _Down()},
        hints: const {'up': 'step up', 'down': 'step down'},
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          spacing: 1,
          children: [
            Row(
              mainAxisSize: .min,
              spacing: 2,
              children: [
                _Focusable(_node),
                Text.rich([Span('count: ', theme.muted), Span('$_count')]),
              ],
            ),
            KeyHintsBar(
              keyLabel: (key) => switch ('$key') {
                'up' => '↑',
                'down' => '↓',
                final name => name,
              },
            ),
            Text.rich([
              Span('did: ', theme.muted),
              if (_did.isEmpty) Span('nothing', theme.muted) else Span(_did),
            ]),
          ],
        ),
      ),
    ),
  );
}

/// [node] in a box that takes the focus, by Tab or a click.
final class _Focusable extends StatelessWidget {
  const _Focusable(this.node);

  final FocusNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: node.requestFocus,
      child: Focus(
        focusNode: node,
        child: ListenableBuilder(
          listenable: node,
          builder: (context, _) => Box(
            border: .all(
              type: node.hasFocus ? .heavy : .rounded,
              style: node.hasFocus ? theme.primary : theme.border,
            ),
            padding: const .x(1),
            child: Text(
              node.debugLabel!,
              style: node.hasFocus ? bold : const Style(),
            ),
          ),
        ),
      ),
    );
  }
}

const bold = Style(attrs: Attr.bold);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| actions enabled | on, off | true |
