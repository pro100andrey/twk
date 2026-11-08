// A Table's row menu: a right click on a row selects it and opens its menu
// at the mouse, the row under the mouse whatever the scroll and the row
// height; Shift+F10 opens the menu of the row selected under it, its first
// entry highlighted, and is told as `shift+f10 menu`.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

typedef File = ({String name});

final files = <File>[for (var i = 0; i < 30; i++) (name: 'n$i')];

void main() {
  late List<String> log;
  late TableController controller;

  setUp(() {
    log = [];
    controller = TableController();
  });

  Widget table({int? rowHeight = 1}) => App(
    child: Table<File>(
      rows: files,
      controller: controller,
      rowHeight: rowHeight,
      autofocus: true,
      columns: [
        TableColumn(title: 'Name', cell: (f) => TableCell(f.name)),
      ],
      rowMenu: (f) => [
        MenuItem('Open', onSelected: () => log.add('open ${f.name}')),
        MenuItem('Delete', onSelected: () => log.add('delete ${f.name}')),
      ],
    ),
  );

  Future<void> rightClick(TwkTester t, int x, int y) async {
    await t.click(x, y, button: 2);
    await t.pumpUntilIdle();
  }

  int lineOf(TwkTester t, String text) =>
      t.lines.indexWhere((l) => l.contains(text));

  Future<void> choose(TwkTester t, String item) async {
    final y = lineOf(t, item);
    await t.click(t.lines[y].indexOf(item), y);
    await t.pumpUntilIdle();
  }

  testTwk('a right click selects the row and opens its menu at the mouse', (
    t,
  ) async {
    await t.pumpWidget(table(), size: (30, 10));
    await rightClick(t, 1, 3);
    expect(controller.selectedKey, 2);
    expect(lineOf(t, 'Open'), greaterThan(3));
    await choose(t, 'Delete');
    expect(log, ['delete n2']);
  });

  testTwk('scrolled, the row under the mouse', (t) async {
    await t.pumpWidget(table(), size: (30, 10));
    await t.press('end');
    await t.pumpUntilIdle();
    final y = lineOf(t, 'n25');
    await rightClick(t, 1, y);
    expect(controller.selectedKey, 25);
    await choose(t, 'Open');
    expect(log, ['open n25']);
  });

  testTwk('Shift+F10 on a row scrolled out of view scrolls to it first', (
    t,
  ) async {
    await t.pumpWidget(table(), size: (30, 8));
    await t.press('down');
    await t.pumpUntilIdle();
    for (var i = 0; i < 3; i++) {
      await t.mouse(MouseKind.wheelDown, 1, 3);
    }
    await t.pumpUntilIdle();
    expect(lineOf(t, 'n0'), -1);
    await t.press('shift+f10');
    await t.pumpUntilIdle();
    expect(lineOf(t, 'n0'), isNonNegative);
    expect(lineOf(t, 'Open'), greaterThan(lineOf(t, 'n0')));
    await t.press('enter');
    await t.pumpUntilIdle();
    expect(log, ['open n0']);
  });

  testTwk('with no selection, a right click opens the menu of the row under '
      'the mouse; Shift+F10 none', (t) async {
    await t.pumpWidget(
      App(
        child: Table<File>(
          rows: files,
          selection: TableSelection.none,
          autofocus: true,
          columns: [
            TableColumn(title: 'Name', cell: (f) => TableCell(f.name)),
          ],
          rowMenu: (f) => [
            MenuItem('Open', onSelected: () => log.add('open ${f.name}')),
          ],
        ),
      ),
      size: (30, 10),
    );
    await t.press('shift+f10');
    await t.pumpUntilIdle();
    expect(lineOf(t, 'Open'), -1);
    await rightClick(t, 1, 2);
    await choose(t, 'Open');
    expect(log, ['open n1']);
  });

  testTwk('rows two tall: the row under the mouse', (t) async {
    await t.pumpWidget(table(rowHeight: 2), size: (30, 12));
    // the header, then n0 on rows 1 and 2, n1 on rows 3 and 4
    await rightClick(t, 1, 4);
    expect(controller.selectedKey, 1);
  });

  testTwk('Shift+F10 opens the menu of the row selected under it, its first '
      'entry highlighted; told as shift+f10 menu', (t) async {
    await t.pumpWidget(table(), size: (30, 12));
    expect(
      t.binding.focusManager.activeKeys.map((k) => k.hint),
      contains('menu'),
    );
    // the first Down selects the first row
    for (var i = 0; i < 4; i++) {
      await t.press('down');
    }
    await t.pumpUntilIdle();
    expect(controller.selectedKey, 3);
    final row = lineOf(t, 'n3');
    await t.press('shift+f10');
    await t.pumpUntilIdle();
    // under the row: a row of the panel's room, then the first entry
    expect(lineOf(t, 'Open'), row + 2);
    expect(t.lines[row + 2], contains('▎ Open'));
    await t.press('enter');
    await t.pumpUntilIdle();
    expect(log, ['open n3']);
  });
}
