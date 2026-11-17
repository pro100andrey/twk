// A Scrollbar's thumb dragged where the terminal reports the pointer in
// pixels: the content follows the part of a cell the pointer moved, which
// on a long list is many rows; with whole cells reported, as before.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Future<ListController> show(TwkTester t, {required bool pixels}) async {
  final list = ListController();
  addTearDown(list.dispose);
  await t.pumpWidget(
    Scrollbar(
      child: ListView.builder(
        itemCount: 100000,
        controller: list,
        itemBuilder: (context, index) => Text('item $index'),
      ),
    ),
    size: (20, 10),
    cellPixels: (10, 20),
    pixelMouse: pixels,
  );
  await t.pump();
  list.jumpTo(99990);
  await t.pump();
  return list;
}

void main() {
  testTwk('the thumb dragged within cells moves the list by the part of a '
      'cell', (t) async {
    final list = await show(t, pixels: true);
    // pressed in the middle of row 9, dragged to the top of row 4: five and
    // a half cells, 44 of the 72 eighths of room
    await t.mouse(MouseKind.down, 19, 9, offsetY: 10);
    await t.mouse(MouseKind.drag, 19, 4, offsetY: 0);
    await t.pump();
    expect(list.offset, (99990 * (72 - 44) / 72).round());
    // to the cell's pixel 16: 4.7 cells back, 37.6 eighths
    await t.mouse(MouseKind.drag, 19, 4, offsetY: 16);
    await t.pump();
    expect(list.offset, (99990 * 34.4 / 72).round());
    await t.mouse(MouseKind.up, 19, 4, offsetY: 16);
  });

  testTwk('with whole cells reported it moves by whole cells', (t) async {
    final list = await show(t, pixels: false);
    await t.mouse(MouseKind.down, 19, 9);
    await t.mouse(MouseKind.drag, 19, 4);
    await t.pump();
    expect(list.offset, 44440);
    await t.mouse(MouseKind.up, 19, 4);
  });
}
