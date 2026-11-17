// A small driver trace written by hand, as twk_driver's TraceRecorder writes
// one (packages/twk_driver/lib/src/trace.dart): a counter on 20x4 that a
// press of Enter makes 1, and a tap on a button that is not there, which
// fails. Events: 0 first frame, 1 marker of step 1, 2 frame 2, 3 marker of
// step 2, 4 frame 3.
import { CastWriter } from '../../core/cast';

const sync = (body: string) => `\x1b[?2026h${body}\x1b[?2026l`;

export function fixtureCast(): string {
  const out: string[] = [];
  const w = new CastWriter((t) => out.push(t), { width: 20, height: 4 });
  const enc = (s: string) => new TextEncoder().encode(s);
  w.writeOutput(0, enc(sync('\x1b[1;1HCount: 0\r\n[ inc ]')));
  w.marker(1000, '1 press {"key":"enter"}');
  w.writeOutput(2000, enc(sync('\x1b[1;1HCount: 1')));
  w.marker(3000, '2 tap {"key":"missing"}');
  w.writeOutput(4000, enc(sync('\x1b[1;1HCount: 1\x1b[3;1Hwhere?')));
  w.close(5000);
  return out.join('');
}

export function fixtureTrace(): string {
  const lines = [
    { type: 'header', version: 1, program: 'counter.dart', size: [20, 4], profile: null, driven: true, start: '2026-11-17T10:00:00.000Z' },
    { type: 'frame', frame: 1, castEvent: 0, outputWritten: 30, raw: 31 },
    { type: 'frame', frame: 2, castEvent: 2, outputWritten: 14, raw: 14 },
    { type: 'frame', frame: 3, castEvent: 4, outputWritten: 30, raw: 30 },
    { type: 'tree', key: 't1', frame: 2, text: 'Column\n  Text "Count: 1"\n  Button "inc"' },
    {
      type: 'step', step: 1, action: 'press', args: { key: 'enter' }, finder: null, target: null, hit: null,
      frameBefore: 1, frame: 2, castEvent: 1, appTime: 1500, realTime: 2500, result: 'ok', error: null, tree: 't1', log: ['info: pressed'],
    },
    {
      type: 'step', step: 2, action: 'tap', args: { key: 'missing' }, finder: { key: 'missing' },
      target: { id: 'inc', type: 'Button', shown: { x: 0, y: 1, width: 7, height: 1 } },
      hit: { covered: 'Text' }, frameBefore: 2, frame: 3, castEvent: 3, appTime: null, realTime: 4500, result: 'error',
      error: 'tap: Button inc is covered by Text', tree: null, log: [],
    },
  ];
  return `${lines.map((l) => JSON.stringify(l)).join('\n')}\n`;
}
