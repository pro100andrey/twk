// The sequence log of a screen (a twk terminal, or a recording played
// back) in a webview of its own (webview/log.ts), spoken to in the
// messages of webview/log_protocol.ts: the screen's traffic made into
// entries by core's SequenceLog as it comes, sent at most every
// [LogPanel.interval] ms; the webview filters and pauses what it shows.
// One panel per screen ([LogPanels]), shown again when asked again; what
// came before it was opened is the screen's [Traffic], kept as bytes from
// the screen's start (its probe, its modes), and decoded only then.
import { Clock, Disposable, Emitter } from '../core/events';
import { LogFilter, SequenceLog, wholeLog } from '../core/seqlog';
import { TrafficPiece, logCast, logText, noteOf } from '../core/seqlog_save';
import { ToLog, isFromLog } from '../webview/log_protocol';
import { Screen } from './ports';
import { WebviewPanelPort } from './webview_view';

/** Opens a new panel for the log of [screen]. */
export type LogPanelFactory = (title: string) => WebviewPanelPort<ToLog>;

type Piece = TrafficPiece;

/** Pieces of traffic kept up to [budget] bytes, the oldest dropped first. */
class Pieces {
  private readonly kept: Piece[] = [];
  private size = 0;

  constructor(private readonly budget: number) {}

  add(p: Piece): void {
    this.kept.push(p);
    this.size += weight(p);
    while (this.size > this.budget && this.kept.length > 1) {
      this.size -= weight(this.kept.shift()!);
    }
  }

  each(f: (p: Piece) => void): void {
    this.kept.forEach(f);
  }

  all(): readonly Piece[] {
    return this.kept;
  }

  clear(): void {
    this.kept.length = 0;
    this.size = 0;
  }
}

const weight = (p: Piece): number => ('output' in p ? p.output.length : 'input' in p ? p.input.length : p.note.length);

/**
 * What a screen wrote and sent since it was made, as it came, up to
 * [budget] bytes (the oldest dropped first): what a log opened later
 * begins with. Kept as bytes: nothing is decoded until a log is opened.
 */
export class Traffic {
  /** The clock's time it began at: the log's times are from it. */
  readonly start: number;
  private readonly pieces: Pieces;
  private readonly listening: Disposable[];

  constructor(
    screen: Screen,
    clock: Clock,
    budget = 4 << 20,
  ) {
    this.pieces = new Pieces(budget);
    this.start = clock.now();
    this.pieces.add({ time: this.start, note: `${screen.name} opened, at ${screen.view.columns}x${screen.view.lines}` });
    this.listening = [
      screen.onDidOutput((o) => this.pieces.add({ time: clock.now(), output: o.bytes, fromApp: o.fromApp })),
      screen.onDidInput((bytes) => this.pieces.add({ time: clock.now(), input: bytes })),
      screen.onDidNote((note) => this.pieces.add({ time: clock.now(), note })),
      screen.onDidDispose(() => this.dispose()),
    ];
  }

  /** Each piece kept, the oldest first. */
  replay(f: (p: Piece) => void): void {
    this.pieces.each(f);
  }

  dispose(): void {
    this.listening.forEach((d) => d.dispose());
  }
}

export class LogPanel {
  /** The longest the webview waits for new entries, in milliseconds. */
  static readonly interval = 100;

  private readonly log: SequenceLog;
  /** The bytes behind the log, as it has them (times from its start): what is saved as a recording. */
  private readonly pieces = new Pieces(4 << 20);
  /** What it listens to of the screen, until the screen goes. */
  private readonly following: Disposable[];
  /** What it listens to of its panel, until it is closed. */
  private readonly listening: Disposable[];
  private readonly disposes = new Emitter<void>();
  /** It was closed. */
  readonly onDidDispose = this.disposes.event;
  private disposed = false;
  private timer: Disposable | undefined;
  /** The webview said it is up: it is sent entries. */
  private ready = false;
  private ended = false;
  private readonly start: number;
  /** What the webview said it shows, last. */
  shown: { readonly rows: number; readonly held: number; readonly last: readonly string[]; readonly filter?: LogFilter } | undefined;
  private readonly saves = new Emitter<void>();
  /** The webview's Save button was pressed. */
  readonly onDidAskSave = this.saves.event;

  constructor(
    readonly screen: Screen,
    readonly panel: WebviewPanelPort<ToLog>,
    private readonly clock: Clock,
    /** What the screen did before: the log begins with it. */
    history?: Traffic,
  ) {
    this.log = new SequenceLog();
    this.start = history?.start ?? clock.now();
    const at = (time: number) => Math.round(time - this.start);
    const apply = (p: Piece) => this.apply(p);
    if (history) {
      history.replay((p) => apply({ ...p, time: at(p.time) }));
    } else {
      apply({ time: 0, note: `the log of ${screen.name} begins, at ${screen.view.columns}x${screen.view.lines}` });
    }
    this.following = [
      screen.onDidOutput((o) => {
        apply({ time: at(clock.now()), output: o.bytes, fromApp: o.fromApp });
        this.later();
      }),
      screen.onDidInput((bytes) => {
        apply({ time: at(clock.now()), input: bytes });
        this.later();
      }),
      screen.onDidNote((text) => {
        apply({ time: at(clock.now()), note: text });
        this.later();
      }),
      screen.onDidDispose(() => this.end()),
    ];
    this.listening = [
      panel.onMessage((m) => {
        if (!isFromLog(m)) {
          return;
        }
        if (m.type === 'shown') {
          this.shown = m;
        } else if (m.type === 'save') {
          this.saves.fire();
        } else if (m.type === 'ready') {
          // its first, or a webview loaded again: all of it
          this.ready = true;
          this.log.take();
          void this.panel.post({ type: 'reset', title: this.title(), entries: this.log.all() });
          if (this.ended) {
            void this.panel.post({ type: 'ended' });
          }
        } else {
          this.log.clear();
          this.pieces.clear();
          void this.panel.post({ type: 'reset', title: this.title(), entries: [] });
        }
      }),
      panel.onDispose(() => this.dispose()),
    ];
  }

