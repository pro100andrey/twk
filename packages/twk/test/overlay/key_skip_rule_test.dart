// The one rule of an overlay's entries and a navigator's dialogs: what is
// shown over a navigator hears the keys as if it were shown in the App's
// overlay, so the bindings between the navigator and that overlay do not
// hear its keys; the navigator's own back key stays on its path and the
// page content still hears the app's bindings. One test per place the
// thing is shown.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Future<void> press(TwkTester t, String key) async {
  await t.press(key);
  await t.pump(const Duration(milliseconds: 300));
}

/// A screen with the focus whose keys open what is shown over it: `d` a
/// dialog on the nearest navigator, `r` one on the root navigator, `e` an
/// entry of the nearest overlay, `p` a popover; `u` is bound on a page
/// binding of its own that [heard] gets.
Widget screen(String name, List<String> heard, {bool openPopover = false}) =>
    Builder(
      builder: (context) => KeyBindings(
        {
          'd': () => unawaited(
            showDialog<void>(
              context: context,
              builder: (_) =>
                  const Focus(autofocus: true, child: Text('dialog')),
              useRootNavigator: false,
              fadeIn: Duration.zero,
            ),
          ),
          'r': () => unawaited(
            showDialog<void>(
              context: context,
              builder: (_) =>
                  const Focus(autofocus: true, child: Text('dialog')),
              fadeIn: Duration.zero,
            ),
          ),
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
        },
        child: Focus(autofocus: true, child: Text(name)),
      ),
    );

/// `q` above the navigator and `ctrl+q` above the App.
Widget app(
  List<String> heard,
  Widget Function(List<String> heard) home, {
  bool navigator = true,
}) => KeyBindings(
  {'ctrl+q': () => heard.add('ctrl+q')},
  child: App(
    child: KeyBindings(
      {'q': () => heard.add('q')},
      child: navigator ? Navigator(home: home(heard)) : home(heard),
    ),
  ),
);

void main() {
  testTwk('the App overlay alone: a dialog hears the bindings above App', (
    t,
  ) async {
    final heard = <String>[];
    await t.pumpWidget(
      app(heard, (h) => screen('home', h), navigator: false),
      size: (30, 7),
    );
    await press(t, 'd');
    expect(t, containsLine(contains('dialog')));
    await press(t, 'ctrl+q');
    expect(heard, ['ctrl+q']);
  });

  testTwk('a dialog on a navigator: skips the app bindings, hears those '
      "above App, and the navigator's back key closes it", (t) async {
    final heard = <String>[];
    await t.pumpWidget(app(heard, (h) => screen('home', h)), size: (30, 7));
    await press(t, 'q');
    expect(heard, ['q'], reason: 'the page content hears the app');
    heard.clear();
    await press(t, 'd');
    expect(t, containsLine(contains('dialog')));
    await press(t, 'q');
    expect(heard, isEmpty);
    await press(t, 'ctrl+q');
    expect(heard, ['ctrl+q']);
    await press(t, 'escape');
    expect(t, isNot(containsLine(contains('dialog'))));
    heard.clear();
    await press(t, 'q');
    expect(heard, ['q']);
  });

  testTwk("an entry of the navigator's overlay skips the app bindings", (
    t,
  ) async {
    final heard = <String>[];
    await t.pumpWidget(app(heard, (h) => screen('home', h)), size: (30, 7));
    await press(t, 'e');
    expect(t, containsLine(contains('entry')));
    await press(t, 'q');
    expect(heard, isEmpty);
    await press(t, 'ctrl+q');
    expect(heard, ['ctrl+q']);
  });

  testTwk('a popover on a page skips the app bindings', (
    t,
  ) async {
    final heard = <String>[];
    await t.pumpWidget(
      app(
        heard,
        (h) => const Popover(
          onDismiss: null,
          open: true,
          popover: Box(
            border: Border.all(),
            child: Button('inside', autofocus: true, onPressed: _noop),
          ),
          child: Button('anchor', onPressed: _noop),
        ),
      ),
      size: (30, 8),
    );
    await press(t, 'q');
    expect(heard, isEmpty);
    await press(t, 'ctrl+q');
    expect(heard, ['ctrl+q']);
  });

  testTwk('nested navigators: a dialog on the inner one (not the root) '
      'skips the bindings between it and the App overlay, the inner '
      "navigator's and the outer's", (t) async {
    final heard = <String>[];
    await t.pumpWidget(
      app(
        heard,
        (h) => KeyBindings(
          {'u': () => h.add('u')},
          child: Navigator(home: screen('inner', h)),
        ),
      ),
      size: (30, 7),
    );
    await press(t, 'u');
    await press(t, 'q');
    expect(heard, ['u', 'q']);
    heard.clear();
    await press(t, 'd');
    expect(t, containsLine(contains('dialog')));
    await press(t, 'u');
    await press(t, 'q');
    expect(heard, isEmpty);
    await press(t, 'ctrl+q');
    expect(heard, ['ctrl+q']);
  });

  testTwk('nested navigators: a dialog on the root navigator skips what '
      'is above it, an inner entry also the outer skip', (t) async {
    final heard = <String>[];
    await t.pumpWidget(
      app(
        heard,
        (h) => KeyBindings(
          {'u': () => h.add('u')},
          child: Navigator(home: screen('inner', h)),
        ),
      ),
      size: (30, 7),
    );
    await press(t, 'r');
    expect(t, containsLine(contains('dialog')));
    await press(t, 'u');
    await press(t, 'q');
    expect(heard, isEmpty);
    await press(t, 'escape');
    await press(t, 'e');
    await press(t, 'u');
    await press(t, 'q');
    expect(heard, isEmpty);
  });

  testTwk('without an overlay above the navigator nothing is skipped', (
    t,
  ) async {
    final heard = <String>[];
    await t.pumpWidget(
      KeyBindings(
        {'q': () => heard.add('q')},
        child: Navigator(home: screen('home', heard)),
      ),
      size: (30, 7),
    );
    await press(t, 'd');
    expect(t, containsLine(contains('dialog')));
    await press(t, 'q');
    expect(heard, ['q']);
  });
}

void _noop() {}
