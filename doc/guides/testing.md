---
title: "Testing"
about: "An app tested on a terminal in memory, under a fake clock, with twk_test."
order: 7
---
# Testing

[twk_test](https://pub.dev/packages/twk_test) runs the real app — the
same `runApp` binding — on a terminal in memory, under a fake clock. Keys,
the mouse and pasted text go in as the bytes a terminal sends, and the
screen is rebuilt from the bytes the app wrote by a strict terminal
emulator, which the matchers read.

```sh
dart pub add dev:twk_test
```

The counter of [Getting started](getting-started.md), tested full screen
and inline:

<!-- file: packages/twk/test/example/counter_test.dart -->
```dart
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/counter.dart' show Counter;

void main() {
  testTwk('full screen, the box fills the terminal and Up counts', (t) async {
    await t.pumpWidget(const Counter(), size: (24, 6));
    expect(
      t,
      matchesScreen('''
╭──────────────────────╮
│                      │
│ Count: 0             │
│                      │
│                      │
╰── up: count  q: quit ╯
'''),
    );

    await t.press('up up up');
    await t.pump();
    expect(t, containsLine('│ Count: 3             │'));
    expect(t, styleAt(2, 2, hasAttr(Attr.dim)));
    expect(t, styleAt(9, 2, allOf(hasAttr(Attr.bold), hasFg(Color.green))));
  });

  testTwk('q quits', (t) async {
    await t.pumpWidget(const Counter());
    await t.press('q');
    expect(t.isRunning, isFalse);
  });

  testTwk('inline, the box is as tall as its text, below the history, and '
      'stays there when q quits', (t) async {
    await t.pumpWidget(
      const Counter(),
      size: (44, 10),
      mode: ScreenMode.inline,
      history: [r'$ dart run example/counter.dart --inline'],
    );
    await t.press('up');
    await t.pump();
    await t.press('q');
    expect(t.isRunning, isFalse);
    expect(
      t,
      matchesScreen(r'''
$ dart run example/counter.dart --inline
╭──────────────────────────────────────────╮
│                                          │
│ Count: 1                                 │
│                                          │
╰────────────────────── up: count  q: quit ╯
'''),
    );
  });
}
```

## The tester

- `pumpWidget(app, size: (columns, rows))` starts the app, 80 × 24 by
  default; `mode: ScreenMode.inline` with `history:` lines above it. A
  later `pumpWidget` shows another widget, the state kept where they
  match.
- Input draws nothing by itself: `await t.pump()` after `type`, `press`
  or a click, before reading the screen. `t.pump(duration)` moves the
  clock on by that much, running the app's timers, frames and animations
  due by then.
- `type('text')` sends text as one read; `press('enter')`,
  `press('tab space')`, `press('ctrl+x ctrl+s')` send each key as a read
  of its own. `click(x, y)`, `clickOn(finder)` and `mouse(...)` work full
  screen; `resize(columns, rows)`.

## Reading the screen

- `t.lines` (rows without their trailing blanks), `t.scrollback`
  (inline), `t.cell(x, y)`, `t.cursor`.
- Matchers: `containsLine`, `hasTextAt(x, y, text)`,
  `styleAt(x, y, hasFg(Color.red))` with `hasAttr` and `hasBg`,
  `cursorAt(x, y)`, `matchesScreen('''…''')` for the whole screen, and
  `matchesScreenFile` for golden files written with
  `TWK_UPDATE_GOLDENS=1`.
- Finders as in Flutter: `find.text`, `find.byType`, `find.byKey`, with
  `findsOneWidget`, `findsNothing`, `findsNWidgets(n)`.

A failing matcher shows the screen, the widget tree with each widget's
size and the render tree, and a failing test prints its last frames.

## Time

No test waits on the wall clock. Only the app's timers and frames are on
the fake clock: `DateTime.now()` and `Stopwatch()` read real time, so pass
dates in. `pumpUntilIdle()` pumps until no frame and no timer waits; an
app with a periodic timer or a spinner is never idle — pump it by a
duration instead.

The rest of the tester — frames recorded and written as a trace, a widget
drawn without an app (`Shot`), processes a test starts — is in
[twk_test's README](https://pub.dev/packages/twk_test).
