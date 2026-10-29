// Select and MultiSelect: the field, the list opened by the keys and the
// mouse in a popup under it or inline below it, the highlighted choice
// moved and chosen, typing that filters by fuzzyMatch, the popup closed
// by Escape, the focus leaving and a press outside; marks and toggles of
// a MultiSelect; a disabled select out of the focus and the mouse.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

/// Presses each key of [keys], pumping after each until the app is idle:
/// a popup that fades in or out has done so.
Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pumpUntilIdle();
  }
}

Future<void> click(TwkTester t, int x, int y) async {
  await t.click(x, y);
  await t.pumpUntilIdle();
}

const List<Choice<String>> fruit = [
  Choice('a', 'Apple'),
  Choice('b', 'Banana'),
  Choice('c', 'Cherry', enabled: false),
  Choice('d', 'Date'),
  Choice('e', 'Elderberry'),
];

/// [select] above a node `next`, in an overlay.
Widget app(Widget select) => Overlay(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      select,
      const Focus(debugLabel: 'next', child: Text('next')),
    ],
  ),
);

/// A [Select] of [choices] whose value [value] holds.
Widget select(
  ValueNotifier<String?> value, {
  List<Choice<String>> choices = fruit,
  bool inline = false,
  bool enabled = true,
  int rows = 8,
}) {
  final node = FocusNode(debugLabel: 'select');
  addTearDown(node.dispose);
  return ValueListenableBuilder<String?>(
    valueListenable: value,
    builder: (context, v, _) => Select<String>(
      choices: choices,
      value: v,
      onChanged: enabled ? (next) => value.value = next : null,
      hint: 'fruit?',
      inline: inline,
      rows: rows,
      focusNode: node,
    ),
  );
}

/// A [MultiSelect] of [fruit] whose values [values] holds.
Widget multi(ValueNotifier<Set<String>> values, {bool inline = false}) =>
    ValueListenableBuilder<Set<String>>(
      valueListenable: values,
      builder: (context, v, _) => MultiSelect<String>(
        choices: fruit,
        values: v,
        onChanged: (next) => values.value = next,
        hint: 'none',
        inline: inline,
        autofocus: true,
      ),
    );

