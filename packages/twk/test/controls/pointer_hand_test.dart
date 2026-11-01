// The hand over what a click presses, where the theme asks for it: a
// button while it is enabled, the terminal's own pointer off it and over a
// disabled one, and with the theme's default none, the mouse's motion not
// asked for; read off the tester's terminal, which shows pointer shapes
// when asked to.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show MouseTracking, MouseTrackingBackend;
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk("the hand over an enabled button, the terminal's own pointer off "
      'it and over a disabled one', (t) async {
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await t.pumpWidget(
      Theme(
        data: const ThemeData.terminal(
          Brightness.dark,
        ).copyWith(handPointer: HandPointer.on),
        child: ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (context, on, _) => Row(
            children: [
              Button('Save', onPressed: on ? () {} : null),
            ],
          ),
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

  testTwk("by the theme's default no hand where the motion is not reported, "
      'and none asked for', (t) async {
    // a box to check, whose look the hover does not change
    await t.pumpWidget(
      Checkbox(value: false, onChanged: (_) {}, label: 'ok'),
      size: (20, 1),
      pointerShapes: true,
    );
    await t.mouse(MouseKind.move, 1, 0);
    await t.pump();
    expect(t.pointerShape, isNot(PointerShape.pointer));
    expect(
      (t.binding.twkApp.terminal as MouseTrackingBackend).mouseTracking,
      isNot(MouseTracking.motion),
    );
  });

  testTwk('a terminal that shows no pointer shapes is given none', (t) async {
    await t.pumpWidget(Button('Save', onPressed: () {}), size: (20, 1));
    await t.mouse(MouseKind.move, 2, 0);
    await t.pump();
    expect(t.pointerShape, isNull);
    expect(t.written(), isNot(contains('\x1b]22;')));
  });
}
