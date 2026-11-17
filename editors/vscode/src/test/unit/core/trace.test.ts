// The driver trace's reading (core/trace.ts) over a trace written by hand
// (../trace_fixture.ts): lines told by type, the frames table as cast
// events, the screens of a step, its facts, tree, log and sequences; and the
// screens held to the cast replayed in a headless xterm.
import * as assert from 'node:assert/strict';

import { Terminal } from '@xterm/headless';

import { parseCast } from '../../../core/cast';
import { driverTestLines, eventOfFrame, firstFailed, parseTrace, siblingOf, stepFacts, stepLabel, stepScreens, stepSequences, traceLinks, tracePathsIn, treeAt, wireEvents } from '../../../core/trace';
import { fixtureCast, fixtureTrace } from '../trace_fixture';

describe('a driver trace', () => {
  const trace = parseTrace(fixtureTrace());
  const cast = parseCast(fixtureCast());

  it('is read by the type of its lines', () => {
    assert.deepEqual([trace.header.program, trace.header.width, trace.header.height, trace.header.driven], ['counter.dart', 20, 4, true]);
    assert.equal(trace.frames.length, 3);
    assert.deepEqual(
      trace.steps.map((s) => [s.step, s.action, s.ok, s.castEvent, s.tree]),
      [
        [1, 'press', true, 1, 't1'],
        [2, 'tap', false, 3, null],
      ],
    );
    assert.equal(trace.trees.get('t1'), 'Column\n  Text "Count: 1"\n  Button "inc"');
    assert.deepEqual(trace.steps[1].target?.shown, { x: 0, y: 1, width: 7, height: 1 });
  });

  it('refuses what is no trace, saying the line', () => {
    assert.throws(() => parseTrace('{"type":"step"}\n'), /no header/);
    assert.throws(() => parseTrace('{"type":"header"}\nnot json\n'), /line 2/);
    assert.throws(() => parseTrace('[1]\n'), /line 1: no JSON object/);
  });

  it('finds its cast beside it, from either file', () => {
    assert.deepEqual(siblingOf('/t/a.trace.jsonl'), { cast: '/t/a.cast', trace: '/t/a.trace.jsonl' });
    assert.deepEqual(siblingOf('/t/a.cast'), { cast: '/t/a.cast', trace: '/t/a.trace.jsonl' });
    assert.equal(siblingOf('/t/a.txt'), undefined);
  });

  it('finds the trace paths of a failure report and a terminal line', () => {
    const report = 'trace, the cast with a marker for each step:\n  .dart_tool/twk_test/traces/c-1-0.cast\n  .dart_tool/twk_test/traces/c-1-0.trace.jsonl\n';
    assert.deepEqual(tracePathsIn(report), ['.dart_tool/twk_test/traces/c-1-0.trace.jsonl']);
    assert.deepEqual(traceLinks('  .dart_tool/x/a.trace.jsonl'), [{ startIndex: 2, length: 26, path: '.dart_tool/x/a.trace.jsonl' }]);
    assert.deepEqual(driverTestLines("void main() {\n  driverTest('a', (d) async {\n  });\n  // driverTest(x\n}"), [1]);
  });

  it('puts each frame at the cast event it ended in, one the table lacks at the last before it', () => {
    assert.deepEqual([1, 2, 3].map((f) => eventOfFrame(trace, f)), [0, 2, 4]);
    assert.equal(eventOfFrame(trace, 0), -1);
    assert.equal(eventOfFrame(trace, 9), 4);
  });

  it('lists the steps, the failed one first to show', () => {
    assert.deepEqual(trace.steps.map(stepLabel), ['1 press {"key":"enter"}', '2 tap {"key":"missing"}']);
    assert.equal(firstFailed(trace), 1);
    assert.equal(firstFailed({ ...trace, steps: [trace.steps[0]] }), 0);
  });

  it('tells the screens of a step: before, each frame it drew, after', () => {
    assert.deepEqual(stepScreens(trace, trace.steps[0]), { before: 0, after: 2, frames: [{ frame: 2, upTo: 2 }] });
    assert.deepEqual(stepScreens(trace, trace.steps[1]), { before: 2, after: 4, frames: [{ frame: 3, upTo: 4 }] });
  });

  it('replays to the screen before and after a step', () => {
    const screen = async (upTo: number) => {
      const term = new Terminal({ cols: 20, rows: 4, allowProposedApi: true });
      let text = '';
      for (const [i, code, data] of wireEvents(cast)) {
        if (i <= upTo && code === 'o') {
          text += data;
        }
      }
      await new Promise<void>((done) => term.write(text, done));
      return Array.from({ length: 4 }, (_, y) => term.buffer.active.getLine(y)?.translateToString(true) ?? '');
    };
    return Promise.all([screen(0), screen(2), screen(4)]).then(([first, second, third]) => {
      assert.deepEqual(first, ['Count: 0', '[ inc ]', '', '']);
      assert.equal(second[0], 'Count: 1');
      assert.equal(third[2], 'where?');
    });
  });

  it('tells a step: its facts, the tree it ended with or the last kept, the sequences it wrote', () => {
    assert.deepEqual(stepFacts(trace.steps[1]), [
      '2 tap: failed',
      'args {"key":"missing"}',
      'finder {"key":"missing"}',
      'target Button inc at 0,1 7x1',
      'hit {"covered":"Text"}',
      'frames 2 -> 3',
      'app time -, driver time 4.5 ms',
      'error tap: Button inc is covered by Text',
    ]);
    assert.equal(treeAt(trace, 1), trace.trees.get('t1'));
    assert.equal(treeAt({ ...trace, steps: [{ ...trace.steps[0], tree: null }] }, 0), undefined);
    const sequences = stepSequences(cast, trace, trace.steps[1]);
    assert.match(sequences, /where\?/);
    assert.doesNotMatch(sequences, /Count: 0/);
  });

  it('keeps only the output and resizes for the viewer, by their index among the events', () => {
    assert.deepEqual(
      wireEvents(cast).map(([i, code]) => [i, code]),
      [[0, 'o'], [2, 'o'], [4, 'o']],
    );
  });
});
