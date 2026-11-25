// TearCheck: the screens a terminal without synchronized updates may show
// between the steps of a frame, held to the screen before it and after it.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_test/vt.dart';

/// A sidebar (`S0`..`S3`) beside a list (`aaaa`..`dddd`) whose rectangle,
/// columns 3 to 7, is to scroll up by a row: (top, bottom, n, x0, x1).
const _listUp = [0, 4, 1, 3, 8];

Vt _screen() {
  final vt = Vt(8, 4);
  for (final (y, row) in ['S0 aaaa', 'S1 bbbb', 'S2 cccc', 'S3 dddd'].indexed) {
    vt.feed(utf8.encode('\x1b[${y + 1};1H$row'));
  }
  return vt;
}

/// What [frame] fed to [vt] tears, the move asked for being [moves].
List<String> _torn(Vt vt, String frame, {List<int> moves = _listUp}) {
  final check = TearCheck(vt)..begin(moves: moves);
  vt.feed(utf8.encode(frame));
  expect(vt.errors, isEmpty);
  return check.end();
}

const _after = ['S0 bbbb', 'S1 cccc', 'S2 dddd', 'S3 eeee'];

void main() {
  group('inline', inlineTests);
  test('a rectangle scrolled as whole rows tears the cells beside it until '
      'they are written again', () {
    final vt = _screen();
    final torn = _torn(
      vt,
      '\x1b[1;4r\x1b[1S\x1b[r'
      '\x1b[1;1HS0\x1b[2;1HS1\x1b[3;1HS2\x1b[4;1HS3\x1b[4;4Heeee',
    );
    expect(vt.lines, _after);
    expect(torn, isNotEmpty);
    // the SU, the second step: the sidebar moved up with the rows
    expect(torn.first, startsWith('step 2 of 13: (1,0) "1"'));
    expect(
      torn.last,
      contains('rows 0-3 by 1 (columns 0-7, asked 3-7)'),
    );
  });

  test('the same frame in a synchronized update shows no step', () {
    final vt = _screen();
    final torn = _torn(
      vt,
      '\x1b[?2026h\x1b[1;4r\x1b[1S\x1b[r'
      '\x1b[1;1HS0\x1b[2;1HS1\x1b[3;1HS2\x1b[4;1HS3\x1b[4;4Heeee'
      '\x1b[?2026l',
    );
    expect(vt.lines, _after);
    expect(torn, isEmpty);
  });

  test('the rectangle scrolled within left and right margins moves only '
      'its cells: no tear', () {
    final vt = _screen();
    final torn = _torn(
      vt,
      '\x1b[?69h\x1b[1;4r\x1b[4;8s\x1b[1S\x1b[r\x1b[s\x1b[?69l'
      '\x1b[4;4Heeee',
    );
    expect(vt.lines, _after);
    expect(torn, isEmpty);
  });

  test('content scrolled down with its rows, then within a rectangle of '
      'them, came by both moves: no tear; shifted along its row then to a '
      'cell the frame leaves blank, it is torn', () {
    const scrolls =
        '\x1b[1;2r\x1b[1T\x1b[r'
        '\x1b[?69h\x1b[2;3r\x1b[3;6s\x1b[1T\x1b[r\x1b[s\x1b[?69l';
    const moves = [0, 2, -1, 0, 6, 1, 3, -1, 2, 6];
    var vt = Vt(6, 3)..feed(utf8.encode('\x1b[1;5HF'));
    expect(_torn(vt, '$scrolls\x1b[3;5H\x1b[K', moves: moves), isEmpty);
    expect(vt.lines.map((l) => l.trim()), ['', '', '']);
    vt = Vt(6, 3)..feed(utf8.encode('\x1b[1;5HF'));
    expect(
      _torn(
        vt,
        '$scrolls\x1b[3;1H\x1b[2P\x1b[3;1H\x1b[K',
        moves: moves,
      ),
      [
        startsWith('step 12 of 14: (2,2) "F"'),
        startsWith('step 13 of 14: (2,2) "F"'),
        contains('row 2 from column 0 by -2'),
      ],
    );
  });

  test('whole rows scrolled where no move was asked for (a scroll the '
      'presenter detected) move as one: no tear', () {
    final vt = Vt(4, 4);
    for (var y = 0; y < 4; y++) {
      vt.feed(utf8.encode('\x1b[${y + 1};1Hr$y'));
    }
    final torn = _torn(
      vt,
      '\x1b[1;4r\x1b[1S\x1b[r\x1b[4;1Hr4',
      moves: const [],
    );
    expect(vt.lines, ['r1', 'r2', 'r3', 'r4']);
    expect(torn, isEmpty);
  });

  test('a row shifted by ICH to where the frame has its cells, and a cell '
      'erased before it is written, are no tear', () {
    final vt = Vt(6, 1)..feed(utf8.encode('abcd'));
    final torn = _torn(
      vt,
      '\x1b[1;2H\x1b[1@\x1b[1;2HX\x1b[1;5H\x1b[K\x1b[1;5Hd',
      moves: const [],
    );
    expect(vt.lines, ['aXbcd']);
    expect(torn, isEmpty);
  });

  test('a glyph a row shift took to a cell the frame writes over is torn '
      'until written', () {
    final vt = Vt(6, 1)..feed(utf8.encode('abcd'));
    final torn = _torn(
      vt,
      '\x1b[1;2H\x1b[1@\x1b[1;2HX\x1b[1;5H\x1b[K\x1b[1;5Hcd',
      moves: const [],
    );
    expect(vt.lines, ['aXbccd']);
    expect(torn, isNotEmpty);
    expect(torn.first, contains('(4,0) "d"'));
  });

  test('a cell the frame leaves as it is, written over in a step, is torn', () {
    final vt = Vt(4, 1)..feed(utf8.encode('ab'));
    final torn = _torn(vt, '\x1b[1;1Hx\x1b[1;1Ha', moves: const []);
    expect(vt.lines, ['ab']);
    expect(torn.first, startsWith('step 2 of 4: (0,0) "x"'));
  });
}

