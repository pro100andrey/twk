// A boundary that keeps what is under it (a TextField) moved by a scroll
// that moves its cells (the surface's scrollRect) rather than painting
// them again: what it puts back as it repaints alone is what is under it
// where the scroll took it.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  for (final list in [false, true]) {
    final name = list ? 'a ListView' : 'a SingleChildScrollView';
    testTwk('a field scrolled by $name while in view, focused and left, '
        'has no focus background left on it', (t) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final field = FocusNode(debugLabel: 'field');
      addTearDown(field.dispose);
      final other = FocusNode(debugLabel: 'other');
      addTearDown(other.dispose);
      Widget row(int i) => i == 5
          ? SizedBox(
              width: 20,
              child: TextField(
                focusNode: field,
                placeholder: 'field',
                focusedStyle: const Style(bg: Color.red),
              ),
            )
          : i == 0
          ? Focus(focusNode: other, child: const Text('row 0'))
          : Text('row $i');
      await t.pumpWidget(
        SizedBox(
          height: 10,
          child: list
              ? ListView.builder(
                  controller: controller,
                  itemCount: 30,
                  itemBuilder: (context, i) => row(i),
                )
              : SingleChildScrollView(
                  controller: controller,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (var i = 0; i < 30; i++) row(i)],
                  ),
                ),
        ),
        size: (24, 10),
      );
      expect(t.lines[5], 'field');
      controller.jumpTo(2);
      await t.pump();
      expect(t.lines[3], 'field');
      field.requestFocus();
      await t.pump();
      expect(t, styleAt(10, 3, hasBg(Color.red)));
      field.unfocus();
      await t.pump();
      expect(t, styleAt(10, 3, isNot(hasBg(Color.red))));
      expect(t, styleAt(0, 3, isNot(hasBg(Color.red))));
    });
  }

  testTwk('a field wider than the view that scrolls it, in a row that '
      'scrolls sideways, focused and left after a scroll, has no focus '
      'background left on it', (t) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final field = FocusNode(debugLabel: 'field');
    addTearDown(field.dispose);
    Widget row(int i) => i == 5
        ? SizedBox(
            height: 1,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 40,
                child: TextField(
                  focusNode: field,
                  placeholder: 'field',
                  focusedStyle: const Style(bg: Color.red),
                ),
              ),
            ),
          )
        : Text('row $i');
    await t.pumpWidget(
      SizedBox(
        height: 10,
        child: SingleChildScrollView(
          controller: controller,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (var i = 0; i < 30; i++) row(i)],
          ),
        ),
      ),
      size: (24, 10),
    );
    expect(t.lines[5], 'field');
    controller.jumpTo(2);
    await t.pump();
    expect(t.lines[3], 'field');
    field.requestFocus();
    await t.pump();
    expect(t, styleAt(10, 3, hasBg(Color.red)));
    field.unfocus();
    await t.pump();
    expect(t, styleAt(10, 3, isNot(hasBg(Color.red))));
    expect(t, styleAt(0, 3, isNot(hasBg(Color.red))));
  });
}
