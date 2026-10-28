// ConsumerWidget, Consumer and ConsumerStatefulWidget: what a build
// watches rebuilds it and nothing else, what it no longer watches does
// not, listeners fire, and what a widget subscribed to is let go when it
// leaves the tree.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_riverpod/twk_riverpod.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

void main() {
  group('ConsumerWidget', () {
    testTwk('shows what it watches and is built again when it changes, '
        'once for any number of changes; those that watch other providers '
        'and the widgets around it are not', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        ProviderScope(
          child: Logged('column', log, [
            Watching('a', a, log),
            Watching('b', b, log),
          ]),
        ),
        size: (10, 2),
      );
      expect(t.lines, ['a: 0', 'b: 0']);
      expect(log, ['column', 'a', 'b']);
      log.clear();
      await t.act(() {
        increment(t, a);
        increment(t, a);
      });
      expect(t.lines, ['a: 2', 'b: 0']);
      expect(log, ['a']);
      log.clear();
      await t.act(() => increment(t, b));
      expect(t.lines, ['a: 2', 'b: 1']);
      expect(log, ['b']);
    });

    testTwk('a provider watched through select rebuilds it only when what '
        'it selects changes', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        ProviderScope(child: Watching('big', a.select((n) => n > 1), log)),
        size: (12, 1),
      );
      expect(t.lines, ['big: false']);
      log.clear();
      await t.act(() => increment(t, a));
      expect(log, isEmpty);
      await t.act(() => increment(t, a));
      expect(t.lines, ['big: true']);
      expect(log, ['big']);
    });

    testTwk('a provider that watches another is built again first, then '
        'the widgets that watch it', (t) async {
      final doubled = Provider((ref) => ref.watch(a) * 2);
      final log = <String>[];
      await t.pumpWidget(
        ProviderScope(child: Watching('doubled', doubled, log)),
        size: (12, 1),
      );
      expect(t.lines, ['doubled: 0']);
      log.clear();
      await t.act(() => increment(t, a));
      await t.pump();
      expect(t.lines, ['doubled: 2']);
      expect(log, ['doubled']);
    });

    testTwk('a provider its last build did not watch no longer rebuilds '
        'it', (t) async {
      final useB = NotifierProvider<Toggle, bool>(Toggle.new);
      final log = <String>[];
      await t.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              log.add('built');
              final provider = ref.watch(useB) ? b : a;
              return Text('${ref.watch(provider)}');
            },
          ),
        ),
        size: (4, 1),
      );
      final container = containerOf(t);
      await t.act(() => container.read(useB.notifier).flip());
      log.clear();
      await t.act(() => increment(t, a));
      expect(log, isEmpty);
      await t.act(() => increment(t, b));
      expect(t.lines, ['1']);
      expect(log, ['built']);
    });

    testTwk('lets go of what it watched when it leaves the tree: a provider '
        'disposed automatically is disposed', (t) async {
      final log = <String>[];
      final watched = Provider.autoDispose((ref) {
        ref.onDispose(() => log.add('disposed'));
        return 'v';
      });
      await t.pumpWidget(
        ProviderScope(child: Watching('w', watched, log)),
        size: (6, 1),
      );
      expect(t.lines, ['w: v']);
      final container = containerOf(t);
      await t.pumpWidget(
        const ProviderScope(child: Text('gone')),
      );
      expect(t.lines.first, 'gone');
      expect(log, ['w', 'disposed']);
      expect(container.exists(watched), isFalse);
    });

    testTwk('its ref is unusable once it left the tree: a StateError', (
      t,
    ) async {
      late WidgetRef kept;
      await t.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              kept = ref;
              return Text('${ref.watch(a)}');
            },
          ),
        ),
      );
      expect(kept.read(a), 0);
      await t.pumpWidget(const ProviderScope(child: Text('gone')));
      expect(() => kept.read(a), throwsStateError);
    });

    testTwk('invalidate builds the provider again before it is next '
        'read, and its watchers with it', (t) async {
      final log = <String>[];
      var builds = 0;
      final counted = Provider((ref) => ++builds);
      await t.pumpWidget(
        ProviderScope(child: Watching('c', counted, log)),
        size: (6, 1),
      );
      expect(t.lines, ['c: 1']);
      await t.act(() => containerOf(t).invalidate(counted));
      await t.pump();
      expect(t.lines, ['c: 2']);
    });
  });

  group('WidgetRef', () {
    testTwk("its context is the widget's, and exists, refresh and "
        'invalidate act on the container of its scope', (t) async {
      var builds = 0;
      final counted = Provider((ref) => ++builds);
      late WidgetRef kept;
      final consumer = Consumer(
        builder: (context, ref, _) {
          kept = ref;
          return const Text('x');
        },
      );
      await t.pumpWidget(ProviderScope(child: consumer), size: (6, 1));
      expect(kept.context.widget, same(consumer));
      expect(kept.exists(counted), isFalse);
      expect(kept.read(counted), 1);
      expect(kept.exists(counted), isTrue);
      expect(kept.refresh(counted), 2);
      kept.invalidate(counted);
      expect(containerOf(t).read(counted), 3);
    });

    testTwk('listen outside the build fails, pointing to listenManual', (
      t,
    ) async {
      late WidgetRef kept;
      await t.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              kept = ref;
              return const Text('x');
            },
          ),
        ),
        size: (6, 1),
      );
      expect(
        () => kept.listen(a, (_, _) {}),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            'ref.listen() outside the build of Consumer: ref.listenManual() '
                'listens from elsewhere',
          ),
        ),
      );
    });
  });

  group('Consumer', () {
    testTwk('builds again only its builder, not the widgets around it nor '
        'the child it hands to the builder', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        ProviderScope(
          child: Logged('column', log, [
            Consumer(
              builder: (context, ref, child) {
                log.add('builder');
                return Logged('row', log, [Text('${ref.watch(a)}'), child!]);
              },
              child: Logged('child', log, const []),
            ),
          ]),
        ),
        size: (4, 1),
      );
      expect(log, ['column', 'builder', 'row', 'child']);
      log.clear();
      await t.act(() => increment(t, a));
      expect(t.lines, ['1']);
      expect(log, ['builder', 'row']);
    });
  });

  group('WidgetRef.listen', () {
    testTwk('calls the listener with the value before and the one after on '
        'each change, not on builds, until the widget leaves the tree', (
      t,
    ) async {
      final heard = <String>[];
      final log = <String>[];
      Widget app({required bool shown}) => ProviderScope(
        child: Logged('column', log, [
          Watching('b', b, log),
          if (shown)
            Consumer(
              builder: (context, ref, _) {
                ref.listen(a, (previous, next) => heard.add('$previous>$next'));
                return Text('${ref.watch(b)}');
              },
            ),
        ]),
      );
      await t.pumpWidget(app(shown: true), size: (6, 2));
      await t.act(() => increment(t, a));
      expect(heard, ['0>1']);
      await t.act(() => increment(t, b));
      await t.act(() => increment(t, a));
      expect(heard, ['0>1', '1>2']);
      await t.pumpWidget(app(shown: false));
      await t.act(() => increment(t, a));
      expect(heard, ['0>1', '1>2']);
    });
  });

  group('ConsumerStatefulWidget', () {
    testTwk('its state has the ref from initState on: listenManual there '
        'listens until the widget leaves the tree, read reads', (t) async {
      final heard = <String>[];
      await t.pumpWidget(
        ProviderScope(child: Listening(heard)),
        size: (6, 1),
      );
      expect(heard, ['read 0', 'null>0']);
      expect(t.lines, ['a: 0']);
      await t.act(() => increment(t, a));
      expect(heard, ['read 0', 'null>0', '0>1']);
      expect(t.lines, ['a: 1']);
      final container = containerOf(t);
      await t.pumpWidget(const ProviderScope(child: Text('gone')));
      container.read(a.notifier).increment();
      expect(heard, ['read 0', 'null>0', '0>1', 'disposed 1']);
    });
  });
}

final class Toggle extends Notifier<bool> {
  @override
  bool build() => false;

  void flip() => state = !state;
}

/// Listens to [a] from its initState, [heard] told of each change.
final class Listening extends ConsumerStatefulWidget {
  const Listening(this.heard, {super.key});

  final List<String> heard;

  @override
  ConsumerState<Listening> createState() => _ListeningState();
}

final class _ListeningState extends ConsumerState<Listening> {
  late final ProviderSubscription<int> _sub;

  @override
  void initState() {
    super.initState();
    widget.heard.add('read ${ref.read(a)}');
    _sub = ref.listenManual(
      a,
      (previous, next) => widget.heard.add('$previous>$next'),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    widget.heard.add('disposed ${_sub.read()}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('a: ${ref.watch(a)}');
}
