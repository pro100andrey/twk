---
title: "Input and focus"
about: "Keys, the focus that Tab moves, the keys hinted where it is, and the mouse."
order: 3
---
# Input and focus

A key goes first to the widget that has the focus, then up through the
layers above it — `KeyBindings`, `Shortcuts`, `Focus` with an
`onKeyEvent` — nearest first, until one takes it. Tab and Shift+Tab that
no widget takes move the focus to the next or the previous widget that
can have it.

<!-- file: packages/twk/example/guides/focus.dart -->
```dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const SignIn());

final class SignIn extends StatefulWidget {
  const SignIn({super.key});

  @override
  State<SignIn> createState() => _SignInState();
}

final class _SignInState extends State<SignIn> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  var _status = '';

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _save() => setState(
    () => _status = _name.text.isEmpty ? 'a name, please' : 'hi, ${_name.text}',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyBindings(
      // not 'q' or 's': a focused field takes the characters typed
      {'ctrl+s': _save, 'ctrl+q': () => AppBinding.of(context).quit()},
      hints: const {'ctrl+s': 'save', 'ctrl+q': 'quit'},
      child: Box(
        style: theme.background.merge(theme.text),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Box(
              border: .all(type: .rounded, style: theme.border),
              titles: [BorderTitle(' Sign in ', style: theme.primary)],
              padding: const .all(1),
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .stretch,
                spacing: 1,
                children: [
                  _Labeled(
                    'Name',
                    child: TextField(
                      controller: _name,
                      placeholder: 'who you are',
                      autofocus: true,
                    ),
                  ),
                  _Labeled(
                    'Password',
                    child: TextField(
                      controller: _password,
                      obscureText: true,
                      semanticsLabel: 'Password',
                    ),
                  ),
                  _Labeled(
                    '',
                    child: Row(
                      spacing: 2,
                      children: [
                        Button('Sign in', onPressed: _save),
                        Text(_status, style: theme.muted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // the keys the focused widget and the bindings above it take
            const KeyHintsBar(),
          ],
        ),
      ),
    );
  }
}

/// [child] after [label], in a column of labels as wide as the longest.
final class _Labeled extends StatelessWidget {
  const _Labeled(this.label, {required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 1,
    children: [
      SizedBox(width: 8, child: Text(label)),
      Expanded(child: child),
    ],
  );
}
```

After typing `ann`, Tab, a password and Ctrl+S:

```text
╭ Sign in ─────────────────────────────╮
│                                      │
│ Name     ann                         │
│                                      │
│ Password ••••••                      │
│                                      │
│           Sign in   hi, ann          │
│                                      │
╰──────────────────────────────────────╯
ctrl+z undo   ctrl+s save   ctrl+q quit
```

## Keys

- `KeyBindings({'ctrl+s': save, 'g g': top}, child:)` binds keys by
  name for what is below it; a space between names makes a sequence.
  `hints:` names what each does for a `KeyHintsBar`, which shows the keys
  that work where the focus is now.
- A focused `TextField` takes the characters typed, so a binding above it
  for `q` never sees `q`. It lets Tab, Escape, Up, Down, Enter without
  `onSubmitted` and the Ctrl and Alt keys it does not edit with go up:
  bind `ctrl+q` rather than `q` in an app with fields.
- `Shortcuts`, `Actions` and `Intent` are Flutter's, for keys that map to
  actions a widget below decides on.
- `InputListener` gets what nobody else took: keys, pastes, resizes.

## Focus

- `autofocus: true` gives a widget the focus when it is first shown.
- A `FocusNode` (`requestFocus()`, `hasFocus`) moves it from code;
  `FocusScope` keeps Tab within a part of the app, `ExcludeFocus` keeps
  the focus out of one.
- Who has the focus: `AppBinding.of(context).focusManager.primaryFocus`
  is the node that has it, or null when no widget does (a `FocusNode`
  you made, compared with `==`, or its `debugLabel`). Read it in a
  callback; a build does not run again when the focus moves. A widget
  that shows whether it has the focus is a `FocusBuilder`.
- Several keys read at once (fast typing, a paste of keys) are handled
  one after another with no build between them: a handler reads the
  state it changes, not what a build made of it. `setState(() => _count++)`
  counts every key of `+++`; `final count = _count;` in the build and
  `setState(() => _count = count + 1)` in the handler counts one, as the
  second key still sees the `count` of the build before.

