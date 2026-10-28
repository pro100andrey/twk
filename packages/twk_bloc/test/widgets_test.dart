// BlocBuilder, BlocSelector, BlocListener, MultiBlocListener and
// BlocConsumer: what each rebuilds and calls for each state, their
// conditions, a bloc given or found, and nothing after they left the tree.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_bloc/twk_bloc.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

void main() {
  group('BlocBuilder', () {
    testTwk('shows the state of the bloc provided above, built again for '
        'each state it emits, once for any number before the frame; the '
        'widgets around it are not', (t) async {
      final log = <String>[];
      final counter = Counter();
      await t.pumpWidget(
        BlocProvider.value(
          value: counter,
          child: Logged('column', log, [
            BlocBuilder<Counter, int>(
              builder: (_, n) {
                log.add('builder');
                return Text('$n');
              },
            ),
            Built('sibling', log, (_) => const Text('-')),
          ]),
        ),
        size: (4, 2),
      );
      expect(t.lines, ['0', '-']);
      expect(log, ['column', 'builder', 'sibling']);
      log.clear();
      await t.act(() {
        counter
          ..increment()
          ..increment();
      });
      expect(t.lines, ['2', '-']);
      expect(log, ['builder']);
    });

    testTwk('buildWhen takes the state emitted before and the one emitted '
        'now; the states it does not take leave the widget as it was', (
      t,
    ) async {
      final asked = <String>[];
      final counter = Counter();
      await t.pumpWidget(
        BlocBuilder<Counter, int>(
          bloc: counter,
          buildWhen: (previous, current) {
            asked.add('$previous>$current');
            return current.isEven;
          },
          builder: (_, n) => Text('$n'),
        ),
        size: (4, 1),
      );
      await t.act(counter.increment);
      expect(t.lines, ['0']);
      await t.act(counter.increment);
      expect(t.lines, ['2']);
      expect(asked, ['0>1', '1>2']);
    });

    testTwk('follows another bloc given by a new widget, the old one no '
        'longer', (t) async {
      final first = Counter(10);
      final second = Counter(20);
      Widget app(Counter counter) => BlocBuilder<Counter, int>(
        bloc: counter,
        builder: (_, n) => Text('$n'),
      );
      await t.pumpWidget(app(first), size: (4, 1));
      expect(t.lines, ['10']);
      await t.pumpWidget(app(second));
      expect(t.lines, ['20']);
      await t.act(first.increment);
      expect(t.lines, ['20']);
      await t.act(second.increment);
      expect(t.lines, ['21']);
    });

    testTwk('follows another bloc a new provider above provides, though its '
        'parent does not build it again; the states alone build it once '
        'each', (t) async {
      final first = Counter(10);
      final second = Counter(20);
      final built = <int>[];
      final builder = BlocBuilder<Counter, int>(
        builder: (_, n) {
          built.add(n);
          return Text('$n');
        },
      );
      Widget app(Counter counter) =>
          BlocProvider.value(value: counter, child: builder);
      await t.pumpWidget(app(first), size: (4, 1));
      await t.act(first.increment);
      await t.pumpWidget(app(second));
      expect(t.lines, ['20']);
      await t.act(first.increment);
      await t.act(second.increment);
      expect(t.lines, ['21']);
      expect(built, [10, 11, 20, 21]);
    });

    testTwk('stops following the bloc when it leaves the tree', (t) async {
      final counter = Counter();
      await t.pumpWidget(
        BlocBuilder<Counter, int>(
          bloc: counter,
          builder: (_, n) => Text('$n'),
        ),
      );
      await t.pumpWidget(const Text('gone'));
      await t.act(counter.increment);
      expect(t.lines.first, 'gone');
    });
  });

  testTwk('a BlocBuilder given no bloc and with none provided above fails, '
      'naming the type and itself', (t) async {
    await t.pumpWidget(
      BlocBuilder<Counter, int>(builder: (_, n) => Text('$n')),
      size: (10, 1),
    );
    const message =
        'no BlocProvider<Counter> or RepositoryProvider<Counter> above '
        'BlocBuilder<Counter, int>';
    expect(errors(t), [message]);
  });

  group('BlocSelector', () {
    testTwk('is built again only when a state picks another value', (
      t,
    ) async {
      final log = <String>[];
      final counter = Counter();
      await t.pumpWidget(
        BlocSelector<Counter, int, bool>(
          bloc: counter,
          selector: (n) => n > 1,
          builder: (_, big) {
            log.add('$big');
            return Text('$big');
          },
        ),
        size: (6, 1),
      );
      await t.act(counter.increment);
      expect(log, ['false']);
      await t.act(counter.increment);
      expect(t.lines, ['true']);
      expect(log, ['false', 'true']);
    });

    testTwk('a new widget with another selector picks again from the state '
        'now', (t) async {
      final counter = Counter(3);
      Widget selecting(int Function(int n) selector) =>
          BlocSelector<Counter, int, int>(
            bloc: counter,
            selector: selector,
            builder: (_, n) => Text('$n'),
          );
      await t.pumpWidget(selecting((n) => n), size: (4, 1));
      expect(t.lines, ['3']);
      await t.pumpWidget(selecting((n) => n * 10));
      expect(t.lines, ['30']);
    });
  });

  group('BlocListener', () {
    testTwk('calls its listener once for each state listenWhen takes, '
        'without rebuilding its child, until it leaves the tree', (
      t,
    ) async {
      final log = <String>[];
      final counter = Counter();
      Widget app({required bool listening}) => BlocProvider.value(
        value: counter,
        child: listening
            ? BlocListener<Counter, int>(
                listenWhen: (previous, current) => current != 2,
                listener: (context, n) => log.add('heard $n'),
                child: Built('child', log, (_) => const Text('child')),
              )
            : const Text('gone'),
      );
      await t.pumpWidget(app(listening: true), size: (6, 1));
      expect(log, ['child']);
      await t.act(() {
        counter
          ..increment()
          ..increment()
          ..increment();
      });
      expect(log, ['child', 'heard 1', 'heard 3']);
      await t.pumpWidget(app(listening: false));
      await t.act(counter.increment);
      expect(log, ['child', 'heard 1', 'heard 3']);
    });
  });

  group('MultiBlocListener', () {
    testTwk('nests its listeners around its child, each called for its '
        'bloc', (t) async {
      final log = <String>[];
      final a = Counter();
      final b = Counter(10);
      await t.pumpWidget(
        MultiBlocListener(
          listeners: [
            BlocListener<Counter, int>(
              bloc: a,
              listener: (_, n) => log.add('a $n'),
            ),
            BlocListener<Counter, int>(
              bloc: b,
              listener: (_, n) => log.add('b $n'),
            ),
          ],
          child: const Text('child'),
        ),
        size: (6, 1),
      );
      expect(t.lines, ['child']);
      await t.act(() {
        a.increment();
        b.increment();
      });
      expect(log, ['a 1', 'b 11']);
    });

    testTwk('a BlocListener without a child outside one fails, naming it', (
      t,
    ) async {
      await t.pumpWidget(
        BlocListener<Counter, int>(bloc: Counter(), listener: (_, _) {}),
        size: (10, 1),
      );
      const message =
          'BlocListener<Counter, int> without a child outside a '
          'MultiBlocListener or MultiProvider';
      expect(errors(t), [message]);
    });
  });

  group('BlocConsumer', () {
    testTwk('calls its listener first, then is built again, each as its '
        'condition says', (t) async {
      final log = <String>[];
      final counter = Counter();
      await t.pumpWidget(
        BlocProvider.value(
          value: counter,
          child: BlocConsumer<Counter, int>(
            listenWhen: (_, n) => n.isOdd,
            listener: (_, n) => log.add('heard $n'),
            buildWhen: (_, n) => n.isEven,
            builder: (_, n) {
              log.add('built $n');
              return Text('$n');
            },
          ),
        ),
        size: (4, 1),
      );
      await t.act(counter.increment);
      expect(t.lines, ['0']);
      await t.act(counter.increment);
      expect(t.lines, ['2']);
      expect(log, ['built 0', 'heard 1', 'built 2']);
    });
  });
}
