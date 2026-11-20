// The cast's events of a driver trace played on a terminal (webview/trace.ts):
// xterm.js queues a write and runs a resize or a reset at once, so each
// segment of text is awaited (its callback) before the resize that follows it,
// and a drawing waits for the one before it, whose queued writes would
// otherwise land after the reset of the next.
import type { WireEvent } from '../core/trace.js';

/** What a replay needs of xterm.js's terminal. */
export interface ReplayTerminal {
  reset(): void;
  resize(columns: number, rows: number): void;
  write(data: string, callback?: () => void): void;
}

/** Draws on [term] one screen at a time. */
export class Replayer {
  private last: Promise<void> = Promise.resolve();
  private generation = 0;

  constructor(private readonly term: ReplayTerminal) {}

  /**
   * The terminal reset to [columns] x [lines] and the [events] up to and
   * including [upTo] written to it; settles once all is parsed, at once for
   * a drawing another one has replaced.
   */
  draw(events: readonly WireEvent[], upTo: number, columns: number, lines: number): Promise<void> {
    const mine = ++this.generation;
    const run = this.last.then(async () => {
      if (mine !== this.generation) {
        return;
      }
      const { term } = this;
      term.reset();
      term.resize(columns, lines);
      let text = '';
      for (const [index, code, data] of events) {
        if (index > upTo) {
          break;
        }
        if (code === 'r') {
          await this.write(text);
          text = '';
          if (mine !== this.generation) {
            return;
          }
          const m = /^(\d+)x(\d+)$/.exec(data);
          if (m) {
            term.resize(Number(m[1]), Number(m[2]));
          }
        } else {
          text += data;
        }
      }
      await this.write(text);
    });
    this.last = run.catch(() => {});
    return run;
  }

  private write(text: string): Promise<void> {
    return new Promise((resolve) => this.term.write(text, resolve));
  }
}
