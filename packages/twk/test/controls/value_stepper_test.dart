// ValueStepper: the value between ‹ and ›, padded to the widest so that
// the arrows keep their places; Left and Right and clicks on the arrows
// step round, past a disabled value; one stop of Tab; disabled; a value
// that is none of the values; cut off to fit; read as a slider.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const List<Choice<String>> modes = [
  Choice('dark', 'dark'),
  Choice('light', 'light'),
  Choice('sepia', 'sepia', enabled: false),
  Choice('auto', 'auto-switching'),
];

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

Widget stepper(
  ValueNotifier<String> value, {
  List<String>? changes,
  List<Choice<String>> values = modes,
  bool enabled = true,
  bool wrap = true,
  FocusNode? focusNode,
}) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    ValueListenableBuilder(
      valueListenable: value,
      builder: (context, v, _) => ValueStepper<String>(
        values: values,
        value: v,
        focusNode: focusNode,
        wrap: wrap,
        onChanged: enabled
            ? (next) {
                changes?.add(next);
                value.value = next;
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

void main() {
  testTwk('the value between ‹ and ›, padded to the widest label so that '
      '› stays in its place; the arrows in the primary color', (t) async {
    final v = ValueNotifier('dark');
    await t.pumpWidget(Theme.terminal(child: stepper(v)), size: (30, 2));
    expect(t.lines.first, '‹ dark           ›');
    expect(t, styleAt(0, 0, hasFg(Color.blue)));
    expect(t, styleAt(17, 0, hasFg(Color.blue)));
    expect(t, styleAt(3, 0, isNot(hasFg(Color.blue))));
    v.value = 'auto';
    await t.pump();
    expect(t.lines.first, '‹ auto-switching ›');
  });

  testTwk('Left and Right step to the value before and after, round and '
      'past a disabled one; one stop of Tab; hinted', (t) async {
    final v = ValueNotifier('dark');
    final changes = <String>[];
    final node = FocusNode(debugLabel: 'mode');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: stepper(v, changes: changes, focusNode: node),
      ),
      size: (30, 2),
    );
    await press(t, 'tab');
    expect(focused(t), 'mode');
    expect(
      [
        for (final k in t.binding.focusManager.activeKeys)
          if (k.hint != null) '$k',
      ],
      ['left previous', 'right next'],
    );
    expect(t, styleAt(5, 0, hasBg(const Color.indexed(237))));
    await press(t, 'right');
    expect(v.value, 'light');
    await press(t, 'right');
    expect(v.value, 'auto');
    await press(t, 'right');
    expect(v.value, 'dark');
    await press(t, 'left');
    expect(v.value, 'auto');
    await press(t, 'left left');
    expect(changes, ['light', 'auto', 'dark', 'auto', 'light', 'dark']);
    await press(t, 'tab');
    expect(focused(t), 'next');
    expect(t, styleAt(5, 0, isNot(hasBg(const Color.indexed(237)))));
  });

  testTwk('by default it stops at the first and the last value, the arrow '
      'there muted and a click on it nothing; wrap: true goes round', (
    t,
  ) async {
    final v = ValueNotifier('light');
    final changes = <String>[];
    final node = FocusNode(debugLabel: 'mode');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: ValueListenableBuilder(
          valueListenable: v,
          builder: (context, value, _) => ValueStepper<String>(
            values: modes,
            value: value,
            focusNode: node,
            onChanged: (next) {
              changes.add(next);
              v.value = next;
            },
          ),
        ),
      ),
      size: (30, 2),
    );
    node.requestFocus();
    await t.pump();
    await press(t, 'left');
    expect(v.value, 'dark');
    expect(t, styleAt(0, 0, hasFg(const Color.indexed(245))));
    expect(t, styleAt(17, 0, hasFg(Color.blue)));
    await press(t, 'left');
    await t.click(0, 0);
    await t.pump();
    expect(changes, ['dark']);
    // past the disabled one, then the last
    await press(t, 'right right');
    expect(v.value, 'auto');
    expect(t, styleAt(17, 0, hasFg(const Color.indexed(245))));
    expect(t, styleAt(0, 0, hasFg(Color.blue)));
    await press(t, 'right');
    await t.click(17, 0);
    await t.pump();
    expect(changes, ['dark', 'light', 'auto']);
  });

  testTwk('a click on ‹ steps back, on › forward, on the value nothing; it '
      'takes the focus', (t) async {
    final v = ValueNotifier('light');
    final changes = <String>[];
    await t.pumpWidget(
      Theme.terminal(child: stepper(v, changes: changes)),
      size: (30, 2),
    );
    await t.click(17, 0);
    await t.pump();
    expect(changes, ['auto']);
    expect(focused(t), isNot('next'));
    await t.click(8, 0);
    await t.pump();
    expect(changes, ['auto']);
    await t.click(0, 0);
    await t.pump();
    expect(changes, ['auto', 'light']);
    // the blank next to an arrow is the value's
    await t.click(1, 0);
    await t.click(16, 0);
    await t.pump();
    expect(changes, hasLength(2));
  });

  testTwk('a value that is none of the values shows nothing; Right steps '
      'to the first, Left to the last', (t) async {
    final v = ValueNotifier('nope');
    final node = FocusNode(debugLabel: 'mode');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: stepper(v, focusNode: node)),
      size: (30, 2),
    );
    expect(t.lines.first, '‹                ›');
    node.requestFocus();
    await t.pump();
    await press(t, 'right');
    expect(v.value, 'dark');
    v.value = 'nope';
    await t.pump();
    await press(t, 'left');
    expect(v.value, 'auto');
  });

  testTwk('without onChanged, or with fewer than two enabled values, it '
      'is muted and takes neither focus nor click', (t) async {
    final v = ValueNotifier('dark');
    final changes = <String>[];
    await t.pumpWidget(
      Theme.terminal(child: stepper(v, enabled: false, changes: changes)),
      size: (30, 2),
    );
    expect(t, styleAt(0, 0, hasFg(const Color.indexed(245))));
    await press(t, 'tab');
    expect(focused(t), 'next');
    await t.click(17, 0);
    await t.pump();
    expect(changes, isEmpty);
    await t.pumpWidget(
      Theme.terminal(
        child: stepper(
          v,
          changes: changes,
          values: const [
            Choice('dark', 'dark'),
            Choice('x', 'x', enabled: false),
          ],
        ),
      ),
    );
    await t.click(7, 0);
    await t.pump();
    expect(changes, isEmpty);
  });

  testTwk('a label wider than the room is cut off with …', (t) async {
    final v = ValueNotifier('auto');
    await t.pumpWidget(Theme.terminal(child: stepper(v)), size: (12, 2));
    expect(t.lines.first, '‹ auto-sw… ›');
  });

  testTwk('the hidden cursor rests on ‹ while it has the focus', (t) async {
    final v = ValueNotifier('dark');
    final node = FocusNode(debugLabel: 'mode');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: stepper(v, focusNode: node)),
      size: (30, 2),
    );
    node.requestFocus();
    await t.pump();
    expect(t.cursor, (0, 0));
  });

  testTwk('a screen reader reads a slider of the label of the value, '
      'disabled while it is', (t) async {
    final v = ValueNotifier('light');
    await t.pumpWidget(Theme.terminal(child: stepper(v)), size: (30, 2));
    expect(t.binding.semantics.lines.first, startsWith('slider light'));
    await t.pumpWidget(
      Theme.terminal(child: stepper(v, enabled: false)),
    );
    expect(t.binding.semantics.lines.first, endsWith('disabled'));
  });
}
