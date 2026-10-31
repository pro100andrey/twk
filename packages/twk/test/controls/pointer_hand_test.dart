// The hand over what a click presses: a button while it is enabled, the
// terminal's own pointer off it and over a disabled one; read off the
// tester's terminal, which shows pointer shapes when asked to.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk("the hand over an enabled button, the terminal's own pointer off "
      'it and over a disabled one', (t) async {
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await t.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: enabled,
        builder: (context, on, _) => Row(
          children: [
            Button('Save', onPressed: on ? () {} : null),
          ],
        ),
      ),
      size: (20, 1),
      pointerShapes: true,
    );
    // the terminal's default pointer
    expect(t.pointerShape, PointerShape.arrow);
    await t.mouse(MouseKind.move, 2, 0);
    await t.pump();
    expect(t.pointerShape, PointerShape.pointer);
    await t.mouse(MouseKind.move, 15, 0);
    await t.pump();
    expect(t.pointerShape, PointerShape.arrow);
    enabled.value = false;
    await t.pump();
    await t.mouse(MouseKind.move, 2, 0);
    await t.pump();
    expect(t.pointerShape, PointerShape.arrow);
  });

  testTwk('a terminal that shows no pointer shapes is given none', (t) async {
    await t.pumpWidget(Button('Save', onPressed: () {}), size: (20, 1));
    await t.mouse(MouseKind.move, 2, 0);
    await t.pump();
    expect(t.pointerShape, isNull);
    expect(t.written(), isNot(contains('\x1b]22;')));
  });
}
