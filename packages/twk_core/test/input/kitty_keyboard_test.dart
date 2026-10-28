// What kitty's keyboard protocol sends under each of its flags, decoded:
// repeats and releases (2) as a key's kind, of `CSI u` keys and of keys in
// their legacy form alike; every key as an escape sequence (8) with the
// text it types (16) or, with Shift, its shifted key (4) as the text typed
// without those flags is, Shift taken into it; a shortcut as its
// unshifted key, modifiers kept. The sequences are kitty's, as
// packages/twk_term's emulator writes them.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/src/input/events.dart';
import 'package:twk_core/src/input/parser.dart';

List<InputEvent> parse(String s) {
  final p = InputParser();
  return [...p.feed(utf8.encode(s)), ...p.flush()];
}

KeyEvent key(
  KeyCode code, {
  String char = '',
  int mods = 0,
  KeyKind kind = KeyKind.press,
}) => KeyEvent(code, char: char, modifiers: mods, kind: kind);

KeyEvent char(String c, {int mods = 0, KeyKind kind = KeyKind.press}) =>
    key(KeyCode.char, char: c, mods: mods, kind: kind);

const KeyKind repeat = KeyKind.repeat;
const KeyKind release = KeyKind.release;

void main() {
  group('event types (flag 2)', () {
    test('a key typing text: pressed and repeated as its text, released as '
        'CSI u', () {
      expect(parse('aa\x1b[97;1:3u'), [
        char('a'),
        char('a'),
        char('a', kind: release),
      ]);
      // Shift+A: its release is the letter with Shift
      expect(parse('A\x1b[97;2:3u'), [
        char('A'),
        char('a', mods: Mod.shift, kind: release),
      ]);
      expect(parse('\x1b[97;5u\x1b[97;5:2u\x1b[97;5:3u\x1b[97;5:1u'), [
        char('a', mods: Mod.ctrl),
        char('a', mods: Mod.ctrl, kind: repeat),
        char('a', mods: Mod.ctrl, kind: release),
        char('a', mods: Mod.ctrl),
      ]);
    });

    test('keys in their legacy form, the type after the modifiers', () {
      expect(
        parse(
          '\x1b[1;1:2A\x1b[1;1:3A\x1b[1;3:3D\x1b[3;1:2~\x1b[6;5:3~'
          '\x1b[1;1:3P\x1b[13;1:3~\x1b[15;1:2~\x1b[1;1:3H\x1b[1;1:3F',
        ),
        [
          key(KeyCode.up, kind: repeat),
          key(KeyCode.up, kind: release),
          key(KeyCode.left, mods: Mod.alt, kind: release),
          key(KeyCode.delete, kind: repeat),
          key(KeyCode.pageDown, mods: Mod.ctrl, kind: release),
          key(KeyCode.f1, kind: release),
          key(KeyCode.f3, kind: release),
          key(KeyCode.f5, kind: repeat),
          key(KeyCode.home, kind: release),
          key(KeyCode.end, kind: release),
        ],
      );
    });

    test('Enter, Tab, Backspace and Escape as CSI u, and the keypad', () {
      expect(
        parse(
          '\x1b[13;1:3u\x1b[9;1:2u\x1b[127;1:3u\x1b[27;1:3u\x1b[57414;1:3u'
          '\x1b[57399;1:2u',
        ),
        [
          key(KeyCode.enter, kind: release),
          key(KeyCode.tab, kind: repeat),
          key(KeyCode.backspace, kind: release),
          key(KeyCode.escape, kind: release),
          key(KeyCode.enter, kind: release),
          char('0', kind: repeat),
        ],
      );
    });

    test('a type out of range is a press; Caps Lock is no modifier', () {
      expect(parse('\x1b[97;1:9u\x1b[97;65:3u\x1b[1;129:2B'), [
        char('a'),
        char('a', kind: release),
        key(KeyCode.down, kind: repeat),
      ]);
    });
  });

  group('every key as an escape sequence (flag 8)', () {
    test('with the text it types (16): the text, Shift taken into it', () {
      expect(
        parse(
          '\x1b[97;;97u\x1b[97;2;65u\x1b[49;2;33u\x1b[97;65;65u\x1b[32;;32u'
          '\x1b[1089;;1089u',
        ),
        [char('a'), char('A'), char('!'), char('A'), char(' '), char('с')],
      );
      // a repeat comes with its text, a release without
      expect(parse('\x1b[97;2:2;65u\x1b[97;2:3u'), [
        char('A', kind: repeat),
        char('a', mods: Mod.shift, kind: release),
      ]);
      // text of several code points: a letter and its combining accent
      expect(parse('\x1b[101;;101:769u'), [char('é')]);
    });

    test('with its shifted key (4): the text, where Shift is held', () {
      expect(parse('\x1b[97:65;2u\x1b[49:33;2:2u\x1b[97:65;2:3u'), [
        char('A'),
        char('!', kind: repeat),
        char('A', kind: release),
      ]);
      // the text, where it comes too, is what the key types
      expect(parse('\x1b[97:65;2;65u'), [char('A')]);
      // no Shift: the shifted key types nothing
      expect(parse('\x1b[97:65u'), [char('a')]);
    });

    test('without either, Shift and the unshifted key', () {
      expect(parse('\x1b[97u\x1b[97;2u\x1b[49;2u'), [
        char('a'),
        char('a', mods: Mod.shift),
        char('1', mods: Mod.shift),
      ]);
    });

    test('a shortcut is its unshifted key, modifiers kept, whatever its '
        'text or shifted key, and the base layout key is not decoded', () {
      expect(
        parse('\x1b[97:65;6u\x1b[97;3;97u\x1b[1089::99;5u\x1b[97:65:97;10u'),
        [
          char('a', mods: Mod.ctrl | Mod.shift),
          char('a', mods: Mod.alt),
          char('с', mods: Mod.ctrl),
          char('a', mods: Mod.superKey | Mod.shift),
        ],
      );
    });

    test('text that is no character falls back to the key', () {
      expect(
        parse('\x1b[97;2;7u\x1b[97;2;65:155u\x1b[97;2;55296u\x1b[97:9;2u'),
        [
          char('a', mods: Mod.shift),
          char('a', mods: Mod.shift),
          char('a', mods: Mod.shift),
          char('a', mods: Mod.shift),
        ],
      );
      // an empty text field is none
      expect(parse('\x1b[97;2;u'), [char('a', mods: Mod.shift)]);
    });

    test('Enter, Tab and Backspace come as CSI u; modifier keys alone '
        'make no key', () {
      expect(parse('\x1b[13u\x1b[9;2u\x1b[127;5u\x1b[13;1:3u'), [
        key(KeyCode.enter),
        key(KeyCode.tab, mods: Mod.shift),
        key(KeyCode.backspace, mods: Mod.ctrl),
        key(KeyCode.enter, kind: release),
      ]);
      // left Shift, right Control: pressed, then released
      expect(
        parse('\x1b[57441;2u\x1b[57441;1:3u\x1b[57448;5u\x1b[57448;1:3u')
            .whereType<KeyEvent>(),
        isEmpty,
      );
    });
  });

  test('press is the type without one', () {
    expect(
      parse('\x1b[97;5u').single,
      const KeyEvent(KeyCode.char, char: 'a', modifiers: Mod.ctrl),
    );
    expect(
      (parse('\x1b[97;5u').single as KeyEvent).kind,
      KeyKind.press,
    );
  });
}
