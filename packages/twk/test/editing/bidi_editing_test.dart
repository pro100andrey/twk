// Fields and areas in visual order: right-to-left text drawn as it reads,
// the terminal's cursor at the caret where it shows, Left and Right moving
// it a cell at a time as the text is drawn, the other keys as it is
// stored, Up and Down keeping the column drawn, the selection the text
// between its ends as stored wherever its pieces are drawn. Visual order is
// the default on a headless terminal, which does no bidi. In logical order,
// for a terminal that reorders text itself, nothing of it.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show PipelineTextOrder, TextOrder;
import 'package:twk_test/twk_test.dart';

/// A focused field of [c], [width] columns wide.
Widget field(
  TextEditingController c, {
  int width = 20,
  bool obscureText = false,
}) => Align(
  alignment: Alignment.topLeft,
  child: SizedBox(
    width: width,
    child: TextField(controller: c, autofocus: true, obscureText: obscureText),
  ),
);

/// A focused area of [c], [width] columns wide.
Widget area(TextEditingController c, {int width = 20}) => Align(
  alignment: Alignment.topLeft,
  child: SizedBox(
    width: width,
    child: TextArea(controller: c, autofocus: true),
  ),
);

/// Draws the app's text in visual order from the next frame on.
Future<void> visual(TwkTester t) async {
  t.binding.twkApp.owner.textOrder = TextOrder.visual;
  await t.pump();
}

/// The caret's offset and the cursor's column after each of [keys].
Future<List<(int, int)>> after(
  TwkTester t,
  TextEditingController c,
  String keys,
) async {
  final out = <(int, int)>[];
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
    out.add((c.selection.extentOffset, t.cursor.$1));
  }
  return out;
}

/// Expects the cells of row [y] up to [width] selected at [columns] only.
void expectSelected(TwkTester t, int y, List<int> columns, int width) {
  for (var x = 0; x < width; x++) {
    expect(
      t,
      styleAt(
        x,
        y,
        columns.contains(x)
            ? hasBg(const Color.indexed(237))
            : isNot(hasBg(const Color.indexed(237))),
      ),
      reason: 'column $x',
    );
  }
}

