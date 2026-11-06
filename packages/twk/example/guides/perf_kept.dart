// The performance guide's second app (doc/guides/performance.md): a long
// text in a panel of its own that keeps its paint, one line of it changed
// by a key.
//
//   dart run example/guides/perf_kept.dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Notes());

final class Notes extends StatefulWidget {
  const Notes({super.key});

  @override
  State<Notes> createState() => _NotesState();
}

final class _NotesState extends State<Notes> {
  var _done = 0;

  String get _text => [
    for (var i = 0; i < 200; i++) '${i < _done ? '[x]' : '[ ]'} task $i',
  ].join('\n');

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'd': () => setState(() => _done++),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Focus(
      autofocus: true,
      child: Panel(
        look: PanelLook.bordered,
        child: Text(_text, keepsPaint: true),
      ),
    ),
  );
}
