// ChangeNotifierProvider, ListenableProvider and ValueListenableProvider:
// what a notification rebuilds, when a listenable is listened to and
// disposed of, and a value replaced.
import 'package:test/test.dart';
import 'package:twk/provider.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

void main() {
  group('ChangeNotifierProvider', () {
    testTwk('creates its notifier when it is first read, rebuilds the '
        'widgets that watch it by each notification, once for any number '
        'before the frame, and disposes of it when it leaves the tree', (
      t,
    ) async {
      final log = <String>[];
      final counter = Counter();
      await t.pumpWidget(
        ChangeNotifierProvider(
          create: (_) {
            log.add('created');
            return counter;
          },
          child: Logged('column', log, [
            Built(
              'watcher',
              log,
              (context) => Text('w${context.watch<Counter>().count}'),
            ),
            Built(
              'reader',
              log,
              (context) => Text('r${context.read<Counter>().count}'),
            ),
          ]),
        ),
        size: (4, 2),
      );
      expect(log, ['column', 'watcher', 'created', 'reader']);
      expect(counter.listened, isTrue);
      log.clear();
      await t.act(() {
        counter
          ..increment()
          ..increment();
      });
      expect(t.lines, ['w2', 'r0']);
      expect(log, ['watcher']);
      await t.pumpWidget(const Text('gone'));
      expect(counter.disposed, isTrue);
    });

    testTwk('with a value, listens to it but does not dispose of it; a new '
        'one: the watchers follow it, the old one is let go', (t) async {
      final first = Counter(1);
      final second = Counter(20);
      final child = Show(
        (context) => Text('${context.watch<Counter>().count}'),
      );
      await t.pumpWidget(
        ChangeNotifierProvider.value(value: first, child: child),
        size: (4, 1),
      );
      expect(t.lines, ['1']);
      await t.pumpWidget(
        ChangeNotifierProvider.value(value: second, child: child),
      );
      expect(t.lines, ['20']);
      expect(first.listened, isFalse);
      await t.act(first.increment);
      expect(t.lines, ['20']);
      await t.act(second.increment);
      expect(t.lines, ['21']);
      await t.pumpWidget(const Text('gone'));
      expect(second.listened, isFalse);
      expect(first.disposed || second.disposed, isFalse);
    });

    testTwk('a notification before the value was read rebuilds nothing', (
      t,
    ) async {
      final log = <String>[];
      final counter = Counter();
      final show = ValueNotifier(false);
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: counter,
          child: ValueListenableBuilder(
            valueListenable: show,
            builder: (context, shown, _) => shown
                ? Built(
                    'watcher',
                    log,
                    (context) => Text('${context.watch<Counter>().count}'),
                  )
                : const Text('-'),
          ),
        ),
        size: (4, 1),
      );
      expect(counter.listened, isFalse);
      await t.act(counter.increment);
      await t.act(() => show.value = true);
      expect(t.lines, ['1']);
      expect(counter.listened, isTrue);
    });
  });

  group('ListenableProvider', () {
    testTwk('provides a listenable, rebuilds the watchers by its '
        'notifications, and hands it to dispose', (t) async {
      final disposed = <ValueNotifier<int>>[];
      final notifier = ValueNotifier(1);
      await t.pumpWidget(
        ListenableProvider(
          create: (_) => notifier,
          dispose: (_, notifier) => disposed.add(notifier),
          child: Show(
            (context) => Text('${context.watch<ValueNotifier<int>>().value}'),
          ),
        ),
        size: (4, 1),
      );
      expect(t.lines, ['1']);
      await t.act(() => notifier.value = 2);
      expect(t.lines, ['2']);
      await t.pumpWidget(const Text('gone'));
      expect(disposed, [same(notifier)]);
    });
  });

  group('ValueListenableProvider', () {
    testTwk('provides the value, found by its own type; the watchers are '
        'rebuilt when it changes, as updateShouldNotify says', (t) async {
      final log = <String>[];
      final notifier = ValueNotifier(1);
      await t.pumpWidget(
        ValueListenableProvider.value(
          value: notifier,
          updateShouldNotify: (previous, current) => current.isEven,
          child: Built(
            'watcher',
            log,
            (context) => Text('${context.watch<int>()}'),
          ),
        ),
        size: (4, 1),
      );
      expect(t.lines, ['1']);
      log.clear();
      await t.act(() => notifier.value = 2);
      expect(t.lines, ['2']);
      await t.act(() => notifier.value = 3);
      expect(t.lines, ['2']);
      expect(log, ['watcher']);
    });
  });
}