void main() {
  group('a field', () {
    testTwk('in visual order by default on a headless terminal', (t) async {
      final c = TextEditingController(text: 'abc אבג');
      await t.pumpWidget(Theme.terminal(child: field(c)), size: (20, 1));
      expect(t.binding.twkApp.owner.textOrder, TextOrder.visual);
      expect(t.lines[0], 'abc גבא');
    });

    testTwk('in logical order (a terminal that reorders itself) draws and '
        'moves as the text is stored', (t) async {
      final c = TextEditingController(text: 'abc אבג');
      await t.pumpWidget(Theme.terminal(child: field(c)), size: (20, 1));
      t.binding.twkApp.owner.textOrder = TextOrder.logical;
      await t.pump();
      expect(t.lines[0], 'abc אבג');
      expect(t, cursorAt(7, 0));
      expect(await after(t, c, 'left right'), [(6, 6), (7, 7)]);
    });

    testTwk('in visual order draws Hebrew and Arabic as they read, numbers '
        'and brackets the way they go', (t) async {
      final c = TextEditingController(text: 'abc אבג (12)');
      await t.pumpWidget(
        Theme.terminal(child: field(c, width: 30)),
        size: (30, 1),
      );
      await visual(t);
      expect(t.lines[0], 'abc (12) גבא');
      c.text = 'العدد 123 فقط';
      await t.pump();
      expect(t.lines[0], 'طقف 123 ددعلا');
    });

    testTwk('shows the caret at the end of a right-to-left word where the '
        'next letter goes; Left and Right move it a cell as drawn', (
      t,
    ) async {
      final c = TextEditingController(text: 'abc אבג');
      await t.pumpWidget(Theme.terminal(child: field(c)), size: (20, 1));
      await visual(t);
      expect(t.lines[0], 'abc גבא');
      expect(t, cursorAt(4, 0));
      expect(await after(t, c, 'left left'), [(3, 3), (2, 2)]);
      expect(await after(t, c, 'right right right right right right'), [
        (3, 3),
        (7, 4),
        (6, 5),
        (5, 6),
        (4, 7),
        (4, 7),
      ]);
      await t.type('ד');
      await t.pump();
      expect(c.text, 'abc דאבג');
      expect(t.lines[0], 'abc גבאד');
      expect(t, cursorAt(7, 0));
    });

    testTwk('narrower than its text, scrolls as drawn to keep the caret in '
        'view, at the start of a character', (t) async {
      final c = TextEditingController(text: 'abcdefgh 漢字 אבג');
      await t.pumpWidget(
        Theme.terminal(child: field(c, width: 5)),
        size: (20, 1),
      );
      await visual(t);
      // the caret at column 14 as drawn; 漢 at 9 and 10 left out whole
      expect(t.lines[0], '字 גב');
      expect(t.cursor, (3, 0));
    });

    testTwk('in a right-to-left paragraph Right goes back through the text '
        'and Left on; Ctrl with them a word as the paragraph runs', (
      t,
    ) async {
      final c = TextEditingController(text: 'שלום עולם');
      await t.pumpWidget(Theme.terminal(child: field(c)), size: (20, 1));
      await visual(t);
      expect(t.lines[0], 'םלוע םולש');
      expect(t, cursorAt(0, 0));
      expect(await after(t, c, 'left ctrl+right ctrl+right ctrl+left'), [
        (9, 0),
        (5, 4),
        (0, 9),
        (4, 5),
      ]);
      expect(await after(t, c, 'right right left'), [(3, 6), (2, 7), (3, 6)]);
    });

    testTwk('Home, End, Alt+B and the keys that delete go as the text is '
        'stored', (t) async {
      final c = TextEditingController(text: 'abc אבג');
      await t.pumpWidget(Theme.terminal(child: field(c)), size: (20, 1));
      await visual(t);
      expect(await after(t, c, 'home end alt+b'), [(0, 0), (7, 4), (4, 7)]);
      await t.press('end backspace');
      await t.pump();
      expect(c.text, 'abc אב');
      expect(t.lines[0], 'abc בא');
      expect(t, cursorAt(4, 0));
    });

    testTwk('shows the selection where its pieces are drawn; Left and Right '
        'end it at the end drawn on their side', (t) async {
      final c = TextEditingController(text: 'abc אבג');
      await t.pumpWidget(Theme.terminal(child: field(c)), size: (20, 1));
      await visual(t);
      c.selection = const TextSelection(baseOffset: 2, extentOffset: 5);
      await t.pump();
      expect(t, cursorAt(6, 0));
      expectSelected(t, 0, [2, 3, 6], 10);
      await t.press('left');
      expect(c.selection, const TextSelection.collapsed(offset: 2));
      c.selection = const TextSelection(baseOffset: 2, extentOffset: 5);
      await t.press('right');
      expect(c.selection, const TextSelection.collapsed(offset: 5));
      // within a right-to-left run its start is on the right
      c.selection = const TextSelection(baseOffset: 4, extentOffset: 6);
      await t.press('left');
      expect(c.selection, const TextSelection.collapsed(offset: 6));
    });

    testTwk('Shift with Right selects as the caret moves as drawn', (t) async {
      final c = TextEditingController(text: 'ab אב');
      await t.pumpWidget(Theme.terminal(child: field(c)), size: (20, 1));
      await visual(t);
      expect(t, cursorAt(3, 0));
      await t.press('shift+right shift+right');
      await t.pump();
      expect(c.selection, const TextSelection(baseOffset: 5, extentOffset: 3));
      expect(t, cursorAt(5, 0));
      expectSelected(t, 0, [3, 4], 10);
    });

    testTwk('an obscured text moves as stored, by characters and words', (
      t,
    ) async {
      final c = TextEditingController(text: 'אבג דה');
      await t.pumpWidget(
        Theme.terminal(child: field(c, obscureText: true)),
        size: (20, 1),
      );
      await visual(t);
      expect(t.lines[0], '••••••');
      expect(await after(t, c, 'left ctrl+left ctrl+left ctrl+right'), [
        (5, 5),
        (4, 4),
        (0, 0),
        (3, 3),
      ]);
    });
  });

  group('an area', () {
    testTwk('draws each line as it reads, one whose first strong character '
        'is right to left in that direction', (t) async {
      final c = TextEditingController(text: 'abc אבג\nשלום abc');
      await t.pumpWidget(Theme.terminal(child: area(c)), size: (20, 2));
      await visual(t);
      expect(t.lines, ['abc גבא', 'abc םולש']);
      expect(t, cursorAt(3, 1));
    });

    testTwk('breaks rows as stored, a blank hanging past the left edge of a '
        'right-to-left row', (t) async {
      final c = TextEditingController(text: 'שלום עולם');
      await t.pumpWidget(
        Theme.terminal(child: area(c, width: 6)),
        size: (6, 2),
      );
      await visual(t);
      expect(t.lines, [' םולש', 'םלוע']);
      await t.pumpWidget(
        Theme.terminal(child: area(c, width: 4)),
        size: (4, 3),
      );
      expect(t.lines, ['םולש', 'םלוע', '']);
    });

    testTwk('Left at the edge of a right-to-left line goes on into the next '
        'line, and back', (t) async {
      final c = TextEditingController(text: 'שלום\nab');
      await t.pumpWidget(Theme.terminal(child: area(c)), size: (20, 2));
      await visual(t);
      c.selection = const TextSelection.collapsed(offset: 0);
      await t.pump();
      expect(t, cursorAt(4, 0));
      final out = <(int, (int, int))>[];
      for (final key in 'left left left left left right right'.split(' ')) {
        await t.press(key);
        await t.pump();
        out.add((c.selection.extentOffset, t.cursor));
      }
      expect(out, [
        (1, (3, 0)),
        (2, (2, 0)),
        (3, (1, 0)),
        (4, (0, 0)),
        (5, (0, 1)),
        (6, (1, 1)),
        (7, (2, 1)),
      ]);
      await t.press('home left');
      await t.pump();
      expect(c.selection.extentOffset, 4);
      expect(t, cursorAt(0, 0));
    });

    testTwk('Up and Down keep the column as drawn', (t) async {
      final c = TextEditingController(text: 'abcdef\nאבגדהו');
      await t.pumpWidget(Theme.terminal(child: area(c)), size: (20, 2));
      await visual(t);
      expect(t.lines, ['abcdef', 'והדגבא']);
      c.selection = const TextSelection.collapsed(offset: 2);
      await t.press('down');
      await t.pump();
      expect(c.selection.extentOffset, 11);
      expect(t, cursorAt(2, 1));
      await t.press('right up');
      await t.pump();
      expect(c.selection.extentOffset, 3);
      expect(t, cursorAt(3, 0));
    });

    testTwk('shows the selection where its pieces are drawn', (t) async {
      final c = TextEditingController(text: 'abc אבג\nde');
      await t.pumpWidget(Theme.terminal(child: area(c)), size: (20, 2));
      await visual(t);
      c.selection = const TextSelection(baseOffset: 2, extentOffset: 5);
      await t.pump();
      expectSelected(t, 0, [2, 3, 6], 10);
      expectSelected(t, 1, [], 10);
    });
  });
}
