import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_term/twk_term.dart';

import 'support.dart';

/// Everything the screen and the scrollback hold, cell by cell.
List<Object> snapshot(TerminalEmulator t) => [
  for (var i = 0; i < t.scrollbackLength; i++) ...[
    ...t.scrollbackLine(i).cells,
    ...t.scrollbackLine(i).styles,
  ],
  for (var y = 0; y < t.height; y++) ...[
    ...t.line(y).cells,
    ...t.line(y).styles,
    t.line(y).wrapped,
  ],
  t.cursorX,
  t.cursorY,
  t.title,
];

void main() {
  group('split writes', () {
    for (final name in [
      'bash',
      'nano',
      'less',
      'htop',
      'git_log',
      'chat_demo',
    ]) {
      test('$name: any split gives the screen of one write', () {
        final bytes = File('test/fixtures/$name.bin').readAsBytesSync();
        final whole = TerminalEmulator()..feed(bytes);
        final expected = snapshot(whole);
        final random = Random(7);
        for (final size in [1, 2, 3, 5, 7, 13, 0]) {
          final t = TerminalEmulator();
          for (var i = 0; i < bytes.length;) {
            final n = size == 0 ? 1 + random.nextInt(40) : size;
            final end = i + n > bytes.length ? bytes.length : i + n;
            t.feed(Uint8List.sublistView(bytes, i, end));
            i = end;
          }
          expect(snapshot(t), expected, reason: 'pieces of $size');
        }
      });
    }
  });

  group('text', () {
    test('ASCII among other text, a mark after it joining still', () {
      final r = fed('é${'a' * 16}\u0301b中', width: 24);
      expect(r.rows.first, 'é${'a' * 15}a\u0301b中');
      expect(r.t.cellText(16, 0), 'a\u0301');
      expect(r.cursor, (20, 0));
    });

    test('a character cut short by a control is U+FFFD, the control '
        'executed', () {
      final r = Rig()..t.feed([0x61, 0xE4, 0xB8, 0x0A, 0x62]);
      expect(r.rows.take(2), ['a\u{FFFD}', '  b']);
    });

    test('a character cut short by ASCII is U+FFFD', () {
      final r = Rig(width: 24);
      r.t
        ..feed([0x61, 0xE4, 0xB8, ...List.filled(16, 0x62)])
        ..feed([0xE4])
        ..feed(List.filled(16, 0x63));
      expect(r.rows.first, 'a\uFFFD${'b' * 16}\uFFFD${'c' * 5}');
    });
  });

  group('sequences', () {
    test('CAN and SUB abort one', () {
      expect(fed('a\x1b[3\x18Xb\x1b[\x1aY').rows.first, 'aXbY');
    });

    test('ESC inside one starts over', () {
      expect(fed('ab\x1b[1\x1b[4GX').rows.first, 'ab X');
    });

    test('a C0 control inside one is executed', () {
      expect(fed('abc\x1b[1\bDX').rows.first, 'aXc');
    });

    test('an OSC ends with BEL, with ST, or with the ESC of what follows', () {
      final r = fed(r'\e]2;one^G\e]2;two\e\\e]2;three\e[2GX');
      expect(r.t.title, 'three');
      expect(r.rows.first, ' X');
    });

    test('an OSC is cut at its limit', () {
      final r = fed('\x1b]2;${'x' * (1 << 21)}\x07ok');
      expect(r.t.title.length, (1 << 20) - 2);
      expect(r.rows.first, 'ok');
    });

    test('an APC, a PM and a sixel DCS are skipped', () {
      expect(
        fed(r'a\e_Gf=1;AAAA\e\b\e^pm\e\c\eP0;1;0q#0;2;0;0;0~-\e\d').rows.first,
        'abcd',
      );
    });

    test('a parameter too large is clamped, too many are dropped', () {
      final r = fed(r'\e[99999999999Cx');
      expect(r.cursor, (9, 0));
      final many = List.filled(40, '0').join(';');
      expect(fed('\x1b[$many;1mx').attrs(0, 0), 0);
    });

    test('a private marker after the parameters makes it malformed', () {
      expect(fed(r'\e[1?hX').rows.first, 'X');
    });
  });
}
