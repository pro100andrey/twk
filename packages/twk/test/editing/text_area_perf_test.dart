// A keystroke repaints the rows of a TextArea it changed and leaves the
// rest as they are on the surface: a character typed its row, a line
// break the rows from it on, a move of the caret none, a selection the
// rows it reaches; and what the area shows is what a whole repaint shows:
// after a change that replaced a row's text from before its start, of
// rows the end of the text left, of a composing range, and after each of
// random edits — soft wrap, wide glyphs, right-to-left lines, selections,
// undo and redo, pastes, scrolls — in logical and in visual order.
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk/src/editing/caret.dart' show TextColumns;
import 'package:twk/src/editing/text_buffer.dart' show TextBuffer;
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show PipelineTextOrder, TextOrder, TextSegmenter;
import 'package:twk_test/twk_test.dart';

/// A focused area of [c], 20 columns wide and 8 rows high, at the top
/// left.
Widget area(
  TextEditingController c, {
  Key? key,
  Style? style,
  Style? selectionStyle,
}) => Align(
  alignment: Alignment.topLeft,
  child: SizedBox(
    width: 20,
    child: TextArea(
      key: key,
      controller: c,
      style: style,
      selectionStyle: selectionStyle,
      autofocus: true,
      minLines: 8,
      maxLines: 8,
    ),
  ),
);

const _width = 20;
const _height = 8;

/// The cells the last frame compared with what the terminal shows: those
/// painted, a row of the area its width.
int compared(TwkTester t) =>
    t.binding.twkApp.screen.presenter.stats.cellsCompared;

/// The cells and the styles of the area on the surface.
(Uint32List, Uint32List) shown(TwkTester t) {
  final s = t.binding.twkApp.screen.surface;
  final cells = Uint32List(_width * _height);
  final styles = Uint32List(_width * _height);
  for (var y = 0; y < _height; y++) {
    cells.setRange(y * _width, (y + 1) * _width, s.cells, y * s.width);
    styles.setRange(y * _width, (y + 1) * _width, s.styles, y * s.width);
  }
  return (cells, styles);
}

/// Expects what the area shows to be what it shows painted again whole.
Future<void> expectWhole(TwkTester t, String reason) async {
  final (cells, styles) = shown(t);
  t.binding.twkApp.owner.markAllDirty();
  await t.pump();
  final (wholeCells, wholeStyles) = shown(t);
  expect(cells, wholeCells, reason: reason);
  expect(styles, wholeStyles, reason: reason);
}

/// What the render object of [key] says it painted last: `none`, or how
/// many rows and from which to which.
String rowsPainted(GlobalKey key) {
  final description = key.currentContext!
      .findRenderObject()!
      .describe()
      .toStringDeep();
  return RegExp(
    'rows painted: "([^"]*)"',
  ).firstMatch(description)!.group(1)!;
}

