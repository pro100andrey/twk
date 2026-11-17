// kitty's keyboard protocol as the webview speaks it (core/kitty_keyboard.ts):
// the flags' stacks, and the keys disambiguation encodes.
import * as assert from 'node:assert/strict';

import { KeyPress, KittyKeyboard, encodeKey } from '../../../core/kitty_keyboard';

const press = (key: string, code: string, mods: Partial<Pick<KeyPress, 'ctrl' | 'alt' | 'shift' | 'meta'>> = {}): KeyPress => ({
  key,
  code,
  ctrl: false,
  alt: false,
  shift: false,
  meta: false,
  ...mods,
});

describe("kitty's keyboard protocol", () => {
  it('a stack of flags for each screen: pushed, popped, set; told back as done', () => {
    const k = new KittyKeyboard();
    assert.equal(k.query('alternate'), '\x1b[?0u');
    k.push('alternate', 1);
    assert.equal(k.flags('alternate'), 1);
    assert.equal(k.flags('normal'), 0, 'the other screen its own');
    k.push('alternate', 0b111111);
    assert.equal(k.query('alternate'), '\x1b[?31u', 'all five done, what is no flag dropped');
    k.pop('alternate');
    assert.equal(k.flags('alternate'), 1);
    k.pop('alternate', 5);
    assert.equal(k.flags('alternate'), 0, 'popping more than pushed empties it');
    k.set('normal', 1);
    assert.equal(k.flags('normal'), 1);
    k.set('normal', 1, 3);
    assert.equal(k.flags('normal'), 0, 'reset');
    k.set('normal', 1, 2);
    assert.equal(k.flags('normal'), 1, 'set');
    k.set('normal', 10, 2);
    assert.equal(k.flags('normal'), 11, 'set, the others kept');
    k.set('normal', 8, 3);
    assert.equal(k.flags('normal'), 3, 'reset, the others kept');
    k.set('normal', 20);
    assert.equal(k.flags('normal'), 20, 'replaced');
    k.reset();
    assert.equal(k.flags('normal'), 0);
    assert.equal(k.flags('alternate'), 0);
    for (let i = 0; i < 20; i++) {
      k.push('normal', 1);
    }
    for (let i = 0; i < 16; i++) {
      k.pop('normal');
    }
    assert.equal(k.flags('normal'), 0, 'sixteen at most');
  });

  it('with disambiguation: Escape, Ctrl and Alt keys as CSI u, modified Enter, Tab and Backspace too', () => {
    const d = (p: KeyPress) => encodeKey(p, 1);
    assert.equal(d(press('Escape', 'Escape')), '\x1b[27u');
    assert.equal(d(press('Escape', 'Escape', { shift: true })), '\x1b[27;2u');
    assert.equal(d(press('c', 'KeyC', { ctrl: true })), '\x1b[99;5u');
    assert.equal(d(press('A', 'KeyA', { alt: true, shift: true })), '\x1b[97;4u');
    assert.equal(d(press('å', 'KeyA', { alt: true })), '\x1b[97;3u', 'by where the key is: macOS Option types another letter');
    assert.equal(d(press('1', 'Digit1', { ctrl: true, alt: true })), '\x1b[49;7u');
    assert.equal(d(press(' ', 'Space', { ctrl: true })), '\x1b[32;5u');
    assert.equal(d(press('/', 'Slash', { ctrl: true })), '\x1b[47;5u');
    assert.equal(d(press('Enter', 'Enter', { ctrl: true })), '\x1b[13;5u');
    assert.equal(d(press('Tab', 'Tab', { shift: true })), '\x1b[9;2u');
    assert.equal(d(press('Backspace', 'Backspace', { alt: true })), '\x1b[127;3u');
  });

  it("leaves to xterm.js what it sends as kitty does: text, Enter, Tab, Backspace alone, arrows and function keys; Meta's to VS Code; all with no flags", () => {
    const d = (p: KeyPress, flags = 1) => encodeKey(p, flags);
    for (const p of [
      press('a', 'KeyA'),
      press('A', 'KeyA', { shift: true }),
      press('!', 'Digit1', { shift: true }),
      press('Enter', 'Enter'),
      press('Tab', 'Tab'),
      press('Backspace', 'Backspace'),
      press('ArrowUp', 'ArrowUp', { ctrl: true }),
      press('F5', 'F5', { alt: true }),
      press('Control', 'ControlLeft', { ctrl: true }),
      press('p', 'KeyP', { meta: true }),
      press('p', 'KeyP', { meta: true, ctrl: true }),
    ]) {
      assert.equal(d(p), undefined, JSON.stringify(p));
    }
    assert.equal(d(press('Escape', 'Escape'), 0), undefined, 'none pushed: legacy');
    assert.equal(d(press('c', 'KeyC', { ctrl: true }), 0), undefined);
  });

  describe('flag 2, event types', () => {
    const ev = (p: KeyPress, type: 'press' | 'repeat' | 'release', flags = 3) => encodeKey({ ...p, type }, flags);

    it('a release and a repeat of a key that is an escape code, in the modifiers field', () => {
      const c = press('c', 'KeyC', { ctrl: true });
      assert.equal(ev(c, 'press'), '\x1b[99;5u');
      assert.equal(ev(c, 'repeat'), '\x1b[99;5:2u');
      assert.equal(ev(c, 'release'), '\x1b[99;5:3u');
      const esc = press('Escape', 'Escape');
      assert.equal(ev(esc, 'press'), '\x1b[27u');
      assert.equal(ev(esc, 'release'), '\x1b[27;1:3u', 'no modifiers still the field: 1');
      assert.equal(ev(press('Enter', 'Enter', { ctrl: true }), 'release'), '\x1b[13;5:3u');
    });

    it('a release of a key that types text is CSI u, a press and a repeat of it its text; Shift in the modifiers, the key by its lower case', () => {
      const a = press('a', 'KeyA');
      assert.equal(ev(a, 'press'), undefined);
      assert.equal(ev(a, 'repeat'), undefined);
      assert.equal(ev(a, 'release'), '\x1b[97;1:3u');
      assert.equal(ev(press('A', 'KeyA', { shift: true }), 'release'), '\x1b[97;2:3u');
      assert.equal(ev(press('!', 'Digit1', { shift: true }), 'release'), '\x1b[49;2:3u');
      assert.equal(ev(press(' ', 'Space'), 'release'), '\x1b[32;1:3u');
    });

    it('Enter, Tab and Backspace come and repeat as legacy and are not released', () => {
      for (const [k, c] of [['Enter', 'Enter'], ['Tab', 'Tab'], ['Backspace', 'Backspace']]) {
        for (const t of ['press', 'repeat', 'release'] as const) {
          assert.equal(ev(press(k, c), t), undefined, `${k} ${t}`);
        }
      }
      assert.equal(ev(press('Enter', 'Enter', { shift: true }), 'release'), '\x1b[13;2:3u', 'a modified one is an escape code, its release too');
    });

    it("the keys of the legacy forms: a press is xterm.js's, a repeat and a release `CSI number ; 1:event final`", () => {
      const cases: [string, string, string][] = [
        ['ArrowUp', '1', 'A'],
        ['ArrowDown', '1', 'B'],
        ['ArrowRight', '1', 'C'],
        ['ArrowLeft', '1', 'D'],
        ['Home', '1', 'H'],
        ['End', '1', 'F'],
        ['F1', '1', 'P'],
        ['F2', '1', 'Q'],
        ['F3', '13', '~'],
        ['F4', '1', 'S'],
        ['Insert', '2', '~'],
        ['Delete', '3', '~'],
        ['PageUp', '5', '~'],
        ['PageDown', '6', '~'],
        ['F5', '15', '~'],
        ['F6', '17', '~'],
        ['F7', '18', '~'],
        ['F8', '19', '~'],
        ['F9', '20', '~'],
        ['F10', '21', '~'],
        ['F11', '23', '~'],
        ['F12', '24', '~'],
      ];
      for (const [key, n, final] of cases) {
        const p = press(key, key);
        assert.equal(ev(p, 'press'), undefined, key);
        assert.equal(ev(p, 'repeat'), `\x1b[${n};1:2${final}`, key);
        assert.equal(ev(p, 'release'), `\x1b[${n};1:3${final}`, key);
      }
      assert.equal(ev(press('ArrowLeft', 'ArrowLeft', { ctrl: true, shift: true }), 'release'), '\x1b[1;6:3D');
      assert.equal(ev(press('Delete', 'Delete', { alt: true }), 'press'), undefined, 'a press with modifiers is xterm.js too');
    });

    it('without the flag a repeat is a press and a release nothing, whatever the key', () => {
      const c = press('c', 'KeyC', { ctrl: true });
      assert.equal(ev(c, 'repeat', 1), '\x1b[99;5u');
      assert.equal(ev(c, 'release', 1), undefined);
      assert.equal(ev(press('ArrowUp', 'ArrowUp'), 'release', 1), undefined);
      assert.equal(ev(press('a', 'KeyA'), 'release', 8), undefined);
    });
  });

  describe('flag 8, all keys as escape codes', () => {
    const a = (p: KeyPress, flags = 8) => encodeKey(p, flags);

    it('text, shifted or not, Enter, Tab and Backspace, with the key unshifted and Shift a modifier', () => {
      assert.equal(a(press('a', 'KeyA')), '\x1b[97u');
      assert.equal(a(press('A', 'KeyA', { shift: true })), '\x1b[97;2u');
      assert.equal(a(press('!', 'Digit1', { shift: true })), '\x1b[49;2u');
      assert.equal(a(press('.', 'Period')), '\x1b[46u');
      assert.equal(a(press(' ', 'Space')), '\x1b[32u');
      assert.equal(a(press('é', 'Quote')), '\x1b[233u');
      assert.equal(a(press('Enter', 'Enter')), '\x1b[13u');
      assert.equal(a(press('Tab', 'Tab')), '\x1b[9u');
      assert.equal(a(press('Tab', 'Tab', { shift: true })), '\x1b[9;2u');
      assert.equal(a(press('Backspace', 'Backspace')), '\x1b[127u');
      assert.equal(a(press('c', 'KeyC', { ctrl: true })), '\x1b[99;5u');
    });

    it('the modifier keys alone, with the modifier they make in the field of their press', () => {
      assert.equal(a(press('Shift', 'ShiftLeft', { shift: true })), '\x1b[57441;2u');
      assert.equal(a(press('Shift', 'ShiftRight', { shift: true })), '\x1b[57447;2u');
      assert.equal(a(press('Control', 'ControlLeft', { ctrl: true })), '\x1b[57442;5u');
      assert.equal(a(press('Control', 'ControlRight', { ctrl: true })), '\x1b[57448;5u');
      assert.equal(a(press('Alt', 'AltLeft', { alt: true })), '\x1b[57443;3u');
      assert.equal(a(press('Alt', 'AltRight', { alt: true })), '\x1b[57449;3u');
      assert.equal(a(press('AltGraph', 'AltRight')), '\x1b[57453u');
      assert.equal(a(press('Meta', 'MetaLeft', { meta: true })), undefined, "Cmd's");
      assert.equal(a(press('Shift', 'ShiftLeft', { shift: true }), 1), undefined, 'not by disambiguation');
      assert.equal(a(press('Shift', 'ShiftLeft', { shift: true }), 2), undefined, 'nor by event types');
      assert.equal(encodeKey({ ...press('Shift', 'ShiftLeft'), type: 'release' }, 10), '\x1b[57441;1:3u');
      assert.equal(encodeKey({ ...press('Control', 'ControlLeft', { shift: true }), type: 'release' }, 10), '\x1b[57442;2:3u');
    });

    it('lock keys and the keys left: Caps Lock, Num Lock, Scroll Lock, Print Screen, Pause, Menu, media keys', () => {
      assert.equal(a(press('CapsLock', 'CapsLock')), '\x1b[57358u');
      assert.equal(a(press('ScrollLock', 'ScrollLock')), '\x1b[57359u');
      assert.equal(a(press('NumLock', 'NumLock')), '\x1b[57360u');
      assert.equal(a(press('PrintScreen', 'PrintScreen')), '\x1b[57361u');
      assert.equal(a(press('Pause', 'Pause')), '\x1b[57362u');
      assert.equal(a(press('ContextMenu', 'ContextMenu')), '\x1b[57363u');
      assert.equal(a(press('MediaPlayPause', 'MediaPlayPause')), '\x1b[57430u');
      assert.equal(a(press('AudioVolumeMute', 'AudioVolumeMute')), '\x1b[57440u');
      assert.equal(a(press('CapsLock', 'CapsLock'), 1), undefined, 'by 8 alone');
    });

    it('the keypad: its own codes, by what the key is, or does with Num Lock off; the main keys as ever', () => {
      const kp = (key: string, code: string, mods: Partial<KeyPress> = {}) => a({ ...press(key, code, mods), location: 3 });
      assert.equal(kp('0', 'Numpad0'), '\x1b[57399u');
      assert.equal(kp('9', 'Numpad9'), '\x1b[57408u');
      assert.equal(kp('.', 'NumpadDecimal'), '\x1b[57409u');
      assert.equal(kp('/', 'NumpadDivide'), '\x1b[57410u');
      assert.equal(kp('*', 'NumpadMultiply'), '\x1b[57411u');
      assert.equal(kp('-', 'NumpadSubtract'), '\x1b[57412u');
      assert.equal(kp('+', 'NumpadAdd'), '\x1b[57413u');
      assert.equal(kp('Enter', 'NumpadEnter'), '\x1b[57414u');
      assert.equal(kp('=', 'NumpadEqual'), '\x1b[57415u');
      assert.equal(kp(',', 'NumpadComma'), '\x1b[57416u');
      assert.equal(kp('ArrowLeft', 'Numpad4'), '\x1b[57417u', 'Num Lock off');
      assert.equal(kp('End', 'Numpad1'), '\x1b[57424u');
      assert.equal(kp('Delete', 'NumpadDecimal'), '\x1b[57426u');
      assert.equal(kp('Enter', 'NumpadEnter', { ctrl: true }), '\x1b[57414;5u');
      assert.equal(a(press('1', 'Digit1')), '\x1b[49u', 'not on the keypad');
      assert.equal(a(press('ArrowLeft', 'ArrowLeft')), undefined, 'a main arrow is the legacy form');
      assert.equal(encodeKey({ ...press('0', 'Numpad0'), location: 3 }, 1), undefined, 'the keypad of 8 alone');
    });

    it('Caps Lock and Num Lock are among the modifiers, with 8 only', () => {
      assert.equal(a({ ...press('a', 'KeyA'), capsLock: true }), '\x1b[97;65u');
      assert.equal(a({ ...press('a', 'KeyA'), capsLock: true, numLock: true, ctrl: true }), '\x1b[97;197u');
      assert.equal(a({ ...press('A', 'KeyA', { shift: true }), numLock: true }), '\x1b[97;130u');
      assert.equal(encodeKey({ ...press('Escape', 'Escape'), numLock: true, capsLock: true }, 1), '\x1b[27u');
    });

    it('the keys no legacy form has: F13 to F24 from disambiguation on; an input method and what is not a key left to xterm.js', () => {
      assert.equal(a(press('F13', 'F13'), 1), '\x1b[57376u');
      assert.equal(a(press('F24', 'F24'), 1), '\x1b[57387u');
      assert.equal(a(press('F13', 'F13', { shift: true }), 1), '\x1b[57376;2u');
      assert.equal(a(press('F13', 'F13'), 0), undefined);
      assert.equal(a({ ...press('a', 'KeyA'), composing: true }), undefined);
      assert.equal(a(press('Dead', 'Quote')), undefined);
      assert.equal(a(press('Unidentified', 'Unknown')), undefined);
      assert.equal(a(press('p', 'KeyP', { meta: true })), undefined);
    });

    it('with event types: a press of text is an escape code, and a repeat and a release are, with the type', () => {
      const t = (type: 'press' | 'repeat' | 'release') => encodeKey({ ...press('a', 'KeyA'), type }, 10);
      assert.equal(t('press'), '\x1b[97u');
      assert.equal(t('repeat'), '\x1b[97;1:2u');
      assert.equal(t('release'), '\x1b[97;1:3u');
      assert.equal(encodeKey({ ...press('Enter', 'Enter'), type: 'release' }, 10), '\x1b[13;1:3u');
      assert.equal(encodeKey({ ...press('Backspace', 'Backspace'), type: 'repeat' }, 10), '\x1b[127;1:2u');
      assert.equal(encodeKey({ ...press('ArrowUp', 'ArrowUp'), type: 'release' }, 10), '\x1b[1;1:3A');
    });
  });

  describe('flag 4, alternate keys', () => {
    const alt = (p: KeyPress, flags = 12) => encodeKey(p, flags);

    it('the shifted key after the code, where Shift is held and it is another', () => {
      assert.equal(alt(press('A', 'KeyA', { shift: true })), '\x1b[97:65;2u');
      assert.equal(alt(press('!', 'Digit1', { shift: true })), '\x1b[49:33;2u');
      assert.equal(alt(press('a', 'KeyA')), '\x1b[97u');
      assert.equal(alt(press('C', 'KeyC', { ctrl: true, shift: true }), 5), '\x1b[99:67;6u');
      assert.equal(alt(press('1', 'Digit1', { ctrl: true }), 5), '\x1b[49;5u');
      assert.equal(alt(press('Enter', 'Enter', { shift: true })), '\x1b[13;2u', 'no alternates of a key that types none');
    });

    it('the key of a US layout in that place after it, where the layout makes another: by its code, an empty shifted key between', () => {
      assert.equal(alt(press('с', 'KeyC', { ctrl: true }), 5), '\x1b[1089::99;5u');
      assert.equal(alt(press('С', 'KeyC', { ctrl: true, shift: true }), 5), '\x1b[1089:1057:99;6u');
      assert.equal(alt(press('ф', 'KeyA')), '\x1b[1092::97u');
      assert.equal(alt(press('Ф', 'KeyA', { shift: true })), '\x1b[1092:1060:97;2u');
      assert.equal(alt(press('q', 'KeyA')), '\x1b[113::97u', 'AZERTY');
      assert.equal(alt(press('&', 'Digit1')), '\x1b[38::49u', 'AZERTY digits');
      assert.equal(alt(press('A', 'KeyA')), '\x1b[97u', 'Caps Lock types a capital, Shift not held: no shifted key');
      assert.equal(alt(press('å', 'KeyA', { alt: true }), 5), '\x1b[97;3u', 'macOS Option: the key is where it is');
    });

    it('without the flag the key by where it is, as for disambiguation, whatever the layout', () => {
      assert.equal(encodeKey(press('с', 'KeyC', { ctrl: true }), 1), '\x1b[99;5u');
      assert.equal(encodeKey(press('A', 'KeyA', { shift: true, alt: true }), 1), '\x1b[97;4u');
      assert.equal(encodeKey(press('A', 'KeyA', { shift: true }), 8), '\x1b[97;2u');
    });

    it('with event types the release has them too', () => {
      assert.equal(encodeKey({ ...press('A', 'KeyA', { shift: true }), type: 'release' }, 6), '\x1b[97:65;2:3u');
    });
  });

  describe('flag 16, associated text', () => {
    const t = (p: KeyPress, flags = 24) => encodeKey(p, flags);

    it('the text typed as code points after the modifiers, an empty field for none', () => {
      assert.equal(t(press('a', 'KeyA')), '\x1b[97;;97u');
      assert.equal(t(press('A', 'KeyA', { shift: true })), '\x1b[97;2;65u');
      assert.equal(t(press('!', 'Digit1', { shift: true })), '\x1b[49;2;33u');
      assert.equal(t(press(' ', 'Space')), '\x1b[32;;32u');
      assert.equal(t(press('é', 'Quote')), '\x1b[233;;233u');
      assert.equal(t(press('😀', 'Unknown')), '\x1b[128512;;128512u');
    });

    it('with the alternates and the event types: a repeat tells the text, a release none', () => {
      assert.equal(t(press('A', 'KeyA', { shift: true }), 28), '\x1b[97:65;2;65u');
      assert.equal(encodeKey({ ...press('a', 'KeyA'), type: 'repeat' }, 26), '\x1b[97;1:2;97u');
      assert.equal(encodeKey({ ...press('a', 'KeyA'), type: 'release' }, 26), '\x1b[97;1:3u');
    });

    it('none for a shortcut, nor for Enter, Tab, Backspace, Escape, or without 8', () => {
      assert.equal(t(press('c', 'KeyC', { ctrl: true })), '\x1b[99;5u');
      assert.equal(t(press('x', 'KeyX', { alt: true })), '\x1b[120;3u');
      assert.equal(t(press('Enter', 'Enter')), '\x1b[13u');
      assert.equal(t(press('Tab', 'Tab')), '\x1b[9u');
      assert.equal(t(press('Backspace', 'Backspace')), '\x1b[127u');
      assert.equal(t(press('Escape', 'Escape')), '\x1b[27u');
      assert.equal(t(press('a', 'KeyA'), 16), undefined, '16 is nothing without 8');
      assert.equal(t(press('a', 'KeyA'), 17), undefined, 'nor with disambiguation alone');
      assert.equal(t(press('F1', 'F1')), undefined);
    });
  });
});
