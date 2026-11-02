// Button.rich: a key in one style and its caption in another on one chip.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ThemeData theme = ThemeData.dark;
final Color surface = theme.surface.bg!;
final Color primary = theme.primary.fg!;

Widget dark(Widget child) => Theme(
  data: theme,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [child],
  ),
);

void main() {
  testTwk('the key and the caption each in their style on one chip, a blank '
      'either side; the width is the cells of the spans', (t) async {
    await t.pumpWidget(
      dark(
        Button.rich([
          'Ent'.bold.fg(Color.yellow),
          const Span(' ø'),
        ], onPressed: () {}),
      ),
      size: (10, 1),
    );
    // " Ent ø " is 7 cells: the chip ends at 6, nothing is on at 7
    expect(t, styleAt(0, 0, hasBg(surface)));
    expect(t, styleAt(1, 0, allOf(hasFg(Color.yellow), hasBg(surface))));
    expect(t, styleAt(3, 0, hasFg(Color.yellow)));
    expect(t, styleAt(5, 0, allOf(hasFg(primary), hasBg(surface))));
    expect(t, styleAt(6, 0, hasBg(surface)));
    expect(t, styleAt(7, 0, isNot(hasBg(surface))));
  });

  testTwk('without own styles it is the Button of the same text', (t) async {
    await t.pumpWidget(
      dark(Button.rich(const [Span('Sa'), Span('ve')], onPressed: () {})),
      size: (8, 1),
    );
    final rich = t.lines;
    await t.pumpWidget(dark(Button('Save', onPressed: () {})), size: (8, 1));
    expect(rich, t.lines);
    expect(t, styleAt(1, 0, allOf(hasFg(primary), hasAttr(Attr.bold))));
  });

  testTwk('focused, the chip is filled and the colors of the spans give way to '
      'the state, their attributes stay', (t) async {
    final node = FocusNode(debugLabel: 'k');
    addTearDown(node.dispose);
    await t.pumpWidget(
      dark(
        Button.rich(
          ['K'.underline.fg(primary), const Span(' go')],
          focusNode: node,
          onPressed: () {},
        ),
      ),
      size: (8, 1),
    );
    node.requestFocus();
    await t.pump();
    expect(
      t,
      styleAt(
        1,
        0,
        allOf(
          hasBg(primary),
          hasFg(theme.onPrimary.fg!),
          hasAttr(Attr.underline),
        ),
      ),
    );
  });

  testTwk('disabled: muted, the color of the span dropped', (t) async {
    await t.pumpWidget(
      dark(Button.rich(['K'.fg(Color.yellow)], onPressed: null)),
      size: (8, 1),
    );
    expect(t, styleAt(1, 0, hasFg(theme.muted.fg!)));
  });

  testTwk('the mouse over it takes the chip a step; the key keeps its '
      'color', (t) async {
    await t.pumpWidget(
      dark(Button.rich(['K'.fg(Color.yellow)], onPressed: () {})),
      size: (8, 1),
    );
    await t.mouse(MouseKind.move, 1, 0);
    await t.pump();
    expect(t, styleAt(1, 0, allOf(hasFg(Color.yellow), isNot(hasBg(surface)))));
  });

  testTwk('a click presses it; a screen reader reads the text of the spans', (
    t,
  ) async {
    var pressed = 0;
    await t.pumpWidget(
      dark(
        Button.rich(['K'.bold, const Span(' go')], onPressed: () => pressed++),
      ),
      size: (8, 1),
    );
    await t.clickOn(find.byType(Button));
    expect(pressed, 1);
    expect(
      const Button.rich([Span('K'), Span(' go')], onPressed: null).label,
      'K go',
    );
  });
}
