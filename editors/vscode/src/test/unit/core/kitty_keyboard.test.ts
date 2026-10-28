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
    k.push('alternate', 0b11111);
    assert.equal(k.query('alternate'), '\x1b[?1u', 'event types and the rest not done');
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
    k.reset();
    assert.equal(k.flags('normal'), 0);
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
});
