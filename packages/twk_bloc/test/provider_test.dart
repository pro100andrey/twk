// BlocProvider and RepositoryProvider: when what they provide is created
// and closed, read and watch, a value replaced, the providers nested by
// MultiBlocProvider and MultiRepositoryProvider, and one not found.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_bloc/twk_bloc.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

void main() {
  group('BlocProvider', () {
    testTwk('creates its bloc when it is first read and closes it when it '
        'leaves the tree', (t) async {
      final log = <String>[];
      final counter = Counter();
      await t.pumpWidget(
        BlocProvider(
          create: (_) {
            log.add('created');
            return counter;
          },
          child: Logged('column', log, const [Text('no reader')]),
        ),
        size: (10, 1),
      );
      expect(log, ['column']);
      await t.pumpWidget(
        BlocProvider(
          create: (_) {
            log.add('created');
            return counter;
          },
          child: Built(
            'reader',
            log,
            (context) => Text('${context.read<Counter>().state}'),
          ),
        ),
      );
      expect(t.lines, ['0']);
      expect(log, ['column', 'reader', 'created']);
      expect(counter.isClosed, isFalse);
      await t.pumpWidget(const Text('gone'));
      expect(counter.isClosed, isTrue);
    });

    testTwk('not lazy, creates it when it is placed in the tree', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        BlocProvider(
          create: (_) {
            log.add('created');
            return Counter();
          },
          lazy: false,
          child: Logged('column', log, const []),
        ),
      );
      expect(log, ['created', 'column']);
    });

    testTwk('watch rebuilds the widget that watches by each state, and no '
        'other; read does not', (t) async {
      final log = <String>[];
      final counter = Counter();
      await t.pumpWidget(
        BlocProvider.value(
          value: counter,
          child: Logged('column', log, [
            Built(
              'watcher',
              log,
              (context) => Text('watched ${context.watch<Counter>().state}'),
            ),
            Built(
              'reader',
              log,
              (context) => Text('read ${context.read<Counter>().state}'),
            ),
          ]),
        ),
        size: (10, 2),
      );
      expect(t.lines, ['watched 0', 'read 0']);
      log.clear();
      await t.act(counter.increment);
      expect(t.lines, ['watched 1', 'read 0']);
      expect(log, ['watcher']);
    });

    testTwk('a widget whose last build did not watch is no longer rebuilt '
        'by its states', (t) async {
      final log = <String>[];
      final counter = Counter();
      final watch = ValueNotifier(true);
      await t.pumpWidget(
        BlocProvider.value(
          value: counter,
          child: ValueListenableBuilder(
            valueListenable: watch,
            builder: (context, watching, _) => Built(
              'built',
              log,
              (context) => Text(
                watching
                    ? '${context.watch<Counter>().state}'
                    : '${context.read<Counter>().state}',
              ),
            ),
          ),
        ),
        size: (4, 1),
      );
      await t.act(() => watch.value = false);
      log.clear();
      await t.act(counter.increment);
      expect(log, isEmpty);
      expect(t.lines, ['0']);
    });

    testTwk('with a value, does not close it; a new widget with another '
        'value rebuilds those that follow the bloc', (t) async {
      final first = Counter(1);
      final second = Counter(2);
      final log = <String>[];
      Widget app(Counter counter) => BlocProvider.value(
        value: counter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BlocBuilder<Counter, int>(builder: (_, n) => Text('built $n')),
            Built(
              'watcher',
              log,
              (context) => Text('watched ${context.watch<Counter>().state}'),
            ),
          ],
        ),
      );
      await t.pumpWidget(app(first), size: (10, 2));
      expect(t.lines, ['built 1', 'watched 1']);
      await t.pumpWidget(app(second));
      expect(t.lines, ['built 2', 'watched 2']);
      await t.act(first.increment);
      expect(t.lines, ['built 2', 'watched 2']);
      await t.act(second.increment);
      expect(t.lines, ['built 3', 'watched 3']);
      await t.pumpWidget(const Text('gone'));
      expect(first.isClosed, isFalse);
      expect(second.isClosed, isFalse);
    });

    testTwk('the nearest provider of a type hides those above it', (t) async {
      await t.pumpWidget(
        BlocProvider.value(
          value: Counter(1),
          child: BlocProvider.value(
            value: Counter(2),
            child: BlocBuilder<Counter, int>(builder: (_, n) => Text('$n')),
          ),
        ),
        size: (4, 1),
      );
      expect(t.lines, ['2']);
    });

    testTwk('of without a provider above is a StateError naming the type '
        'and the widget', (t) async {
      await t.pumpWidget(const Text('alone'));
      final context = t.element(find.text('alone'));
      expect(
        () => BlocProvider.of<Counter>(context),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'no BlocProvider<Counter> or RepositoryProvider<Counter> above '
                'Text',
          ),
        ),
      );
    });
  });

  group('MultiBlocProvider', () {
    testTwk('nests its providers, the first outermost, each found by its '
        'type', (t) async {
      final counter = Counter(1);
      final log = <String>[];
      await t.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: counter),
            BlocProvider(create: (context) => _Doubled(context.read())),
          ],
          child: Built(
            'reader',
            log,
            (context) => Text(
              '${context.watch<Counter>().state} '
              '${context.watch<_Doubled>().state}',
            ),
          ),
        ),
        size: (6, 1),
      );
      expect(t.lines, ['1 2']);
      await t.act(counter.increment);
      await t.pump();
      expect(t.lines, ['2 4']);
    });
  });

  group('RepositoryProvider', () {
    testTwk('provides what it creates, read where it is first needed, and '
        'hands it to dispose when it leaves the tree', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider(
              create: (_) => 'repo',
              dispose: (value) => log.add('disposed $value'),
            ),
            RepositoryProvider.value(value: 7),
          ],
          child: Built(
            'reader',
            log,
            (context) => Text(
              '${RepositoryProvider.of<String>(context)} '
              '${context.read<int>()}',
            ),
          ),
        ),
        size: (8, 1),
      );
      expect(t.lines, ['repo 7']);
      await t.pumpWidget(const Text('gone'));
      expect(log, ['reader', 'disposed repo']);
    });

    testTwk('a widget that watches it is built again when a new widget '
        'provides another; one that reads it is not', (t) async {
      final log = <String>[];
      final child = Logged('column', log, [
        Built('watcher', log, (context) => Text(context.watch<String>())),
        Built('reader', log, (context) => Text(context.read<String>())),
      ]);
      Widget app(String value) =>
          RepositoryProvider.value(value: value, child: child);
      await t.pumpWidget(app('a'), size: (4, 2));
      log.clear();
      await t.pumpWidget(app('b'));
      expect(t.lines, ['b', 'a']);
      expect(log, ['watcher']);
    });
  });

  testTwk('a provider without a child outside a MultiBlocProvider or '
      'MultiRepositoryProvider fails, naming it', (t) async {
    await t.pumpWidget(BlocProvider.value(value: Counter()), size: (10, 1));
    const message =
        'BlocProvider<Counter> without a child outside a MultiBlocProvider, '
        'MultiRepositoryProvider or MultiProvider';
    expect(errors(t), [message]);
  });
}

/// Twice the [Counter] it is made with, as it counts.
final class _Doubled extends Cubit<int> {
  _Doubled(Counter counter) : super(counter.state * 2) {
    _counting = counter.stream.listen((n) => emit(n * 2));
  }

  late final StreamSubscription<int> _counting;

  @override
  Future<void> close() async {
    await _counting.cancel();
    return super.close();
  }
}
