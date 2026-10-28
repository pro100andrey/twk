// The sequence log's entries (core/seqlog.ts): what the app wrote, a
// synchronized update one frame entry holding its own, however many reads
// it takes; what the terminal sent; notes; what is kept and taken.
import * as assert from 'node:assert/strict';

import { LogEntry, SequenceLog } from '../../../core/seqlog';

const b = (s: string) => Buffer.from(s, 'utf8');
const names = (es: readonly LogEntry[]) => es.map((e) => e.name);

describe('the sequence log', () => {
  it('makes an entry of each piece, a frame of each synchronized update, with when', () => {
    const log = new SequenceLog();
    log.note(0, 'an app connected');
    log.output(5, b('\x1b[?1049h'));
    log.output(10, b('\x1b[?2026h\x1b[1;1HCount: 0\x1b[0m\x1b[?2026l'));
    log.input(20, b('\x1b[A'));
    const es = log.take();
    assert.deepEqual(names(es), ['an app connected', 'DECSET 1049 alternate screen, cursor saved', 'frame 1: 1 DECSET, 1 CUP, 1 text, 1 SGR, 1 DECRST', 'key Up']);
    const frame = es[2];
    assert.equal(frame.kind, 'frame');
    assert.equal(frame.time, 10);
    assert.equal(frame.bytes, Buffer.byteLength('\x1b[?2026h\x1b[1;1HCount: 0\x1b[0m\x1b[?2026l'));
    assert.deepEqual(names(frame.children ?? []), [
      'DECSET 2026 synchronized output',
      'CUP cursor to row 1, column 1',
      'text "Count: 0"',
      'SGR reset',
      'DECRST 2026 synchronized output',
    ]);
    assert.deepEqual(
      es.map((e) => [e.direction, e.raw]),
      [
        ['note', ''],
        ['out', 'ESC [?1049h'],
        ['out', `${frame.bytes} bytes`],
        ['in', 'ESC [A'],
      ],
    );
    assert.deepEqual(log.take(), []);
    assert.equal(log.all().length, 4);
  });

  it('holds a frame until its update ends, a later read, its time its beginning and how long it took', () => {
    const log = new SequenceLog();
    log.output(100, b('\x1b[?2026hab'));
    log.output(110, b('\x1b[?20'));
    assert.deepEqual(log.take(), []);
    log.output(130, b('26lx'));
    const es = log.take();
    assert.deepEqual(names(es), ['frame 1: 1 DECSET, 1 text, 1 DECRST, 30 ms', 'text "x"']);
    assert.equal(es[0].time, 100);
    log.output(140, b('\x1b[?2026h\x1b[?2026l'));
    assert.match(log.take()[0].name, /^frame 2: /);
  });

  it('keeps the newest entries up to its limit, a frame its first ones up to its own', () => {
    const log = new SequenceLog({ limit: 3, frameLimit: 2 });
    for (let i = 0; i < 5; i++) {
      log.note(i, `note ${i}`);
    }
    assert.deepEqual(names(log.all()), ['note 2', 'note 3', 'note 4']);
    log.take();
    log.output(9, b('\x1b[?2026habc\x1b[1;1H\x1b[?2026l'));
    const [frame] = log.take();
    assert.equal(frame.children?.length, 2);
    assert.match(frame.name, /\(the first 2 entries\)$/);
    log.clear();
    assert.deepEqual(log.all(), []);
    log.note(10, 'after');
    assert.deepEqual(names(log.take()), ['after']);
  });
});
