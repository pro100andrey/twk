// ConfirmInput as the design draws it, in the dark theme: the answers as
// button chips, the one highlighted primary, the other muted, a flash as
// one is given; and a plain look through its styles.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ThemeData theme = ThemeData.dark;
final Color surface = theme.surface.bg!;
final Color primary = theme.primary.fg!;
final Color muted = theme.muted.fg!;

/// [child] at the top left, as small as it is, in the dark theme.
Widget dark(Widget child) => Theme(
  data: theme,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [child],
  ),
);

void main() {
  testTwk('the answers on surface chips: the one highlighted primary and '
      'bold, the other muted; focused, the highlighted one filled with the '
      'primary color', (t) async {
    final node = FocusNode(debugLabel: 'confirm');
    addTearDown(node.dispose);
    await t.pumpWidget(
      dark(ConfirmInput('Sure?', onConfirmed: (_) {}, focusNode: node)),
      size: (20, 1),
    );
    expect(t.lines, ['Sure?  Yes   No']);
    for (final x in [6, 10]) {
      expect(t, styleAt(x, 0, hasBg(surface)));
    }
    // " Yes " at 6, " No " at 12
    for (final x in [7, 9]) {
      expect(
        t,
        styleAt(
          x,
          0,
          allOf(hasBg(surface), hasFg(primary), hasAttr(Attr.bold)),
        ),
      );
    }
    for (final x in [12, 15]) {
      expect(t, styleAt(x, 0, hasBg(surface)));
    }
    // a blank's color and bold are those the terminal is left with
    for (final x in [13, 14]) {
      expect(
        t,
        styleAt(
          x,
          0,
          allOf(hasBg(surface), hasFg(muted), isNot(hasAttr(Attr.bold))),
        ),
      );
    }
    expect(t, styleAt(11, 0, isNot(hasBg(surface))));
    node.requestFocus();
    await t.pump();
    expect(
      t,
      styleAt(
        7,
        0,
        allOf(hasBg(primary), hasFg(theme.onPrimary.fg!), hasAttr(Attr.bold)),
      ),
    );
    expect(t, styleAt(13, 0, allOf(hasBg(surface), hasFg(muted))));
  });

  testTwk('an answer given flashes its chip, fading in 260 ms', (t) async {
    await t.pumpWidget(
      dark(ConfirmInput('Sure?', onConfirmed: (_) {}, autofocus: true)),
      size: (20, 1),
    );
    await t.pump();
    await t.press('n');
    await t.pump();
    expect(t, styleAt(13, 0, isNot(hasBg(primary))));
    expect(t, styleAt(13, 0, hasFg(theme.onPrimary.fg!)));
    await t.pump(const Duration(milliseconds: 300));
    expect(t, styleAt(13, 0, hasBg(primary)));
  });

  testTwk('the hidden cursor rests on the highlighted answer as Left and '
      'Right move it', (t) async {
    final node = FocusNode(debugLabel: 'confirm');
    addTearDown(node.dispose);
    await t.pumpWidget(
      dark(ConfirmInput('Sure?', onConfirmed: (_) {}, focusNode: node)),
      size: (20, 1),
    );
    node.requestFocus();
    await t.pump();
    expect(t.cursorVisible, isFalse);
    // " Yes " at 6, " No " at 12
    expect(t.cursor, (6, 0));
    await t.press('right');
    await t.pump();
    expect(t.cursor, (12, 0));
    await t.press('left');
    await t.pump();
    expect(t.cursor, (6, 0));
  });

  testTwk('disabled: muted on fainter chips', (t) async {
    await t.pumpWidget(
      dark(const ConfirmInput('Sure?', onConfirmed: null)),
      size: (20, 1),
    );
    for (final x in [7, 13]) {
      expect(
        t,
        styleAt(
          x,
          0,
          allOf(
            hasFg(muted),
            hasBg(const Color.rgb(0x1c, 0x1f, 0x25)),
            isNot(hasAttr(Attr.bold)),
          ),
        ),
      );
    }
  });

  testTwk('disabled with an answer style: both answers in it over the '
      'muted row, no fainter chip', (t) async {
    await t.pumpWidget(
      dark(
        const ConfirmInput(
          'Sure?',
          onConfirmed: null,
          answerStyle: Style(attrs: Attr.underline),
        ),
      ),
      size: (20, 1),
    );
    for (final x in [7, 13]) {
      expect(
        t,
        styleAt(
          x,
          0,
          allOf(
            hasFg(muted),
            hasAttr(Attr.underline),
            isNot(hasBg(const Color.rgb(0x1c, 0x1f, 0x25))),
          ),
        ),
      );
    }
  });

  testTwk('an answer held down by the mouse stays lit while the mouse is '
      'over it, and goes out as it is dragged off', (t) async {
    final given = <bool>[];
    await t.pumpWidget(
      dark(ConfirmInput('Sure?', onConfirmed: given.add)),
      size: (20, 2),
    );
    await t.mouse(MouseKind.down, 13, 0);
    await t.pump(const Duration(milliseconds: 300));
    expect(t, styleAt(13, 0, isNot(hasBg(surface))));
    await t.mouse(MouseKind.drag, 13, 1);
    await t.pump();
    expect(t, styleAt(13, 0, hasBg(surface)));
    await t.mouse(MouseKind.drag, 13, 0);
    await t.pump();
    expect(t, styleAt(13, 0, isNot(hasBg(surface))));
    await t.mouse(MouseKind.up, 13, 0);
    expect(given, [false]);
  });

  testTwk('a plain look: no chips, the highlighted answer '
      'primary and bold, reversed while focused', (t) async {
    await t.pumpWidget(
      dark(
        ConfirmInput(
          'Sure?',
          onConfirmed: (_) {},
          autofocus: true,
          answerStyle: const Style(),
          highlightedStyle: theme.primary.merge(const Style(attrs: Attr.bold)),
          focusedStyle: const Style(attrs: Attr.reverse),
        ),
      ),
      size: (20, 1),
    );
    await t.pump();
    expect(
      t,
      styleAt(7, 0, allOf(hasFg(primary), hasAttr(Attr.bold | Attr.reverse))),
    );
    expect(t, styleAt(7, 0, isNot(hasBg(surface))));
    expect(
      t,
      styleAt(
        13,
        0,
        allOf(hasFg(theme.text.fg!), isNot(hasBg(surface))),
      ),
    );
  });
}
