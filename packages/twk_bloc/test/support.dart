// What the tests share: a counter cubit, widgets that log their builds,
// and the errors an app logged.
import 'package:twk/twk.dart';
import 'package:twk_bloc/twk_bloc.dart';
import 'package:twk_test/twk_test.dart';

final class Counter extends Cubit<int> {
  Counter([super.initialState = 0]);

  void increment() => emit(state + 1);
}

/// Lays [children] out in a column, [log] told of each build.
final class Logged extends StatelessWidget {
  const Logged(this.name, this.log, this.children, {super.key});

  final String name;
  final List<String> log;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    log.add(name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// Shows what [builder] returns, [log] told of each build as [name].
final class Built extends StatelessWidget {
  const Built(this.name, this.log, this.builder, {super.key});

  final String name;
  final List<String> log;
  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) {
    log.add(name);
    return builder(context);
  }
}

/// The messages of the errors the app logged.
List<Object?> errors(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level == LogLevel.error)
      switch (r.error) {
        final StateError e => e.message,
        final e => e,
      },
];
