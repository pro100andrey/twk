// RadioGroup: the marks, one stop of Tab whose arrows choose the choice
// before and after, round, passing disabled ones by; Space and Enter
// choosing the one that shows the focus; clicks; a group across; a
// disabled group out of the focus and the mouse.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

/// Presses each key of [keys], pumping a frame after each.
Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

Future<void> click(TwkTester t, int x, int y) async {
  await t.click(x, y);
  await t.pump();
}

const List<Choice<String>> fruit = [
  Choice('a', 'Apple'),
  Choice('b', 'Banana', enabled: false),
  Choice('c', 'Cherry'),
  Choice('d', 'Date'),
];

/// A [RadioGroup] of [fruit] whose value [value] holds.
Widget group(
  ValueNotifier<String?> value, {
  FocusNode? node,
  Axis direction = Axis.vertical,
  bool enabled = true,
}) => ValueListenableBuilder<String?>(
  valueListenable: value,
  builder: (context, v, _) => RadioGroup<String>(
    choices: fruit,
    value: v,
    onChanged: enabled ? (next) => value.value = next : null,
    direction: direction,
    focusNode: node,
  ),
);

void main() {
  testTwk(
    '(●) marks the choice chosen, ( ) the others; Down and Up choose '
    'the enabled one after and before, round, Home and End the first '
    'and the last; hinted; the chosen one selected while focused',
    (
      t,
    ) async {
      final value = ValueNotifier<String?>('a');
      addTearDown(value.dispose);
      final node = FocusNode(debugLabel: 'fruit');
      addTearDown(node.dispose);
      await t.pumpWidget(
        Theme.terminal(child: group(value, node: node)),
        size: (12, 4),
      );
      expect(t.lines, ['(●) Apple', '( ) Banana', '( ) Cherry', '( ) Date']);
      expect(t, styleAt(1, 0, allOf(hasFg(Color.blue), hasAttr(Attr.bold))));
      expect(t, styleAt(1, 1, hasFg(const Color.indexed(245))));
      await press(t, 'down');
      expect(value.value, 'a');
      node.requestFocus();
      await t.pump();
      expect(t, styleAt(5, 0, hasBg(const Color.indexed(237))));
      expect(hints(t), ['up previous', 'down next']);
      final seen = <String?>[];
      for (final key in ['down', 'down', 'down', 'up', 'up', 'end', 'home']) {
        await press(t, key);
        seen.add(value.value);
      }
      expect(seen, ['c', 'd', 'a', 'd', 'c', 'd', 'a']);
      expect(t.lines, ['(●) Apple', '( ) Banana', '( ) Cherry', '( ) Date']);
      await press(t, 'right right left');
      expect(value.value, 'c');
      expect(t, styleAt(5, 2, hasBg(const Color.indexed(237))));
      expect(t, styleAt(5, 0, isNot(hasBg(const Color.indexed(237)))));
    },
  );

  testTwk('with none chosen, the first enabled one shows the focus: Space '
      'and Enter choose it, Down the first and Up the last', (t) async {
    final value = ValueNotifier<String?>(null);
    addTearDown(value.dispose);
    final node = FocusNode(debugLabel: 'fruit');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: group(value, node: node)),
      size: (12, 4),
    );
    expect(t.lines.first, '( ) Apple');
    node.requestFocus();
    await t.pump();
    expect(t, styleAt(5, 0, hasBg(const Color.indexed(237))));
    await press(t, 'space');
    expect(value.value, 'a');
    value.value = null;
    await t.pump();
    await press(t, 'enter');
    expect(value.value, 'a');
    value.value = null;
    await t.pump();
    await press(t, 'down');
    expect(value.value, 'a');
    value.value = null;
    await t.pump();
    await press(t, 'up');
    expect(value.value, 'd');
    value.value = 'b';
    await t.pump();
    // a disabled choice is not chosen: Down goes from none
    expect(t.lines[1], '( ) Banana');
    await press(t, 'down');
    expect(value.value, 'a');
  });

  testTwk('a choice clicked is chosen and focuses the group; a disabled one '
      'is not', (t) async {
    final value = ValueNotifier<String?>('a');
    addTearDown(value.dispose);
    final node = FocusNode(debugLabel: 'fruit');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: group(value, node: node)),
      size: (12, 4),
    );
    await click(t, 6, 3);
    expect(value.value, 'd');
    expect(focused(t), 'fruit');
    expect(t.lines.last, '(●) Date');
    await click(t, 6, 1);
    expect(value.value, 'd');
    await click(t, 1, 2);
    expect(value.value, 'c');
  });

  testTwk('across, two blanks between the choices, Left and Right hinted', (
    t,
  ) async {
    final value = ValueNotifier<String?>('c');
    addTearDown(value.dispose);
    final node = FocusNode(debugLabel: 'fruit');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: group(value, node: node, direction: Axis.horizontal),
      ),
      size: (50, 1),
    );
    expect(t.lines, ['( ) Apple  ( ) Banana  (●) Cherry  ( ) Date']);
    node.requestFocus();
    await t.pump();
    expect(hints(t), ['left previous', 'right next']);
    await press(t, 'right');
    expect(value.value, 'd');
    await click(t, 2, 0);
    expect(value.value, 'a');
  });

  testTwk('disabled without onChanged: all muted, passed by by Tab, deaf '
      'to clicks; as is a group with no enabled choice', (t) async {
    final value = ValueNotifier<String?>('a');
    addTearDown(value.dispose);
    final node = FocusNode(debugLabel: 'fruit');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: Column(
          children: [
            group(value, node: node, enabled: false),
            RadioGroup<int>(
              choices: const [Choice(1, 'one', enabled: false)],
              value: null,
              onChanged: (_) {},
              focusNode: FocusNode(debugLabel: 'none'),
            ),
            const Focus(debugLabel: 'next', child: Text('next')),
          ],
        ),
      ),
      size: (12, 6),
    );
    expect(t, styleAt(1, 0, hasFg(const Color.indexed(245))));
    expect(t, styleAt(1, 0, isNot(hasAttr(Attr.bold))));
    await press(t, 'tab');
    expect(focused(t), 'next');
    await press(t, 'tab');
    expect(focused(t), 'next');
    await click(t, 2, 3);
    expect(value.value, 'a');
    expect(focused(t), 'next');
  });

  testTwk('a disabled group leaves its keys to the layers above, alone in '
      'the app too, where a key with no node focused walks down past it', (
    t,
  ) async {
    final value = ValueNotifier<String?>('a');
    addTearDown(value.dispose);
    final seen = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: KeyBindings(
          {'down': () => seen.add('down'), 'space': () => seen.add('space')},
          child: group(value, enabled: false),
        ),
      ),
      size: (12, 4),
    );
    await t.type('\x1b[B \t\x1b[B');
    await t.pump();
    expect(seen, ['down', 'space', 'down']);
    expect(value.value, 'a');
    expect(hints(t), isEmpty);
  });

  test('a Choice is equal to another of the same value, label and enabled', () {
    const a = Choice('a', 'Apple');
    expect(a, Choice('a', 'Apple', enabled: a.enabled));
    expect(a.hashCode, Choice('a', 'Apple', enabled: a.enabled).hashCode);
    expect(a, isNot(const Choice('a', 'Avocado')));
    expect(a, isNot(const Choice('b', 'Apple')));
    expect(a, isNot(const Choice('a', 'Apple', enabled: false)));
  });

  test('a Choice describes itself by its value and label', () {
    expect('${const Choice(1, 'One')}', 'Choice(1, One)');
  });
}