void main() {
  testTwk('a keystroke repaints the rows it changed and leaves the others '
      'as they are', (t) async {
    final c = TextEditingController(
      text: [for (var i = 0; i < 12; i++) 'line $i of it'].join('\n'),
    );
    // the caret at the end of line 3
    c.moveCaret(c.text.indexOf('\nline 4'));
    final key = GlobalKey();
    // a screen taller than four times the area's rows: the presenter looks
    // for no scroll in a frame that changed only the area's
    await t.pumpWidget(area(c, key: key), size: (30, 40));

    /// The rows the area painted after [keys], and the cells the frame
    /// compared with what the terminal shows.
    Future<(String, int)> after(String keys, {bool typed = false}) async {
      await (typed ? t.type(keys) : t.press(keys));
      await t.pump();
      final description = key.currentContext!
          .findRenderObject()!
          .describe()
          .toStringDeep();
      final painted = RegExp(
        'rows painted: "([^"]*)"',
      ).firstMatch(description)!.group(1)!;
      return (painted, compared(t));
    }

    expect(await after('x'), ('1, 3 to 3', _width), reason: 'a character');
    expect(await after('backspace'), ('1, 3 to 3', _width), reason: 'deleted');
    expect(await after('left'), ('none', 0), reason: 'the caret moved');
    expect(await after('up'), ('none', 0), reason: 'by a row');
    // the caret in line 2: the rows from it on show other lines
    expect((await after('enter')).$1, '2, 2 to 3', reason: 'a line break');
    expect((await after('backspace')).$1, '2, 2 to 7', reason: 'joined');
    expect(
      await after('shift+right'),
      ('1, 2 to 2', _width),
      reason: 'a character selected',
    );
    expect(
      await after('shift+down'),
      ('2, 2 to 3', 2 * _width),
      reason: 'into the next row',
    );
    expect(
      await after('right'),
      ('2, 2 to 3', 2 * _width),
      reason: 'the selection gone',
    );
    expect(await after('shift+left'), ('1, 3 to 3', _width), reason: 'one');
    // the selection's end stays, its start moves
    expect(await after('shift+left'), ('1, 3 to 3', _width), reason: 'two');
    expect(await after('right'), ('1, 3 to 3', _width), reason: 'none');
    // a word that wraps line 3 onto two rows moves the rows after it down:
    // the row it wrapped onto painted
    expect(
      (await after(' wrapped', typed: true)).$1,
      '2, 3 to 4',
      reason: 'a row wrapped',
    );
    // the word undone, the blank before it stays: row 3 shows what it did,
    // the rows after it moved back up, the one that came into view painted
    expect((await after('ctrl+z')).$1, '1, 7 to 7', reason: 'undone');
  });

  testTwk('a key mid-text repaints the rows whose text it changed: a line '
      'break or a join moves the rows below it, what it shows a whole '
      'repaint shows', (t) async {
    final c = TextEditingController(
      text: [for (var i = 0; i < 12; i++) 'line $i of it'].join('\n'),
    );
    // the caret in the middle of line 3
    c.moveCaret(c.text.indexOf('of it\nline 4'));
    final key = GlobalKey();
    // the screen as wide as the area: the terminal scrolls its rows
    await t.pumpWidget(area(c, key: key), size: (_width, 40));

    /// The rows the area painted after [keys] and the cells the frame
    /// compared with what the terminal shows; what the area shows checked
    /// against a whole repaint.
    Future<(String, int)> after(String keys, {bool typed = false}) async {
      await (typed ? t.type(keys) : t.press(keys));
      await t.pump();
      final painted = (rowsPainted(key), compared(t));
      await expectWhole(t, keys);
      return painted;
    }

    expect(
      await after('x', typed: true),
      ('1, 3 to 3', _width),
      reason: 'a character',
    );
    // the line split: its head and its tail painted, the rows below moved
    expect(
      await after('enter'),
      ('2, 3 to 4', 2 * _width),
      reason: 'a line break',
    );
    expect(t.lines[4], 'of it');
    expect(t.lines[7], 'line 6 of it');
    // joined again: the rows below moved back up, the row that came into
    // view at the bottom painted
    expect(
      await after('backspace'),
      ('2, 3 to 7', 2 * _width),
      reason: 'joined',
    );
    expect(t.lines[3], 'line 3 xof it');
    expect(t.lines[7], 'line 7 of it');
    // Delete at the end of a line joins the next to it: the line takes two
    // rows, the rows after them where they were
    await after('end');
    expect(
      await after('delete'),
      ('2, 3 to 4', 2 * _width),
      reason: 'a line break deleted',
    );
    expect(t.lines[3], 'line 3 xof itline 4');
    expect(t.lines[4], 'of it');
    expect(t.lines[5], 'line 5 of it');
    // a word that wraps the line onto another row moves the rows below
    // it down
    await after('ctrl+z');
    expect(
      await after(' wrapped', typed: true),
      ('2, 3 to 4', 2 * _width),
      reason: 'wrapped',
    );
    expect(t.lines[4], 'wrapped');
    expect(t.lines[5], 'line 4 of it');
  });

  testTwk('a scroll moves the rows the area showed and paints those that '
      'came into view only, what it shows a whole repaint shows', (t) async {
    final c = TextEditingController(
      text: [for (var i = 0; i < 30; i++) 'line $i of it'].join('\n'),
    );
    // the caret on the last row in view
    c.moveCaret(c.text.indexOf('\nline 8'));
    final key = GlobalKey();
    await t.pumpWidget(area(c, key: key), size: (30, 40));

    /// The rows the area painted after [keys].
    Future<String> after(String keys) async {
      await t.press(keys);
      await t.pump();
      return rowsPainted(key);
    }

    expect(await after('down'), '1, 7 to 7', reason: 'a row down');
    await expectWhole(t, 'a row down');
    expect(t.lines[0], 'line 1 of it');
    for (var i = 0; i < 7; i++) {
      await after('up');
    }
    expect(await after('up'), '1, 0 to 0', reason: 'a row up');
    await expectWhole(t, 'a row up');
    expect(t.lines[0], 'line 0 of it');
    // a line break on the last row: the rows above it move up, the new
    // line's row painted
    await after('pagedown');
    for (var i = 0; i < 7; i++) {
      await after('down');
    }
    expect(await after('end'), 'none', reason: 'the caret moved');
    expect(await after('enter'), '1, 7 to 7', reason: 'a line at the bottom');
    await expectWhole(t, 'a line at the bottom');
    // a page on: no row in view still; to the end of the text, the rows
    // after the six that came into view moved
    expect(await after('pagedown'), '8, 0 to 7', reason: 'a page');
    await expectWhole(t, 'a page');
    expect(await after('ctrl+end'), '6, 2 to 7', reason: 'six rows on');
    await expectWhole(t, 'six rows on');
    expect(t.lines[7], 'line 29 of it');
    // a selection scrolled up a row, the caret at the end of the row: the
    // row it brought into view painted and the one it selected all of, the
    // others selected as they were
    expect(await after('shift+pageup'), '8, 0 to 7', reason: 'selected');
    for (var i = 0; i < 7; i++) {
      await after('shift+up');
    }
    expect(await after('shift+up'), '2, 0 to 1', reason: 'selected a row up');
    await expectWhole(t, 'selected a row up');
    // and back down: the row that left it selected no more
    expect(await after('down'), '8, 0 to 7', reason: 'the selection gone');
    expect(await after('ctrl+home'), '8, 0 to 7', reason: 'the start');
    await expectWhole(t, 'the start');
  });

  testTwk('a change in a text of many lines puts the text together for '
      'onChanged only: for onEdited when it reads it, once', (t) async {
    final text = [for (var i = 0; i < 10000; i++) 'line $i of it'].join('\n');
    final c = TextEditingController(text: text)..moveCaret(text.length ~/ 2);
    final told = <String>[];
    final edited = <TextEditingValue>[];
    Widget app({bool changed = false, bool edits = false}) => TextArea(
      controller: c,
      autofocus: true,
      minLines: 8,
      maxLines: 8,
      onChanged: changed ? told.add : null,
      onEdited: edits ? edited.add : null,
    );

    /// How many times a text was put together for five keys typed.
    Future<int> joins() async {
      final before = TextBuffer.joins;
      await t.type('hello');
      await t.pump();
      return TextBuffer.joins - before;
    }

    await t.pumpWidget(app(), size: (30, 10));
    expect(await joins(), 0, reason: 'nobody told');
    await t.pumpWidget(app(edits: true), size: (30, 10));
    expect(await joins(), 0, reason: 'onEdited');
    expect(edited, hasLength(5));
    expect(edited.last, c.value);
    // its text, put together as it is read, once
    final joined = TextBuffer.joins;
    expect(edited.last.text, c.text);
    expect(edited.last.text, endsWith(text.substring(text.length ~/ 2)));
    expect(TextBuffer.joins - joined, 1);
    await t.pumpWidget(app(changed: true, edits: true), size: (30, 10));
    edited.clear();
    expect(await joins(), 5, reason: 'onChanged, after each key');
    expect(told, [for (final v in edited) v.text]);
  });

  testTwk('a row a change replaced from before its start, the rows after '
      'the end of the text, a composing range: each shown as a whole repaint '
      'shows it', (t) async {
    final c = TextEditingController(
      text: [for (var i = 0; i < 5; i++) 'line $i of it'].join('\n'),
    );
    await t.pumpWidget(area(c), size: (30, 40));
    // the line break and the first character of line 3 replaced by as
    // many, nothing selected: line 3's row starts and ends where it did
    final start = c.text.indexOf('\nline 3');
    c.replace(start, start + 2, '\nX');
    await t.pump();
    expect(c.text.split('\n')[3], 'Xine 3 of it');
    await expectWhole(t, 'a row replaced from before it');
    // the last line deleted: its row blank again
    c.selection = TextSelection(
      baseOffset: c.text.indexOf('\nline 4'),
      extentOffset: c.text.length,
    );
    await t.pump();
    await t.press('backspace');
    await t.pump();
    expect(c.text.split('\n'), hasLength(4));
    await expectWhole(t, 'the last line deleted');
    // a composing range, then none
    c.value = c.value.copyWith(composing: const TextRange(start: 2, end: 6));
    await t.pump();
    await expectWhole(t, 'composing');
    c.value = c.value.copyWith(composing: const TextRange(start: 3, end: 6));
    await t.pump();
    await expectWhole(t, 'composing less');
    c.value = c.value.copyWith(composing: const TextRange(start: 3, end: 9));
    await t.pump();
    await expectWhole(t, 'composing more');
    c.value = c.value.copyWith(composing: TextRange.empty);
    await t.pump();
    await expectWhole(t, 'composed');
    // the styles changed, part of the text selected
    c.selection = const TextSelection(baseOffset: 2, extentOffset: 20);
    await t.pump();
    await t.pumpWidget(
      area(c, selectionStyle: const Style(attrs: Attr.bold)),
      size: (30, 40),
    );
    await expectWhole(t, 'another selection style');
    await t.pumpWidget(
      area(
        c,
        style: const Style(attrs: Attr.italic),
        selectionStyle: const Style(attrs: Attr.bold),
      ),
      size: (30, 40),
    );
    await expectWhole(t, 'another style');
    // in visual order, a line of rows that runs the other way once its
    // first strong character does: its rows after the first show the same
    // text, drawn the other way
    t.binding.twkApp.owner.textOrder = TextOrder.visual;
    c.text = 'top\na ${'שלום עולם ' * 5}1 2\nend';
    await t.pump();
    await expectWhole(t, 'in visual order');
    c.replace(4, 5, 'ש');
    await t.pump();
    await expectWhole(t, 'the line right to left');
  });

  for (final order in TextOrder.values) {
    testTwk('what it shows after each of random edits is what a whole '
        'repaint shows, in ${order.name} order', (t) async {
      final r = Random(order.index + 7);
      final c = TextEditingController(
        text: [
          'plain words that wrap onto rows',
          '日本語のテキストと wide 한국어',
          'שלום עולם and some מילים',
          'emoji 👋🏽 and 👨‍👩‍👧 flags 🇺🇦',
          '',
          'a\tb\tc',
          'last',
        ].join('\n'),
      )..moveCaret(10);
      await t.pumpWidget(area(c), size: (30, 10));
      t.binding.twkApp.owner.textOrder = order;
      await t.pump();
      const keys = [
        'left', 'right', 'up', 'down', 'home', 'end', 'pageup', 'pagedown', //
        'shift+left', 'shift+right', 'shift+down', 'shift+up', //
        'backspace', 'delete', 'enter', 'ctrl+z', 'ctrl+y', 'ctrl+home', //
        'ctrl+end', 'space',
      ];
      const typed = ['x', '日', 'ש', 'é', 'wide 語 word ', '👋🏽'];
      for (var step = 0; step < 300; step++) {
        final what = r.nextInt(10);
        if (what < 6) {
          await t.press(keys[r.nextInt(keys.length)]);
        } else if (what < 8) {
          await t.type(typed[r.nextInt(typed.length)]);
        } else if (what < 9) {
          await t.paste(r.nextBool() ? '\nX' : 'pasted\nלא ${r.nextInt(9)}\n');
        } else {
          // a word or two selected, or deleted
          for (var i = r.nextInt(4); i >= 0; i--) {
            await t.press(r.nextBool() ? 'shift+ctrl+left' : 'shift+right');
          }
          if (r.nextBool()) {
            await t.press('backspace');
          }
        }
        await t.pump();
        await expectWhole(
          t,
          'step $step, ${c.text.length} long, at ${c.selection}',
        );
      }
    });
  }

  testTwk('as wide as its widest line after each of random edits, the lines '
      'an edit did not reach measured before', (t) async {
    final r = Random(3);
    final c = TextEditingController(
      text: [for (var i = 0; i < 30; i++) 'line $i ${'·' * (i % 7)}']
          .join('\n'),
    );
    final key = GlobalKey();
    await t.pumpWidget(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicWidth(
            child: TextArea(
              key: key,
              controller: c,
              autofocus: true,
              maxLines: 8,
            ),
          ),
          const Text('|'),
        ],
      ),
      size: (200, 10),
    );
    final columns = TextColumns(TextSegmenter());
    const keys = ['up', 'down', 'left', 'right', 'home', 'end', 'backspace'];
    const typed = ['x', '日本', 'wide word ', '\n', '👋🏽', 'é'];
    for (var step = 0; step < 300; step++) {
      if (r.nextBool()) {
        await t.press(keys[r.nextInt(keys.length)]);
      } else if (r.nextInt(8) > 0) {
        await t.type(typed[r.nextInt(typed.length)]);
      } else {
        await t.paste(r.nextBool() ? '\n${'a' * r.nextInt(50)}\n' : '');
      }
      await t.pump();
      var widest = 0;
      for (final line in c.text.split('\n')) {
        columns.measure(line);
        widest = max(widest, columns.width);
      }
      expect(
        key.currentContext!.findRenderObject()!.width,
        min(widest + 1, 200),
        reason: 'step $step',
      );
    }
  });

  for (final (name, under) in [
    (
      'in a dialog',
      (Widget child) => Box(
        style: const Style(bg: Color.rgb(0x22, 0x25, 0x2c)),
        child: child,
      ),
    ),
    (
      'on a gradient down it, whose rows are not alike',
      (Widget child) => GradientBackground(
        gradient: const Gradient(
          [Color.rgb(0, 0, 96), Color.rgb(0, 96, 0)],
          direction: Axis.vertical,
        ),
        child: child,
      ),
    ),
  ]) {
    testTwk('$name: over what is under it, typed, broken, scrolled and '
        'selected, as a whole repaint shows it', (t) async {
      final c = TextEditingController(
        text: [for (var i = 0; i < 30; i++) 'line $i of it'].join('\n'),
      );
      // what is under it four columns wider than it, which show it beside
      Widget tree() => Align(
        alignment: Alignment.topLeft,
        child: under(
          SizedBox(
            width: _width + 4,
            height: _height,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: _width,
                child: TextArea(
                  controller: c,
                  autofocus: true,
                  minLines: _height,
                  maxLines: _height,
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpWidget(tree(), size: (30, 10));
      final under0 = [
        for (var y = 0; y < _height; y++) t.cell(_width + 2, y).bg,
      ];
      for (final keys in [
        'x',
        'enter',
        'down down down',
        'pagedown',
        'ctrl+end',
        'enter enter',
        'shift+up shift+up',
        'backspace',
        'ctrl+home',
        'pageup',
      ]) {
        for (final k in keys.split(' ')) {
          await t.press(k);
        }
        await t.pump();
        await expectWhole(t, keys);
        // the area's last column, a blank on every row of this text
        for (var y = 0; y < _height; y++) {
          expect(t.cell(_width - 1, y).bg, under0[y], reason: '$keys, row $y');
        }
      }
    });
  }
}
