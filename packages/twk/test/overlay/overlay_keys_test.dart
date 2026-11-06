// What shows in a navigator's own overlay (an entry inserted in it, a
// context menu, a popover) skips the app's bindings between the navigator
// and the overlay above it, as a dialog does and as an entry of App's
// overlay would; the skip follows a change of the tree above, and lands
// at the end of the outer navigator's skip for an inner navigator.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Future<void> press(TwkTester t, String key) async {
  await t.press(key);
  await t.pump();
}

List<String> active(TwkTester t) => [
  for (final key in t.binding.focusManager.activeKeys) key.label(),
];

/// A screen that binds `e` to an entry of the nearest overlay, with a
/// focused text in it, `m` to a context menu, `p` to a popover and `n` to
/// push a screen of an inner navigator.
Widget screen(String name, {List<String>? inner}) => Builder(
  builder: (context) => KeyBindings(
    {
      'e': () {
        late final OverlayEntry entry;
        entry = OverlayEntry(
          fadeIn: Duration.zero,
          fadeOut: Duration.zero,
          builder: (_) => Positioned(
            left: 0,
            top: 3,
            child: FocusScope(
              autofocus: true,
              child: KeyBindings(
                {'x': entry.remove},
                child: const Focus(autofocus: true, child: Text('entry')),
              ),
            ),
          ),
        );
        Overlay.of(context).insert(entry);
      },
      'm': () => showContextMenu(
        context: context,
        items: [
          MenuItem('Copy', onSelected: () {}),
        ],
        at: (2, 2),
      ),
    },
    child: Focus(autofocus: true, child: Text(name)),
  ),
);

Widget root(List<String> heard, {Widget? home}) => Builder(
  builder: (context) => KeyBindings(
    {'q': () => heard.add('q')},
    hints: const {'q': 'quit'},
    child: Navigator(home: home ?? screen('home')),
  ),
);

void main() {
  testTwk("an entry of the navigator's overlay: the app's bindings above "
      'the navigator do not hear the keys it leaves, nor list theirs', (
    t,
  ) async {
    final heard = <String>[];
    await t.pumpWidget(App(child: root(heard)), size: (30, 7));
    expect(active(t), contains('q'));
    await press(t, 'e');
    expect(t, containsLine(contains('entry')));
    expect(active(t), isNot(contains('q')));
    await press(t, 'q');
    expect(heard, isEmpty);
    await press(t, 'x');
    await press(t, 'q');
    expect(heard, ['q']);
  });

  testTwk('a context menu opened from a screen of the navigator', (t) async {
    final heard = <String>[];
    await t.pumpWidget(App(child: root(heard)), size: (30, 7));
    await press(t, 'm');
    await t.pump(const Duration(milliseconds: 200));
    expect(t, containsLine(contains('Copy')));
    await press(t, 'q');
    expect(heard, isEmpty);
    expect(active(t), isNot(contains('q')));
  });

  testTwk('bindings above App hear what the entry leaves', (t) async {
    final above = <String>[];
    await t.pumpWidget(
      KeyBindings(
        {'ctrl+q': () => above.add('ctrl+q')},
        child: App(child: root([])),
      ),
      size: (30, 7),
    );
    await press(t, 'e');
    await press(t, 'ctrl+q');
    expect(above, ['ctrl+q']);
  });

  testTwk('a binding placed above the navigator after the entry opened is '
      'skipped too', (t) async {
    final heard = <String>[];
    final extra = ValueNotifier(false);
    final navigator = GlobalKey();
    Widget nav() => Navigator(key: navigator, home: screen('home'));
    await t.pumpWidget(
      App(
        child: ListenableBuilder(
          listenable: extra,
          builder: (context, _) => extra.value
              ? KeyBindings({'w': () => heard.add('w')}, child: nav())
              : nav(),
        ),
      ),
      size: (30, 7),
    );
    await press(t, 'e');
    extra.value = true;
    await t.pump();
    expect(t, containsLine(contains('entry')));
    await press(t, 'w');
    expect(heard, isEmpty);
  });

  testTwk('a binding taken from above the navigator after the entry opened: '
      'the rest is still skipped', (t) async {
    final heard = <String>[];
    final extra = ValueNotifier(true);
    final navigator = GlobalKey();
    Widget nav() => Navigator(key: navigator, home: screen('home'));
    await t.pumpWidget(
      App(
        child: Builder(
          builder: (context) => KeyBindings(
            {'q': () => heard.add('q')},
            child: ListenableBuilder(
              listenable: extra,
              builder: (context, _) => extra.value
                  ? KeyBindings({'w': () => heard.add('w')}, child: nav())
                  : nav(),
            ),
          ),
        ),
      ),
      size: (30, 7),
    );
    await press(t, 'e');
    extra.value = false;
    await t.pump();
    expect(t, containsLine(contains('entry')));
    await press(t, 'q');
    expect(heard, isEmpty);
  });

  testTwk('with no overlay above the navigator nothing is skipped', (
    t,
  ) async {
    final heard = <String>[];
    await t.pumpWidget(root(heard), size: (30, 7));
    await press(t, 'e');
    expect(t, containsLine(contains('entry')));
    await press(t, 'q');
    expect(heard, ['q']);
  });

  testTwk('an inner navigator in a page of the outer: its entry skips what '
      "is between it and the outer navigator's overlay, and the outer "
      'skip as well', (t) async {
    final heard = <String>[];
    final page = <String>[];
    final inner = Builder(
      builder: (context) => KeyBindings(
        {'u': () => page.add('u')},
        child: Navigator(home: screen('inner')),
      ),
    );
    await t.pumpWidget(
      App(child: root(heard, home: inner)),
      size: (30, 7),
    );
    expect(active(t), containsAll(['q', 'u']));
    await press(t, 'e');
    expect(t, containsLine(contains('entry')));
    await press(t, 'u');
    await press(t, 'q');
    expect(page, isEmpty);
    expect(heard, isEmpty);
  });
}
