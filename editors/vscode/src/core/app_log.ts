// The log an app serves (`LogSink.serve`, twk_core's lib/src/log.dart and
// platform/log_server.dart) as the extension reads it: the address file
// `.dart_tool/twk/logs` (the socket and its token, as `twk logs` reads it,
// twk_dev's lib/src/logs.dart), a record of a line of JSON
// (`LogRecord.toJson`), and the frames of a stack trace made places of the
// code. Pure: nothing here reads a file or a socket.
import { ShellAddress, fromVariable } from './address.js';

/** How much a record matters, in the order of twk_core's `LogLevel`. */
export type Level = 'debug' | 'info' | 'warning' | 'error';

export const levels: readonly Level[] = ['debug', 'info', 'warning', 'error'];

/** A record of the app's log. */
export interface AppRecord {
  /** Milliseconds since the epoch. */
  readonly time: number;
  readonly level: Level;
  readonly message: string;
  readonly error?: string;
  readonly stack?: string;
}

/** The file of the project the app serves its log's address in. */
export const addressFile = ['.dart_tool', 'twk', 'logs'] as const;

/**
 * The address a `logs` file holds: the place (`unix:<path>` or
 * `tcp:<host>:<port>`) and the token, on a line each, as twk_core's
 * `LocalAddress` writes them; undefined for anything else.
 */
export function parseAddressFile(text: string): ShellAddress | undefined {
  const lines = text.split(/\r?\n/);
  const [where, token] = lines;
  return where && token ? fromVariable(`${where}#${token}`) : undefined;
}

const isLevel = (v: unknown): v is Level => levels.some((l) => l === v);

/**
 * The record a line of the served log is: its JSON, checked. A line that
 * is not one (a text, or a record of another version) is a record of its
 * own at [now], level `info`, its message the line, as `twk logs` shows
 * the line itself.
 */
export function parseRecord(line: string, now: number): AppRecord {
  try {
    const json: unknown = JSON.parse(line);
    if (typeof json === 'object' && json !== null && !Array.isArray(json)) {
      const j = json as Record<string, unknown>;
      const time = typeof j.time === 'string' ? Date.parse(j.time) : NaN;
      if (!Number.isNaN(time) && isLevel(j.level) && typeof j.message === 'string') {
        return {
          time,
          level: j.level,
          message: j.message,
          ...(typeof j.error === 'string' ? { error: j.error } : {}),
          ...(typeof j.stack === 'string' && j.stack.trim() !== '' ? { stack: j.stack } : {}),
        };
      }
    }
  } catch {
    // not JSON
  }
  return { time: now, level: 'info', message: line };
}

/** [time] as `09:05:07.042`, in local time, as twk_core's `LogRecord.formatTime`. */
export function formatTime(time: number): string {
  const d = new Date(time);
  const two = (n: number) => String(n).padStart(2, '0');
  return `${two(d.getHours())}:${two(d.getMinutes())}:${two(d.getSeconds())}.${String(d.getMilliseconds()).padStart(3, '0')}`;
}

/** Whether a record of [level], [message] and [error] is shown by the levels on and the word (lowercase, or empty). */
export function matchesFilter(
  row: { readonly level: Level; readonly message: string; readonly error?: string | undefined; readonly stack?: readonly { readonly text: string }[] | undefined },
  on: ReadonlySet<Level>,
  word: string,
): boolean {
  if (!on.has(row.level)) {
    return false;
  }
  if (word === '') {
    return true;
  }
  return [row.message, row.error ?? '', ...(row.stack ?? []).map((f) => f.text)].some((t) => t.toLowerCase().includes(word));
}

/** A line of a stack trace, and the place it names where it names one of Dart code. */
export interface Frame {
  readonly text: string;
  /** `file:` or `package:`, with the place in the file (from 1); not for `dart:` frames or a line with none. */
  readonly place?: { readonly uri: string; readonly line: number; readonly column: number };
}

// `#0      main (file:///a/b.dart:10:5)`, `#1  f (package:app/m.dart:3:4)`:
// the VM's own; the place ends at a closing parenthesis or a space
const vmFrame = /((?:file|package):[^\s)]*?):(\d+)(?::(\d+))?(?=\)|\s|$)/;
// `package:app/m.dart 3:4  f`: package:stack_trace's
const traceFrame = /^\s*((?:file|package):\S+?)\s+(\d+):(\d+)/;

