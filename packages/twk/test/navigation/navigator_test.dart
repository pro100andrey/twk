// The Navigator: routes pushed and popped with results; a covered route's
// state kept while it is not laid out, painted or hit; the focus taken by
// a route pushed and given back when it is popped; named routes with
// arguments; the back key through the key layers; pushReplacement,
// popUntil and removeRoute; the routes' futures when the navigator goes;
// its Overlay; its height in the inline mode.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A [Focus] shown as its [label], after `>` while it has the primary
/// focus and ` ` while not.
final class Field extends StatelessWidget {
  const Field(this.label, {this.autofocus = false, super.key});

  final String label;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: autofocus,
    debugLabel: label,
    child: _Mark(label),
  );
}

final class _Mark extends StatelessWidget {
  const _Mark(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text('${Focus.of(context).hasPrimaryFocus ? '>' : ' '}$label');
}

/// A screen titled [title] with [fields] under it; each key of [keys] does
/// what its callback does with the screen's context.
final class Screen extends StatelessWidget {
  const Screen(
    this.title, {
    this.keys = const {},
    this.fields = const [],
    super.key,
  });

  final String title;
  final Map<String, void Function(BuildContext context)> keys;
  final List<Widget> fields;

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      for (final MapEntry(:key, :value) in keys.entries)
        key: () => value(context),
    },
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(title), ...fields],
    ),
  );
}

/// A [Screen] pushed on the navigator above [context], its result added to
/// [results]; `x` pops it with `done`.
void pushScreen(
  BuildContext context,
  List<Object?> results,
  String title, {
  List<Widget> fields = const [],
  Map<String, void Function(BuildContext context)> keys = const {},
}) => unawaited(
  Navigator.push(
    context,
    PageRoute<String>(
      builder: (_) => Screen(
        title,
        fields: fields,
        keys: {'x': (context) => Navigator.pop(context, 'done'), ...keys},
      ),
    ),
  ).then(results.add),
);

/// The label of the node with the primary focus.
String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

/// Presses [key] and pumps a frame.
Future<void> press(TwkTester t, String key) async {
  await t.press(key);
  await t.pump();
}

/// The keys the layers on the key path handle now, as `key hint`.
List<String> activeKeys(TwkTester t) => [
  for (final key in t.binding.focusManager.activeKeys) '$key',
];

