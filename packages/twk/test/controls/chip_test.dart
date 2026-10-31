// Chip and ChipList: chips on surface, selected ones filled, × where they
// can be removed; a list that wraps; one stop of Tab whose arrows move the
// highlight; Space, Enter, Delete and Backspace; clicks on a chip and on
// its ×; disabled chips and a disabled list; plain output; read as
// checkboxes.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../text/plain_lines.dart';

const List<Choice<String>> tags = [
  Choice('dart', 'dart'),
  Choice('tui', 'tui'),
  Choice('beta', 'beta', enabled: false),
  Choice('terminal', 'terminal'),
];

List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

/// A list of [chips] that keeps its chips and what is on, reporting each
/// press to [pressed] and each removal to [removed], then a button.
Widget list(
  ValueNotifier<List<Choice<String>>> chips,
  ValueNotifier<Set<String>> on, {
  List<String>? pressed,
  List<String>? removed,
  bool press = true,
  bool remove = true,
  FocusNode? focusNode,
}) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    ListenableBuilder(
      listenable: Listenable.merge([chips, on]),
      builder: (context, _) => ChipList<String>(
        chips: chips.value,
        selected: on.value,
        focusNode: focusNode,
        onPressed: press
            ? (v) {
                pressed?.add(v);
                on.value = on.value.contains(v)
                    ? ({...on.value}..remove(v))
                    : {...on.value, v};
              }
            : null,
        onRemove: remove
            ? (v) {
                removed?.add(v);
                chips.value = [...chips.value.where((c) => c.value != v)];
              }
            : null,
      ),
    ),
    Button(
      'next',
      focusNode: FocusNode(debugLabel: 'next'),
      onPressed: () {},
    ),
  ],
);

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

