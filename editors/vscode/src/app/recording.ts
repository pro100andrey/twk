// A twk terminal's session recorded as asciicast v2 (core/cast.ts), as
// `twk record` records one: what was written to the terminal ("o"), what
// it sent ("i": keys and answers alike, which `twk play` leaves out), and
// its sizes ("r"), each at its time since the start with every pause
// longer than two seconds cut to it. A recording begun while an app has
// the terminal begins with the screen it is on (the alternate one) and has
// the app paint all of itself, so that it plays back from a whole screen.
import { CastWriter } from '../core/cast';
import { Clock, Disposable, Emitter } from '../core/events';
import { CastSink, Screen } from './ports';
import { TwkTerminal } from './terminal';

/** The longest pause a recording keeps, as `twk record`'s default. */
export const idleLimitSeconds = 2;

export interface RecordingDeps {
  readonly clock: Clock;
  /** Seconds since the Unix epoch, for the header's timestamp. */
  readonly epochSeconds: () => number;
  /** The `TERM` the terminal tells its apps, for the header's env. */
  readonly term: string | undefined;
  /** Has the app in the terminal paint all of itself, where one does (a run's, a debug session's). */
  readonly redraw?: () => Promise<void>;
}

/** How a recording ended. */
export interface RecordingEnd {
  readonly events: number;
  /** The recording's length, its pauses cut. */
  readonly seconds: number;
  /** What the sink threw, where writing failed. */
  readonly error?: Error;
}

export class Recording {
  private readonly listening: Disposable[] = [];
  private stopping: Promise<RecordingEnd> | undefined;
  private failure: Error | undefined;
  /** Its constructor ran: a failed write stops it from then on (before, [start] does). */
  private constructed = false;
  private readonly start: number;
  private readonly writer: CastWriter;
  private readonly stops = new Emitter<RecordingEnd>();
  /** It ended: stopped, its terminal closed, or its file failed. */
  readonly onDidStop = this.stops.event;

  private constructor(
    readonly screen: Screen,
    private readonly sink: CastSink,
    private readonly deps: RecordingDeps,
    /** What begins it: the screen it is on. */
    preamble: string,
  ) {
    const { view } = screen;
    this.start = deps.clock.now();
    this.writer = new CastWriter(
      (text) => this.write(text),
      {
        width: view.columns,
        height: view.lines,
        timestamp: Math.trunc(deps.epochSeconds()),
        idleTimeLimit: idleLimitSeconds,
        title: screen.name,
        ...(deps.term ? { env: { TERM: deps.term } } : {}),
      },
      idleLimitSeconds * 1e6,
    );
    // with the first output, so that its first frame is a whole screen
    this.preamble = new TextEncoder().encode(preamble);
    this.listening.push(
      screen.onDidOutput((o) => this.output(o.bytes)),
      screen.onDidInput((bytes) => this.writer.writeInput(this.at(), bytes)),
      screen.onDidResize(() => this.writer.resize(this.at(), view.columns, view.lines)),
      screen.onDidDispose(() => void this.stop()),
    );
    this.constructed = true;
  }

  /**
   * Records [screen] into [sink] from now: its header at once, the screen
   * the terminal is on, and, with an app in it, what the app paints of all
   * of itself ([RecordingDeps.redraw]).
   */
  static async start(screen: Screen, sink: CastSink, deps: RecordingDeps): Promise<Recording> {
    const shown = await screen.view.snapshot();
    const recording = new Recording(screen, sink, deps, shown.buffer === 'alternate' ? '\x1b[?1049h\x1b[H\x1b[2J' : '');
    if (recording.failure) {
      // its header could not be written
      const { error } = await recording.stop();
      throw error;
    }
    await deps.redraw?.();
    return recording;
  }

  /** Whether it was stopped. */
  get stopped(): boolean {
    return this.stopping !== undefined;
  }

  /** What begins it, until it is written with the first output (or at its end). */
  private preamble: Uint8Array;

