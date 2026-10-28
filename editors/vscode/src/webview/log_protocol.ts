// The messages between the extension and the sequence log's webview
// (log.ts), defined once for both ends and checked at each
// ([isFromLog], [isToLog]): postMessage carries anything.
import type { Direction, EntryKind, LogEntry } from '../core/seqlog.js';

/** What the extension tells the log. */
export type ToLog =
  /** Every entry kept, in place of what it shows: its first, or the extension's again (the webview loaded again, or cleared). */
  | { readonly type: 'reset'; readonly title: string; readonly entries: readonly LogEntry[] }
  /** Entries made since the last. */
  | { readonly type: 'entries'; readonly entries: readonly LogEntry[] }
  /** Its terminal was closed: nothing more comes. */
  | { readonly type: 'ended' };

/** What the log tells the extension. */
export type FromLog =
  /** It is up: the entries kept, please. */
  | { readonly type: 'ready' }
  /** Forget the entries kept. */
  | { readonly type: 'clear' }
  /** What it shows now, told after each change: how many rows, how many entries held while paused, the names of the last rows (the last last). */
  | { readonly type: 'shown'; readonly rows: number; readonly held: number; readonly last: readonly string[] };

type Fields = Record<string, unknown>;

const isObject = (m: unknown): m is Fields => typeof m === 'object' && m !== null;
const directions: readonly Direction[] = ['out', 'in', 'note'];
const kinds: readonly EntryKind[] = ['text', 'control', 'esc', 'ss3', 'csi', 'osc', 'dcs', 'apc', 'pm', 'sos', 'mouse', 'frame', 'note'];
const isNumber = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v) && v >= 0;

/** Whether [e] is a [LogEntry], its children too. */
export function isEntry(e: unknown): e is LogEntry {
  return (
    isObject(e) &&
    isNumber(e.id) &&
    isNumber(e.time) &&
    directions.some((d) => d === e.direction) &&
    kinds.some((k) => k === e.kind) &&
    typeof e.name === 'string' &&
    typeof e.raw === 'string' &&
    isNumber(e.bytes) &&
    (e.children === undefined || (Array.isArray(e.children) && e.children.every(isEntry)))
  );
}

const isEntries = (v: unknown): v is readonly LogEntry[] => Array.isArray(v) && v.every(isEntry);

/** Whether [m] is a [ToLog] message. */
export function isToLog(m: unknown): m is ToLog {
  if (!isObject(m)) {
    return false;
  }
  switch (m.type) {
    case 'reset':
      return typeof m.title === 'string' && isEntries(m.entries);
    case 'entries':
      return isEntries(m.entries);
    case 'ended':
      return true;
    default:
      return false;
  }
}

/** Whether [m] is a [FromLog] message. */
export function isFromLog(m: unknown): m is FromLog {
  if (!isObject(m)) {
    return false;
  }
  switch (m.type) {
    case 'ready':
    case 'clear':
      return true;
    case 'shown':
      return isNumber(m.rows) && isNumber(m.held) && Array.isArray(m.last) && m.last.every((n) => typeof n === 'string');
    default:
      return false;
  }
}
