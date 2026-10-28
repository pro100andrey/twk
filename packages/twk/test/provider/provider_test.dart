// Provider and InheritedProvider: when a value is created and disposed of,
// read and watch, a value replaced, a provider not found, the providers
// above found from create, what is refused, and MultiProvider.
import 'package:test/test.dart';
import 'package:twk/provider.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

void main() {
  group('Provider', () {
    testTwk('creates its value when it is first read and disposes of it '
        'when it leaves the tree', (t) async {
      final log = <String>[];
      Widget app(Widget child) => Provider<String>(
        create: (_) {
          log.add('created');
          return 'value';
        },
        dispose: (_, value) => log.add('disposed $value'),
        child: child,
      );
      await t.pumpWidget(
        app(Logged('column', log, const [Text('no reader')])),
        size: (10, 1),
      );
      expect(log, ['column']);
      await t.pumpWidget(
        app(Built('reader', log, (context) => Text(context.read<String>()))),
      );
      expect(t.lines, ['value']);
      expect(log, ['column', 'reader', 'created']);
      await t.pumpWidget(const Text('gone'));
      expect(log, ['column', 'reader', 'created', 'disposed value']);
    });

    testTwk('a value never read is neither created nor disposed of', (
      t,
    ) async {
      final log = <String>[];
      await t.pumpWidget(
        Provider<int>(
          create: (_) {
            log.add('created');
            return 1;
          },
          dispose: (_, _) => log.add('disposed'),
          child: const Text('no reader'),
        ),
      );
      await t.pumpWidget(const Text('gone'));
      expect(log, isEmpty);
    });

    testTwk('not lazy, creates it when it is placed in the tree', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        Provider<int>(
          create: (_) {
            log.add('created');
            return 1;
          },
          lazy: false,
          child: Logged('column', log, const []),
        ),
      );
      expect(log, ['created', 'column']);
    });

    testTwk('a new widget keeps the value create made', (t) async {
      var created = 0;
      Widget app(String text) => Provider<int>(
        create: (_) => ++created,
        child: Show(
          (context) => Text('$text ${context.watch<int>()}'),
        ),
      );
      await t.pumpWidget(app('a'), size: (4, 1));
      await t.pumpWidget(app('b'));
      expect(t.lines, ['b 1']);
      expect(created, 1);
    });

    testTwk('with a value, a new one not == rebuilds the widgets that watch '
        'it, not those that read it', (t) async {
      final log = <String>[];
      // the same child each time: only the provider rebuilds it
      final child = Logged('column', log, [
        Built('watcher', log, (context) => Text('w${context.watch<int>()}')),
        Built('reader', log, (context) => Text('r${context.read<int>()}')),
      ]);
      await t.pumpWidget(Provider.value(value: 1, child: child), size: (4, 2));
      expect(t.lines, ['w1', 'r1']);
      log.clear();
      await t.pumpWidget(Provider.value(value: 1, child: child));
      expect(log, isEmpty);
      await t.pumpWidget(Provider.value(value: 2, child: child));
      expect(t.lines, ['w2', 'r1']);
      expect(log, ['watcher']);
    });

    testTwk('with a value, updateShouldNotify says whether a new one '
        'rebuilds the widgets that watch it', (t) async {
      final log = <String>[];
      final asked = <String>[];
      final child = Built(
        'watcher',
        log,
        (context) => Text('${context.watch<int>()}'),
      );
      Widget app(int value) => Provider.value(
        value: value,
        updateShouldNotify: (previous, current) {
          asked.add('$previous>$current');
          return current.isEven;
        },
        child: child,
      );
      await t.pumpWidget(app(0), size: (4, 1));
      log.clear();
      await t.pumpWidget(app(1));
      expect(t.lines, ['0']);
      expect(log, isEmpty);
      await t.pumpWidget(app(2));
      expect(t.lines, ['2']);
      expect(log, ['watcher']);
      expect(asked, ['0>1', '1>2']);
    });

    testTwk('a widget whose last build did not watch is no longer rebuilt '
        'by a new value', (t) async {
      final log = <String>[];
      final watch = ValueNotifier(true);
      final child = ValueListenableBuilder(
        valueListenable: watch,
        builder: (context, watching, _) => Built(
          'built',
          log,
          (context) => Text(
            watching ? '${context.watch<int>()}' : '${context.read<int>()}',
          ),
        ),
      );
      await t.pumpWidget(Provider.value(value: 1, child: child), size: (4, 1));
      await t.act(() => watch.value = false);
      log.clear();
      await t.pumpWidget(Provider.value(value: 2, child: child));
      expect(log, isEmpty);
      expect(t.lines, ['1']);
    });

    testTwk('the nearest provider of a type hides those above it; create '
        'finds the one above its own', (t) async {
      await t.pumpWidget(
        Provider.value(
          value: 1,
          child: Provider<int>(
            create: (context) => context.read<int>() + 10,
            child: Show(
              (context) => Text('${context.read<int>()}'),
            ),
          ),
        ),
        size: (4, 1),
      );
      expect(t.lines, ['11']);
    });

    testTwk('builder builds the child below the provider, handed the one '
        'given', (t) async {
      await t.pumpWidget(
        Provider.value(
          value: 7,
          builder: (context, child) => Row(
            children: [Text('${context.watch<int>()}:'), child!],
          ),
          child: const Text('child'),
        ),
        size: (8, 1),
      );
      expect(t.lines, ['7:child']);
    });

    testTwk('read, watch and select without a provider above are a '
        'ProviderNotFoundException naming the type and the widget; one of '
        'a nullable type is null', (t) async {
      await t.pumpWidget(const Text('alone'));
      final context = t.element(find.text('alone'));
      final notFound = throwsA(
        isA<ProviderNotFoundException>()
            .having((e) => e.valueType, 'valueType', int)
            .having((e) => e.widgetType, 'widgetType', Text)
            .having(
              (e) => '$e',
              'message',
              startsWith(
                'Error: Could not find the correct Provider<int> above this '
                'Text Widget',
              ),
            ),
      );
      expect(context.read<int>, notFound);
      expect(context.watch<int>, notFound);
      expect(() => context.select<int, int>((n) => n), notFound);
      expect(() => Provider.of<int>(context, listen: false), notFound);
      expect(context.read<int?>(), isNull);
    });

    testTwk('a Provider<int?> is found as an int, its null a '
        'ProviderNullException, read or selected; a Provider<int> as an '
        'int?', (t) async {
      await t.pumpWidget(
        Provider<int?>.value(
          value: null,
          child: Provider<String>.value(value: 's', child: const Text('x')),
        ),
      );
      final context = t.element(find.text('x'));
      expect(context.read<int?>(), isNull);
      expect(
        context.read<int>,
        throwsA(
          isA<ProviderNullException>().having(
            (e) => e.valueType,
            'valueType',
            int,
          ),
        ),
      );
      expect(
        () => context.select<int, int>((n) => n),
        throwsA(isA<ProviderNullException>()),
      );
      expect(context.read<String?>(), 's');
    });

    testTwk('create that depends on a provider is an error while asserts '
        'are on; reading one is not', (t) async {
      await t.pumpWidget(
        Provider.value(
          value: 'text',
          child: Provider<int>(
            create: (context) => context.watch<String>().length,
            child: Show(
              (context) => Text('${context.read<int>()}'),
            ),
          ),
        ),
        size: (10, 1),
      );
      expect(loggedErrors(t), [
        isA<AssertionError>().having(
          (e) => e.message,
          'message',
          contains('Tried to listen to an InheritedWidget'),
        ),
      ]);
    });

    testTwk('a value whose create threw is a StateError when read again', (
      t,
    ) async {
      final show = ValueNotifier(1);
      await t.pumpWidget(
        Provider<int>(
          create: (_) => throw const FormatException('boom'),
          child: ValueListenableBuilder(
            valueListenable: show,
            builder: (context, n, _) => Text('${context.read<int>()}'),
          ),
        ),
        size: (10, 1),
      );
      await t.act(() => show.value = 2);
      expect(loggedErrors(t), [
        isA<FormatException>(),
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('threw during the creation of its value'),
        ),
      ]);
    });

    testTwk('of a Listenable or a Stream is an error while asserts are on, '
        'unless debugCheckInvalidValueType is null', (t) async {
      expect(
        () => Provider.value(value: Counter(), child: const Text('')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Listenable/Stream (Counter)'),
          ),
        ),
      );
      await t.pumpWidget(
        Provider<Stream<int>>(
          create: (_) => const Stream.empty(),
          child: Show((context) {
            context.read<Stream<int>>();
            return const Text('read');
          }),
        ),
        size: (4, 1),
      );
      expect(loggedErrors(t), [isA<StateError>()]);
      final check = Provider.debugCheckInvalidValueType;
      addTearDown(() => Provider.debugCheckInvalidValueType = check);
      Provider.debugCheckInvalidValueType = null;
      expect(
        Provider.value(value: Counter(), child: const Text('')),
        isNotNull,
      );
    });

    testTwk('rebuilt with another constructor is an error while asserts are '
        'on', (t) async {
      await t.pumpWidget(
        Provider<int>(create: (_) => 1, child: const Text('x')),
      );
      await t.pumpWidget(Provider<int>.value(value: 1, child: const Text('x')));
      expect(loggedErrors(t), [
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('using a different constructor'),
        ),
      ]);
    });

    testTwk('outside a MultiProvider, without a child or a builder, is a '
        'StateError', (t) async {
      await t.pumpWidget(Provider<int>.value(value: 1));
      expect(loggedErrors(t), [isA<StateError>()]);
    });
  });

  group('InheritedProvider', () {
    testTwk('a dependency update made stays through the builds that do not '
        'call it', (t) async {
      final made = <Counter>[];
      // update depends on the int; the counter it makes rebuilds the
      // provider's dependents by its notifications, with no update
      final provider = InheritedProvider<Counter>(
        update: (context, _) {
          final counter = Counter(Provider.of<int>(context));
          made.add(counter);
          return counter;
        },
        startListening: (element, counter) {
          counter.addListener(element.markNeedsNotifyDependents);
          return () =>
              counter.removeListener(element.markNeedsNotifyDependents);
        },
        child: Show(
          (context) => Text('${context.watch<Counter>().count}'),
        ),
      );
      await t.pumpWidget(
        Provider.value(value: 1, child: provider),
        size: (4, 1),
      );
      expect(t.lines, ['1']);
      await t.act(made.last.increment);
      expect(t.lines, ['2']);
      await t.pumpWidget(Provider.value(value: 10, child: provider));
      expect(t.lines, ['10']);
      expect(made, hasLength(2));
    });
  });

  group('MultiProvider', () {
    testTwk('nests its providers, the first outermost; each finds those '
        'before it, and the child all of them', (t) async {
      await t.pumpWidget(
        MultiProvider(
          providers: [
            Provider.value(value: 2),
            Provider<String>(create: (context) => 'n${context.read<int>()}'),
            ChangeNotifierProvider(
              create: (context) => Counter(context.read<int>() * 3),
            ),
          ],
          child: Show(
            (context) => Text(
              '${context.watch<int>()} ${context.watch<String>()} '
              '${context.watch<Counter>().count}',
            ),
          ),
        ),
        size: (8, 1),
      );
      expect(t.lines, ['2 n2 6']);
    });

    testTwk('keeps the values of its providers across its builds, and gives '
        'them the new child', (t) async {
      var created = 0;
      // the same providers each time: only the MultiProvider gives them
      // the new child
      final providers = [Provider<int>(create: (_) => ++created)];
      Widget app(String text) => MultiProvider(
        providers: providers,
        child: Show(
          (context) => Text('$text${context.read<int>()}'),
        ),
      );
      await t.pumpWidget(app('a'), size: (4, 1));
      expect(t.lines, ['a1']);
      await t.pumpWidget(app('b'));
      expect(t.lines, ['b1']);
      expect(created, 1);
    });

    testTwk('builder builds the child below the providers; a MultiProvider '
        'nests in another', (t) async {
      await t.pumpWidget(
        MultiProvider(
          providers: [
            Provider.value(value: 1),
            MultiProvider(providers: [Provider.value(value: 'a')]),
          ],
          builder: (context, child) => Row(
            children: [
              Text('${context.watch<int>()}${context.watch<String>()}:'),
              child!,
            ],
          ),
          child: const Text('c'),
        ),
        size: (6, 1),
      );
      expect(t.lines, ['1a:c']);
    });

    testTwk('without a child or a builder is a StateError', (t) async {
      await t.pumpWidget(MultiProvider(providers: [Provider.value(value: 1)]));
      expect(loggedErrors(t), [isA<StateError>()]);
    });
  });
}
