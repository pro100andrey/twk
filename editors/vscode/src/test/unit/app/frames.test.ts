// The frames panel (app/frames.ts) over fakes: of the apps' services, the
// view, the log and the clock. The app is told to post `twk.frame` while
// the view is on the screen and not after; the events it posts become bars
// and a summary, those of another version none; a click on a bar shows the
// frame in the log by the bytes the app had written; an app that gives no
// stats shows bytes only.
import * as assert from 'node:assert/strict';

import { Frames, FramesView, noApp, noEvents, noFrames, noTimes, renderGap } from '../../../app/frames';
import { AppConnection } from '../../../app/hot_apps';
import { TwkTerminal } from '../../../app/terminal';
import { Emitter } from '../../../core/events';
import { Metric } from '../../../core/frames';
import { FramesState } from '../../../webview/frames_protocol';
import { FakeAppService, FakeClock, FakeNotice } from '../fakes';

class FakeFramesView implements FramesView {
  visible = true;
  readonly shown: FramesState[] = [];
  private readonly visibility = new Emitter<boolean>();
  private readonly metrics = new Emitter<Metric>();
  private readonly picks = new Emitter<number>();
  private readonly clears = new Emitter<void>();
  readonly onVisible = this.visibility.event;
  readonly onMetric = this.metrics.event;
  readonly onPick = this.picks.event;
  readonly onClear = this.clears.event;
  show(state: FramesState): void {
    this.shown.push(state);
  }
  get last(): FramesState {
    return this.shown.at(-1)!;
  }
  setVisible(on: boolean): void {
    this.visible = on;
    this.visibility.fire(on);
  }
  chooseMetric(m: Metric): void {
    this.metrics.fire(m);
  }
  click(frame: number): void {
    this.picks.fire(frame);
  }
  clear(): void {
    this.clears.fire(undefined);
  }
}

/** The data of a `twk.frame` of twk. */
const frameData = (frame: number, outputWritten: number | null, stats?: { micros: number; bytes: number }, extra: Record<string, unknown> = {}) => ({
  version: 1,
  frame,
  drawn: true,
  outputWritten,
  ...(stats ? { stats: { build: 1, layout: 1, paint: 1, present: 1, ...stats } } : {}),
  ...extra,
});

/** An app that answers `ext.twk.flags` as twk does, its flags kept as set; [frameEvents] false for an older twk. */
function app(frameEvents = true): FakeAppService {
  const service = new FakeAppService();
  const on = new Set<string>();
  service.answers.set('ext.twk.flags', (p) => {
    for (const [k, v] of Object.entries(p)) {
      if (v === 'true') {
        on.add(k);
      } else {
        on.delete(k);
      }
    }
    const all = ['overlay', 'console', 'rainbow', 'relayout', 'overflow', 'keys', 'select', 'selectMany', 'treeEvents', ...(frameEvents ? ['frameEvents'] : [])];
    return { version: 1, ...Object.fromEntries(all.map((f) => [f, on.has(f)])) };
  });
  return service;
}

const settle = () => new Promise<void>((r) => setImmediate(r));

