// In visual order a label a render object paints itself reads as a Text
// draws it: an OptionList's rows with their marks and details, a Box's
// titles, a TabBar's tabs, a menu bar's titles and the entries of its
// menus, each through a TextPainter it keeps. Right-to-left labels reverse
// (Text('שלום עולם') draws 'םלוע םולש'); left-to-right ones draw as they
// did.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show PipelineTextOrder, TextOrder;
import 'package:twk_test/twk_test.dart';

const hebrew = 'שלום עולם';
const reversed = 'םלוע םולש';

/// Draws the app's text in [order] from the next frame on.
Future<void> draw(TwkTester t, TextOrder order) async {
  t.binding.twkApp.owner.textOrder = order;
  await t.pump();
}

Future<void> visual(TwkTester t) => draw(t, TextOrder.visual);

Future<void> logical(TwkTester t) => draw(t, TextOrder.logical);

void main() {
  testTwk('an OptionList row, its marks and its detail read as a Text does', (
    t,
  ) async {
    await t.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: OptionList(
          options: [
            Option(hebrew, marks: [0, 5], detail: 'אבג'),
            Option('apple', marks: [1]),
          ],
          highlighted: 0,
        ),
      ),
      size: (20, 3),
    );
    await logical(t);
    expect(t.lines[0], '▎$hebrew  אבג');
    expect(t.lines[1], ' apple');
    await visual(t);
    expect(t.lines[0], '▎$reversed  גבא');
    expect(t.lines[1], ' apple');
    // the marks are in the label's own run, in the mark style: the first
    // and sixth characters, drawn at the far ends of their words
    final bold = [
      for (var x = 1; x < 20; x++)
        if (t.cell(x, 0).attrs & Attr.bold != 0 &&
            t.cell(x, 0).text.trim().isNotEmpty)
          t.cell(x, 0).text,
    ];
    expect(bold, ['ע', 'ש']);
    await t.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: OptionList(
          options: [
            Option('apple', marks: [1]),
          ],
        ),
      ),
      size: (20, 3),
    );
    expect(t.lines[0], ' apple');
  });

  testTwk('a Box title reads as a Text does, cut with its ellipsis', (t) async {
    await t.pumpWidget(
      const SizedBox(
        width: 14,
        height: 3,
        child: Box(
          border: Border.all(),
          titles: [BorderTitle(hebrew)],
        ),
      ),
      size: (14, 3),
    );
    await logical(t);
    expect(t.lines[0], '┌$hebrew───┐');
    await visual(t);
    expect(t.lines[0], '┌$reversed───┐');
    await t.pumpWidget(
      const SizedBox(
        width: 8,
        height: 3,
        child: Box(
          border: Border.all(),
          titles: [BorderTitle(hebrew)],
        ),
      ),
      size: (8, 3),
    );
    // cut in stored order, the ellipsis after the cut, then drawn as read
    await logical(t);
    expect(t.lines[0], '┌שלום…─┐');
    await visual(t);
    expect(t.lines[0], '┌…םולש─┐');
  });

  testTwk('a TabBar label reads as a Text does and a click finds its tab', (
    t,
  ) async {
    final c = TabController(length: 2);
    await t.pumpWidget(
      TabBar(controller: c, tabs: const [hebrew, 'two']),
      size: (30, 1),
    );
    await logical(t);
    expect(t.lines[0], ' $hebrew  two');
    await visual(t);
    expect(t.lines[0], ' $reversed  two');
    await t.click(14, 0);
    await t.pump();
    expect(c.index, 1);
    await t.click(3, 0);
    await t.pump();
    expect(c.index, 0);
  });

  Widget menuBar(String title) => Overlay(
    child: MenuBar(
      look: PanelLook.bordered,
      menus: [
        Menu(
          title,
          items: [
            MenuItem('$hebrew&x', onSelected: () {}),
            MenuItem('&Open', onSelected: () {}),
          ],
        ),
      ],
      child: const Text('body'),
    ),
  );

  testTwk('a menu bar title reads as a Text does', (t) async {
    await t.pumpWidget(menuBar(hebrew), size: (30, 6));
    await logical(t);
    expect(t.lines[0], ' $hebrew');
    await visual(t);
    expect(t.lines[0], ' $reversed');
  });

  testTwk('the entries of a menu read as a Text does, a left-to-right one as '
      'before', (t) async {
    await t.pumpWidget(menuBar('&File'), size: (30, 6));
    await logical(t);
    await t.press('f10');
    await t.press('enter');
    await t.pump();
    expect(t, containsLine(contains('${hebrew}x')));
    expect(t, containsLine(contains('Open')));
    await visual(t);
    expect(t, containsLine(contains('x$reversed')));
    expect(t, containsLine(contains('Open')));
  });
}
