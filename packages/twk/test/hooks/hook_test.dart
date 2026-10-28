// Hooks over elements: the states a build's hooks keep, updated and
// disposed with the element, created anew when their keys change, moved
// with a GlobalKey; the rules a build keeps, broken with errors that name
// the hooks; and the descriptions of the states.
import 'package:test/test.dart';
import 'package:twk/hooks.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A hook whose state logs what it is told to [log], by [name].
final class Logged extends Hook<String> {
  const Logged(this.name, this.log, {super.keys, this.disposeThrows = false});

  final String name;
  final List<String> log;
  final bool disposeThrows;

  @override
  LoggedState createState() => LoggedState();
}

final class LoggedState extends HookState<String, Logged> {
  @override
  void initHook() {
    super.initHook();
    hook.log.add('init ${hook.name}');
  }

  @override
  void didUpdateHook(Logged oldHook) {
    super.didUpdateHook(oldHook);
    hook.log.add('update ${oldHook.name} to ${hook.name}');
  }

  @override
  String build(BuildContext context) {
    hook.log.add('build ${hook.name}');
    return hook.name;
  }

  @override
  void deactivate() {
    hook.log.add('deactivate ${hook.name}');
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    hook.log.add('activate ${hook.name}');
  }

  @override
  void dispose() {
    hook.log.add('dispose ${hook.name}');
    super.dispose();
    if (hook.disposeThrows) {
      throw StateError('${hook.name} failed to dispose');
    }
  }
}

String useLogged(String name, List<String> log, {List<Object?>? keys}) =>
    use(Logged(name, log, keys: keys));

/// A hook whose states are kept in [states] as they are created.
final class Probe extends Hook<void> {
  const Probe(this.states);

  final List<ProbeState> states;

  @override
  ProbeState createState() => ProbeState();
}

final class ProbeState extends HookState<void, Probe> {
  @override
  void initHook() {
    super.initHook();
    hook.states.add(this);
  }

  @override
  void build(BuildContext context) {}
}

/// A hook whose state calls [useState] as it is created.
final class Nested extends Hook<void> {
  const Nested();

  @override
  NestedState createState() => NestedState();
}

final class NestedState extends HookState<void, Nested> {
  @override
  void initHook() {
    super.initHook();
    useState(0);
  }

  @override
  void build(BuildContext context) {}
}

/// A stateful widget whose state logs its life to [log] and builds with a
/// hook that does.
final class Stateful extends StatefulHookWidget {
  const Stateful(this.log, {super.key});

  final List<String> log;

  @override
  State<Stateful> createState() => StatefulState();
}

final class StatefulState extends State<Stateful> {
  @override
  void initState() {
    super.initState();
    widget.log.add('initState');
  }

  @override
  void deactivate() {
    widget.log.add('deactivate state');
    super.deactivate();
  }

  @override
  void dispose() {
    widget.log.add('dispose state');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(useLogged('a', widget.log));
}

/// A stateful hook widget whose state calls a hook in its initState.
final class HookInInitState extends StatefulHookWidget {
  const HookInInitState({super.key});

  @override
  State<HookInInitState> createState() => _HookInInitStateState();
}

final class _HookInInitStateState extends State<HookInInitState> {
  @override
  void initState() {
    super.initState();
    useState(0);
  }

  @override
  Widget build(BuildContext context) => const Text('x');
}

/// A counter of key presses: Up counts.
final class Counter extends HookWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useState(0);
    return KeyBindings({
      'up': () => count.value++,
    }, child: Text('count ${count.value}'));
  }
}

/// The errors the app logged, as the messages of the assertions.
List<Object?> errors(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level == LogLevel.error)
      switch (r.error) {
        final AssertionError e => e.message,
        final StateError e => e.message,
        final e => e,
      },
];

const rule =
    'a build calls the same hooks in the same order every time, none in a '
    'condition or a loop whose course changes';

