// Lines of text edited through the parser: rows broken by word, a long
// word and wide glyphs between characters, the caret after a full row on a
// row of its own; the area growing from minLines to maxLines, then
// scrolling to keep the caret in view; Up, Down, PageUp and PageDown by
// rows keeping the caret's column; the line's ends for Home, End, Ctrl+U
// and Ctrl+K; Enter and onSubmitted; a paste keeping its line breaks; undo
// and redo; the selection across rows and line breaks; a megabyte pasted
// and edited in time, of many lines or of one, no keystroke putting its
// text together; a keystroke repainting the area alone and laying out the
// lines in view only.
//
// "In time" is in passes over the text (passOver): measured on the
// machine at the same moment, a machine busy with other work slows both
// alike, where a bound in milliseconds was passed under `handover -j`.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/src/editing/text_buffer.dart' show TextBuffer;
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../data/shot.dart' show Counted, PaintCount;

/// The microseconds of a pass over [text] that taking it in at all makes:
/// its UTF-8 bytes decoded and its lines found, the mean of three.
double passOver(String text) {
  // real time on purpose: what the work costs is what is measured
  final watch = Stopwatch()..start();
  var lines = 0;
  for (var i = 0; i < 3; i++) {
    lines += utf8.decode(utf8.encode(text)).split('\n').length;
  }
  expect(lines, greaterThan(0));
  return watch.elapsedMicroseconds / 3;
}

/// A focused area of [c], [width] columns wide, its height its own.
Widget area(
  TextEditingController c, {
  int width = 10,
  int minLines = 1,
  int? maxLines,
  void Function(String)? onChanged,
  void Function(String)? onSubmitted,
  Key? key,
}) => Align(
  alignment: Alignment.topLeft,
  child: SizedBox(
    width: width,
    child: TextArea(
      key: key,
      controller: c,
      autofocus: true,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    ),
  ),
);

/// Where the cursor is after each of [keys], pressed in turn.
Future<List<(int, int)>> cursorsAfter(TwkTester t, String keys) async {
  final cursors = <(int, int)>[];
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
    cursors.add(t.cursor);
  }
  return cursors;
}

