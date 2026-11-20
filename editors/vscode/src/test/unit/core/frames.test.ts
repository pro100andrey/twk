// The frames panel's data (core/frames.ts): what a `twk.frame` event is
// taken for, the frames kept, the bars, the median, the count and the
// slowest; an app that gives no stats.
import * as assert from 'node:assert/strict';

import { FrameEvent, FrameHistory, FrameSample, barsOf, formatBytes, formatMicros, median, parseFrameEvent, summarize } from '../../../core/frames';

const stats = (micros: number, bytes: number) => ({ micros, build: 1, layout: 2, paint: 3, present: 4, bytes });

/** The data of a `twk.frame` of twk, [extra] over it. */
const data = (extra: Record<string, unknown> = {}) => ({ version: 1, frame: 7, drawn: true, outputWritten: 900, size: { width: 80, height: 24 }, ...extra });

const event = (frame: number, outputWritten: number | null, micros?: number, bytes = 0): FrameEvent => ({
  frame,
  drawn: true,
  outputWritten,
  ...(micros === undefined ? {} : { stats: stats(micros, bytes) }),
});

const sample = (frame: number, micros: number | null, bytes: number | null): FrameSample => ({ frame, outputWritten: null, micros, bytes });

describe('twk.frame events', () => {
  it('reads the frame, whether it was drawn, the output count and the stats', () => {
    assert.deepEqual(parseFrameEvent(data()), { frame: 7, drawn: true, outputWritten: 900 });
    assert.deepEqual(parseFrameEvent(data({ stats: stats(1500, 40) })), { frame: 7, drawn: true, outputWritten: 900, stats: stats(1500, 40) });
    assert.deepEqual(parseFrameEvent(data({ drawn: false, outputWritten: null })), { frame: 7, drawn: false, outputWritten: null });
  });

  it('takes an event of another version, or one that is no frame, for none', () => {
    assert.equal(parseFrameEvent(data({ version: 2 })), undefined);
    assert.equal(parseFrameEvent({ frame: 7, drawn: true }), undefined);
    assert.equal(parseFrameEvent(data({ frame: -1 })), undefined);
    assert.equal(parseFrameEvent(data({ frame: 'x' })), undefined);
    assert.equal(parseFrameEvent(data({ drawn: 1 })), undefined);
    assert.equal(parseFrameEvent([]), undefined);
    assert.equal(parseFrameEvent(undefined), undefined);
  });

  it('reads an event with no stats, or with stats it does not read, as one of an app that gives none', () => {
    assert.equal(parseFrameEvent(data())!.stats, undefined);
    assert.equal(parseFrameEvent(data({ stats: { micros: 5 } }))!.stats, undefined);
    assert.equal(parseFrameEvent(data({ stats: { ...stats(5, 1), paint: 'x' } }))!.stats, undefined);
    assert.equal(parseFrameEvent(data({ stats: { ...stats(5, 1), bytes: -1 } }))!.stats, undefined);
    assert.equal(parseFrameEvent(data({ outputWritten: 'x' }))!.outputWritten, null);
  });
});

describe('the frames kept', () => {
  it('keeps the time and the bytes of the stats', () => {
    const h = new FrameHistory();
    h.add(event(1, 100, 2000, 60));
    assert.deepEqual(
      h.samples.map((s) => [s.frame, s.micros, s.bytes, s.outputWritten]),
      [[1, 2000, 60, 100]],
    );
  });

  it('keeps the bytes as the difference of the output counts, and no time, where an app gives no stats', () => {
    const h = new FrameHistory();
    h.add(event(1, 100));
    h.add(event(2, 160));
    h.add(event(3, 160));
    assert.deepEqual(
      h.samples.map((s) => [s.micros, s.bytes]),
      [
        [null, null],
        [null, 60],
        [null, 0],
      ],
    );
  });

  it('counts what an event that drew nothing wrote into the next frame, and keeps no frame of it', () => {
    const h = new FrameHistory();
    h.add(event(1, 100));
    assert.equal(h.add({ frame: 1, drawn: false, outputWritten: 130 }), undefined);
    h.add(event(2, 150));
    assert.deepEqual(
      h.samples.map((s) => s.bytes),
      [null, 20],
    );
    assert.equal(h.total, 2);
  });

  it('knows no bytes where the count is not there or went back', () => {
    const h = new FrameHistory();
    h.add(event(1, null));
    h.add(event(2, 50));
    h.add(event(3, 20));
    assert.deepEqual(
      h.samples.map((s) => s.bytes),
      [null, null, null],
    );
  });

  it('keeps the last frames only, and counts them all', () => {
    const h = new FrameHistory(3);
    for (let i = 1; i <= 5; i++) {
      h.add(event(i, i * 10, 100 * i, 1));
    }
    assert.deepEqual(
      h.samples.map((s) => s.frame),
      [3, 4, 5],
    );
    assert.equal(h.total, 5);
    h.clear();
    assert.equal(h.samples.length, 0);
    assert.equal(h.total, 0);
  });
});

