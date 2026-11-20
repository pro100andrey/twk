// The sequence log's entries (core/seqlog.ts): what the app wrote, a
// synchronized update one frame entry holding its own, however many reads
// it takes; what the terminal sent; notes; what is kept and taken.
import * as assert from 'node:assert/strict';

import { LogEntry, SequenceLog, entryAtAppBytes } from '../../../core/seqlog';

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

describe('the log by the app\'s count of its bytes', () => {
  const sync = (text: string) => `\x1b[?2026h${text}\x1b[?2026l`;
  const first = sync('ab');
  const second = sync('é€😀'); // 2, 3 and 4 bytes of UTF-8, which the app counts as bytes

  it('gives each entry of the app\'s output where it begins and ends in the app\'s count, a frame its whole', () => {
    const log = new SequenceLog();
    log.output(0, b('\x1b[?1049h'), { run: 1, offset: 0 });
    log.output(5, b(first), { run: 1, offset: 8 });
    log.output(9, b(second), { run: 1, offset: 8 + Buffer.byteLength(first) });
    const [alt, one, two] = log.all();
    assert.deepEqual([alt.run, alt.at, alt.end], [1, 0, 8]);
    assert.deepEqual([one.run, one.at, one.end], [1, 8, 8 + Buffer.byteLength(first)]);
    assert.equal(two.end, 8 + Buffer.byteLength(first) + Buffer.byteLength(second));
    assert.equal(two.children!.at(-1)!.end, two.end);
    assert.equal(two.at, one.end);
  });

  it('carries no count for output nobody counted, nor for what the terminal sent', () => {
    const log = new SequenceLog();
    log.output(0, b('x'));
    log.input(1, b('q'));
    for (const e of log.all()) {
      assert.equal(e.end, undefined);
      assert.equal(e.run, undefined);
    }
  });

  it('keeps the count across a sequence cut between reads', () => {
    const log = new SequenceLog();
    const whole = b(first);
    log.output(0, whole.subarray(0, 5), { run: 1, offset: 0 });
    log.output(1, whole.subarray(5), { run: 1, offset: 5 });
    const [frame] = log.all();
    assert.deepEqual([frame.at, frame.end], [0, whole.length]);
  });

  it('goes on from where the bytes are said to be where some were let go between', () => {
    const log = new SequenceLog();
    log.output(0, b(first), { run: 1, offset: 0 });
    log.output(1, b(first), { run: 1, offset: 1000 });
    const [one, two] = log.all();
    assert.deepEqual([one.at, one.end], [0, Buffer.byteLength(first)]);
    assert.deepEqual([two.at, two.end], [1000, 1000 + Buffer.byteLength(first)]);
  });

  it('finds the entry where the app had written a count: the first that reaches it', () => {
    const log = new SequenceLog();
    log.output(0, b(first), { run: 1, offset: 0 });
    log.output(1, b(second), { run: 1, offset: Buffer.byteLength(first) });
    const entries = log.all();
    const end1 = Buffer.byteLength(first);
    assert.equal(entryAtAppBytes(entries, end1)!.entry, entries[0]);
    assert.equal(entryAtAppBytes(entries, end1 + 1)!.entry, entries[1]);
    assert.equal(entryAtAppBytes(entries, end1 + Buffer.byteLength(second))!.entry, entries[1]);
    assert.equal(entryAtAppBytes(entries, end1 + Buffer.byteLength(second))!.dropped, false);
    // the log has not got as far: the last one
    assert.equal(entryAtAppBytes(entries, 100000)!.entry, entries[1]);
  });

  it('finds a count the log begins after as dropped: the first entry there is', () => {
    const log = new SequenceLog();
    // what came before offset 100 was let go
    log.output(0, b(first), { run: 1, offset: 100 });
    const entries = log.all();
    const found = entryAtAppBytes(entries, 40)!;
    assert.equal(found.dropped, true);
    assert.equal(found.entry, entries[0]);
    assert.equal(entryAtAppBytes(entries, 100 + Buffer.byteLength(first))!.dropped, false);
  });

  it('counts each app anew, and looks in the latest', () => {
    const log = new SequenceLog();
    log.output(0, b(first), { run: 1, offset: 0 });
    log.output(1, b(first), { run: 2, offset: 0 });
    log.output(2, b(second), { run: 2, offset: Buffer.byteLength(first) });
    const entries = log.all();
    assert.equal(entries[1].run, 2);
    assert.equal(entries[1].at, 0);
    assert.equal(entryAtAppBytes(entries, 3)!.entry, entries[1]);
    assert.equal(entryAtAppBytes([], 3), undefined);
    const noRun = new SequenceLog();
    noRun.output(0, b(first));
    assert.equal(entryAtAppBytes(noRun.all(), 3), undefined);
  });

  it('finishes a synchronized update the last run died in when a new run begins, so the new run has frames', () => {
    const log = new SequenceLog();
    log.output(0, b('\x1b[?2026h\x1b[1;1Hhalf'), { run: 1, offset: 0 });
    log.output(5, b('\x1b[?2026h\x1b[1;1Hagain\x1b[?2026l'), { run: 2, offset: 0 });
    log.output(9, b('\x1b[?2026h\x1b[1;1Hmore\x1b[?2026l'), { run: 2, offset: 25 });
    const frames = log.all().filter((e) => e.kind === 'frame');
    assert.equal(frames.length, 3);
    assert.match(frames[0].name, /not closed/);
    assert.doesNotMatch(frames[1].name, /not closed/);
    assert.doesNotMatch(frames[2].name, /not closed/);
  });

  it('forgets the half of a sequence the last run left when it is finished', () => {
    const log = new SequenceLog();
    log.output(0, b('\x1b[1'), { run: 1, offset: 0 });
    log.output(1, b('mtext'), { run: 2, offset: 0 });
    assert.deepEqual(names(log.all()), ['output cut short: ESC [1', 'text "mtext"']);
  });

  it('counts the bytes of a cut UTF-8 character once in the app offsets when the next read starts with a control', () => {
    const log = new SequenceLog();
    // a, and the first two bytes of the euro sign, which never completes
    log.output(0, Buffer.from('a€', 'utf8').subarray(0, 3), { run: 1, offset: 0 });
    log.output(1, b('\r\nz'), { run: 1, offset: 3 });
    log.output(2, b('y'), { run: 1, offset: 6 });
    const last = log.all().filter((e) => e.kind === 'text').pop()!;
    assert.equal(last.name, 'text "y"');
    assert.equal(last.at, 6);
    assert.equal(last.end, 7);
  });
});
