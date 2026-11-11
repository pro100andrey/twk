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

/** What a log shows of its entries: which directions, the text runs, and a word (lower case) of the name or the bytes. */
export interface LogFilter {
  readonly out: boolean;
  readonly in: boolean;
  readonly note: boolean;
  readonly text: boolean;
  readonly word: string;
}

/** Nothing left out. */
export const wholeLog: LogFilter = { out: true, in: true, note: true, text: true, word: '' };

/** Whether the log shows [e] under [filter]: a frame also when one of its own matches the word. */
export function entryMatches(e: LogEntry, filter: LogFilter): boolean {
  if (!filter[e.direction] || (!filter.text && e.kind === 'text')) {
    return false;
  }
  if (filter.word === '') {
    return true;
  }
  const has = (x: LogEntry): boolean => x.name.toLowerCase().includes(filter.word) || x.raw.toLowerCase().includes(filter.word);
  return has(e) || (e.children ?? []).some(has);
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
  private positionAsked = 0;
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
      const stray = change < 0 && this.depth <= 0;
      this.depth = Math.max(0, this.depth + change);
      if (t.kind === 'csi' && t.final === 'n' && t.intermediates === '' && (t.prefix === '' || t.prefix === '?') && t.params === '6') {
        this.positionAsked++;
      }
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
        if (stray) {
          // a capture that began inside a frame, or a frame lost its start
          this.note(time, 'no synchronized update is open: CSI ? 2026 l ignored');
        }
      }
    }
  }

  /** What the terminal sent at [time]: each read whole. */
  input(time: number, bytes: Uint8Array): void {
    for (const t of new SequenceReader(true).read(bytes)) {
      // a CSI 1 ; n R is the answer to a position query asked and not yet answered (as twk_dev's replay InputSplitter tells), else the F3 key;
      // a key typed gives the queries up
      const entry = this.entry(time, 'in', t.kind, describeInput(t, this.positionAsked > 0), t.raw);
      if (t.kind === 'csi' && t.final === 'R' && (t.prefix === '' || t.prefix === '?')) {
        // CSI r;c R answers CSI 6 n, CSI ? r;c R answers CSI ? 6 n; not sent after an ESC
        if (!t.alt && this.positionAsked > 0 && t.params.includes(';')) {
          this.positionAsked--;
        }
      } else if (t.kind === 'text' || t.kind === 'control' || t.kind === 'esc' || t.kind === 'ss3' || t.kind === 'mouse') {
        this.positionAsked = 0;
      }
      this.add(entry);
    }
  }

  /**
   * The traffic ended at [time]: a synchronized update still open is closed as a frame saying so, and what the app's last write left
   * unfinished (an OSC, a DCS, a CSI without its end) is a note saying it was cut short.
   */
  finish(time: number): void {
    const open = this.open;
    if (open) {
      this.closeFrame(open, time, false);
      this.depth = 0;
    }
    const waiting = this.out.waiting;
    if (waiting !== '') {
      this.add({ id: this.nextId++, time, direction: 'note', kind: 'note', name: `output cut short: ${visible(waiting, 60)}`, raw: '', bytes: waiting.length });
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

  private closeFrame(open: Open, time: number, closed = true): void {
    this.open = undefined;
    const cut = open.entries.length >= this.frameLimit ? ` (the first ${this.frameLimit} entries)` : '';
    const ms = time - open.time;
    this.add({
      id: this.nextId++,
      time: open.time,
      direction: 'out',
      kind: 'frame',
      name: `frame ${open.number}: ${summary(open.entries)}${cut}${ms > 0 ? `, ${ms} ms` : ''}${closed ? '' : ', not closed'}`,
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
