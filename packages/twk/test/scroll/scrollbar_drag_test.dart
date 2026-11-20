// A Scrollbar's thumb grabbed: the content stays where it is until the
// pointer moves, and a bar that never built is disposed without a lookup.
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
  list.jumpTo(12345);
  await t.pump();
  return list;
}

void main() {
  testTwk('a thumb pressed mid-cell and dragged to the same pixel moves '
      'nothing, whole cells reported', (t) async {
    final list = await show(t, pixels: false);
    // the thumb is one cell of 8 steps in 10 cells: its start is near row 1
    await t.mouse(MouseKind.down, 19, 1);
    await t.mouse(MouseKind.drag, 19, 1);
    await t.pump();
    expect(list.offset, 12345);
    await t.mouse(MouseKind.up, 19, 1);
  });

  testTwk('a thumb pressed mid-cell and dragged to the same pixel moves '
      'nothing, pixels reported', (t) async {
    final list = await show(t, pixels: true);
    await t.mouse(MouseKind.down, 19, 1, offsetY: 7);
    await t.mouse(MouseKind.drag, 19, 1, offsetY: 7);
    await t.pump();
    expect(list.offset, 12345);
    await t.mouse(MouseKind.up, 19, 1, offsetY: 7);
  });

  test('a bar that never built is disposed without a lookup', () {
    // what a first build that threw leaves: a state mounted, never built
    final state = const Scrollbar(child: Text('x')).createState();
    // the framework's call, made here as it would make it
    // ignore: invalid_use_of_protected_member
    expect(state.dispose, returnsNormally);
  });
}
