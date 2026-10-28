// Where a caret stops: characters as grapheme clusters across scripts and
// emoji, words of letters, of punctuation and apart by blanks; and the
// controller's value kept within its text, edits that replace the
// selection and end the composing, caret moves that select; undo and redo
// by steps, typing and deleting a word at a time; an edit of a megabyte
// of text in time, its text not put together until asked for.
import 'package:test/test.dart';
import 'package:twk/src/editing/text_buffer.dart' show TextBuffer;
import 'package:twk/twk.dart';

/// Every offset the caret stops at going right from the start of [text].
List<int> stopsRight(String text, int Function(String, int) next) {
  final stops = [0];
  while (stops.last < text.length) {
    stops.add(next(text, stops.last));
  }
  return stops;
}

/// Every offset the caret stops at going left from the end of [text].
List<int> stopsLeft(String text, int Function(String, int) previous) {
  final stops = [text.length];
  while (stops.last > 0) {
    stops.add(previous(text, stops.last));
  }
  return stops;
}

void main() {
  group('TextBoundaries', () {
    // e and a combining acute, a Cyrillic letter, a CJK ideograph, a
    // family of three joined by ZWJ, a flag, a hand with a skin tone
    const mixed = 'éя日👨‍👩‍👧🇺🇦👋🏽!';

    test('counts and steps over characters: grapheme clusters, whatever '
        'their code points and code units', () {
      expect(mixed.characterCount, 7);
      expect(stopsRight(mixed, (t, o) => t.characterEndAfter(o)), [
        0,
        2,
        3,
        4,
        12,
        16,
        20,
        21,
      ]);
      expect(
        stopsLeft(mixed, (t, o) => t.characterStartBefore(o)),
        [21, 20, 16, 12, 4, 3, 2, 0],
      );
      expect(
        [for (var i = 0; i <= 7; i++) mixed.characterOffset(i)],
        [0, 2, 3, 4, 12, 16, 20, 21],
      );
      expect(mixed.characterIndexAt(12), 4);
    });

    test('takes an offset inside a character as its start', () {
      // inside the family
      expect(mixed.characterStartBefore(6), 4);
      expect(mixed.characterEndAfter(6), 12);
      expect(mixed.characterIndexAt(6), 3);
    });

    test('stops at the ends of the text', () {
      expect('ab'.characterStartBefore(0), 0);
      expect('ab'.characterEndAfter(2), 2);
      expect(''.characterCount, 0);
      expect(''.characterEndAfter(0), 0);
      expect(''.wordStartBefore(0), 0);
      expect(''.wordEndAfter(0), 0);
    });

    test('a word is a run of letters, digits, marks and emoji, or a run of '
        'punctuation, the blanks before it passed over', () {
      const text = 'foo.bar  héllo_2 —— мир 日本 👋🏽x';
      expect(
        stopsRight(text, (t, o) => t.wordEndAfter(o)),
        [0, 3, 4, 7, 16, 19, 23, 26, 32],
      );
      expect(
        stopsLeft(text, (t, o) => t.wordStartBefore(o)),
        [32, 27, 24, 20, 17, 9, 4, 3, 0],
      );
    });

    test('apart by blanks, a word is what lies between them', () {
      const text = 'git  commit -m "fix it"';
      expect(
        stopsLeft(
          text,
          (t, o) => t.wordStartBefore(o, blankDelimited: true),
        ),
        [23, 20, 15, 12, 5, 0],
      );
      expect(
        stopsRight(text, (t, o) => t.wordEndAfter(o, blankDelimited: true)),
        [0, 3, 11, 14, 19, 23],
      );
    });
  });

  group('TextEditingController', () {
    test('starts with the caret at the end of its text, and puts it there '
        'when the text is set', () {
      final c = TextEditingController(text: 'abc');
      expect(c.selection, const TextSelection.collapsed(offset: 3));
      c.text = 'hello';
      expect(
        c.value,
        const TextEditingValue(
          text: 'hello',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      c.clear();
      expect(c.value, TextEditingValue.empty);
    });

    test('keeps a value within its text: offsets past its end at it, a '
        'composing range that does not fit dropped', () {
      final c = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'ab',
          selection: TextSelection(baseOffset: 9, extentOffset: 1),
          composing: TextRange(start: 1, end: 5),
        ),
      );
      expect(c.selection, const TextSelection(baseOffset: 2, extentOffset: 1));
      expect(c.composing, TextRange.empty);
      c.selection = const TextSelection.collapsed(offset: 7);
      expect(c.selection.extentOffset, 2);
    });

    test('puts text in place of the selection, the caret after it, and '
        'ends the composing', () {
      final c = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'hello world',
          selection: TextSelection(baseOffset: 6, extentOffset: 11),
          composing: TextRange(start: 0, end: 5),
        ),
      )..insert('мир');
      expect(
        c.value,
        const TextEditingValue(
          text: 'hello мир',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      c.replace(0, 5, 'bye');
      expect(c.text, 'bye мир');
      expect(c.selection.extentOffset, 3);
    });

    test('a replacement by the same text moves the caret after it, and is '
        'no step to undo', () {
      final c = TextEditingController(text: 'hello world')
        ..moveCaret(0)
        ..replace(6, 11, 'world');
      expect(c.text, 'hello world');
      expect(c.selection, const TextSelection.collapsed(offset: 11));
      expect(c.canUndo, isFalse);
    });

    test('moves the caret, or with extend grows and shrinks the selection '
        'from its base', () {
      final c = TextEditingController(text: 'abcdef')
        ..moveCaret(2)
        ..moveCaret(4, extend: true);
      expect(c.selection, const TextSelection(baseOffset: 2, extentOffset: 4));
      c.moveCaret(0, extend: true);
      expect(c.selection, const TextSelection(baseOffset: 2, extentOffset: 0));
      expect(c.selection.start, 0);
      expect(c.selection.end, 2);
      c.moveCaret(5);
      expect(c.selection, const TextSelection.collapsed(offset: 5));
      c.selectAll();
      expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 6));
    });

    test('deletes the selection, else from the caret to an offset on '
        'either side', () {
      final c = TextEditingController(text: 'abcdef')
        ..moveCaret(3)
        ..deleteTo(1);
      expect(
        c.value,
        const TextEditingValue(
          text: 'adef',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      c.deleteTo(3);
      expect(c.text, 'af');
      c
        ..text = 'abcdef'
        ..selection = const TextSelection(baseOffset: 4, extentOffset: 1)
        ..deleteTo(6);
      expect(
        c.value,
        const TextEditingValue(
          text: 'aef',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
    });

    test('undo takes back typing a word and the blanks after it at a time, '
        'redo makes it again', () {
      final c = TextEditingController();
      for (final ch in 'hi там\nok'.split('')) {
        c.insert(ch);
      }
      final texts = <String>[];
      while (c.canUndo) {
        c.undo();
        texts.add(c.text);
      }
      expect(texts, ['hi там\n', 'hi ', '']);
      expect(c.selection, const TextSelection.collapsed(offset: 0));
      c
        ..redo()
        ..redo();
      expect(c.value.text, 'hi там\n');
      expect(c.selection, const TextSelection.collapsed(offset: 7));
      expect(c.canRedo, isTrue);
    });

    test('a run of deletions backward or forward is a step a word at a '
        'time; a paste, a deletion of more and a replaced selection one '
        'each', () {
      final c = TextEditingController(text: 'one two three four')
        ..moveCaret(13);
      for (var i = 0; i < 8; i++) {
        c.deleteTo(c.selection.extentOffset - 1);
      }
      expect(c.text, 'one t four');
      c.moveCaret(0);
      for (var i = 0; i < 5; i++) {
        c.deleteTo(1);
      }
      c
        ..moveCaret(c.text.length)
        ..insert(' 😀👍🏽')
        ..deleteTo(c.text.wordStartBefore(c.text.length))
        ..selection = const TextSelection(baseOffset: 0, extentOffset: 1)
        // typing over a selection: the selection is in the step
        ..insert('X')
        ..insert('Y');
      expect(c.text, 'XYfour ');
      final texts = <String>[];
      while (c.canUndo) {
        c.undo();
        texts.add(c.text);
      }
      expect(texts, [
        ' four ',
        ' four 😀👍🏽',
        ' four',
        't four',
        'one t four',
        'one two four',
        'one two three four',
      ]);
    });

    test('moving the caret ends the step typing makes; an edit drops what '
        'was undone', () {
      final c = TextEditingController()
        ..insert('a')
        ..insert('b')
        ..moveCaret(1)
        ..moveCaret(2)
        ..insert('c')
        ..undo();
      expect(c.text, 'ab');
      expect(c.selection, const TextSelection.collapsed(offset: 2));
      c.insert('d');
      expect(c.canRedo, isFalse);
      c
        ..undo()
        ..undo();
      expect(c.text, '');
      expect(c.canUndo, isFalse);
    });

    test('a text set is a step of its own, undone as one, the selection '
        'back as it was', () {
      final c = TextEditingController(text: 'keep this one')
        ..selection = const TextSelection(baseOffset: 5, extentOffset: 9)
        ..text = 'keep that one';
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.text, 'keep this one');
      expect(c.selection, const TextSelection(baseOffset: 5, extentOffset: 9));
      c.redo();
      expect(c.text, 'keep that one');
    });

    test('an undo and a redo end the step being made', () {
      final c = TextEditingController(text: 'abc')
        ..deleteTo(2)
        ..insert('x')
        ..undo()
        ..deleteTo(1)
        ..undo();
      expect(c.text, 'ab');
      c
        ..redo()
        ..deleteTo(0)
        ..undo();
      expect(c.text, 'a');
    });

    test('keeps the last ${TextEditingController.undoLimit} steps', () {
      final c = TextEditingController();
      for (var i = 0; i < TextEditingController.undoLimit + 5; i++) {
        c.insert('w$i ');
      }
      var steps = 0;
      while (c.canUndo) {
        c.undo();
        steps++;
      }
      expect(steps, TextEditingController.undoLimit);
      expect(c.text, startsWith('w0 w1 w2 w3 w4 '));
    });

    test('notifies its listeners of each change, and of nothing else', () {
      var told = 0;
      final c = TextEditingController(text: 'ab')
        ..addListener(() => told++)
        ..moveCaret(2)
        ..deleteTo(2)
        ..text = 'ab';
      expect(told, 0);
      expect(c.canUndo, isFalse, reason: 'the same text set');
      c
        ..moveCaret(1)
        ..insert('x')
        ..deleteTo(0)
        ..composing = const TextRange(start: 0, end: 1);
      expect(told, 4);
    });

    test('a reset puts its text in, the caret at its end, the composing '
        'ended, and is no step to undo: the steps before it are gone, those '
        'undone too; an edit after it is one', () {
      var told = 0;
      final c = TextEditingController(text: 'one')
        ..insert(' two')
        ..insert(' three')
        ..undo()
        ..composing = const TextRange(start: 0, end: 3)
        ..addListener(() => told++)
        ..reset('/home/');
      expect(c.text, '/home/');
      expect(c.selection, const TextSelection.collapsed(offset: 6));
      expect(c.composing, TextRange.empty);
      expect((c.canUndo, c.canRedo), (false, false));
      expect(told, 1);
      c
        ..undo()
        ..redo();
      expect(c.text, '/home/');
      c.insert('x');
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.text, '/home/');
      expect(c.canUndo, isFalse);
      c.reset();
      expect(c.text, '');
      expect(c.canRedo, isFalse);
    });

    test('a reset to the text there tells the listeners only when there was '
        'a step to undo or redo', () {
      var told = 0;
      final c = TextEditingController(text: 'ab')
        ..addListener(() => told++)
        ..reset('ab');
      expect(told, 0);
      c
        ..insert('c')
        ..reset('abc');
      expect(told, 2);
      expect(c.canUndo, isFalse);
      c
        ..insert('d')
        ..undo()
        ..reset('abc');
      expect(told, 5);
      expect(c.canRedo, isFalse);
    });

    test('edits a megabyte of text, of many lines or of one, in time, and '
        'puts its text together only when asked for it', () {
      const word = 'lorem ipsum dolor sit amet, привет 日本語 👋🏽 ';
      for (final unit in ['$word\n', word]) {
        final text = unit * (1048576 ~/ unit.length);
        final middle = text.length ~/ 2 - text.length ~/ 2 % unit.length;
        final c = TextEditingController(text: text)..moveCaret(middle);
        final joins = TextBuffer.joins;
        final times = <int>[];
        // real time on purpose: what the work costs is what is measured
        final watch = Stopwatch()..start();
        // each character typed in place of the one after it
        for (var i = 0; i < 200; i++) {
          watch.reset();
          if (i.isEven) {
            c.insert(i % 10 == 8 ? ' ' : 'x');
          } else {
            c.deleteTo(c.selection.extentOffset + 1);
          }
          times.add(watch.elapsedMicroseconds);
        }
        expect(TextBuffer.joins, joins, reason: 'the text put together');
        times.sort();
        // generous: an edit in a two-thousandth of a second
        expect(times[times.length ~/ 2], lessThan(500), reason: 'an edit');
        final typed = text.replaceRange(middle, middle + 100, 'xxxx ' * 20);
        expect(c.text, typed);
        expect(c.text, same(c.text));
        expect(TextBuffer.joins, joins + 1);
        c.undo();
        expect(c.text, isNot(typed));
      }
    });
  });

  group('the values', () {
    test('a range, a selection and a value are equal to another of the same '
        'offsets and text, with the same hash code', () {
      // not constants, which are one object when equal
      final start = int.parse('2');
      final range = TextRange(start: start, end: 5);
      expect(range, TextRange(start: start, end: 5));
      expect(range.hashCode, TextRange(start: start, end: 5).hashCode);
      expect(range, isNot(TextRange(start: start, end: 4)));
      final selection = TextSelection(baseOffset: start, extentOffset: 5);
      expect(
        selection.hashCode,
        TextSelection(baseOffset: start, extentOffset: 5).hashCode,
      );
      expect(
        selection,
        isNot(const TextSelection(baseOffset: 5, extentOffset: 2)),
      );
      final value = TextEditingValue(text: 'abcdef', selection: selection);
      expect(
        value.hashCode,
        TextEditingValue(text: 'abcdef', selection: selection).hashCode,
      );
      expect(
        value,
        isNot(TextEditingValue(text: 'abcdeg', selection: selection)),
      );
    });

    test('describe their offsets and text', () {
      expect('${const TextRange(start: 2, end: 5)}', 'TextRange(2, 5)');
      const caret = TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect('$caret', 'TextEditingValue("ab", TextSelection.collapsed(1))');
      const composing = TextEditingValue(
        text: 'ab',
        selection: TextSelection(baseOffset: 0, extentOffset: 2),
        composing: TextRange(start: 0, end: 1),
      );
      expect(
        '$composing',
        'TextEditingValue("ab", TextSelection(0, 2), '
            'composing TextRange(0, 1))',
      );
    });
  });
}
