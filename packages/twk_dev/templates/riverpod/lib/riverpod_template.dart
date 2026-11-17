import 'package:twk/twk.dart';
import 'package:twk_riverpod/twk_riverpod.dart';

/// The count: its state is an int, changed by the methods the widgets
/// call through `ref.read(countProvider.notifier)`.
final class Count extends Notifier<int> {
  @override
  int build() => 0;

  /// Counts one up.
  void increment() => state++;

  /// Counts one down.
  void decrement() => state--;

  /// Back to zero.
  void reset() => state = 0;
}

/// Where the count lives: a `ProviderScope` keeps it for the widgets below.
final countProvider = NotifierProvider<Count, int>(Count.new);

/// The app: the count in a box, `up` and `down` change it, `r` resets it,
/// `q` quits. The widgets watch the provider and are rebuilt when it
/// changes.
final class Counter extends ConsumerWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.read(countProvider.notifier);
    return KeyBindings(
      {
        'up': count.increment,
        'down': count.decrement,
        'r': count.reset,
        'q': () => AppBinding.of(context).quit(),
      },
      child: Box(
        border: const .all(type: .rounded),
        titles: const [
          BorderTitle(
            ' up/down: count  r: reset  q: quit ',
            alignment: .bottomRight,
          ),
        ],
        padding: const .all(1),
        child: Text.rich([
          'Count: '.dim,
          '${ref.watch(countProvider)}'.bold.fg(.green),
        ]),
      ),
    );
  }
}
