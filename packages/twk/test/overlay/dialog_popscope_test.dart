// A dialog shown on a Navigator closes on Escape and on a click on its
// barrier through a pop of its route: a PopScope in it that cannot pop
// keeps it open and is told so, one that can is told of the pop, and the
// navigator's observers see it popped, not removed.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Writes each pop and removal down as `didX route previous`, a route by
/// its name, `?` for one without.
final class Log extends NavigatorObserver {
  final calls = <String>[];

  static String _name(Route<Object?>? route) =>
      route == null ? '-' : route.settings.name ?? '?';

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) =>
      calls.add('pop ${_name(route)} ${_name(previousRoute)}');

  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) =>
      calls.add('remove ${_name(route)} ${_name(previousRoute)}');
}

/// Presses [key] and pumps a frame.
Future<void> press(TwkTester t, String key) async {
  await t.press(key);
  await t.pump();
}

/// `d` shows a dialog over `home` whose PopScope can pop while [canPop]
/// holds, telling [calls] of each pop as `invoked didPop result`; `x` in
/// the dialog closes it with `done`. Its result goes to [results].
final class Home extends StatelessWidget {
  const Home(this.results, this.calls, this.canPop, {super.key});

  final List<Object?> results;
  final List<String> calls;
  final ValueNotifier<bool> canPop;

  @override
  Widget build(BuildContext context) => KeyBindings({
    'd': () => unawaited(
      showDialog<String>(
        context,
        (context) => ListenableBuilder(
          listenable: canPop,
          builder: (context, _) => PopScope<String>(
            canPop: canPop.value,
            onPopInvokedWithResult: (didPop, result) =>
                calls.add('invoked $didPop $result'),
            child: Dialog(
              title: 'Ask',
              child: KeyBindings({
                'x': () => closeDialog(context, 'done'),
              }, child: const Text('sure?')),
            ),
          ),
        ),
        fadeIn: Duration.zero,
      ).then(results.add),
    ),
  }, child: const Text('home'));
}

void main() {
  late List<Object?> results;
  late List<String> calls;
  late ValueNotifier<bool> canPop;
  late Log log;

  Future<void> show(TwkTester t, {required bool pop}) async {
    results = [];
    calls = [];
    canPop = ValueNotifier(pop);
    log = Log();
    await t.pumpWidget(
      Navigator(
        observers: [log],
        routes: {'/': (_) => Home(results, calls, canPop)},
      ),
      size: (20, 7),
    );
    await press(t, 'd');
    expect(t.lines.join('\n'), contains('sure?'));
  }

  testTwk('a PopScope that cannot pop keeps a dialog open on Escape and '
      'is told it did not pop', (t) async {
    await show(t, pop: false);
    await press(t, 'escape');
    expect(t.lines.join('\n'), contains('sure?'));
    expect(calls, ['invoked false null']);
    expect(results, isEmpty);
    expect(log.calls, isEmpty);

    // once it can, Escape pops it
    canPop.value = true;
    await t.pump();
    await press(t, 'escape');
    expect(t.lines.join('\n'), isNot(contains('sure?')));
    expect(calls, ['invoked false null', 'invoked true null']);
    expect(results, [null]);
    expect(log.calls, ['pop ? /']);
  });

  testTwk('a PopScope that cannot pop keeps a dialog open on a click on '
      'the barrier and is told it did not pop', (t) async {
    await show(t, pop: false);
    await t.click(0, 0);
    await t.pump();
    expect(t.lines.join('\n'), contains('sure?'));
    expect(calls, ['invoked false null']);
    expect(results, isEmpty);
    expect(log.calls, isEmpty);
  });

  testTwk('Escape and a click on the barrier pop a dialog: the observers '
      'see it popped, its PopScope is told so, its result is null', (
    t,
  ) async {
    await show(t, pop: true);
    await press(t, 'escape');
    expect(t.lines.join('\n'), isNot(contains('sure?')));
    expect(calls, ['invoked true null']);
    expect(log.calls, ['pop ? /']);

    await press(t, 'd');
    await t.click(0, 0);
    await t.pump();
    expect(t.lines.join('\n'), isNot(contains('sure?')));
    expect(calls, ['invoked true null', 'invoked true null']);
    expect(log.calls, ['pop ? /', 'pop ? /']);
    expect(results, [null, null]);
  });

  testTwk('closeDialog closes a dialog with its result although its '
      'PopScope cannot pop', (t) async {
    await show(t, pop: false);
    await press(t, 'x');
    expect(t.lines.join('\n'), isNot(contains('sure?')));
    expect(results, ['done']);
  });
}
