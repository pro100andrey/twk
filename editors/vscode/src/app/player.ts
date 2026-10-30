// A recording played back in a terminal view of its own, as `twk play`
// plays one: what the program wrote, at its times (each pause cut to the
// recording's idle_time_limit), the view at the recording's size; what the
// view sends (the answers to the queries in the recording among it) goes
// nowhere. It plays, pauses, goes a frame on or back and starts again, a
// frame as twk_test's screenFrames takes one (core/cast.ts's castSteps), from
// the bar of its view or keys typed in it: Space, Right or `.`, Left or
// `,`, Home or `r`.
import { Cast, CastStep, castSteps } from '../core/cast';
import { Clock, Disposable, Emitter } from '../core/events';
import { PlayerControl, PlayerState } from '../webview/protocol';
import { Output, Screen, TerminalView } from './ports';

/** What the keys typed in a player's view ask. */
const keys: Readonly<Record<string, PlayerControl>> = {
  ' ': 'toggle',
  '.': 'step',
  '\x1b[C': 'step',
  ',': 'back',
  '\x1b[D': 'back',
  r: 'restart',
  '\x1b[H': 'restart',
};

/** Resets the terminal: what the recording left on, the screen and its modes (RIS). */
const reset = '\x1bc';

export class Player implements Screen {
  private readonly steps: readonly CastStep[];
  /** When each step is played, in seconds from the start, its pauses cut. */
  private readonly due: readonly number[];
  /** The steps written. */
  private shown = 0;
  private playing = false;
  private timer: Disposable | undefined;
  /** The writes to the view, one after another. */
  private writing: Promise<void> = Promise.resolve();
  private readonly listening: Disposable[];
  private disposed = false;
  private readonly changes = new Emitter<PlayerState>();
  /** It played, paused or went to another frame. */
  readonly onDidChange = this.changes.event;
  private readonly outputs = new Emitter<Output>();
  readonly onDidOutput = this.outputs.event;
  private readonly inputs = new Emitter<Uint8Array>();
  readonly onDidInput = this.inputs.event;
  private readonly notes = new Emitter<string>();
  readonly onDidNote = this.notes.event;
  private readonly resizes = new Emitter<void>();
  readonly onDidResize = this.resizes.event;
  private readonly disposes = new Emitter<void>();
  readonly onDidDispose = this.disposes.event;

  constructor(
    /** What it is called: the recording's file. */
    readonly name: string,
    readonly cast: Cast,
    readonly view: TerminalView,
    private readonly clock: Clock,
    /** How many times faster than recorded. */
    private readonly speed = 1,
  ) {
    this.steps = castSteps(cast);
    const limit = cast.header.idleTimeLimit;
    let at = 0;
    let last = 0;
    this.due = this.steps.map((s) => {
      const gap = Math.max(s.time - last, 0);
      last = s.time;
      at += limit === undefined || limit <= 0 ? gap : Math.min(gap, limit);
      return at;
    });
    this.listening = [
      view.onControl((c) => this.control(c)),
      view.onInput((bytes) => {
        this.inputs.fire(bytes);
        const c = keys[Buffer.from(bytes).toString('latin1')];
        if (c) {
          this.control(c);
        }
      }),
      view.onResize(() => this.resizes.fire()),
      // a webview that loaded again shows nothing: what was shown, again
      view.onReload(() => this.seek(this.shown)),
      view.onClose(() => this.dispose()),
    ];
  }

  /** Where it is. */
  get state(): PlayerState {
    const frames = this.steps.filter((s) => s.frame > 0).length;
    const last = this.shown > 0 ? this.steps[this.shown - 1] : undefined;
    return {
      playing: this.playing,
      frame: this.steps.slice(0, this.shown).filter((s) => s.frame > 0).length,
      frames,
      time: last?.time ?? 0,
      duration: this.cast.events.at(-1)?.time ?? 0,
    };
  }

