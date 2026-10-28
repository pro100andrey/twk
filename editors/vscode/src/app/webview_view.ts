// The [TerminalView] of a webview with xterm.js (webview/main.ts), spoken
// to in the messages of webview/protocol.ts: what the panel does, over a
// [WebviewPanelPort] that vscode/panel.ts makes of VS Code's webview panel
// and the tests of a fake.
import { Answers } from '../core/capabilities';
import { TerminalRequest } from '../core/emulation';
import { Disposable, Emitter, Event } from '../core/events';
import { PlayerControl, PlayerState, ToWebview, isFromWebview } from '../webview/protocol';
import { PickedCell, Snapshot, TerminalView } from './ports';

/** A webview in a panel, spoken to in the messages [To], as a view needs it (a terminal's, a log's). */
export interface WebviewPanelPort<To = ToWebview> {
  /** Sends [message]; settles false, sent to nobody, when the webview took it not. */
  post(message: To): Promise<boolean>;
  /** Whether the panel is the editor's active one. */
  readonly active: boolean;
  setTitle(title: string): void;
  reveal(): void;
  /** Closes the panel. */
  dispose(): void;
  /** What the webview sent: anything, checked before it is taken for a message. */
  readonly onMessage: Event<unknown>;
  /** The panel was closed, by the person or by [dispose]. */
  readonly onDispose: Event<void>;
}

const nothingShown: Snapshot = { buffer: 'normal', rows: [] };

export class WebviewTerminalView implements TerminalView {
  columns = 80;
  lines = 24;
  readonly ready: Promise<void>;
  private isReady = false;
  private nextId = 0;
  private readonly writes = new Map<number, () => void>();
  private readonly snapshots = new Map<number, (s: Snapshot) => void>();
  /** The panel was closed: its webview takes no more messages, title or reveal. */
  private closed = false;
  private readonly inputs = new Emitter<Uint8Array>();
  private readonly requests = new Emitter<TerminalRequest>();
  private readonly resizes = new Emitter<void>();
  private readonly closes = new Emitter<void>();
  private readonly reloads = new Emitter<void>();
  private readonly picks = new Emitter<PickedCell | null>();
  private readonly controls = new Emitter<PlayerControl>();
  readonly onPick = this.picks.event;
  readonly onControl = this.controls.event;
  readonly onInput = this.inputs.event;
  readonly onRequest = this.requests.event;
  readonly onResize = this.resizes.event;
  readonly onClose = this.closes.event;
  readonly onReload = this.reloads.event;
  private readonly listening: Disposable[];

  constructor(readonly panel: WebviewPanelPort) {
    let ready!: () => void;
    let gone!: (e: Error) => void;
    this.ready = new Promise((resolve, reject) => {
      ready = resolve;
      gone = reject;
    });
    this.ready.catch(() => {});
    this.listening = [
      panel.onMessage((m) => this.onMessage(m, ready)),
      panel.onDispose(() => {
        this.closed = true;
        gone(new Error('the twk terminal was closed before it was ready'));
        this.settle();
        this.closes.fire();
        this.listening.forEach((d) => d.dispose());
        [this.inputs, this.requests, this.resizes, this.closes, this.reloads, this.picks, this.controls].forEach((e) => e.dispose());
      }),
    ];
  }

  get isClosed(): boolean {
    return this.closed;
  }

  get isActive(): boolean {
    return !this.closed && this.panel.active;
  }

  reveal(): void {
    if (!this.closed) {
      this.panel.reveal();
    }
  }

  setTitle(title: string): void {
    if (!this.closed) {
      this.panel.setTitle(title);
    }
  }

  close(): void {
    if (!this.closed) {
      this.panel.dispose();
    }
  }

  /** Sends [message] to the webview: false, sent to nobody, once the panel was closed. */
  private post(message: ToWebview): Promise<boolean> {
    if (this.closed) {
      return Promise.resolve(false);
    }
    try {
      return this.panel.post(message).catch(() => false);
    } catch {
      return Promise.resolve(false);
    }
  }

  fixSize(columns: number | null, lines: number | null): void {
    void this.post({ type: 'size', columns, lines });
  }

  answer(answers: Answers): void {
    void this.post({ type: 'answers', answers });
  }

  pick(on: boolean): void {
    void this.post({ type: 'pick', on });
  }

  player(state: PlayerState | null): void {
    void this.post({ type: 'player', state });
  }

  write(bytes: Uint8Array): Promise<void> {
    const id = this.nextId++;
    return new Promise((resolve) => {
      this.writes.set(id, resolve);
      void this.post({ type: 'output', id, data: new Uint8Array(bytes) }).then((sent) => sent || this.written(id));
    });
  }

  snapshot(): Promise<Snapshot> {
    const id = this.nextId++;
    return new Promise((resolve) => {
      this.snapshots.set(id, resolve);
      void this.post({ type: 'snapshot', id }).then((sent) => {
        if (!sent) {
          this.snapshots.delete(id);
          resolve(nothingShown);
        }
      });
    });
  }

  private written(id: number): void {
    this.writes.get(id)?.();
    this.writes.delete(id);
  }

  /** Settles what was asked of the webview: it answers no more. */
  private settle(): void {
    for (const id of [...this.writes.keys()]) {
      this.written(id);
    }
    for (const [id, resolve] of [...this.snapshots]) {
      this.snapshots.delete(id);
      resolve(nothingShown);
    }
  }

  private onMessage(m: unknown, ready: () => void): void {
    if (this.closed || !isFromWebview(m)) {
      return;
    }
    switch (m.type) {
      case 'ready':
        this.columns = m.columns;
        this.lines = m.lines;
        if (!this.isReady) {
          this.isReady = true;
          ready();
        } else {
          // a new webview: what was asked of the old one it never answers
          this.settle();
          this.reloads.fire();
        }
        break;
      case 'resize':
        this.columns = m.columns;
        this.lines = m.lines;
        this.resizes.fire();
        break;
      case 'input':
        this.inputs.fire(Buffer.from(m.data, m.binary ? 'latin1' : 'utf8'));
        break;
      case 'written':
        this.written(m.id);
        break;
      case 'request':
        this.requests.fire(m.request);
        break;
      case 'picked':
        this.picks.fire(m.cell);
        break;
      case 'control':
        this.controls.fire(m.control);
        break;
      case 'snapshot':
        this.snapshots.get(m.id)?.({ buffer: m.buffer, rows: m.rows, ...(m.backgrounds ? { backgrounds: m.backgrounds } : {}) });
        this.snapshots.delete(m.id);
        break;
    }
  }
}
