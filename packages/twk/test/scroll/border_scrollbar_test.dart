// Box(scrollbar:): the bar of the scrollable inside drawn on the box's
// right border between its corners, a heavier line for the thumb, the
// border's own line while there is nothing to scroll; the child keeps all
// the room inside; the thumb dragged scrolls the content.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A column of [count] rows, `item 0` on.
Widget column(int count) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [for (var i = 0; i < count; i++) Text('item $i')],
);

/// The glyphs of column [x], rows 0 to [rows] - 1.
List<String> down(TwkTester t, int x, int rows) => [
  for (var y = 0; y < rows; y++) t.cell(x, y).text,
];

/// A panel of [count] rows in a scroll view, its bar on its border.
Widget panel(int count, {ScrollController? controller}) => Box(
  border: const Border.all(),
  scrollbar: Axis.vertical,
  child: SingleChildScrollView(controller: controller, child: column(count)),
);

void main() {
  testTwk('the thumb on the right border, between its corners; the child '
      'keeps the room inside', (t) async {
    await t.pumpWidget(panel(32), size: (20, 10));
    // 8 cells of track inside the corners, 2 of thumb
    expect(down(t, 19, 10), [
      '┐',
      '┃',
      '┃',
      ...List.filled(6, '│'),
      '┘',
    ]);
    expect(t.lines[1], '│item 0            ┃');
    expect(
      t,
      styleAt(
        19,
        1,
        hasFg(const ThemeData.terminal(Brightness.dark).muted.fg!),
      ),
    );
  });

  testTwk("the border's own line while there is nothing to scroll", (
    t,
  ) async {
    await t.pumpWidget(panel(3), size: (20, 10));
    expect(down(t, 19, 10), ['┐', ...List.filled(8, '│'), '┘']);
  });

  testTwk('the thumb dragged scrolls the content', (t) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await t.pumpWidget(panel(32, controller: controller), size: (20, 10));
    await t.mouse(MouseKind.down, 19, 1);
    await t.mouse(MouseKind.drag, 19, 5);
    await t.mouse(MouseKind.up, 19, 5);
    await t.pump();
    expect(controller.offset, greaterThan(0));
    expect(t.lines[1], isNot(contains('item 0')));
  });
}
