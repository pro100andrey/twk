// The hooks of a build's own state: useState, useEffect, useMemoized,
// useRef, useCallback and useValueChanged, each through mounting,
// rebuilding with the same and with other keys, and unmounting.
import 'package:test/test.dart';
import 'package:twk/hooks.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'matchers.dart';

void main() {
  testTwk('useState is the notifier of the first build, whose changes '
      'rebuild the element, and is disposed with it', (t) async {
    final notifiers = <ValueNotifier<int>>[];
    var builds = 0;
    Widget counting(int initial) => HookBuilder(
      builder: (context) {
        builds++;
        final count = useState(initial);
        notifiers.add(count);
        return Text('${count.value}');
      },
    );
    await t.pumpWidget(counting(1), size: (10, 1));
    expect(t.lines, ['1']);
    notifiers.last.value = 5;
    await t.pump();
    expect(t.lines, ['5']);
    expect(builds, 2);
    await t.pumpWidget(counting(9));
    expect(t.lines, ['5']);
    expect(notifiers.toSet(), hasLength(1));
    // an equal value notifies nothing, and rebuilds nothing
    notifiers.last.value = 5;
    await t.pump();
    expect(builds, 3);
    await t.pumpWidget(const Text('gone'));
    expect(notifiers.last, isDisposed);
  });

  testTwk('useEffect runs its effect in the first build and cleans up when '
      'unmounted; with keys again where they change, without in every '
      'build, the last cleanup first', (t) async {
    final log = <String>[];
    Widget effects(int key) => HookBuilder(
      builder: (context) {
        useEffect(() {
          log.add('keyed $key');
          return () => log.add('clean keyed $key');
        }, [key]);
        useEffect(() {
          log.add('every $key');
          return () => log.add('clean every $key');
        });
        useEffect(() {
          log.add('once $key');
          return null;
        }, const []);
        return const Text('x');
      },
    );
    await t.pumpWidget(effects(1), size: (10, 1));
    expect(log, ['keyed 1', 'every 1', 'once 1']);
    log.clear();
    await t.pumpWidget(effects(1));
    expect(log, ['clean every 1', 'every 1']);
    log.clear();
    await t.pumpWidget(effects(2));
    expect(log, ['clean keyed 1', 'keyed 2', 'clean every 1', 'every 2']);
    log.clear();
    await t.pumpWidget(const Text('gone'));
    expect(log, ['clean every 2', 'clean keyed 2']);
  });

  testTwk('useMemoized keeps the value of the first build until the keys '
      'change; without keys for good', (t) async {
    final made = <String>[];
    final seen = <(Object, Object)>[];
    Widget memo(int key) => HookBuilder(
      builder: (context) {
        final keyed = useMemoized(() {
          made.add('keyed $key');
          return Object();
        }, [key]);
        final kept = useMemoized(() {
          made.add('kept $key');
          return Object();
        });
        seen.add((keyed, kept));
        return const Text('x');
      },
    );
    await t.pumpWidget(memo(1), size: (10, 1));
    await t.pumpWidget(memo(1));
    expect(made, ['keyed 1', 'kept 1']);
    expect(seen[1], seen[0]);
    await t.pumpWidget(memo(2));
    expect(made, ['keyed 1', 'kept 1', 'keyed 2']);
    expect(seen[2].$1, isNot(same(seen[1].$1)));
    expect(seen[2].$2, same(seen[1].$2));
  });

  testTwk('useRef is the same box in every build, whose value changes '
      'rebuild nothing', (t) async {
    final refs = <ObjectRef<int>>[];
    var builds = 0;
    Widget ref() => HookBuilder(
      builder: (context) {
        builds++;
        refs.add(useRef(0));
        return const Text('x');
      },
    );
    await t.pumpWidget(ref(), size: (10, 1));
    refs.last.value = 3;
    await t.pump();
    expect(builds, 1);
    await t.pumpWidget(ref());
    expect(refs, hasLength(2));
    expect(refs[1], same(refs[0]));
    expect(refs[1].value, 3);
  });

  test('a ref shows what it holds', () {
    expect('${ObjectRef(3)}', 'ObjectRef(3)');
    expect('${ObjectRef<String?>(null)}', 'ObjectRef(null)');
  });

  testTwk('useCallback keeps the function of the first build until the keys '
      'change', (t) async {
    final callbacks = <int Function()>[];
    Widget callback(int key) => HookBuilder(
      builder: (context) {
        callbacks.add(useCallback(() => key, [key]));
        return const Text('x');
      },
    );
    await t.pumpWidget(callback(1), size: (10, 1));
    await t.pumpWidget(callback(1));
    expect(callbacks[1], same(callbacks[0]));
    await t.pumpWidget(callback(2));
    expect(callbacks[2](), 2);
  });

  testTwk('useValueChanged is null at first, then what its callback returned '
      'the last time the value changed', (t) async {
    final calls = <(int, String?)>[];
    final results = <String?>[];
    Widget changed(int value) => HookBuilder(
      builder: (context) {
        results.add(
          useValueChanged<int, String>(value, (old, result) {
            calls.add((old, result));
            return '$old>$value';
          }),
        );
        return const Text('x');
      },
    );
    await t.pumpWidget(changed(1), size: (10, 1));
    await t.pumpWidget(changed(1));
    await t.pumpWidget(changed(2));
    await t.pumpWidget(changed(2));
    await t.pumpWidget(changed(3));
    expect(results, [null, null, '1>2', '1>2', '2>3']);
    expect(calls, [(1, null), (2, '1>2')]);
  });
}
