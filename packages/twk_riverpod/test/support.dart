// What the tests share: counters, a widget that watches a provider and
// one that lays others out, each logging its builds.
import 'package:twk/twk.dart';
import 'package:twk_riverpod/misc.dart';
import 'package:twk_riverpod/twk_riverpod.dart';
import 'package:twk_test/twk_test.dart';

final class Count extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

final a = NotifierProvider<Count, int>(Count.new);
final b = NotifierProvider<Count, int>(Count.new);

/// Shows `name: value` of [provider], [log] told of each build.
final class Watching extends ConsumerWidget {
  const Watching(this.name, this.provider, this.log, {super.key});

  final String name;
  final ProviderListenable<Object?> provider;
  final List<String> log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    log.add(name);
    return Text('$name: ${ref.watch(provider)}');
  }
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

/// The container of the scope the app's widgets are in.
ProviderContainer containerOf(TwkTester t) => ProviderScope.containerOf(
  t.element(find.byType(Text).first),
  listen: false,
);

void increment(TwkTester t, NotifierProvider<Count, int> provider) =>
    containerOf(t).read(provider.notifier).increment();
