import 'package:twk/twk.dart';
import 'package:twk_bloc/twk_bloc.dart';

/// The count: a cubit whose state is an int, changed by its methods and
/// emitted to the widgets that build on it.
final class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);

  /// Counts one up.
  void increment() => emit(state + 1);

  /// Counts one down.
  void decrement() => emit(state - 1);

  /// Back to zero.
  void reset() => emit(0);
}

/// The app: the count in a box, `up` and `down` change it, `r` resets it,
/// `q` quits. A `BlocBuilder` rebuilds the box as the cubit emits.
final class Counter extends StatelessWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CounterCubit>();
    return KeyBindings(
      {
        'up': cubit.increment,
        'down': cubit.decrement,
        'r': cubit.reset,
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
        child: BlocBuilder<CounterCubit, int>(
          builder: (context, count) => Text.rich([
            'Count: '.dim,
            '$count'.bold.fg(.green),
          ]),
        ),
      ),
    );
  }
}
