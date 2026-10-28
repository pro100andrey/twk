// What the webview makes of what an app writes (core/emulation.ts): the
// answers it gives, and the requests it parses.
import * as assert from 'node:assert/strict';

import { answersOf, presetNamed } from '../../../core/capabilities';
import {
  cellSizeReply,
  clipboardOf,
  isColorQuery,
  isSafeLink,
  modeReply,
  notificationOf,
  pointerOf,
  progressOf,
  progressText,
  versionReply,
} from '../../../core/emulation';

const xterm = answersOf(presetNamed('xterm.js').capabilities);
const none = answersOf(presetNamed('no answers').capabilities);

describe("the webview's emulation", () => {
  it('answers DECRQM of a denied mode "not recognised", leaves the rest to xterm.js', () => {
    assert.equal(modeReply(2026, xterm), undefined);
    assert.equal(modeReply(2026, none), '\x1b[?2026;0$y');
    assert.equal(modeReply(69, none), '\x1b[?69;0$y');
    assert.equal(modeReply(1049, none), undefined, 'no capability of it');
  });

  it("answers XTVERSION with its name, a cell's size in whole pixels, each only where it answers", () => {
    assert.equal(versionReply(xterm), '\x1bP>|twk-vscode(0.0.1)\x1b\\');
    assert.equal(versionReply(none), undefined);
    assert.equal(cellSizeReply(xterm, { width: 8.6, height: 17.2 }), '\x1b[6;17;9t');
    assert.equal(cellSizeReply(xterm, undefined), undefined, 'not known');
    assert.equal(cellSizeReply(xterm, { width: 0, height: 17 }), undefined, 'not laid out');
    assert.equal(cellSizeReply(none, { width: 8, height: 17 }), undefined);
  });

  it('tells a colour query from a colour set', () => {
    assert.ok(isColorQuery('?'));
    assert.ok(isColorQuery('0;?;1;?'));
    assert.equal(isColorQuery('rgb:00/00/00'), false);
    assert.equal(isColorQuery('1;rgb:ff/00/00'), false);
  });

  it("parses an app's notification, progress, clipboard and pointer shape as twk writes them", () => {
    assert.deepEqual(notificationOf('notify;Build;done, 3 tests'), { type: 'notify', title: 'Build', body: 'done, 3 tests' });
    assert.deepEqual(notificationOf('notify;Only'), { type: 'notify', title: 'Only', body: '' });
    assert.equal(notificationOf('preexec'), undefined);
    assert.deepEqual(progressOf('4;1;40'), { type: 'progress', state: 1, percent: 40 });
    assert.deepEqual(progressOf('4;3'), { type: 'progress', state: 3, percent: null });
    assert.deepEqual(progressOf('4;0;50'), { type: 'progress', state: 0, percent: null }, 'none takes no percent');
    assert.deepEqual(progressOf('4;2;250'), { type: 'progress', state: 2, percent: 100 });
    assert.equal(progressOf('Build done'), undefined, "iTerm2's OSC 9 notification");
    assert.equal(progressOf('4;7'), undefined);
    assert.deepEqual(clipboardOf(`c;${Buffer.from('héllo').toString('base64')}`), { type: 'clipboard', text: 'héllo' });
    assert.deepEqual(clipboardOf('c;'), { type: 'clipboard', text: '' });
    assert.equal(clipboardOf('c;?'), undefined, 'a query: never read');
    assert.equal(clipboardOf('c;not base64!'), undefined);
    assert.equal(clipboardOf(`c;${Buffer.from([0xff, 0xfe]).toString('base64')}`), undefined, 'no UTF-8');
    assert.equal(clipboardOf('nothing'), undefined);
    assert.equal(pointerOf('pointer'), 'pointer');
    assert.equal(pointerOf('zoom-in'), 'zoom-in');
    assert.equal(pointerOf(''), null);
    assert.equal(pointerOf('url(x)'), undefined);
  });

  it('opens links to the web and mail only', () => {
    for (const ok of ['https://dart.dev', 'http://localhost:8080/x', 'mailto:a@b.c', 'HTTPS://X']) {
      assert.ok(isSafeLink(ok), ok);
    }
    for (const no of ['command:workbench.action.quit', 'file:///etc/passwd', 'vscode://x', 'javascript:alert(1)', ' https://x']) {
      assert.equal(isSafeLink(no), false, no);
    }
  });

  it("says an app's progress in the status bar by its state", () => {
    assert.equal(progressText('a.dart', 1, 40), '$(loading~spin) a.dart 40%');
    assert.equal(progressText('a.dart', 3, null), '$(loading~spin) a.dart');
    assert.equal(progressText('a.dart', 2, 10), '$(error) a.dart 10%');
    assert.equal(progressText('a.dart', 4, null), '$(debug-pause) a.dart');
    assert.equal(progressText('a.dart', 0, null), undefined);
  });
});