void main() {
  testTwk('push shows a route in front of the others, pop takes it off, '
      'its future completing with the result', (t) async {
    final results = <Object?>[];
    await t.pumpWidget(
      Navigator(
        home: Screen(
          'home',
          keys: {'n': (context) => pushScreen(context, results, 'detail')},
        ),
      ),
      size: (20, 3),
    );
    expect(t, matchesScreen('home'));
    await press(t, 'n');
    expect(t, matchesScreen('detail'));
    await press(t, 'x');
    expect(results, ['done']);
    expect(t, matchesScreen('home'));
  });

  testTwk('pop with a result not of the route type throws a TypeError and '
      'leaves it; pop on the first route throws a StateError', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    final results = <Object?>[];
    await t.pumpWidget(
      Navigator(key: navigator, home: const Text('home')),
      size: (20, 3),
    );
    final state = navigator.currentState!;
    expect(state.canPop(), isFalse);
    expect(
      state.pop,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'pop: the navigator keeps its first route; canPop tells whether '
              'there is one to pop',
        ),
      ),
    );
    final route = PageRoute<String>(builder: (_) => const Text('detail'));
    unawaited(state.push(route).then(results.add));
    await t.pump();
    expect(
      [state.canPop(), route.isCurrent, route.isFirst],
      [
        true,
        true,
        false,
      ],
    );
    expect(() => state.pop(42), throwsA(isA<TypeError>()));
    await t.pump();
    expect(t, matchesScreen('detail'));
    state.pop('ok');
    await t.pump();
    expect(results, ['ok']);
    expect([route.isActive, route.isCurrent], [false, false]);
    expect(t, matchesScreen('home'));
  });

  testTwk('a covered route keeps its state and builds, but is not laid '
      'out, painted or hit until it is in front again', (t) async {
    final log = <String>[];
    final taps = <String>[];
    final results = <Object?>[];
    await t.pumpWidget(
      Navigator(
        home: Screen(
          'home',
          keys: {'n': (context) => pushScreen(context, results, 'detail')},
          fields: [Ticking(log, taps)],
        ),
      ),
      size: (20, 4),
    );
    expect(t, matchesScreen('home\ntick 0'));
    expect(log, ['build 0', 'layout 0', 'paint 0']);
    await t.click(2, 1);
    await t.pump();
    expect(taps, ['tap 0']);
    log.clear();
    await press(t, 'n');
    expect(t, matchesScreen('detail'));
    expect(log, isEmpty);
    await t.pump(const Duration(seconds: 3));
    await t.click(2, 1);
    await t.pump();
    expect(log, ['build 1', 'build 2', 'build 3']);
    expect(taps, ['tap 0']);
    log.clear();
    await press(t, 'x');
    expect(t, matchesScreen('home\ntick 3'));
    expect(log, ['layout 3', 'paint 3']);
    await t.click(2, 1);
    await t.pump();
    expect(taps, ['tap 0', 'tap 3']);
  });

  testTwk('a route pushed takes the focus and keeps Tab in it; the routes '
      'under it cannot take it; popped, it gives it back where it was', (
    t,
  ) async {
    final results = <Object?>[];
    await t.pumpWidget(
      Navigator(
        home: Screen(
          'home',
          keys: {
            'n': (context) => pushScreen(
              context,
              results,
              'detail',
              fields: const [Field('c'), Field('e')],
            ),
          },
          fields: const [Field('a', autofocus: true), Field('b')],
        ),
      ),
      size: (20, 4),
    );
    expect(focused(t), 'a');
    await press(t, 'tab');
    expect(focused(t), 'b');
    final a = t.binding.focusManager.primaryFocus!.parent!.children.first;
    await press(t, 'n');
    expect(focused(t), 'route');
    await press(t, 'tab');
    expect(focused(t), 'c');
    await press(t, 'tab');
    await press(t, 'tab');
    expect(focused(t), 'c');
    expect(a.canRequestFocus, isFalse);
    a.requestFocus();
    expect(focused(t), 'c');
    await press(t, 'x');
    expect(results, ['done']);
    expect(focused(t), 'b');
    expect(t, matchesScreen('home\n a\n>b'));
  });

  testTwk('a route gives the focus back to what had it when it was pushed, '
      'outside the navigator too; a route under it removed hands it what '
      'it would have given back', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    PageRoute<void> screen(String title) =>
        PageRoute(builder: (_) => Screen(title, fields: [Field(title)]));
    await t.pumpWidget(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 6, child: Field('out', autofocus: true)),
          Expanded(
            child: Navigator(
              key: navigator,
              home: const Screen('home', fields: [Field('a')]),
            ),
          ),
        ],
      ),
      size: (20, 3),
    );
    final state = navigator.currentState!;
    expect(focused(t), 'out');
    unawaited(state.push(screen('one')));
    await t.pump();
    expect(focused(t), 'route');
    state.pop();
    await t.pump();
    expect(focused(t), 'out');
    final two = screen('two');
    unawaited(state.push(two));
    await t.pump();
    await press(t, 'tab');
    expect(focused(t), 'two');
    unawaited(state.push(screen('three')));
    await t.pump();
    state.removeRoute(two);
    await t.pump();
    expect(t, matchesScreen(' out  three\n       three'));
    state.pop();
    await t.pump();
    expect(focused(t), 'out');
    expect(t, matchesScreen('>out  home\n       a'));
  });

  testTwk('the first route takes the focus when nothing has it, so that '
      'its keys reach it', (t) async {
    final results = <Object?>[];
    await t.pumpWidget(
      Navigator(
        home: Screen(
          'home',
          keys: {'n': (context) => pushScreen(context, results, 'detail')},
        ),
      ),
      size: (20, 3),
    );
    expect(focused(t), '/');
    await press(t, 'n');
    expect(t, matchesScreen('detail'));
    await press(t, 'x');
    expect(focused(t), '/');
  });

  testTwk('named routes: home, routes, onGenerateRoute and onUnknownRoute '
      'make them, with their arguments; with none a StateError', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    final results = <Object?>[];
    await t.pumpWidget(
      Navigator(
        key: navigator,
        home: const Text('home'),
        routes: {
          '/item': (context) => Text('item ${Route.of(context).settings}'),
        },
        onGenerateRoute: (settings) => settings.name!.startsWith('/gen/')
            ? PageRoute<int>(
                builder: (_) => Text('gen ${settings.name}'),
                settings: settings,
              )
            : null,
        onUnknownRoute: (settings) => PageRoute<Object?>(
          builder: (_) => Text('unknown ${settings.name}'),
          settings: settings,
        ),
      ),
      size: (40, 3),
    );
    final state = navigator.currentState!;
    expect(t, matchesScreen('home'));
    unawaited(state.pushNamed<int>('/item', arguments: 7).then(results.add));
    await t.pump();
    expect(t, matchesScreen('item RouteSettings(/item, 7)'));
    state.pop(8);
    unawaited(state.pushNamed<int>('/gen/a').then(results.add));
    await t.pump();
    expect(t, matchesScreen('gen /gen/a'));
    state.pop(9);
    unawaited(state.pushNamed<String>('/nope').then(results.add));
    await t.pump();
    expect(t, matchesScreen('unknown /nope'));
    state.pop('no');
    await t.pump();
    expect(results, [8, 9, 'no']);

    await t.pumpWidget(
      Navigator(
        key: navigator,
        initialRoute: '/item',
        routes: {
          '/item': (context) => Text('item ${Route.of(context).settings}'),
        },
      ),
    );
    expect(t, matchesScreen('home'));
    await t.pumpWidget(
      Navigator(
        initialRoute: '/item',
        routes: {
          '/item': (context) => Text('item ${Route.of(context).settings}'),
        },
      ),
    );
    expect(t, matchesScreen('item RouteSettings(/item, null)'));
    final state2 = Navigator.of(
      t.binding.focusManager.primaryFocus!.context!,
    );
    expect(
      () => state2.pushNamed<void>('/nope'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Navigator: no route named "/nope": give it in routes, or make it '
              'in onGenerateRoute or onUnknownRoute',
        ),
      ),
    );
  });

  testTwk('the back key pops the route in front, after its own bindings; '
      'with none to pop it goes on past the navigator', (t) async {
    final log = <String>[];
    final results = <Object?>[];
    Widget app({String? backKey = 'escape'}) => KeyBindings(
      {
        'escape': () => log.add('app escape'),
        'q': () => log.add('app q'),
      },
      child: Navigator(
        backKey: backKey,
        home: Screen(
          'home',
          keys: {
            'n': (context) => pushScreen(context, results, 'detail'),
            'o': (context) => pushScreen(
              context,
              results,
              'own',
              keys: {'escape': (_) => log.add('own escape')},
            ),
          },
        ),
      ),
    );
    await t.pumpWidget(app(), size: (20, 3));
    expect(activeKeys(t), ['n', 'o', 'escape', 'q']);
    await press(t, 'escape');
    expect(log, ['app escape']);
    await press(t, 'n');
    expect(activeKeys(t), ['x', 'escape back', 'q']);
    await press(t, 'escape');
    expect(t, matchesScreen('home'));
    expect(results, [null]);
    expect(log, ['app escape']);
    await press(t, 'o');
    await press(t, 'escape');
    expect(t, matchesScreen('own'));
    expect(log, ['app escape', 'own escape']);
    await press(t, 'x');

    await t.pumpWidget(app(backKey: 'q'));
    await press(t, 'n');
    await press(t, 'escape');
    await press(t, 'q');
    expect(t, matchesScreen('home'));
    expect(log, ['app escape', 'own escape', 'app escape']);
    await press(t, 'q');
    expect(log, ['app escape', 'own escape', 'app escape', 'app q']);

    await t.pumpWidget(app(backKey: null));
    await press(t, 'n');
    await press(t, 'escape');
    expect(t, matchesScreen('detail'));
    expect(log.last, 'app escape');
  });

  testTwk('pushReplacement completes the route it replaces, which the new '
      'one pops back past; popUntil and removeRoute take routes off, the '
      'focus going back where it was before them', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    final results = <Object?>[];
    PageRoute<String> screen(String title, [String? name]) => PageRoute(
      builder: (_) => Screen(title, fields: [Field(title)]),
      settings: RouteSettings(name: name),
    );
    await t.pumpWidget(
      Navigator(
        key: navigator,
        home: const Screen('home', fields: [Field('a'), Field('b')]),
      ),
      size: (20, 3),
    );
    final state = navigator.currentState!;
    await press(t, 'tab');
    await press(t, 'tab');
    expect(focused(t), 'b');
    unawaited(state.push(screen('one')).then(results.add));
    await t.pump();
    await press(t, 'tab');
    expect(focused(t), 'one');
    unawaited(
      state
          .pushReplacement(screen('two'), result: 'replaced')
          .then(results.add),
    );
    await t.pump();
    expect(t, matchesScreen('two\n two'));
    expect(results, ['replaced']);
    state.pop('popped');
    await t.pump();
    expect(results, ['replaced', 'popped']);
    expect(focused(t), 'b');

    final three = screen('three', '/three');
    final four = screen('four');
    final five = screen('five');
    for (final route in [three, four, five]) {
      unawaited(state.push(route).then(results.add));
      await t.pump();
      await press(t, 'tab');
    }
    expect(focused(t), 'five');
    state.removeRoute(four, 'removed');
    await t.pump();
    expect(t, matchesScreen('five\n>five'));
    expect(results.last, 'removed');
    state.popUntil(Route.withName('/three'));
    await t.pump();
    expect(focused(t), 'three');
    state.popUntil((route) => false);
    await t.pump();
    expect(results, ['replaced', 'popped', 'removed', null, null]);
    expect(focused(t), 'b');
    expect(t, matchesScreen('home\n a\n>b'));
  });

  testTwk('a navigator built again builds its routes again, the first '
      'with the new home, those under the one in front too', (t) async {
    final results = <Object?>[];
    Widget app(String word) => Navigator(
      home: Screen(
        'home $word',
        keys: {
          'n': (context) => pushScreen(
            context,
            results,
            'detail',
            fields: [Builder(builder: (_) => Text(word))],
          ),
        },
      ),
    );
    await t.pumpWidget(app('one'), size: (20, 3));
    expect(t, matchesScreen('home one'));
    await t.pumpWidget(app('two'));
    expect(t, matchesScreen('home two'));
    await press(t, 'n');
    expect(t, matchesScreen('detail\ntwo'));
    await t.pumpWidget(app('three'));
    expect(t, matchesScreen('detail\ntwo'));
    await press(t, 'x');
    expect(t, matchesScreen('home three'));
  });

  testTwk('the routes complete with null when the navigator leaves the '
      'tree', (t) async {
    final results = <Object?>[];
    await t.pumpWidget(
      Navigator(
        home: Screen(
          'home',
          keys: {
            'n': (context) => pushScreen(
              context,
              results,
              'detail',
              keys: {'n': (context) => pushScreen(context, results, 'more')},
            ),
          },
        ),
      ),
    );
    await press(t, 'n');
    await press(t, 'n');
    expect(t, matchesScreen('more'));
    await t.pumpWidget(const Text('gone'));
    expect(results, [null, null]);
    expect(focused(t), 'root');
  });

  testTwk('the navigator holds an Overlay over its routes: their toasts '
      'show over them', (t) async {
    final results = <Object?>[];
    await t.pumpWidget(
      Navigator(
        home: Screen(
          'home',
          keys: {
            'n': (context) => pushScreen(
              context,
              results,
              'detail',
              keys: {'s': (context) => showToast(context, 'Saved')},
            ),
          },
        ),
      ),
      size: (20, 6),
    );
    await press(t, 'n');
    await press(t, 's');
    // slid in
    await t.pump(const Duration(milliseconds: 300));
    expect(
      t,
      matchesScreen('''
detail
        ▌
        ▌ Saved
        ▌'''),
    );
  });

  testTwk('in the inline mode the region is as tall as the route shown', (
    t,
  ) async {
    final results = <Object?>[];
    await t.pumpWidget(
      Navigator(
        home: Screen(
          'home',
          keys: {
            'n': (context) => pushScreen(
              context,
              results,
              'detail',
              fields: const [Text('more'), Text('lines')],
            ),
          },
        ),
      ),
      size: (20, 6),
      mode: ScreenMode.inline,
    );
    expect(t.lines.first, 'home');
    await press(t, 'n');
    expect(t.lines.take(3), ['detail', 'more', 'lines']);
    await t.quit();
    expect(t.vt.cy, 3, reason: 'the cursor on the line below the region');
  });

  testTwk('along an axis with no bound the navigator is as long as the '
      'first route it shows, a route that is not opaque over it as big, '
      'the route under that shown', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Unbounded(
            child: Navigator(
              key: navigator,
              home: const Text('home page'),
            ),
          ),
          const Text('end'),
        ],
      ),
      size: (20, 6),
    );
    expect(t, matchesScreen('home page\nend'));
    final state = navigator.currentState!;
    unawaited(state.push(Layer('over\nmore')));
    await t.pump();
    expect(t, matchesScreen('over page\nend'));
    unawaited(
      state.push(
        PageRoute<void>(
          builder: (_) => const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text('a'), Text('b')],
          ),
        ),
      ),
    );
    await t.pump();
    expect(t, matchesScreen('a\nb\nend'));
  });

  testTwk('the statics of Navigator act on the navigator above the '
      'context: pushNamed, pushReplacement, pushReplacementNamed, popUntil '
      'and maybePop', (t) async {
    final results = <Object?>[];
    late BuildContext home;
    await t.pumpWidget(
      Navigator(
        home: Builder(
          builder: (context) {
            home = context;
            return const Text('home');
          },
        ),
        routes: {
          '/a': (context) => Text('a ${Route.of(context).settings.arguments}'),
          '/b': (context) => Text('b ${Route.of(context).settings.arguments}'),
        },
      ),
      size: (20, 2),
    );
    unawaited(
      Navigator.pushNamed<Object?>(home, '/a', arguments: 1).then(results.add),
    );
    await t.pump();
    expect(t, matchesScreen('a 1'));
    unawaited(
      Navigator.pushReplacement(
        home,
        PageRoute<String>(builder: (_) => const Text('page')),
        result: 'replaced by a page',
      ).then(results.add),
    );
    await t.pump();
    expect(t, matchesScreen('page'));
    expect(results, ['replaced by a page']);
    unawaited(
      Navigator.pushReplacementNamed<Object?>(
        home,
        '/b',
        arguments: 2,
        result: 'replaced by b',
      ).then(results.add),
    );
    await t.pump();
    expect(t, matchesScreen('b 2'));
    expect(results, ['replaced by a page', 'replaced by b']);
    unawaited(Navigator.pushNamed<Object?>(home, '/a', arguments: 3));
    await t.pump();
    Navigator.popUntil(home, (route) => route.settings.name == '/b');
    await t.pump();
    expect(t, matchesScreen('b 2'));
    expect(Navigator.maybePop(home, 'back'), isTrue);
    await t.pump();
    expect(t, matchesScreen('home'));
    expect(results.last, 'back');
    expect(
      Navigator.maybePop(home),
      isFalse,
      reason: 'the first route is left to what is past the navigator',
    );
  });

  testTwk('NavigatorState.pushReplacementNamed puts the route of a name in '
      "place of the one in front, its future of the name's type", (t) async {
    final navigator = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      Navigator(
        key: navigator,
        home: const Text('home'),
        routes: {'/next': (context) => const Text('next')},
      ),
      size: (20, 2),
    );
    final state = navigator.currentState!;
    final first = state.push(PageRoute<int>(builder: (_) => const Text('1')));
    await t.pump();
    final next = state.pushReplacementNamed<String>('/next', result: 7);
    await t.pump();
    expect(t, matchesScreen('next'));
    expect(await first, 7);
    state.pop('done');
    await t.pump();
    expect(await next, 'done');
    expect(t, matchesScreen('home'));
  });

  testTwk('Navigator.of and Route.of throw a StateError where there is '
      'none; maybeOf gives null, and canPop false', (t) async {
    late BuildContext context;
    await t.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const Text('no navigator');
        },
      ),
      size: (20, 1),
    );
    expect(Navigator.maybeOf(context), isNull);
    expect(Route.maybeOf(context), isNull);
    expect(Navigator.canPop(context), isFalse);
    expect(
      () => Navigator.of(context),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'no Navigator above Builder: place a Navigator above it',
        ),
      ),
    );
    expect(
      () => Route.of(context),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'no Route above Builder: a Navigator shows its routes',
        ),
      ),
    );
  });

  testTwk('removeRoute throws an ArgumentError for a route of another '
      'navigator, and a StateError for the only route', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      Navigator(key: navigator, home: const Text('home')),
      size: (20, 2),
    );
    final state = navigator.currentState!;
    final elsewhere = PageRoute<void>(builder: (_) => const Text('x'));
    expect(
      () => state.removeRoute(elsewhere),
      throwsA(
        isA<ArgumentError>().having((e) => e.name, 'name', 'route'),
      ),
    );
    late Route<Object?> home;
    unawaited(
      state.push(
        PageRoute<void>(
          builder: (context) {
            home = Route.of(context);
            return const Text('page');
          },
        ),
      ),
    );
    await t.pump();
    state.removeRoute(home);
    await t.pump();
    expect(t, matchesScreen('home'));
    final first = navigator.currentState!;
    late Route<Object?> only;
    await t.pumpWidget(
      Navigator(
        key: navigator,
        home: Builder(
          builder: (context) {
            only = Route.of(context);
            return const Text('home');
          },
        ),
      ),
    );
    expect(identical(navigator.currentState, first), isTrue);
    expect(
      () => first.removeRoute(only),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'removeRoute: the navigator keeps its only route',
        ),
      ),
    );
  });

  test("a route's toString names its type, a short hash and its name", () {
    final named = PageRoute<void>(
      builder: (_) => const Text(''),
      settings: const RouteSettings(name: '/settings'),
    );
    final anonymous = PageRoute<void>(builder: (_) => const Text(''));
    expect(
      '$named',
      matches(RegExp(r'^PageRoute<void>#[0-9a-f]{5}\(/settings\)$')),
    );
    expect('$anonymous', matches(RegExp(r'^PageRoute<void>#[0-9a-f]{5}$')));
  });

  testTwk('the intrinsic size of a navigator is the biggest of the routes '
      'it shows', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: IntrinsicWidth(
              child: Navigator(
                key: navigator,
                home: const Text('home page'),
              ),
            ),
          ),
          const Text('end'),
        ],
      ),
      size: (20, 6),
    );
    expect(t, matchesScreen('home page\nend'));
    unawaited(navigator.currentState!.push(Layer('a\nb\nc')));
    await t.pump();
    expect(
      t,
      matchesScreen('aome page\nb\nc\nend'),
      reason: 'as wide as the home page, as tall as the layer over it',
    );
  });
}

