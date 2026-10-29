// An app run by runApp on the process's own terminal, for a run in a
// pseudo-terminal under an interactive shell (stop_test.dart): the size
// it is drawn at; Ctrl+Z, which nothing in it takes, stops it for the
// shell, and q quits it.
import 'package:twk/twk.dart';

Future<void> main() => runApp(const _Stop());

final class _Stop extends StatelessWidget {
  const _Stop();

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'q': () => AppBinding.of(context).quit()},
    child: Focus(
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, c) => Text('stop app ${c.maxW}x${c.maxH}'),
      ),
    ),
  );
}
