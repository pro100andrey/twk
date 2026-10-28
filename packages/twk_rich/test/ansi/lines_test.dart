// How text, line endings, carriage returns, backspaces, tabs and erasing
// in the line write the lines, as a terminal would show them.
import 'package:test/test.dart';
import 'package:twk/twk.dart' show Span, Style;
import 'package:twk_core/twk_core.dart' show Color;
import 'package:twk_rich/twk_rich.dart';

/// The text of the lines of [text], one string per line.
List<String> plain(String text, {int tabWidth = 8}) => [
  for (final line in parseAnsi(text, tabWidth: tabWidth))
    line.map((span) => span.text).join(),
];

void main() {
  group('line endings', () {
    test('no text is no line', () => expect(parseAnsi(''), isEmpty));

    test('a line feed ends a line', () {
      expect(plain('a\nb'), ['a', 'b']);
      expect(plain('a\n'), ['a']);
      expect(plain('a\n\nb\n'), ['a', '', 'b']);
      expect(parseAnsi('\n'), [<Span>[]]);
    });

    test('CR LF ends a line', () {
      expect(plain('a\r\nb\r\n'), ['a', 'b']);
    });

    test('a vertical tab and a form feed end a line', () {
      expect(plain('a\x0Bb\x0Cc'), ['a', 'b', 'c']);
    });
  });

  group('carriage return', () {
    test('text after it writes over the line', () {
      expect(plain('10%\r50%\r100%\n'), ['100%']);
      expect(plain('100%\r50%'), ['50%%']);
    });

    test('alone at the end it leaves the line', () {
      expect(plain('Receiving objects:  45%\r'), ['Receiving objects:  45%']);
    });

    test('text written over takes its own style', () {
      expect(parseAnsi('\x1B[31mred\x1B[m\rB'), [
        [const Span('B'), const Span('ed', Style(fg: Color.red))],
      ]);
    });
  });

  group('erase in line', () {
    test('from the cursor to the end', () {
      expect(plain('downloading\rdone\x1B[K\n'), ['done']);
      expect(plain('downloading\rdone\x1B[0K'), ['done']);
      expect(plain('abc\x1B[K'), ['abc']);
    });

    test('from the start to the cursor', () {
      expect(plain('abcdef\b\b\b\x1B[1K'), ['    ef']);
    });

    test('the whole line', () {
      expect(plain('abc\x1B[2Kd'), ['   d']);
      expect(plain('abc\r\x1B[2K'), isEmpty);
      expect(plain('abc\r\x1B[2K\nd'), ['', 'd']);
    });

    test('of other kinds or with a marker is ignored', () {
      expect(plain('abc\r\x1B[3K\x1B[?2K\x1B[2;1K'), ['abc']);
    });
  });

  group('backspace', () {
    test('moves back a column', () {
      expect(plain('ab\bc'), ['ac']);
      expect(plain('|\b/\b-\b\\'), [r'\']);
    });

    test('stops at the start of the line', () {
      expect(plain('\b\bab'), ['ab']);
    });
  });

  group('tabs', () {
    test('move to the next stop', () {
      expect(plain('a\tb'), ['a       b']);
      expect(plain('abcdefgh\tb'), ['abcdefgh        b']);
      expect(plain('\t\tb'), ['                b']);
    });

    test('stop where the tab width says', () {
      expect(plain('a\tb', tabWidth: 4), ['a   b']);
      expect(plain('a\tb', tabWidth: 1), ['a b']);
    });

    test('count a wide character as two columns', () {
      expect(plain('漢字\tb'), ['漢字    b']);
    });

    test('leave the columns they move over unstyled', () {
      expect(parseAnsi('\x1B[41ma\tb'), [
        [
          const Span('a', Style(bg: Color.red)),
          const Span('       '),
          const Span('b', Style(bg: Color.red)),
        ],
      ]);
    });

    test('at the end of a line add nothing', () {
      expect(plain('a\t\n\t'), ['a']);
    });

    test('move over text without erasing it', () {
      expect(plain('abcdefghij\r\tX'), ['abcdefghXj']);
    });
  });

  group('wide characters', () {
    test('written over take both their columns', () {
      expect(plain('漢字\rab'), ['ab字']);
    });

    test('cut in two leave a blank', () {
      expect(plain('漢字\rx'), ['x 字']);
      expect(plain('a漢字\rxy'), ['xy 字']);
      expect(plain('ab字\r漢'), ['漢字']);
      expect(plain('a漢\rb字'), ['b字']);
    });

    test('erased in part leave a blank', () {
      expect(plain('漢字\b\x1B[K'), ['漢 ']);
      expect(plain('漢字\r\x1B[1K'), ['  字']);
    });
  });

  test('a combining mark joins the character before it', () {
    expect(plain('e\u0301x\rab'), ['ab']);
    expect(plain('e\x1B[1m\u0301'), ['e\u0301']);
    expect(plain('漢\x1B[1m\u0301'), ['漢\u0301']);
    expect(plain('\u0301e'), ['e']);
  });

  test('a byte order mark at the start is dropped', () {
    expect(plain('\uFEFFa'), ['a']);
  });
}
