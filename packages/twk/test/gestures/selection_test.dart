// Text selected with the mouse in a SelectionArea: drags across wrapped
// and wide text and from one Text to the next, words and lines by double
// and triple clicks, the highlight, and the copy (OSC 52), also wrapped for
// tmux and GNU screen.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show Multiplexer, clipboardSequence;
import 'package:twk_test/twk_test.dart';

/// [children] one below another from the left, in a [SelectionArea] that
/// tells [copies] what it copied.
Widget area(
  List<String> copies,
  List<Widget> children, {
  Style? style,
  bool copyOnRelease = true,
  String? copyKey,
}) => SelectionArea(
  style: style,
  copyOnRelease: copyOnRelease,
  copyKey: copyKey,
  onCopy: copies.add,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  ),
);

/// Presses the left button at [from], drags it through [through] and
/// releases it at the last of those.
Future<void> drag(
  TwkTester t,
  (int, int) from,
  List<(int, int)> through,
) async {
  await t.mouse(MouseKind.down, from.$1, from.$2);
  for (final (x, y) in through) {
    await t.mouse(MouseKind.drag, x, y);
  }
  final (x, y) = through.last;
  await t.mouse(MouseKind.up, x, y);
  await t.pump();
}

/// The columns of row [y] from 0 to [width] with the selection's background
/// video, as `x`, and without, as `.`.
String marked(TwkTester t, int y, int width) => [
  for (var x = 0; x < width; x++)
    if (t.vt.cell(x, y).bg == const Color.indexed(237).value) 'x' else '.',
].join();

