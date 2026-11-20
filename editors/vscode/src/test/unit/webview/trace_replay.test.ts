// The replay of a trace's cast (webview/trace_replay.ts) on a headless xterm.js:
// a resize takes the text before it at the size before it, and a drawing
// begins only once the one before it has been parsed.
import * as assert from 'node:assert/strict';

import { Terminal } from '@xterm/headless';

import { WireEvent } from '../../../core/trace';
import { Replayer } from '../../../webview/trace_replay';

function rowsOf(term: Terminal): string[] {
  const buffer = term.buffer.active;
  const out: string[] = [];
  for (let y = 0; y < term.rows; y++) {
    out.push(buffer.getLine(y)?.translateToString(true) ?? '');
  }
  return out;
}

describe('the replay of a cast', () => {
  let term: Terminal;
  let replayer: Replayer;

  beforeEach(() => {
    term = new Terminal({ cols: 80, rows: 24, scrollback: 0, allowProposedApi: true });
    replayer = new Replayer(term);
  });

  afterEach(() => term.dispose());

  it('writes the text before a resize at the size before it', async () => {
    const events: WireEvent[] = [
      [0, 'o', 'abcdefghijklmnopqrst'],
      [1, 'r', '20x4'],
    ];
    await replayer.draw(events, 1, 10, 4);
    assert.equal(term.cols, 20);
    assert.deepEqual(rowsOf(term).slice(0, 2), ['abcdefghij', 'klmnopqrst']);
  });

  it('writes the text after a resize at the new size', async () => {
    const events: WireEvent[] = [
      [0, 'r', '20x4'],
      [1, 'o', 'abcdefghijklmnopqrst'],
    ];
    await replayer.draw(events, 1, 10, 4);
    assert.deepEqual(rowsOf(term).slice(0, 2), ['abcdefghijklmnopqrst', '']);
  });

  it('draws nothing past the event asked for', async () => {
    const events: WireEvent[] = [
      [0, 'o', 'one'],
      [1, 'o', 'two'],
    ];
    await replayer.draw(events, 0, 10, 2);
    assert.equal(rowsOf(term)[0], 'one');
  });

  it('lets a drawing finish before the next resets the screen, the last one standing', async () => {
    const first = replayer.draw([[0, 'o', 'x'.repeat(200000)]], 0, 10, 4);
    const second = replayer.draw([[0, 'o', 'second']], 0, 10, 4);
    await Promise.all([first, second]);
    assert.deepEqual(rowsOf(term), ['second', '', '', '']);
  });
});
