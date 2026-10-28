// The hints of the keys a Scrollable takes: those that would move it now,
// listed while the focus is in it and followed by a KeyHintsBar as it
// moves; none with nothing to scroll or with keyHints false; the keys at
// an end still going on to the nodes above, a focused widget inside it
// and a list that does not take the focus itself (a SelectionList's)
// keeping theirs.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

/// A column of [count] rows, `item 0` on.
Widget column(int count) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [for (var i = 0; i < count; i++) Text('item $i')],
);

/// [view], 4 rows of it, above a [KeyHintsBar].
Widget withBar(Widget view) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    SizedBox(height: 4, child: view),
    // the keys by their names, whatever the bar's own are
    KeyHintsBar(separator: ' · ', keyLabel: (c) => '$c'),
  ],
);

const _top = ['down scroll', 'pagedown a window', 'end the ends'];
const _middle = [
  'up scroll',
  'down scroll',
  'pageup a window',
  'pagedown a window',
  'home the ends',
  'end the ends',
];
const _bottom = ['up scroll', 'pageup a window', 'home the ends'];

void main() {
  group('a Scrollable', () {
    testTwk('lists the keys that would move it, as it moves', (t) async {
      await t.pumpWidget(
        SingleChildScrollView(autofocus: true, child: column(9)),
        size: (20, 5),
      );
      expect(hints(t), _top);
      await t.press('down');
      await t.pump();
      expect(hints(t), _middle);
      await t.press('end');
      await t.pump();
      expect(hints(t), _bottom);
      await t.press('home');
      await t.pump();
      expect(hints(t), _top);
    });

    testTwk('a KeyHintsBar follows them in the frame after the key', (
      t,
    ) async {
      await t.pumpWidget(
        withBar(SingleChildScrollView(autofocus: true, child: column(9))),
        size: (60, 5),
      );
      expect(t.lines[4], 'down scroll · pagedown a window · end the ends');
      await t.press('down');
      await t.pump();
      // the keys back too, however the bar puts those of one hint
      expect(
        t.lines[4],
        allOf(contains('up'), contains('pageup'), contains('home')),
      );
      await t.press('end');
      await t.pump();
      expect(t.lines[4], 'up scroll · pageup a window · home the ends');
    });

    testTwk('lists none with nothing to scroll, and once the content '
        'outgrows the window, those on', (t) async {
      final rows = ValueNotifier(2);
      await t.pumpWidget(
        withBar(
          ListenableBuilder(
            listenable: rows,
            builder: (context, _) => SingleChildScrollView(
              autofocus: true,
              child: column(rows.value),
            ),
          ),
        ),
        size: (60, 5),
      );
      expect(hints(t), isEmpty);
      expect(t.lines[4].trim(), isEmpty);
      rows.value = 9;
      await t.pump();
      await t.pump();
      expect(hints(t), _top);
      expect(t.lines[4], 'down scroll · pagedown a window · end the ends');
    });

    testTwk('along a horizontal axis, Left and Right', (t) async {
      await t.pumpWidget(
        const SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          autofocus: true,
          child: Text('a line far wider than the window'),
        ),
        size: (10, 2),
      );
      expect(hints(t), ['right scroll', 'pagedown a window', 'end the ends']);
      await t.press('right');
      await t.pump();
      expect(hints(t), [
        'left scroll',
        'right scroll',
        'pageup a window',
        'pagedown a window',
        'home the ends',
        'end the ends',
      ]);
    });

    testTwk('keyHints false: none, the keys scrolling it still', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        SingleChildScrollView(
          controller: controller,
          autofocus: true,
          keyHints: false,
          child: column(9),
        ),
        size: (20, 5),
      );
      expect(hints(t), isEmpty);
      await t.press('down');
      await t.pump();
      expect(controller.offset, 1);
      expect(hints(t), isEmpty);
    });

    testTwk('a key at an end goes on to the nodes above, whose hint shows '
        'in place of its own', (t) async {
      final pressed = <String>[];
      await t.pumpWidget(
        KeyBindings(
          {'up': () => pressed.add('up'), 'down': () => pressed.add('down')},
          hints: const {'up': 'above', 'down': 'below'},
          child: SingleChildScrollView(autofocus: true, child: column(9)),
        ),
        size: (20, 5),
      );
      expect(hints(t), [..._top, 'up above']);
      await t.press('up');
      await t.press('down');
      expect(pressed, ['up']);
    });

    testTwk('a focused widget inside it: its keys first, then the '
        "scrollable's", (t) async {
      await t.pumpWidget(
        SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeyBindings(
                {'space': () {}},
                hints: const {'space': 'press'},
                child: const Focus(autofocus: true, child: Text('button')),
              ),
              column(9),
            ],
          ),
        ),
        size: (20, 5),
      );
      expect(hints(t), ['space press', ..._top]);
    });

    testTwk('one that does not take the focus, under a focused node that '
        'takes its keys (a SelectionList), lists none of its own', (t) async {
      await t.pumpWidget(
        SelectionList(
          autofocus: true,
          itemCount: 20,
          itemBuilder: (context, index) => Text('item $index'),
          keyOf: (index) => index,
        ),
        size: (20, 5),
      );
      expect(hints(t), isEmpty);
      await t.press('down');
      await t.pump();
      expect(hints(t), isEmpty);
    });
  });

  group('a ListView', () {
    testTwk('lists the keys that would scroll it; none when all of it '
        'shows, or with keyHints false', (t) async {
      final items = ValueNotifier(30);
      final hinted = ValueNotifier(true);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: Listenable.merge([items, hinted]),
          builder: (context, _) => ListView.builder(
            autofocus: true,
            keyHints: hinted.value,
            itemCount: items.value,
            itemBuilder: (context, index) => Text('item $index'),
          ),
        ),
        size: (20, 5),
      );
      expect(hints(t), _top);
      await t.press('pagedown');
      await t.pump();
      expect(hints(t), _middle);
      hinted.value = false;
      await t.pump();
      expect(hints(t), isEmpty);
      hinted.value = true;
      items.value = 3;
      await t.pump();
      await t.pump();
      expect(hints(t), isEmpty);
    });

    testTwk('one that sticks to the bottom starts with the keys back', (
      t,
    ) async {
      await t.pumpWidget(
        ListView(
          autofocus: true,
          stickToBottom: true,
          children: [for (var i = 0; i < 30; i++) Text('item $i')],
        ),
        size: (20, 5),
      );
      expect(hints(t), _bottom);
    });
  });
}