/// A route that is not opaque: [text] over the routes under it.
final class Layer extends Route<void> {
  Layer(this.text);

  final String text;

  @override
  bool get opaque => false;

  @override
  Widget build(BuildContext context) => Text(text);
}

/// Lays [child] out with no bound on its height, and is as tall as it.
final class Unbounded extends SingleChildRenderObjectWidget {
  const Unbounded({super.child, super.key});

  @override
  SingleChildRenderObjectElement createElement() => _UnboundedElement(this);

  @override
  RenderUnbounded createRenderObject(BuildContext context) => RenderUnbounded();
}

final class _UnboundedElement extends SingleChildRenderObjectElement {
  _UnboundedElement(super.widget);

  @override
  RenderUnbounded get renderObject => super.renderObject as RenderUnbounded;

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) =>
      renderObject.child = child;

  @override
  void moveRenderObjectChild(
    RenderObject child,
    Object? oldSlot,
    Object? newSlot,
  ) => throw UnsupportedError('one child does not move');

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) =>
      renderObject.child = null;
}

final class RenderUnbounded extends RenderObject
    with RenderObjectWithChildMixin {
  @override
  void performLayout(BoxConstraints c) {
    final child = this.child!
      ..layout(
        BoxConstraints(0, c.maxW, 0, BoxConstraints.unbounded),
        parentUsesSize: true,
      );
    width = c.constrainW(child.width);
    height = c.constrainH(child.height);
  }

  @override
  void paint(PaintContext ctx) => paintChild(ctx, child!);
}

