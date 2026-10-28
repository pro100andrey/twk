// The mouse in a TextField and a TextArea, through the parser: a press
// places the caret at the cell's character (a wide one's second cell too,
// past the end the end, through the scroll) and focuses the field; a drag
// selects, forward and back; a double press selects the word, a triple
// one the line, a drag after either going on by words or lines; Shift
// with a press selects from the base; an obscured field maps through its
// mask; a field that takes no focus takes no mouse.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show MouseTracking;
import 'package:twk_test/twk_test.dart';

/// A field of [c], [width] columns wide, at the top left.
Widget field(
  TextEditingController c, {
  int width = 20,
  FocusNode? focusNode,
  bool obscureText = false,
  String obscuringCharacter = '•',
  bool? canRequestFocus,
}) => SizedBox(
  width: width,
  child: TextField(
    controller: c,
    focusNode: focusNode,
    obscureText: obscureText,
    obscuringCharacter: obscuringCharacter,
    canRequestFocus: canRequestFocus,
  ),
);

/// An area of [c], [width] columns wide, at the top left.
Widget area(
  TextEditingController c, {
  int width = 10,
  int minLines = 1,
  int? maxLines,
  FocusNode? focusNode,
}) => SizedBox(
  width: width,
  child: TextArea(
    controller: c,
    focusNode: focusNode,
    minLines: minLines,
    maxLines: maxLines,
  ),
);

/// [child] at the top left.
Widget top(Widget child) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [child],
);

/// Presses the left button at [from], drags it to [to] and releases it
/// there.
Future<void> drag(TwkTester t, (int, int) from, (int, int) to) async {
  await t.mouse(MouseKind.down, from.$1, from.$2);
  await t.mouse(MouseKind.drag, to.$1, to.$2);
  await t.mouse(MouseKind.up, to.$1, to.$2);
  await t.pump();
}

/// Where the selection of [c] goes from and to.
(int, int) sel(TextEditingController c) =>
    (c.selection.baseOffset, c.selection.extentOffset);

