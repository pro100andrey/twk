// A Navigator's observers, told of each route pushed, popped, replaced
// and removed with the route next to it; PopScope, which refuses or
// intercepts a pop of its route: the back key consumed and the callback
// told it did not pop, even on the first route, and told the result of a
// pop that went ahead.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Writes each call down as `didX route previous`, a route by its name.
final class Log extends NavigatorObserver {
  final calls = <String>[];

  static String _name(Route<Object?>? route) =>
      route == null ? '-' : route.settings.name ?? '?';

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) =>
      calls.add('push ${_name(route)} ${_name(previousRoute)}');

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) =>
      calls.add('pop ${_name(route)} ${_name(previousRoute)}');

  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) =>
      calls.add('remove ${_name(route)} ${_name(previousRoute)}');

  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) =>
      calls.add('replace ${_name(newRoute)} ${_name(oldRoute)}');
}

/// A route named [name] showing it.
PageRoute<String> page(String name) => PageRoute<String>(
  builder: (_) => Text(name),
  settings: RouteSettings(name: name),
);

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
  testTwk('the observers are told of the first route, of each push, pop, '
      'replacement and removal, with the route under it', (t) async {
    final log = Log();
    final navigator = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      Navigator(
        key: navigator,
        observers: [log],
        routes: {'/': (_) => const Text('home')},
      ),
      size: (20, 3),
    );
    final state = navigator.currentState!;
    expect(log.navigator, same(state));
    expect(log.calls, ['push / -']);

    unawaited(state.push(page('a')));
    unawaited(state.push(page('b')));
    await t.pump();
    expect(log.calls.skip(1), ['push a /', 'push b a']);

    log.calls.clear();
    state.pop();
    unawaited(state.pushReplacement(page('c')));
    await t.pump();
    expect(log.calls, ['pop b a', 'replace c a']);

    log.calls.clear();
    final d = page('d');
    unawaited(state.push(d));
    unawaited(state.push(page('e')));
    state.removeRoute(d);
    await t.pump();
    expect(log.calls, ['push d c', 'push e d', 'remove d c']);

    log.calls.clear();
    state.popUntil(Route.withName('/'));
    await t.pump();
    expect(log.calls, ['pop e c', 'pop c /']);
    expect(t, matchesScreen('home'));
  });

  testTwk('observers given anew are told from then on; one leaves the '
      'navigator with it', (t) async {
    final first = Log();
    final second = Log();
    final navigator = GlobalKey<NavigatorState>();
    Widget app(List<NavigatorObserver> observers) => Navigator(
      key: navigator,
      observers: observers,
      home: const Text('home'),
    );
    await t.pumpWidget(app([first]), size: (20, 3));
    await t.pumpWidget(app([second]));
    expect(first.navigator, isNull);
    expect(second.navigator, same(navigator.currentState));
    unawaited(navigator.currentState!.push(page('a')));
    await t.pump();
    expect(first.calls, ['push / -']);
    expect(second.calls, ['push a /']);
    await t.pumpWidget(const Text('gone'));
    expect(second.navigator, isNull);
  });

  testTwk('a PopScope that cannot pop keeps the back key from popping its '
      'route, which it consumes, and is told it did not pop; one that can '
      'is told the result of a pop', (t) async {
    final calls = <String>[];
    final canPop = ValueNotifier(false);
    final navigator = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      KeyBindings(
        {'escape': () => calls.add('app escape')},
        child: Navigator(key: navigator, home: const Text('home')),
      ),
      size: (20, 3),
    );
    final results = <Object?>[];
    unawaited(
      navigator.currentState!
          .push(
            PageRoute<String>(
              builder: (_) => ValueListenableBuilder(
                valueListenable: canPop,
                builder: (context, value, _) => PopScope<String>(
                  canPop: value,
                  onPopInvokedWithResult: (didPop, result) =>
                      calls.add('invoked $didPop $result'),
                  onPopInvoked: (didPop) => calls.add('didPop $didPop'),
                  child: const Text('form'),
                ),
              ),
            ),
          )
          .then(results.add),
    );
    await t.pump();
    expect(activeKeys(t), ['escape back']);
    await press(t, 'escape');
    expect(t, matchesScreen('form'));
    expect(calls, ['invoked false null', 'didPop false']);
    expect(navigator.currentState!.maybePop('x'), isTrue);
    expect(calls.skip(2), ['invoked false x', 'didPop false']);

    calls.clear();
    canPop.value = true;
    await t.pump();
    navigator.currentState!.pop('saved');
    await t.pump();
    expect(calls, ['invoked true saved', 'didPop true']);
    expect(results, ['saved']);
    expect(t, matchesScreen('home'));
  });

  testTwk('Navigator.pop goes past a PopScope that cannot pop, which is '
      'told it did', (t) async {
    final calls = <bool>[];
    final navigator = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      Navigator(key: navigator, home: const Text('home')),
      size: (20, 3),
    );
    unawaited(
      navigator.currentState!.push(
        PageRoute<void>(
          builder: (_) => PopScope<void>(
            canPop: false,
            onPopInvoked: calls.add,
            child: const Text('form'),
          ),
        ),
      ),
    );
    await t.pump();
    navigator.currentState!.pop();
    await t.pump();
    expect(calls, [true]);
    expect(t, matchesScreen('home'));
  });

  testTwk('on the first route, a PopScope that cannot pop takes the back '
      'key, which otherwise goes on past the navigator; as it lets go, the '
      'key goes on again, and what lists the keys is told', (t) async {
    final calls = <String>[];
    final canPop = ValueNotifier(false);
    await t.pumpWidget(
      KeyBindings(
        {'escape': () => calls.add('app escape')},
        child: Navigator(
          home: Focus(
            autofocus: true,
            child: ValueListenableBuilder(
              valueListenable: canPop,
              builder: (context, value, _) => PopScope<Object?>(
                canPop: value,
                onPopInvoked: (didPop) => calls.add('didPop $didPop'),
                child: const Text('home'),
              ),
            ),
          ),
        ),
      ),
      size: (20, 3),
    );
    expect(activeKeys(t), ['escape back']);
    await press(t, 'escape');
    expect(calls, ['didPop false']);

    // what lists the keys, a KeyHintsBar, is told
    var told = 0;
    t.binding.focusManager.keysChanged.addListener(() => told++);
    canPop.value = true;
    await t.pump();
    expect(told, 1);
    expect(activeKeys(t), ['escape']);
    await press(t, 'escape');
    expect(calls, ['didPop false', 'app escape']);
  });

  testTwk('a route reports how the back key would pop it', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      Navigator(key: navigator, home: const Text('home')),
      size: (20, 3),
    );
    final home = Route.of(t.element(find.text('home')));
    expect(home.popDisposition, RoutePopDisposition.bubble);
    final a = page('a');
    unawaited(navigator.currentState!.push(a));
    await t.pump();
    expect(a.popDisposition, RoutePopDisposition.pop);
    expect(navigator.currentState!.maybePop(), isTrue);
    await t.pump();
    expect(navigator.currentState!.maybePop(), isFalse);
  });

  testTwk('an observer that overrides only didPush is told of the pushes, '
      'and the pops, replacements and removals do nothing to it', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    final pushes = Pushes();
    await t.pumpWidget(
      Navigator(
        key: navigator,
        home: const Text('home'),
        observers: [pushes],
      ),
      size: (20, 2),
    );
    final state = navigator.currentState!;
    unawaited(state.push(page('a')));
    unawaited(state.push(page('b')));
    await t.pump();
    state.pop();
    final c = page('c');
    unawaited(state.pushReplacement(c));
    unawaited(state.push(page('d')));
    await t.pump();
    state.removeRoute(c);
    await t.pump();
    expect(t, matchesScreen('d'));
    expect(pushes.names, ['/', 'a', 'b', 'd']);
    expect(pushes.navigator, same(state));
  });
}

/// Writes down the name of each route pushed, and nothing else.
final class Pushes extends NavigatorObserver {
  final names = <String?>[];

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) =>
      names.add(route.settings.name);
}
