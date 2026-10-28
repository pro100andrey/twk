# Examples

Each runs on the alternate screen, and most with `--inline` below the
shell's history: `dart run example/<file>.dart [--inline]`.

| file | what it shows |
| --- | --- |
| [counter.dart](counter.dart) | a counter in a rounded box: Up counts, q quits |
| [static_screen.dart](static_screen.dart) | a header, two boxes of wrapped text side by side, a footer |
| [interactive.dart](interactive.dart) | a chat: a list that follows new messages, a list of people, a text field, focus moved by Tab and the mouse |
| [settings.dart](settings.dart) | a menu bar, tabs of switches, checkboxes and radio buttons in one form, a context menu, a dialog, a spinner and toasts, in a dark or light theme from the terminal |
| [monitor.dart](monitor.dart) | a process monitor: gauges, sparklines, and a sorted table or a tree of processes |
| [dashboard.dart](dashboard.dart) | an operations dashboard, live: tiles of figures with sparklines, a chart, a heatmap of deploys and a log in a grid with shared borders, a dark or light theme from the terminal, the debug overlays |
| [files.dart](files.dart) | a file manager: a tree and a table in a split view, a menu bar, a command palette, copying with a progress bar |
| [hooks/counter.dart](hooks/counter.dart) | the counter written with `package:twk/hooks.dart` |
| [hooks/search.dart](hooks/search.dart) | a search written with hooks: the list loaded with `useFuture`, filtered by `useMemoized` once the typing pauses, with a hook of its own, `useDebounced` |
| [provider/counter.dart](provider/counter.dart) | the counter on a `ChangeNotifier` with `package:twk/provider.dart` |

The counter:

```dart
import 'package:twk/twk.dart';

Future<void> main(List<String> args) => runApp(
  const Counter(),
  mode: args.contains('--inline') ? .inline : .fullscreen,
);

final class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

final class _CounterState extends State<Counter> {
  var _n = 0;

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'up': () => setState(() => _n++),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Box(
      border: const .all(type: .rounded),
      titles: const [
        BorderTitle(' up: count  q: quit ', alignment: .bottomRight),
      ],
      padding: const .all(1),
      child: Text.rich(['Count: '.dim, '$_n'.bold.fg(.green)]),
    ),
  );
}
```

Each has its test in
[test/example/](https://github.com/pro100andrey/twk/tree/main/packages/twk/test/example).
