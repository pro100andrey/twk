// The cell under a visible block cursor is written in its own foreground:
// Konsole paints the block in it, and a blank a Backspace leaves was written
// in the foreground of the line written last (the status line's).
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const _statusFg = Color.rgb(200, 40, 40);

Widget _app(TextEditingController c) => Theme(
  data: ThemeData.dark,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 5,
        child: TextField(
          controller: c,
          autofocus: true,
          cursorShape: CursorShape.block,
        ),
      ),
      const Text('status', style: Style(fg: _statusFg)),
    ],
  ),
);

void main() {
  testTwk('a Backspace in a TextField with a block cursor leaves the blank '
      "under it in the text's foreground, not the status line's", (t) async {
    final c = TextEditingController(text: 'abc')
      ..selection = const TextSelection.collapsed(offset: 3);
    addTearDown(c.dispose);
    await t.pumpWidget(_app(c), size: (10, 2));
    expect(t.vt.cursorShape, CursorShape.block.code);
    final x = t.vt.cx;
    await t.press('backspace');
    await t.pump();
    expect(c.text, 'ab');
    expect(t.vt.cx, x - 1);
    expect(t.vt.cell(t.vt.cx, 0).fgColor, t.vt.cell(0, 0).fgColor);
    expect(t.vt.cell(0, 0).fgColor, isNot(_statusFg));
  });

  testTwk('with a bar cursor nothing more is written under it', (t) async {
    final c = TextEditingController(text: 'abc')
      ..selection = const TextSelection.collapsed(offset: 3);
    addTearDown(c.dispose);
    await t.pumpWidget(
      Theme(
        data: ThemeData.dark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 5,
              child: TextField(controller: c, autofocus: true),
            ),
            const Text('status', style: Style(fg: _statusFg)),
          ],
        ),
      ),
      size: (10, 2),
    );
    expect(t.vt.cursorShape, CursorShape.bar.code);
    await t.press('backspace');
    await t.pump();
    expect(t.vt.cell(t.vt.cx, 0).fgColor, isNot(t.vt.cell(0, 0).fgColor));
  });
}
