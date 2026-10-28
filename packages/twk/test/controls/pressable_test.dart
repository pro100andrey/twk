// Button and the toggles: what each shows, the keys while it has the
// focus and their hints, clicks, and a disabled one out of the focus and
// the mouse; Checkbox and Switch flipping their value through the app,
// ConfirmInput answering by key, by the highlighted answer and by click.
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

/// What [build] builds from [value], which the app sets through it.
Widget hold<T>(
  ValueNotifier<T> value,
  Widget Function(T value, void Function(T value) set) build,
) => ValueListenableBuilder<T>(
  valueListenable: value,
  builder: (context, v, _) => build(v, (next) => value.value = next),
);

void main() {
  group('Button', () {
    testTwk('its label with a blank on either side in the primary color, '
        'bold; Enter and Space press it while it has the focus, Enter '
        'hinted, the chip filled with the primary color', (t) async {
      final pressed = <String>[];
      final node = FocusNode(debugLabel: 'save');
      addTearDown(node.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Button(
                'Save',
                focusNode: node,
                onPressed: () => pressed.add('save'),
              ),
              Button('Quit', onPressed: () => pressed.add('quit')),
            ],
          ),
        ),
        size: (10, 2),
      );
      expect(t.lines, [' Save', ' Quit']);
      expect(t, styleAt(1, 0, allOf(hasFg(Color.blue), hasAttr(Attr.bold))));
      expect(t, styleAt(1, 0, isNot(hasAttr(Attr.reverse))));
      await press(t, 'enter space');
      expect(pressed, isEmpty);
      node.requestFocus();
      await t.pump();
      final filled = allOf(
        hasBg(Color.blue),
        hasFg(const Color.rgb(255, 255, 255)),
      );
      expect(t, styleAt(0, 0, filled));
      expect(t, styleAt(5, 0, filled));
      expect(t, styleAt(1, 1, isNot(hasBg(Color.blue))));
      expect(hints(t), ['enter press']);
      await press(t, 'enter space');
      expect(pressed, ['save', 'save']);
      await press(t, 'tab enter');
      expect(pressed, ['save', 'save', 'quit']);
      expect(t, styleAt(1, 0, isNot(hasBg(Color.blue))));
    });

    testTwk('its keys from the moment it has the focus: Enter and Space '
        'typed right after the Tab that focuses it, in one read', (t) async {
      final pressed = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Button(
                'Save',
                autofocus: true,
                onPressed: () => pressed.add('save'),
              ),
              Button('Quit', onPressed: () => pressed.add('quit')),
            ],
          ),
        ),
        size: (10, 2),
      );
      await t.pump();
      await t.type('\t\r \x1b[Z\r');
      await t.pump();
      expect(pressed, ['quit', 'quit', 'save']);
      expect(hints(t), ['enter press']);
    });

    testTwk('a click presses it and gives it the focus; a press released '
        'off it gives the focus alone', (t) async {
      final pressed = <String>[];
      final node = FocusNode(debugLabel: 'ok');
      addTearDown(node.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Button('OK', focusNode: node, onPressed: () => pressed.add('ok')),
            ],
          ),
        ),
        size: (10, 2),
      );
      await click(t, 1, 0);
      expect(pressed, ['ok']);
      expect(focused(t), 'ok');
      node.unfocus();
      await t.pump();
      await t.mouse(MouseKind.down, 2, 0);
      await t.mouse(MouseKind.up, 8, 1);
      await t.pump();
      expect(pressed, ['ok']);
      expect(focused(t), 'ok');
      await click(t, 8, 1);
      expect(pressed, ['ok']);
      node.unfocus();
      await t.pump();
      await t.click(1, 0, button: 2);
      await t.pump();
      expect(pressed, ['ok']);
      expect(focused(t), isNot('ok'));
    });

    testTwk('disabled without onPressed: muted, passed by by Tab, deaf to '
        'clicks; disabled while focused, it lets the focus go', (t) async {
      final pressed = <String>[];
      final enabled = ValueNotifier(false);
      addTearDown(enabled.dispose);
      final nodes = [
        for (final l in ['a', 'b', 'c']) FocusNode(debugLabel: l),
      ];
      addTearDown(() {
        for (final n in nodes) {
          n.dispose();
        }
      });
      await t.pumpWidget(
        Theme.terminal(
          child: hold(
            enabled,
            (on, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Button('A', focusNode: nodes[0], onPressed: () {}),
                Button(
                  'B',
                  focusNode: nodes[1],
                  onPressed: on ? () => pressed.add('b') : null,
                ),
                Button('C', focusNode: nodes[2], onPressed: () {}),
              ],
            ),
          ),
        ),
        size: (10, 3),
      );
      expect(
        t,
        styleAt(
          1,
          1,
          allOf(hasFg(const Color.indexed(245)), isNot(hasAttr(Attr.bold))),
        ),
      );
      final seen = <String?>[];
      for (var i = 0; i < 3; i++) {
        await press(t, 'tab');
        seen.add(focused(t));
      }
      expect(seen, ['a', 'c', 'a']);
      await click(t, 1, 1);
      expect(pressed, isEmpty);
      expect(focused(t), 'a');
      nodes[1].requestFocus();
      await t.pump();
      expect(focused(t), 'a');
      enabled.value = true;
      await t.pump();
      await click(t, 1, 1);
      expect(pressed, ['b']);
      expect(focused(t), 'b');
      enabled.value = false;
      await t.pump();
      expect(focused(t), isNot('b'));
      await press(t, 'enter');
      expect(pressed, ['b']);
    });
  });

  group('Checkbox and Switch', () {
    testTwk('a checkbox shows [x] or [ ] before its label; Space and Enter '
        'flip it while it has the focus, Space hinted, as a click does; '
        "the row on the theme's selection while focused", (t) async {
      final value = ValueNotifier(false);
      addTearDown(value.dispose);
      final node = FocusNode(debugLabel: 'box');
      addTearDown(node.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: hold(
            value,
            (on, set) => Checkbox(
              value: on,
              onChanged: set,
              label: 'Accept',
              focusNode: node,
            ),
          ),
        ),
        size: (12, 1),
      );
      expect(t.lines, ['[ ] Accept']);
      expect(t, styleAt(1, 0, isNot(hasAttr(Attr.bold))));
      await click(t, 6, 0);
      expect(value.value, isTrue);
      expect(t.lines, ['[x] Accept']);
      expect(focused(t), 'box');
      expect(t, styleAt(1, 0, hasBg(const Color.indexed(237))));
      expect(t, styleAt(9, 0, hasBg(const Color.indexed(237))));
      expect(hints(t), ['space toggle']);
      await press(t, 'space');
      expect(t.lines, ['[ ] Accept']);
      await press(t, 'enter');
      expect(value.value, isTrue);
      node.unfocus();
      await t.pump();
      expect(t, styleAt(1, 0, allOf(hasFg(Color.blue), hasAttr(Attr.bold))));
      expect(t, styleAt(5, 0, isNot(hasAttr(Attr.bold))));
      await press(t, 'space');
      expect(value.value, isTrue);
    });

    testTwk('a switch shows a pill, its knob at the right end while on, at '
        'the left while off; disabled ones are muted, passed by and deaf to '
        'clicks', (t) async {
      final value = ValueNotifier(true);
      addTearDown(value.dispose);
      final nodes = [
        for (final l in ['wifi', 'off', 'last']) FocusNode(debugLabel: l),
      ];
      addTearDown(() {
        for (final n in nodes) {
          n.dispose();
        }
      });
      await t.pumpWidget(
        Theme.terminal(
          child: hold(
            value,
            (on, set) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Switch(
                  value: on,
                  onChanged: set,
                  label: 'Wi-Fi',
                  focusNode: nodes[0],
                ),
                Switch(
                  value: on,
                  onChanged: null,
                  label: 'Fixed',
                  focusNode: nodes[1],
                ),
                Checkbox(
                  value: false,
                  onChanged: null,
                  label: 'Never',
                  focusNode: nodes[2],
                ),
              ],
            ),
          ),
        ),
        size: (14, 3),
      );
      expect(t.lines, ['▐  ●▌ Wi-Fi', '▐  ●▌ Fixed', '[ ] Never']);
      expect(t, styleAt(1, 1, hasFg(const Color.indexed(245))));
      expect(t, styleAt(1, 1, isNot(hasAttr(Attr.bold))));
      await press(t, 'tab');
      expect(focused(t), 'wifi');
      await press(t, 'space');
      // the knob runs to the other end
      await t.pump(const Duration(milliseconds: 200));
      expect(t.lines.first, '▐●  ▌ Wi-Fi');
      await press(t, 'tab');
      expect(focused(t), 'wifi');
      await click(t, 2, 1);
      await click(t, 2, 2);
      expect(value.value, isFalse);
      await t.pump(const Duration(milliseconds: 200));
      expect(t.lines, ['▐●  ▌ Wi-Fi', '▐●  ▌ Fixed', '[ ] Never']);
      await click(t, 2, 0);
      expect(value.value, isTrue);
    });
  });

  group('ConfirmInput', () {
    testTwk('the prompt, then Yes and No, the default highlighted; y and n '
        'answer, either case, hinted; Enter the highlighted one, which Left '
        'and Right move; a click answers', (t) async {
      final answers = <bool>[];
      final node = FocusNode(debugLabel: 'confirm');
      addTearDown(node.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: ConfirmInput(
            'Delete?',
            defaultValue: false,
            onConfirmed: answers.add,
            focusNode: node,
            autofocus: true,
          ),
        ),
        size: (20, 1),
      );
      expect(t.lines, ['Delete?  Yes   No']);
      // No highlighted and focused: filled with the primary color, Yes
      // not
      final filled = allOf(
        hasBg(Color.blue),
        hasFg(const Color.rgb(255, 255, 255)),
      );
      expect(t, styleAt(14, 0, filled));
      expect(t, styleAt(9, 0, isNot(hasBg(Color.blue))));
      expect(hints(t), ['y yes', 'n no']);
      await press(t, 'enter');
      expect(answers, [false]);
      await press(t, 'y');
      expect(answers, [false, true]);
      expect(t, styleAt(9, 0, filled));
      await press(t, 'N Y n');
      expect(answers, [false, true, false, true, false]);
      await press(t, 'left enter right enter');
      expect(answers, [false, true, false, true, false, true, false]);
      answers.clear();
      await click(t, 10, 0);
      await click(t, 15, 0);
      await click(t, 3, 0);
      expect(answers, [true, false]);
      node.unfocus();
      await t.pump();
      // the highlighted answer in the primary color, bold, not filled
      expect(t, styleAt(15, 0, allOf(hasFg(Color.blue), hasAttr(Attr.bold))));
      expect(t, styleAt(15, 0, isNot(hasBg(Color.blue))));
      await press(t, 'y');
      expect(answers, [true, false]);
    });

    testTwk('disabled without onConfirmed: muted, passed by by Tab, deaf to '
        'clicks', (t) async {
      final node = FocusNode(debugLabel: 'confirm');
      addTearDown(node.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConfirmInput('Sure?', onConfirmed: null, focusNode: node),
              const Focus(debugLabel: 'next', child: Text('next')),
            ],
          ),
        ),
        size: (20, 2),
      );
      expect(t.lines, ['Sure?  Yes   No', 'next']);
      expect(t, styleAt(8, 0, hasFg(const Color.indexed(245))));
      await press(t, 'tab');
      expect(focused(t), 'next');
      await click(t, 8, 0);
      expect(focused(t), 'next');
    });
  });
}
