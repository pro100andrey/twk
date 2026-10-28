// twk_bloc with package:twk/provider.dart in one file: one SingleChildWidget, so that
// the providers of either nest in the Multi widgets of the other, and one
// context.read, watch and select, which find blocs and other values alike.
import 'package:test/test.dart';
import 'package:twk/provider.dart';
import 'package:twk/twk.dart';
import 'package:twk_bloc/twk_bloc.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

void main() {
  testTwk('a BlocProvider nests in a MultiProvider, beside a Provider, '
      'watched and read by the same context extensions', (t) async {
    final log = <String>[];
    final counter = Counter();
    await t.pumpWidget(
      MultiProvider(
        providers: [
          Provider.value(value: 'count'),
          BlocProvider.value(value: counter),
        ],
        child: Built(
          'watcher',
          log,
          (context) => Text(
            '${context.read<String>()} ${context.watch<Counter>().state}',
          ),
        ),
      ),
      size: (10, 1),
    );
    expect(t.lines, ['count 0']);
    await t.act(counter.increment);
    expect(t.lines, ['count 1']);
    expect(log, ['watcher', 'watcher']);
  });

  testTwk('a Provider and a ChangeNotifierProvider nest in a '
      'MultiBlocProvider: a list of SingleChildWidgets of either package', (
    t,
  ) async {
    final count = ValueNotifier(1);
    final providers = <SingleChildWidget>[
      ChangeNotifierProvider.value(value: count),
      BlocProvider(
        create: (context) => Counter(context.read<ValueNotifier<int>>().value),
      ),
      RepositoryProvider.value(value: 'repo'),
    ];
    await t.pumpWidget(
      MultiBlocProvider(
        providers: providers,
        child: BlocBuilder<Counter, int>(
          builder: (context, n) => Text(
            '$n ${context.watch<ValueNotifier<int>>().value} '
            '${context.read<String>()}',
          ),
        ),
      ),
      size: (10, 1),
    );
    expect(t.lines, ['1 1 repo']);
    await t.act(() => count.value = 5);
    expect(t.lines, ['1 5 repo']);
  });

  testTwk('a BlocListener nests in a MultiProvider; select depends on a '
      'part of a bloc', (t) async {
    final heard = <int>[];
    final log = <String>[];
    final counter = Counter();
    await t.pumpWidget(
      BlocProvider.value(
        value: counter,
        child: MultiProvider(
          providers: [
            BlocListener<Counter, int>(listener: (_, n) => heard.add(n)),
          ],
          child: Built(
            'over 1',
            log,
            (context) =>
                Text('${context.select<Counter, bool>((c) => c.state > 1)}'),
          ),
        ),
      ),
      size: (5, 1),
    );
    await t.act(counter.increment);
    await t.act(counter.increment);
    await t.act(counter.increment);
    expect(heard, [1, 2, 3]);
    expect(t.lines, ['true']);
    expect(log, ['over 1', 'over 1']);
  });

  testTwk("read without a provider above is the provider library's "
      'ProviderNotFoundException', (t) async {
    await t.pumpWidget(const Text('alone'));
    final context = t.element(find.text('alone'));
    expect(
      () => context.read<Counter>(),
      throwsA(
        isA<ProviderNotFoundException>().having(
          (e) => e.valueType,
          'valueType',
          Counter,
        ),
      ),
    );
  });
}