/// An inline region's terminal: a screen of 6 x 3 with a scrollback.
Vt _inline() =>
    Vt(6, 3, scrollback: true, allowLineFeed: true)
      ..feed(utf8.encode('r0\r\nr1\r\nr2'));

void inlineTests() {
  test('a row committed on the screen and scrolled into the scrollback '
      'by line feeds passes through: no tear', () {
    final vt = _inline();
    // the row printed on the region's last row, scrolled up into the
    // scrollback, the region written again below it
    final torn = _torn(
      vt,
      '\x1b[3;1HCOMMIT\r\n\r\n\r\n\x1b[1;1Hr0\x1b[2;1Hr1\x1b[3;1Hr2',
      moves: const [],
    );
    expect(vt.history.map((r) => r.map((c) => c.text).join()).last, 'COMMIT');
    expect(torn, isEmpty);
  });

  test('a row deleted off the top (DL) is not scrolled into the scrollback: '
      'written and deleted, it is torn', () {
    final vt = _inline();
    // the same row then printed again and scrolled into the scrollback by
    // a line feed, where the deleted one is not
    final torn = _torn(
      vt,
      [
        '\x1b[1;1HGONE  \x1b[1;1H\x1b[M',
        '\x1b[1;1HGONE  \x1b[3;1H\n',
        '\x1b[1;1Hr1\x1b[2;1Hr2\x1b[3;1Hr3',
      ].join(),
      moves: const [],
    );
    expect(vt.history.map((r) => r.map((c) => c.text).join()).last, 'GONE  ');
    expect(torn, isNotEmpty);
    expect(torn.first, startsWith('step 2 of'));
  });

  test('a scroll is the move asked for only in its direction', () {
    // the rows scrolled down (SD) where a move of the list up was asked:
    // not that move, so the sidebar moved down with its rows, as the
    // terminal moved it, and is no tear
    final vt = _screen();
    final torn = _torn(
      vt,
      '\x1b[1;4r\x1b[1T\x1b[r'
      '\x1b[1;1HS0 bbbb\x1b[2;1HS1 cccc\x1b[3;1HS2 dddd\x1b[4;1HS3 eeee',
    );
    expect(vt.lines, _after);
    expect(torn, isEmpty);
  });
}
