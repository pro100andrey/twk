// The sequence log saved to a file, for a bug report: the rows as the log
// shows them (text, laid out as `twk decode` prints them), or the bytes with
// their times as asciicast v2 (core/cast.ts's CastWriter), which `twk decode`
// and `twk play` read, with the app's output as `o` events, what the terminal
// sent as `i` events and the notes as `m` events (markers, which `twk decode`
// reads as notes). Pure: no node, no DOM.
import { CastWriter } from './cast.js';
import { LogEntry, LogFilter, entryMatches } from './seqlog.js';

/** A piece of a screen's traffic, at [time] ms of the log's clock. */
export type TrafficPiece =
  | { readonly time: number; readonly output: Uint8Array; readonly fromApp: boolean }
  | { readonly time: number; readonly input: Uint8Array }
  | { readonly time: number; readonly note: string };

/** The longest pause a saved recording tells a player to keep, as a recording's. */
const idleSeconds = 2;

/** A line the extension wrote to a terminal, as the log's note: without colours. */
export const noteOf = (bytes: Uint8Array): string => new TextDecoder().decode(bytes).replace(/\x1b\[[0-9;]*m/g, '').trim();

const rowName = (s: string): string => s.replace(/[\x00-\x1f\x7f-\x9f]/g, ' ');

function row(e: LogEntry, indent: string): string {
  const dir = e.direction === 'note' ? '-- ' : e.direction === 'in' ? 'in ' : 'out';
  const time = (e.time / 1000).toFixed(3).padStart(9);
  const name = indent + rowName(e.name);
  return `${time}  ${dir} ${name.padEnd(56)} ${rowName(e.raw)}`.trimEnd();
}

/**
 * The rows of [entries] that [filter] lets through, a line each as `twk decode` prints them (time in seconds, `out`
 * for the app's, `in` for the terminal's, `--` for a note, the name, the bytes), a frame's own rows indented below it
 * (all, or those that match the word where the frame's row does not); controls in a name or the bytes are blanked.
 */
export function logText(entries: readonly LogEntry[], filter: LogFilter): string {
  const lines: string[] = [];
  for (const e of entries) {
    if (!entryMatches(e, filter)) {
      continue;
    }
    lines.push(row(e, ''));
    if (e.kind === 'frame') {
      const own = e.name.toLowerCase().includes(filter.word) || e.raw.toLowerCase().includes(filter.word);
      for (const c of e.children ?? []) {
        if (filter.text || c.kind !== 'text') {
          if (own || filter.word === '' || entryMatches(c, filter)) {
            lines.push(row(c, '  '));
          }
        }
      }
    }
  }
  return lines.length === 0 ? '' : `${lines.join('\n')}\n`;
}

export interface CastMeta {
  readonly width: number;
  readonly height: number;
  readonly title: string;
  /** Seconds since the Unix epoch when the log began. */
  readonly timestamp: number;
  /** The `TERM` of the terminal, where known. */
  readonly term?: string;
}

/**
 * [pieces] as an asciicast: what the app wrote as `o` events, what the terminal sent as `i` events and each note as an
 * `m` event, at the times the log has them, kept in order. [filter] leaves out a direction; its word and its text runs
 * name decoded entries, not bytes, and are not applied (cutting a byte stream by them would break its sequences).
 */
export function logCast(pieces: readonly TrafficPiece[], filter: LogFilter, meta: CastMeta): string {
  let text = '';
  const writer = new CastWriter(
    (t) => {
      text += t;
    },
    {
      width: meta.width,
      height: meta.height,
      timestamp: meta.timestamp,
      idleTimeLimit: idleSeconds,
      title: meta.title,
      ...(meta.term ? { env: { TERM: meta.term } } : {}),
    },
  );
  let last = 0;
  for (const p of pieces) {
    // microseconds; never back in time
    const at = Math.max(last, Math.round(p.time * 1000));
    last = at;
    if ('output' in p) {
      if (p.fromApp) {
        if (filter.out) {
          writer.writeOutput(at, p.output);
        }
      } else if (filter.note) {
        // a line of the extension's own written to the terminal: a note in the log, as there
        writer.marker(at, rowName(noteOf(p.output)));
      }
    } else if ('input' in p) {
      if (filter.in) {
        writer.writeInput(at, p.input);
      }
    } else if (filter.note) {
      writer.marker(at, rowName(p.note));
    }
  }
  writer.close(last);
  return text;
}
