// A [TerminalView] over a headless xterm.js with the webview's emulation on
// it (webview/answers.ts), as the webview is one over the page's: what is
// written parsed by xterm.js, what it and the emulation answer sent as
// input, its screen read as the webview reads it. For the unit tests that
// run a real twk app, or play a recording into a terminal.
import { Terminal } from '@xterm/headless';

import { Answers } from '../../core/capabilities';
import { TerminalRequest } from '../../core/emulation';
import { Emitter } from '../../core/events';
import { PickedCell, Snapshot, TerminalView } from '../../app/ports';
import { Emulation } from '../../webview/answers';
import { cursorRowShown } from '../../webview/pick';
import { PlayerControl, PlayerState } from '../../webview/protocol';

export class HeadlessView implements TerminalView {
  readonly term: Terminal;
  readonly emulation: Emulation;
  readonly ready = Promise.resolve();
  title = '';
  isActive = false;
  /** The player's bar as it was told, last. */
  playerState: PlayerState | null = null;
  private closed = false;
  private readonly inputs = new Emitter<Uint8Array>();
  private readonly requests = new Emitter<TerminalRequest>();
  private readonly resizes = new Emitter<void>();
  private readonly closes = new Emitter<void>();
  private readonly reloads = new Emitter<void>();
  private readonly picks = new Emitter<PickedCell | null>();
  private readonly controls = new Emitter<PlayerControl>();
  readonly onInput = this.inputs.event;
  readonly onRequest = this.requests.event;
  readonly onResize = this.resizes.event;
  readonly onClose = this.closes.event;
  readonly onReload = this.reloads.event;
  readonly onPick = this.picks.event;
  readonly onControl = this.controls.event;

  constructor(columns = 60, lines = 12) {
    this.term = new Terminal({ cols: columns, rows: lines, allowProposedApi: true });
    this.emulation = new Emulation(this.term, {
      reply: (text) => this.inputs.fire(Buffer.from(text, 'utf8')),
      request: (r) => this.requests.fire(r),
      pointer: () => {},
      cellSize: () => ({ width: 9, height: 18 }),
    });
    // xterm.js's own answers (DECRQM, DA1, CPR) come as its input
    this.term.onData((d) => this.inputs.fire(Buffer.from(d, 'utf8')));
  }

  get columns(): number {
    return this.term.cols;
  }

  get lines(): number {
    return this.term.rows;
  }

  get isClosed(): boolean {
    return this.closed;
  }

  write(bytes: Uint8Array): Promise<void> {
    if (this.closed) {
      return Promise.resolve();
    }
    return new Promise((resolve) => this.term.write(bytes, resolve));
  }

  /** What it shows, row by row, as the webview's snapshot reads it. */
  rows(): string[] {
    const b = this.term.buffer.active;
    return Array.from({ length: this.term.rows }, (_, y) => b.getLine(b.viewportY + y)?.translateToString(true) ?? '');
  }

  async snapshot(): Promise<Snapshot> {
    return this.closed ? { buffer: 'normal', rows: [] } : { buffer: this.term.buffer.active.type, rows: this.rows() };
  }

  fixSize(columns: number | null, lines: number | null): void {
    if (columns && lines && (columns !== this.term.cols || lines !== this.term.rows)) {
      this.term.resize(columns, lines);
      this.resizes.fire();
    }
  }

  answer(answers: Answers): void {
    this.emulation.configure(answers);
  }

  setTitle(title: string): void {
    this.title = title;
  }

  reveal(): void {}

  /** Whether a click picks, as it was told last. */
  picking = false;

  pick(on: boolean): void {
    this.picking = on;
  }

  /** A click on the cell [x], [y] of the screen shown picks it, while picking, with the cursor's row, as the webview tells it. */
  click(x: number, y: number): void {
    if (this.picking) {
      const b = this.term.buffer.active;
      this.picks.fire({ x, y, cursorY: cursorRowShown(b.cursorY, b.baseY, b.viewportY) });
    }
  }

  player(state: PlayerState | null): void {
    this.playerState = state;
  }

  /** A button of its player's bar is pressed. */
  control(c: PlayerControl): void {
    this.controls.fire(c);
  }

  /** Comes back empty, as a webview that loaded again. */
  reload(): void {
    this.term.reset();
    this.reloads.fire();
  }

  /** Typed in it. */
  type(text: string): void {
    this.inputs.fire(Buffer.from(text, 'utf8'));
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    this.closes.fire();
    this.emulation.dispose();
    this.term.dispose();
  }
}
