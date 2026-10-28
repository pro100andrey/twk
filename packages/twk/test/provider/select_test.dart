// context.select, Selector, Consumer and Consumer2: what each rebuilds
// when a value changes, and what a selector may not do.
import 'package:test/test.dart';
import 'package:twk/provider.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

void main() {
  group('context.select', () {
    testTwk('rebuilds the widget only when a change makes the selector pick '
        'something else; one that watches by every change', (t) async {
      final log = <String>[];
      final counter = Counter();
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: counter,
          child: Logged('column', log, [
            Built(
              'half',
              log,
              (context) =>
                  Text('${context.select<Counter, int>((c) => c.count ~/ 2)}'),
            ),
            Built(
              'watcher',
              log,
              (context) => Text('${context.watch<Counter>().count}'),
            ),
          ]),
        ),
        size: (4, 2),
      );
      log.clear();
      await t.act(counter.increment);
      expect(t.lines, ['0', '1']);
      expect(log, ['watcher']);
      log.clear();
      await t.act(counter.increment);
      expect(t.lines, ['1', '2']);
      expect(log, ['half', 'watcher']);
    });

    testTwk('compares lists, sets and maps element by element', (t) async {
      final log = <String>[];
      final counter = Counter();
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: counter,
          child: Built('parts', log, (context) {
            final list = context.select<Counter, List<int>>(
              (c) => [c.count ~/ 2],
            );
            final set = context.select<Counter, Set<int>>(
              (c) => {c.count ~/ 2},
            );
            final map = context.select<Counter, Map<String, List<int>>>(
              (c) => {
                'half': [c.count ~/ 2],
              },
            );
            return Text('${list.single}${set.single}${map['half']!.single}');
          }),
        ),
        size: (4, 1),
      );
      log.clear();
      await t.act(counter.increment);
      expect(log, isEmpty);
      await t.act(counter.increment);
      expect(t.lines, ['111']);
      expect(log, ['parts']);
    });

    testTwk('each build selects anew: what the builds before selected no '
        'longer rebuilds the widget', (t) async {
      final log = <String>[];
      final counter = Counter();
      final coarse = ValueNotifier(false);
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: counter,
          child: ValueListenableBuilder(
            valueListenable: coarse,
            builder: (context, tens, _) => Built(
              'selector',
              log,
              (context) => Text(
                tens
                    ? 't${context.select<Counter, int>((c) => c.count ~/ 10)}'
                    : '${context.select<Counter, int>((c) => c.count)}',
              ),
            ),
          ),
        ),
        size: (4, 1),
      );
      await t.act(() => coarse.value = true);
      expect(t.lines, ['t0']);
      log.clear();
      await t.act(counter.increment);
      expect(log, isEmpty);
    });

    testTwk('a build may select parts of several values; a change of any '
        'rebuilds it', (t) async {
      final log = <String>[];
      final counter = Counter();
      final names = ValueNotifier('ab');
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: counter,
          child: ValueListenableProvider.value(
            value: names,
            child: Built(
              'both',
              log,
              (context) => Text(
                '${context.select<Counter, bool>((c) => c.count.isEven)}'
                '${context.select<String, int>((s) => s.length)}',
              ),
            ),
          ),
        ),
        size: (8, 1),
      );
      log.clear();
      await t.act(() => names.value = 'cd');
      expect(log, isEmpty);
      await t.act(() => names.value = 'abc');
      expect(t.lines, ['true3']);
      await t.act(counter.increment);
      expect(t.lines, ['false3']);
      expect(log, ['both', 'both']);
    });

    testTwk('a selector that reads a provider is an error while asserts are '
        'on', (t) async {
      await t.pumpWidget(
        Provider.value(
          value: 1,
          child: ChangeNotifierProvider(
            create: (_) => Counter(),
            child: Show((context) {
              final n = context.select<Counter, int>(
                (c) => c.count + context.read<int>(),
              );
              return Text('$n');
            }),
          ),
        ),
        size: (4, 1),
      );
      expect(loggedErrors(t), [
        isA<AssertionError>().having(
          (e) => e.message,
          'message',
          contains('inside the callback of a context.select'),
        ),
      ]);
    });
  });

  testTwk('select of a value that becomes null, as a non-nullable type, '
      'fails the build with a ProviderNullException naming the widget', (
    t,
  ) async {
    final child = Builder(
      builder: (context) =>
          Text('${context.select<int, bool>((n) => n.isEven)}'),
    );
    await t.pumpWidget(
      Provider<int?>.value(value: 2, child: child),
      size: (10, 1),
    );
    expect(t.lines, ['true']);
    await t.pumpWidget(Provider<int?>.value(value: null, child: child));
    final error = t.logs.records.single.error;
    expect(error, isA<ProviderNullException>());
    expect(
      '$error',
      'Error: The widget Builder tried to read Provider<int> but the '
          'matching provider returned null: make it Provider<int?>',
    );
  });

  group('Selector', () {
    testTwk('builds again only when the selector picks something else; the '
        'selector runs by each change', (t) async {
      final log = <String>[];
      final counter = Counter();
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: counter,
          child: Selector<Counter, List<int>>(
            selector: (_, c) {
              log.add('selector');
              return [c.count ~/ 2];
            },
            builder: (_, half, _) {
              log.add('builder');
              return Text('${half.single}');
            },
          ),
        ),
        size: (4, 1),
      );
      expect(log, ['selector', 'builder']);
      log.clear();
      await t.act(counter.increment);
      expect(log, ['selector']);
      log.clear();
      await t.act(counter.increment);
      expect(t.lines, ['1']);
      expect(log, ['selector', 'builder']);
    });

    testTwk('shouldRebuild says whether it builds again', (t) async {
      final counter = Counter();
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: counter,
          child: Selector<Counter, int>(
            selector: (_, c) => c.count,
            shouldRebuild: (previous, next) => next - previous > 1,
            builder: (_, n, _) => Text('$n'),
          ),
        ),
        size: (4, 1),
      );
      await t.act(counter.increment);
      expect(t.lines, ['0']);
      await t.act(counter.increment);
      expect(t.lines, ['2']);
    });

    testTwk('hands the child over, built by the parent', (t) async {
      await t.pumpWidget(
        Provider.value(
          value: 3,
          child: Selector<int, int>(
            selector: (_, n) => n,
            builder: (_, n, child) => Row(children: [Text('$n:'), child!]),
            child: const Text('c'),
          ),
        ),
        size: (4, 1),
      );
      expect(t.lines, ['3:c']);
    });
  });

  group('Consumer', () {
    testTwk('builds with the value, again by each change; the child is '
        'built once, by the parent', (t) async {
      final log = <String>[];
      final counter = Counter();
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: counter,
          child: Consumer<Counter>(
            builder: (_, counter, child) {
              log.add('builder');
              return Row(children: [Text('${counter.count}:'), child!]);
            },
            child: Built('child', log, (_) => const Text('c')),
          ),
        ),
        size: (4, 1),
      );
      expect(log, ['builder', 'child']);
      log.clear();
      await t.act(counter.increment);
      expect(t.lines, ['1:c']);
      expect(log, ['builder']);
    });

    testTwk('Selector2 picks from two values, and builds again only when '
        'it picks something else', (t) async {
      final log = <String>[];
      final counter = Counter();
      await t.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: counter),
            Provider.value(value: 'n'),
          ],
          child: Selector2<Counter, String, String>(
            selector: (_, counter, name) => '$name${counter.count ~/ 2}',
            builder: (_, picked, _) {
              log.add(picked);
              return Text(picked);
            },
          ),
        ),
        size: (4, 1),
      );
      await t.act(counter.increment);
      expect(log, ['n0']);
      await t.act(counter.increment);
      expect(t.lines, ['n1']);
      expect(log, ['n0', 'n1']);
    });

    testTwk('Consumer2 builds with two values', (t) async {
      final counter = Counter(4);
      await t.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: counter),
            Provider.value(value: 'n'),
          ],
          child: Consumer2<Counter, String>(
            builder: (_, counter, name, _) => Text('$name${counter.count}'),
          ),
        ),
        size: (4, 1),
      );
      expect(t.lines, ['n4']);
      await t.act(counter.increment);
      expect(t.lines, ['n5']);
    });
  });
}
