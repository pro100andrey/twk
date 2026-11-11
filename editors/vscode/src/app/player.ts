// A recording played back in a terminal view of its own, as `twk play`
// plays one: what the program wrote, at its times (each pause cut to the
// recording's idle_time_limit), the view at the recording's size; what the
// view sends (the answers to the queries in the recording among it) goes
// nowhere. It plays, pauses, goes a frame on or back and starts again, a
// frame as twk_test's screenFrames takes one (core/cast.ts's castSteps), from
// the bar of its view or keys typed in it: Space, Right or `.`, Left or
// `,`, Home or `r`; a recording's markers (its `m` events) are places to go
// to, `]` for the next and `[` for the one before or a click on the track,
// as `twk play` goes to them: each marker is a stop, several on one step too.
import { Cast, CastMarker, CastStep, castMarkers, castSteps, markerLabel } from '../core/cast';
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
  '[': 'previousMarker',
  ']': 'nextMarker',
  r: 'restart',
  '\x1b[H': 'restart',
};

/** Resets the terminal: what the recording left on, the screen and its modes (RIS). */
const reset = '\x1bc';

export class Player implements Screen {
  private readonly steps: readonly CastStep[];
  /** When each step is played, in seconds from the start, its pauses cut. */
  private readonly due: readonly number[];
  /** The recording's markers. */
  private readonly markers: readonly CastMarker[];
  /** The markers as the state tells them, made once. */
  private readonly markerList: readonly { label: string; time: number }[];
  /** The marker a marker key or a click last went to (from 1), while the screen is still the one it showed. */
  private pin: number | undefined;
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
  private readonly tests = new Emitter<void>();
  /** The bar's Test button was pressed: a test of the recording is asked for. */
  readonly onDidAskTest = this.tests.event;
  private readonly inputAsks = new Emitter<void>();
  /** The bar's Keys button was pressed: the recording's keys are asked to be typed into an app. */
  readonly onDidAskInput = this.inputAsks.event;
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
    this.markers = castMarkers(cast, this.steps);
    this.markerList = this.markers.map((m) => ({ label: markerLabel(m.label), time: m.time }));
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
      view.onMarker((n) => this.goToMarker(n)),
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
    const markers = this.markerList;
    return {
      playing: this.playing,
      frame: this.steps.slice(0, this.shown).filter((s) => s.frame > 0).length,
      frames,
      time: last?.time ?? 0,
      duration: this.cast.events.at(-1)?.time ?? 0,
      ...(markers.length > 0 ? { markers, marker: this.reached() } : {}),
    };
  }

  /** The markers the screen shown has reached: those at or before it, and the pinned one where it is exactly at its place. */
  private reached(): number {
    const k = this.pin;
    if (k !== undefined && k > 0 && this.markers[k - 1]?.at === this.shown) {
      return k;
    }
    return this.shown === 0 ? 0 : this.markers.filter((m) => m.at <= this.shown).length;
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
    if (c === 'toggle' || c === 'step' || c === 'back' || c === 'restart') {
      this.pin = undefined;
    }
    switch (c) {
      case 'nextMarker':
      case 'previousMarker': {
        const now = this.reached();
        // the stop as a count of markers: the next, or the one before the
        // screen (the one shown is not "before" it when the screen is
        // exactly its place); none after the last or before the first
        const k =
          c === 'nextMarker'
            ? now < this.markers.length
              ? now + 1
              : 0
            : now > 0 && this.markers[now - 1].at === this.shown
              ? now - 1
              : now;
        this.goToMarker(k);
        break;
      }
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
      case 'test':
        this.tests.fire();
        break;
      case 'input':
        this.inputAsks.fire();
        break;
    }
  }

  /** Paused, the screen as at the place of marker [k] (from 1) among the events; none such stays where it is. */
  goToMarker(k: number): void {
    this.pause();
    if (this.disposed) {
      return;
    }
    if (Number.isInteger(k) && k >= 1 && k <= this.markers.length) {
      this.pin = k;
      this.seek(this.markers[k - 1].at);
    }
    this.told();
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
    [this.changes, this.tests, this.inputAsks, this.outputs, this.inputs, this.notes, this.resizes, this.disposes].forEach((e) => e.dispose());
  }
}
