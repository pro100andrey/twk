<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# App

The app around it all: the screen modes, a fixed viewport, output kept in the scrollback, the window title, notifications and a command-line tool’s console.

[All widgets](../widgets.md)

## InputListener

The input no widget took: keys nothing is bound to, the mouse where no Listener is, pastes, focus and resizes.

API: [`InputListener`](https://pub.dev/documentation/twk/latest/twk/InputListener-class.html).

### Code

```dart
final _events = <(String, String)>[];

/// A key as twk names it: ctrl+x, shift+tab, pageDown, space.
String _name(KeyEvent key) => [
  if (key.ctrl) 'ctrl',
  if (key.alt) 'alt',
  if (key.shift && key.code != KeyCode.char) 'shift',
  switch (key) {
    KeyEvent(code: KeyCode.char, char: ' ') => 'space',
    KeyEvent(code: KeyCode.char, :final char) => char,
    KeyEvent(:final code) => code.name,
  },
].join('+');

bool _onEvent(InputEvent event) {
  final heard = switch (event) {
    KeyEvent(kind: KeyKind.release) => null,
    final KeyEvent key => ('key', _name(key)),
    MouseEvent(:final kind, :final x, :final y) => (
      'mouse',
      '${kind.name} $x,$y',
    ),
    PasteEvent(:final text) => ('paste', 'of ${text.length} characters'),
    FocusEvent(:final focused) => ('focus', focused ? 'in' : 'out'),
    ResizeEvent(:final width, :final height) => (
      'resize',
      'to $width×$height',
    ),
    _ => null,
  };
  if (heard != null) {
    setState(() {
      _events.add(heard);
      if (_events.length > 8) {
        _events.removeAt(0);
      }
    });
  }
  // not taken: the listeners mounted before this one get it too
  return false;
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  final styles = {
    'key': theme.info,
    'mouse': theme.accent,
    'paste': theme.success,
    'focus': theme.warning,
    'resize': theme.primary,
  };
  return InputListener(
    onEvent: _onEvent,
    child: SizedBox(
      width: 46,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Press a key nothing takes, such as x',
                  style: theme.muted,
                ),
              ),
              // takes Enter and Space while it has the focus, and its
              // clicks: none of them reach the listener
              Button('Clear', onPressed: () => setState(_events.clear)),
            ],
          ),
          Box(
            border: .all(type: .rounded, style: theme.border),
            padding: const .x(1),
            child: SizedBox(
              height: 8,
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  if (_events.isEmpty)
                    Text('nothing yet', style: theme.muted),
                  for (final (kind, what) in _events)
                    Text.rich([
                      Span(kind.padRight(7), styles[kind]),
                      Span(what),
                    ]),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
```

## ErrorWidget

An error shown in place of what failed to build, as the app does by itself.

API: [`ErrorWidget`](https://pub.dev/documentation/twk/latest/twk/ErrorWidget-class.html).

### Code

```dart
/// The weather card's content.
final class _Weather extends StatelessWidget {
  const _Weather();

  // throws: the app shows an ErrorWidget in its place, as
  // ErrorWidget(StateError('the weather failed to load')) would,
  // and logs the error with the path of the widget at LogLevel.error
  @override
  Widget build(BuildContext context) =>
      throw StateError('the weather failed to load');
}

/// The cpu's load at step [i]: a wave and noise, from 4 to 96.
static double _loadAt(int i) {
  final s = sin(i * 78.233 + 1.7) * 43758.5453;
  final noise = s - s.floorToDouble();
  return (40 + 16 * sin(i / 2.3) + 34 * (noise - 0.5))
      .clamp(4, 96)
      .roundToDouble();
}

// the last 8 loads, a new one every 600 ms
var _step = 0;
var _load = [for (var i = -7; i <= 0; i++) _loadAt(i)];
late final Timer _timer;

@override
void initState() {
  super.initState();
  _timer = Timer.periodic(
    const Duration(milliseconds: 600),
    (_) => setState(() => _load = [..._load.skip(1), _loadAt(++_step)]),
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
  const bold = Style(attrs: Attr.bold);
  Widget card(String title, Widget child, {int flex = 1}) => Expanded(
    flex: flex,
    child: Box(
      border: .all(type: .rounded, style: theme.border),
      titles: [BorderTitle(' $title ')],
      padding: const .x(1),
      child: child,
    ),
  );
  return SizedBox(
    width: 50,
    height: 5,
    child: Row(
      crossAxisAlignment: .stretch,
      spacing: 1,
      children: [
        card(
          'cpu',
          Column(
            crossAxisAlignment: .stretch,
            children: [
              Text('${_load.last.round()}%', style: bold),
              Expanded(
                child: Sparkline(data: _load, max: 100, style: theme.primary),
              ),
            ],
          ),
        ),
        card('weather', const _Weather(), flex: 2),
        card(
          'disk',
          Column(
            crossAxisAlignment: .stretch,
            children: [
              const Text('61%', style: bold),
              LineGauge(
                ratio: 0.61,
                type: .heavy,
                filledStyle: theme.primary,
                unfilledStyle: theme.border,
              ),
              Text('512 GB', style: theme.muted),
            ],
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
| weather fails | on, off | true |
| what it throws | StateError, FormatException, Exception | StateError |

## Static

Output that is finished once shown: in place here; in the inline mode above the app, in the terminal's history.

API: [`Static`](https://pub.dev/documentation/twk/latest/twk/Static-class.html).

### Code

```dart
import 'dart:async';

import 'package:twk/twk.dart';

void main() => runApp(const Build(), mode: ScreenMode.inline);

final class Build extends StatefulWidget {
  const Build({super.key});

  @override
  State<Build> createState() => _BuildState();
}

final class _BuildState extends State<Build> {
  static const _doing = [
    'resolving packages',
    'compiling',
    'running tests',
    'writing build/app.js',
  ];
  static const _did = [
    'resolved 42 packages',
    'compiled 118 libraries',
    'ran 214 tests',
    'wrote build/app.js',
  ];

  // the steps done, each shown once: finished output
  final _done = <String>[];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) => _step());
  }

  void _step() {
    if (_done.length == _did.length) {
      // a tick after the last item: the frame that built it wrote it
      _timer?.cancel();
      AppBinding.of(context).quit();
      return;
    }
    setState(() => _done.add(_did[_done.length]));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .start,
      children: [
        // each item goes to the terminal's history, above the region
        Static<String>(
          items: _done,
          builder: (context, step) =>
              Text.rich([Span('✓ ', theme.success), Span(step)]),
        ),
        if (_done.length < _did.length)
          Row(
            spacing: 1,
            children: [
              const Spinner(),
              Text('${_doing[_done.length]}…'),
              Text(' ${_done.length + 1}/${_did.length}', style: theme.muted),
            ],
          ),
      ],
    );
  }
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| mode | inline, fullscreen | inline |

