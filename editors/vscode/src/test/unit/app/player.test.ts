// A recording played back (app/player.ts) into a headless xterm.js on a
// fake clock: at the recording's size, a frame at each frame's time (a
// pause cut to its idle limit), its bar told where it is; paused, a frame
// on and back, from the start, by the bar and by keys; what the view sends
// going nowhere; a view that loaded again shown again; closed.
import * as assert from 'node:assert/strict';

import { Player } from '../../../app/player';
import { parseCast } from '../../../core/cast';
import { FakeClock } from '../fakes';
import { HeadlessView } from '../headless_view';

const recording = [
  '{"version": 2, "width": 20, "height": 3, "idle_time_limit": 1}',
  '[0.5, "o", "\\u001b[?1049h\\u001b[?2026h\\u001b[1;1HCount: 0\\u001b[?2026l"]',
  '[0.6, "i", "\\u001b[A"]',
  '[0.7, "o", "\\u001b[?2026h\\u001b[1;8H1"]',
  '[0.8, "o", "\\u001b[?2026l"]',
  '[1.0, "r", "24x4"]',
  '[9.0, "o", "\\u001b[1;8H2\\u001b[c"]',
].join('\n');

describe('a recording played back', () => {
  let clock: FakeClock;
  let view: HeadlessView;
  let player: Player;

  beforeEach(async () => {
    clock = new FakeClock();
    view = new HeadlessView(80, 24);
    player = new Player('counter.cast', parseCast(recording), view, clock);
  });

  afterEach(() => player.dispose());

  /** What the view shows once the player wrote what it was to. */
  const shown = async () => {
    await player.settled;
    return view.rows()[0];
  };

  it('plays at its size, each frame at its time, a pause cut to the idle limit, its bar told where it is', async () => {
    await player.start();
    assert.deepEqual([view.columns, view.lines], [20, 3]);
    assert.match(view.title, /^counter\.cast · twk replay 20x3$/);
    assert.deepEqual(view.playerState, { playing: true, frame: 0, frames: 3, time: 0, duration: 9 });
    clock.elapse(499);
    assert.equal(await shown(), '');
    clock.elapse(1);
    await player.settled;
    assert.equal(await shown(), 'Count: 0');
    assert.equal(view.term.buffer.active.type, 'alternate');
    clock.elapse(300);
    assert.equal(await shown(), 'Count: 1');
    assert.deepEqual(view.playerState, { playing: true, frame: 2, frames: 3, time: 0.8, duration: 9 });
    // 8.2 s to the last, cut to 1 s
    clock.elapse(999);
    assert.equal(await shown(), 'Count: 1');
    clock.elapse(1);
    assert.equal(await shown(), 'Count: 2');
    assert.deepEqual([view.columns, view.lines], [24, 4]);
    assert.deepEqual(view.playerState, { playing: false, frame: 3, frames: 3, time: 9, duration: 9 });
  });

  it('pauses, goes a frame on and back, and starts again, from the bar and by keys', async () => {
    const inputs: string[] = [];
    player.onDidInput((b) => inputs.push(Buffer.from(b).toString('latin1')));
    await player.start(false);
    assert.equal(view.playerState?.playing, false);
    view.control('step');
    assert.equal(await shown(), 'Count: 0');
    view.type('.');
    assert.equal(await shown(), 'Count: 1');
    view.type('\x1b[C');
    assert.equal(await shown(), 'Count: 2');
    assert.deepEqual(view.playerState, { playing: false, frame: 3, frames: 3, time: 9, duration: 9 });
    // the DA1 in it answered by xterm.js: nowhere but the log
    assert.ok(inputs.some((i) => i.startsWith('\x1b[?')));
    view.control('back');
    assert.equal(await shown(), 'Count: 1');
    assert.deepEqual([view.columns, view.lines], [20, 3]);
    view.type(',');
    assert.equal(await shown(), 'Count: 0');
    view.type(' ');
    assert.equal(view.playerState?.playing, true);
    clock.elapse(300);
    assert.equal(await shown(), 'Count: 1');
    view.type(' ');
    assert.equal(view.playerState?.playing, false);
    clock.elapse(5000);
    assert.equal(await shown(), 'Count: 1');
    view.type('r');
    assert.equal(await shown(), '');
    assert.equal(view.term.buffer.active.type, 'normal');
    assert.equal(view.playerState?.frame, 0);
    clock.elapse(500);
    assert.equal(await shown(), 'Count: 0');
  });

  it('played to its end plays again from the start', async () => {
    await player.start(false);
    for (let i = 0; i < 3; i++) {
      player.step();
    }
    assert.equal(await shown(), 'Count: 2');
    player.play();
    assert.equal(await shown(), '');
    clock.elapse(500);
    assert.equal(await shown(), 'Count: 0');
  });

  it('shows what it showed again in a view that came back empty, and ends with its view', async () => {
    await player.start(false);
    player.step();
    player.step();
    await player.settled;
    view.reload();
    assert.equal(await shown(), 'Count: 1');
    let ended = false;
    player.onDidDispose(() => (ended = true));
    view.close();
    assert.ok(ended);
    assert.equal(clock.pending, 0);
  });

  it('tells that the bar asked for a test, and plays on as it was', async () => {
    await player.start(false);
    let asked = 0;
    player.onDidAskTest(() => asked++);
    player.control('test');
    assert.equal(asked, 1);
    assert.equal(player.state.playing, false);
    assert.equal(player.state.frame, 0);
  });

  it('tells that the bar asked for its keys to be typed into an app, and plays on as it was', async () => {
    await player.start(false);
    let asked = 0;
    player.onDidAskInput(() => asked++);
    player.control('input');
    assert.equal(asked, 1);
    assert.equal(player.state.playing, false);
  });

  describe('with markers', () => {
    const marked = [
      '{"version": 2, "width": 20, "height": 3}',
      '[0.0, "m", "start"]',
      '[0.5, "o", "\\u001b[1;1HA"]',
      '[0.6, "m", "a"]',
      '[0.7, "m", "b\\u001b[31m"]',
      '[1.0, "o", "\\u001b[1;1HB"]',
      `[2.0, "m", ${JSON.stringify('x'.repeat(50))}]`,
    ].join('\n');
    let marks: Player;
    let mv: HeadlessView;

    beforeEach(async () => {
      mv = new HeadlessView(80, 24);
      marks = new Player('marks.cast', parseCast(marked), mv, clock);
      await marks.start(false);
    });

    afterEach(() => marks.dispose());

    const at = () => [mv.playerState?.marker, mv.rows()[0]];

    it('tells the markers, labels cut as twk play cuts them, and which the screen has reached', () => {
      assert.deepEqual(mv.playerState?.markers, [
        { label: 'start', time: 0 },
        { label: 'a', time: 0.6 },
        { label: 'b [31m', time: 0.7 },
        { label: `${'x'.repeat(39)}…`, time: 2 },
      ]);
      assert.equal(mv.playerState?.marker, 0);
      assert.equal(player.state.markers, undefined, 'none for a recording without');
    });

    it('] and [ go to each marker as a stop: one at the start, several on a step, one after the last', async () => {
      const seen: unknown[] = [];
      for (let i = 0; i < 4; i++) {
        mv.type(']');
        await marks.settled;
        seen.push(at());
      }
      assert.deepEqual(seen, [
        [1, ''],
        [2, 'A'],
        [3, 'A'],
        [4, 'B'],
      ]);
      assert.equal(mv.playerState?.playing, false);
      // no marker after the last: where it is
      mv.type(']');
      await marks.settled;
      assert.deepEqual(at(), [4, 'B']);
      const back: unknown[] = [];
      for (let i = 0; i < 4; i++) {
        mv.type('[');
        await marks.settled;
        back.push(at());
      }
      assert.deepEqual(back, [
        [3, 'A'],
        [2, 'A'],
        [1, ''],
        [1, ''],
      ]);
    });

    it('the bar asks for them too, a click goes to the marker, any other move leaves the stop', async () => {
      mv.control('nextMarker');
      mv.clickMarker(3);
      await marks.settled;
      assert.deepEqual(at(), [3, 'A']);
      mv.clickMarker(9);
      mv.clickMarker(0);
      assert.deepEqual(at(), [3, 'A']);
      mv.control('step');
      await marks.settled;
      // the pin is left: the screen is the last, which has reached the marker after the step too
      assert.deepEqual(at(), [4, 'B']);
      mv.control('back');
      await marks.settled;
      assert.deepEqual(at(), [3, 'A']);
      mv.control('previousMarker');
      assert.equal(mv.playerState?.marker, 2);
    });

    it('goes paused, from a recording that plays', async () => {
      marks.play();
      assert.equal(mv.playerState?.playing, true);
      mv.type(']');
      assert.equal(mv.playerState?.playing, false);
      assert.equal(clock.pending, 0);
    });
  });
});
