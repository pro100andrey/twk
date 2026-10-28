// What an object's paint does besides painting its cells still happens
// when a scroll view paints only the rows a scroll exposed and the object
// is not among them: the terminal's cursor at the caret of a field goes
// with the field, and is hidden once the field is scrolled off; a popover
// follows the child it shows by; an Opacity mixes what a repaint boundary
// inside it repaints with what is under it where it is now, from the frame
// after the one that found what it kept of that gone.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('the cursor goes with a field a scroll view scrolls', (t) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    final c = TextEditingController(text: 'abc');
    addTearDown(c.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await t.pumpWidget(
      SingleChildScrollView(
        controller: scroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 3; i++) Text('line $i'),
            SizedBox(
              width: 10,
              child: TextField(controller: c, focusNode: node),
            ),
            for (var i = 3; i < 30; i++) Text('line $i'),
          ],
        ),
      ),
      size: (12, 5),
    );
    node.requestFocus();
    await t.pump();
    expect(t, cursorAt(3, 3));

    scroll.jumpTo(1);
    await t.pump();
    expect(t, cursorAt(3, 2));

    scroll.jumpTo(3);
    await t.pump();
    expect(t, cursorAt(3, 0));

    scroll.jumpTo(5);
    await t.pump();
    expect(t.cursorVisible, isFalse);

    scroll.jumpTo(2);
    await t.pump();
    expect(t, cursorAt(3, 1));
  });

  testTwk('a popover follows its child a scroll view scrolls', (t) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await t.pumpWidget(
      Overlay(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // the popover shows under the view, over none of it
            SizedBox(
              height: 4,
              child: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < 3; i++) Text('line $i'),
                    const Popover(
                      open: true,
                      popover: Text('pop'),
                      child: Text('anchor'),
                    ),
                    for (var i = 3; i < 30; i++) Text('line $i'),
                  ],
                ),
              ),
            ),
            for (var i = 0; i < 6; i++) Text('below $i'),
          ],
        ),
      ),
      size: (12, 10),
    );
    await t.pump();
    expect(t, hasTextAt(0, 3, 'anchor'));
    expect(t, hasTextAt(0, 4, 'pop'));
    scroll.jumpTo(1);
    await t.pump();
    await t.pump();
    expect(t, hasTextAt(0, 2, 'anchor'));
    expect(t, hasTextAt(0, 3, 'pop'));
    expect(t, hasTextAt(0, 4, 'below 0'));
    // scrolled off: placed where the child is now, as a frame that paints
    // everything places it
    scroll.jumpTo(5);
    await t.pump();
    await t.pump();
    final shown = t.lines;
    await t.resize(12, 11);
    await t.pump();
    expect(t.lines.take(10), shown);
  });

  testTwk('an Opacity mixes a repaint boundary inside it that repaints on '
      'its own where a scroll view scrolled it', (t) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await t.pumpWidget(
      SingleChildScrollView(
        controller: scroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 3; i++) Text('line $i'),
            const Opacity(
              opacity: 0.5,
              child: Spinner(
                style: Style(
                  fg: Color.rgb(255, 255, 255),
                  bg: Color.rgb(0, 0, 200),
                ),
              ),
            ),
            for (var i = 3; i < 30; i++) Text('line $i'),
          ],
        ),
      ),
      size: (12, 6),
    );
    final mixed = (t.cell(0, 3).fg, t.cell(0, 3).bg);
    expect(mixed.$2, isNot(const Color.rgb(0, 0, 200).value));
    scroll.jumpTo(1);
    await t.pump();
    for (var step = 0; step < 3; step++) {
      // the spinner turns: it repaints on its own, mixed from the frame
      // after the scroll's at the latest
      await t.pump(const Duration(milliseconds: 80));
      await t.pump();
      expect((t.cell(0, 2).fg, t.cell(0, 2).bg), mixed);
    }
  });
}
