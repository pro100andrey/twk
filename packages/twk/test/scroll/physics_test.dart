// ScrollPhysics on SingleChildScrollView, and what NeverScrollableScrollPhysics
// leaves of a scrollable: the wheel goes to the view around, no key hints, and
// no stop of Tab.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Widget rows(int n) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [for (var i = 0; i < n; i++) Text('row $i')],
);

void main() {
  testTwk('a SingleChildScrollView with NeverScrollableScrollPhysics leaves '
      'the wheel to the view around', (t) async {
    final outer = ScrollController();
    addTearDown(outer.dispose);
    final inner = ScrollController();
    addTearDown(inner.dispose);
    await t.pumpWidget(
      SingleChildScrollView(
        controller: outer,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 4,
              child: SingleChildScrollView(
                controller: inner,
                physics: const NeverScrollableScrollPhysics(),
                child: rows(20),
              ),
            ),
            rows(20),
          ],
        ),
      ),
      size: (20, 8),
    );
    await t.mouse(MouseKind.wheelDown, 2, 1);
    await t.pump();
    expect((outer.offset, inner.offset), (3, 0));
    inner.jumpTo(5);
    await t.pump();
    expect(inner.offset, 5);
  });

  for (final (name, view) in <(String, Widget Function(FocusNode))>[
    (
      'SingleChildScrollView',
      (node) => SingleChildScrollView(
        focusNode: node,
        physics: const NeverScrollableScrollPhysics(),
        child: rows(20),
      ),
    ),
    (
      'ListView',
      (node) => ListView(
        focusNode: node,
        physics: const NeverScrollableScrollPhysics(),
        children: [for (var i = 0; i < 20; i++) Text('row $i')],
      ),
    ),
  ]) {
    testTwk('a $name that never scrolls offers no key hints and no stop '
        'of Tab', (t) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final other = FocusNode();
      addTearDown(other.dispose);
      await t.pumpWidget(
        Column(
          children: [
            SizedBox(height: 4, child: view(node)),
            Focus(focusNode: other, child: const Text('other')),
          ],
        ),
        size: (20, 6),
      );
      expect(
        [for (final k in t.binding.focusManager.activeKeys) k.hint],
        everyElement(isNull),
      );
      await t.press('tab');
      expect(node.hasFocus, isFalse);
      expect(other.hasFocus, isTrue);
      await t.press('tab');
      expect(node.hasFocus, isFalse);
    });
  }
}
