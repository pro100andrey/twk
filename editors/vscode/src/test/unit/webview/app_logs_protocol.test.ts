// The messages of the app log's webview, checked at both ends.
import * as assert from 'node:assert/strict';

import { isFromAppLogs, isToAppLogs } from '../../../webview/app_logs_protocol';

const row = { id: 1, app: 1, time: 1700000000000, level: 'warning', message: 'm', stack: [{ text: '#0 f', open: true }] };
const app = { id: 1, label: 'counter.dart', state: 'connected' };

describe('the messages of the app log', () => {
  it('to the webview: a reset, the apps, rows', () => {
    assert.ok(isToAppLogs({ type: 'reset', title: 't', apps: [app], rows: [row, { ...row, level: 'note' }] }));
    assert.ok(isToAppLogs({ type: 'apps', apps: [app] }));
    assert.ok(isToAppLogs({ type: 'rows', rows: [row] }));
  });

  it('to the webview: nothing else', () => {
    for (const m of [null, 'rows', { type: 'rows' }, { type: 'rows', rows: [{ ...row, level: 'loud' }] }, { type: 'apps', apps: [{ ...app, state: 'x' }] }, { type: 'rows', rows: [{ ...row, stack: [{ text: 1 }] }] }, { type: 'other' }]) {
      assert.equal(isToAppLogs(m), false, JSON.stringify(m));
    }
  });

  it('to the extension: ready, clear, open a frame, what is shown', () => {
    for (const m of [{ type: 'ready' }, { type: 'clear' }, { type: 'open', row: 1, frame: 0 }, { type: 'shown', rows: 2, held: 0, last: ['a'] }]) {
      assert.ok(isFromAppLogs(m), JSON.stringify(m));
    }
    for (const m of [{ type: 'open', row: -1, frame: 0 }, { type: 'open', row: 1 }, { type: 'shown', rows: 1, held: 0, last: [1] }, { type: 'x' }, 3]) {
      assert.equal(isFromAppLogs(m), false, JSON.stringify(m));
    }
  });
});
