// The messages between the extension and the screen file editor's webview
// (screen.ts), defined once for both ends and checked at each
// ([isToScreen], [isFromScreen]): postMessage carries anything.
import type { CellChange, ScreenDiff, ScreenFile } from '../core/screen_file.js';

/** What the extension shows of a screen file. */
export type ScreenState =
  /** The file is no screen file: [message] says why. */
  | { readonly kind: 'bad'; readonly message: string }
  /**
   * The golden, and the screen a failed test left beside it where there is a
   * fresh one ([actual], [diff] against the golden); [stale] where one is
   * there but older than the golden.
   */
  | { readonly kind: 'ok'; readonly golden: ScreenFile; readonly actual: ScreenFile | null; readonly diff: ScreenDiff | null; readonly stale: boolean };

/** What the extension tells the screen editor. */
export type ToScreen = { readonly type: 'show'; readonly name: string; readonly state: ScreenState };

/** What the screen editor tells the extension. */
export type FromScreen =
  /** It is up: the state, please. */
  | { readonly type: 'ready' }
  /** Accept Actual: the screen of the failed test becomes the golden. */
  | { readonly type: 'accept' };

type Fields = Record<string, unknown>;

const isObject = (m: unknown): m is Fields => typeof m === 'object' && m !== null;
const isCount = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v) && v >= 0;
const isStrings = (v: unknown): v is readonly string[] => Array.isArray(v) && v.every((s) => typeof s === 'string');
const isPoint = (v: unknown): v is readonly [number, number] => Array.isArray(v) && v.length === 2 && isCount(v[0]) && isCount(v[1]);

/** Whether [f] is a [ScreenFile]. */
export function isScreenFile(f: unknown): f is ScreenFile {
  return (
    isObject(f) &&
    isCount(f.width) &&
    isCount(f.height) &&
    (f.cursor === null || isPoint(f.cursor)) &&
    isStrings(f.text) &&
    f.text.length === f.height &&
    isStrings(f.styles) &&
    f.styles.length === f.height &&
    isObject(f.legend) &&
    Object.values(f.legend).every((s) => typeof s === 'string')
  );
}

const isStyle = (v: unknown): v is string | null => v === null || typeof v === 'string';
const isPair = <T>(v: unknown, is: (x: unknown) => x is T): v is readonly [T, T] => Array.isArray(v) && v.length === 2 && is(v[0]) && is(v[1]);

function isChange(c: unknown): c is CellChange {
  return isObject(c) && isCount(c.x) && isCount(c.y) && isPair(c.text, (s): s is string => typeof s === 'string') && isPair(c.style, isStyle);
}

/** Whether [d] is a [ScreenDiff]. */
export function isScreenDiff(d: unknown): d is ScreenDiff {
  return (
    isObject(d) &&
    (d.size === null || isPair(d.size, isPoint)) &&
    (d.cursor === null || (Array.isArray(d.cursor) && d.cursor.length === 2 && d.cursor.every((c) => c === null || isPoint(c)))) &&
    Array.isArray(d.cells) &&
    d.cells.every(isChange)
  );
}

/** Whether [s] is a [ScreenState]. */
export function isScreenState(s: unknown): s is ScreenState {
  if (!isObject(s)) {
    return false;
  }
  if (s.kind === 'bad') {
    return typeof s.message === 'string';
  }
  return s.kind === 'ok' && isScreenFile(s.golden) && (s.actual === null || isScreenFile(s.actual)) && (s.diff === null || isScreenDiff(s.diff)) && typeof s.stale === 'boolean';
}

/** Whether [m] is a [ToScreen] message. */
export const isToScreen = (m: unknown): m is ToScreen => isObject(m) && m.type === 'show' && typeof m.name === 'string' && isScreenState(m.state);

/** Whether [m] is a [FromScreen] message. */
export const isFromScreen = (m: unknown): m is FromScreen => isObject(m) && (m.type === 'ready' || m.type === 'accept');