describe('the bars and the summary', () => {
  const samples = [sample(1, 1000, 10), sample(2, 4000, 40), sample(3, 2000, 20)];

  it('makes a bar of each frame, as high as its share of the tallest', () => {
    const bars = barsOf(samples, 'time');
    assert.deepEqual(
      bars.map((b) => [b.frame, b.value, b.height]),
      [
        [1, 1000, 0.25],
        [2, 4000, 1],
        [3, 2000, 0.5],
      ],
    );
    assert.equal(bars[1].title, 'frame 2: 4.0 ms');
    assert.deepEqual(
      barsOf(samples, 'bytes').map((b) => b.value),
      [10, 40, 20],
    );
  });

  it('gives a frame of no known value a bar of no height, saying so, and the others by the tallest known', () => {
    const bars = barsOf([sample(1, null, null), sample(2, 500, 5)], 'time');
    assert.deepEqual(
      bars.map((b) => [b.value, b.height]),
      [
        [null, 0],
        [500, 1],
      ],
    );
    assert.equal(bars[0].title, 'frame 1: time unknown');
    assert.deepEqual(
      barsOf([sample(1, null, null)], 'bytes').map((b) => b.height),
      [0],
    );
  });

  it('says what each phase took in the title of a bar of a frame with stats', () => {
    const [bar] = barsOf([{ frame: 1, outputWritten: 1, micros: 1500, bytes: 3, stats: stats(1500, 3) }], 'time');
    assert.equal(bar.title, 'frame 1: 1.5 ms (build 1 µs, layout 2 µs, paint 3 µs, present 4 µs)');
  });

  it('counts the frames, takes the median and the slowest', () => {
    assert.deepEqual(summarize(samples, 'time', 9), { metric: 'time', count: 3, total: 9, median: 2000, slowest: { frame: 2, value: 4000 } });
    assert.deepEqual(summarize(samples, 'bytes'), { metric: 'bytes', count: 3, total: 3, median: 20, slowest: { frame: 2, value: 40 } });
  });

  it('takes the mean of the two middle values as the median of an even count, and the latest of equals as the slowest', () => {
    const even = [sample(1, 1000, 1), sample(2, 3000, 1), sample(3, 3000, 1), sample(4, 2000, 1)];
    const s = summarize(even, 'time');
    assert.equal(s.median, 2500);
    assert.deepEqual(s.slowest, { frame: 3, value: 3000 });
    assert.equal(median([5, 1, 3]), 3);
    assert.equal(median([]), undefined);
  });

  it('leaves frames of an unknown value out of the median and the slowest, and says nothing where none is known', () => {
    const s = summarize([sample(1, null, 8), sample(2, 700, 2), sample(3, null, 4)], 'time');
    assert.deepEqual(s, { metric: 'time', count: 3, total: 3, median: 700, slowest: { frame: 2, value: 700 } });
    const none = summarize([sample(1, null, null)], 'time');
    assert.deepEqual(none, { metric: 'time', count: 1, total: 1 });
    assert.deepEqual(summarize([], 'bytes'), { metric: 'bytes', count: 0, total: 0 });
  });

  it('writes microseconds and bytes as a person reads them', () => {
    assert.equal(formatMicros(850), '850 µs');
    assert.equal(formatMicros(2400), '2.4 ms');
    assert.equal(formatMicros(25000), '25 ms');
    assert.equal(formatBytes(812), '812 B');
    assert.equal(formatBytes(1200), '1.2 kB');
  });
});
