// A counter in a provider: Up counts, q quits.
//
//   dart run example/counter.dart           # on the alternate screen
//   dart run example/counter.dart --inline  # below the shell's history
import 'package:twk/twk.dart';
import 'package:twk_riverpod/twk_riverpod.dart';

Future<void> main(List<String> args) => runApp(
  const ProviderScope(child: Counter()),
  mode: args.contains('--inline') ? .inline : .fullscreen,
);

final class Count extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

final countProvider = NotifierProvider<Count, int>(Count.new);

final class Counter extends ConsumerWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => KeyBindings(
    {
      'up': () => ref.read(countProvider.notifier).increment(),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Box(
      border: const .all(type: .rounded),
      titles: const [
        BorderTitle(' up: count  q: quit ', alignment: .bottomRight),
      ],
      padding: const .all(1),
      child: Text.rich([
        'Count: '.dim,
        '${ref.watch(countProvider)}'.bold.fg(.green),
      ]),
    ),
  );
}
