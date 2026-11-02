// The input guide's keys read together (doc/guides/input-and-focus.md): +
// counts, however many arrive in one read.
//
//   dart run example/guides/batch.dart
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
