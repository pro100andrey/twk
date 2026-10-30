import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/src/input/events.dart';
import 'package:twk_core/src/input/parser.dart';

List<InputEvent> parse(String s, {bool flush = true}) {
  final p = InputParser();
  return [...p.feed(utf8.encode(s)), if (flush) ...p.flush()];
}

void main() {
  test('plain text, grouped by grapheme', () {
    expect(parse('aя'), [
      const KeyEvent(KeyCode.char, char: 'a'),
      const KeyEvent(KeyCode.char, char: 'я'),
    ]);
    expect(parse('👨\u{200D}👩'), [
      const KeyEvent(KeyCode.char, char: '👨\u{200D}👩'),
    ]);
  });

  test('controls', () {
    expect(parse('\r\t\x7f\x01'), [
      const KeyEvent(KeyCode.enter),
      const KeyEvent(KeyCode.tab),
      const KeyEvent(KeyCode.backspace),
      const KeyEvent(KeyCode.char, char: 'a', modifiers: Mod.ctrl),
    ]);
  });

  test('a character split across reads is not resolved by the timeout', () {
    final p = InputParser();
    expect(p.feed([0xD0]), isEmpty);
    expect(p.hasPending, isFalse, reason: 'no ESC: nothing to time out');
    expect(p.feed([0xB8]), [const KeyEvent(KeyCode.char, char: 'и')]);
  });

  test('overlong UTF-8 is not decoded', () {
    for (final bytes in [
      [0xE0, 0x80, 0x8D], // CR
      [0xF0, 0x80, 0x80, 0x9B], // ESC
      [0xE0, 0x9F, 0xBF], // U+07FF
      [0xF0, 0x8F, 0xBF, 0xBF], // U+FFFF
    ]) {
      final p = InputParser();
      final ev = [...p.feed(bytes), ...p.flush()];
      expect(ev, [
        const KeyEvent(KeyCode.char, char: '\uFFFD'),
      ], reason: '$bytes');
    }
    // the shortest forms still decode
    expect(parse('\u0800\u{10000}'), [
      const KeyEvent(KeyCode.char, char: '\u0800'),
      const KeyEvent(KeyCode.char, char: '\u{10000}'),
    ]);
  });

  test('a terminal whose Backspace sends ^H', () {
    final p = InputParser()..backspaceSendsCtrlH = true;
    expect(p.feed([0x08, 0x7F, 0x1B, 0x08]), [
      const KeyEvent(KeyCode.backspace),
      const KeyEvent(KeyCode.backspace, modifiers: Mod.ctrl),
      const KeyEvent(KeyCode.backspace, modifiers: Mod.alt),
    ]);
  });

  test('two arrows in one read are two events', () {
    expect(parse('\x1b[A\x1b[B'), [
      const KeyEvent(KeyCode.up),
      const KeyEvent(KeyCode.down),
    ]);
  });

  test('a modifier parameter below 1 means no modifiers', () {
    expect(parse('\x1b[1;0A\x1b[1;A'), [
      const KeyEvent(KeyCode.up),
      const KeyEvent(KeyCode.up),
    ]);
  });

  test('modified keys, function keys, tilde keys', () {
    expect(parse('\x1b[1;5C'), [
      const KeyEvent(KeyCode.right, modifiers: Mod.ctrl),
    ]);
    expect(parse('\x1bOP'), [const KeyEvent(KeyCode.f1)]);
    expect(parse('\x1b[15~'), [const KeyEvent(KeyCode.f5)]);
    expect(parse('\x1b[3;2~'), [
      const KeyEvent(KeyCode.delete, modifiers: Mod.shift),
    ]);
    expect(parse('\x1b[Z'), [
      const KeyEvent(KeyCode.tab, modifiers: Mod.shift),
    ]);
    expect(parse('\x1b[1;5Z'), [
      const KeyEvent(KeyCode.tab, modifiers: Mod.ctrl | Mod.shift),
    ], reason: 'what else is held with Shift+Tab, where it is told');
    expect(parse('\x1b[1;3R'), [
      const KeyEvent(KeyCode.f3, modifiers: Mod.alt),
    ]);
  });

  test('alt + key, escape', () {
    expect(parse('\x1bx'), [
      const KeyEvent(KeyCode.char, char: 'x', modifiers: Mod.alt),
    ]);
    expect(parse('\x1b'), [const KeyEvent(KeyCode.escape)]);
    final p = InputParser();
    expect(p.feed([0x1B]), isEmpty, reason: 'lone ESC waits');
    expect(p.hasPending, isTrue);
    expect(p.flush(), [const KeyEvent(KeyCode.escape)]);
  });

  test('a sequence cut off by a pause yields no text', () {
    // the parameters of a cut CSI are not typed text
    expect(parse('\x1b[1;5').whereType<KeyEvent>(), isEmpty);
    expect(parse('\x1b[1;5'), [isA<UnknownSequence>()]);
    // nothing after the introducer: the Alt+key it also is
    expect(parse('\x1b['), [
      const KeyEvent(KeyCode.char, char: '[', modifiers: Mod.alt),
    ]);
    expect(parse('\x1b]'), [
      const KeyEvent(KeyCode.char, char: ']', modifiers: Mod.alt),
    ]);
    expect(parse('\x1bP'), [
      const KeyEvent(KeyCode.char, char: 'P', modifiers: Mod.alt),
    ]);
    expect(parse('\x1b]hello'), [isA<UnknownSequence>()]);
  });

  test('an ESC inside a CSI starts a new sequence', () {
    expect(parse('\x1b[1\x1b[A'), [
      isA<UnknownSequence>(),
      const KeyEvent(KeyCode.up),
    ]);
  });

  test("xterm's modifyOtherKeys: the key typed, a shortcut's letter "
      'unshifted', () {
    expect(
      parse(
        '\x1b[27;5;59~\x1b[27;6;65~\x1b[27;2;65~\x1b[27;5;13~\x1b[27;3;9~',
      ),
      [
        const KeyEvent(KeyCode.char, char: ';', modifiers: Mod.ctrl),
        const KeyEvent(
          KeyCode.char,
          char: 'a',
          modifiers: Mod.ctrl | Mod.shift,
        ),
        const KeyEvent(KeyCode.char, char: 'A'),
        const KeyEvent(KeyCode.enter, modifiers: Mod.ctrl),
        const KeyEvent(KeyCode.tab, modifiers: Mod.alt),
      ],
    );
  });

  test('ESC O followed by something that is not SS3', () {
    expect(parse('\x1bO x'), [
      const KeyEvent(KeyCode.char, char: 'O', modifiers: Mod.alt),
      const KeyEvent(KeyCode.char, char: ' '),
      const KeyEvent(KeyCode.char, char: 'x'),
    ]);
    // the old form of a modified SS3 key
    expect(parse('\x1bO5P'), [
      const KeyEvent(KeyCode.f1, modifiers: Mod.ctrl),
    ]);
    // more digits than a modifier has: no key, and none of what is left
    expect(parse('\x1bO1234Px'), [
      isA<UnknownSequence>().having((e) => '$e', 'text', 'Unknown(ESCO1234P)'),
      const KeyEvent(KeyCode.char, char: 'x'),
    ]);
  });

  test('ESC before a key sequence is Alt (urxvt, Linux console)', () {
    expect(parse('\x1b\x1b[A\x1b\x1bOB'), [
      const KeyEvent(KeyCode.up, modifiers: Mod.alt),
      const KeyEvent(KeyCode.down, modifiers: Mod.alt),
    ]);
    expect(parse('\x1b\x1b'), [
      const KeyEvent(KeyCode.escape, modifiers: Mod.alt),
    ]);
    expect(parse('\x1b\x1b[<0;3;4M'), [
      const KeyEvent(KeyCode.escape),
      isA<MouseEvent>(),
    ]);
  });

  test('a sequence whose parameters arrived is known to have started', () {
    bool started(String s) {
      final p = InputParser()..feed(utf8.encode(s));
      return p.sequenceStarted;
    }

    // could still be Escape, Alt+[ or Alt+Escape: worth a short wait only
    expect(started('\x1b'), isFalse);
    expect(started('\x1b['), isFalse);
    expect(started('\x1b\x1b'), isFalse);
    // parameters arrived: the rest is coming
    expect(started('\x1b[<35;10'), isTrue);
    expect(started('\x1b]11;rgb:'), isTrue);
    expect(started('x'), isFalse);
  });

  test('kitty keyboard protocol', () {
    expect(parse('\x1b[97;5u'), [
      const KeyEvent(KeyCode.char, char: 'a', modifiers: Mod.ctrl),
    ]);
    expect(parse('\x1b[97;1:3u'), [
      const KeyEvent(KeyCode.char, char: 'a', kind: KeyKind.release),
    ]);
    expect(parse('\x1b[13u'), [const KeyEvent(KeyCode.enter)]);
    expect(parse('\x1b[27u'), [const KeyEvent(KeyCode.escape)]);
    // Caps Lock and Num Lock states are not modifiers
    expect(parse('\x1b[1;129A\x1b[27;129u\x1b[97;69u'), [
      const KeyEvent(KeyCode.up),
      const KeyEvent(KeyCode.escape),
      const KeyEvent(KeyCode.char, char: 'a', modifiers: Mod.ctrl),
    ]);
    // keypad and other functional keys use Private Use Area codes
    expect(parse('\x1b[57414u\x1b[57419u\x1b[57399u\x1b[57413;5u'), [
      const KeyEvent(KeyCode.enter),
      const KeyEvent(KeyCode.up),
      const KeyEvent(KeyCode.char, char: '0'),
      const KeyEvent(KeyCode.char, char: '+', modifiers: Mod.ctrl),
    ]);
    for (final code in [57376, 57358, 57428, 57441, 57454]) {
      // F13, Caps Lock, media keys, modifier keys: no KeyCode for them
      expect(parse('\x1b[${code}u').whereType<KeyEvent>(), isEmpty);
    }
    // reply to the protocol query CSI ? u
    expect(parse('\x1b[?1u'), [const KeyboardFlagsReport(1)]);
    expect(parse('\x1b[?u'), [const KeyboardFlagsReport(0)]);
  });

  test('an ESC inside an unterminated string starts a new sequence', () {
    // a truncated OSC reply must not swallow the paste that follows it
    final ev = parse('\x1b]11;rgb:1e1e\x1b[200~hi\x1b[201~\x1b[A');
    expect(ev, hasLength(3));
    expect(ev[0], isA<UnknownSequence>());
    expect(ev.sublist(1), [const PasteEvent('hi'), const KeyEvent(KeyCode.up)]);
    // ST (ESC \) still terminates the string
    expect(parse('\x1b]11;rgb:1e1e/2020/3030\x1b\\'), [
      isA<ColorReport>(),
    ]);
  });

  test('SGR mouse', () {
    expect(parse('\x1b[<0;10;5M'), [const MouseEvent(MouseKind.down, 9, 4)]);
    expect(parse('\x1b[<0;10;5m'), [const MouseEvent(MouseKind.up, 9, 4)]);
    expect(parse('\x1b[<32;11;5M'), [const MouseEvent(MouseKind.drag, 10, 4)]);
    expect(parse('\x1b[<35;11;5M'), [const MouseEvent(MouseKind.move, 10, 4)]);
    expect(parse('\x1b[<65;1;1M'), [
      const MouseEvent(MouseKind.wheelDown, 0, 0),
    ]);
    expect(parse('\x1b[<80;3;4M'), [
      const MouseEvent(MouseKind.wheelUp, 2, 3, modifiers: Mod.ctrl),
    ], reason: 'ctrl+wheel is a wheel event, not a press');
    // side buttons (back, forward)
    expect(parse('\x1b[<128;5;5M\x1b[<129;5;5m\x1b[<160;6;5M'), [
      const MouseEvent(MouseKind.down, 4, 4, button: 8),
      const MouseEvent(MouseKind.up, 4, 4, button: 9),
      const MouseEvent(MouseKind.drag, 5, 4, button: 8),
    ]);
  });

  test("X10 mouse, from a terminal that ignores SGR's: events, not keys", () {
    expect(parse('\x1b[M !!\x1b[M#!!\x1b[MC5%\x1b[Ma"#x'), [
      const MouseEvent(MouseKind.down, 0, 0),
      const MouseEvent(MouseKind.up, 0, 0),
      const MouseEvent(MouseKind.move, 20, 4),
      const MouseEvent(MouseKind.wheelDown, 1, 2),
      const KeyEvent(KeyCode.char, char: 'x'),
    ]);
    // the three bytes waited for; cut off, no keys
    expect(parse('\x1b[M !', flush: false), isEmpty);
    expect(parse('\x1b[M !'), [
      isA<UnknownSequence>().having((e) => '$e', 'text', 'Unknown(ESC[M !)'),
    ]);
  });

  test('bracketed paste (incl. CRLF and split end marker)', () {
    expect(parse('\x1b[200~line1\r\nline2\x1b[201~x'), [
      const PasteEvent('line1\nline2'),
      const KeyEvent(KeyCode.char, char: 'x'),
    ]);
    final p = InputParser();
    final ev = <InputEvent>[
      ...p.feed(utf8.encode('\x1b[200~ab\x1b[2')),
      ...p.feed(utf8.encode('01~')),
    ];
    expect(ev, [const PasteEvent('ab')]);
    expect(parse('\x1b[200~\x1b[A\x1b[201~'), [
      const PasteEvent('\x1b[A'),
    ], reason: 'escape sequences inside a paste are text');
  });

  test('a timeout inside a paste waits for the end marker', () {
    final p = InputParser();
    expect(p.feed(utf8.encode('\x1b[200~abc\x1b[2')), isEmpty);
    // nothing to resolve: the paste isn't over yet
    expect(p.hasPending, isFalse);
    expect(p.flush(), isEmpty);
    expect(p.feed(utf8.encode('01~x\x1b[A')), [
      const PasteEvent('abc'),
      const KeyEvent(KeyCode.char, char: 'x'),
      const KeyEvent(KeyCode.up),
    ]);
  });

  test('endPaste() delivers a paste whose end marker never came', () {
    final p = InputParser();
    expect(p.feed(utf8.encode('\x1b[200~hi\x1b[2')), isEmpty);
    expect(p.inPaste, isTrue);
    expect(p.endPaste(), [const PasteEvent('hi\x1b[2')]);
    expect(p.inPaste, isFalse);
    expect(p.feed(utf8.encode('x')), [const KeyEvent(KeyCode.char, char: 'x')]);
    expect(p.endPaste(), isEmpty, reason: 'no paste open');
  });

  test('replies: DECRPM, DA1, OSC 11 and 4, in-band resize, CPR', () {
    expect(parse('\x1b[?2026;2\$y'), [const ModeReport(2026, 2)]);
    // 4 = permanently reset: known, but can't be turned on
    expect(
      [for (var v = 0; v <= 4; v++) ModeReport(2026, v).supported],
      [
        false,
        true,
        true,
        true,
        false,
      ],
    );
    final da = parse('\x1b[?62;22c').single as DeviceAttributes;
    expect(da.params, [62, 22]);
    final c1 = parse('\x1b]11;rgb:1e1e/2020/3030\x07').single as ColorReport;
    expect(c1.rgb, 0x1e2030);
    final c2 = parse('\x1b]11;rgb:ff/00/80\x1b\\').single as ColorReport;
    expect(c2.rgb, 0xff0080);
    final c4 = parse('\x1b]4;12;rgb:8989/b4b4/fafa\x1b\\').single;
    expect(
      c4,
      isA<ColorReport>()
          .having((c) => c.which, 'which', 4)
          .having((c) => c.index, 'index', 12)
          .having((c) => c.rgb, 'rgb', 0x89b4fa),
    );
    expect((c1.which, c1.index), (11, 0));
    expect(parse('\x1b]4;256;rgb:ff/ff/ff\x07').single, isA<UnknownSequence>());
    expect(parse('\x1b[48;40;120;800;1600t'), [const ResizeEvent(120, 40)]);
    final p = InputParser()..expectCursorReport = true;
    final cpr = p.feed(utf8.encode('\x1b[5;12R')).single as CursorReport;
    expect((cpr.x, cpr.y), (11, 4));
  });

  test('as many cursor reports as are expected, in one read, then F3 with '
      'modifiers again', () {
    final p = InputParser()..cursorReportsExpected = 2;
    expect(p.expectCursorReport, isTrue);
    final events = p.feed(utf8.encode('\x1b[5;1R\x1b[1;2R\x1b[1;2R'));
    expect(events.take(2), everyElement(isA<CursorReport>()));
    expect(events.last, const KeyEvent(KeyCode.f3, modifiers: Mod.shift));
    expect(p.expectCursorReport, isFalse);
  });

  test('color scheme reports (DEC mode 2031)', () {
    expect(parse('\x1b[?997;1n\x1b[?997;2n'), [
      const ColorSchemeReport(Brightness.dark),
      const ColorSchemeReport(Brightness.light),
    ]);
    for (final other in ['?997;0n', '?997;3n', '?997n', '?998;1n', '997;1n']) {
      expect(
        parse('\x1b[$other').single,
        isA<UnknownSequence>(),
        reason: other,
      );
    }
  });

  test('focus', () {
    expect(parse('\x1b[I\x1b[O'), [
      const FocusEvent(true),
      const FocusEvent(false),
    ]);
  });

  test('any split of the byte stream yields the same events', () {
    final stream = [
      'ab\x1b[1;5Aя🧪\x1b[<0;3;4M\x1b[200~p\r\nq\x1b[201~',
      '\x1bOQ\x1b[97;5u\x1b]11;rgb:10/20/30\x1b\\\x1b[?2027;1\$y',
      '👨\u{200D}👩\x1b[3~\x1bz\x1b[I\x1b[?997;2n\r',
    ].join();
    final bytes = utf8.encode(stream);
    final whole = parse(stream);
    // A read boundary inside a grapheme cluster legitimately splits it into
    // several char events (the joined text is the same), so plain text is
    // compared as one concatenated token.
    String fmt(List<InputEvent> e) {
      final out = <String>[];
      final text = StringBuffer();
      for (final x in e) {
        if (x is KeyEvent && x.code == KeyCode.char && x.modifiers == 0) {
          text.write(x.char);
          continue;
        }
        if (text.isNotEmpty) {
          out.add('text($text)');
          text.clear();
        }
        out.add(switch (x) {
          ColorReport(:final rgb) => 'color($rgb)',
          ModeReport(:final mode, :final value) => 'mode($mode,$value)',
          FocusEvent(:final focused) => 'focus($focused)',
          _ => x.toString(),
        });
      }
      if (text.isNotEmpty) {
        out.add('text($text)');
      }
      return out.join('|');
    }

    // byte by byte
    final p = InputParser();
    final one = <InputEvent>[
      for (final b in bytes) ...p.feed([b]),
      ...p.flush(),
    ];
    expect(fmt(one), fmt(whole));
    // random chunkings
    final rnd = Random(3);
    for (var t = 0; t < 300; t++) {
      final q = InputParser();
      final ev = <InputEvent>[];
      var i = 0;
      while (i < bytes.length) {
        final n = 1 + rnd.nextInt(7);
        final end = min(bytes.length, i + n);
        ev.addAll(q.feed(bytes.sublist(i, end)));
        i = end;
      }
      ev.addAll(q.flush());
      expect(fmt(ev), fmt(whole), reason: 'chunking #$t');
    }
  });

  test('CSI parameters: the edge of an int, zeros, sub- and many', () {
    // the largest int is a number; one more is no sequence the parser maps
    // (the numbers parsed: their literals aren't ints on the web)
    final largest = int.parse('9223372036854775807');
    expect(parse('\x1b[<0;$largest;1M'), [
      MouseEvent(MouseKind.down, largest - 1, 0),
    ]);
    const tooLarge = '\x1b[<0;9223372036854775808;1M';
    expect(parse(tooLarge), [isA<UnknownSequence>()]);
    expect(
      (parse(tooLarge).single as UnknownSequence).bytes,
      tooLarge.codeUnits,
    );
    expect(parse('\x1b[1;99999999999999999999A'), [isA<UnknownSequence>()]);
    // leading zeros, and long numbers that are ints
    expect(parse('\x1b[<0;0000000000000000000000012;003M'), [
      const MouseEvent(MouseKind.down, 11, 2),
    ]);
    expect(parse('\x1b[<0;1234567890123456789;0000001234567890123456M'), [
      MouseEvent(
        MouseKind.down,
        int.parse('1234567890123456788'),
        1234567890123455,
      ),
    ]);
    // empty parameters are 0, sub-parameters are read where they are
    expect(parse('\x1b[;5A'), [
      const KeyEvent(KeyCode.up, modifiers: Mod.ctrl),
    ]);
    expect(parse('\x1b[1;5:3A'), [
      const KeyEvent(KeyCode.up, modifiers: Mod.ctrl, kind: KeyKind.release),
    ]);
    expect(parse('\x1b[1;:2A'), [
      const KeyEvent(KeyCode.up, kind: KeyKind.repeat),
    ]);
    expect(parse('\x1b[97:65;2u'), [const KeyEvent(KeyCode.char, char: 'A')]);
    expect(parse('\x1b[97:65:97;2u'), [
      const KeyEvent(KeyCode.char, char: 'A'),
    ]);
    expect(parse('\x1b[97;2u'), [
      const KeyEvent(KeyCode.char, char: 'a', modifiers: Mod.shift),
    ]);
    expect(parse('\x1b[97;1;104:105u'), [
      const KeyEvent(KeyCode.char, char: 'hi'),
    ]);
    // more parameters than a short sequence has, then a short one again
    final many = List.generate(40, (i) => i);
    final da = parse('\x1b[?${many.join(';')}c').single as DeviceAttributes;
    expect(da.params, many);
    expect((parse('\x1b[?;c').single as DeviceAttributes).params, [0, 0]);
    final p = InputParser();
    expect(
      (p.feed(utf8.encode('\x1b[?${many.join(';')}c')).single
              as DeviceAttributes)
          .params,
      many,
    );
    expect(p.feed(utf8.encode('\x1b[1;3B')), [
      const KeyEvent(KeyCode.down, modifiers: Mod.alt),
    ]);
  });

  test('pastes larger than the paste buffer, and values that are no byte', () {
    final p = InputParser();
    final big = 'x' * 100000;
    expect(p.feed(utf8.encode('\x1b[200~$big\x1b[201~')), [PasteEvent(big)]);
    expect(p.feed(utf8.encode('\x1b[200~ab\x1b[201~')), [
      const PasteEvent('ab'),
    ]);
    // a value past 255 decodes as a malformed byte does
    expect(
      p.feed([
        ...'\x1b[200~a'.codeUnits,
        0x4E2D,
        0xE4,
        300,
        ...'b\x1b[201~'.codeUnits,
      ]),
      [const PasteEvent('a���b')],
    );
  });

  test('garbage never throws', () {
    final rnd = Random(9);
    for (var t = 0; t < 2000; t++) {
      final junk = List<int>.generate(rnd.nextInt(40), (_) => rnd.nextInt(256));
      InputParser()
        ..feed(junk)
        ..flush();
    }
    for (final hex in ['f' * 16, 'f' * 17, '0' * 40]) {
      expect(
        () => parse('\x1b]11;rgb:$hex/0/0\x07'),
        returnsNormally,
        reason: 'OSC 11 with ${hex.length} hex digits',
      );
    }
    // malformed sequences built from the pieces real ones are made of
    const pieces = [
      '\x1b[',
      '\x1b]',
      '\x1bP',
      '\x1bO',
      '\x1b',
      '\x07',
      '\x1b\\',
      '11;rgb:',
      '10;rgb:',
      '/',
      ';',
      ':',
      '?',
      '<',
      '>',
      r'$y',
      'u',
      'M',
      'm',
      '~',
      'R',
      't',
      'c',
      'A',
      'I',
      '200~',
      '201~',
      '0',
      '1',
      '9',
      '99999999999999999999',
      'ffffffffffffffffffff',
      'ff',
      '-',
      'я',
    ];
    for (var t = 0; t < 5000; t++) {
      final s = [
        for (var k = rnd.nextInt(12); k > 0; k--)
          pieces[rnd.nextInt(pieces.length)],
      ].join();
      expect(() => parse(s), returnsNormally, reason: jsonEncode(s));
    }
  });
}