/** The lines of [stack] as frames; blank lines left out. */
export function parseFrames(stack: string): Frame[] {
  return stack
    .split(/\r?\n/)
    .filter((l) => l.trim() !== '')
    .map((text) => {
      const m = vmFrame.exec(text) ?? traceFrame.exec(text);
      return m ? { text, place: { uri: m[1], line: Number(m[2]), column: m[3] === undefined ? 1 : Number(m[3]) } } : { text };
    });
}

/** The roots of the packages of a `package_config.json`, by name: URIs ending in `/`. */
export type Packages = ReadonlyMap<string, string>;

/**
 * The packages [json] (a `package_config.json`) lists, their `packageUri`
 * roots resolved against [configUri], the URI of the file; empty for a text
 * that is none.
 */
export function parsePackages(json: string, configUri: string): Packages {
  const packages = new Map<string, string>();
  try {
    const config: unknown = JSON.parse(json);
    const list = typeof config === 'object' && config !== null ? (config as { packages?: unknown }).packages : undefined;
    for (const p of Array.isArray(list) ? (list as unknown[]) : []) {
      const { name, rootUri, packageUri } = (p ?? {}) as Record<string, unknown>;
      if (typeof name === 'string' && typeof rootUri === 'string') {
        const root = new URL(rootUri.endsWith('/') ? rootUri : `${rootUri}/`, configUri);
        const lib = new URL(typeof packageUri === 'string' ? (packageUri.endsWith('/') ? packageUri : `${packageUri}/`) : '', root);
        packages.set(name, lib.href);
      }
    }
  } catch {
    // none
  }
  return packages;
}

/** The `file:` URI of [uri], a `file:` or a `package:` one; undefined where [packages] does not know the package. */
export function resolveUri(uri: string, packages: Packages): string | undefined {
  if (uri.startsWith('file:')) {
    return uri;
  }
  const m = /^package:([^/]+)\/(.*)$/.exec(uri);
  const root = m ? packages.get(m[1]) : undefined;
  return m && root ? new URL(m[2], root).href : undefined;
}

/**
 * The last [keep] items of a stream, trimmed in batches (a [slack] past
 * [keep], then the overflow dropped at once, not a copy per item), with a
 * pause that holds what comes meanwhile: [add] answers what is to be shown
 * now, [resume] what was held.
 */
export class RowBuffer<T> {
  private items: T[] = [];
  private heldItems: T[] = [];
  private isPaused = false;

  constructor(
    readonly keep: number,
    readonly slack: number = Math.max(1, Math.floor(keep / 10)),
  ) {}

  get paused(): boolean {
    return this.isPaused;
  }

  /** The items kept, the oldest first. */
  get kept(): readonly T[] {
    return this.items.length > this.keep ? this.items.slice(this.items.length - this.keep) : this.items;
  }

  /** How many items are held by the pause. */
  get held(): number {
    return this.heldItems.length;
  }

  /** The items kept that are not held, the oldest first. */
  get shown(): T[] {
    const kept = this.kept;
    return this.heldItems.length === 0 ? [...kept] : kept.slice(0, Math.max(0, kept.length - this.heldItems.length));
  }

  /** Replaces the items (and ends any pause's holding). */
  reset(items: readonly T[]): void {
    this.items = [...items];
    this.heldItems = [];
    this.trim();
  }

  /** Keeps [more]; answers those to show now: none while paused. */
  add(more: readonly T[]): readonly T[] {
    for (const m of more) {
      this.items.push(m);
    }
    this.trim();
    if (this.isPaused) {
      this.heldItems.push(...more);
      if (this.heldItems.length > this.keep) {
        this.heldItems.splice(0, this.heldItems.length - this.keep);
      }
      return [];
    }
    return more;
  }

  pause(): void {
    this.isPaused = true;
  }

  /** Ends the pause; answers the items held, to be shown now (they are kept already). */
  resume(): T[] {
    this.isPaused = false;
    const h = this.heldItems;
    this.heldItems = [];
    return h;
  }

  private trim(): void {
    if (this.items.length > this.keep + this.slack) {
      this.items.splice(0, this.items.length - this.keep);
    }
  }
}
