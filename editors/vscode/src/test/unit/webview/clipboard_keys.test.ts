// The keys of copy and paste in the terminal's webview.
import * as assert from 'node:assert/strict';

import { ClipboardKey, clipboardAction } from '../../../webview/clipboard_keys';

const key = (k: string, mods: Partial<Omit<ClipboardKey, 'code'>> = {}): ClipboardKey => ({ code: k, ctrl: false, alt: false, shift: false, meta: false, ...mods });

describe('the webview clipboard keys', () => {
  it('Ctrl+Shift+C copies and Ctrl+Shift+V pastes; Ctrl+C and Ctrl+V stay the app', () => {
    assert.equal(clipboardAction(key('KeyC', { ctrl: true, shift: true }), false), 'copy');
    assert.equal(clipboardAction(key('KeyV', { ctrl: true, shift: true }), false), 'paste');
    assert.equal(clipboardAction(key('KeyC', { ctrl: true }), false), undefined);
    assert.equal(clipboardAction(key('KeyV', { ctrl: true }), false), undefined);
  });

  it('Ctrl+Insert copies and Shift+Insert pastes', () => {
    assert.equal(clipboardAction(key('Insert', { ctrl: true }), false), 'copy');
    assert.equal(clipboardAction(key('Insert', { shift: true }), false), 'paste');
    assert.equal(clipboardAction(key('Insert'), false), undefined);
  });

  it('Cmd+C and Cmd+V on macOS only', () => {
    assert.equal(clipboardAction(key('KeyC', { meta: true }), true), 'copy');
    assert.equal(clipboardAction(key('KeyV', { meta: true }), true), 'paste');
    assert.equal(clipboardAction(key('KeyC', { meta: true }), false), undefined);
    assert.equal(clipboardAction(key('KeyC', { ctrl: true, shift: true }), true), undefined);
  });

  it('the key is told by its place: a Russian layout, whose Ctrl+Shift+C types a Cyrillic letter, copies too', () => {
    // the event's key is 'С' or 'м' there; only its code is looked at
    assert.equal(clipboardAction({ code: 'KeyC', ctrl: true, alt: false, shift: true, meta: false }, false), 'copy');
    assert.equal(clipboardAction({ code: 'KeyV', ctrl: false, alt: false, shift: false, meta: true }, true), 'paste');
    assert.equal(clipboardAction({ code: 'KeyM', ctrl: true, alt: false, shift: true, meta: false }, false), undefined);
  });

  it('a key with Alt, or any other letter, is the app', () => {
    assert.equal(clipboardAction(key('KeyC', { ctrl: true, shift: true, alt: true }), false), undefined);
    assert.equal(clipboardAction(key('KeyX', { ctrl: true, shift: true }), false), undefined);
    assert.equal(clipboardAction(key('KeyC'), false), undefined);
  });
});
