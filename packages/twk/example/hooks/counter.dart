// A counter written with hooks: Up counts, q quits.
//
//   dart run example/hooks/counter.dart           # on the alternate screen
//   dart run example/hooks/counter.dart --inline  # below the shell's history
import 'package:twk/hooks.dart';
import 'package:twk/twk.dart';

Future<void> main(List<String> args) => runApp(
  const Counter(),
  mode: args.contains('--inline') ? .inline : .fullscreen,
);

final class Counter extends HookWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useState(0);
    return KeyBindings(
      {
        'up': () => count.value++,
        'q': () => AppBinding.of(context).quit(),
      },
      child: Box(
        border: const .all(type: .rounded),
        titles: const [
          BorderTitle(' up: count  q: quit ', alignment: .bottomRight),
        ],
        padding: const .all(1),
        child: Text.rich(['Count: '.dim, '${count.value}'.bold.fg(.green)]),
      ),
    );
  }
}
