// A counter in a ChangeNotifier: Up counts, q quits.
//
//   dart run example/provider/counter.dart           # on the alternate screen
//   dart run example/provider/counter.dart --inline  # below the shell's history
import 'package:twk/provider.dart';
import 'package:twk/twk.dart';

Future<void> main(List<String> args) => runApp(
  ChangeNotifierProvider(create: (_) => CounterModel(), child: const Counter()),
  mode: args.contains('--inline') ? .inline : .fullscreen,
);

class CounterModel extends ChangeNotifier {
  var _count = 0;

  int get count => _count;

  void increment() {
    _count++;
    notifyListeners();
  }
}

final class Counter extends StatelessWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'up': () => context.read<CounterModel>().increment(),
      'q': () => AppBinding.of(context).quit(),
    },
    child: const Box(
      border: .all(type: .rounded),
      titles: [BorderTitle(' up: count  q: quit ', alignment: .bottomRight)],
      padding: .all(1),
      child: _Count(),
    ),
  );
}

// rebuilt alone, by the counts it selects
final class _Count extends StatelessWidget {
  const _Count();

  @override
  Widget build(BuildContext context) {
    final n = context.select<CounterModel, int>((counter) => counter.count);
    return Text.rich(['Count: '.dim, '$n'.bold.fg(.green)]);
  }
}