/// What [builder] builds.
final class Builder extends StatelessWidget {
  const Builder({required this.builder, super.key});

  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

/// Counts each second, from a timer, and shows the count; logs its builds
/// and the layouts and paints of a [Probe] it shows, and its taps.
final class Ticking extends StatefulWidget {
  const Ticking(this.log, this.taps, {super.key});

  final List<String> log;
  final List<String> taps;

  @override
  State<Ticking> createState() => _TickingState();
}

final class _TickingState extends State<Ticking> {
  var _count = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _count++),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.log.add('build $_count');
    return GestureDetector(
      onTap: (_) => widget.taps.add('tap $_count'),
      child: SizedBox(
        width: 20,
        height: 3,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text('tick $_count'), Probe(_count, widget.log)],
        ),
      ),
    );
  }
}

/// Logs the layouts and paints of its render object, a cell that paints
/// nothing: an object the clip leaves no cell of is not painted.
final class Probe extends LeafRenderObjectWidget {
  const Probe(this.value, this.log, {super.key});

  final int value;
  final List<String> log;

  @override
  RenderProbe createRenderObject(BuildContext context) =>
      RenderProbe(value, log);

  @override
  void updateRenderObject(BuildContext context, RenderProbe renderObject) =>
      renderObject.update(value);
}

final class RenderProbe extends RenderObject {
  RenderProbe(this._value, this.log);

  final List<String> log;

  int _value;

  void update(int v) {
    if (v != _value) {
      _value = v;
      markNeedsLayout();
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    log.add('layout $_value');
    width = c.constrainW(1);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) => log.add('paint $_value');
}
