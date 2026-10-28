// A twk terminal's session recorded (app/recording.ts) over a fake view and
// clock, into a sink in memory: the header, what was written and typed and
// the sizes at their times, a pause cut; begun on the alternate screen with
// the app's whole screen; one recording at a time, its title saying so; its
// end with the terminal, and a sink that fails.
import * as assert from 'node:assert/strict';

import { CastSink } from '../../../app/ports';
import { Recording, Recordings } from '../../../app/recording';
import { TwkTerminal } from '../../../app/terminal';
import { parseCast } from '../../../core/cast';
import { FakeClock, FakeDesktop, FakeLog, FakeSettings, FakeView, realShell } from '../fakes';

/** A sink in memory, failing from its [failAfter]th write. */
class MemorySink implements CastSink {
  text = '';
  closed = false;
  writes = 0;
  constructor(private readonly failAfter = Infinity) {}
  write(text: string): void {
    if (++this.writes > this.failAfter) {
      throw new Error('ENOSPC: no space left on device');
    }
    this.text += text;
  }
  async close(): Promise<void> {
    this.closed = true;
  }
}

describe('recording a twk terminal', () => {
  let clock: FakeClock;
  let view: FakeView;
  let terminal: TwkTerminal;
  let recordings: Recordings;
  let redraws: number;
  let alternate: boolean;

  beforeEach(async () => {
    clock = new FakeClock();
    clock.time = 5000;
    view = new FakeView('counter.dart');
    view.columns = 40;
    view.lines = 10;
    alternate = false;
    view.snapshot = async () => ({ buffer: alternate ? 'alternate' : 'normal', rows: [] });
    terminal = new TwkTerminal('counter.dart', { view, startShell: realShell, settings: new FakeSettings(), log: new FakeLog(), desktop: new FakeDesktop() });
    await terminal.start();
    redraws = 0;
    recordings = new Recordings({
      clock,
      epochSeconds: () => 1700000000.75,
      term: () => 'xterm-256color',
      redrawOf: () => async () => {
        redraws++;
        // what the app paints of all of itself, written to its terminal
        await terminal.write(Buffer.from('\x1b[?2026h\x1b[1;1HCount: 3\x1b[?2026l'));
      },
    });
  });

  afterEach(() => terminal.dispose());

  it('writes the header, what was written, typed and sized at its times, every pause cut to 2 s', async () => {
    const sink = new MemorySink();
    const recording = await recordings.start(terminal, sink);
    assert.equal(redraws, 1);
    clock.elapse(250);
    view.type('\x1b[A');
    clock.elapse(50);
    await terminal.write(Buffer.from('\x1b[1;8H4'));
    clock.elapse(10000);
    view.resize(50, 12);
    await terminal.write(Buffer.from('\xe2\x94', 'latin1'));
    clock.elapse(1);
    await terminal.write(Buffer.from('\x80', 'latin1'));
    const end = await recording.stop();
    assert.ok(sink.closed);
    const cast = parseCast(sink.text);
    assert.deepEqual(cast.header, { width: 40, height: 10, timestamp: 1700000000, idleTimeLimit: 2, title: 'counter.dart', env: { TERM: 'xterm-256color' } });
    assert.deepEqual(
      cast.events.map((e) => [e.time, e.code, e.data]),
      [
        [0, 'o', '\x1b[?2026h\x1b[1;1HCount: 3\x1b[?2026l'],
        [0.25, 'i', '\x1b[A'],
        [0.3, 'o', '\x1b[1;8H4'],
        [2.3, 'r', '50x12'],
        [2.301, 'o', '─'],
      ],
    );
    assert.deepEqual(end, { events: 5, seconds: 2.301 });
  });

  it('begun on the alternate screen, begins there, with the first output: its first frame a whole screen', async () => {
    alternate = true;
    const sink = new MemorySink();
    const recording = await recordings.start(terminal, sink);
    await recording.stop();
    assert.deepEqual(
      parseCast(sink.text).events.map((e) => e.data),
      ['\x1b[?1049h\x1b[H\x1b[2J\x1b[?2026h\x1b[1;1HCount: 3\x1b[?2026l'],
    );
  });

  it("one at a time for a terminal, its title saying so; the extension's own lines recorded too", async () => {
    const sink = new MemorySink();
    const recording = await recordings.start(terminal, sink);
    assert.match(view.title, /· ● recording$/);
    assert.equal(recordings.of(terminal), recording);
    await assert.rejects(recordings.start(terminal, new MemorySink()), /counter\.dart is recorded already/);
    terminal.say('twk: the app went away\r\n');
    await recording.stop();
    assert.doesNotMatch(view.title, /recording/);
    assert.equal(recordings.of(terminal), undefined);
    assert.equal(parseCast(sink.text).events.at(-1)?.data, 'twk: the app went away\r\n');
    const again = await recordings.start(terminal, new MemorySink());
    await again.stop();
  });

  it('ends when its terminal is closed', async () => {
    const sink = new MemorySink();
    const ended: number[] = [];
    recordings.onDidEnd(({ end }) => ended.push(end.events));
    const recording = await recordings.start(terminal, sink);
    await terminal.dispose();
    await recording.stop();
    assert.ok(sink.closed);
    assert.deepEqual(ended, [1]);
    assert.deepEqual(recordings.all(), []);
  });

  it('a sink that fails ends it, saying why; one that fails at once starts none', async () => {
    const sink = new MemorySink(2);
    const ends: (Error | undefined)[] = [];
    recordings.onDidEnd(({ end }) => ends.push(end.error));
    await recordings.start(terminal, sink);
    await terminal.write(Buffer.from('more'));
    await new Promise((r) => setImmediate(r));
    assert.match(String(ends[0]), /ENOSPC/);
    assert.ok(sink.closed);
    assert.deepEqual(recordings.all(), []);
    assert.doesNotMatch(view.title, /recording/);

    const none = new MemorySink(0);
    await assert.rejects(Recording.start(terminal, none, { clock, epochSeconds: () => 0, term: undefined }), /ENOSPC/);
    assert.ok(none.closed);
  });
});
