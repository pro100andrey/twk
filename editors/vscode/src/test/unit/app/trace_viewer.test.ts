// The trace viewer (app/trace_viewer.ts) over a fake panel: nothing sent
// before the page is up, then the steps, the cast and the failed step to
// begin at with its detail; the detail of each step selected; what the page
// sends that is no message is let go.
import * as assert from 'node:assert/strict';

import { TraceViewer, TraceViewers, stepRows } from '../../../app/trace_viewer';
import { parseCast } from '../../../core/cast';
import { parseTrace } from '../../../core/trace';
import { ToTrace, isToTrace } from '../../../webview/trace_protocol';
import { FakePanel } from '../fakes';
import { fixtureCast, fixtureTrace } from '../trace_fixture';

describe('the trace viewer', () => {
  const trace = parseTrace(fixtureTrace());
  const cast = parseCast(fixtureCast());
  let panel: FakePanel<ToTrace>;
  let viewer: TraceViewer;

  beforeEach(() => {
    panel = new FakePanel<ToTrace>();
    viewer = new TraceViewer('counter-1-0', trace, cast, panel);
  });

  it('is titled by its trace and sends nothing before the page is up', () => {
    assert.equal(panel.title, 'counter-1-0 · twk trace');
    assert.equal(panel.posted.length, 0);
  });

  it('sends the steps, the cast and the failed step with its detail once the page is up', () => {
    panel.send({ type: 'ready' });
    assert.deepEqual(
      panel.posted.map((m) => m.type),
      ['open', 'detail'],
    );
    const [open, detail] = panel.posted;
    assert.ok(open.type === 'open' && isToTrace(open));
    assert.equal(open.select, 1);
    assert.deepEqual([open.width, open.height], [20, 4]);
    assert.deepEqual(
      open.steps.map((s) => [s.label, s.ok, s.before, s.after]),
      [
        ['1 press {"key":"enter"}', true, 0, 2],
        ['2 tap {"key":"missing"}', false, 2, 4],
      ],
    );
    assert.deepEqual(open.steps[1].outline, { x: 0, y: 1, width: 7, height: 1 });
    assert.equal(open.steps[0].outline, null);
    assert.ok(detail.type === 'detail' && isToTrace(detail));
    assert.equal(detail.index, 1);
    assert.match(detail.detail.facts.join('\n'), /error tap: Button inc is covered by Text/);
    assert.match(detail.detail.sequences, /where\?/);
    assert.equal(detail.detail.tree, trace.trees.get('t1'));
  });

  it('sends the detail of a step selected, its log among it', () => {
    panel.send({ type: 'ready' });
    panel.posted.length = 0;
    panel.send({ type: 'select', index: 0 });
    const [m] = panel.posted;
    assert.ok(m.type === 'detail');
    assert.deepEqual(m.detail.log, ['info: pressed']);
    assert.equal(m.detail.tree, trace.trees.get('t1'));
  });

  it('lets go of what is no message, and of a step the trace has not', () => {
    panel.send({ type: 'ready' });
    panel.posted.length = 0;
    panel.send({ type: 'select', index: 9 });
    panel.send({ type: 'select', index: -1 });
    panel.send('select');
    panel.send(null);
    assert.equal(panel.posted.length, 0);
  });

  it('makes a row of each step', () => {
    assert.equal(stepRows(trace).length, 2);
  });

  it('closes its panel once, and is gone when the panel is closed', () => {
    viewer.dispose();
    assert.ok(panel.disposed);
    viewer.dispose();
    panel.send({ type: 'ready' });
    assert.equal(panel.posted.length, 0);
  });

  it('tells that its panel was closed, once', () => {
    let closed = 0;
    viewer.onClose(() => closed++);
    panel.dispose();
    viewer.dispose();
    assert.equal(closed, 1);
  });
});

describe('the trace viewers open', () => {
  const trace = parseTrace(fixtureTrace());
  const cast = parseCast(fixtureCast());
  const panels: FakePanel<ToTrace>[] = [];
  let revealed = 0;
  const make = () => {
    const panel = new FakePanel<ToTrace>();
    panel.reveal = () => revealed++;
    panels.push(panel);
    return new TraceViewer('t', trace, cast, panel);
  };

  beforeEach(() => {
    panels.length = 0;
    revealed = 0;
  });

  it('reveal the viewer of a trace shown, and make none anew', () => {
    const viewers = new TraceViewers();
    const first = viewers.open('a', make);
    assert.equal(viewers.open('a', make), first);
    assert.equal(revealed, 1);
    assert.equal(panels.length, 1);
    assert.notEqual(viewers.open('b', make), first);
  });

  it('make a new viewer of a trace whose panel was closed, never revealing the dead one', () => {
    const viewers = new TraceViewers();
    const first = viewers.open('a', make);
    panels[0].dispose();
    const second = viewers.open('a', make);
    assert.notEqual(second, first);
    assert.equal(revealed, 0);
    assert.equal(panels.length, 2);
    // the closing of the old one does not take the new one away
    first.dispose();
    assert.equal(viewers.open('a', make), second);
  });
});