void main() {
  testTwk('a chip is its label between blanks, × after it where removable; '
      'selected in the primary color filled and bold, a disabled one '
      'muted', (t) async {
    await t.pumpWidget(
      const Theme.terminal(
        child: Row(
          gap: 1,
          children: [
            Chip('a'),
            Chip('b', selected: true, removable: true),
            Chip('c', enabled: false),
          ],
        ),
      ),
      size: (30, 1),
    );
    expect(t.lines, [' a   b ×   c']);
    expect(t, styleAt(5, 0, hasAttr(Attr.bold)));
    expect(t, styleAt(1, 0, isNot(hasAttr(Attr.bold))));
    expect(t, styleAt(11, 0, hasFg(const Color.indexed(245))));
  });

  testTwk('the chips wrap onto rows at the width, a blank between two', (
    t,
  ) async {
    final chips = ValueNotifier(tags);
    final on = ValueNotifier(<String>{});
    await t.pumpWidget(Theme.terminal(child: list(chips, on)), size: (16, 4));
    // ' dart ' 6, ' tui ' 5, ' beta ' 6, ' terminal ' 10, × 2 each
    expect(t.lines.take(3), [' dart ×   tui ×', ' beta ×', ' terminal ×']);
    // one column less and the second chip does not fit
    await t.pumpWidget(Theme.terminal(child: list(chips, on)), size: (15, 5));
    expect(t.lines.take(4), [' dart ×', ' tui ×', ' beta ×', ' terminal ×']);
  });

  testTwk('one stop of Tab; arrows move the highlight over the enabled '
      'chips, round; Up and Down between rows; hinted', (t) async {
    final chips = ValueNotifier(tags);
    final on = ValueNotifier(<String>{});
    final node = FocusNode(debugLabel: 'tags');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: list(chips, on, focusNode: node)),
      size: (16, 4),
    );
    await press(t, 'tab');
    expect(focused(t), 'tags');
    expect(hints(t), [
      'left previous',
      'right next',
      'space toggle',
      'delete remove',
    ]);
    const lit = Color.indexed(237);
    expect(t, styleAt(1, 0, hasBg(lit)));
    await press(t, 'right');
    expect(t, styleAt(10, 0, hasBg(lit)));
    expect(t, styleAt(1, 0, isNot(hasBg(lit))));
    // down: the row below has beta (disabled) and terminal: terminal
    await press(t, 'down');
    expect(t, styleAt(2, 2, hasBg(lit)));
    await press(t, 'down');
    expect(t, styleAt(2, 2, hasBg(lit)));
    await press(t, 'up');
    expect(t, styleAt(1, 0, hasBg(lit)));
    await press(t, 'end');
    expect(t, styleAt(2, 2, hasBg(lit)));
    // round, past beta
    await press(t, 'right');
    expect(t, styleAt(1, 0, hasBg(lit)));
    await press(t, 'left');
    expect(t, styleAt(2, 2, hasBg(lit)));
    await press(t, 'home');
    expect(t, styleAt(1, 0, hasBg(lit)));
    await press(t, 'tab');
    expect(focused(t), 'next');
    expect(t, styleAt(1, 0, isNot(hasBg(lit))));
  });

  testTwk('Space and Enter press the highlighted chip, Delete and '
      'Backspace remove it; the highlight stays in place, or on the last '
      'chip', (t) async {
    final chips = ValueNotifier(tags);
    final on = ValueNotifier(<String>{});
    final pressed = <String>[];
    final removed = <String>[];
    final node = FocusNode(debugLabel: 'tags');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: list(
          chips,
          on,
          pressed: pressed,
          removed: removed,
          focusNode: node,
        ),
      ),
      size: (30, 4),
    );
    node.requestFocus();
    await t.pump();
    await press(t, 'space right enter');
    expect(pressed, ['dart', 'tui']);
    expect(on.value, {'dart', 'tui'});
    await press(t, 'space');
    expect(on.value, {'dart'});
    await press(t, 'delete');
    expect(removed, ['tui']);
    // the list is dart, beta, terminal; the highlight was on the second
    // place, beta, which is disabled: it went back to dart
    expect(t.lines.first, ' dart ×   beta ×   terminal ×');
    await press(t, 'end backspace');
    expect(removed, ['tui', 'terminal']);
    // the last chip now is beta, disabled: the highlight went to dart
    await press(t, 'space');
    expect(pressed.last, 'dart');
  });

  testTwk('a click on a chip presses it, on its × removes it, between '
      'chips nothing; the clicked chip is highlighted', (t) async {
    final chips = ValueNotifier(tags);
    final on = ValueNotifier(<String>{});
    final pressed = <String>[];
    final removed = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: list(chips, on, pressed: pressed, removed: removed),
      ),
      size: (30, 4),
    );
    // ' dart ×   tui ×   beta ×': dart 0-7, tui 9-15, beta 17-24
    await t.click(2, 0);
    await t.pump();
    expect(pressed, ['dart']);
    expect(t, styleAt(1, 0, hasBg(const Color.indexed(237))));
    await t.click(8, 0);
    await t.pump();
    expect(pressed, ['dart']);
    await t.click(11, 0);
    await t.pump();
    expect(pressed, ['dart', 'tui']);
    // the × of dart, and the blank after it
    await t.click(6, 0);
    await t.pump();
    expect(removed, ['dart']);
    expect(t.lines.first, ' tui ×   beta ×   terminal ×');
    await t.click(5, 0);
    await t.pump();
    expect(removed, ['dart', 'tui']);
    // a disabled chip takes no click
    await t.click(2, 0);
    await t.click(7, 0);
    await t.pump();
    expect(removed, ['dart', 'tui']);
    expect(pressed, ['dart', 'tui']);
  });

  testTwk('without onRemove no ×, no Delete; without onPressed a click '
      'only highlights; with neither the list takes no focus', (t) async {
    final chips = ValueNotifier(tags);
    final on = ValueNotifier(<String>{});
    final node = FocusNode(debugLabel: 'tags');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: list(chips, on, remove: false, focusNode: node)),
      size: (30, 4),
    );
    expect(t.lines.first, ' dart   tui   beta   terminal');
    node.requestFocus();
    await t.pump();
    expect(hints(t), ['left previous', 'right next', 'space toggle']);
    await t.pumpWidget(
      Theme.terminal(
        child: list(chips, on, press: false, remove: false, focusNode: node),
      ),
    );
    // a list that only removes: Space does nothing, a click on a chip
    // highlights it
    final removed = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: list(chips, on, press: false, removed: removed, focusNode: node),
      ),
    );
    await t.click(11, 0);
    await t.pump();
    expect(t, styleAt(11, 0, hasBg(const Color.indexed(237))));
    await press(t, 'space');
    expect(on.value, isEmpty);
    expect(removed, isEmpty);
    await press(t, 'delete');
    expect(removed, ['tui']);
    await t.pumpWidget(
      Theme.terminal(
        child: list(chips, on, press: false, remove: false, focusNode: node),
      ),
    );
    await press(t, 'tab');
    expect(focused(t), 'next');
  });

  testTwk('a screen reader reads checkboxes, checked while selected; the '
      'highlighted chip focused', (t) async {
    final chips = ValueNotifier(tags);
    final on = ValueNotifier({'tui'});
    final node = FocusNode(debugLabel: 'tags');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: list(chips, on, focusNode: node)),
      size: (30, 4),
    );
    node.requestFocus();
    await t.pump();
    expect(t.binding.semantics.lines.take(4), [
      'checkbox dart, not checked',
      'checkbox tui, checked',
      'checkbox beta, not checked, disabled',
      'checkbox terminal, not checked',
    ]);
    expect(t.binding.semantics.focusedLine, 0);
    await press(t, 'right');
    expect(t.binding.semantics.focusedLine, 1);
  });

  testTwk('the hidden cursor rests on the highlighted chip', (t) async {
    final chips = ValueNotifier(tags);
    final on = ValueNotifier(<String>{});
    final node = FocusNode(debugLabel: 'tags');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: list(chips, on, focusNode: node)),
      size: (30, 4),
    );
    node.requestFocus();
    await t.pump();
    expect(t.cursor, (0, 0));
    await press(t, 'right');
    expect(t.cursor, (9, 0));
  });

  testTwk('a label too long for the row is cut off with …', (t) async {
    final chips = ValueNotifier(const [Choice('x', 'a very long label')]);
    final on = ValueNotifier(<String>{});
    await t.pumpWidget(Theme.terminal(child: list(chips, on)), size: (10, 2));
    expect(t.lines.first.trimRight().length, lessThanOrEqualTo(10));
    expect(t.lines.first, contains('…'));
  });

  test('on plain output a selected chip shows ✓ before its label', () async {
    final lines = await plainLines(
      ChipList<String>(
        chips: const [Choice('a', 'a'), Choice('b', 'b')],
        selected: const {'b'},
        onPressed: (_) {},
      ),
      width: 30,
    );
    expect(lines, [' a   ✓ b']);
  });
}
