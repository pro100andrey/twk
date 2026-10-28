// InputParser on what test/input_parser_test.dart leaves out: F1 to F4
// with modifiers in xterm's CSI form, the modifiers and tilted wheel of a
// mouse report, a paste bigger than the parser holds at first, ESC and a
// character split across reads, and what a flush leaves behind.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

List<InputEvent> parse(String s) => InputParser().feed(s.codeUnits);

void main() {
  test('F1 to F4 with modifiers come as CSI 1 ; modifiers P, Q, R, S', () {
    expect(parse('\x1b[1;5P\x1b[1;2Q\x1b[1;2R\x1b[1;3S'), const [
      KeyEvent(KeyCode.f1, modifiers: Mod.ctrl),
      KeyEvent(KeyCode.f2, modifiers: Mod.shift),
      KeyEvent(KeyCode.f3, modifiers: Mod.shift),
      KeyEvent(KeyCode.f4, modifiers: Mod.alt),
    ]);
  });

  test('a mouse report tells Shift, Alt and Ctrl held, and the wheel '
      'tilted either way', () {
    expect(parse('\x1b[<4;1;1M\x1b[<8;5;3M\x1b[<16;1;1m'), const [
      MouseEvent(MouseKind.down, 0, 0, modifiers: Mod.shift),
      MouseEvent(MouseKind.down, 4, 2, modifiers: Mod.alt),
      MouseEvent(MouseKind.up, 0, 0, modifiers: Mod.ctrl),
    ]);
    expect(parse('\x1b[<66;2;3M\x1b[<67;2;3M'), const [
      MouseEvent(MouseKind.wheelLeft, 1, 2),
      MouseEvent(MouseKind.wheelRight, 1, 2),
    ]);
  });

  test('a paste of many times what the parser holds at first, in one '
      'read, arrives whole', () {
    final text = List.generate(5000, (i) => 'line $i').join('\n');
    expect(parse('\x1b[200~$text\x1b[201~'), [PasteEvent(text)]);
  });

  test('a paste that comes a little at a time arrives whole', () {
    final parser = InputParser();
    final pieces = [for (var i = 0; i < 40; i++) 'piece $i, '];
    final events = [
      ...parser.feed('\x1b[200~'.codeUnits),
      for (final piece in pieces) ...parser.feed(piece.codeUnits),
      ...parser.feed('\x1b[201~'.codeUnits),
    ];
    expect(events, [PasteEvent(pieces.join())]);
  });

  test('ESC and a character split across reads waits for the rest, not '
      'for the timeout', () {
    // Alt+€ (E2 82 AC) and Alt+😀 (F0 9F 98 80), cut after each byte of
    // the character: only its completion can follow, so there is nothing
    // to time out, and no flush breaks it into replacement characters
    for (final (char, bytes) in [
      ('€', [0xE2, 0x82, 0xAC]),
      ('😀', [0xF0, 0x9F, 0x98, 0x80]),
    ]) {
      for (var cut = 1; cut < bytes.length; cut++) {
        final p = InputParser();
        expect(p.feed([0x1B, ...bytes.sublist(0, cut)]), isEmpty);
        expect(p.hasPending, isFalse, reason: '$char cut after $cut');
        expect(p.sequenceStarted, isFalse, reason: '$char cut after $cut');
        expect(p.feed(bytes.sublist(cut)), [
          KeyEvent(KeyCode.char, char: char, modifiers: Mod.alt),
        ], reason: '$char cut after $cut');
      }
    }
    // a lone ESC still waits for the timeout, and the character typed
    // after it completes the same way
    final p = InputParser();
    expect(p.feed([0x1B]), isEmpty);
    expect(p.hasPending, isTrue);
    expect(p.feed([0xE2]), isEmpty);
    expect(p.hasPending, isFalse);
    expect(p.feed([0x82, 0xAC]), [
      const KeyEvent(KeyCode.char, char: '€', modifiers: Mod.alt),
    ]);
  });

  test('a flush leaves nothing of a cut sequence for the next read', () {
    // every prefix of each, flushed as a timeout does: whatever it
    // resolves to, the next read starts afresh
    for (final s in [
      '\x1b[<35;10;20M',
      '\x1b[1;5A',
      '\x1b[?1;2c',
      '\x1bO5P',
      '\x1bOA',
      '\x1b]11;rgb:ffff/0000/8080\x1b\\',
      '\x1b]11;rgb:ffff/0000/8080\x07',
      '\x1bP>|kitty\x1b\\',
      '\x1b_Gi=1;OK\x1b\\',
      '\x1b\x1b[A',
      '\x1b\x1bOB',
      '\x1b\x1b',
      '\x1b€',
      '\x1b😀',
      '€',
    ]) {
      final bytes = utf8.encode(s);
      for (var cut = 1; cut <= bytes.length; cut++) {
        final p = InputParser()
          ..feed(bytes.sublist(0, cut))
          ..flush();
        final reason = '${jsonEncode(s)} cut after $cut';
        expect(p.hasPending, isFalse, reason: reason);
        expect(p.feed('x'.codeUnits), [
          const KeyEvent(KeyCode.char, char: 'x'),
        ], reason: reason);
      }
    }
  });
}
