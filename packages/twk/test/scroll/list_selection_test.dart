// A ListView with itemText: one Selectable for all its items, built or
// not, selected by a drag across them, scrolled by a drag past its edge,
// copied, drawn by the items that ask ListView.selectionOf, and selected
// from a SelectionAreaController.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

final List<String> names = [for (var i = 0; i < 30; i++) 'item $i'];

/// The cells of row [y], columns 0 to [width] - 1, with the selection's
/// background video as `x`, and without as `.`.
String marked(TwkTester t, int y, int width) => [
  for (var x = 0; x < width; x++)
    if (t.vt.cell(x, y).bg == const Color.indexed(237).value) 'x' else '.',
].join();

Widget app({
  SelectionAreaController? controller,
  void Function(String)? onCopy,
  bool reverse = false,
  bool separated = false,
  ItemText Function(int)? text,
  int count = 30,
  bool draw = true,
}) {
  Widget item(BuildContext context, int index) {
    final selected = draw ? ListView.selectionOf(context, index) : null;
    return Text.rich(
      selected?.spans(names[index]) ?? [Span(names[index])],
      wrap: TextWrap.none,
    );
  }

  return Theme.terminal(
    child: SelectionArea(
      controller: controller,
      onCopy: onCopy,
      child: separated
          ? ListView.separated(
              itemCount: count,
              itemBuilder: item,
              separatorBuilder: (context, index) => const Text('--'),
              itemText: text ?? (i) => ItemText(names[i]),
              reverse: reverse,
            )
          : ListView.builder(
              itemCount: count,
              itemBuilder: item,
              itemText: text ?? (i) => ItemText(names[i]),
              reverse: reverse,
            ),
    ),
  );
}

