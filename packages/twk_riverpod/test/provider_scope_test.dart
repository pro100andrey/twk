// ProviderScope and UncontrolledProviderScope: the container's life, a
// scope below another overriding providers for its subtree, overrides
// updated, and a new container's providers watched in place of the old.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_riverpod/twk_riverpod.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

final name = Provider<String>((ref) => 'outer');

void main() {
  group('ProviderScope', () {
    testTwk('creates a container when it is placed in the tree and disposes '
        'it when it leaves', (t) async {
      final log = <String>[];
      final watched = Provider((ref) {
        ref.onDispose(() => log.add('disposed'));
        return 'v';
      });
      await t.pumpWidget(
        ProviderScope(child: Watching('w', watched, log)),
        size: (6, 1),
      );
      final container = containerOf(t);
      await t.pumpWidget(const Text('gone'));
      expect(log, ['w', 'disposed']);
      expect(() => container.read(watched), throwsStateError);
    });

    testTwk('one below another overrides providers for its subtree; those '
        'it does not override are shared with the scope above', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        ProviderScope(
          child: Logged('column', log, [
            Watching('name', name, log),
            Watching('a', a, log),
            ProviderScope(
              overrides: [name.overrideWithValue('inner')],
              child: Logged('inner', log, [
                Watching('name', name, log),
                Watching('a', a, log),
              ]),
            ),
          ]),
        ),
        size: (12, 4),
      );
      expect(t.lines, ['name: outer', 'a: 0', 'name: inner', 'a: 0']);
      final inner = ProviderScope.containerOf(
        t.element(find.text('name: inner')),
        listen: false,
      );
      expect(inner, isNot(same(containerOf(t))));
      await t.act(() => inner.read(a.notifier).increment());
      expect(t.lines, ['name: outer', 'a: 1', 'name: inner', 'a: 1']);
    });

    testTwk('a new widget with other values for its overrides rebuilds '
        'what watches them', (t) async {
      final log = <String>[];
      Widget app(String value) => ProviderScope(
        overrides: [name.overrideWithValue(value)],
        child: Watching('name', name, log),
      );
      await t.pumpWidget(app('one'), size: (10, 1));
      expect(t.lines, ['name: one']);
      await t.pumpWidget(app('two'));
      expect(t.lines, ['name: two']);
    });

    testTwk('containerOf without a scope above is a StateError naming the '
        'widget', (t) async {
      await t.pumpWidget(const Text('alone'));
      expect(
        () => ProviderScope.containerOf(t.element(find.text('alone'))),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            startsWith('no ProviderScope above Text'),
          ),
        ),
      );
    });
  });

  group('UncontrolledProviderScope', () {
    testTwk('gives its container to the widgets below it without disposing '
        'it; given another, they watch its providers instead', (t) async {
      final first = ProviderContainer.test();
      final second = ProviderContainer.test();
      final log = <String>[];
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: first,
          child: Watching('a', a, log),
        ),
        size: (6, 1),
      );
      await t.act(() => first.read(a.notifier).increment());
      expect(t.lines, ['a: 1']);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: second,
          child: Watching('a', a, log),
        ),
      );
      expect(t.lines, ['a: 0']);
      log.clear();
      await t.act(() => first.read(a.notifier).increment());
      expect(log, isEmpty);
      await t.act(() => second.read(a.notifier).increment());
      expect(t.lines, ['a: 1']);
      await t.pumpWidget(const Text('gone'));
      expect(first.read(a), 2);
    });
  });
}
