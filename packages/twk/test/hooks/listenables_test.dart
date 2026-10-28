// The hooks of listenables: useListenable and useValueListenable, which
// rebuild when one notifies, and useValueNotifier, which makes one; each
// through mounting, another listenable or other keys, and unmounting.
import 'package:test/test.dart';
import 'package:twk/hooks.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'matchers.dart';

/// A notifier that counts its listeners.
final class Counted extends ChangeNotifier {
  var listeners = 0;

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }

  void ping() => notifyListeners();
}

void main() {
  testTwk('useListenable rebuilds when its listenable notifies, goes over '
      'to the listenable of a later build, and stops listening when '
      'unmounted', (t) async {
    final a = Counted();
    final b = Counted();
    var builds = 0;
    Widget listening(Counted? listenable) => HookBuilder(
      builder: (context) {
        builds++;
        expect(useListenable(listenable), same(listenable));
        return const Text('x');
      },
    );
    await t.pumpWidget(listening(a), size: (10, 1));
    expect(a.listeners, 1);
    a.ping();
    await t.pump();
    expect(builds, 2);
    await t.pumpWidget(listening(b));
    expect((a.listeners, b.listeners), (0, 1));
    a.ping();
    await t.pump();
    expect(builds, 3);
    b.ping();
    await t.pump();
    expect(builds, 4);
    await t.pumpWidget(listening(null));
    expect(b.listeners, 0);
    await t.pumpWidget(listening(a));
    expect(a.listeners, 1);
    await t.pumpWidget(const Text('gone'));
    expect(a.listeners, 0);
  });

  testTwk('useValueListenable is the value of its listenable, rebuilt when '
      'it changes', (t) async {
    final value = ValueNotifier('a');
    await t.pumpWidget(
      HookBuilder(builder: (context) => Text(useValueListenable(value))),
      size: (10, 1),
    );
    expect(t.lines, ['a']);
    value.value = 'b';
    await t.pump();
    expect(t.lines, ['b']);
  });

  testTwk('useValueNotifier is the notifier of the first build, made anew '
      'when the keys change, the old one disposed, and its changes rebuild '
      'nothing', (t) async {
    final notifiers = <ValueNotifier<int>>[];
    var builds = 0;
    Widget notifier(int initial, int key) => HookBuilder(
      builder: (context) {
        builds++;
        notifiers.add(useValueNotifier(initial, [key]));
        return const Text('x');
      },
    );
    await t.pumpWidget(notifier(1, 1), size: (10, 1));
    notifiers.last.value = 2;
    await t.pump();
    expect(builds, 1);
    await t.pumpWidget(notifier(5, 1));
    expect(notifiers[1], same(notifiers[0]));
    expect(notifiers[1].value, 2);
    await t.pumpWidget(notifier(5, 2));
    expect(notifiers[1], isDisposed);
    expect(notifiers[2].value, 5);
    await t.pumpWidget(const Text('gone'));
    expect(notifiers[2], isDisposed);
  });
}
