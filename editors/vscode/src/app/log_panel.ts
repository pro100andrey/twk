// The sequence log of a screen (a twk terminal, or a recording played
// back) in a webview of its own (webview/log.ts), spoken to in the
// messages of webview/log_protocol.ts: the screen's traffic made into
// entries by core's SequenceLog as it comes, sent at most every
// [LogPanel.interval] ms; the webview filters and pauses what it shows.
// One panel per screen ([LogPanels]), shown again when asked again; what
// came before it was opened is the screen's [Traffic], kept as bytes from
// the screen's start (its probe, its modes), and decoded only then.
import { Clock, Disposable, Emitter } from '../core/events';
import { SequenceLog } from '../core/seqlog';
import { ToLog, isFromLog } from '../webview/log_protocol';
import { Screen } from './ports';
import { WebviewPanelPort } from './webview_view';

/** Opens a new panel for the log of [screen]. */
export type LogPanelFactory = (title: string) => WebviewPanelPort<ToLog>;

/** A piece of a screen's traffic, at [time] ms of its clock. */
type Piece =
  | { readonly time: number; readonly output: Uint8Array; readonly fromApp: boolean }
  | { readonly time: number; readonly input: Uint8Array }
  | { readonly time: number; readonly note: string };

/**
 * What a screen wrote and sent since it was made, as it came, up to
 * [budget] bytes (the oldest dropped first): what a log opened later
 * begins with. Kept as bytes: nothing is decoded until a log is opened.
 */
export class Traffic {
  /** The clock's time it began at: the log's times are from it. */
  readonly start: number;
  private readonly pieces: Piece[] = [];
  private size = 0;
  private readonly listening: Disposable[];

  constructor(
    screen: Screen,
    clock: Clock,
    private readonly budget = 4 << 20,
  ) {
    this.start = clock.now();
    this.add({ time: this.start, note: `${screen.name} opened, at ${screen.view.columns}x${screen.view.lines}` }, 0);
    this.listening = [
      screen.onDidOutput((o) => this.add({ time: clock.now(), output: o.bytes, fromApp: o.fromApp }, o.bytes.length)),
      screen.onDidInput((bytes) => this.add({ time: clock.now(), input: bytes }, bytes.length)),
      screen.onDidNote((note) => this.add({ time: clock.now(), note }, note.length)),
      screen.onDidDispose(() => this.dispose()),
    ];
  }

  private add(p: Piece, bytes: number): void {
    this.pieces.push(p);
    this.size += bytes;
    while (this.size > this.budget && this.pieces.length > 1) {
      const gone = this.pieces.shift()!;
      this.size -= 'output' in gone ? gone.output.length : 'input' in gone ? gone.input.length : gone.note.length;
    }
  }

  /** Each piece kept, the oldest first. */
  replay(f: (p: Piece) => void): void {
    this.pieces.forEach(f);
  }

  dispose(): void {
    this.listening.forEach((d) => d.dispose());
  }
}

export class LogPanel {
  /** The longest the webview waits for new entries, in milliseconds. */
  static readonly interval = 100;

  private readonly log: SequenceLog;
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
  shown: { readonly rows: number; readonly held: number; readonly last: readonly string[] } | undefined;

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
    const output = (time: number, bytes: Uint8Array, fromApp: boolean) => {
      if (fromApp) {
        this.log.output(at(time), bytes);
      } else {
        this.log.note(at(time), new TextDecoder().decode(bytes).replace(/\x1b\[[0-9;]*m/g, '').trim());
      }
    };
    if (history) {
      history.replay((p) => {
        if ('output' in p) {
          output(p.time, p.output, p.fromApp);
        } else if ('input' in p) {
          this.log.input(at(p.time), p.input);
        } else {
          this.log.note(at(p.time), p.note);
        }
      });
    } else {
      this.log.note(0, `the log of ${screen.name} begins, at ${screen.view.columns}x${screen.view.lines}`);
    }
    this.following = [
      screen.onDidOutput((o) => {
        output(clock.now(), o.bytes, o.fromApp);
        this.later();
      }),
      screen.onDidInput((bytes) => {
        this.log.input(at(clock.now()), bytes);
        this.later();
      }),
      screen.onDidNote((text) => {
        this.log.note(at(clock.now()), text);
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

  private end(): void {
    if (this.ended) {
      return;
    }
    this.ended = true;
    this.log.note(Math.round(this.clock.now() - this.start), `${this.screen.name} was closed`);
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
  }
}

/** The log panels open, one per screen, and the traffic of the screens followed. */
export class LogPanels {
  private readonly open = new Map<Screen, LogPanel>();
  private readonly traffic = new Map<Screen, Traffic>();

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
  }
}