<!-- file: packages/twk/example/guides/batch.dart -->
```dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Counter());

final class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

final class _CounterState extends State<Counter> {
  var _count = 0;

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      // changes the field itself: the next key of the batch sees it
      '+': () => setState(() => _count++),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Focus(autofocus: true, child: Text('count: $_count')),
  );
}
```

## The mouse

Full screen, the terminal reports the mouse while a widget that needs it
is mounted: `GestureDetector` (`onTap:`, `onDoubleTap:`, `onPanUpdate:`),
`Listener`, `MouseRegion` for hovers and the pointer's shape, `Draggable`
and `DragTarget`. A click on a focusable widget focuses it. Inline, the
mouse stays the terminal's: its own selection keeps working.

Detectors one inside another compete for a press: each gesture goes to
the deepest one with a callback for it, and a press is one gesture, so
when the inner one takes the tap the outer one gets nothing of it. A press
of a button the inner one has no callback for goes to the outer one.
A tap on the outer card's padding says nothing: a `Box` without a
`style` background is hit on its border and its child alone, as Flutter's
`DecoratedBox` is, so `GestureDetector(behavior: HitTestBehavior.opaque)`
takes the cells between. Below, a tap on the inner card says `inner`, one
on the outer card's border `outer`, and F2 says whether the search field
has the focus.

To see a press the inner detector takes, put a `Listener` (`onPointerDown:`,
`onPointerUp:`) around it: a `Listener` is not in the competition and gets every
press hit in it, as in Flutter, the deepest first. It is the answer for a
parent that counts clicks itself, or that has to know of a tap anyway.

The terminal reports the mouse by mode for the whole app, not by area:
presses and the wheel (1000) for taps and `onScroll`, motion with a button
held (1002) for drags, all motion (1003) for `onHover`, `onEnter`,
`onExit`, `onMove`, a `MouseRegion`'s `cursor` where the terminal shows
the pointer's shape, and a `Button`'s hover look. One of them anywhere in
the app turns 1003 on everywhere. The hand over what a click presses is
`ThemeData.pointerMode`, by default `PointerMode.auto`: shown only where motion
is reported already, so a checkbox or a link asks for presses alone; `PointerMode.on`
asks for motion.

The pointer follows the press: a `GestureDetector` with `onTap` or `onTapDown`
shows the hand by that rule, with nothing else to write. `cursor` puts a
`PointerShape` of its own in its place (`PointerShape.arrow` for a click that
presses nothing), and `tapAt: (x, y) => ...` says which cells of a row a tap is
on, for the hand and the tap at once.

A `ListView` or `Scrollable` that should leave the wheel (and the keys) to
the view around takes `physics: const NeverScrollableScrollPhysics()`; its
controller still moves it.

<!-- file: packages/twk/example/guides/who.dart -->
```dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Who());

final class Who extends StatefulWidget {
  const Who({super.key});

  @override
  State<Who> createState() => _WhoState();
}

final class _WhoState extends State<Who> {
  final _search = FocusNode(debugLabel: 'search');
  var _said = 'nothing yet';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      // the node that has the focus now, none if no widget does
      'f2': () => setState(() {
        final focus = AppBinding.of(context).focusManager.primaryFocus;
        _said = 'focus: ${focus == _search ? 'search' : 'elsewhere'}';
      }),
      'ctrl+q': () => AppBinding.of(context).quit(),
    },
    child: Column(
      crossAxisAlignment: .start,
      children: [
        Text(_said),
        GestureDetector(
          onTap: (_) => setState(() => _said = 'outer'),
          child: Box(
            border: const .all(type: .rounded),
            padding: const .all(1),
            child: GestureDetector(
              // the deepest detector with an onTap takes the tap
              onTap: (_) => setState(() => _said = 'inner'),
              child: const Box(
                border: .all(type: .single),
                child: Text('inner'),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 20,
          child: TextField(
            focusNode: _search,
            autofocus: true,
            placeholder: 'search',
          ),
        ),
      ],
    ),
  );
}
```

| | |
| --- | --- |
| ![KeyBindings](../../packages/gallery/doc/shots/focus-and-keys/keybindings-leaderkey.dark.svg)<br>**[KeyBindings, LeaderKey](../widgets/focus-and-keys/keybindings-leaderkey.md)** | ![KeyHintsBar](../../packages/gallery/doc/shots/controls/keyhintsbar.dark.svg)<br>**[KeyHintsBar](../widgets/controls/keyhintsbar.md)** |

More in the catalog's [Focus and keys](../widgets/focus-and-keys.md) and
[Mouse](../widgets/mouse.md) groups.