void main() {
  group('TextField', () {
    testTwk('a press focuses it and places the caret at the character of the '
        "cell, a wide one's second cell too, the end past it", (t) async {
      final a = TextEditingController(text: 'first');
      final b = TextEditingController(text: 'ab中cd');
      final na = FocusNode();
      final nb = FocusNode();
      addTearDown(() {
        a.dispose();
        b.dispose();
        na.dispose();
        nb.dispose();
      });
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              field(a, focusNode: na),
              field(b, focusNode: nb),
            ],
          ),
        ),
        size: (20, 3),
      );
      na.requestFocus();
      await t.pump();
      final carets = <int>[];
      for (final x in [3, 2, 4, 1, 12]) {
        await t.click(x, 1);
        carets.add(b.selection.extentOffset);
        expect(b.selection.isCollapsed, isTrue);
      }
      // 中 takes cells 2 and 3
      expect(carets, [2, 2, 3, 1, 5]);
      expect(nb.hasFocus, isTrue);
      expect(na.hasFocus, isFalse);
      await t.pump();
      expect(t.cursor, (6, 1));
      await t.click(2, 0);
      expect(na.hasFocus, isTrue);
      expect(a.selection, const TextSelection.collapsed(offset: 2));
    });

    testTwk('a scrolled field maps the cell through its scroll', (t) async {
      final c = TextEditingController(text: 'abcdefghij');
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme.terminal(child: top(field(c, width: 5))),
        size: (10, 2),
      );
      await t.click(0, 0);
      await t.pump();
      // the caret at the end scrolled the text by 6 columns
      expect(t.lines[0], startsWith('ghij'));
      expect(c.selection, const TextSelection.collapsed(offset: 6));
      await t.click(3, 0);
      expect(c.selection, const TextSelection.collapsed(offset: 9));
    });

    testTwk('a drag selects from the cell pressed to the mouse, forward and '
        'back', (t) async {
      final c = TextEditingController(text: 'hello world');
      addTearDown(c.dispose);
      await t.pumpWidget(Theme.terminal(child: top(field(c))), size: (20, 2));
      await drag(t, (1, 0), (7, 0));
      expect(sel(c), (1, 7));
      expect(t, styleAt(1, 0, hasBg(const Color.indexed(237))));
      expect(t, styleAt(7, 0, isNot(hasBg(const Color.indexed(237)))));
      await drag(t, (7, 0), (2, 0));
      expect(sel(c), (7, 2));
      // past the end, to the end
      await drag(t, (3, 0), (15, 0));
      expect(sel(c), (3, 11));
    });

    testTwk('a double press selects the word, or the blanks, a triple press '
        'the text; a drag after either goes on by words; Shift with a press '
        'selects from the base', (t) async {
      final c = TextEditingController(text: 'one, two  three');
      addTearDown(c.dispose);
      await t.pumpWidget(Theme.terminal(child: top(field(c))), size: (20, 2));
      await t.click(6, 0);
      await t.click(6, 0);
      expect(sel(c), (5, 8));
      await t.click(9, 0);
      await t.click(9, 0);
      expect(sel(c), (8, 10));
      await t.click(3, 0);
      await t.click(3, 0);
      expect(sel(c), (3, 4));
      await t.click(1, 0);
      await t.click(1, 0);
      await t.click(1, 0);
      expect(sel(c), (0, 15));
      await t.pump(const Duration(milliseconds: 400));
      await t.click(6, 0);
      await t.pump(const Duration(milliseconds: 400));
      await t.click(6, 0);
      expect(sel(c), (6, 6));
      await t.pump(const Duration(milliseconds: 400));
      await t.click(6, 0);
      await t.mouse(MouseKind.down, 6, 0);
      await t.mouse(MouseKind.drag, 12, 0);
      await t.mouse(MouseKind.up, 12, 0);
      expect(sel(c), (5, 15));
      await t.pump(const Duration(milliseconds: 400));
      await t.click(2, 0);
      await t.mouse(MouseKind.down, 12, 0, modifiers: Mod.shift);
      await t.mouse(MouseKind.up, 12, 0, modifiers: Mod.shift);
      expect(sel(c), (2, 12));
    });

    testTwk('obscured, a cell maps through the mask, and a double press '
        'selects it all', (t) async {
      final c = TextEditingController(text: 'ab cd');
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: top(field(c, obscureText: true, obscuringCharacter: '🔒')),
        ),
        size: (20, 2),
      );
      expect(t.lines[0], startsWith('🔒🔒🔒🔒🔒'));
      await t.click(7, 0);
      expect(c.selection, const TextSelection.collapsed(offset: 3));
      await t.click(7, 0);
      expect(sel(c), (0, 5));
    });

    testTwk('one that takes no focus takes no mouse', (t) async {
      final c = TextEditingController(text: 'hello');
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme.terminal(child: top(field(c, canRequestFocus: false))),
        size: (20, 2),
      );
      expect(t.terminal.mouseTracking, MouseTracking.off);
      await t.click(1, 0);
      expect(c.selection, const TextSelection.collapsed(offset: 5));
    });
  });

  group('TextArea', () {
    // 'hello ' / 'world foo' / 'bar', the first two one line
    const notes = 'hello world foo\nbar';

    testTwk('a press focuses it and places the caret at the character of the '
        'cell: past the end of a row its end, below the last row the end of '
        'the text', (t) async {
      final c = TextEditingController(text: notes)
        ..selection = const TextSelection.collapsed(offset: 0);
      final node = FocusNode();
      addTearDown(() {
        c.dispose();
        node.dispose();
      });
      await t.pumpWidget(
        Theme.terminal(child: top(area(c, minLines: 5, focusNode: node))),
        size: (10, 6),
      );
      expect(t.lines.take(3), ['hello', 'world foo', 'bar']);
      final carets = <int>[];
      for (final (x, y) in [(2, 1), (9, 0), (8, 2), (0, 4), (0, 0)]) {
        await t.click(x, y);
        carets.add(c.selection.extentOffset);
      }
      expect(carets, [8, 5, 19, 19, 0]);
      expect(node.hasFocus, isTrue);
      await t.click(2, 2);
      await t.pump();
      expect(t.cursor, (2, 2));
    });

    testTwk("a wide character's second cell maps to it, and a scrolled area "
        'maps through its scroll', (t) async {
      final c = TextEditingController(text: 'a中b\n$notes');
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme.terminal(child: top(area(c, maxLines: 2))),
        size: (10, 3),
      );
      // the caret at the end: the rows of the second line's end shown
      await t.click(0, 0);
      await t.pump();
      expect(t.lines.take(2), ['world foo', 'bar']);
      expect(c.selection, const TextSelection.collapsed(offset: 10));
      await t.click(1, 1);
      expect(c.selection, const TextSelection.collapsed(offset: 21));
      c.selection = const TextSelection.collapsed(offset: 0);
      await t.pump();
      expect(t.lines[0], 'a中b');
      await t.click(2, 0);
      expect(c.selection, const TextSelection.collapsed(offset: 1));
      await t.click(3, 0);
      expect(c.selection, const TextSelection.collapsed(offset: 2));
    });

    testTwk('a drag selects across rows and lines, forward and back', (
      t,
    ) async {
      final c = TextEditingController(text: notes);
      addTearDown(c.dispose);
      await t.pumpWidget(Theme.terminal(child: top(area(c))), size: (10, 4));
      await drag(t, (1, 0), (2, 2));
      expect(sel(c), (1, 18));
      await drag(t, (3, 1), (1, 0));
      expect(sel(c), (9, 1));
    });

    testTwk('a double press selects the word in its line, a triple press the '
        'line; a drag after a triple press goes on by lines', (t) async {
      final c = TextEditingController(text: notes);
      addTearDown(c.dispose);
      await t.pumpWidget(Theme.terminal(child: top(area(c))), size: (10, 4));
      await t.click(2, 1);
      await t.click(2, 1);
      expect(sel(c), (6, 11));
      await t.pump(const Duration(milliseconds: 400));
      // past the end of 'bar': the word before
      await t.click(6, 2);
      await t.click(6, 2);
      expect(sel(c), (16, 19));
      await t.pump(const Duration(milliseconds: 400));
      await t.click(2, 1);
      await t.click(2, 1);
      await t.click(2, 1);
      expect(sel(c), (0, 15));
      await t.pump(const Duration(milliseconds: 400));
      await t.click(1, 2);
      await t.click(1, 2);
      await t.mouse(MouseKind.down, 1, 2);
      await t.mouse(MouseKind.drag, 1, 0);
      await t.mouse(MouseKind.up, 1, 0);
      expect(sel(c), (19, 0));
    });

    testTwk('a double press on an empty line selects nothing, the caret on '
        'that line', (t) async {
      final c = TextEditingController(text: 'one\n\nthree');
      addTearDown(c.dispose);
      await t.pumpWidget(Theme.terminal(child: top(area(c))), size: (10, 4));
      await t.click(2, 1);
      await t.click(2, 1);
      expect(sel(c), (4, 4));
    });
  });
}