  private output(bytes: Uint8Array): void {
    if (this.preamble.length > 0) {
      const first = new Uint8Array(this.preamble.length + bytes.length);
      first.set(this.preamble);
      first.set(bytes, this.preamble.length);
      this.preamble = new Uint8Array(0);
      this.writer.writeOutput(this.at(), first);
    } else {
      this.writer.writeOutput(this.at(), bytes);
    }
  }

  /** Microseconds since it began. */
  private at(): number {
    return Math.round((this.deps.clock.now() - this.start) * 1000);
  }

  private write(text: string): void {
    if (this.failure) {
      return;
    }
    try {
      this.sink.write(text);
    } catch (e) {
      this.failure = e instanceof Error ? e : new Error(String(e));
      if (this.constructed) {
        void this.stop();
      }
    }
  }

  /** Ends it, what is left of a character written, the file closed; once, however often it is called. */
  stop(): Promise<RecordingEnd> {
    this.stopping ??= this.stopOnce();
    return this.stopping;
  }

  private async stopOnce(): Promise<RecordingEnd> {
    this.listening.forEach((d) => d.dispose());
    if (!this.failure) {
      if (this.preamble.length > 0) {
        this.output(new Uint8Array(0));
      }
      this.writer.close(this.at());
    }
    try {
      await this.sink.close();
    } catch (e) {
      this.failure ??= e instanceof Error ? e : new Error(String(e));
    }
    const end: RecordingEnd = { events: this.writer.count, seconds: this.writer.time, ...(this.failure ? { error: this.failure } : {}) };
    this.stops.fire(end);
    this.stops.dispose();
    return end;
  }
}

export interface RecordingsDeps {
  readonly clock: Clock;
  readonly epochSeconds: () => number;
  /** The `TERM` the terminals tell their apps now. */
  readonly term: () => string | undefined;
  /** What has the app in [terminal] paint all of itself, where an app the extension runs or debugs has it. */
  readonly redrawOf: (terminal: TwkTerminal) => (() => Promise<void>) | undefined;
}

/** The recordings being made: one at most per terminal, its title saying so. */
export class Recordings {
  private readonly made = new Map<TwkTerminal, Recording>();
  /** The terminals whose recording is starting. */
  private readonly starting = new Set<TwkTerminal>();
  private readonly changes = new Emitter<void>();
  /** A recording began or ended. */
  readonly onDidChange = this.changes.event;
  private readonly ends = new Emitter<{ readonly terminal: TwkTerminal; readonly end: RecordingEnd }>();
  /** A recording ended, how. */
  readonly onDidEnd = this.ends.event;

  constructor(private readonly deps: RecordingsDeps) {}

  /** The recording of [terminal], while it is made. */
  of(terminal: TwkTerminal): Recording | undefined {
    return this.made.get(terminal);
  }

  /** The recordings being made, the oldest first. */
  all(): Recording[] {
    return [...this.made.values()];
  }

  /** Records [terminal] into [sink] from now; throws when it is recorded already, or the sink fails at once. */
  async start(terminal: TwkTerminal, sink: CastSink): Promise<Recording> {
    if (this.made.has(terminal) || this.starting.has(terminal)) {
      throw new Error(`${terminal.name} is recorded already`);
    }
    const { clock, epochSeconds, term, redrawOf } = this.deps;
    const redraw = redrawOf(terminal);
    this.starting.add(terminal);
    let recording: Recording;
    try {
      recording = await Recording.start(terminal, sink, { clock, epochSeconds, term: term(), ...(redraw ? { redraw } : {}) });
    } finally {
      this.starting.delete(terminal);
    }
    if (recording.stopped) {
      // its terminal closed meanwhile
      return recording;
    }
    this.made.set(terminal, recording);
    terminal.setRecorded(true);
    recording.onDidStop((end) => {
      this.made.delete(terminal);
      if (!terminal.isClosed) {
        terminal.setRecorded(false);
      }
      this.changes.fire();
      this.ends.fire({ terminal, end });
    });
    this.changes.fire();
    return recording;
  }

  /** Stops each recording. */
  async dispose(): Promise<void> {
    await Promise.all(this.all().map((r) => r.stop()));
    this.changes.dispose();
    this.ends.dispose();
  }
}
