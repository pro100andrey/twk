import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_term/twk_term.dart';

import 'support.dart';

void main() {
  group('printing', () {
    test('text goes where the cursor is and moves it', () {
      final r = fed('abc');
      expect(r.rows, ['abc', '', '', '']);
      expect(r.cursor, (3, 0));
    });

    test('a character in the last column leaves a wrap pending', () {
      final r = fed('0123456789');
      expect(r.cursor, (9, 0));
      expect(r.t.wrapPending, isTrue);
      r.feed('x');
      expect(r.rows, ['0123456789', 'x', '', '']);
      expect(r.t.line(0).wrapped, isTrue);
      expect(r.cursor, (1, 1));
    });

    test('CR with a wrap pending stays on the row', () {
      final r = fed('0123456789\rX');
      expect(r.rows.first, 'X123456789');
      expect(r.cursor, (1, 0));
    });

    test('without autowrap the last column is overwritten', () {
      final r = fed(r'\e[?7l0123456789abc');
      expect(r.rows, ['012345678c', '', '', '']);
      expect(r.cursor, (9, 0));
      r.feed('é');
      expect(r.rows.first, '012345678é');
    });

    test('wrapping at the bottom scrolls into the scrollback', () {
      final r = fed('aaaaabbbbbccccc', width: 5, height: 2);
      expect(r.history, ['aaaaa']);
      expect(r.rows, ['bbbbb', 'ccccc']);
    });

    test('LF keeps the column, CR returns, LNM makes LF do both', () {
      expect(fed('ab\ncd').rows.take(2), ['ab', '  cd']);
      expect(fed('ab\r\ncd').rows.take(2), ['ab', 'cd']);
      expect(
        fed(
          r'\e[20hab'
          '\ncd',
        ).rows.take(2),
        ['ab', 'cd'],
      );
    });

    test('BS moves left, also from a pending wrap, and stops at 0', () {
      expect(fed('abc\b\bX').rows.first, 'aXc');
      expect(fed('0123456789\bX').rows.first, '01234567X9');
      final r = fed('\b\bX');
      expect(r.rows.first, 'X');
    });

    test('REP repeats the last character', () {
      expect(fed(r'ab\e[3b').rows.first, 'abbbb');
      expect(fed(r'中\e[2b').rows.first, '中中中');
    });

    test('C1 characters and lone controls print nothing', () {
      final r = fed('a\u0085b\x00\x7fc');
      expect(r.rows.first, 'abc');
    });
  });

  group('tabs', () {
    test('HT goes to the next stop, the last column at most', () {
      final r = fed('a\tb', width: 20);
      expect(r.rows.first, 'a       b');
      r.feed('\t\t\tc');
      expect(r.cursor, (19, 0));
    });

    test('HTS sets a stop, TBC clears one or all', () {
      final r = fed(
        r'\e[3g\e[4G\eH'
        '\r\tX',
        width: 20,
      );
      expect(r.rows.first, '   X');
      r.feed(
        r'\e[4G\e[g'
        '\r\tY',
      );
      expect(r.cursor, (19, 0));
    });

    test('CHT and CBT go several stops', () {
      final r = fed(r'\e[2I', width: 30);
      expect(r.cursor, (16, 0));
      r.feed(r'\e[Z');
      expect(r.cursor, (8, 0));
      r.feed(r'\e[5Z');
      expect(r.cursor, (0, 0));
    });
  });

  group('wide and combining characters', () {
    test('a wide character takes two cells', () {
      final r = fed('中a');
      expect(r.t.cellAt(0, 0) & kWide, kWide);
      expect(r.t.cellAt(1, 0) & kCont, kCont);
      expect(r.t.cellText(2, 0), 'a');
      expect(r.cursor, (3, 0));
    });

    test('one that does not fit in the last column wraps whole', () {
      final r = fed('abcd中', width: 5);
      expect(r.rows.take(2), ['abcd', '中']);
      expect(r.t.line(0).wrapped, isTrue);
      expect(r.cursor, (2, 1));
    });

    test('overwriting either half blanks the other', () {
      expect(fed(r'中\e[2Gx').rows.first, ' x');
      expect(fed(r'中\e[1Gx').rows.first, 'x');
      expect(fed(r'ab中\e[1G1234').rows.first, '1234');
      expect(fed(r'中文\e[2G\e[1X').rows.first, '  文');
    });

    test('a combining mark joins the character before it', () {
      final r = fed('e\u0301x');
      expect(r.t.cellText(0, 0), 'e\u0301');
      expect(r.t.cellText(1, 0), 'x');
    });

    test('also when it comes in a later write', () {
      final r = fed('e')..feed('\u0301');
      expect(r.t.cellText(0, 0), 'e\u0301');
      expect(r.cursor, (1, 0));
      final wrapped = fed('abc', width: 3)..feed('\u0308');
      expect(wrapped.t.cellText(2, 0), 'c\u0308');
      expect(wrapped.t.wrapPending, isTrue);
    });

    test('a character split between writes', () {
      final r = Rig();
      r.t
        ..feed([0xE4])
        ..feed([0xB8, 0xAD]);
      expect(r.rows.first, '中');
    });

    test('malformed UTF-8 prints U+FFFD', () {
      final r = Rig();
      r.t.feed([0x61, 0xFF, 0x62, 0xE4, 0xB8, 0x63, 0xC0, 0xAF]);
      expect(r.rows.first, 'a\uFFFDb\uFFFDc\uFFFD');
    });

    test('code point by code point by default, as wcwidth', () {
      final r = fed('\u2764\uFE0F|👨\u200D👩|');
      expect(r.t.cellText(0, 0), '\u2764\uFE0F');
      expect(r.t.cellText(1, 0), '|');
      expect(r.t.cellText(2, 0), '👨\u200D');
      expect(r.t.cellText(4, 0), '👩');
      expect(r.cursor, (7, 0));
    });

    test('grapheme clusters with mode 2027', () {
      final r = fed(
        r'\e[?2027h'
        '\u2764\uFE0F|👨\u200D👩\u200D👧|',
        width: 12,
      );
      expect(r.t.cellText(0, 0), '\u2764\uFE0F');
      expect(r.t.cellAt(0, 0) & kWide, kWide);
      expect(r.t.cellText(2, 0), '|');
      expect(r.t.cellText(3, 0), '👨\u200D👩\u200D👧');
      expect(r.cursor, (6, 0));
      r.feed(r'\e[?2027$p');
      expect(r.takeSent(), r'\e[?2027;1$y');
      expect(r.t.segmenter.mode, TextMode.graphemes);
    });

    test('a cluster arriving in pieces is one cell', () {
      final r = fed('👨\u200D', mode: TextMode.graphemes)..feed('👩');
      expect(r.t.cellText(0, 0), '👨\u200D👩');
      expect(r.cursor, (2, 0));
      // a VS16 widens the character before it
      r
        ..feed('\u2764')
        ..feed('\uFE0Fx');
      expect(r.t.cellText(2, 0), '\u2764\uFE0F');
      expect(r.t.cellAt(2, 0) & kWide, kWide);
      expect(r.t.cellText(4, 0), 'x');
    });
  });

  group('cursor', () {
    test('CUP and HVP, clamped to the screen', () {
      final r = fed(r'\e[2;3HX\e[HY\e[99;99fZ');
      expect(r.rows, ['Y', '  X', '', '         Z']);
    });

    test('relative moves stop at the edges', () {
      final r = fed(r'\e[2;5H');
      expect((r..feed(r'\e[9A')).cursor, (4, 0));
      expect((r..feed(r'\e[2B')).cursor, (4, 2));
      expect((r..feed(r'\e[3C')).cursor, (7, 2));
      expect((r..feed(r'\e[20D')).cursor, (0, 2));
      expect((r..feed(r'\e[5G')).cursor, (4, 2));
      expect((r..feed(r'\e[A\e[2a')).cursor, (6, 1));
      expect((r..feed(r'\e[E')).cursor, (0, 2));
      expect((r..feed(r'\e[3C\e[2F')).cursor, (0, 0));
      expect((r..feed(r'\e[3d\e[e')).cursor, (0, 3));
      expect((r..feed(r'\e[4`')).cursor, (3, 3));
    });

    test('CUU and CUD stop at the margins from inside them', () {
      final r = fed(r'\e[2;4r\e[3;1H\e[5A', height: 6);
      expect(r.cursor, (0, 1));
      r.feed(r'\e[9B');
      expect(r.cursor, (0, 3));
      r.feed(r'\e[1;1H\e[9B');
      expect(r.cursor, (0, 3));
      r.feed(r'\e[6;1H\e[9A');
      expect(r.cursor, (0, 1));
    });

    test('origin mode counts rows from the top margin', () {
      final r = fed(r'\e[2;4r\e[?6h\e[1;1HX\e[9;1HY', height: 6);
      expect(r.rows, ['', 'X', '', 'Y', '', '']);
      r.feed(r'\e[6n');
      expect(r.takeSent(), r'\e[3;2R');
      r.feed(r'\e[?6l');
      expect(r.cursor, (0, 0));
    });

    test('DECSC and DECRC keep the position and the attributes', () {
      final r = fed(r'\e[31m\e[2;3H\e7\e[0m\e[H\e8X');
      expect(r.rows[1], '  X');
      expect(r.fg(2, 1), Color.red);
      r.feed(r'\e[3;4H\e[s\e[H\e[uY');
      expect(r.rows[2], '   Y');
    });

    test('DECRC without a DECSC goes home', () {
      expect(fed(r'\e[3;3H\e8X').rows.first, 'X');
    });
  });

  group('erasing', () {
    test('EL to the end, to the start and whole, in the background', () {
      final r = fed(r'abcdefghij\e[5G\e[41m\e[K');
      expect(r.rows.first, 'abcd');
      expect(r.bg(3, 0), Color.defaultColor);
      expect(r.bg(4, 0), Color.red);
      expect(r.bg(9, 0), Color.red);
      expect(r.attrs(9, 0), 0);
      expect(fed(r'abcdefghij\e[5G\e[1K').rows.first, '     fghij');
      expect(fed(r'abcdefghij\e[5G\e[2K').rows.first, '');
    });

    test('ED below, above, all, and the scrollback', () {
      Rig rig() => fed('aaa\r\nbbb\r\nccc\r\nddd\x1b[2;2H');
      expect((rig()..feed(r'\e[J')).rows, ['aaa', 'b', '', '']);
      expect((rig()..feed(r'\e[1J')).rows, ['', '  b', 'ccc', 'ddd']);
      expect((rig()..feed(r'\e[2J')).rows, ['', '', '', '']);
      expect((rig()..feed(r'\e[2J')).cursor, (1, 1));
      final r = fed('1\r\n2\r\n3', height: 2);
      expect(r.history, ['1']);
      r.feed(r'\e[3J');
      expect(r.history, isEmpty);
      expect(r.rows, ['2', '3']);
    });

    test('ECH erases in place', () {
      expect(fed(r'abcdef\e[2G\e[3X').rows.first, 'a   ef');
      expect(fed(r'abcdef\e[2G\e[99X').rows.first, 'a');
    });

    test('an erase of the text after the cursor ends a wrapped line', () {
      final r = fed('abcd', width: 3);
      expect(r.t.line(0).wrapped, isTrue);
      r.feed(r'\e[1;2H\e[K');
      expect(r.t.line(0).wrapped, isFalse);
    });

    test('an erase that ends inside a wide character blanks it whole', () {
      final r = fed(r'中文\e[1G\e[X');
      expect(r.rows.first, '  文');
      expect(r.t.cellText(1, 0), ' ');
    });

    test('DECALN fills the screen with E', () {
      final r = fed(r'\e[2;2r\e[2;2H\e#8', width: 3, height: 2);
      expect(r.rows, ['EEE', 'EEE']);
      expect(r.cursor, (0, 0));
      expect(r.t.margins, (0, 2));
    });
  });

  group('editing', () {
    test('ICH inserts blanks, the end of the row falling off', () {
      expect(fed(r'abcdef\e[2G\e[2@').rows.first, 'a  bcdef');
      expect(fed(r'abcdefghij\e[2G\e[2@').rows.first, 'a  bcdefgh');
      expect(fed(r'abcdefgh中\e[1G\e[@').rows.first, ' abcdefgh');
    });

    test('DCH deletes, blanks coming in at the end', () {
      expect(fed(r'abcdef\e[2G\e[2P').rows.first, 'adef');
      expect(fed(r'a中b\e[3G\e[P').rows.first, 'a b');
    });

    test('IRM pushes the rest of the row right', () {
      expect(fed(r'\e[4habc\e[1Gx').rows.first, 'xabc');
      expect(fed(r'\e[4habc\e[1G中').rows.first, '中abc');
      expect(fed(r'abc\e[4h\e[4l\e[1Gx').rows.first, 'xbc');
    });

    test('IL and DL move the rows below the cursor in the margins', () {
      Rig rig() => fed('1\r\n2\r\n3\r\n4');
      expect((rig()..feed(r'\e[2;3H\e[L')).rows, ['1', '', '2', '3']);
      expect((rig()..feed(r'\e[2;3H\e[L')).cursor, (0, 1));
      expect((rig()..feed(r'\e[2;1H\e[M')).rows, ['1', '3', '4', '']);
      expect((rig()..feed(r'\e[2;1H\e[9M')).rows, ['1', '', '', '']);
      expect((rig()..feed(r'\e[1;3r\e[2;1H\e[L')).rows, ['1', '', '2', '4']);
      expect((rig()..feed(r'\e[2;3r\e[4;1H\e[L')).rows, ['1', '2', '3', '4']);
    });

    test('SU and SD scroll the margins', () {
      Rig rig() => fed('1\r\n2\r\n3\r\n4');
      final up = (rig()..feed(r'\e[2S'));
      expect(up.rows, ['3', '4', '', '']);
      expect(up.history, ['1', '2']);
      expect((rig()..feed(r'\e[T')).rows, ['', '1', '2', '3']);
      final region = (rig()..feed(r'\e[2;3r\e[S'));
      expect(region.rows, ['1', '3', '', '4']);
      expect(region.history, isEmpty);
    });

    test('LF at the bottom margin scrolls only the margins', () {
      final r = fed('1\r\n2\r\n3\r\n4')
        ..feed(
          r'\e[2;3r\e[3;1H'
          '\nX',
        );
      expect(r.rows, ['1', '3', 'X', '4']);
      expect(r.history, isEmpty);
    });

    test('margins at the top row scroll into the scrollback', () {
      final r = fed('1\r\n2\r\n3\r\n4')
        ..feed(
          r'\e[1;2r\e[2;1H'
          '\n',
        );
      expect(r.history, ['1']);
      expect(r.rows, ['2', '', '3', '4']);
    });

    test('RI at the top margin scrolls down', () {
      final r = fed('1\r\n2\r\n3\r\n4')..feed(r'\e[2;3r\e[2;1H\eM');
      expect(r.rows, ['1', '', '2', '4']);
      r.feed(r'\e[1;1H\eM');
      expect(r.rows, ['1', '', '2', '4'], reason: 'above the margins');
    });

    test('scrolled rows take the background (BCE)', () {
      final r = fed(
        r'\e[44m'
        '\r\n\r\n',
        height: 2,
      );
      expect(r.bg(0, 1), Color.blue);
      expect(r.bg(0, 0), Color.defaultColor);
    });

    test('the scrollback keeps its limit, oldest lines going', () {
      final r = fed('1\r\n2\r\n3\r\n4\r\n5', height: 1, scrollback: 2);
      expect(r.t.scrollbackLimit, 2);
      expect(r.history, ['3', '4']);
      r.t.scrollbackLimit = 1;
      expect(r.history, ['4']);
      r.t.scrollbackLimit = 0;
      r.feed('\r\n6');
      expect(r.history, isEmpty);
    });
  });

  group('SGR', () {
    test('attributes on and off', () {
      final r = fed(r'\e[1;2;3;4;5;7;8;9;53mx\e[22;23;24;25;27;28;29;55my');
      expect(
        r.attrs(0, 0),
        Attr.bold |
            Attr.dim |
            Attr.italic |
            Attr.underline |
            Attr.blink |
            Attr.reverse |
            Attr.hidden |
            Attr.strike |
            Attr.overline,
      );
      expect(r.attrs(1, 0), 0);
      expect(fed(r'\e[1mx\e[mx').attrs(1, 0), 0);
      expect(fed(r'\e[1mx\e[0mx').attrs(1, 0), 0);
    });

    test('underline styles', () {
      final r = fed(r'\e[4:3ma\e[21mb\e[4:0mc\e[4:5md\e[4me\e[24mf');
      expect(r.attrs(0, 0), Attr.curlyUnderline);
      expect(r.attrs(1, 0), Attr.doubleUnderline);
      expect(r.attrs(2, 0), 0);
      expect(r.attrs(3, 0), Attr.dashedUnderline);
      expect(r.attrs(4, 0), Attr.underline);
      expect(r.attrs(5, 0), 0);
    });

    test('16, 256 and 24-bit colors in both notations', () {
      final r = fed(
        r'\e[31;42ma\e[91;102mb\e[38;5;196;48;5;21mc'
        r'\e[38;2;1;2;3md\e[38:2::10:20:30me\e[48:2:7:8:9mf'
        r'\e[38:5:100mg\e[39;49mh\e[4;58:5:9mi\e[58;2;1;1;1mj\e[59mk',
        width: 20,
      );
      expect((r.fg(0, 0), r.bg(0, 0)), (Color.red, Color.green));
      expect(
        (r.fg(1, 0), r.bg(1, 0)),
        (const Color.indexed(9), const Color.indexed(10)),
      );
      expect(
        (r.fg(2, 0), r.bg(2, 0)),
        (const Color.indexed(196), const Color.indexed(21)),
      );
      expect(r.fg(3, 0), const Color.rgb(1, 2, 3));
      expect(r.fg(4, 0), const Color.rgb(10, 20, 30));
      expect(r.bg(5, 0), const Color.rgb(7, 8, 9));
      expect(r.fg(6, 0), const Color.indexed(100));
      expect(
        (r.fg(7, 0), r.bg(7, 0)),
        (Color.defaultColor, Color.defaultColor),
      );
      expect(r.ul(8, 0), const Color.indexed(9));
      expect(r.ul(9, 0), const Color.rgb(1, 1, 1));
      expect(r.ul(10, 0), Color.defaultColor);
    });

    test('an attribute after a color is applied', () {
      final r = fed(r'\e[38;5;1;1mx\e[38;2;1;2;3;4my');
      expect((r.fg(0, 0), r.attrs(0, 0)), (Color.red, Attr.bold));
      expect(r.attrs(1, 0) & Attr.underline, Attr.underline);
    });
  });

  group('character sets', () {
    test('DEC special graphics draw lines', () {
      expect(fed(r'\e(0lqkxmj\e(Bq').rows.first, '┌─┐│└┘q');
    });

    test('SO and SI switch to G1 and back', () {
      expect(
        fed(
          r'\e)0'
          '\x0eqa\x0fq',
        ).rows.first,
        '─▒q',
      );
    });

    test('a single shift takes one character from G2', () {
      expect(fed(r'\e*0\eNqq').rows.first, '─q');
    });

    test('the UK set has a pound for #', () {
      expect(fed(r'\e(A#\e(B#').rows.first, '£#');
    });

    test('DECSC keeps the sets', () {
      expect(fed(r'\e(0\e7\e(B\e8q').rows.first, '─');
    });
  });

  group('screens', () {
    test('1049 saves the cursor, switches and clears; back restores', () {
      final r = fed(r'main\e[?1049h');
      expect(r.t.alternateScreen, isTrue);
      expect(r.rows.first, '');
      r.feed(r'\e[2;2Halt\e[?1049l');
      expect(r.t.alternateScreen, isFalse);
      expect(r.rows.first, 'main');
      expect(r.cursor, (4, 0));
      r.feed(r'\e[?1049h');
      expect(r.rows[1], '', reason: 'cleared again');
    });

    test('47 switches without clearing, 1047 clears on leaving', () {
      final r = fed(r'\e[?47hA\e[?47l\e[?47h');
      expect(r.rows.first, 'A');
      r.feed(r'\e[?47l\e[?1047h\e[?1047l\e[?47h');
      expect(r.rows.first, '');
    });

    test('the alternate screen keeps no scrollback', () {
      final r = fed(
        r'\e[?1049h'
        '1\r\n2\r\n3',
        height: 2,
      );
      expect(r.history, isEmpty);
      expect(r.rows, ['2', '3']);
    });

    test('RIS resets the screen and the modes, the scrollback stays', () {
      final r = fed('1\r\n2\r\n3', height: 2)
        ..feed(
          r'\e[?1049h\e[?25l\e[4h\e[31m\e[2;2r\ec',
        );
      expect(r.t.alternateScreen, isFalse);
      expect(r.rows, ['', '']);
      expect(r.history, ['1']);
      expect(r.t.cursorVisible, isTrue);
      expect(r.t.mode(TerminalMode.insert), isFalse);
      expect(r.t.margins, (0, 2));
      r.feed('x');
      expect(r.fg(0, 0), Color.defaultColor);
    });

    test('DECSTR resets modes and attributes but not the screen', () {
      final r = fed(r'abc\e[?25l\e[4h\e[?6h\e[1m\e[!p');
      expect(r.rows.first, 'abc');
      expect(r.t.cursorVisible, isTrue);
      expect(r.t.mode(TerminalMode.insert), isFalse);
      expect(r.t.mode(TerminalMode.origin), isFalse);
      r.feed('x');
      expect(r.attrs(0, 0), 0);
    });
  });

  group('modes', () {
    test('a change is an event, a set mode set again none', () {
      final r = fed(r'\e[?2004h\e[?2004h\e[?1h\e[?2004l');
      expect(
        r.events,
        [
          const ModeChanged(TerminalMode.bracketedPaste, enabled: true),
          const ModeChanged(TerminalMode.cursorKeys, enabled: true),
          const ModeChanged(TerminalMode.bracketedPaste, enabled: false),
        ].map(
          (e) => isA<ModeChanged>()
              .having((m) => m.mode, 'mode', e.mode)
              .having((m) => m.enabled, 'enabled', e.enabled),
        ),
      );
    });

    test('one mouse protocol and one encoding at a time', () {
      final r = fed(r'\e[?1000h\e[?1006h');
      expect(r.t.mouseProtocol, MouseProtocol.buttons);
      expect(r.t.mouseEncoding, MouseEncoding.sgr);
      r.feed(r'\e[?1003h\e[?1015h');
      expect(r.t.mouseProtocol, MouseProtocol.motion);
      expect(r.t.mouseEncoding, MouseEncoding.urxvt);
      expect(r.t.mode(TerminalMode.mouseButtons), isFalse);
      r.feed(r'\e[?1000l');
      expect(r.t.mouseProtocol, MouseProtocol.off);
      r.feed(r'\e[?9h');
      expect(r.t.mouseProtocol, MouseProtocol.x10);
      r.feed(r'\e[?1002h');
      expect(r.t.mouseProtocol, MouseProtocol.drags);
      r.feed(r'\e[?1005h');
      expect(r.t.mouseEncoding, MouseEncoding.utf8);
      r.feed(r'\e[?1005l');
      expect(r.t.mouseEncoding, MouseEncoding.x10);
    });

    test('several modes in one sequence; XTSAVE and XTRESTORE', () {
      final r = fed(r'\e[?1;2004;1004h');
      expect(r.t.mode(TerminalMode.cursorKeys), isTrue);
      expect(r.t.mode(TerminalMode.bracketedPaste), isTrue);
      expect(r.t.mode(TerminalMode.focus), isTrue);
      r.feed(r'\e[?2004s\e[?2004l\e[?2004r');
      expect(r.t.mode(TerminalMode.bracketedPaste), isTrue);
    });

    test('DECKPAM and DECKPNM', () {
      final r = fed(r'\e=');
      expect(r.t.mode(TerminalMode.keypad), isTrue);
      r.feed(r'\e>');
      expect(r.t.mode(TerminalMode.keypad), isFalse);
    });

    test('the events of icon names, modes, cursor shapes and resizes say '
        'what the program asked', () {
      final r = fed(r'\e]1;icon^G\e[?2004h\e[5 q\e[8;3;7t');
      expect(r.events.map((e) => '$e'), [
        'IconNameChanged(icon)',
        'ModeChanged(bracketedPaste, true)',
        'CursorShapeChanged(blinkingBar)',
        'ResizeRequested(7, 3)',
      ]);
    });

    test('DECSCUSR sets the cursor shape', () {
      final r = fed(r'\e[5 q\e[5 q\e[2 q');
      expect(r.t.cursorShape, CursorShape.block);
      expect(r.events.whereType<CursorShapeChanged>().map((e) => e.shape), [
        CursorShape.blinkingBar,
        CursorShape.block,
      ]);
    });
  });

  group('answers', () {
    test('device attributes and the version', () {
      final r = fed(r'\e[c\e[0c\e[>c\e[=c\e[>q');
      expect(
        r.takeSent(),
        r'\e[?62;22;52c\e[?62;22;52c\e[>1;10;0c\eP!|00000000\e\'
        r'\eP>|twk_term 0.1.0\e\',
      );
    });

    test('status and the cursor position', () {
      final r = fed(r'\e[5n\e[3;4H\e[6n\e[?6n');
      expect(r.takeSent(), r'\e[0n\e[3;4R\e[?3;4R');
      r.feed(r'\e[1;1H0123456789\e[6n');
      expect(r.takeSent(), r'\e[1;10R');
    });

    test('DECRQM for private, ANSI and unknown modes', () {
      final r = fed(
        r'\e[?25$p\e[?2004$p\e[?9999$p\e[4$p\e[?1049$p\e[?47$p\e[?7$p',
      );
      expect(
        r.takeSent(),
        r'\e[?25;1$y\e[?2004;2$y\e[?9999;0$y\e[4;2$y\e[?1049;2$y'
        r'\e[?47;2$y\e[?7;1$y',
      );
    });

    test('DECRQSS for SGR, margins and the cursor', () {
      final r = fed(
        r'\e[1;4:3;31;48;5;200;58:2::1:2:3m\eP$qm\e\'
        r'\e[2;3r\eP$qr\e\\e[6 q\eP$q q\e\\eP$qx\e\',
      );
      expect(
        r.takeSent(),
        r'\eP1$r0;1;4:3;31;48:5:200;58:2::1:2:3m\e\'
        r'\eP1$r2;3r\e\\eP1$r6 q\e\\eP0$r\e\',
      );
    });

    test('XTGETTCAP tells no capability', () {
      expect(fed(r'\eP+q544e\e\').takeSent(), r'\eP0+r544e\e\');
    });

    test('XTWINOPS reports the size, in pixels once known', () {
      final r = fed(r'\e[18t\e[19t\e[14t\e[16t');
      expect(r.takeSent(), r'\e[8;4;10t\e[9;4;10t');
      r.t
        ..cellPixelWidth = 8
        ..cellPixelHeight = 16;
      r.feed(r'\e[14t\e[16t');
      expect(r.takeSent(), r'\e[4;64;80t\e[6;16;8t');
      r.feed(r'\e[8;30;100t');
      expect(r.events.last, isA<ResizeRequested>());
    });

    test('the default colors, asked and set (OSC 10, 11, 12)', () {
      final r = fed(r'\e]10;?^G\e]11;?\e\');
      expect(
        r.takeSent(),
        r'\e]10;rgb:e5e5/e5e5/e5e5'
        '\x07'
        r'\e]11;rgb:0000/0000/0000\e\',
      );
      r.t.defaultBackground = 0x102030;
      r.feed(r'\e]10;#ff8000;?^G\e]12;rgb:f/0/0^G\e]12;?^G');
      expect(
        r.takeSent(),
        r'\e]11;rgb:1010/2020/3030'
        '\x07'
        r'\e]12;rgb:ffff/0000/0000'
        '\x07',
      );
      expect(r.t.foregroundColor, 0xFF8000);
      r.feed(r'\e]110^G');
      expect(r.t.foregroundColor, 0xE5E5E5);
      expect(r.events.whereType<ColorsChanged>(), hasLength(3));
      r.feed(r'\e[?996n');
      expect(r.takeSent(), r'\e[?997;1n');
    });

    test('the palette, asked and set (OSC 4, 104)', () {
      final r = fed(r'\e]4;1;?^G\e]4;1;rgb:12/34/56;2;?^G\e]4;1;?^G');
      expect(
        r.takeSent(),
        r'\e]4;1;rgb:cdcd/0000/0000'
        '\x07'
        r'\e]4;2;rgb:0000/cdcd/0000'
        '\x07'
        r'\e]4;1;rgb:1212/3434/5656'
        '\x07',
      );
      r.feed(r'\e]104;1^G');
      expect(r.t.palette[1], 0xCD0000);
    });
  });

  group('OSC', () {
    test('titles and the title stack', () {
      final r = fed(r'\e]0;both^G\e]2;title\e\\e[22t\e]2;other^G\e[23t');
      expect(r.t.title, 'title');
      expect(r.t.iconName, 'both');
      expect(r.events.whereType<TitleChanged>().map((e) => e.title), [
        'both',
        'title',
        'other',
        'title',
      ]);
      fed(r'\e]1;icon^G').events.single as IconNameChanged;
    });

    test('a hyperlink is in the style of the cells printed under it', () {
      final r = fed(r'\e]8;id=1;http://x\e\ab\e]8;;\e\c');
      expect(r.link(0, 0), 'http://x');
      expect(r.link(1, 0), 'http://x');
      expect(r.link(2, 0), isNull);
      r.feed(r'\e[1G\e[K');
      expect(r.link(0, 0), isNull, reason: 'an erase takes the link');
    });

    test('a hyperlink past 2083 characters is none', () {
      final long = 'http://x/${'a' * 2083}';
      final r = fed('\\e]8;;$long\\e\\ab\\e]8;;\\e\\');
      expect(r.link(0, 0), isNull);
      r.feed('\\e]8;;${long.substring(0, 2083)}\\e\\c');
      expect(r.link(2, 0), long.substring(0, 2083));
    });

    test('a title, a notification and a pointer shape keep 4096 code units '
        'at most, no half of a pair', () {
      final long = 'a' * 5000;
      // the 4096th code unit is the first of a pair
      final paired = '${'a' * 4095}🙂b';
      final r = fed(
        '\\e]2;$long^G\\e]1;$paired^G\\e]9;$long^G'
        '\\e]777;notify;$long;$long^G\\e]22;$long^G',
      );
      expect(r.t.title, 'a' * 4096);
      expect(r.t.iconName, 'a' * 4095);
      final told = [
        for (final e in r.events)
          if (e case NotificationRequested(:final title, :final body))
            (title.length, body.length),
      ];
      expect(told, [(0, 4096), (4096, 4096)]);
      expect(
        r.events.whereType<PointerShapeChanged>().single.shape,
        hasLength(4096),
      );
    });

    test('a palette query answers 256 colors a sequence at most', () {
      final r = fed('\\e]4;${List.filled(300, '1;?').join(';')}^G');
      expect(r'\e]4;1;'.allMatches(r.takeSent()), hasLength(256));
    });

    test('a working directory not a file: URI is none', () {
      final r = fed(r'\e]7;http://host/tmp^G\e]7;/tmp^G');
      expect(r.t.workingDirectory, isNull);
      expect(r.events, isEmpty);
    });

    test('DEL within a string is ignored', () {
      expect(fed('\\e]2;a\x7fb^G').t.title, 'ab');
    });

    test("the clipboard is the host's: written, read, answered", () {
      final r = fed(r'\e]52;c;aGVsbG8=^G\e]52;;?^G\e]52;p;!!^G');
      expect(r.events, hasLength(2));
      final write = r.events.first as ClipboardWrite;
      expect((write.selection, write.text), ('c', 'hello'));
      expect((r.events[1] as ClipboardRead).selection, 'c');
      r.t.answerClipboard('c', 'hi');
      expect(r.takeSent(), r'\e]52;c;aGk=\e\');
    });

    test('directory, notifications, progress, prompts, pointer, bell', () {
      final r = fed(
        r'\e]7;file://host/tmp/x^G\e]9;done^G\e]777;notify;Title;Body^G'
        r'\e]9;4;1;42^G\e]133;A^G\e[2;1H\e]133;D;3^G\e]22;text^G'
        '\x07',
      );
      expect(r.t.workingDirectory, Uri.parse('file://host/tmp/x'));
      expect(r.events.map((e) => e.toString()), [
        'WorkingDirectoryChanged(file://host/tmp/x)',
        'NotificationRequested(, done)',
        'NotificationRequested(Title, Body)',
        'ProgressChanged(1, 42)',
        'PromptMarked(promptStart, 0, null)',
        'PromptMarked(commandEnd, 1, 3)',
        'PointerShapeChanged(text)',
        'BellRang()',
      ]);
    });
  });

  group('unknown sequences', () {
    test('are ignored unless strict', () {
      final t = TerminalEmulator(width: 5, height: 1)
        ..feedText('a\x1b[5}b\x1b]5555;x\x07c\x1bPzq\x1b\\d\x1b_apc\x1b\\e');
      expect(t.lineText(0), 'abcde');
      expect(() => fed(r'\e[5}'), throwsFormatException);
    });
  });

  group('resize', () {
    test('a narrower screen rewraps the lines', () {
      final r = fed('abcdefghijkl');
      expect(r.rows.take(2), ['abcdefghij', 'kl']);
      r.t.resize(6, 4);
      expect(r.rows, ['abcdef', 'ghijkl', '', '']);
      expect(r.cursor, (5, 1));
      expect(r.t.wrapPending, isTrue);
      r.feed('m');
      expect(r.rows.take(3), ['abcdef', 'ghijkl', 'm']);
    });

    test('a wider one joins them again', () {
      final r = fed('abcdefghijkl\r\nxy', width: 6);
      r.t.resize(12, 4);
      expect(r.rows, ['abcdefghijkl', 'xy', '', '']);
      expect(r.cursor, (2, 1));
    });

    test('the cursor stays on its character', () {
      final r = fed(r'abcdefgh\e[1;3H', width: 6);
      r.t.resize(4, 4);
      expect(r.rows, ['abcd', 'efgh', '', '']);
      expect(r.cursor, (2, 0));
      r.t.resize(3, 4);
      expect(r.rows, ['abc', 'def', 'gh', '']);
      expect(r.cursor, (2, 0));
    });

    test('a wide character is not cut', () {
      final r = fed('abc中d', width: 6);
      r.t.resize(4, 4);
      expect(r.rows, ['abc', '中d', '', '']);
      r.t.resize(6, 4);
      expect(r.rows, ['abc中d', '', '', '']);
    });

    test('lines go to the scrollback and come back', () {
      final r = fed('1\r\n2\r\n3\r\n4', width: 4, height: 3);
      expect(r.history, ['1']);
      r.t.resize(4, 2);
      expect(r.history, ['1', '2']);
      expect(r.rows, ['3', '4']);
      r.t.resize(4, 5);
      expect(r.history, isEmpty);
      expect(r.rows, ['1', '2', '3', '4', '']);
      expect(r.cursor, (1, 3));
    });

    test('blank rows below the cursor go first', () {
      final r = fed('1\r\n2', width: 4);
      r.t.resize(4, 2);
      expect(r.history, isEmpty);
      expect(r.rows, ['1', '2']);
    });

    test('the scrollback is rewrapped too', () {
      final r = fed('abcdef\r\ng', width: 4, height: 1);
      expect(r.history, ['abcd', 'ef']);
      r.t.resize(8, 1);
      expect(r.history, ['abcdef']);
      expect(r.rows, ['g']);
    });

    test('the alternate screen is cut, the primary rewrapped under it', () {
      final r = fed(r'abcdefgh\e[?1049h\e[3;1Hxyzuvw', width: 6);
      r.t.resize(4, 2);
      expect(r.rows, ['', 'xyzu'], reason: "the cursor's row kept");
      expect(r.cursor, (3, 1));
      r.feed(r'\e[?1049l');
      expect(r.rows, ['abcd', 'efgh']);
      expect(r.cursor, (3, 1));
      expect(r.t.wrapPending, isTrue);
    });

    test('a wide character cut by the edge of the alternate screen is '
        'blanked', () {
      final r = fed(r'\e[?1049h\e[1;8Ha中');
      expect(r.rows.first, '       a中');
      r.t.resize(9, 4);
      expect(r.rows.first, '       a');
      expect(r.t.cellAt(8, 0), r.t.cellAt(6, 0), reason: 'a blank');
    });

    test('a line wrapped over many rows is rewrapped whole', () {
      final text = [for (var i = 0; i < 300; i++) i % 10].join();
      final r = fed(text, width: 100, height: 5);
      r.t.resize(70, 5);
      expect(r.rows, [
        for (var i = 0; i < 300; i += 70)
          text.substring(i, i + 70 > 300 ? 300 : i + 70),
      ]);
      expect(r.t.text, r.rows.join('\n'));
    });

    test('the margins are reset and the tab stops extended', () {
      final r = fed(r'\e[2;3r');
      r.t.resize(20, 6);
      expect(r.t.margins, (0, 6));
      r.feed(
        r'\e[1;10H'
        '\t',
      );
      expect(r.cursor, (16, 0));
    });
  });

  group('for a view', () {
    test('moves of rows are told as they happen', () {
      final moves = <(int, int, int)>[];
      final r = Rig()
        ..t.onScrolled = ((a, b, n) => moves.add((a, b, n)))
        ..feed('1\r\n2\r\n3\r\n4');
      expect(moves, isEmpty);
      r.feed('\r\n5\n\x1b[H\x1bM\x1bM');
      expect(moves, [(0, 4, 1), (0, 4, 1), (0, 4, -1), (0, 4, -1)]);
      moves.clear();
      r.feed('\x1b[2;3r\x1b[3;1H\n\x1b[2S\x1b[T\x1b[2;1H\x1b[L\x1b[2M');
      expect(moves, [(1, 3, 1), (1, 3, 2), (1, 3, -1), (1, 3, -1), (1, 3, 2)]);
      moves.clear();
      r.feed(r'\e[r\e[?1049h\e[2;1H\e[M');
      expect(moves, [(1, 4, 1)], reason: 'on the alternate screen too');
    });

    test('the lines that go into the scrollback are counted', () {
      final r = Rig(height: 3, scrollback: 2)
        ..feed('1\r\n2\r\n3\r\n4\r\n5\r\n6');
      expect(r.t.scrollbackAdded, 3);
      expect(r.t.scrollbackLength, 2);
      r.feed('\x1b[?1049h\n\n\n\x1b[?1049l\x1b[2;3r\x1b[3;1H\n\x1b[r');
      expect(r.t.scrollbackAdded, 3, reason: 'none went to it');
      final none = Rig(height: 1, scrollback: 0)..feed('1\r\n2');
      expect(none.t.scrollbackAdded, 0);
    });
  });
}
