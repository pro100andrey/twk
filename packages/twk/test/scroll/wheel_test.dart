// A ListView that does not take the user's scrolling (ScrollPhysics): the
// wheel over it goes to the scrollable around it, its keys do nothing, and
// its controller still moves it.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  Widget list(ScrollController inner, {ScrollPhysics? physics}) => ListView(
    controller: inner,
    physics: physics,
    autofocus: true,
    children: [for (var i = 0; i < 20; i++) Text('item $i')],
  );

  Widget around(
    ScrollController outer,
    ScrollController inner, {
    ScrollPhysics? physics,
  }) => SingleChildScrollView(
    controller: outer,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 4, child: list(inner, physics: physics)),
        for (var i = 0; i < 20; i++) Text('row $i'),
      ],
    ),
  );

  testTwk('the wheel over a ListView takes it', (t) async {
    final outer = ScrollController();
    final inner = ScrollController();
    await t.pumpWidget(around(outer, inner), size: (20, 8));
    await t.mouse(MouseKind.wheelDown, 2, 1);
    await t.pump();
    expect((outer.offset, inner.offset), (0, 3));
  });

  testTwk('with NeverScrollableScrollPhysics the wheel over a ListView goes '
      'to the view around', (t) async {
    final outer2 = ScrollController();
    final inner2 = ScrollController();
    await t.pumpWidget(
      around(outer2, inner2, physics: const NeverScrollableScrollPhysics()),
      size: (20, 8),
    );
    await t.mouse(MouseKind.wheelDown, 2, 1);
    await t.pump();
    expect((outer2.offset, inner2.offset), (3, 0));
  });

  testTwk('NeverScrollableScrollPhysics leaves the keys and the hints out, '
      'and the controller still moves the list', (t) async {
    final inner = ScrollController();
    await t.pumpWidget(
      SizedBox(
        height: 4,
        child: list(inner, physics: const NeverScrollableScrollPhysics()),
      ),
      size: (20, 4),
    );
    await t.press('down');
    await t.press('pagedown');
    expect(inner.offset, 0);
    inner.jumpTo(5);
    await t.pump();
    expect(inner.offset, 5);
    expect(t.lines.first, 'item 5');
  });
}