void main() {
  group('Select', () {
    testTwk('the field shows the label chosen, or the hint muted; Enter '
        'opens the enabled choices under it, the chosen one highlighted; '
        'Down and Up move round, Enter chooses and closes, Escape closes; '
        'hinted', (t) async {
      final value = ValueNotifier<String?>(null);
      addTearDown(value.dispose);
      await t.pumpWidget(
        Theme.terminal(child: app(select(value))),
        size: (20, 8),
      );
      expect(t.lines, [' fruit?     ▾', 'next', '', '', '', '', '', '']);
      expect(t, styleAt(1, 0, hasFg(const Color.indexed(245))));
      value.value = 'b';
      await t.pump();
      expect(t.lines.first, ' Banana     ▾');
      await press(t, 'tab');
      expect(focused(t), 'select');
      // a chip filled with the primary color
      expect(t, styleAt(1, 0, allOf(hasBg(Color.blue), hasAttr(Attr.bold))));
      expect(t, styleAt(12, 0, hasBg(Color.blue)));
      expect(hints(t), ['enter open']);
      await press(t, 'enter');
      expect(t.lines, [
        ' Banana     ▾',
        ' Apple',
        '▎Banana',
        ' Date',
        ' Elderberry',
        '',
        '',
        '',
      ]);
      expect(t, styleAt(1, 2, hasBg(const Color.indexed(237))));
      expect(t, styleAt(1, 1, isNot(hasBg(const Color.indexed(237)))));
      // the popover's Escape hinted too
      expect(hints(t), ['enter choose', 'escape close']);
      await press(t, 'down down down up');
      expect(t, styleAt(1, 4, hasBg(const Color.indexed(237))));
      await press(t, 'down');
      expect(t, styleAt(1, 1, hasBg(const Color.indexed(237))));
      await press(t, 'up enter');
      expect(value.value, 'e');
      expect(t.lines.take(2), [' Elderberry ▾', 'next']);
      expect(focused(t), 'select');
      for (final key in ['space', 'up', 'down']) {
        await press(t, key);
        expect(t.lines[1], ' Apple', reason: key);
        await press(t, 'escape');
        expect(t.lines[1], 'next', reason: key);
      }
      expect(value.value, 'e');
      await press(t, 'down');
      await press(t, 'tab');
      expect(focused(t), 'next');
      expect(t.lines.take(2), [' Elderberry ▾', 'next']);
    });

    testTwk("in a theme's colors: a chip of the surface, ▾ muted; focused, "
        'filled with the primary color, its text bold in onPrimary, the '
        'hint a step towards the fill; ▾ kept when the text is cut off', (
      t,
    ) async {
      const dark = ThemeData.dark;
      final value = ValueNotifier<String?>(null);
      addTearDown(value.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: Theme(data: dark, child: app(select(value))),
        ),
        size: (20, 8),
      );
      expect(t.lines.first, ' fruit?     ▾');
      expect(t.cell(0, 0).bg, dark.surface.bg);
      expect(t.cell(12, 0).bg, dark.surface.bg);
      expect(t.cell(12, 0).fg, dark.muted.fg);
      expect(t.cell(1, 0).fg, dark.muted.fg);
      await press(t, 'tab');
      expect(t.cell(0, 0).bg, dark.primary.fg);
      expect(t.cell(12, 0).bg, dark.primary.fg);
      expect(t.cell(12, 0).fg, dark.onPrimary.fg);
      // the hint 0.3 of the way from onPrimary to primary, not bold
      expect(t.cell(1, 0).fg, const Color.rgb(0x2c, 0x43, 0x61));
      expect(t, styleAt(1, 0, isNot(hasAttr(Attr.bold))));
      value.value = 'e';
      await t.pump();
      expect(t, styleAt(1, 0, hasAttr(Attr.bold)));
      expect(t.cell(1, 0).fg, dark.onPrimary.fg);
      // the list a panel of the surface without an outline
      await press(t, 'enter');
      expect(t.lines[1], ' Apple');
      expect(t.cell(0, 1).bg, dark.surface.bg);
      await press(t, 'escape');
      // cut off, the text ends in … and ▾ stays
      await t.pumpWidget(
        Theme.terminal(
          child: Theme(
            data: dark,
            child: app(SizedBox(width: 8, child: select(value))),
          ),
        ),
      );
      expect(t.lines.first, ' Elde… ▾');
    });

    testTwk('style, focusedStyle, arrowStyle and popupLook give a '
        'plain look', (t) async {
      final value = ValueNotifier<String?>('b');
      addTearDown(value.dispose);
      final node = FocusNode(debugLabel: 'select');
      addTearDown(node.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: app(
            ValueListenableBuilder<String?>(
              valueListenable: value,
              builder: (context, v, _) => Select<String>(
                choices: fruit,
                value: v,
                onChanged: (next) => value.value = next,
                focusNode: node,
                style: const Style(),
                focusedStyle: const Style(
                  fg: Color.blue,
                  attrs: Attr.bold | Attr.reverse,
                ),
                arrowStyle: const Style(),
                popupLook: PanelLook.bordered,
              ),
            ),
          ),
        ),
        size: (20, 8),
      );
      expect(t, styleAt(12, 0, isNot(hasFg(const Color.indexed(245)))));
      await press(t, 'tab');
      expect(t, styleAt(1, 0, hasAttr(Attr.reverse)));
      expect(t, styleAt(12, 0, hasAttr(Attr.reverse)));
      await press(t, 'enter');
      expect(t.lines.take(3), [
        ' Banana     ▾',
        '┌────────────┐',
        '│ Apple      │',
      ]);
    });

    testTwk('typing filters the choices by fuzzyMatch, best first, the '
        'characters standing out, the query in the field; Backspace takes '
        'one off; typing opens it; no match says so', (t) async {
      final value = ValueNotifier<String?>('a');
      addTearDown(value.dispose);
      await t.pumpWidget(
        Theme.terminal(child: app(select(value))),
        size: (20, 8),
      );
      await press(t, 'tab enter');
      expect(t, styleAt(1, 1, hasBg(const Color.indexed(237))));
      // the best match highlighted, not the one before that matches too
      await t.type('e');
      await t.pumpUntilIdle();
      expect(t.lines.take(5), [
        ' e          ▾',
        '▎Elderberry',
        ' Apple',
        ' Date',
        '',
      ]);
      // the best match highlighted, its e marked
      expect(
        t,
        styleAt(
          1,
          1,
          allOf(hasBg(const Color.indexed(237)), hasAttr(Attr.bold)),
        ),
      );
      expect(t, styleAt(2, 1, isNot(hasAttr(Attr.bold))));
      expect(t, styleAt(5, 2, allOf(hasFg(Color.blue), hasAttr(Attr.bold))));
      // a key with Ctrl is not typed
      await press(t, 'ctrl+r');
      await t.type('rr');
      await t.pumpUntilIdle();
      expect(t.lines.take(3), [' err        ▾', '▎Elderberry', '']);
      await t.type('x');
      await t.pumpUntilIdle();
      expect(t.lines.take(3), [' errx       ▾', ' no match', '']);
      await press(t, 'enter');
      expect(value.value, 'a');
      await press(t, 'backspace backspace backspace');
      expect(t.lines.take(2), [' e          ▾', '▎Elderberry']);
      await press(t, 'down enter');
      expect(value.value, 'a');
      expect(t.lines.take(2), [' Apple      ▾', 'next']);
      // a blank is typed too: no choice has one
      await t.type('d');
      await t.pumpUntilIdle();
      await press(t, 'space');
      expect(t.lines.take(2), [' d          ▾', ' no match']);
    });

    testTwk('a click on the field opens and closes the list, focusing it; '
        'one on a choice chooses it; a press outside closes it', (t) async {
      final value = ValueNotifier<String?>('a');
      addTearDown(value.dispose);
      await t.pumpWidget(
        Theme.terminal(child: app(select(value))),
        size: (20, 8),
      );
      await click(t, 3, 0);
      expect(focused(t), 'select');
      expect(t.lines[3], ' Date');
      await click(t, 3, 0);
      expect(t.lines[1], 'next');
      await click(t, 3, 0);
      await click(t, 4, 3);
      expect(value.value, 'd');
      expect(t.lines.take(2), [' Date       ▾', 'next']);
      await click(t, 3, 0);
      await click(t, 18, 7);
      expect(t.lines[1], 'next');
      expect(value.value, 'd');
    });

    testTwk('at most rows choices show, the window moving with the '
        'highlighted one; PageDown and PageUp move it a window; a click '
        'chooses the choice shown there', (t) async {
      final value = ValueNotifier<String?>(null);
      addTearDown(value.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: app(
            select(
              value,
              rows: 3,
              choices: [for (var i = 0; i < 10; i++) Choice('$i', 'n$i')],
            ),
          ),
        ),
        size: (20, 8),
      );
      await press(t, 'tab enter');
      expect(t.lines.skip(1).take(3), [
        '▎n0',
        ' n1',
        ' n2',
      ]);
      await press(t, 'down down down');
      expect(t.lines.skip(1).take(3), [
        ' n1',
        ' n2',
        '▎n3',
      ]);
      await press(t, 'pagedown');
      expect(t.lines.skip(1).take(3), [
        ' n4',
        ' n5',
        '▎n6',
      ]);
      expect(t, styleAt(1, 3, hasBg(const Color.indexed(237))));
      await press(t, 'pagedown pagedown');
      expect(t.lines.skip(1).take(3), [
        ' n7',
        ' n8',
        '▎n9',
      ]);
      await press(t, 'pageup');
      expect(t.lines.skip(1).take(3), [
        '▎n6',
        ' n7',
        ' n8',
      ]);
      expect(t, styleAt(1, 1, hasBg(const Color.indexed(237))));
      await click(t, 3, 2);
      expect(value.value, '7');
    });

    testTwk('inline: the list always below the field; Enter chooses, Escape '
        'clears the query, then passes on', (t) async {
      final value = ValueNotifier<String?>('b');
      addTearDown(value.dispose);
      final escaped = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: KeyBindings(
            {'escape': () => escaped.add('esc')},
            child: app(select(value, inline: true)),
          ),
        ),
        size: (20, 8),
      );
      expect(t.lines.take(6), [
        ' Banana     ▾',
        ' Apple',
        ' Banana',
        ' Date',
        ' Elderberry',
        'next',
      ]);
      expect(t, styleAt(1, 2, isNot(hasBg(const Color.indexed(237)))));
      await press(t, 'tab');
      expect(t, styleAt(1, 2, hasBg(const Color.indexed(237))));
      await press(t, 'down enter');
      expect(value.value, 'd');
      await click(t, 2, 1);
      expect(value.value, 'a');
      await t.type('el');
      await t.pumpUntilIdle();
      expect(t.lines.take(3), [' el         ▾', '▎Elderberry', 'next']);
      await press(t, 'escape');
      expect(escaped, isEmpty);
      expect(t.lines[1], '▎Apple');
      await press(t, 'escape');
      expect(escaped, ['esc']);
    });

    testTwk('inline: a choice made from what is typed clears the query, the '
        'field showing its label', (t) async {
      final value = ValueNotifier<String?>('b');
      addTearDown(value.dispose);
      await t.pumpWidget(
        Theme.terminal(child: app(select(value, inline: true))),
        size: (20, 8),
      );
      await press(t, 'tab');
      await t.type('da');
      await t.pumpUntilIdle();
      expect(t.lines.take(2), [' da         ▾', '▎Date']);
      await press(t, 'enter');
      expect(value.value, 'd');
      expect(t.lines.take(5), [
        ' Date       ▾',
        ' Apple',
        ' Banana',
        '▎Date',
        ' Elderberry',
      ]);
    });

    testTwk('inline: the hidden cursor rests on the highlighted choice as it '
        'moves', (t) async {
      final value = ValueNotifier<String?>('b');
      addTearDown(value.dispose);
      await t.pumpWidget(
        Theme.terminal(child: app(select(value, inline: true))),
        size: (20, 8),
      );
      await press(t, 'tab');
      expect(t.cursorVisible, isFalse);
      // Banana, below the field and Apple
      expect(t.cursor, (0, 2));
      await press(t, 'down');
      expect(t.cursor, (0, 3));
      await press(t, 'up up');
      expect(t.cursor, (0, 1));
    });

    testTwk('the highlight stays on its choice as the choices change', (
      t,
    ) async {
      final choices = ValueNotifier(fruit);
      addTearDown(choices.dispose);
      final value = ValueNotifier<String?>('d');
      addTearDown(value.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: app(
            ValueListenableBuilder<List<Choice<String>>>(
              valueListenable: choices,
              builder: (context, list, _) => select(value, choices: list),
            ),
          ),
        ),
        size: (20, 8),
      );
      await press(t, 'tab enter');
      expect(t, styleAt(1, 3, hasBg(const Color.indexed(237))));
      choices.value = [const Choice('z', 'Zucchini'), ...fruit];
      await t.pump();
      expect(t.lines[4], '▎Date');
      expect(t, styleAt(1, 4, hasBg(const Color.indexed(237))));
      await press(t, 'enter');
      expect(value.value, 'd');
    });

    testTwk('inline, it needs no Overlay', (t) async {
      final value = ValueNotifier<String?>('a');
      addTearDown(value.dispose);
      await t.pumpWidget(
        Theme.terminal(child: select(value, inline: true)),
        size: (20, 8),
      );
      expect(t.lines.take(2), [' Apple      ▾', ' Apple']);
    });

    testTwk('disabled without onChanged: muted, passed by by Tab, deaf to '
        'clicks', (t) async {
      final value = ValueNotifier<String?>('a');
      addTearDown(value.dispose);
      await t.pumpWidget(
        Theme.terminal(child: app(select(value, enabled: false))),
        size: (20, 8),
      );
      expect(t, styleAt(1, 0, hasFg(const Color.indexed(245))));
      await press(t, 'tab');
      expect(focused(t), 'next');
      await click(t, 3, 0);
      expect(focused(t), 'next');
      expect(t.lines[1], 'next');
      await t.pumpWidget(
        Theme.terminal(child: app(select(value, enabled: false, inline: true))),
        size: (20, 8),
      );
      expect(t.lines[2], ' Banana');
      await click(t, 3, 2);
      expect(value.value, 'a');
      expect(focused(t), 'next');
    });
  });

  group('MultiSelect', () {
    testTwk('[x] marks the choices selected; Space and a click select or '
        'deselect the highlighted one, the list open; Enter closes; the '
        'field lists the labels selected', (t) async {
      final values = ValueNotifier<Set<String>>({'d'});
      addTearDown(values.dispose);
      await t.pumpWidget(
        Theme.terminal(child: app(multi(values))),
        size: (30, 8),
      );
      expect(t.lines.first, ' Date           ▾');
      await press(t, 'enter');
      expect(t.lines.take(6), [
        ' Date           ▾',
        ' [ ] Apple',
        ' [ ] Banana',
        '▎[x] Date',
        ' [ ] Elderberry',
        '',
      ]);
      expect(hints(t), ['space toggle', 'enter done', 'escape close']);
      await press(t, 'space up up space');
      expect(values.value, {'a'});
      await click(t, 4, 4);
      expect(values.value, {'a', 'e'});
      expect(t.lines[4], '▎[x] Elderberry');
      await t.type('ban');
      await t.pumpUntilIdle();
      expect(t.lines.take(2), [' ban            ▾', '▎[ ] Banana']);
      // the characters of the query stand out past the mark
      expect(t, styleAt(5, 1, hasAttr(Attr.bold)));
      expect(t, styleAt(8, 1, isNot(hasAttr(Attr.bold))));
      await press(t, 'space enter');
      expect(values.value, {'a', 'e', 'b'});
      expect(t.lines.take(2), [' Apple, Banana, Elderberry ▾', 'next']);
    });

    testTwk('inline: the marks below the field, Space toggling', (t) async {
      final values = ValueNotifier<Set<String>>({});
      addTearDown(values.dispose);
      await t.pumpWidget(
        Theme.terminal(child: app(multi(values, inline: true))),
        size: (24, 8),
      );
      expect(t.lines.take(2), [' none           ▾', '▎[ ] Apple']);
      expect(t, styleAt(1, 0, hasAttr(Attr.dim)));
      await press(t, 'down space');
      expect(values.value, {'b'});
      expect(t.lines[2], '▎[x] Banana');
    });
  });

  group('a decorated Select', () {
    testTwk('is drawn in its decoration without a chip, the label in the '
        "box's room, ▾ at its right edge; the focus is the border's, not a "
        'fill; the list opens under the border, as wide as the box, and '
        'chooses', (t) async {
      const dark = ThemeData.dark;
      final value = ValueNotifier<String?>('b');
      addTearDown(value.dispose);
      final node = FocusNode(debugLabel: 'select');
      addTearDown(node.dispose);
      await t.pumpWidget(
        Theme(
          data: dark,
          child: app(
            SizedBox(
              width: 20,
              child: ValueListenableBuilder<String?>(
                valueListenable: value,
                builder: (context, v, _) => Select<String>(
                  choices: fruit,
                  value: v,
                  onChanged: (next) => value.value = next,
                  focusNode: node,
                  decoration: const InputDecoration(
                    labelText: 'Fruit',
                    helperText: 'one',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
          ),
        ),
        size: (20, 8),
      );
      expect(t.lines.take(5), [
        '╭ Fruit ───────────╮',
        '│ Banana         ▾ │',
        '╰──────────────────╯',
        'one',
        'next',
      ]);
      // no chip: the cells of the label on what is under them
      expect(t, styleAt(2, 1, isNot(hasBg(dark.surface.bg!))));
      expect(t, styleAt(17, 1, hasFg(dark.muted.fg!)));
      expect(t, styleAt(0, 0, hasFg(dark.border.fg!)));
      await press(t, 'tab');
      expect(focused(t), 'select');
      expect(t, styleAt(0, 0, hasFg(dark.primary.fg!)));
      expect(t, styleAt(2, 1, isNot(hasBg(dark.primary.fg!))));
      expect(t, styleAt(17, 1, hasFg(dark.primary.fg!)));
      await press(t, 'enter');
      // right under the border, from its left edge, as wide as the box,
      // over the helper
      expect(t.lines.take(6), [
        '╭ Fruit ───────────╮',
        '│ Banana         ▾ │',
        '╰──────────────────╯',
        ' Apple',
        '▎Banana',
        ' Date',
      ]);
      expect(t, styleAt(19, 3, hasBg(dark.surface.bg!)));
      await press(t, 'down enter');
      expect(value.value, 'd');
      expect(t.lines[1], '│ Date           ▾ │');
    });

    testTwk('disabled: in the colors of a disabled decoration, out of the '
        'focus', (t) async {
      const dark = ThemeData.dark;
      await t.pumpWidget(
        Theme(
          data: dark,
          child: app(
            const SizedBox(
              width: 12,
              child: MultiSelect<String>(
                choices: fruit,
                values: {'a'},
                onChanged: null,
                decoration: InputDecoration(labelText: 'Fruit'),
              ),
            ),
          ),
        ),
        size: (12, 4),
      );
      expect(t.lines.take(3), ['Fruit', 'Apple      ▾', '─' * 12]);
      expect(t, styleAt(0, 0, hasFg(dark.muted.fg!)));
      expect(t, styleAt(0, 1, hasFg(dark.muted.fg!)));
      await press(t, 'tab');
      expect(focused(t), 'next');
    });
  });
}