## TerminalProgress

The program's progress in the terminal's tab or taskbar, where the terminal shows one (Ghostty, kitty, Windows Terminal, ConEmu).

API: [`TerminalProgress`](https://pub.dev/documentation/twk/latest/twk/TerminalProgress-class.html).

### Code

```dart
// written where the terminal is known to show it (OSC 9;4,
// TerminalInfo.progressReports): when what is shown changes, and every
// 10 s while it does not; taken away when it leaves the tree
final theme = Theme.of(context);
return TerminalProgress(
  state: .normal,
  value: 0.33,
  child: Column(
    crossAxisAlignment: .start,
    children: [
      const Text('In the tab: normal, 33%'),
      Text.rich([
        Span('wrote: ', theme.muted),
        Span('nothing', theme.muted),
      ]),
    ],
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| state | none, normal, error, indeterminate, paused | normal |
| value known | on, off | true |
| value | 0% to 100% | 33 |
| terminal shows it | on, off | true |

## Viewport

The app in a fixed rectangle of the screen (Viewport.fixed): nothing outside it is written, so what the terminal showed around it stays.

### Code

```dart
import 'dart:async';

import 'package:twk/twk.dart';

// the 20 × 4 cells from column 20 of row 0: nothing else is
// written, so what the terminal showed around them stays
void main() => runApp(
  const Build(),
  mode: ScreenMode.inline,
  viewport: const Viewport.fixed(20, 0, 20, 4),
);

final class Build extends StatefulWidget {
  const Build({super.key});

  @override
  State<Build> createState() => _BuildState();
}

final class _BuildState extends State<Build> {
  static const _steps = ['resolving', 'compiling', 'testing', 'writing'];

  var _done = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) => _step());
  }

  void _step() {
    if (_done == _steps.length) {
      // a tick after the last step: its frame stays in the cells
      _timer?.cancel();
      AppBinding.of(context).quit();
      return;
    }
    setState(() => _done++);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _done < _steps.length;
    // laid out at the viewport's size, as a full screen of it
    return Box(
      border: .all(type: .rounded, style: theme.border),
      titles: const [BorderTitle(' build ')],
      padding: const .x(1),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          if (busy)
            Row(spacing: 1, children: [const Spinner(), Text('${_steps[_done]}…')])
          else
            Text.rich([Span('✓ ', theme.success), const Span('built')]),
          Text(
            '${busy ? _done + 1 : _done}/${_steps.length}',
            style: theme.muted,
          ),
        ],
      ),
    );
  }
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| left | 0 to 20 | 20 |
| top | 0 to 4 | 0 |
| mode | inline, fullscreen | inline |