void main() {
  group('a ListView with itemText', () {
    testTwk('a drag across items selects and draws the text between, copied '
        'one line each', (t) async {
      final copies = <String>[];
      await t.pumpWidget(app(onCopy: copies.add), size: (10, 5));
      await t.mouse(MouseKind.down, 2, 0);
      await t.mouse(MouseKind.drag, 3, 2);
      await t.mouse(MouseKind.up, 3, 2);
      await t.pump();
      expect(copies, ['em 0\nitem 1\nitem']);
      expect(marked(t, 0, 7), '..xxxx.');
      expect(marked(t, 1, 7), 'xxxxxx.');
      expect(marked(t, 2, 7), 'xxxx...');
      expect(marked(t, 3, 7), '.......');
    });

    testTwk('a drag past the bottom scrolls the list on, items not built '
        'before are in the copy', (t) async {
      final copies = <String>[];
      await t.pumpWidget(app(onCopy: copies.add), size: (10, 5));
      await t.mouse(MouseKind.down, 0, 0);
      await t.mouse(MouseKind.drag, 3, 4);
      await t.pump(const Duration(milliseconds: 400));
      await t.mouse(MouseKind.up, 3, 4);
      await t.pump();
      final copied = copies.single.split('\n');
      expect(copied.length, greaterThan(6), reason: 'went past the window');
      expect(copied.first, 'item 0');
      expect([
        for (var i = 0; i < copied.length - 1; i++) 'item $i',
      ], copied.take(copied.length - 1).toList());
      expect(t.lines[0], isNot('item 0'));
    });

    testTwk('items that scroll out and in keep what is selected of them', (
      t,
    ) async {
      final controller = SelectionAreaController();
      addTearDown(controller.dispose);
      await t.pumpWidget(app(controller: controller), size: (10, 5));
      await t.mouse(MouseKind.down, 0, 1);
      await t.mouse(MouseKind.drag, 3, 2);
      await t.mouse(MouseKind.up, 3, 2);
      await t.pump();
      expect(controller.text, 'item 1\nitem');
      for (var i = 0; i < 20; i++) {
        await t.mouse(MouseKind.wheelDown, 5, 2);
      }
      await t.pump();
      expect(t.lines[0], isNot('item 1'));
      expect(controller.text, 'item 1\nitem');
      for (var i = 0; i < 20; i++) {
        await t.mouse(MouseKind.wheelUp, 5, 2);
      }
      await t.pump();
      expect(t.lines[1], 'item 1');
      expect(marked(t, 1, 7), 'xxxxxx.');
      expect(marked(t, 2, 7), 'xxxx...');
    });

    testTwk('the controller selects a range in it, and selectAll selects all '
        'of it, rows not built too', (t) async {
      final controller = SelectionAreaController();
      addTearDown(controller.dispose);
      await t.pumpWidget(app(controller: controller), size: (10, 5));
      controller.selectAll();
      await t.pump();
      final list = controller.start!.object;
      expect(controller.text, names.join('\n'));
      expect(marked(t, 0, 6), 'xxxxxx');
      expect(marked(t, 4, 6), 'xxxxxx');
      controller.clear();
      await t.pump();
      expect(marked(t, 0, 6), '......');
      final start = (object: list, offset: 9);
      expect(controller.select(start, (object: list, offset: 18)), isTrue);
      await t.pump();
      expect(controller.text, 'em 1\nitem');
      expect(marked(t, 1, 7), '..xxxx.');
      expect(marked(t, 2, 7), 'xxxx...');
    });

    testTwk('a reverse list selects in the order of the screen', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        app(onCopy: copies.add, reverse: true, count: 3),
        size: (10, 5),
      );
      // item 2 at the top of the three at the bottom: rows 2, 3, 4
      expect(t.lines[2], 'item 2');
      await t.mouse(MouseKind.down, 0, 2);
      await t.mouse(MouseKind.drag, 3, 3);
      await t.mouse(MouseKind.up, 3, 3);
      await t.pump();
      expect(copies, ['item 2\nitem']);
      expect(marked(t, 2, 6), 'xxxxxx');
      expect(marked(t, 3, 6), 'xxxx..');
    });

    testTwk('a drag past the top of a reverse list scrolls it up, to items '
        'above the window', (t) async {
      final copies = <String>[];
      await t.pumpWidget(app(onCopy: copies.add, reverse: true), size: (10, 5));
      // item 29 is at the top of the screen's order: item 0 at the bottom
      await t.mouse(MouseKind.down, 0, 4);
      await t.mouse(MouseKind.drag, 3, 0);
      await t.pump(const Duration(milliseconds: 400));
      await t.mouse(MouseKind.up, 3, 0);
      await t.pump();
      final copied = copies.single.split('\n');
      expect(copied.length, greaterThan(6), reason: 'went past the window');
      expect(copied.last, 'i');
      expect(copied[copied.length - 2], 'item 1');
      expect(t.lines[4], isNot('item 0'));
    });

    testTwk('separators are not selected, nor copied', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        app(onCopy: copies.add, separated: true, count: 5),
        size: (10, 6),
      );
      expect(t.lines[1], '--');
      await t.mouse(MouseKind.down, 0, 0);
      await t.mouse(MouseKind.drag, 3, 4);
      await t.mouse(MouseKind.up, 3, 4);
      await t.pump();
      expect(copies, ['item 0\nitem 1\nitem']);
    });

    testTwk('the runs of an item are cells of their own, what is between is '
        'not text', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        app(
          onCopy: copies.add,
          draw: false,
          count: 2,
          text: (i) => ItemText.runs([(0, 'ab'), (5, 'cd')]),
        ),
        size: (12, 3),
      );
      // the cells of 'ab' and 'cd': from b to c, the gap between not text
      await t.mouse(MouseKind.down, 1, 0);
      await t.mouse(MouseKind.drag, 5, 0);
      await t.mouse(MouseKind.up, 5, 0);
      await t.pump();
      expect(copies, ['b\tc']);
    });

    testTwk('without the option, the items select as Texts do', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: SelectionArea(
            onCopy: copies.add,
            child: ListView.builder(
              itemCount: 3,
              itemBuilder: (context, i) => Text(names[i]),
            ),
          ),
        ),
        size: (10, 4),
      );
      await t.mouse(MouseKind.down, 0, 0);
      await t.mouse(MouseKind.drag, 3, 1);
      await t.mouse(MouseKind.up, 3, 1);
      await t.pump();
      expect(copies, ['item 0\nitem']);
    });
  });
}