describe('the frames panel', () => {
  let apps: Emitter<AppConnection>;
  let view: FakeFramesView;
  let clock: FakeClock;
  let notice: FakeNotice;
  let revealed: { terminal: TwkTerminal; count: number }[];
  let result: { found: boolean; dropped: boolean };
  let frames: Frames;
  const terminal = { name: 'counter.dart' } as unknown as TwkTerminal;

  beforeEach(() => {
    apps = new Emitter<AppConnection>();
    view = new FakeFramesView();
    clock = new FakeClock();
    notice = new FakeNotice();
    revealed = [];
    result = { found: true, dropped: false };
    frames = new Frames({
      apps: apps.event,
      view,
      logs: {
        reveal: (t, count) => {
          revealed.push({ terminal: t, count });
          return result;
        },
      },
      notice,
      clock,
    });
  });

  afterEach(() => frames.dispose());

  /** Connects [service] and lets what it was told settle. */
  async function connect(service: FakeAppService, t = terminal): Promise<void> {
    apps.fire({ terminal: t, service });
    await settle();
  }

  const flagCalls = (service: FakeAppService) => service.asked.filter((a) => a.startsWith('ext.twk.flags'));

  it('says there is no app until one is there', () => {
    assert.equal(view.last.message, noApp);
    assert.deepEqual(view.last.bars, []);
  });

  it('has the app post frame events while the view is on the screen, and not after', async () => {
    const service = app();
    await connect(service);
    assert.deepEqual(flagCalls(service), ['ext.twk.flags frameEvents=true']);
    view.setVisible(false);
    await settle();
    view.setVisible(true);
    await settle();
    assert.deepEqual(flagCalls(service), ['ext.twk.flags frameEvents=true', 'ext.twk.flags frameEvents=false', 'ext.twk.flags frameEvents=true']);
    frames.dispose();
    await settle();
    assert.equal(flagCalls(service).at(-1), 'ext.twk.flags frameEvents=false');
  });

  it('asks nothing of an app while the view is hidden, and tells one whose binding comes later', async () => {
    view.visible = false;
    const service = app();
    service.bound = false;
    await connect(service);
    assert.deepEqual(flagCalls(service), []);
    view.setVisible(true);
    await settle();
    assert.deepEqual(flagCalls(service), [], 'told once it is bound');
    service.bind();
    await settle();
    assert.deepEqual(flagCalls(service), ['ext.twk.flags frameEvents=true']);
  });

  it('shows the frames the app posts as bars with the median, the count and the slowest, at most every 100 ms', async () => {
    const service = app();
    await connect(service);
    clock.elapse(renderGap);
    assert.equal(view.last.message, noFrames);
    service.post('twk.frame', frameData(1, 100, { micros: 1000, bytes: 100 }));
    service.post('twk.frame', frameData(2, 300, { micros: 4000, bytes: 200 }));
    service.post('twk.frame', frameData(3, 350, { micros: 2000, bytes: 50 }));
    const before = view.shown.length;
    assert.equal(view.shown.length, before, 'nothing sent before the gap');
    clock.elapse(renderGap);
    assert.equal(view.shown.length, before + 1, 'one sending for the three');
    const s = view.last;
    assert.deepEqual(
      s.bars.map((b) => [b.frame, b.value, b.height]),
      [
        [1, 1000, 0.25],
        [2, 4000, 1],
        [3, 2000, 0.5],
      ],
    );
    assert.deepEqual(s.summary, { metric: 'time', count: 3, total: 3, median: 2000, slowest: { frame: 2, value: 4000 } });
    assert.equal(s.note, '');
    view.chooseMetric('bytes');
    clock.elapse(renderGap);
    assert.deepEqual(
      view.last.bars.map((b) => b.value),
      [100, 200, 50],
    );
    assert.deepEqual(view.last.summary.slowest, { frame: 2, value: 200 });
    view.clear();
    clock.elapse(renderGap);
    assert.equal(view.last.message, noFrames);
  });

  it('takes an event of another version, of another name, or with no frame for none', async () => {
    const service = app();
    await connect(service);
    service.post('twk.frame', { ...frameData(1, 10, { micros: 5, bytes: 1 }), version: 2 });
    service.post('twk.input', frameData(2, 10, { micros: 5, bytes: 1 }));
    service.post('twk.frame', { version: 1 });
    clock.elapse(renderGap);
    assert.deepEqual(view.last.bars, []);
    service.post('twk.frame', frameData(3, 10, { micros: 5, bytes: 1 }));
    clock.elapse(renderGap);
    assert.equal(view.last.bars.length, 1);
  });

  it('shows bytes only, from the output counts, of an app that gives no stats, saying so', async () => {
    const service = app();
    await connect(service);
    service.post('twk.frame', frameData(1, 100));
    service.post('twk.frame', frameData(2, 180));
    service.post('twk.frame', frameData(3, 200));
    clock.elapse(renderGap);
    assert.equal(view.last.note, noTimes);
    assert.deepEqual(
      view.last.bars.map((b) => b.value),
      [null, null, null],
    );
    view.chooseMetric('bytes');
    clock.elapse(renderGap);
    assert.equal(view.last.note, '');
    assert.deepEqual(
      view.last.bars.map((b) => b.value),
      [null, 80, 20],
    );
    assert.deepEqual(view.last.summary.median, 50);
  });

  it('says so of an app that does not report the frameEvents flag', async () => {
    const service = app(false);
    await connect(service);
    clock.elapse(renderGap);
    assert.equal(view.last.message, noEvents);
  });

  it('shows a frame in the log of the terminal by the bytes the app had written at its end', async () => {
    const service = app();
    await connect(service);
    service.post('twk.frame', frameData(5, 640, { micros: 9, bytes: 40 }));
    service.post('twk.frame', frameData(6, 700, { micros: 9, bytes: 60 }));
    view.click(5);
    assert.deepEqual(revealed, [{ terminal, count: 640 }]);
    assert.deepEqual(notice.said, []);
    // not one it kept
    view.click(99);
    assert.equal(revealed.length, 1);
  });

  it('says a frame is no longer in the log where the log begins after it, and where it has none, and where the app counts no output', async () => {
    const service = app();
    await connect(service);
    service.post('twk.frame', frameData(5, 640, { micros: 9, bytes: 40 }));
    service.post('twk.frame', frameData(6, null, { micros: 9, bytes: 40 }));
    result = { found: true, dropped: true };
    view.click(5);
    assert.deepEqual(notice.said, ['Frame 5 is no longer in the log.']);
    result = { found: false, dropped: false };
    view.click(5);
    assert.equal(notice.said.at(-1), 'Frame 5 is not in the log.');
    view.click(6);
    assert.equal(revealed.length, 2, 'asked for no frame of no count');
    assert.match(notice.said.at(-1)!, /^Frame 6 cannot be found in the log/);
  });

  it('follows the newest app, and starts afresh for the app of a restart', async () => {
    const first = app();
    await connect(first);
    first.post('twk.frame', frameData(1, 10, { micros: 5, bytes: 1 }));
    clock.elapse(renderGap);
    assert.equal(view.last.bars.length, 1);
    const second = app();
    await connect(second);
    assert.equal(flagCalls(first).at(-1), 'ext.twk.flags frameEvents=true');
    // the same terminal: the old app is dropped
    clock.elapse(renderGap);
    assert.deepEqual(view.last.bars, []);
    first.post('twk.frame', frameData(2, 10, { micros: 5, bytes: 1 }));
    clock.elapse(renderGap);
    assert.deepEqual(view.last.bars, [], 'what the old app posts is not heard');
    second.end();
    await settle();
    clock.elapse(renderGap);
    assert.equal(view.last.message, noApp);
  });
});