## Window title

The title of the terminal's window or tab while the app runs; the user's own comes back when it ends.

### Code

```dart
// the title of the terminal's window or tab while this is in the
// tree, set again when it changes: of nested ones the innermost, as
// Flutter's Title. The user's own comes back when the app ends.
return TerminalTitle(
  title: 'twk gallery',
  child: const Text('In the title bar: twk gallery'),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| title | twk gallery, build: 3 of 5, chat · ~/project | twk gallery |
| app running | on, off | true |

## Notifications

A desktop notification of a title and a body, where the terminal shows one (OSC 9, 777 or 99); nothing where it does not.

### Code

```dart
var _notified = 0;

// shown where the terminal is known to show one (OSC 9, 777 or 99,
// TerminalInfo.notifications); nothing elsewhere
void _notify() {
  AppBinding.of(context).notify('Build finished', 'ran 214 tests in 3.2 s');
  setState(() => _notified++);
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      Button('Notify', onPressed: _notify),
      Text.rich([
        Span('notified: ', theme.muted),
        if (_notified == 0)
          Span('nothing', theme.muted)
        else
          Span('$_notified'),
      ]),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| terminal | kitty, Ghostty, iTerm2, xterm | kitty |

## Cli

A command-line tool's console (twk's cli.dart) as it runs: questions that leave their answer as a line, a spinner, tasks with bars, a traceback.

### Code

```dart
// Asks what a new app is to be: its name, a template, its features and a
// last yes or no. At a terminal each question is a widget until it is
// answered, then a line: `✔ Template? server`.
import 'package:twk/cli.dart';
import 'package:twk/twk.dart';

Future<void> main(List<String> args) => Cli.runWithArgs(args, create);

Future<void> create(Cli cli, List<String> rest) async {
  final name = await cli.prompt(
    'Project name?',
    defaultValue: 'my_app',
    validate: (name) => RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)
        ? null
        : 'lowercase letters, digits and _',
  );
  final template = await cli.chooseOne(
    'Template?',
    choices: ['console', 'package', 'server', 'web'],
  );
  final features = await cli.chooseAny(
    'Features?',
    choices: ['Linter', 'Docker', 'Tests', 'CI'],
    defaultValues: ['Linter'],
  );
  if (!await cli.confirm('Create $name?')) {
    cli.info('Nothing created.');
    return;
  }
  cli.success([
    'Created '.bold,
    name,
    ' from ',
    template.italic,
    ' with ${features.join(', ')}',
  ]);
}

```

### Options

| option | values | starts at |
| --- | --- | --- |
| program | create, install, check | create |
