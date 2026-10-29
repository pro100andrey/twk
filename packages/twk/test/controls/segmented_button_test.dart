// SegmentedButton: joined segments between caps, those on in the primary
// color; one stop of Tab whose arrows move a highlight, Space, Enter and
// the digits pressing; clicks; a single and a multiple choice, empty or
// not; disabled segments and a disabled control; labels cut off evenly;
// the hover; plain output; read as radios or checkboxes; where │ and …
// are two columns wide.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../text/ambiguous.dart';
import '../text/plain_lines.dart';

const List<Choice<String>> views = [
  Choice('all', 'All'),
  Choice('errors', 'Errors (3)'),
  Choice('warnings', 'Warnings (12)'),
  Choice('info', 'Info', enabled: false),
];

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

/// A control of [segments] that keeps what is on in [on] and reports each
/// change to [changes], then a button to move the focus to.
Widget segmented(
  ValueNotifier<Set<String>> on, {
  List<Set<String>>? changes,
  List<Choice<String>> segments = views,
  bool multi = false,
  bool empty = false,
  bool icon = false,
  bool enabled = true,
  FocusNode? focusNode,
}) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    ValueListenableBuilder(
      valueListenable: on,
      builder: (context, value, _) => SegmentedButton<String>(
        segments: segments,
        selected: value,
        multiSelectionEnabled: multi,
        emptySelectionAllowed: empty,
        showSelectedIcon: icon,
        focusNode: focusNode,
        onSelectionChanged: enabled
            ? (value) {
                changes?.add(value);
                on.value = value;
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
  testTwk('the segments joined between brackets, those on in the primary '
      'color and bold, the lines in the border color, one that cannot be '
      'pressed muted', (t) async {
    final on = ValueNotifier({'errors'});
    await t.pumpWidget(Theme.terminal(child: segmented(on)), size: (50, 2));
    expect(t.lines.first, '[ All │ Errors (3) │ Warnings (12) │ Info ]');
    expect(t, styleAt(10, 0, allOf(hasFg(Color.blue), hasAttr(Attr.bold))));
    expect(t, styleAt(2, 0, isNot(hasAttr(Attr.bold))));
    for (final x in [0, 6, 19, 35, 42]) {
      expect(
        t,
        styleAt(x, 0, hasFg(const Color.indexed(240))),
        reason: 'at $x',
      );
    }
    expect(t, styleAt(38, 0, hasFg(const Color.indexed(245))));
    expect(t, styleAt(2, 0, isNot(hasFg(const Color.indexed(245)))));
  });

  testTwk('with showSelectedIcon a segment on shows ✓ before its label; '
      'other caps', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: SegmentedButton<int>(
          segments: const [Choice(1, 'One'), Choice(2, 'Two')],
          selected: const {2},
          showSelectedIcon: true,
          caps: ('(', ')'),
          onSelectionChanged: (_) {},
        ),
      ),
      size: (30, 1),
    );
    expect(t.lines, ['( One │ ✓ Two )']);
  });

  testTwk('one stop of Tab; Left and Right move the highlight from the one '
      'on, passing a disabled one by, round; Space and Enter press it; '
      'hinted', (t) async {
    final on = ValueNotifier({'errors'});
    final changes = <Set<String>>[];
    final node = FocusNode(debugLabel: 'views');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: segmented(on, changes: changes, focusNode: node),
      ),
      size: (50, 2),
    );
    await press(t, 'tab');
    expect(focused(t), 'views');
    expect(hints(t), [
      'left previous',
      'right next',
      'space select',
      '1 …4 select',
    ]);
    // highlighted: the one on
    expect(t, styleAt(10, 0, hasBg(const Color.indexed(237))));
    await press(t, 'right');
    expect(t, styleAt(22, 0, hasBg(const Color.indexed(237))));
    expect(t, styleAt(10, 0, isNot(hasBg(const Color.indexed(237)))));
    expect(changes, isEmpty);
    // past the disabled one, round to the first
    await press(t, 'right');
    expect(t, styleAt(2, 0, hasBg(const Color.indexed(237))));
    await press(t, 'left');
    expect(t, styleAt(22, 0, hasBg(const Color.indexed(237))));
    await press(t, 'space');
    expect(changes, [
      {'warnings'},
    ]);
    expect(t, styleAt(22, 0, allOf(hasFg(Color.blue), hasAttr(Attr.bold))));
    await press(t, 'left enter');
    expect(on.value, {'errors'});
    // a press of the one on changes nothing
    await press(t, 'space');
    expect(changes, hasLength(2));
    await press(t, 'tab');
    expect(focused(t), 'next');
    expect(t, styleAt(10, 0, isNot(hasBg(const Color.indexed(237)))));
  });

  testTwk('the hidden cursor rests on the highlighted segment as it '
      'moves', (t) async {
    final on = ValueNotifier({'errors'});
    final node = FocusNode(debugLabel: 'views');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: segmented(on, focusNode: node)),
      size: (50, 2),
    );
    node.requestFocus();
    await t.pump();
    expect(t.cursorVisible, isFalse);
    expect(t.cursor, (7, 0));
    await press(t, 'right');
    expect(t.cursor, (20, 0));
    // past the disabled one, round to the first
    await press(t, 'right');
    expect(t.cursor, (1, 0));
    await press(t, 'tab');
    expect(focused(t), 'next');
    expect(t.cursor, (0, 1));
  });

  testTwk('1 to 9 press the segment of that number, highlighting it; a '
      'disabled one not', (t) async {
    final on = ValueNotifier({'all'});
    final node = FocusNode(debugLabel: 'views');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: segmented(on, focusNode: node)),
      size: (50, 2),
    );
    node.requestFocus();
    await t.pump();
    await press(t, '3');
    expect(on.value, {'warnings'});
    expect(t, styleAt(22, 0, hasBg(const Color.indexed(237))));
    await press(t, '4');
    expect(on.value, {'warnings'});
    await press(t, '2');
    expect(on.value, {'errors'});
  });

  testTwk('a click presses a segment and focuses the control; one disabled, '
      'the caps and the lines do nothing', (t) async {
    final on = ValueNotifier({'all'});
    final changes = <Set<String>>[];
    final node = FocusNode(debugLabel: 'views');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: segmented(on, changes: changes, focusNode: node),
      ),
      size: (50, 2),
    );
    await click(t, 14, 0);
    expect(on.value, {'errors'});
    expect(focused(t), 'views');
    for (final x in [0, 6, 19, 39, 42]) {
      await click(t, x, 0);
    }
    expect(changes, [
      {'errors'},
    ]);
    await click(t, 30, 0);
    expect(on.value, {'warnings'});
  });

  testTwk('a multiple choice toggles each segment, never the last one off '
      'unless an empty one is allowed', (t) async {
    final on = ValueNotifier({'all'});
    final node = FocusNode(debugLabel: 'views');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: segmented(on, multi: true, focusNode: node)),
      size: (50, 2),
    );
    node.requestFocus();
    await t.pump();
    expect(hints(t), contains('space toggle'));
    await press(t, '2 3');
    expect(on.value, {'all', 'errors', 'warnings'});
    await press(t, '1 2');
    expect(on.value, {'warnings'});
    await press(t, '3');
    expect(on.value, {'warnings'});

    await t.pumpWidget(
      Theme.terminal(
        child: segmented(on, multi: true, empty: true, focusNode: node),
      ),
    );
    await press(t, '3');
    expect(on.value, isEmpty);
  });

  testTwk('a single choice with an empty one allowed turns the one on off', (
    t,
  ) async {
    final on = ValueNotifier({'all'});
    final node = FocusNode(debugLabel: 'views');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: segmented(on, empty: true, focusNode: node)),
      size: (50, 2),
    );
    await click(t, 2, 0);
    expect(on.value, isEmpty);
    await press(t, 'space');
    expect(on.value, {'all'});
  });

  testTwk('without onSelectionChanged it takes neither the focus nor the '
      'mouse, all of it muted', (t) async {
    final on = ValueNotifier({'errors'});
    final node = FocusNode(debugLabel: 'views');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: segmented(on, enabled: false, focusNode: node)),
      size: (50, 2),
    );
    expect(
      t,
      styleAt(
        10,
        0,
        allOf(hasFg(const Color.indexed(245)), isNot(hasFg(Color.blue))),
      ),
    );
    await click(t, 2, 0);
    expect(on.value, {'errors'});
    await press(t, 'tab');
    expect(focused(t), 'next');
  });

  testTwk('where the segments do not fit, the labels are cut off with … '
      'evenly, the widest first, never wrapped', (t) async {
    final on = ValueNotifier({'all'});
    await t.pumpWidget(
      Theme.terminal(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 30,
            child: SegmentedButton<String>(
              segments: views,
              selected: on.value,
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      ),
      size: (40, 2),
    );
    expect(t.lines, ['[ All │ Erro… │ Warn… │ Info ]', '']);
    await t.pumpWidget(
      Theme.terminal(
        child: SegmentedButton<String>(
          segments: views,
          selected: on.value,
          onSelectionChanged: (_) {},
        ),
      ),
    );
    // what the others leave: the narrow ones whole, the widest cut
    expect(t.lines, ['[ All │ Errors (3) │ Warnings … │ Info ]', '']);
    await t.pumpWidget(
      Theme.terminal(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 22,
            child: SegmentedButton<String>(
              segments: views,
              selected: on.value,
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(t.lines, ['[ All │ E… │ W… │ I… ]', '']);
  });

  testTwk('the mouse over an enabled segment lights it a step from the '
      'surface towards its text', (t) async {
    const theme = ThemeData.dark;
    final on = ValueNotifier({'all'});
    await t.pumpWidget(
      Theme.terminal(
        child: Theme(data: theme, child: segmented(on)),
      ),
      size: (50, 2),
    );
    await t.mouse(MouseKind.move, 12, 0);
    await t.pump();
    int channel(int x, int y) => (x + (y - x) * 0.18).round();
    final s = theme.surface.bg!;
    final f = theme.text.fg!;
    final hover = hasBg(
      Color.rgb(channel(s.r, f.r), channel(s.g, f.g), channel(s.b, f.b)),
    );
    expect(t, styleAt(9, 0, hover));
    expect(t, styleAt(18, 0, hover));
    expect(t, styleAt(2, 0, isNot(hover)));
    await t.mouse(MouseKind.move, 38, 0);
    await t.pump();
    expect(t, styleAt(12, 0, isNot(hover)));
    expect(t, styleAt(38, 0, isNot(hover)));
  });

  testTwk('a screen reader reads radios, or checkboxes in a multiple '
      'choice, checked while on; the highlighted one focused', (t) async {
    final on = ValueNotifier({'errors'});
    final node = FocusNode(debugLabel: 'views');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: segmented(on, focusNode: node)),
      size: (50, 2),
    );
    node.requestFocus();
    await t.pump();
    expect(t.binding.semantics.lines.take(4), [
      'radio All, not checked',
      'radio Errors (3), checked',
      'radio Warnings (12), not checked',
      'radio Info, not checked, disabled',
    ]);
    expect(t.binding.semantics.focusedLine, 1);
    await press(t, 'right');
    expect(t.binding.semantics.focusedLine, 2);
    await t.pumpWidget(
      Theme.terminal(child: segmented(on, multi: true, focusNode: node)),
    );
    expect(t.binding.semantics.lines.take(2), [
      'checkbox All, not checked',
      'checkbox Errors (3), checked',
    ]);
  });

  test('on plain output a segment on shows ✓ before its label', () async {
    final lines = await plainLines(
      SegmentedButton<String>(
        segments: views,
        selected: const {'errors'},
        onSelectionChanged: (_) {},
      ),
      width: 60,
    );
    expect(lines, ['[ All │ ✓ Errors (3) │ Warnings (12) │ Info ]']);
  });

  group('where │ and … are two columns wide (ambiguous width 2)', () {
    test('a click hits the segment drawn where it is, not one a column '
        'off for each │ before it', () async {
      final on = ValueNotifier({'all'});
      final changes = <Set<String>>[];
      final app = await WideApp.start(segmented(on, changes: changes));
      expect(app.lines().first, '[ All │ Errors (3) │ Warnings (12) │ Info ]');
      // the second column of the │ after Errors (3)
      await app.click(21, 0);
      expect(changes, isEmpty);
      // the blank after Warnings (12), the blank after Errors (3)
      await app.click(36, 0);
      await app.click(19, 0);
      expect(changes, [
        {'warnings'},
        {'errors'},
      ]);
      await app.quit();
    });

    test('labels cut off fit the row, the lines and the ellipsis two '
        'columns each', () async {
      final on = ValueNotifier({'all'});
      final app = await WideApp.start(
        Row(
          children: [
            SizedBox(width: 30, child: segmented(on)),
          ],
        ),
      );
      final row = app.lines().first;
      expect(row, startsWith('[ All │ '));
      expect(row, contains('…'));
      expect(row, endsWith(' ]'));
      await app.quit();
    });
  });
}
