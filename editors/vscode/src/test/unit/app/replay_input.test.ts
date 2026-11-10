// A recording's keys typed into a live app (app/replay_input.ts) on a fake
// clock: at their recorded times counted from the recording's first output,
// or a step each time asked; the answers never typed; ended by the last
// keys, a stop, the terminal closing or the app going away.
import * as assert from 'node:assert/strict';

import { InputReplay, InputTarget } from '../../../app/replay_input';
import { parseCast } from '../../../core/cast';
import { Emitter } from '../../../core/events';
import { FakeClock } from '../fakes';

const recording = [
  '{"version": 2, "width": 20, "height": 3}',
  '[1.0, "o", "Count: 0"]',
  '[1.5, "i", "\\u001b[?62;4c\\u001b[A"]',
  '[1.6, "o", "Count: 1"]',
  '[2.0, "i", "\\u001b[?2026;2$y"]',
  '[3.5, "i", "q"]',
].join('\n');

class FakeTarget implements InputTarget {
  readonly name = 'counter.dart';
  readonly typed: string[] = [];
  hasApp = true;
  private readonly disposes = new Emitter<void>();
  readonly onDidDispose = this.disposes.event;
  type(text: string): void {
    this.typed.push(text);
  }
  close(): void {
    this.disposes.fire();
  }
}

describe('a recording\'s keys typed into an app', () => {
  let clock: FakeClock;
  let target: FakeTarget;

  beforeEach(() => {
    clock = new FakeClock();
    target = new FakeTarget();
  });

  const replay = (mode: 'timed' | 'steps', speed?: number) => new InputReplay('counter.cast', parseCast(recording), target, mode, clock, speed);

  it('types the keys, not the answers, at their times counted from the recording\'s first output', () => {
    const r = replay('timed');
    const states: number[] = [];
    r.onDidChange((s) => states.push(s.typed));
    r.start();
    assert.deepEqual(r.state, { typed: 0, total: 2 });
    clock.elapse(499);
    assert.deepEqual(target.typed, []);
    clock.elapse(1);
    assert.deepEqual(target.typed, ['\x1b[A']);
    clock.elapse(1999);
    assert.deepEqual(target.typed, ['\x1b[A']);
    clock.elapse(1);
    assert.deepEqual(target.typed, ['\x1b[A', 'q']);
    assert.deepEqual(r.state, { typed: 2, total: 2, ended: 'done' });
    assert.deepEqual(states, [1, 2]);
    assert.equal(clock.pending, 0);
  });

  it('goes faster by the factor', () => {
    replay('timed', 2).start();
    clock.elapse(250);
    assert.deepEqual(target.typed, ['\x1b[A']);
    clock.elapse(1000);
    assert.deepEqual(target.typed, ['\x1b[A', 'q']);
  });

  it('types a step each time asked, and nothing by itself', () => {
    const r = replay('steps');
    r.start();
    clock.elapse(60000);
    assert.deepEqual(target.typed, []);
    assert.equal(clock.pending, 0);
    assert.equal(r.next, '\x1b[A');
    r.step();
    assert.deepEqual(target.typed, ['\x1b[A']);
    assert.equal(r.next, 'q');
    assert.equal(r.isEnded, false);
    r.step();
    assert.deepEqual(r.state, { typed: 2, total: 2, ended: 'done' });
    r.step();
    assert.deepEqual(target.typed, ['\x1b[A', 'q']);
  });

  it('types the next keys at once when asked while it waits for their time', () => {
    const r = replay('timed');
    r.start();
    r.step();
    assert.deepEqual(target.typed, ['\x1b[A']);
    clock.elapse(2000);
    assert.deepEqual(target.typed, ['\x1b[A', 'q']);
  });

  it('stops, and types nothing more', () => {
    const r = replay('timed');
    r.start();
    r.stop();
    assert.deepEqual(r.state, { typed: 0, total: 2, ended: 'stopped' });
    assert.equal(clock.pending, 0);
    clock.elapse(10000);
    assert.deepEqual(target.typed, []);
  });

  it('ends with the terminal, and where the app went away', () => {
    const r = replay('timed');
    r.start();
    target.close();
    assert.equal(r.state.ended, 'the terminal was closed');
    assert.equal(clock.pending, 0);

    const t2 = new FakeTarget();
    const r2 = new InputReplay('counter.cast', parseCast(recording), t2, 'timed', clock);
    r2.start();
    clock.elapse(500);
    t2.hasApp = false;
    clock.elapse(2000);
    assert.deepEqual(t2.typed, ['\x1b[A']);
    assert.deepEqual(r2.state, { typed: 1, total: 2, ended: 'the app went away' });
  });

  it('has nothing to do for a recording without keys', () => {
    const r = new InputReplay('x.cast', parseCast('{"version": 2, "width": 20, "height": 3}\n[1.0, "o", "a"]'), target, 'steps', clock);
    r.start();
    assert.deepEqual(r.state, { typed: 0, total: 0, ended: 'done' });
  });
});