void main() {
  testTwk('breaks its lines into rows by word, and grows from minLines to '
      'maxLines, then scrolls to keep the caret in view', (t) async {
    final c = TextEditingController();
    await t.pumpWidget(
      Theme.terminal(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 10,
              child: TextArea(
                controller: c,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
              ),
            ),
            const Text('---'),
          ],
        ),
      ),
      size: (12, 6),
    );
    expect(t.lines.sublist(0, 3), ['', '', '---']);
    expect(t, cursorAt(0, 0));
    await t.type('the quick brown fox jumps');
    await t.pump();
    expect(t.lines.sublist(0, 4), ['the quick', 'brown fox', 'jumps', '---']);
    expect(t, cursorAt(5, 2));
    await t.type(' over the lazy dog');
    await t.pump();
    expect(t.lines.sublist(0, 5), [
      'brown fox',
      'jumps over',
      'the lazy',
      'dog',
      '---',
    ]);
    expect(t, cursorAt(3, 3));
    expect(t.vt.cursorShape, CursorShape.bar.code);
  });

  testTwk('breaks a word longer than a row between characters, a wide one '
      'whole, CJK between characters, and puts the caret after a full row '
      'on a row of its own', (
    t,
  ) async {
    final c = TextEditingController(text: 'abcdefghijklmn');
    await t.pumpWidget(Theme.terminal(child: area(c, width: 6)), size: (8, 4));
    expect(t.lines.sublist(0, 3), ['abcdef', 'ghijkl', 'mn']);
    expect(t, cursorAt(2, 2));
    c.text = 'abcde日本 語';
    await t.pump();
    expect(t.lines.sublist(0, 3), ['abcde', '日本', '語']);
    expect(t, cursorAt(2, 2));
    c.text = '日本語のテキスト';
    await t.pump();
    expect(t.lines.sublist(0, 3), ['日本語', 'のテキ', 'スト']);
    expect(t, cursorAt(4, 2));
    c.text = 'ab 日本語';
    await t.pump();
    expect(t.lines.sublist(0, 2), ['ab 日', '本語']);
    c.text = 'abcdef';
    await t.pump();
    expect(t.lines.sublist(0, 2), ['abcdef', '']);
    expect(t, cursorAt(0, 1));
    // before a blank hanging past the edge, the caret is on the next row
    c
      ..text = 'abcdef  gh'
      ..selection = const TextSelection.collapsed(offset: 6);
    await t.pump();
    expect(t.lines.sublist(0, 2), ['abcdef', 'gh']);
    expect(t, cursorAt(0, 1));
    await t.press('right right right');
    await t.pump();
    expect(t, cursorAt(1, 1));
  });

  testTwk('Up and Down move a row, wrapped or not, keeping the column the '
      'caret had, over wide glyphs; with Shift they select', (t) async {
    final c = TextEditingController(text: 'one two three four\n日本語日本語\nxy')
      ..selection = const TextSelection.collapsed(offset: 5);
    await t.pumpWidget(Theme.terminal(child: area(c, width: 8)), size: (8, 7));
    expect(t.lines.sublist(0, 6), [
      'one two',
      'three',
      'four',
      '日本語日',
      '本語',
      'xy',
    ]);
    expect(t, cursorAt(5, 0));
    expect(await cursorsAfter(t, 'down down down down down up up up up'), [
      (5, 1),
      (4, 2),
      (4, 3),
      (4, 4),
      (2, 5),
      (4, 4),
      (4, 3),
      (4, 2),
      (5, 1),
    ]);
    await t.press('shift+down shift+down');
    expect(c.selection, const TextSelection(baseOffset: 13, extentOffset: 21));
    await t.type('|');
    expect(c.text, 'one two three|語日本語\nxy');
  });

  testTwk('Up on the first row moves to the start of the text, Down on the '
      'last to its end, and then they go up to the nodes above', (t) async {
    final c = TextEditingController(text: 'abc\ndef')
      ..selection = const TextSelection.collapsed(offset: 1);
    final above = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: Focus(
          onKeyEvent: (node, event) {
            above.add('${KeyCombo.fromEvent(event)}');
            return KeyEventResult.handled;
          },
          child: area(c),
        ),
      ),
      size: (10, 3),
    );
    final carets = <int>[];
    for (final key in ['up', 'up', 'down', 'down', 'down', 'up']) {
      await t.press(key);
      carets.add(c.selection.extentOffset);
    }
    // back up the column Up and Down keep
    expect(carets, [0, 0, 5, 7, 7, 1]);
    expect(above, ['up', 'down']);
  });

  testTwk('PageUp and PageDown move the caret and the text as many rows as '
      'the area shows', (t) async {
    final c = TextEditingController(
      text: [for (var i = 0; i < 20; i++) 'line $i'].join('\n'),
    )..selection = const TextSelection.collapsed(offset: 3);
    await t.pumpWidget(
      Theme.terminal(child: area(c, maxLines: 5)),
      size: (10, 6),
    );
    expect(t.lines.sublist(0, 5), [
      'line 0',
      'line 1',
      'line 2',
      'line 3',
      'line 4',
    ]);
    await t.press('pagedown');
    await t.pump();
    expect(t.lines.sublist(0, 5), [
      'line 5',
      'line 6',
      'line 7',
      'line 8',
      'line 9',
    ]);
    expect(t, cursorAt(3, 0));
    await t.press('pagedown pagedown pagedown');
    await t.pump();
    expect(t.lines[0], 'line 15');
    expect(t.lines[4], 'line 19');
    expect(t, cursorAt(3, 4));
    await t.press('pagedown');
    await t.pump();
    expect(t, cursorAt(7, 4));
    await t.press('pageup');
    await t.pump();
    expect(t.lines.sublist(0, 5), [
      'line 10',
      'line 11',
      'line 12',
      'line 13',
      'line 14',
    ]);
    expect(t, cursorAt(3, 4));
    await t.press('shift+pageup');
    expect(
      c.selection.range.textInside(c.text),
      'e 9\nline 10\nline 11\nline 12\nline 13\nlin',
    );
  });

  testTwk('scrolls a row at a time to keep the caret in view, without '
      'blank rows after the text', (t) async {
    final c = TextEditingController(text: 'a\nb\nc\nd\ne\nf');
    await t.pumpWidget(
      Theme.terminal(child: area(c, maxLines: 3)),
      size: (10, 4),
    );
    expect(t.lines.sublist(0, 3), ['d', 'e', 'f']);
    await t.press('up up up');
    await t.pump();
    expect(t.lines.sublist(0, 3), ['c', 'd', 'e']);
    expect(t, cursorAt(1, 0));
    await t.press('ctrl+end');
    await t.pump();
    expect(t.lines.sublist(0, 3), ['d', 'e', 'f']);
    await t.press('shift+up shift+up shift+up backspace');
    await t.pump();
    expect(c.text, 'a\nb\nc');
    expect(t.lines.sublist(0, 3), ['a', 'b', 'c']);
    await t.press('ctrl+home');
    await t.pump();
    expect(t, cursorAt(0, 0));
  });

  testTwk("Home, End, Ctrl+A and Ctrl+E go to the ends of the caret's line, "
      'Ctrl+Home and Ctrl+End to those of the text; Ctrl+U and Ctrl+K '
      'delete to the ends of the line, and at them join the lines', (
    t,
  ) async {
    final c = TextEditingController(text: 'ab\ncd\nef')
      ..selection = const TextSelection.collapsed(offset: 4);
    await t.pumpWidget(Theme.terminal(child: area(c)), size: (10, 3));
    final carets = <int>[];
    for (final key in ['home', 'end', 'ctrl+a', 'ctrl+e', 'ctrl+home']) {
      await t.press(key);
      carets.add(c.selection.extentOffset);
    }
    await t.press('ctrl+end');
    carets.add(c.selection.extentOffset);
    expect(carets, [3, 5, 3, 5, 0, 8]);
    c.selection = const TextSelection.collapsed(offset: 4);
    final texts = <String>[];
    for (final key in ['ctrl+k', 'ctrl+k', 'ctrl+u', 'ctrl+u']) {
      await t.press(key);
      texts.add(c.text);
    }
    expect(texts, ['ab\nc\nef', 'ab\ncef', 'ab\nef', 'abef']);
  });

  testTwk('Left, Right, words and Backspace go over the line breaks', (
    t,
  ) async {
    final c = TextEditingController(text: 'one\n\ntwo three\nfour');
    await t.pumpWidget(
      Theme.terminal(child: area(c, width: 20)),
      size: (20, 4),
    );
    final carets = <int>[];
    for (final key in [
      'ctrl+left',
      'left',
      'ctrl+left',
      'ctrl+left',
      'alt+b',
      'ctrl+right',
      'right',
      'alt+f',
    ]) {
      await t.press(key);
      carets.add(c.selection.extentOffset);
    }
    expect(carets, [15, 14, 9, 5, 4, 8, 9, 14]);
    await t.press('ctrl+home down');
    await t.press('backspace');
    expect(c.text, 'one\ntwo three\nfour');
    await t.press('ctrl+w');
    expect(c.text, '\ntwo three\nfour');
  });

  testTwk('Enter breaks the line; with onSubmitted, Enter submits and '
      'Alt+Enter breaks the line', (t) async {
    final c = TextEditingController(text: 'ab');
    final submitted = <String>[];
    await t.pumpWidget(Theme.terminal(child: area(c)), size: (10, 4));
    await t.press('left enter');
    await t.pump();
    expect(c.text, 'a\nb');
    expect(t.lines.sublist(0, 2), ['a', 'b']);
    expect(t, cursorAt(0, 1));
    await t.pumpWidget(
      Theme.terminal(child: area(c, onSubmitted: submitted.add)),
    );
    await t.press('enter alt+enter');
    expect(submitted, ['a\nb']);
    expect(c.text, 'a\n\nb');
  });

  testTwk('takes a paste as typed, keeping its line breaks, without other '
      'control characters but tabs', (t) async {
    final c = TextEditingController(text: '> ');
    final changed = <String>[];
    await t.pumpWidget(
      Theme.terminal(child: area(c, width: 20, onChanged: changed.add)),
      size: (20, 5),
    );
    await t.paste('one\r\ntwo\rthree\x07\tfour\n');
    await t.pump();
    expect(c.text, '> one\ntwo\nthree\tfour\n');
    expect(changed, [c.text]);
    expect(t.lines.sublist(0, 4), ['> one', 'two', 'three four', '']);
    expect(t, cursorAt(0, 3));
  });

  testTwk('Ctrl+Z undoes typing a word at a time and a paste at once, '
      'Ctrl+Y redoes; with nothing to undo they go up', (t) async {
    final c = TextEditingController();
    final changed = <String>[];
    final above = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: Focus(
          onKeyEvent: (node, event) {
            above.add('${KeyCombo.fromEvent(event)}');
            return KeyEventResult.handled;
          },
          child: area(c, width: 20, onChanged: changed.add),
        ),
      ),
      size: (20, 3),
    );
    await t.type('hello world');
    await t.paste('\nmore');
    final texts = <String>[];
    for (final key in ['ctrl+z', 'ctrl+z', 'ctrl+z', 'ctrl+y', 'ctrl+y']) {
      await t.press(key);
      texts.add(c.text);
    }
    expect(texts, [
      'hello world',
      'hello ',
      '',
      'hello ',
      'hello world',
    ]);
    expect(changed.sublist(changed.length - 5), texts);
    await t.press('ctrl+y ctrl+y ctrl+z');
    expect(c.text, 'hello world');
    expect(above, ['ctrl+y']);
    await t.pump();
    expect(t, cursorAt(11, 0));
  });

  testTwk('shows the selection across rows and lines, a line break in it '
      'as a cell', (t) async {
    final c = TextEditingController(text: 'abc def\nxy\n\nz')
      ..selection = const TextSelection(baseOffset: 2, extentOffset: 12);
    await t.pumpWidget(Theme.terminal(child: area(c, width: 5)), size: (6, 5));
    expect(t.lines.sublist(0, 5), ['abc', 'def', 'xy', '', 'z']);
    bool selected(int x, int y) =>
        t.cell(x, y).bg == const Color.indexed(237).value;
    final rows = [
      for (var y = 0; y < 5; y++)
        [
          for (var x = 0; x < 5; x++)
            if (selected(x, y)) '#' else '.',
        ].join(),
    ];
    // the blank after "abc" ends its row; the line breaks show
    expect(rows, ['..##.', '####.', '###..', '#....', '.....']);
  });

  testTwk('shows its placeholder while empty, in the muted style, and the '
      "controller's composing range underlined", (t) async {
    final c = TextEditingController();
    await t.pumpWidget(
      Theme.terminal(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 10,
            child: TextArea(
              controller: c,
              autofocus: true,
              placeholder: 'Message',
            ),
          ),
        ),
      ),
      size: (10, 2),
    );
    expect(t.lines[0], 'Message');
    expect(t, styleAt(0, 0, hasFg(const Color.indexed(245))));
    expect(t, cursorAt(0, 0));
    c.value = const TextEditingValue(
      text: 'ab\nnihon',
      selection: TextSelection.collapsed(offset: 8),
      composing: TextRange(start: 5, end: 8),
    );
    await t.pump();
    expect(t.lines.sublist(0, 2), ['ab', 'nihon']);
    final underlined = [
      for (var x = 0; x < 6; x++) t.cell(x, 1).attrs & Attr.underline != 0,
    ];
    expect(underlined, [false, false, true, true, true, false]);
  });

  testTwk('hides the cursor once it loses the focus', (t) async {
    final c = TextEditingController(text: 'ab\ncd');
    await t.pumpWidget(
      Theme.terminal(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 10,
              child: TextArea(controller: c, autofocus: true),
            ),
            const Focus(child: Text('elsewhere')),
          ],
        ),
      ),
      size: (10, 3),
    );
    expect(t, cursorAt(2, 1));
    await t.press('tab');
    await t.pump();
    expect(t.cursorVisible, isFalse);
  });

  testTwk('as wide as its widest line and a column for the caret where '
      'asked', (t) async {
    final c = TextEditingController(text: 'ab\n日本語\nc');
    await t.pumpWidget(
      Theme.terminal(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicWidth(child: TextArea(controller: c, autofocus: true)),
            const Text('|'),
          ],
        ),
      ),
      size: (20, 3),
    );
    expect(t.lines, ['ab     |', '日本語', 'c']);
  });

  testTwk('grows with its text under IntrinsicHeight, which asks for its '
      'height', (t) async {
    final c = TextEditingController(text: 'a');
    await t.pumpWidget(
      Theme.terminal(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 10,
              child: IntrinsicHeight(
                child: TextArea(controller: c, autofocus: true, maxLines: 3),
              ),
            ),
            const Text('---'),
          ],
        ),
      ),
      size: (10, 5),
    );
    expect(t.lines.sublist(0, 2), ['a', '---']);
    await t.press('enter b enter c enter d');
    await t.pump();
    expect(t.lines.sublist(0, 4), ['b', 'c', 'd', '---']);
  });

  testTwk('in the inline mode the region grows with its text', (t) async {
    final c = TextEditingController();
    await t.pumpWidget(
      Theme.terminal(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('prompt'),
            TextArea(controller: c, autofocus: true, maxLines: 3),
          ],
        ),
      ),
      size: (20, 8),
      mode: ScreenMode.inline,
      history: ['earlier'],
    );
    expect(t, cursorAt(0, 2));
    await t.press('o n e enter t w o enter');
    await t.pump();
    expect(t.lines.sublist(0, 5), ['earlier', 'prompt', 'one', 'two', '']);
    expect(t, cursorAt(0, 4));
    await t.press('backspace');
    await t.pump();
    expect(t, cursorAt(3, 3));
  });

  testTwk('a keystroke repaints nothing but the area', (t) async {
    final count = PaintCount();
    final c = TextEditingController(text: 'one\ntwo');
    await t.pumpWidget(
      Theme.terminal(
        child: Column(
          children: [
            Counted(count),
            SizedBox(
              height: 3,
              child: TextArea(controller: c, autofocus: true),
            ),
            Counted(count),
          ],
        ),
      ),
      size: (20, 5),
    );
    final paints = count.paints;
    for (final key in [
      'a',
      'enter',
      'up',
      'shift+down',
      'backspace',
      'ctrl+z',
    ]) {
      await t.press(key);
      await t.pump();
    }
    expect(c.text, 'one\ntwoa\n');
    expect(count.paints, paints);
  });

  testTwk('a megabyte pasted is shown and edited in time, the area laying '
      'out the lines in view only', (t) async {
    final c = TextEditingController();
    final key = GlobalKey();
    await t.pumpWidget(
      Theme.terminal(child: area(c, width: 80, maxLines: 20, key: key)),
      size: (80, 24),
    );
    final line = '${'lorem ipsum dolor sit amet, ' * 2}привет 日本語 👋🏽\n';
    final paste = line * (1048576 ~/ line.length);
    final pass = passOver(paste);
    // real time on purpose: what the work costs is what is measured
    final watch = Stopwatch()..start();
    await t.paste(paste);
    await t.pump();
    final pasted = watch.elapsedMicroseconds;
    expect(c.text.length, paste.length);
    expect(t, cursorAt(0, 19));
    watch.reset();
    final joins = TextBuffer.joins;
    for (final k in [
      'x',
      'up',
      'backspace',
      'pageup',
      'ctrl+home',
      'y',
      'down',
      'ctrl+end',
      'ctrl+z',
    ]) {
      await t.press(k);
      await t.pump();
    }
    final keys = watch.elapsedMicroseconds;
    expect(TextBuffer.joins, joins, reason: 'the text put together');
    final last = paste.length - line.length;
    expect(c.text, '${paste.replaceRange(last, last + 1, '')}x');
    // generous: the paste and its frame took 3.5 to 6 passes over the
    // text, idle and under load; a keystroke and its frame a tenth to a
    // fifth of one on average, none of them going over the text whole
    expect(pasted / pass, lessThan(25), reason: 'paste and its frame');
    expect(keys / 9 / pass, lessThan(1), reason: 'a keystroke and its frame');
    final description = key.currentContext!
        .findRenderObject()!
        .describe()
        .toStringDeep();
    final kept = int.parse(
      RegExp(r'rows kept: (\d+)').firstMatch(description)!.group(1)!,
    );
    expect(kept, lessThan(50));
  });

  testTwk('a line of a megabyte is edited in time, a keystroke breaking '
      'into rows again the rows by it only', (t) async {
    const word = 'lorem ipsum dolor sit amet, привет 日本語 👋🏽 ';
    final line = word * (1048576 ~/ word.length);
    final middle = line.length ~/ 2 - line.length ~/ 2 % word.length;
    final c = TextEditingController(text: line)..moveCaret(middle);
    await t.pumpWidget(
      Theme.terminal(child: area(c, width: 80, maxLines: 20)),
      size: (80, 24),
    );
    final pass = passOver(line);
    final joins = TextBuffer.joins;
    // real time on purpose: what the work costs is what is measured
    final watch = Stopwatch()..start();
    for (final k in [
      'x',
      'y',
      'backspace',
      'left',
      'right',
      'down',
      'up',
      'ctrl+z',
    ]) {
      await t.press(k);
      await t.pump();
    }
    final keys = watch.elapsedMicroseconds;
    expect(TextBuffer.joins, joins, reason: 'the text put together');
    // generous: a keystroke and its frame took a tenth to a fifth of a
    // pass over the text on average, idle and under load
    expect(keys / 8 / pass, lessThan(1), reason: 'a keystroke and its frame');
    expect(c.selection, TextSelection.collapsed(offset: middle + 2));
    expect(c.text, line.replaceRange(middle, middle, 'xy'));
    expect(t.lines.where((l) => l.contains('xylorem')), hasLength(1));
  });

  testTwk('shows the cursor in its cursorShape, and rebuilt with another '
      'in that one', (t) async {
    final c = TextEditingController(text: 'ab\ncd');
    Widget area(CursorShape shape) =>
        TextArea(controller: c, autofocus: true, cursorShape: shape);
    await t.pumpWidget(
      Theme.terminal(child: area(CursorShape.underline)),
      size: (10, 2),
    );
    expect(t, cursorAt(2, 1));
    expect(t.vt.cursorShape, CursorShape.underline.code);
    await t.pumpWidget(Theme.terminal(child: area(CursorShape.blinkingBlock)));
    expect(t.vt.cursorShape, CursorShape.blinkingBlock.code);
  });
}
