import 'package:twk/twk.dart';

/// A counter: up counts, q quits. It knows nothing of the browser, so the
/// test runs it on a terminal in memory.
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
      'up': () => setState(() => _count++),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Box(
      border: const .all(type: .rounded),
      titles: const [
        BorderTitle(' up: count  q: quit ', alignment: .bottomRight),
      ],
      padding: const .all(1),
      child: Text.rich(['Count: '.dim, '$_count'.bold.fg(.green)]),
    ),
  );
}
