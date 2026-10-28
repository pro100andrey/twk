// Button as the design draws it, in the dark theme: a chip at rest, filled
// while focused, a step lighter under the mouse, a flash on a press, a
// fainter chip while disabled, lifted from the surface where it sits on
// it; and a plain look through its styles.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show MouseTracking, MouseTrackingBackend;
import 'package:twk_test/twk_test.dart';

const ThemeData theme = ThemeData.dark;
final Color surface = theme.surface.bg!;
final Color primary = theme.primary.fg!;

/// [child] at the top left, as small as it is, in the dark theme.
Widget dark(Widget child) => Theme(
  data: theme,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [child],
  ),
);

MouseTracking tracking(TwkTester t) =>
    (t.binding.twkApp.terminal as MouseTrackingBackend).mouseTracking;

void main() {
  testTwk('at rest the primary color in bold on a surface chip, a blank of '
      'it on either side; focused, the chip filled with the primary color '
      'and the text the background color', (t) async {
    final node = FocusNode(debugLabel: 'save');
    addTearDown(node.dispose);
    await t.pumpWidget(
      dark(
        Button('Save', focusNode: node, onPressed: () {}),
      ),
      size: (8, 1),
    );
    for (final x in [0, 5]) {
      expect(t, styleAt(x, 0, hasBg(surface)));
    }
    expect(
      t,
      styleAt(1, 0, allOf(hasFg(primary), hasBg(surface), hasAttr(Attr.bold))),
    );
    expect(t, styleAt(6, 0, isNot(hasBg(surface))));
    node.requestFocus();
    await t.pump();
    for (final x in [0, 1, 5]) {
      expect(
        t,
        styleAt(
          x,
          0,
          allOf(hasBg(primary), hasFg(theme.onPrimary.fg!), hasAttr(Attr.bold)),
        ),
      );
    }
  });

  testTwk('on a raised panel, or any box of the surface, the chip is a '
      'step from the surface towards the text, 0.08 of the way on a dark '
      'theme and 0.06 on a light one; the mouse over it a step from that; '
      'a style given is as given', (t) async {
    Color mix(Color a, Color b, double k) {
      int channel(int x, int y) => (x + (y - x) * k).round();
      return Color.rgb(channel(a.r, b.r), channel(a.g, b.g), channel(a.b, b.b));
    }

    for (final (theme, k) in [
      (ThemeData.dark, 0.08),
      (ThemeData.light, 0.06),
    ]) {
      await t.pumpWidget(
        Theme(
          data: theme,
          child: Align(
            alignment: Alignment.topLeft,
            child: Panel(
              shadow: false,
              // a box with no background is passed by
              child: Box(
                child: Row(
                  gap: 1,
                  children: [
                    Button('Keep', onPressed: () {}),
                    Button(
                      'Go',
                      onPressed: () {},
                      style: theme.surface.merge(theme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        size: (16, 3),
      );
      final surface = theme.surface.bg!;
      final chip = mix(surface, theme.text.fg!, k);
      expect(t, styleAt(1, 1, hasBg(chip)), reason: '${theme.brightness}');
      expect(t, styleAt(6, 1, hasBg(chip)));
      expect(t, styleAt(7, 1, hasBg(surface)), reason: 'the gap');
      expect(t, styleAt(8, 1, hasBg(surface)), reason: 'its style given');
      await t.mouse(MouseKind.move, 2, 1);
      await t.pump();
      expect(t, styleAt(1, 1, hasBg(mix(chip, theme.primary.fg!, 0.18))));
      await t.mouse(MouseKind.move, 15, 2);
      await t.pump();
    }
    // on the background it is on the surface
    await t.pumpWidget(
      dark(
        Box(
          style: theme.background,
          child: Button('Keep', onPressed: () {}),
        ),
      ),
    );
    expect(t, styleAt(0, 0, hasBg(surface)));
  });

  testTwk('disabled: muted, not bold, on a chip half of the way from the '
      'surface to the background', (t) async {
    await t.pumpWidget(
      dark(const Button('Off', onPressed: null)),
      size: (8, 1),
    );
    expect(
      t,
      styleAt(
        1,
        0,
        allOf(
          hasFg(theme.muted.fg!),
          hasBg(const Color.rgb(0x1c, 0x1f, 0x25)),
          isNot(hasAttr(Attr.bold)),
        ),
      ),
    );
  });

  testTwk('disabled with a style of its own: muted over it, on its chip', (
    t,
  ) async {
    await t.pumpWidget(
      dark(const Button('Off', onPressed: null, style: Style(bg: Color.blue))),
      size: (8, 1),
    );
    expect(
      t,
      styleAt(1, 0, allOf(hasFg(theme.muted.fg!), hasBg(Color.blue))),
    );
  });

  testTwk('the mouse over it takes its chip 0.18 of the way to the primary '
      'color, and back as it leaves; not while it has the focus', (t) async {
    final node = FocusNode(debugLabel: 'save');
    addTearDown(node.dispose);
    await t.pumpWidget(
      dark(
        Button('Save', focusNode: node, onPressed: () {}),
      ),
      size: (10, 2),
    );
    expect(tracking(t), MouseTracking.motion);
    await t.mouse(MouseKind.move, 2, 0);
    await t.pump();
    const lit = Color.rgb(45, 61, 82);
    expect(t, styleAt(0, 0, hasBg(lit)));
    expect(t, styleAt(2, 0, allOf(hasBg(lit), hasFg(primary))));
    await t.mouse(MouseKind.move, 8, 1);
    await t.pump();
    expect(t, styleAt(2, 0, hasBg(surface)));
    node.requestFocus();
    await t.mouse(MouseKind.move, 2, 0);
    await t.pump();
    expect(t, styleAt(2, 0, hasBg(primary)));
  });

  testTwk('a press by key flashes the chip a step towards white, fading in '
      '260 ms; held by the mouse it stays lit while the mouse is over it', (
    t,
  ) async {
    var pressed = 0;
    await t.pumpWidget(
      dark(
        Button('Go', autofocus: true, onPressed: () => pressed++),
      ),
      size: (10, 2),
    );
    await t.pump();
    expect(t, styleAt(1, 0, hasBg(primary)));
    await t.press('enter');
    await t.pump();
    expect(pressed, 1);
    // 0.28 of the way to white at the start, the frame after it less
    expect(t, styleAt(1, 0, isNot(hasBg(primary))));
    await t.pump(const Duration(milliseconds: 300));
    expect(t, styleAt(1, 0, hasBg(primary)));
    await t.mouse(MouseKind.down, 1, 0);
    await t.pump(const Duration(milliseconds: 300));
    const held = Color.rgb(140, 192, 255);
    expect(t, styleAt(1, 0, hasBg(held)));
    await t.mouse(MouseKind.drag, 8, 1);
    await t.pump();
    expect(t, styleAt(1, 0, hasBg(primary)));
    await t.mouse(MouseKind.drag, 2, 0);
    await t.pump();
    expect(t, styleAt(1, 0, hasBg(held)));
    await t.mouse(MouseKind.up, 2, 0);
    await t.pump(const Duration(milliseconds: 300));
    expect(pressed, 2);
    expect(t, styleAt(1, 0, hasBg(primary)));
  });

  testTwk('the plain look through its styles: no chip, no hover, the mouse '
      'motion unread, reversed while focused', (t) async {
    final node = FocusNode(debugLabel: 'save');
    addTearDown(node.dispose);
    await t.pumpWidget(
      dark(
        Button(
          'Save',
          focusNode: node,
          style: theme.primary.merge(const Style(attrs: Attr.bold)),
          focusedStyle: const Style(attrs: Attr.reverse),
          onPressed: () {},
        ),
      ),
      size: (10, 2),
    );
    expect(tracking(t), isNot(MouseTracking.motion));
    await t.mouse(MouseKind.move, 2, 0);
    await t.pump();
    expect(
      t,
      styleAt(
        2,
        0,
        allOf(hasFg(primary), hasAttr(Attr.bold), isNot(hasBg(surface))),
      ),
    );
    node.requestFocus();
    await t.pump();
    expect(
      t,
      styleAt(2, 0, allOf(hasFg(primary), hasAttr(Attr.bold | Attr.reverse))),
    );
  });

  group('outlined and filled, one row', () {
    testTwk('the label between two edges, or on a fill, two blanks either '
        'side; as wide as an Expanded makes them, the label in the middle', (
      t,
    ) async {
      await t.pumpWidget(
        dark(
          Row(
            mainAxisSize: MainAxisSize.min,
            gap: 1,
            children: [
              Button.outlined('No', onPressed: () {}),
              Button.filled('Yes', onPressed: () {}),
            ],
          ),
        ),
        size: (20, 1),
      );
      expect(t.lines, ['▕ No ▏   Yes']);
      expect(t, styleAt(0, 0, hasFg(theme.border.fg!)));
      expect(t, styleAt(7, 0, hasBg(primary)));
      expect(t, styleAt(13, 0, hasBg(primary)));
      expect(t, styleAt(14, 0, isNot(hasBg(primary))));
      await t.pumpWidget(
        dark(
          SizedBox(
            width: 12,
            child: Button.outlined('No', onPressed: () {}),
          ),
        ),
        size: (20, 1),
      );
      expect(t.lines, ['▕    No    ▏']);
    });

    testTwk('focused, the edges and the label primary', (t) async {
      await t.pumpWidget(
        dark(Button.outlined('No', onPressed: () {})),
        size: (20, 1),
      );
      await t.press('tab');
      await t.pump();
      expect(t, styleAt(0, 0, hasFg(primary)));
      expect(t, styleAt(2, 0, allOf(hasFg(primary), hasAttr(Attr.bold))));
    });
  });

  group('outlined and filled, tall', () {
    Widget pair({VoidCallback? onCancel, VoidCallback? onApprove}) => dark(
      SizedBox(
        width: 30,
        child: Row(
          children: [
            Expanded(
              child: Button.outlined('CANCEL', tall: true, onPressed: onCancel),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Button.filled('APPROVE', tall: true, onPressed: onApprove),
            ),
          ],
        ),
      ),
    );

    testTwk('three rows, the label in the middle: a box drawn around one, '
        'a fill of the primary color for the other; as wide as an Expanded '
        'makes them', (t) async {
      await t.pumpWidget(
        pair(onCancel: () {}, onApprove: () {}),
        size: (30, 3),
      );
      expect(t.lines, [
        '┌────────────┐',
        '│   CANCEL   │     APPROVE',
        '└────────────┘',
      ]);
      expect(t, styleAt(0, 0, hasFg(theme.border.fg!)));
      expect(t, styleAt(5, 1, hasFg(theme.text.fg!)));
      for (final y in [0, 1, 2]) {
        expect(t, styleAt(16, y, hasBg(primary)), reason: 'row $y');
      }
      expect(t, styleAt(21, 1, hasFg(theme.onPrimary.fg!)));
    });

    testTwk('focused, the outline and the label primary, the fill the '
        "text's color, bold; Enter and a click press them", (t) async {
      var cancelled = 0;
      var approved = 0;
      await t.pumpWidget(
        pair(onCancel: () => cancelled++, onApprove: () => approved++),
        size: (30, 3),
      );
      await t.press('tab');
      await t.pump();
      expect(t, styleAt(0, 0, hasFg(primary)));
      expect(t, styleAt(5, 1, allOf(hasFg(primary), hasAttr(Attr.bold))));
      await t.press('enter');
      await t.pump();
      expect(cancelled, 1);
      await t.press('tab');
      await t.pump();
      expect(t, styleAt(0, 0, hasFg(theme.border.fg!)));
      expect(
        t,
        styleAt(16, 1, allOf(hasBg(theme.text.fg!), hasAttr(Attr.bold))),
      );
      await t.click(20, 0);
      await t.pump();
      expect(approved, 1);
    });

    testTwk('as wide as the label and three blanks either side outside an '
        'Expanded; disabled, muted and taking no focus', (t) async {
      await t.pumpWidget(
        dark(const Button.filled('OK', tall: true, onPressed: null)),
        size: (12, 3),
      );
      expect(t.lines, ['', '   OK', '']);
      // the fill eight wide
      expect(t, styleAt(7, 0, isNot(hasBg(Color.defaultColor))));
      expect(t, styleAt(8, 0, hasBg(Color.defaultColor)));
      expect(t, styleAt(3, 1, hasFg(theme.muted.fg!)));
      await t.press('tab');
      await t.pump();
      expect(t.binding.focusManager.primaryFocus, isNull);
    });
  });
}
