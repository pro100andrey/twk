import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_term/twk_term.dart';

import 'support.dart';

void main() {
  group('keys', () {
    String? key(
      KeyCode code, {
      String char = '',
      int mods = 0,
      bool cursorKeys = false,
      bool newLine = false,
    }) => keySequence(
      KeyEvent(code, char: char, modifiers: mods),
      cursorKeys: cursorKeys,
      newLine: newLine,
    )?.replaceAll('\x1b', r'\e');

    test('characters as typed, with Ctrl and Alt', () {
      expect(key(KeyCode.char, char: 'é'), 'é');
      expect(key(KeyCode.char, char: 'c', mods: Mod.ctrl), '\x03');
      expect(key(KeyCode.char, char: 'C', mods: Mod.ctrl), '\x03');
      expect(key(KeyCode.char, char: ' ', mods: Mod.ctrl), '\x00');
      expect(key(KeyCode.char, char: '[', mods: Mod.ctrl), r'\e');
      expect(key(KeyCode.char, char: '/', mods: Mod.ctrl), '\x1f');
      expect(key(KeyCode.char, char: '?', mods: Mod.ctrl), '\x7f');
      expect(key(KeyCode.char, char: 'x', mods: Mod.alt), r'\ex');
      expect(key(KeyCode.char, char: 'x', mods: Mod.alt | Mod.ctrl), '\\e\x18');
      expect(key(KeyCode.char, char: '1', mods: Mod.ctrl), '1');
      // Shift with a letter, as the kitty protocol reports it
      expect(key(KeyCode.char, char: 'a', mods: Mod.shift), 'A');
      expect(key(KeyCode.char, char: '1', mods: Mod.shift), '1');
    });

    test('Enter, Tab, Backspace and Escape', () {
      expect(key(KeyCode.enter), '\r');
      expect(key(KeyCode.enter, newLine: true), '\r\n');
      expect(key(KeyCode.enter, mods: Mod.alt), '\\e\r');
      expect(key(KeyCode.tab), '\t');
      expect(key(KeyCode.tab, mods: Mod.shift), r'\e[Z');
      expect(key(KeyCode.backspace), '\x7f');
      expect(key(KeyCode.backspace, mods: Mod.ctrl), '\x08');
      expect(key(KeyCode.backspace, mods: Mod.alt), '\\e\x7f');
      expect(key(KeyCode.escape), r'\e');
    });

    test('cursor keys, in normal and application mode, with modifiers', () {
      expect(key(KeyCode.up), r'\e[A');
      expect(key(KeyCode.up, cursorKeys: true), r'\eOA');
      expect(key(KeyCode.left, mods: Mod.ctrl), r'\e[1;5D');
      expect(key(KeyCode.right, mods: Mod.shift, cursorKeys: true), r'\e[1;2C');
      expect(key(KeyCode.home), r'\e[H');
      expect(key(KeyCode.end, cursorKeys: true), r'\eOF');
    });

    test('editing and function keys', () {
      expect(key(KeyCode.insert), r'\e[2~');
      expect(key(KeyCode.delete, mods: Mod.alt), r'\e[3;3~');
      expect(key(KeyCode.pageUp), r'\e[5~');
      expect(key(KeyCode.pageDown), r'\e[6~');
      expect(key(KeyCode.f1), r'\eOP');
      expect(key(KeyCode.f4, mods: Mod.shift), r'\e[1;2S');
      expect(key(KeyCode.f5), r'\e[15~');
      expect(key(KeyCode.f12, mods: Mod.ctrl), r'\e[24;5~');
    });

    test('a release sends nothing', () {
      expect(
        keySequence(const KeyEvent(KeyCode.up, kind: KeyKind.release)),
        isNull,
      );
    });

    test('the emulator sends keys in the modes the program set', () {
      final r = Rig();
      expect(r.t.sendKey(const KeyEvent(KeyCode.up)), isTrue);
      r.feed(r'\e[?1h');
      r.t.sendKey(const KeyEvent(KeyCode.up));
      r.t.sendText('hé');
      expect(r.takeSent(), r'\e[A\eOAhé');
    });
  });

  group('kitty keys', () {
    String? key(
      int flags,
      KeyCode code, {
      String char = '',
      int mods = 0,
      KeyKind kind = KeyKind.press,
    }) => kittyKeySequence(
      KeyEvent(code, char: char, modifiers: mods, kind: kind),
      flags,
    )?.replaceAll('\x1b', r'\e');

    test('disambiguated: text as typed, modified keys as CSI u', () {
      expect(key(1, KeyCode.char, char: 'a'), 'a');
      expect(key(1, KeyCode.char, char: 'A'), 'A');
      expect(key(1, KeyCode.char, char: 'a', mods: Mod.shift), 'A');
      expect(key(1, KeyCode.char, char: 'a', mods: Mod.ctrl), r'\e[97;5u');
      expect(key(1, KeyCode.char, char: 'A', mods: Mod.ctrl), r'\e[97;6u');
      expect(key(1, KeyCode.char, char: 'x', mods: Mod.alt), r'\e[120;3u');
      expect(key(1, KeyCode.char, char: 'é', mods: Mod.superKey), r'\e[233;9u');
      expect(key(1, KeyCode.escape), r'\e[27u');
      expect(key(1, KeyCode.enter), '\r');
      expect(key(1, KeyCode.enter, mods: Mod.ctrl), r'\e[13;5u');
      expect(key(1, KeyCode.tab), '\t');
      expect(key(1, KeyCode.tab, mods: Mod.shift), r'\e[9;2u');
      expect(key(1, KeyCode.backspace), '\x7f');
      expect(key(1, KeyCode.backspace, mods: Mod.alt), r'\e[127;3u');
    });

    test('functional keys keep their legacy forms, F3 its own', () {
      expect(key(1, KeyCode.up), r'\e[A');
      expect(key(1, KeyCode.up, mods: Mod.ctrl), r'\e[1;5A');
      expect(key(1, KeyCode.home), r'\e[H');
      expect(key(1, KeyCode.delete), r'\e[3~');
      expect(key(1, KeyCode.pageDown, mods: Mod.shift), r'\e[6;2~');
      expect(key(1, KeyCode.f1), r'\e[P');
      expect(key(1, KeyCode.f3), r'\e[13~');
      expect(key(1, KeyCode.f12), r'\e[24~');
    });

    test('event types: repeats and releases', () {
      expect(key(1, KeyCode.char, char: 'a', kind: KeyKind.release), isNull);
      expect(key(3, KeyCode.char, char: 'a', kind: KeyKind.repeat), 'a');
      expect(
        key(3, KeyCode.char, char: 'a', kind: KeyKind.release),
        r'\e[97;1:3u',
      );
      expect(
        key(3, KeyCode.char, char: 'a', mods: Mod.ctrl, kind: KeyKind.repeat),
        r'\e[97;5:2u',
      );
      expect(key(3, KeyCode.up, kind: KeyKind.release), r'\e[1;1:3A');
      expect(key(3, KeyCode.enter, kind: KeyKind.release), isNull);
      expect(key(11, KeyCode.enter, kind: KeyKind.release), r'\e[13;1:3u');
    });

    test('all keys as escape codes, with alternates and text', () {
      expect(key(8, KeyCode.char, char: 'a'), r'\e[97u');
      expect(key(8, KeyCode.enter), r'\e[13u');
      expect(key(8, KeyCode.escape), r'\e[27u');
      expect(key(12, KeyCode.char, char: 'A'), r'\e[97:65;2u');
      expect(key(24, KeyCode.char, char: 'a'), r'\e[97;;97u');
      expect(key(28, KeyCode.char, char: 'A'), r'\e[97:65;2;65u');
      expect(key(24, KeyCode.char, char: 'a', mods: Mod.ctrl), r'\e[97;5u');
    });

    test('the program pushes, sets, asks for and pops its flags', () {
      final r = Rig();
      void press(KeyEvent key) => r.t.sendKey(key);
      press(const KeyEvent(KeyCode.escape));
      r.feed(r'\e[?u\e[>1u\e[?u');
      press(const KeyEvent(KeyCode.escape));
      r.feed(r'\e[=8;2u\e[?u');
      press(const KeyEvent(KeyCode.char, char: 'a'));
      r.feed(r'\e[=1;3u\e[?u\e[<u\e[?u');
      press(const KeyEvent(KeyCode.escape));
      expect(
        r.takeSent(),
        r'\e\e[?0u\e[?1u\e[27u\e[?9u\e[97u\e[?8u\e[?0u\e',
      );
    });

    test('each screen has flags of its own, which a reset clears', () {
      final r = Rig()..feed(r'\e[>1u\e[?1049h');
      expect(r.t.keyboardFlags, 0);
      r.feed(r'\e[>3u\e[>8u');
      expect(r.t.keyboardFlags, 8);
      r.feed(r'\e[<5u');
      expect(r.t.keyboardFlags, 0);
      r.feed(r'\e[>3u\e[?1049l');
      expect(r.t.keyboardFlags, 1);
      r.feed(r'\ec');
      expect(r.t.keyboardFlags, 0);
      // the stack keeps the newest 16
      for (var i = 0; i < 20; i++) {
        r.feed('\x1b[>${i % 2 + 1}u');
      }
      r.feed(r'\e[<15u');
      expect(r.t.keyboardFlags, 1);
      r.feed(r'\e[<u');
      expect(r.t.keyboardFlags, 0);
    });
  });

  group('mouse', () {
    String? report(
      MouseEvent e,
      MouseProtocol p, [
      MouseEncoding enc = MouseEncoding.sgr,
    ]) {
      final bytes = mouseSequence(e, p, enc);
      return bytes == null
          ? null
          : String.fromCharCodes(bytes).replaceAll('\x1b', r'\e');
    }

    const down = MouseEvent(MouseKind.down, 4, 2);
    const up = MouseEvent(MouseKind.up, 4, 2);

    test('SGR reports with modifiers and releases', () {
      expect(report(down, MouseProtocol.buttons), r'\e[<0;5;3M');
      expect(report(up, MouseProtocol.buttons), r'\e[<0;5;3m');
      expect(
        report(
          const MouseEvent(
            MouseKind.down,
            0,
            0,
            button: 2,
            modifiers: Mod.ctrl,
          ),
          MouseProtocol.buttons,
        ),
        r'\e[<18;1;1M',
      );
      expect(
        report(
          const MouseEvent(MouseKind.wheelUp, 0, 0),
          MouseProtocol.buttons,
        ),
        r'\e[<64;1;1M',
      );
      expect(
        report(
          const MouseEvent(MouseKind.down, 0, 0, button: 8),
          MouseProtocol.buttons,
        ),
        r'\e[<128;1;1M',
      );
    });

    test('the wheel across, Shift and Alt; a button it has no code for '
        'reports nothing', () {
      MouseEvent at(MouseKind kind, {int button = 0, int modifiers = 0}) =>
          MouseEvent(kind, 0, 0, button: button, modifiers: modifiers);
      expect(
        report(at(MouseKind.wheelLeft), MouseProtocol.buttons),
        r'\e[<66;1;1M',
      );
      expect(
        report(
          at(MouseKind.wheelRight, modifiers: Mod.shift),
          MouseProtocol.buttons,
        ),
        r'\e[<71;1;1M',
      );
      expect(
        report(at(MouseKind.down, modifiers: Mod.alt), MouseProtocol.buttons),
        r'\e[<8;1;1M',
      );
      expect(
        report(at(MouseKind.down, button: 3), MouseProtocol.buttons),
        isNull,
      );
    });

    test('motion only as the protocol asks', () {
      const drag = MouseEvent(MouseKind.drag, 1, 1);
      const move = MouseEvent(MouseKind.move, 1, 1);
      expect(report(drag, MouseProtocol.buttons), isNull);
      expect(report(drag, MouseProtocol.drags), r'\e[<32;2;2M');
      expect(report(move, MouseProtocol.drags), isNull);
      expect(report(move, MouseProtocol.motion), r'\e[<35;2;2M');
      expect(report(up, MouseProtocol.x10), isNull);
      expect(
        report(
          const MouseEvent(MouseKind.down, 0, 0, modifiers: Mod.shift),
          MouseProtocol.x10,
        ),
        r'\e[<0;1;1M',
        reason: 'no modifiers in X10',
      );
    });

    test('X10, UTF-8 and urxvt encodings', () {
      expect(
        mouseSequence(down, MouseProtocol.buttons, MouseEncoding.x10),
        [0x1B, 0x5B, 0x4D, 32, 37, 35],
      );
      expect(report(up, MouseProtocol.buttons, MouseEncoding.x10), r'\e[M#%#');
      expect(
        mouseSequence(
          const MouseEvent(MouseKind.down, 300, 0),
          MouseProtocol.buttons,
          MouseEncoding.x10,
        ),
        isNull,
      );
      expect(
        mouseSequence(
          const MouseEvent(MouseKind.down, 300, 0),
          MouseProtocol.buttons,
          MouseEncoding.utf8,
        ),
        [0x1B, 0x5B, 0x4D, 32, 0xC5, 0x8D, 33],
      );
      expect(
        report(down, MouseProtocol.buttons, MouseEncoding.urxvt),
        r'\e[32;5;3M',
      );
    });

    test('the emulator reports only what the program asked for', () {
      final r = Rig();
      expect(r.t.sendMouse(down), isFalse);
      r.feed(r'\e[?1000;1006h');
      expect(r.t.sendMouse(down), isTrue);
      expect(r.takeSent(), r'\e[<0;5;3M');
    });

    test('the wheel goes as arrow keys on the alternate screen (1007)', () {
      final r = fed(r'\e[?1007h');
      const wheel = MouseEvent(MouseKind.wheelDown, 0, 0);
      expect(r.t.sendMouse(wheel), isFalse);
      r.feed(r'\e[?1049h\e[?1h');
      expect(r.t.sendMouse(wheel), isTrue);
      expect(r.takeSent(), r'\eOB');
    });
  });

  group('paste and focus', () {
    test('line breaks become CR, bracketed when asked', () {
      expect(pasteSequence('a\nb\r\nc', bracketed: false), 'a\rb\rc');
      expect(
        pasteSequence('x\x1b[201~y', bracketed: true),
        '\x1b[200~xy\x1b[201~',
      );
      final r = Rig();
      r.t.sendPaste('a\n');
      r
        ..feed(r'\e[?2004h')
        ..t.sendPaste('b');
      expect(r.takeSent(), 'a\r\\e[200~b\\e[201~');
    });

    test('focus changes go when the program asked for them', () {
      final r = Rig();
      expect(r.t.sendFocus(focused: true), isFalse);
      r.feed(r'\e[?1004h');
      r.t
        ..sendFocus(focused: true)
        ..sendFocus(focused: false);
      expect(r.takeSent(), r'\e[I\e[O');
    });
  });
}
