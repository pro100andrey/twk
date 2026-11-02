// TreeView(physics:): a tree in an app's own scrolling list leaves the wheel
// to the list, and keeps its own keys.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('a TreeView with NeverScrollableScrollPhysics leaves the wheel to '
      'the list around, and keeps its keys and its stop of Tab', (t) async {
    final outer = ScrollController();
    final controller = TreeController();
    final node = FocusNode();
    await t.pumpWidget(
      SingleChildScrollView(
        controller: outer,
        canRequestFocus: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 4,
              child: TreeView<String>(
                roots: [for (var i = 0; i < 20; i++) 'n$i'],
                children: (_) => const [],
                label: (context, entry) => Text(entry.node),
                controller: controller,
                focusNode: node,
                physics: const NeverScrollableScrollPhysics(),
              ),
            ),
            for (var i = 0; i < 20; i++) Text('row $i'),
          ],
        ),
      ),
      size: (20, 8),
    );
    expect(node.hasFocus, isFalse);
    await t.press('tab');
    expect(node.hasFocus, isTrue);
    await t.press('end');
    expect(controller.selectedKey, 'n19');
    await t.pump();
    expect(t.lines.join('\n'), contains('n19'));
    await t.mouse(MouseKind.wheelDown, 2, 1);
    expect(outer.offset, 3);
  });
}