  /** Shows the recording's first screen, its size and its bar, then plays when [play]. */
  async start(play = true): Promise<void> {
    await this.view.ready;
    this.view.fixSize(this.cast.header.width, this.cast.header.height);
    this.view.setTitle(this.title());
    this.told();
    if (play) {
      this.play();
    }
  }

  private title(): string {
    const { width, height } = this.cast.header;
    return `${this.name} · twk replay ${width}x${height}`;
  }

  /** Does what a button of the bar, or a key, asks. */
  control(c: PlayerControl): void {
    switch (c) {
      case 'toggle':
        if (this.playing) {
          this.pause();
        } else {
          this.play();
        }
        break;
      case 'step':
        this.step();
        break;
      case 'back':
        this.back();
        break;
      case 'restart':
        this.restart();
        break;
    }
  }

  /** Plays on from where it is; from the start once it ended. */
  play(): void {
    if (this.disposed || this.playing) {
      return;
    }
    if (this.shown >= this.steps.length) {
      this.seek(0);
    }
    this.playing = true;
    this.schedule();
    this.told();
  }

  pause(): void {
    if (!this.playing) {
      return;
    }
    this.playing = false;
    this.timer?.dispose();
    this.timer = undefined;
    this.told();
  }

  /** Paused, the next frame shown. */
  step(): void {
    this.pause();
    if (this.shown < this.steps.length) {
      this.show(this.shown);
      this.told();
    }
  }

  /** Paused, the frame before the one shown shown. */
  back(): void {
    this.pause();
    if (this.shown > 0) {
      this.seek(this.shown - 1);
      this.told();
    }
  }

  /** Paused at the start, nothing shown, then played. */
  restart(): void {
    this.pause();
    this.seek(0);
    this.play();
  }

  /** Settles once what it was asked to show was shown. */
  get settled(): Promise<void> {
    return this.writing;
  }

  /** The terminal reset and the first [n] steps written at once. */
  private seek(n: number): void {
    this.shown = 0;
    this.notes.fire(n === 0 ? 'from the start' : `to step ${n}`);
    this.writeOut(reset);
    this.view.fixSize(this.cast.header.width, this.cast.header.height);
    let output = '';
    for (let i = 0; i < n; i++) {
      const s = this.steps[i];
      if (s.size) {
        this.writeOut(output);
        output = '';
        this.resize(s);
      }
      output += s.output;
    }
    this.writeOut(output);
    this.shown = n;
  }

  private show(i: number): void {
    const s = this.steps[i];
    this.resize(s);
    this.writeOut(s.output);
    this.shown = i + 1;
  }

  private resize(s: CastStep): void {
    if (s.size) {
      this.view.fixSize(s.size.width, s.size.height);
    }
  }

  private writeOut(text: string): void {
    if (text === '' || this.disposed) {
      return;
    }
    const bytes = new TextEncoder().encode(text);
    this.outputs.fire({ bytes, fromApp: true });
    this.writing = this.writing.then(() => this.view.write(bytes));
  }

  /** The next step at its time, after the one shown. */
  private schedule(): void {
    if (!this.playing || this.disposed || this.timer) {
      return;
    }
    if (this.shown >= this.steps.length) {
      this.playing = false;
      this.told();
      return;
    }
    const from = this.shown > 0 ? this.due[this.shown - 1] : 0;
    const wait = Math.max(0, Math.round(((this.due[this.shown] - from) * 1000) / this.speed));
    this.timer = this.clock.setTimeout(() => {
      this.timer = undefined;
      this.show(this.shown);
      this.told();
      // the next once the view parsed this one, so a slow view is not run over
      void this.writing.then(() => this.schedule());
    }, wait);
  }

  private told(): void {
    const state = this.state;
    this.view.player(state);
    this.changes.fire(state);
  }

  /** Stops playing and closes its view; once. */
  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.playing = false;
    this.timer?.dispose();
    this.listening.forEach((d) => d.dispose());
    this.view.close();
    this.disposes.fire();
    [this.changes, this.outputs, this.inputs, this.notes, this.resizes, this.disposes].forEach((e) => e.dispose());
  }
}
