// Screens of vttest (https://invisible-island.net/vttest/), its sequences
// written out as its tests send them to an 80x24 terminal, its newlines as
// CR LF (the tty's ONLCR).
import 'package:test/test.dart';

import 'support.dart';

String cup(int row, int col) => '\x1b[$row;${col}H';
String hvp(int row, int col) => '\x1b[$row;${col}f';
String cuu(int n) => '\x1b[${n}A';
String cud(int n) => '\x1b[${n}B';
String cuf(int n) => '\x1b[${n}C';
String cub(int n) => '\x1b[${n}D';
String ed(int n) => '\x1b[${n}J';
String el(int n) => '\x1b[${n}K';
const ind = '\x1bD';
const ri = '\x1bM';
const nel = '\x1bE';
const decaln = '\x1b#8';

void main() {
  test('cursor movements: a border of *s and +s, a frame of Es', () {
    const cols = 80;
    const lines = 24;
    const innerL = (cols - 60) ~/ 2;
    const innerR = 61 + innerL;
    final sb = StringBuffer()
      ..write(decaln)
      ..write(cup(9, innerL))
      ..write(ed(1))
      ..write(cup(18, 60))
      ..write(ed(0))
      ..write(el(1))
      ..write(cup(9, innerR))
      ..write(el(0));
    for (var row = 10; row <= 16; row++) {
      sb
        ..write(cup(row, innerL))
        ..write(el(1))
        ..write(cup(row, innerR))
        ..write(el(0));
    }
    sb
      ..write(cup(17, 30))
      ..write(el(2));
    for (var col = 1; col <= cols; col++) {
      sb
        ..write(hvp(lines, col))
        ..write('*')
        ..write(hvp(1, col))
        ..write('*');
    }
    sb.write(cup(2, 2));
    for (var row = 2; row <= lines - 1; row++) {
      sb
        ..write('+')
        ..write(cub(1))
        ..write(ind);
    }
    sb.write(cup(lines - 1, cols - 1));
    for (var row = lines - 1; row >= 2; row--) {
      sb
        ..write('+')
        ..write(cub(1))
        ..write(ri);
    }
    sb.write(cup(2, 1));
    for (var row = 2; row <= lines - 1; row++) {
      sb
        ..write('*')
        ..write(cup(row, cols))
        ..write('*')
        ..write(cub(10))
        ..write(row < 10 ? nel : '\r\n');
    }
    sb
      ..write(cup(2, 10))
      ..write(cub(42))
      ..write(cuf(2));
    for (var col = 3; col <= cols - 2; col++) {
      sb
        ..write('+')
        ..write(cuf(0))
        ..write(cub(2))
        ..write(cuf(1));
    }
    sb
      ..write(cup(lines - 1, innerR - 1))
      ..write(cuf(42))
      ..write(cub(2));
    for (var col = cols - 2; col >= 3; col--) {
      sb
        ..write('+')
        ..write(cub(1))
        ..write(cuf(1))
        ..write(cub(0))
        ..write('\b');
    }
    sb
      ..write(cup(1, 1))
      ..write(cuu(10))
      ..write(cuu(1))
      ..write(cuu(0))
      ..write(cup(lines, cols))
      ..write(cud(10))
      ..write(cud(1))
      ..write(cud(0))
      ..write(cup(10, 2 + innerL));
    for (var row = 10; row <= 15; row++) {
      for (var col = 2 + innerL; col <= innerR - 2; col++) {
        sb.write(' ');
      }
      sb
        ..write(cud(1))
        ..write(cub(58));
    }
    const text = [
      'The screen should be cleared,  and have an unbroken bor-',
      "der of *'s and +'s around the edge,   and exactly in the",
      "middle  there should be a frame of E's around this  text",
      'with  one (1) free position around it.    ',
    ];
    sb
      ..write(cuu(5))
      ..write(cuf(1))
      ..write(text[0]);
    for (var k = 1; k < 4; k++) {
      sb
        ..write(cup(11 + k, 13))
        ..write(text[k]);
    }
    final r = fed(sb.toString(), width: cols, height: lines);

    String inner(String middle) => '*+${middle.padRight(76)}+*';
    final frame = '${' ' * 8}${'E' * 60}';
    String side(String s) => '${' ' * 8}E ${s.padRight(57)}E';
    expect(r.rows, [
      '*' * 80,
      '*${'+' * 78}*',
      for (var y = 3; y <= 8; y++) inner(''),
      inner(frame),
      inner(side('')),
      for (final s in text) inner(side(s)),
      inner(side('')),
      inner(frame),
      for (var y = 17; y <= 22; y++) inner(''),
      '*${'+' * 78}*',
      '*' * 80,
    ]);
  });

  test('autowrap mixed with controls: letters in order at both margins', () {
    const cols = 80;
    const region = 18; // the last row of the margins, counted from them
    final sb = StringBuffer()
      ..write('Test of autowrap, mixing control and print characters.\r\n')
      ..write('The left/right margins should have letters in order:\r\n')
      ..write('\x1b[3;${region + 3}r')
      ..write('\x1b[?6h');
    for (var i = 0; i < 26; i++) {
      final left = String.fromCharCode(0x41 + i);
      final right = String.fromCharCode(0x61 + i);
      final prev = String.fromCharCode(0x61 + i - 1);
      switch (i % 4) {
        case 0:
          sb.write(
            '${cup(region + 1, 1)}$left${cup(region + 1, cols)}$right\r\n',
          );
        case 1:
          sb
            ..write('${cup(region, cols)}$prev$left')
            ..write('${cup(region + 1, cols)}$left\b $right\r\n');
        case 2:
          sb
            ..write('${cup(region + 1, cols)}$left\b\b\t\t$right')
            ..write('${cup(region + 1, 2)}\b$left\r\n');
        default:
          sb
            ..write('${cup(region + 1, cols)}\r\n')
            ..write('${cup(region, 1)}$left')
            ..write('${cup(region, cols)}$right');
      }
    }
    sb
      ..write('\x1b[?6l')
      ..write('\x1b[r');
    final r = fed(sb.toString(), width: cols, height: 24);
    final rows = r.rows;
    expect(rows[0], 'Test of autowrap, mixing control and print characters.');
    expect(rows[1], 'The left/right margins should have letters in order:');
    final pairs = [
      for (var y = 2; y < 2 + region + 1; y++)
        if (rows[y].isNotEmpty) rows[y],
    ];
    expect(pairs, [
      for (var i = 26 - pairs.length; i < 26; i++)
        String.fromCharCodes([0x41 + i, ...List.filled(78, 0x20), 0x61 + i]),
    ]);
    expect(pairs.length, greaterThanOrEqualTo(region));
  });

  test('the screen alignment pattern with scroll margins and origin mode', () {
    final r = fed(
      '\x1b#8\x1b[2;4r\x1b[?6h\x1b[1;1HA\x1b[9;9HB\x1b[?6l\x1b[r',
      width: 6,
      height: 5,
    );
    expect(r.rows, ['EEEEEE', 'AEEEEE', 'EEEEEE', 'EEEEEB', 'EEEEEE']);
  });

  test('insert and delete lines in a region, reverse index at its top', () {
    final r = fed('A\r\nB\r\nC\r\nD\r\nE\r\nF', width: 4, height: 6)
      ..feed('\x1b[2;5r\x1b[3;1H\x1b[2L\x1b[5;1H\x1b[M')
      ..feed('\x1b[2;1H\x1bM\x1b[r');
    expect(r.rows, ['A', '', 'B', '', '', 'F']);
  });
}
