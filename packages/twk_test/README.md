# twk_test

Tests for apps built with [twk](https://pub.dev/packages/twk). A test runs
the real app on a terminal in memory, presses keys, clicks, and checks the
screen the user would see.

## Features

- **The real app:** `testTwk` runs your widget under `runApp`'s binding, not
  a stand-in, so a test sees what the user sees.
- **A fake clock:** timers, animations and frames wait for the test, which
  moves time with `pump`. No test waits on the wall clock.
- **Input as a terminal sends it:** `press('ctrl+s')`, `type('text')`,
  `paste`, `click` and `resize`, decoded by the same parser the app uses.
- **The screen as text:** `lines`, `cell(x, y)` for colors and attributes,
  the cursor and the scrollback, read from a strict terminal emulator that
  fails on a sequence a real terminal would not take.
- **Matchers:** `containsLine`, `hasTextAt`, `styleAt`, `cursorAt`, and
  `matchesScreen` for a snapshot of the screen, with its styles or from a
  golden file.
- **Finders:** `find.byType`, `find.byKey`, `find.text`, to click a widget
  or read its state and the cells it covers.
- **Failures that explain themselves:** a failing matcher shows the screen,
  the widget tree and the render tree, and a failing test shows its last
  frames and the app's log.
- **More:** the emulator and a terminal for programs on twk's console, a
  `Shot` of a widget without an app, and helpers for tests that run a
  process.

## Getting started

```sh
dart pub add dev:twk_test
```

A counter and a test of it. Save it as `test/counter_test.dart` and run
`dart test`:

```dart
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

final class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

final class _CounterState extends State<Counter> {
  var _n = 0;

  @override
  Widget build(BuildContext context) => KeyBindings({
    'up': () => setState(() => _n++),
  }, child: Text('Count: $_n'));
}

void main() {
  testTwk('Up counts', (t) async {
    await t.pumpWidget(const Counter(), size: (20, 3));
    expect(t, containsLine('Count: 0'));

    await t.press('up up up');
    await t.pump();
    expect(t, containsLine('Count: 3'));
  });
}
```

## Learn more

- [Example](https://github.com/pro100andrey/twk/blob/main/packages/twk_test/example/twk_test_example.dart):
  a counter with a snapshot of the screen, a style check and a quit.
- [Guide](https://github.com/pro100andrey/twk/blob/main/packages/twk_test/doc/guide.md):
  writing a test, time, input, errors.
- [The screen](https://github.com/pro100andrey/twk/blob/main/packages/twk_test/doc/screen.md):
  reading it, matchers, golden files, finders and frames.
- [Other libraries](https://github.com/pro100andrey/twk/blob/main/packages/twk_test/doc/libraries.md):
  the emulator, `Shot`, `FakeClock` on its own, and tests that run processes.
- [How it is tested](https://github.com/pro100andrey/twk/blob/main/packages/twk_test/doc/internals.md):
  for those who work on the package.

## License

MIT, copyright 2026 Andrii Ivanov: [LICENSE](LICENSE).
