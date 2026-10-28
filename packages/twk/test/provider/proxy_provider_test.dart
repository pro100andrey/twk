// ProxyProvider and ProxyProvider2: a value made from those of providers
// above, made anew when they change, and the values replaced disposed of.
import 'package:test/test.dart';
import 'package:twk/provider.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

void main() {
  group('ProxyProvider', () {
    testTwk('update makes the value from the one above and the one it made '
        'before, create the first; anew each time the one above changes', (
      t,
    ) async {
      final counter = Counter();
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: counter,
          child: ProxyProvider<Counter, String>(
            create: (_) => 's',
            update: (_, counter, previous) => '$previous${counter.count}',
            child: Show(
              (context) => Text(context.watch<String>()),
            ),
          ),
        ),
        size: (6, 1),
      );
      expect(t.lines, ['s0']);
      await t.act(counter.increment);
      expect(t.lines, ['s01']);
      await t.act(counter.increment);
      expect(t.lines, ['s012']);
    });

    testTwk('a new value not == rebuilds the watchers and the one it '
        'replaces is handed to dispose; the last when it leaves the tree', (
      t,
    ) async {
      final log = <String>[];
      final counter = Counter();
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: counter,
          child: ProxyProvider<Counter, int>(
            update: (_, counter, _) => counter.count ~/ 2,
            dispose: (_, half) => log.add('disposed $half'),
            child: Built(
              'watcher',
              log,
              (context) => Text('${context.watch<int>()}'),
            ),
          ),
        ),
        size: (4, 1),
      );
      log.clear();
      await t.act(counter.increment);
      expect(t.lines, ['0']);
      expect(log, isEmpty);
      await t.act(counter.increment);
      expect(t.lines, ['1']);
      expect(log, ['disposed 0', 'watcher']);
      await t.pumpWidget(const Text('gone'));
      expect(log, ['disposed 0', 'watcher', 'disposed 1']);
    });

    testTwk('a new widget runs update again, with the value made before', (
      t,
    ) async {
      final calls = <String>[];
      Widget app(String suffix) => Provider.value(
        value: 1,
        child: ProxyProvider<int, String>(
          update: (_, n, previous) {
            calls.add('$previous');
            return '$n$suffix';
          },
          child: Show(
            (context) => Text(context.watch<String>()),
          ),
        ),
      );
      await t.pumpWidget(app('a'), size: (4, 1));
      await t.pumpWidget(app('b'));
      expect(t.lines, ['1b']);
      expect(calls, ['null', '1a']);
    });
  });

  group('ProxyProvider2', () {
    testTwk('update makes the value from the providers of two types above, '
        'anew when either changes', (t) async {
      final counter = Counter(2);
      final names = ValueNotifier('a');
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: counter,
          child: ValueListenableProvider.value(
            value: names,
            child: ProxyProvider2<Counter, String, String>(
              update: (_, counter, name, _) => '$name${counter.count}',
              child: Show(
                (context) => Text(context.watch<String>()),
              ),
            ),
          ),
        ),
        size: (4, 1),
      );
      expect(t.lines, ['a2']);
      await t.act(counter.increment);
      expect(t.lines, ['a3']);
      await t.act(() => names.value = 'b');
      expect(t.lines, ['b3']);
    });
  });
}
