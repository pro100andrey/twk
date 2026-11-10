// The sequence log saved (core/seqlog_save.ts): the rows as text, as `twk
// decode` lays them out, as filtered; the bytes with their times as an
// asciicast that parseCast reads and that, decoded again, makes the entries
// the log had.
import * as assert from 'node:assert/strict';

import { parseCast } from '../../../core/cast';
import { LogFilter, SequenceLog, wholeLog } from '../../../core/seqlog';
import { TrafficPiece, logCast, logText } from '../../../core/seqlog_save';

const b = (s: string) => Buffer.from(s, 'utf8');
const only = (f: Partial<LogFilter>): LogFilter => ({ ...wholeLog, ...f });

/** A session as pieces and as the log of them. */
function session(): { pieces: TrafficPiece[]; log: SequenceLog } {
  const pieces: TrafficPiece[] = [
    { time: 0, note: 'counter.dart opened, at 80x24' },
    { time: 5, output: b('\x1b[?1049h'), fromApp: true },
    { time: 10, output: b('\x1b[?2026h\x1b[1;1HCount: 0\x1b[0m\x1b[?2026l'), fromApp: true },
    { time: 20, input: b('\x1b[A') },
    { time: 30, output: b('twk: \x1b[2mthe app went away\x1b[0m'), fromApp: false },
    { time: 3000, output: b('1é'), fromApp: true },
  ];
  const log = new SequenceLog();
  for (const p of pieces) {
    if ('output' in p) {
      if (p.fromApp) {
        log.output(p.time, p.output);
      } else {
        log.note(p.time, 'twk: the app went away');
      }
    } else if ('input' in p) {
      log.input(p.time, p.input);
    } else {
      log.note(p.time, p.note);
    }
  }
  return { pieces, log };
}

describe('the sequence log saved as text', () => {
  it('a row a line as twk decode lays it out, a frame with its own rows indented', () => {
    const { log } = session();
    const lines = logText(log.all(), wholeLog).split('\n');
    assert.equal(lines.pop(), '');
    assert.equal(lines[0], '    0.000  --  counter.dart opened, at 80x24');
    assert.match(lines[1], /^ {4}0\.005 {2}out DECSET 1049 alternate screen, cursor saved +ESC \[\?1049h$/);
    assert.match(lines[2], /^ {4}0\.010 {2}out frame 1: 1 DECSET, 1 CUP, 1 text, 1 SGR, 1 DECRST/);
    assert.match(lines[3], /^ {4}0\.010 {2}out {3}DECSET 2026 synchronized output +ESC \[\?2026h$/);
    assert.match(lines[8], /^ {4}0\.020 {2}in {2}key Up +ESC \[A$/);
    assert.equal(lines.length, 11);
  });

  it('only what the filter shows: a direction, no text runs, a word (a frame with the rows that match)', () => {
    const { log } = session();
    const names = (f: LogFilter) =>
      logText(log.all(), f)
        .split('\n')
        .filter((l) => l !== '')
        .map((l) => l.slice(15).trim().replace(/ {2,}.*/, ''));
    assert.deepEqual(names(only({ out: false, note: false })), ['key Up']);
    assert.deepEqual(names(only({ out: false, in: false })), ['counter.dart opened, at 80x24', 'twk: the app went away']);
    assert.ok(!names(only({ text: false })).some((n) => n.startsWith('text')));
    assert.deepEqual(names(only({ word: 'cursor to row' })), ['frame 1: 1 DECSET, 1 CUP, 1 text, 1 SGR, 1 DECRST', 'CUP cursor to row 1, column 1']);
    assert.equal(logText(log.all(), only({ word: 'no such thing' })), '');
  });

  it('a control in a name stays out of a row', () => {
    const log = new SequenceLog();
    log.note(0, 'a\nb\x1b[31mc');
    assert.equal(logText(log.all(), wholeLog), '    0.000  --  a b [31mc\n');
  });
});

describe('the sequence log saved as asciicast', () => {
  it('the bytes with their times: o for the app, i for the terminal, m for a note, in order, read by parseCast', () => {
    const { pieces } = session();
    const text = logCast(pieces, wholeLog, { width: 80, height: 24, title: 'counter.dart', timestamp: 1700000000, term: 'xterm-256color' });
    assert.equal(text.split('\n')[0], '{"version":2,"width":80,"height":24,"timestamp":1700000000,"idle_time_limit":2.0,"title":"counter.dart","env":{"TERM":"xterm-256color"}}');
    const cast = parseCast(text);
    assert.deepEqual(
      cast.events.map((e) => [e.time, e.code]),
      [
        [0, 'm'],
        [0.005, 'o'],
        [0.01, 'o'],
        [0.02, 'i'],
        [0.03, 'm'],
        // the real pause kept: the header's idle limit is the player's to apply
        [3, 'o'],
      ],
    );
    assert.equal(cast.events[2].data, '\x1b[?2026h\x1b[1;1HCount: 0\x1b[0m\x1b[?2026l');
    assert.equal(cast.events[3].data, '\x1b[A');
    assert.equal(cast.events[4].data, 'twk: the app went away');
    assert.equal(cast.events[5].data, '1é');
    assert.deepEqual(cast.header.env, { TERM: 'xterm-256color' });
  });

  it('read again as a recording it makes the entries the log had (output, input, notes as they were)', () => {
    const { pieces, log } = session();
    const cast = parseCast(logCast(pieces, wholeLog, { width: 80, height: 24, title: 't', timestamp: 1 }));
    const again = new SequenceLog();
    for (const e of cast.events) {
      const time = Math.round(e.time * 1000);
      const data = Buffer.from(e.data, 'utf8');
      if (e.code === 'o') {
        again.output(time, data);
      } else if (e.code === 'i') {
        again.input(time, data);
      } else {
        again.note(time, e.data);
      }
    }
    const shape = (l: SequenceLog) => l.all().map((e) => [e.time, e.direction, e.name, e.raw, e.children?.length]);
    assert.deepEqual(shape(again), shape(log));
  });

  it('a direction left out of the filter is left out of the file; the word and the text runs do not cut bytes', () => {
    const { pieces } = session();
    const meta = { width: 1, height: 1, title: 't', timestamp: 0 };
    const codes = (f: LogFilter) => parseCast(logCast(pieces, f, meta)).events.map((e) => e.code).join('');
    assert.equal(codes(only({ out: false })), 'mim');
    assert.equal(codes(only({ in: false, note: false })), 'ooo');
    assert.equal(codes(only({ word: 'cursor', text: false })), 'mooimo');
  });

  it('a character cut between two reads is put together; an empty log is a header', () => {
    const e = Buffer.from('é');
    const text = logCast([{ time: 1, output: e.subarray(0, 1), fromApp: true }, { time: 2, output: e.subarray(1), fromApp: true }], wholeLog, { width: 2, height: 2, title: 't', timestamp: 0 });
    assert.deepEqual(parseCast(text).events.map((x) => x.data), ['é']);
    assert.equal(parseCast(logCast([], wholeLog, { width: 2, height: 2, title: 't', timestamp: 0 })).events.length, 0);
  });
});
