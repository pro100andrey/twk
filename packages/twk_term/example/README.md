# Examples

| file | what it shows |
| --- | --- |
| [split_shells.dart](split_shells.dart) | two shells side by side, each in a `TerminalView`, in a `SplitView`: a click or Alt+1 and Alt+2 focus one, the divider drags, Ctrl+Q quits, and so does the end of both |

```bash
dart run example/split_shells.dart [shell]   # $SHELL, or sh, unless named
```

A shell in the whole terminal, the app quitting when it ends:

```dart
import 'package:twk/twk.dart';
import 'package:twk_term/twk_term.dart';

Future<void> main() => runApp(const Shell());

/// bash in the whole terminal; the app quits when it ends.
final class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

final class _ShellState extends State<Shell> {
  // started at the view's size, at its first layout
  final _session = TerminalSession.start('bash', const []);

  @override
  void initState() {
    super.initState();
    _session.addListener(() {
      if (_session.ended) {
        AppBinding.of(context).quit();
      }
    });
  }

  @override
  void dispose() {
    _session.dispose(); // hangs up: SIGHUP for bash
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TerminalView(session: _session, autofocus: true);
}
```
