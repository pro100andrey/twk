// The keys of a recording (core/replay_input.ts), told from the terminal's
// answers by their shape, as twk_dev's InputSplitter does for `twk record
// --replay` (the same cases as its replay_test.dart).
import * as assert from 'node:assert/strict';

import { parseCast } from '../../../core/cast';
import { replaySteps } from '../../../core/replay_input';

/** A recording of [events]: `[time, code, data]`. */
const castOf = (events: [number, string, string][]) =>
  parseCast([JSON.stringify({ version: 2, width: 80, height: 24 }), ...events.map((e) => JSON.stringify(e))].join('\n'));

const keysOf = (events: [number, string, string][]) => replaySteps(castOf(events)).map((s) => [s.time, s.keys]);

describe('the keys of a recording', () => {
  it('leaves the terminal\'s answers out, whatever the event holds with them', () => {
    assert.deepEqual(
      keysOf([
        [0.1, 'i', '\x1b[?62;4c\x1b[>0;10;1c\x1b[?2026;2$y\x1b[?0u\x1b[0n\x1b[8;24;80t'],
        [0.2, 'i', '\x1b]11;rgb:0000/0000/0000\x07\x1bP>|xterm\x1b\\\x1b_Gi=1;OK\x1b\\'],
        [0.3, 'i', 'a\x1b[?62;4cb\x1b]10;rgb:ffff/ffff/ffff\x1b\\'],
      ]),
      [[0.3, 'ab']],
    );
  });

  it('keeps every key: cursor, tilde, kitty, SS3, focus, the mouse, Alt', () => {
    const keys = ['\x1b[A', '\x1b[1;5C', '\x1b[3~', '\x1b[97;5u', '\x1bOP', '\x1b[I', '\x1b[O', '\x1b[<0;5;5M', '\x1b[<0;5;5m', '\x1bb', '\x1b\x1b[A', 'é', '\r', '\x7f', '\x1b'];
    assert.deepEqual(keysOf(keys.map((k, i): [number, string, string] => [i, 'i', k + (i === keys.length - 1 ? 'x' : '')])).map(([, k]) => k), [...keys.slice(0, -1), '\x1bx']);
  });

  it('tells a cursor position from the modified F3 by whether the app asked and was not answered yet', () => {
    assert.deepEqual(keysOf([[0.1, 'i', '\x1b[1;5R']]), [[0.1, '\x1b[1;5R']], 'asked by none: F3');
    assert.deepEqual(
      keysOf([
        [0.0, 'o', '\x1b[6n'],
        [0.1, 'i', '\x1b[1;5R'],
        [0.2, 'i', '\x1b[1;5R'],
      ]),
      [[0.2, '\x1b[1;5R']],
      'one query, one answer, then F3',
    );
    assert.deepEqual(
      keysOf([
        [0.0, 'o', '\x1b[?6n\x1b[6'],
        [0.0, 'o', 'n'],
        [0.1, 'i', '\x1b[?3;4R\x1b[12;7R'],
        [0.2, 'i', '\x1b[12;7R'],
      ]),
      [[0.2, '\x1b[12;7R']],
      'a query cut between writes counts; ? R answers ?6n',
    );
    // a key typed gives the queries up
    assert.deepEqual(
      keysOf([
        [0.0, 'o', '\x1b[6n'],
        [0.1, 'i', 'x'],
        [0.2, 'i', '\x1b[1;5R'],
      ]),
      [
        [0.1, 'x'],
        [0.2, '\x1b[1;5R'],
      ],
    );
    // asked by none, a row other than 1 is no F3 but the shape is all there is to tell: a key
    assert.deepEqual(keysOf([[0.1, 'i', '\x1b[12;7R']]), [[0.1, '\x1b[12;7R']]);
  });

  it('puts a sequence cut between two events together, at the time it ends', () => {
    assert.deepEqual(
      keysOf([
        [0.1, 'i', '\x1b[?62'],
        [0.2, 'i', ';4c'],
        [0.3, 'i', '\x1b['],
        [0.4, 'i', 'A'],
      ]),
      [[0.4, '\x1b[A']],
    );
  });

  it('takes what waits at the end for keys: an Alt+] that opens no string', () => {
    assert.deepEqual(keysOf([[0.1, 'i', 'a\x1b]']]), [
      [0.1, 'a'],
      [0.1, '\x1b]'],
    ]);
  });

  it('keeps a paste whole, whatever its content holds', () => {
    assert.deepEqual(
      keysOf([[0.1, 'i', '\x1b[200~echo \x1b[?62;4c \x1b]11;x\x07\x1b[201~\x1b[?62;4c']]),
      [[0.1, '\x1b[200~echo \x1b[?62;4c \x1b]11;x\x07\x1b[201~']],
    );
  });

  it('knows which keys the app reacted to, by the order of the events', () => {
    const steps = replaySteps(
      castOf([
        [0.1, 'o', 'a'],
        [0.2, 'i', 'x'],
        [0.2, 'o', 'b'],
        [0.2, 'i', 'y'],
        [0.3, 'i', 'z'],
      ]),
    );
    assert.deepEqual(steps.map((s) => s.reacts), [true, false, false]);
  });

  it('has nothing to type in a recording made without keys', () => {
    assert.deepEqual(keysOf([[0.1, 'o', 'hi']]), []);
  });
});
