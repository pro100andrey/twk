// The messages between the extension and the app log's webview
// (app_logs.ts), defined once for both ends and checked at each
// ([isFromAppLogs], [isToAppLogs]): postMessage carries anything.
import { Level, levels } from '../core/app_log.js';

/** An app whose log is followed. */
export interface AppInfo {
  readonly id: number;
  readonly label: string;
  readonly state: 'waiting' | 'connected' | 'ended';
}

/** A line of a stack, and whether it can be opened in the editor. */
export interface FrameRow {
  readonly text: string;
  readonly open: boolean;
}

/** A row of the log: a record of an app, or a note (an app connected or went away). */
export interface LogRow {
  readonly id: number;
  readonly app: number;
  /** Milliseconds since the epoch. */
  readonly time: number;
  readonly level: Level | 'note';
  readonly message: string;
  readonly error?: string;
  readonly stack?: readonly FrameRow[];
}

/** What the extension tells the log. */
export type ToAppLogs =
  /** Every app and row kept, in place of what it shows: its first, or after a clear. */
  | { readonly type: 'reset'; readonly title: string; readonly apps: readonly AppInfo[]; readonly rows: readonly LogRow[] }
  /** The apps, their states changed. */
  | { readonly type: 'apps'; readonly apps: readonly AppInfo[] }
  /** Rows made since the last. */
  | { readonly type: 'rows'; readonly rows: readonly LogRow[] };

/** What the log tells the extension. */
export type FromAppLogs =
  /** It is up: all of it, please. */
  | { readonly type: 'ready' }
  /** Forget the rows kept. */
  | { readonly type: 'clear' }
  /** Open the [frame] of the stack of the row [row] in the editor. */
  | { readonly type: 'open'; readonly row: number; readonly frame: number }
  /** What it shows now, told after each change: how many rows, how many held while paused, the messages of the last rows (the last last). */
  | { readonly type: 'shown'; readonly rows: number; readonly held: number; readonly last: readonly string[] };

type Fields = Record<string, unknown>;

const isObject = (m: unknown): m is Fields => typeof m === 'object' && m !== null;
const isNumber = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v) && v >= 0;
const states: readonly string[] = ['waiting', 'connected', 'ended'];

function isApp(a: unknown): a is AppInfo {
  return isObject(a) && isNumber(a.id) && typeof a.label === 'string' && typeof a.state === 'string' && states.includes(a.state);
}

function isFrame(f: unknown): f is FrameRow {
  return isObject(f) && typeof f.text === 'string' && typeof f.open === 'boolean';
}

/** Whether [r] is a [LogRow]. */
export function isRow(r: unknown): r is LogRow {
  return (
    isObject(r) &&
    isNumber(r.id) &&
    isNumber(r.app) &&
    typeof r.time === 'number' &&
    Number.isFinite(r.time) &&
    typeof r.level === 'string' &&
    (r.level === 'note' || (levels as readonly string[]).includes(r.level)) &&
    typeof r.message === 'string' &&
    (r.error === undefined || typeof r.error === 'string') &&
    (r.stack === undefined || (Array.isArray(r.stack) && r.stack.every(isFrame)))
  );
}

const isApps = (v: unknown): v is readonly AppInfo[] => Array.isArray(v) && v.every(isApp);
const isRows = (v: unknown): v is readonly LogRow[] => Array.isArray(v) && v.every(isRow);

/** Whether [m] is a [ToAppLogs] message. */
export function isToAppLogs(m: unknown): m is ToAppLogs {
  if (!isObject(m)) {
    return false;
  }
  switch (m.type) {
    case 'reset':
      return typeof m.title === 'string' && isApps(m.apps) && isRows(m.rows);
    case 'apps':
      return isApps(m.apps);
    case 'rows':
      return isRows(m.rows);
    default:
      return false;
  }
}

/** Whether [m] is a [FromAppLogs] message. */
export function isFromAppLogs(m: unknown): m is FromAppLogs {
  if (!isObject(m)) {
    return false;
  }
  switch (m.type) {
    case 'ready':
    case 'clear':
      return true;
    case 'open':
      return isNumber(m.row) && isNumber(m.frame);
    case 'shown':
      return isNumber(m.rows) && isNumber(m.held) && Array.isArray(m.last) && m.last.every((n) => typeof n === 'string');
    default:
      return false;
  }
}
