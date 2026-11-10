// A recording's keys typed into a live app of a twk terminal, to reproduce
// what the recording shows (a bug): the `i` events with the terminal's
// answers taken out (core/replay_input.ts), either at their recorded times
// or one step each time it is asked. Timed, each keys step is typed at the
// time the recording has them, counted from its first output (the app is
// already up) and from the moment the replay began, so a late timer or a
// step typed by hand ahead does not move the others; the times already have
// the recording's pauses cut. The app's own queries are answered by the
// terminal as they always are; keys typed by hand meanwhile reach the app
// as well, in between.
import { Cast } from '../core/cast';
import { Clock, Disposable, Emitter, Event } from '../core/events';
import { ReplayStep, replaySteps } from '../core/replay_input';

/** What the keys are typed into: a twk terminal with an app. */
export interface InputTarget {
  readonly name: string;
  /** Types [text] as if from the keyboard. */
  type(text: string): void;
  /** Whether an app is connected to take them. */
  readonly hasApp: boolean;
  readonly onDidDispose: Event<void>;
}

export type ReplayMode = 'timed' | 'steps';

export interface ReplayState {
  /** How many steps of keys were typed. */
  readonly typed: number;
  readonly total: number;
  /** Why it ended, or undefined while it goes on: `done`, `stopped`, or what went wrong. */
  readonly ended?: string;
}

export class InputReplay {
  readonly steps: readonly ReplayStep[];
  private readonly origin: number;
  private typed = 0;
  /** The clock's time when it began. */
  private began = 0;
  private timer: Disposable | undefined;
  private ended: string | undefined;
  private readonly changes = new Emitter<ReplayState>();
  /** It typed a step, or ended. */
  readonly onDidChange = this.changes.event;
  private readonly listening: Disposable;

  constructor(
    readonly name: string,
    cast: Cast,
    private readonly target: InputTarget,
    readonly mode: ReplayMode,
    private readonly clock: Clock,
  ) {
    this.steps = replaySteps(cast);
    this.origin = cast.events.find((e) => e.code === 'o')?.time ?? 0;
    this.listening = target.onDidDispose(() => this.end('the terminal was closed'));
  }

  get state(): ReplayState {
    return { typed: this.typed, total: this.steps.length, ...(this.ended === undefined ? {} : { ended: this.ended }) };
  }

  /** The keys of the step to come next, if any. */
  get next(): string | undefined {
    return this.steps[this.typed]?.keys;
  }

  get isEnded(): boolean {
    return this.ended !== undefined;
  }

  /** Begins: timed, the first step is scheduled; stepping, it waits for [step]. */
  start(): void {
    if (this.steps.length === 0) {
      this.end('done');
    } else if (this.mode === 'timed') {
      this.began = this.clock.now();
      this.schedule();
    } else {
      this.changes.fire(this.state);
    }
  }

  /** Types the next step now (stepping, or timed to hurry it). */
  step(): void {
    if (this.ended !== undefined) {
      return;
    }
    this.timer?.dispose();
    this.timer = undefined;
    this.typeNext();
    if (this.mode === 'timed') {
      this.schedule();
    }
  }

  private schedule(): void {
    if (this.ended !== undefined) {
      return;
    }
    const due = this.began + (this.steps[this.typed].time - this.origin) * 1000;
    const wait = Math.max(0, due - this.clock.now());
    this.timer = this.clock.setTimeout(() => {
      this.timer = undefined;
      this.typeNext();
      this.schedule();
    }, wait);
  }

  private typeNext(): void {
    if (this.ended !== undefined) {
      return;
    }
    if (!this.target.hasApp) {
      this.end('the app went away');
      return;
    }
    this.target.type(this.steps[this.typed].keys);
    this.typed++;
    if (this.typed >= this.steps.length) {
      this.end('done');
    } else {
      this.changes.fire(this.state);
    }
  }

  /** Ends it before its last step. */
  stop(): void {
    this.end('stopped');
  }

  private end(why: string): void {
    if (this.ended !== undefined) {
      return;
    }
    this.ended = why;
    this.timer?.dispose();
    this.timer = undefined;
    this.listening.dispose();
    this.changes.fire(this.state);
  }
}
