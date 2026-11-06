// A dialog on a navigator under App is as one in App's overlay: the keys
// it leaves skip the app's bindings between the navigator and the overlay,
// which list none of their keys while it is open, and go to those above
// App; a page pushed on the navigator still gets the app's keys; without
// an overlay above the navigator nothing is skipped.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [t] given [key] and a frame.
Future<void> press(TwkTester t, String key) async {
  await t.press(key);
  await t.pump();
}

/// A dialog of a button, shown from [context].
void open(BuildContext context) => unawaited(
  showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      title: 'Find',
      child: Button('OK', autofocus: true, onPressed: () {}),
    ),
    fadeIn: Duration.zero,
  ),
);

/// A screen of the navigator that binds `d`, which opens a dialog from it,
/// and `p`, which pushes another such screen.
Widget screen(String name) => Builder(
  builder: (context) => KeyBindings(
    {
      'd': () => open(context),
      'p': () => unawaited(
        Navigator.push<void>(
          context,
          PageRoute(builder: (_) => screen('page')),
        ),
      ),
    },
    child: Focus(autofocus: true, child: Text(name)),
  ),
);

/// The app's root bindings, `q` adding to [heard] and `r` opening a dialog
/// from above the navigator, around a navigator of [screen]s.
Widget root(List<String> heard) => Builder(
  builder: (context) => KeyBindings(
    {'q': () => heard.add('q'), 'r': () => open(context)},
    hints: const {'q': 'quit'},
    child: Navigator(home: screen('home')),
  ),
);

/// The keys the layers on the focus's key path list now, by label.
List<String> active(TwkTester t) => [
  for (final key in t.binding.focusManager.activeKeys) key.label(),
];

void main() {
  testTwk("a dialog opened from a navigator's screen: the app's bindings "
      'above the navigator do not hear the keys it leaves', (t) async {
    final heard = <String>[];
    await t.pumpWidget(App(child: root(heard)), size: (30, 7));
    await press(t, 'd');
    expect(t, containsLine(contains('Find')));
    await press(t, 'q');
    expect(heard, isEmpty);
    await press(t, 'escape');
    expect(t, isNot(containsLine(contains('Find'))));
    await press(t, 'q');
    expect(heard, ['q']);
  });

  testTwk('nor list their keys while it is open', (t) async {
    await t.pumpWidget(App(child: root([])), size: (30, 7));
    expect(active(t), contains('q'));
    await press(t, 'd');
    expect(active(t), isNot(contains('q')));
    expect(active(t), contains('escape'));
    await press(t, 'escape');
    expect(active(t), contains('q'));
  });

  testTwk('a dialog opened from the root bindings, above the navigator: they '
      'do not hear the keys it leaves', (t) async {
    final heard = <String>[];
    await t.pumpWidget(App(child: root(heard)), size: (30, 7));
    await press(t, 'r');
    expect(t, containsLine(contains('Find')));
    await press(t, 'q');
    expect(heard, isEmpty);
  });

  testTwk('bindings above App hear what the dialog leaves', (t) async {
    final above = <String>[];
    await t.pumpWidget(
      KeyBindings(
        {'ctrl+q': () => above.add('ctrl+q')},
        child: App(child: root([])),
      ),
      size: (30, 7),
    );
    await press(t, 'd');
    await press(t, 'ctrl+q');
    expect(above, ['ctrl+q']);
  });

  testTwk("a page pushed on the navigator gets the app's keys", (t) async {
    final heard = <String>[];
    await t.pumpWidget(App(child: root(heard)), size: (30, 7));
    await press(t, 'p');
    expect(t, containsLine('page'));
    await press(t, 'q');
    expect(heard, ['q']);
  });

  testTwk('a dialog over a dialog: neither lets the keys through', (t) async {
    final heard = <String>[];
    await t.pumpWidget(
      App(
        child: Builder(
          builder: (context) => KeyBindings(
            {'q': () => heard.add('q')},
            child: Navigator(
              home: Builder(
                builder: (context) => KeyBindings(
                  {'d': () => open(context)},
                  child: const Focus(autofocus: true, child: Text('home')),
                ),
              ),
            ),
          ),
        ),
      ),
      size: (30, 7),
    );
    await press(t, 'd');
    // the dialog's button has the focus, and the screen's d is not on the
    // path: a second dialog is opened from the first one's context
    final first = t.binding.focusManager.primaryFocus!.context!;
    open(first);
    await t.pump();
    await press(t, 'q');
    expect(heard, isEmpty);
    await press(t, 'escape');
    await press(t, 'q');
    expect(heard, isEmpty);
    await press(t, 'escape');
    await press(t, 'q');
    expect(heard, ['q']);
  });

  testTwk('with no overlay above the navigator nothing is skipped: the '
      'bindings above it hear what the dialog leaves', (t) async {
    final heard = <String>[];
    await t.pumpWidget(root(heard), size: (30, 7));
    await press(t, 'd');
    expect(t, containsLine(contains('Find')));
    await press(t, 'q');
    expect(heard, ['q']);
  });
}
