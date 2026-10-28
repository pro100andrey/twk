// ListTile in the dark theme: its parts in a row, the title primary where
// selected, the subtitle and the trailing muted; tapped by a click and by
// Enter, on the selection while focused and on the hover under the mouse;
// muted and passed by Tab while disabled; a plain row without onTap.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ThemeData theme = ThemeData.dark;

/// [children] in a column 24 wide, at the top left, in the dark theme.
Widget dark(List<Widget> children) => Theme(
  data: theme,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 24,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  ),
);

void main() {
  testTwk('leading, the title over the subtitle, trailing at the right end, '
      'a column apart; the selected title primary and bold', (t) async {
    await t.pumpWidget(
      dark([
        ListTile(
          leading: const Text('▤'),
          title: const Text('notes.md'),
          subtitle: const Text('2 KB'),
          trailing: const Text('›'),
          selected: true,
          onTap: () {},
        ),
        ListTile(title: const Text('todo.md'), onTap: () {}),
      ]),
      size: (24, 3),
    );
    expect(t.lines, ['▤ notes.md             ›', '  2 KB', 'todo.md']);
    expect(
      t,
      styleAt(2, 0, allOf(hasFg(theme.primary.fg!), hasAttr(Attr.bold))),
    );
    expect(t, styleAt(2, 1, hasFg(theme.muted.fg!)));
    expect(t, styleAt(23, 0, hasFg(theme.muted.fg!)));
    expect(t, styleAt(0, 2, hasFg(theme.text.fg!)));
  });

  testTwk('tapped by a click and by Enter or Space while focused, on the '
      'selection then; on the hover under the mouse', (t) async {
    var taps = 0;
    await t.pumpWidget(
      dark([
        ListTile(title: const Text('a'), onTap: () => taps++),
        ListTile(title: const Text('b'), onTap: () => taps++),
      ]),
      size: (24, 2),
    );
    await t.press('tab');
    await t.pump();
    expect(t, styleAt(5, 0, hasBg(theme.selection.bg!)));
    await t.press('enter');
    await t.press('space');
    expect(taps, 2);
    await t.mouse(MouseKind.move, 5, 1);
    await t.pump();
    expect(t, styleAt(5, 1, hasBg(theme.hover.bg!)));
    await t.click(5, 1);
    await t.pump();
    expect(taps, 3);
  });

  testTwk('disabled, muted and passed by Tab; without onTap a row that '
      'takes no focus', (t) async {
    await t.pumpWidget(
      dark([
        ListTile(title: const Text('off'), enabled: false, onTap: () {}),
        const ListTile(title: Text('plain')),
        const Button('next', onPressed: null),
      ]),
      size: (24, 3),
    );
    expect(t, styleAt(0, 0, hasFg(theme.muted.fg!)));
    await t.press('tab');
    await t.pump();
    expect(t.binding.focusManager.primaryFocus, isNull);
  });

  testTwk('disabled and enabled again, no hover left from before: the mouse '
      'that left it meanwhile is heard', (t) async {
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await t.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: enabled,
        builder: (context, on, _) => dark([
          ListTile(title: const Text('a'), enabled: on, onTap: () {}),
          ListTile(title: const Text('b'), onTap: () {}),
        ]),
      ),
      size: (24, 2),
    );
    await t.mouse(MouseKind.move, 5, 0);
    await t.pump();
    expect(t, styleAt(5, 0, hasBg(theme.hover.bg!)));
    enabled.value = false;
    await t.pump();
    expect(t, styleAt(5, 0, isNot(hasBg(theme.hover.bg!))));
    await t.mouse(MouseKind.move, 5, 1);
    await t.pump();
    enabled.value = true;
    await t.pump();
    expect(t, styleAt(5, 0, isNot(hasBg(theme.hover.bg!))));
    expect(t, styleAt(5, 1, hasBg(theme.hover.bg!)));
  });

  testTwk('without onTap and with it again, no hover left from before: the '
      'mouse left it while it heard none', (t) async {
    final tappable = ValueNotifier(true);
    addTearDown(tappable.dispose);
    await t.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: tappable,
        builder: (context, on, _) => dark([
          ListTile(title: const Text('a'), onTap: on ? () {} : null),
          ListTile(title: const Text('b'), onTap: () {}),
        ]),
      ),
      size: (24, 2),
    );
    await t.mouse(MouseKind.move, 5, 0);
    await t.pump();
    expect(t, styleAt(5, 0, hasBg(theme.hover.bg!)));
    tappable.value = false;
    await t.pump();
    expect(t, styleAt(5, 0, isNot(hasBg(theme.hover.bg!))));
    await t.mouse(MouseKind.move, 5, 1);
    await t.pump();
    tappable.value = true;
    await t.pump();
    expect(t, styleAt(5, 0, isNot(hasBg(theme.hover.bg!))));
    expect(t, styleAt(5, 1, hasBg(theme.hover.bg!)));
  });
}