void main() {
  testTwk('a drag selects from cell to cell across wrapped and wide text and '
      'on to the next Text; the release copies it', (t) async {
    final copies = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: area(copies, const [Text('hello world'), Text('a中b')]),
      ),
      size: (7, 4),
    );
    expect(t.lines.take(3), ['hello', 'world', 'a中b']);
    await drag(t, (1, 0), [(3, 1), (2, 2)]);
    expect(copies, ['ello world\na中']);
    expect(t.written(), contains(clipboardSequence('ello world\na中')));
    expect(marked(t, 0, 7), '.xxxx..');
    expect(marked(t, 1, 7), 'xxxxx..');
    expect(marked(t, 2, 7), 'xxx....');
  });

  testTwk('drags between two frames: each Text selected by either is drawn '
      'selected', (t) async {
    final copies = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: area(copies, const [Text('aaa'), Text('bbb'), Text('ccc')]),
      ),
      size: (5, 4),
    );
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.drag, 1, 1);
    await t.mouse(MouseKind.drag, 1, 2);
    await t.pump();
    expect(marked(t, 0, 3), '.xx');
    expect(marked(t, 1, 3), 'xxx');
    expect(marked(t, 2, 3), 'xx.');
  });

  testTwk('a drag back: from the cell pressed to the one before it, both '
      'included', (t) async {
    final copies = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: area(copies, const [Text('hello world'), Text('a中b')]),
      ),
      size: (7, 4),
    );
    await drag(t, (1, 2), [(3, 0)]);
    expect(copies, ['lo world\na中']);
  });

  testTwk('a drag from right of a row: what follows the row, the Text '
      'nearest by rows first', (t) async {
    final copies = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: area(copies, const [Text('hello world'), Text('a中b')]),
      ),
      size: (7, 4),
    );
    await drag(t, (6, 0), [(2, 1)]);
    expect(copies, ['wor']);
    await drag(t, (6, 3), [(3, 2)]);
    expect(copies.last, 'b');
  });

  testTwk('the spans of a Text: selected across them, each keeping its own '
      "style under the selection's", (t) async {
    final copies = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: area(
          copies,
          const [
            Text.rich([
              Span('bold', Style(attrs: Attr.bold)),
              Span(' plain'),
            ]),
          ],
          style: const Style(bg: Color.rgb(1, 2, 3)),
        ),
      ),
      size: (12, 2),
    );
    await drag(t, (2, 0), [(6, 0)]);
    expect(copies, ['ld pl']);
    expect(t, styleAt(1, 0, isNot(hasBg(const Color.rgb(1, 2, 3)))));
    expect(t, styleAt(2, 0, hasBg(const Color.rgb(1, 2, 3))));
    expect(t, styleAt(3, 0, hasAttr(Attr.bold)));
    expect(t, styleAt(6, 0, hasBg(const Color.rgb(1, 2, 3))));
    expect(t, styleAt(7, 0, isNot(hasBg(const Color.rgb(1, 2, 3)))));
  });

  testTwk('a double click selects the word, or the blanks, a triple click '
      'the line; a click after the interval is a click of its own', (
    t,
  ) async {
    final copies = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: area(copies, const [Text('one, two  three\nfour')]),
      ),
      size: (20, 3),
    );
    await t.click(6, 0);
    await t.click(6, 0);
    expect(copies, ['two']);
    await t.click(9, 0);
    await t.click(9, 0);
    expect(copies.last, '  ');
    await t.click(3, 0);
    await t.click(3, 0);
    expect(copies.last, ',');
    await t.click(1, 1);
    await t.click(1, 1);
    await t.click(1, 1);
    expect(copies.last, 'four');
    await t.click(2, 0);
    await t.click(2, 0);
    await t.click(2, 0);
    await t.pump();
    expect(copies.last, 'one, two  three');
    expect(marked(t, 0, 16), 'xxxxxxxxxxxxxxx.');
    expect(marked(t, 1, 5), '.....');
    copies.clear();
    await t.click(6, 0);
    await t.pump(const Duration(milliseconds: 400));
    await t.click(6, 0);
    await t.pump();
    expect(copies, isEmpty);
    expect(marked(t, 0, 16), '................');
  });

  testTwk('a drag after a double click goes on by words, after a triple one '
      'by lines', (t) async {
    final copies = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: area(copies, const [Text('one two\nthree four'), Text('five')]),
      ),
      size: (12, 4),
    );
    await t.click(5, 0);
    await t.mouse(MouseKind.down, 5, 0);
    await t.mouse(MouseKind.drag, 7, 1);
    await t.mouse(MouseKind.up, 7, 1);
    expect(copies, ['two\nthree four']);
    await t.click(1, 0);
    await t.click(1, 0);
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.drag, 1, 2);
    await t.mouse(MouseKind.up, 1, 2);
    expect(copies.last, 'one two\nthree four\nfive');
  });

  testTwk('a click clears the selection and copies nothing', (t) async {
    final copies = <String>[];
    await t.pumpWidget(
      Theme.terminal(child: area(copies, const [Text('hello')])),
      size: (7, 2),
    );
    await drag(t, (0, 0), [(2, 0)]);
    expect(marked(t, 0, 5), 'xxx..');
    await t.click(4, 0);
    await t.pump();
    expect(marked(t, 0, 5), '.....');
    expect(copies, ['hel']);
  });

  testTwk('the copy key copies what is selected; with nothing selected the '
      'key passes on', (t) async {
    final copies = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: area(
          copies,
          const [Text('hello')],
          copyOnRelease: false,
          copyKey: 'ctrl+c',
        ),
      ),
      size: (7, 2),
    );
    await drag(t, (1, 0), [(3, 0)]);
    expect(copies, isEmpty);
    await t.press('ctrl+c');
    expect(copies, ['ell']);
    expect(t.isRunning, isTrue);
    await t.click(4, 0);
    await t.pump();
    await t.press('ctrl+c');
    await t.pump();
    expect(t.isRunning, isFalse, reason: 'Ctrl+C quits');
  });

  testTwk('a Text shortened under its selection: what is left of it is '
      'selected', (t) async {
    final copies = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: area(copies, const [Text('hello')], copyKey: 'ctrl+y'),
      ),
      size: (7, 2),
    );
    await drag(t, (1, 0), [(3, 0)]);
    await t.pumpWidget(
      Theme.terminal(
        child: area(copies, const [Text('he')], copyKey: 'ctrl+y'),
      ),
    );
    expect(marked(t, 0, 3), '.x.');
    await t.press('ctrl+y');
    expect(copies, ['ell', 'e']);
  });

  for (final (multiplexer, wrapped) in [
    (
      Multiplexer.tmux,
      '\x1b]52;c;ZWxsbw==\x1b\\\x1bPtmux;\x1b\x1b]52;c;ZWxsbw==\x1b\x1b\\\x1b\\',
    ),
    (Multiplexer.screen, '\x1bP\x1b]52;c;ZWxsbw==\x07\x1b\\'),
  ]) {
    testTwk('inside ${multiplexer.name}: the OSC 52 wrapped for it', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(child: area(copies, const [Text('hello')])),
        size: (7, 2),
        multiplexer: multiplexer,
      );
      await drag(t, (1, 0), [(4, 0)]);
      expect(copies, ['ello']);
      expect(t.written(), contains(wrapped));
    });
  }

  testTwk('a GestureDetector inside that drags keeps its drags', (t) async {
    final copies = <String>[];
    final drags = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: area(copies, [
          GestureDetector(
            onDragUpdate: (d) => drags.add('${d.x},${d.y}'),
            child: const Text('drag me'),
          ),
          const Text('select me'),
        ]),
      ),
      size: (10, 3),
    );
    await drag(t, (1, 0), [(4, 0)]);
    expect(drags, ['4,0']);
    expect(copies, isEmpty);
    await drag(t, (1, 1), [(4, 1)]);
    expect(copies, ['elec']);
  });

  testTwk("a press in a text field is the field's: it clears the selection, "
      'and its drags, double and triple presses select in the field '
      'alone', (t) async {
    final copies = <String>[];
    final c = TextEditingController(text: 'hello world');
    addTearDown(c.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: area(copies, [
          const Text('one two'),
          SizedBox(width: 12, child: TextField(controller: c)),
        ]),
      ),
      size: (12, 3),
    );
    await drag(t, (0, 0), [(2, 0)]);
    expect(copies, ['one']);
    expect(marked(t, 0, 7), 'xxx....');
    await t.click(1, 1);
    await t.pump();
    expect(marked(t, 0, 7), '.......');
    expect(c.selection, const TextSelection.collapsed(offset: 1));
    await t.click(1, 1);
    await t.click(1, 1);
    await t.pump();
    expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 11));
    await t.pump(const Duration(milliseconds: 400));
    await drag(t, (7, 1), [(9, 1), (2, 1)]);
    expect(c.selection, const TextSelection(baseOffset: 7, extentOffset: 2));
    expect(copies, ['one']);
    expect(marked(t, 0, 7), '.......');
  });
}