void main() {
  testTwk("a HookWidget's state changes rebuild it", (t) async {
    await t.pumpWidget(const Counter(), size: (10, 1));
    expect(t.lines, ['count 0']);
    await t.press('up up');
    await t.pump();
    expect(t.lines, ['count 2']);
  });

  testTwk('a build keeps the states of its hooks, each updated with the '
      'hook of every later build, and disposes them when it is unmounted, '
      'the last first', (t) async {
    final log = <String>[];
    var name = 'a';
    Widget logged() => HookBuilder(
      builder: (context) =>
          Text('${useLogged(name, log)} ${useLogged('b', log)}'),
    );
    await t.pumpWidget(logged(), size: (10, 1));
    expect(t.lines, ['a b']);
    expect(log, ['init a', 'build a', 'init b', 'build b']);
    log.clear();
    name = 'c';
    await t.pumpWidget(logged());
    expect(t.lines, ['c b']);
    expect(log, ['update a to c', 'build c', 'update b to b', 'build b']);
    log.clear();
    await t.pumpWidget(const Text('gone'));
    expect(log, ['deactivate b', 'deactivate c', 'dispose b', 'dispose c']);
  });

  testTwk('a hook given again, the very same, is not updated', (t) async {
    final log = <String>[];
    final hook = Logged('a', log);
    Widget same() => HookBuilder(
      builder: (context) {
        use(hook);
        return const Text('x');
      },
    );
    await t.pumpWidget(same(), size: (10, 1));
    log.clear();
    await t.pumpWidget(same());
    expect(log, ['build a']);
  });

  testTwk('a hook whose keys differ from those of the last build gets a new '
      'state, the old one disposed first; equal keys keep it', (t) async {
    final log = <String>[];
    Widget keyed(Object? key, String name) => HookBuilder(
      builder: (context) {
        useLogged(name, log, keys: [key, 1]);
        return const Text('x');
      },
    );
    await t.pumpWidget(keyed(1, 'a'), size: (10, 1));
    expect(log, ['init a', 'build a']);
    log.clear();
    await t.pumpWidget(keyed(1, 'b'));
    expect(log, ['update a to b', 'build b']);
    log.clear();
    await t.pumpWidget(keyed(2, 'c'));
    expect(log, ['dispose b', 'init c', 'build c']);
    log.clear();
    // a NaN is identical to itself
    await t.pumpWidget(keyed(double.nan, 'd'));
    await t.pumpWidget(keyed(double.nan, 'e'));
    expect(log, ['dispose c', 'init d', 'build d', 'update d to e', 'build e']);
    log.clear();
    await t.pumpWidget(const Text('gone'));
    expect(log, ['deactivate e', 'dispose e']);
  });

  test('keys are equal when both are null, or as long and equal item by '
      'item', () {
    expect(Hook.keysEqual(null, null), isTrue);
    expect(Hook.keysEqual(null, const []), isFalse);
    expect(Hook.keysEqual(const [], const []), isTrue);
    expect(Hook.keysEqual([1, 'a'], [1, 'a']), isTrue);
    expect(Hook.keysEqual([1], [1, 2]), isFalse);
    expect(Hook.keysEqual([1], [2]), isFalse);
  });

  testTwk("a StatefulHookWidget's state builds with hooks, which are "
      'deactivated and disposed before it', (t) async {
    final log = <String>[];
    await t.pumpWidget(Stateful(log), size: (10, 1));
    expect(t.lines, ['a']);
    expect(log, ['initState', 'init a', 'build a']);
    log.clear();
    await t.pumpWidget(const Text('gone'));
    expect(log, [
      'deactivate a',
      'deactivate state',
      'dispose a',
      'dispose state',
    ]);
  });

  testTwk('a widget a GlobalKey moves keeps the states of its hooks, '
      'deactivated and activated on the way', (t) async {
    final log = <String>[];
    final key = GlobalKey();
    late ValueNotifier<int> count;
    Widget moved() => HookBuilder(
      key: key,
      builder: (context) {
        count = useState(0);
        return Text('${useLogged('a', log)}${count.value}');
      },
    );
    Widget tree({required bool left}) => Row(
      children: [
        SizedBox(width: 5, child: left ? moved() : const Text('-')),
        SizedBox(width: 5, child: left ? const Text('-') : moved()),
      ],
    );
    await t.pumpWidget(tree(left: true), size: (10, 1));
    count.value = 3;
    await t.pump();
    expect(t.lines, ['a3   -']);
    log.clear();
    await t.pumpWidget(tree(left: false));
    expect(t.lines, ['-    a3']);
    expect(log, ['deactivate a', 'activate a', 'update a to a', 'build a']);
  });

  testTwk("a hook whose dispose throws leaves the others' disposed, and the "
      'error goes on once the element is unmounted', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      HookBuilder(
        builder: (context) {
          useLogged('a', log);
          use(Logged('b', log, disposeThrows: true));
          useLogged('c', log);
          return const Text('x');
        },
      ),
      size: (10, 1),
    );
    log.clear();
    await expectLater(
      t.pumpWidget(const Text('gone')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'b failed to '
              'dispose',
        ),
      ),
    );
    expect(log, [
      'deactivate c',
      'deactivate b',
      'deactivate a',
      'dispose c',
      'dispose b',
      'dispose a',
    ]);
  });

  testTwk('a state is mounted from its first use until it is disposed, and '
      'is named by its hook', (t) async {
    final states = <ProbeState>[];
    await t.pumpWidget(
      HookBuilder(
        builder: (context) {
          use(Probe(states));
          return const Text('x');
        },
      ),
      size: (10, 1),
    );
    final state = states.single;
    expect(state.mounted, isTrue);
    expect('$state', 'the state of Probe');
    await t.pumpWidget(const Text('y'));
    expect(state.mounted, isFalse);
  });

  testTwk('useContext is the context of the build', (t) async {
    BuildContext? used;
    BuildContext? built;
    await t.pumpWidget(
      HookBuilder(
        builder: (context) {
          used = useContext();
          built = context;
          return const Text('x');
        },
      ),
    );
    expect(used, same(built));
  });

  testTwk("an element's description has its hooks' states", (t) async {
    await t.pumpWidget(
      HookBuilder(
        builder: (context) {
          useState(3);
          useValueNotifier('a');
          return const Text('x');
        },
      ),
    );
    final description = t
        .element(find.byType(HookBuilder))
        .describe()
        .toStringDeep();
    expect(description, contains('useState<int>: 3'));
    expect(description, contains('useValueNotifier<String>: "a"'));
  });

  group('the rules', () {
    test('a hook called outside a build is a StateError naming it', () {
      expect(
        () => useState(0),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'useState<int> called outside a build: hooks are called by the '
                "build of a HookWidget, a StatefulHookWidget's state or a "
                'HookBuilder',
          ),
        ),
      );
      expect(
        useContext,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            startsWith('useContext called outside a build'),
          ),
        ),
      );
    });

    testTwk("a hook called by a state's initState fails the build", (
      t,
    ) async {
      await t.pumpWidget(const HookInInitState());
      expect(errors(t), [startsWith('useState<int> called outside a build')]);
    });

    testTwk('a build that calls another hook in the place of one fails, '
        'naming both', (t) async {
      var swap = false;
      Widget swapping() => HookBuilder(
        key: const Key('k'),
        builder: (context) {
          useState(0);
          if (swap) {
            useMemoized(() => 0);
          } else {
            useState(0);
          }
          return const Text('x');
        },
      );
      await t.pumpWidget(swapping(), size: (10, 1));
      swap = true;
      await t.pumpWidget(swapping());
      const message =
          "HookBuilder-[<'k'>] called useMemoized<int> as its hook 2, where "
          'its last build called useState<int>: $rule';
      expect(errors(t), [message]);
    });

    testTwk('a build that calls more hooks than the last fails, naming the '
        'first of them', (t) async {
      var more = false;
      Widget growing() => HookBuilder(
        builder: (context) {
          useState(0);
          if (more) {
            useRef('');
          }
          return const Text('x');
        },
      );
      await t.pumpWidget(growing(), size: (10, 1));
      more = true;
      await t.pumpWidget(growing());
      const message =
          'HookBuilder called useRef<String> as its hook 2, which its last '
          'build did not call: $rule';
      expect(errors(t), [message]);
    });

    testTwk('a build that calls fewer hooks than the last fails, naming the '
        'first it left out', (t) async {
      var fewer = false;
      Widget shrinking() => HookBuilder(
        builder: (context) {
          useState(0);
          if (!fewer) {
            useEffect(() => null);
          }
          return const Text('x');
        },
      );
      await t.pumpWidget(shrinking(), size: (10, 1));
      fewer = true;
      await t.pumpWidget(shrinking());
      const message =
          'HookBuilder stopped calling hooks before its hook 2, useEffect, '
          'which its last build called: $rule';
      expect(errors(t), [message]);
    });

    testTwk('a build that threw before its last hooks may call them after', (
      t,
    ) async {
      var fail = true;
      final log = <String>[];
      Widget failing() => HookBuilder(
        builder: (context) {
          useLogged('a', log);
          if (fail) {
            throw StateError('not now');
          }
          useLogged('b', log);
          return const Text('x');
        },
      );
      await t.pumpWidget(failing(), size: (10, 1));
      expect(errors(t), ['not now']);
      fail = false;
      await t.pumpWidget(failing());
      expect(errors(t), ['not now']);
      expect(log, [
        'init a',
        'build a',
        'update a to a',
        'build a',
        'init b',
        'build b',
      ]);
    });

    testTwk('a build that threw after its hooks, then one that calls fewer, '
        'disposes those it left', (t) async {
      var fail = true;
      final log = <String>[];
      Widget failing() => HookBuilder(
        builder: (context) {
          useLogged('a', log);
          if (fail) {
            useLogged('b', log);
            throw StateError('not now');
          }
          return const Text('x');
        },
      );
      await t.pumpWidget(failing(), size: (10, 1));
      fail = false;
      log.clear();
      await t.pumpWidget(failing());
      expect(errors(t), ['not now']);
      expect(log, ['update a to a', 'build a', 'dispose b']);
    });

    testTwk('a hook called by another hook fails, naming both', (t) async {
      await t.pumpWidget(
        HookBuilder(
          builder: (context) {
            use(const Nested());
            return const Text('x');
          },
        ),
        size: (10, 1),
      );
      const message =
          'useState<int> called by Nested: hooks are called by builds, not by '
          'other hooks';
      expect(errors(t), [message]);
    });
  });
}
