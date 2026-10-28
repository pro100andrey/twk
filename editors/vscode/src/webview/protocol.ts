// The messages between the extension and the terminal's webview (main.ts),
// defined once for both ends. What arrives from the other end is checked
// ([isFromWebview], [isToWebview]) before it is taken for one of these:
// postMessage carries anything.
import type { Answers, Graphics, Query } from '../core/capabilities.js';
import type { TerminalRequest } from '../core/emulation.js';

/** What the extension tells the webview. */
export type ToWebview =
  /** Bytes for xterm.js; answered with `written` and the same [id] once parsed. */
  | { readonly type: 'output'; readonly id: number; readonly data: Uint8Array }
  /** A fixed size, or null for both: fitted to the panel. */
  | { readonly type: 'size'; readonly columns: number | null; readonly lines: number | null }
  /** Answered with `snapshot` and the same [id]. */
  | { readonly type: 'snapshot'; readonly id: number }
  | { readonly type: 'focus' }
  /** What to answer and emulate for the app taken now (core/capabilities.ts's answersOf). */
  | { readonly type: 'answers'; readonly answers: Answers }
  /** Whether each click picks a cell (told back as `picked`) in place of reaching the app, until told off or Escape. */
  | { readonly type: 'pick'; readonly on: boolean }
  /** The bar of a recording played back, as it is now; null: none (a terminal of an app). */
  | { readonly type: 'player'; readonly state: PlayerState | null };

export type ScreenBuffer = 'normal' | 'alternate';

/** Where a recording played back is. */
export interface PlayerState {
  readonly playing: boolean;
  /** The frames shown (from 0, none yet), of how many. */
  readonly frame: number;
  readonly frames: number;
  /** The recording's time of the last frame shown, and of its end, in seconds. */
  readonly time: number;
  readonly duration: number;
}

/** What a player's bar (or a key in its terminal) asks: play or pause, a frame on, a frame back, from the start. */
export type PlayerControl = 'toggle' | 'step' | 'back' | 'restart';

const playerControls: readonly PlayerControl[] = ['toggle', 'step', 'back', 'restart'];

/** What the webview tells the extension. */
export type FromWebview =
  /** xterm.js is open, at this size. */
  | { readonly type: 'ready'; readonly columns: number; readonly lines: number }
  | { readonly type: 'resize'; readonly columns: number; readonly lines: number }
  /** Keys and answers: UTF-8 text, or bytes as latin1 when [binary] (X10 mouse). */
  | { readonly type: 'input'; readonly data: string; readonly binary: boolean }
  | { readonly type: 'written'; readonly id: number }
  | {
      readonly type: 'snapshot';
      readonly id: number;
      readonly buffer: ScreenBuffer;
      readonly rows: readonly string[];
      /** Each row's cells, `#` for one of a background of its own (an outline's), a space for the terminal's. */
      readonly backgrounds?: readonly string[];
    }
  /** What the app asked of the editor (a notification, progress, the clipboard, a link clicked), as the answers allow. */
  | { readonly type: 'request'; readonly request: TerminalRequest }
  /** The cell a click picked, from 0, and the row the cursor was on then; null: the pick ended with none (Escape). */
  | { readonly type: 'picked'; readonly cell: { readonly x: number; readonly y: number; readonly cursorY: number } | null }
  /** A button of the player's bar. */
  | { readonly type: 'control'; readonly control: PlayerControl };

type Fields = Record<string, unknown>;

const isObject = (m: unknown): m is Fields => typeof m === 'object' && m !== null;
const isCount = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v) && v >= 0;
const isSize = (m: Fields) => isCount(m.columns) && isCount(m.lines);
const isText = (v: unknown): v is string => typeof v === 'string';

const queries: readonly Query[] = ['synchronizedOutput', 'graphemes', 'inBandResize', 'margins', 'colorSchemeReports', 'colors', 'deviceAttributes'];
const graphics: readonly Graphics[] = ['none', 'sixel', 'iterm2'];
const answerFlags = ['kittyKeyboard', 'cellSize', 'notifications', 'progress', 'pointerShapes', 'links', 'clipboard'] as const;

/** Whether [a] is an [Answers]. */
export function isAnswers(a: unknown): a is Answers {
  return (
    isObject(a) &&
    Array.isArray(a.deny) &&
    a.deny.every((q) => queries.some((k) => k === q)) &&
    (a.version === null || isText(a.version)) &&
    graphics.some((g) => g === a.graphics) &&
    answerFlags.every((f) => typeof a[f] === 'boolean')
  );
}

/** Whether [r] is a [TerminalRequest]. */
export function isRequest(r: unknown): r is TerminalRequest {
  if (!isObject(r)) {
    return false;
  }
  switch (r.type) {
    case 'notify':
      return isText(r.title) && isText(r.body);
    case 'progress':
      return isCount(r.state) && r.state <= 4 && (r.percent === null || (isCount(r.percent) && r.percent <= 100));
    case 'clipboard':
      return isText(r.text);
    case 'openLink':
      return isText(r.uri);
    default:
      return false;
  }
}

const isSeconds = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v) && v >= 0;

/** Whether [s] is a [PlayerState]. */
export function isPlayerState(s: unknown): s is PlayerState {
  return isObject(s) && typeof s.playing === 'boolean' && isCount(s.frame) && isCount(s.frames) && isSeconds(s.time) && isSeconds(s.duration);
}

/** Whether [m] is a [FromWebview] message. */
export function isFromWebview(m: unknown): m is FromWebview {
  if (!isObject(m)) {
    return false;
  }
  switch (m.type) {
    case 'ready':
    case 'resize':
      return isSize(m);
    case 'input':
      return typeof m.data === 'string' && typeof m.binary === 'boolean';
    case 'written':
      return isCount(m.id);
    case 'snapshot':
      return (
        isCount(m.id) &&
        (m.buffer === 'normal' || m.buffer === 'alternate') &&
        Array.isArray(m.rows) &&
        m.rows.every((r) => typeof r === 'string') &&
        (m.backgrounds === undefined || (Array.isArray(m.backgrounds) && m.backgrounds.every((r) => typeof r === 'string')))
      );
    case 'request':
      return isRequest(m.request);
    case 'picked':
      return m.cell === null || (isObject(m.cell) && isCount(m.cell.x) && isCount(m.cell.y) && Number.isInteger(m.cell.cursorY));
    case 'control':
      return playerControls.some((c) => c === m.control);
    default:
      return false;
  }
}

/** Whether [m] is a [ToWebview] message. */
export function isToWebview(m: unknown): m is ToWebview {
  if (!isObject(m)) {
    return false;
  }
  const sizeOrNull = (v: unknown) => v === null || v === undefined || isCount(v);
  switch (m.type) {
    case 'output':
      return isCount(m.id) && m.data instanceof Uint8Array;
    case 'size':
      return sizeOrNull(m.columns) && sizeOrNull(m.lines);
    case 'snapshot':
      return isCount(m.id);
    case 'focus':
      return true;
    case 'answers':
      return isAnswers(m.answers);
    case 'pick':
      return typeof m.on === 'boolean';
    case 'player':
      return m.state === null || isPlayerState(m.state);
    default:
      return false;
  }
}
