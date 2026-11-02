// Escape in a popover or a menu shown on a page of a Navigator closes it
// and leaves the page: the navigator's back key does not hear the key the
// popover or the menu took. The tests guard it.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Future<void> press(TwkTester t, String key) async {
  await t.press(key);
  await t.pump(const Duration(milliseconds: 300));
}

List<String> shown(TwkTester t) => [
  for (final l in t.lines)
    if (l.trim().isNotEmpty) l.trim(),
];

/// A popover over a button, open at first, that closes on dismissal; the
/// focus is on the button (the anchor) or on the button in the popover.
final class PopoverPage extends StatefulWidget {
  const PopoverPage({required this.focusInPopover, super.key});

  final bool focusInPopover;

  @override
  State<PopoverPage> createState() => _PopoverPageState();
}

class _PopoverPageState extends State<PopoverPage> {
  var open = true;

  @override
  Widget build(BuildContext context) => Popover(
    open: open,
    onDismiss: () => setState(() => open = false),
    popover: Box(
      border: const Border.all(),
      child: widget.focusInPopover
          ? Button('inside', autofocus: true, onPressed: () {})
          : const Text('pop'),
    ),
    child: Button(
      'anchor',
      autofocus: !widget.focusInPopover,
      onPressed: () {},
    ),
  );
}

/// A navigator whose home pushes [page] on `p`.
Widget app(WidgetBuilder page) => App(
  child: Navigator(
    home: Builder(
      builder: (context) => KeyBindings(
        {
          'p': () => unawaited(
            Navigator.push<void>(context, PageRoute(builder: page)),
          ),
        },
        child: const Focus(autofocus: true, child: Text('home')),
      ),
    ),
  ),
);

void main() {
  for (final inPopover in [false, true]) {
    testTwk(
      'Escape with the focus ${inPopover ? 'in the popover' : 'on its '
                'anchor'} closes the popover and leaves the page',
      (t) async {
        await t.pumpWidget(
          app((_) => PopoverPage(focusInPopover: inPopover)),
          size: (30, 8),
        );
        await press(t, 'p');
        expect(shown(t), contains('anchor'));
        expect(shown(t).any((l) => l.contains('┌')), isTrue);
        await press(t, 'escape');
        expect(shown(t), ['anchor'], reason: 'the page, popover closed');
      },
    );
  }

  testTwk('Escape in a context menu closes the menu and leaves the page', (
    t,
  ) async {
    await t.pumpWidget(
      app(
        (_) => Builder(
          builder: (context) => KeyBindings(
            {
              'm': () => showContextMenu(
                context,
                [
                  MenuItem('Copy', onSelected: () {}),
                ],
                at: (2, 2),
              ),
            },
            child: const Focus(autofocus: true, child: Text('page')),
          ),
        ),
      ),
      size: (30, 8),
    );
    await press(t, 'p');
    await press(t, 'm');
    expect(shown(t), ['page', 'Copy']);
    await press(t, 'escape');
    expect(shown(t), ['page']);
    await press(t, 'escape');
    expect(shown(t), ['home'], reason: 'a second Escape goes back');
  });
}