  private title(): string {
    return `${this.screen.name} · twk sequence log`;
  }

  reveal(): void {
    this.panel.reveal();
  }

  /** What it shows, as the webview was sent it: for the tests. */
  entries() {
    return this.log.all();
  }

  /** The filter the webview applies, as it last said; the whole log before it did. */
  get filter(): LogFilter {
    return this.shown?.filter ?? wholeLog;
  }

  /** The rows [filter] lets through, as text: one line each, as `twk decode` prints them. */
  text(filter: LogFilter = this.filter): string {
    return logText(this.log.all(), filter);
  }

  /**
   * The log's bytes with their times as asciicast v2 (`twk decode` and `twk play` read it): the app's output, what the
   * terminal sent, the notes as markers; [filter] leaves out a direction. [epochSeconds] is now, [term] the terminal's `TERM`.
   */
  cast(epochSeconds: number, term?: string, filter: LogFilter = this.filter): string {
    const elapsed = (this.clock.now() - this.start) / 1000;
    return logCast(this.pieces.all(), filter, {
      width: this.screen.view.columns,
      height: this.screen.view.lines,
      title: this.screen.name,
      timestamp: Math.trunc(epochSeconds - elapsed),
      ...(term ? { term } : {}),
    });
  }

  /** Sends what came, at most every interval. */
  private later(): void {
    if (this.timer || !this.ready) {
      return;
    }
    this.timer = this.clock.setTimeout(() => {
      this.timer = undefined;
      this.flush();
    }, LogPanel.interval);
  }

  /** Sends the entries made since the last, at once. */
  flush(): void {
    const entries = this.log.take();
    if (this.ready && entries.length > 0) {
      void this.panel.post({ type: 'entries', entries });
    }
  }

  /** Keeps [p] and makes of it what the log has. */
  private apply(p: Piece): void {
    this.pieces.add(p);
    if ('output' in p) {
      if (p.fromApp) {
        this.log.output(p.time, p.output);
      } else {
        this.log.note(p.time, noteOf(p.output));
      }
    } else if ('input' in p) {
      this.log.input(p.time, p.input);
    } else {
      this.log.note(p.time, p.note);
    }
  }

  private end(): void {
    if (this.ended) {
      return;
    }
    this.ended = true;
    this.apply({ time: Math.round(this.clock.now() - this.start), note: `${this.screen.name} was closed` });
    this.flush();
    void this.panel.post({ type: 'ended' });
    this.following.forEach((d) => d.dispose());
  }

  /** Closes the panel; once. */
  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.timer?.dispose();
    this.timer = undefined;
    this.following.forEach((d) => d.dispose());
    this.listening.forEach((d) => d.dispose());
    this.panel.dispose();
    this.disposes.fire();
    this.disposes.dispose();
    this.saves.dispose();
  }
}

/** The log panels open, one per screen, and the traffic of the screens followed. */
export class LogPanels {
  private readonly open = new Map<Screen, LogPanel>();
  private readonly traffic = new Map<Screen, Traffic>();
  private readonly saves = new Emitter<LogPanel>();
  /** The Save button of a panel's webview was pressed. */
  readonly onDidAskSave = this.saves.event;

  constructor(
    private readonly panels: LogPanelFactory,
    private readonly clock: Clock,
  ) {}

  /** Keeps what [screen] does from now on (as it is made), for its log opened later; forgotten once it goes. */
  follow(screen: Screen): void {
    if (this.traffic.has(screen)) {
      return;
    }
    this.traffic.set(screen, new Traffic(screen, this.clock));
    screen.onDidDispose(() => this.traffic.delete(screen));
  }

  /** The log of [screen]: its panel shown, opened when it has none. */
  show(screen: Screen): LogPanel {
    const shown = this.open.get(screen);
    if (shown) {
      shown.reveal();
      return shown;
    }
    const panel = new LogPanel(screen, this.panels(`${screen.name} · twk sequence log`), this.clock, this.traffic.get(screen));
    this.open.set(screen, panel);
    panel.onDidAskSave(() => this.saves.fire(panel));
    panel.onDidDispose(() => this.open.delete(screen));
    return panel;
  }

  /** The panel of [screen]'s log, where one is open. */
  of(screen: Screen): LogPanel | undefined {
    return this.open.get(screen);
  }

  dispose(): void {
    [...this.open.values()].forEach((p) => p.dispose());
    [...this.traffic.values()].forEach((t) => t.dispose());
    this.traffic.clear();
    this.saves.dispose();
  }
}
