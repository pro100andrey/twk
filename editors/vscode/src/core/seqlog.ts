// The sequence log of a terminal: what the app wrote and what the terminal
// sent, cut and named by sequences.ts, with when; the app's coming and
// going and the terminal's sizes as notes. What a synchronized update (DEC
// mode 2026) holds is one entry, a frame, with its sequences below it.
// Pure: no node, no DOM; its entries are what the log's webview shows.
import { SequenceReader, Token, describeInput, describeOutput, syncChange, visible } from './sequences.js';

/** Which way an entry went: written by the app, sent by the terminal, or said of the session. */
export type Direction = 'out' | 'in' | 'note';

/** What an entry is: a token's kind, a frame of a synchronized update, or a note. */
export type EntryKind = Token['kind'] | 'frame' | 'note';

export interface LogEntry {
  /** From 0, in the order they came; a frame's own entries are numbered too. */
  readonly id: number;
  /** Milliseconds since the log began. */
  readonly time: number;
  readonly direction: Direction;
  readonly kind: EntryKind;
  /** What it is: `CUP cursor to row 3, column 5`, `key Up`, `frame 12: ...`. */
  readonly name: string;
  /** Its bytes as the log shows them (`ESC [3;5H`), cut where long. */
  readonly raw: string;
  /** How many bytes it is. */
  readonly bytes: number;
  /** A frame's entries, in order. */
  readonly children?: readonly LogEntry[];
}

/** An open synchronized update: its entries, held until it ends. */
interface Open {
  readonly time: number;
  readonly number: number;
  readonly entries: LogEntry[];
  bytes: number;
}

/** A frame's summary: how many of each name's first word, the most first. */
function summary(entries: readonly LogEntry[]): string {
  const counts = new Map<string, number>();
  for (const e of entries) {
    const word = e.kind === 'text' ? 'text' : e.name.split(' ')[0];
    counts.set(word, (counts.get(word) ?? 0) + 1);
  }
  return [...counts]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 6)
    .map(([w, n]) => `${n} ${w}`)
    .join(', ');
}

export interface SequenceLogOptions {
  /** The most entries kept (the oldest dropped first). */
  readonly limit?: number;
  /** The most entries a frame keeps below it: one that holds more is cut, said so. */
  readonly frameLimit?: number;
}

/** Entries made of a terminal's traffic as it comes; [take] gives those made since it was called last. */
export class SequenceLog {
  private readonly out = new SequenceReader(false);
  private readonly kept: LogEntry[] = [];
  private fresh: LogEntry[] = [];
  private nextId = 0;
  private frames = 0;
  private open: Open | undefined;
  private depth = 0;
  private readonly limit: number;
  private readonly frameLimit: number;

  constructor(options: SequenceLogOptions = {}) {
    this.limit = options.limit ?? 20000;
    this.frameLimit = options.frameLimit ?? 2000;
  }

  /** What the app wrote at [time]. */
  output(time: number, bytes: Uint8Array): void {
    for (const t of this.out.read(bytes)) {
      const change = syncChange(t);
      const entry = this.entry(time, 'out', t.kind, describeOutput(t), t.raw);
      if (change > 0 && this.depth <= 0 && this.open === undefined) {
        this.open = { time, number: ++this.frames, entries: [], bytes: 0 };
      }
      this.depth += change;
      const open = this.open;
      if (open) {
        if (open.entries.length < this.frameLimit) {
          open.entries.push(entry);
        }
        open.bytes += entry.bytes;
        if (this.depth <= 0) {
          this.closeFrame(open, time);
        }
      } else {
        this.add(entry);
      }
    }
  }

  /** What the terminal sent at [time]: each read whole. */
  input(time: number, bytes: Uint8Array): void {
    for (const t of new SequenceReader(true).read(bytes)) {
      this.add(this.entry(time, 'in', t.kind, describeInput(t), t.raw));
    }
  }

  /** Something of the session at [time]: an app came or went, a size. */
  note(time: number, text: string): void {
    this.add({ id: this.nextId++, time, direction: 'note', kind: 'note', name: text, raw: '', bytes: 0 });
  }

  /** The entries made since the last [take], in order (an open frame's once it ends). */
  take(): LogEntry[] {
    const f = this.fresh;
    this.fresh = [];
    return f;
  }

  /** Every entry kept, in order. */
  all(): LogEntry[] {
    return [...this.kept];
  }

  /** Forgets every entry; a frame open goes on, and is told once it ends. */
  clear(): void {
    this.kept.length = 0;
    this.fresh = [];
  }

  private entry(time: number, direction: Direction, kind: EntryKind, name: string, raw: string): LogEntry {
    return { id: this.nextId++, time, direction, kind, name, raw: visible(raw), bytes: raw.length };
  }

  private closeFrame(open: Open, time: number): void {
    this.open = undefined;
    const cut = open.entries.length >= this.frameLimit ? ` (the first ${this.frameLimit} entries)` : '';
    const ms = time - open.time;
    this.add({
      id: this.nextId++,
      time: open.time,
      direction: 'out',
      kind: 'frame',
      name: `frame ${open.number}: ${summary(open.entries)}${cut}${ms > 0 ? `, ${ms} ms` : ''}`,
      raw: `${open.bytes} bytes`,
      bytes: open.bytes,
      children: open.entries,
    });
  }

  private add(e: LogEntry): void {
    this.kept.push(e);
    this.fresh.push(e);
    if (this.kept.length > this.limit) {
      this.kept.splice(0, this.kept.length - this.limit);
    }
    if (this.fresh.length > this.limit) {
      this.fresh.splice(0, this.fresh.length - this.limit);
    }
  }
}
