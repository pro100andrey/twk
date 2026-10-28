// A counter in a cubit: Up counts, q quits.
//
//   dart run example/counter.dart           # on the alternate screen
//   dart run example/counter.dart --inline  # below the shell's history
import 'package:twk/twk.dart';
import 'package:twk_bloc/twk_bloc.dart';

Future<void> main(List<String> args) => runApp(
  BlocProvider(create: (_) => CounterCubit(), child: const Counter()),
  mode: args.contains('--inline') ? .inline : .fullscreen,
);

final class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);

  void increment() => emit(state + 1);
}

final class Counter extends StatelessWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'up': () => context.read<CounterCubit>().increment(),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Box(
      border: const .all(type: .rounded),
      titles: const [
        BorderTitle(' up: count  q: quit ', alignment: .bottomRight),
      ],
      padding: const .all(1),
      child: BlocBuilder<CounterCubit, int>(
        builder: (context, n) =>
            Text.rich(['Count: '.dim, '$n'.bold.fg(.green)]),
      ),
    ),
  );
}
