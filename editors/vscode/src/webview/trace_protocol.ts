// The messages between the extension and the trace viewer's webview
// (trace.ts), defined once for both ends and checked at each: postMessage
// carries anything.
import type { Rect, StepFrame, WireEvent } from '../core/trace.js';

/** A step as the list shows it, with where its screens are in the cast. */
export interface StepRow {
  readonly label: string;
  readonly ok: boolean;
  /** The cast events (inclusive) its screen before and after are replayed to; -1: nothing drawn yet. */
  readonly before: number;
  readonly after: number;
  /** Each frame it drew. */
  readonly frames: readonly StepFrame[];
  /** The target's cells, outlined on the screens; null: none. */
  readonly outline: Rect | null;
}

/** What is told of the step selected: the tabs of the viewer. */
export interface StepDetail {
  readonly facts: readonly string[];
  /** The widget tree the step ended with, or the last one kept. */
  readonly tree: string | null;
  /** The records of the app's log written during the step. */
  readonly log: readonly string[];
  /** The sequences the app wrote during the step, a line each. */
  readonly sequences: string;
}

/** What the extension tells the viewer. */
export type ToTrace =
  /** The trace: its name, the terminal's size, the steps, the cast's output and resizes; [select] is the step to show first (-1: none). */
  | {
      readonly type: 'open';
      readonly title: string;
      readonly width: number;
      readonly height: number;
      readonly steps: readonly StepRow[];
      readonly events: readonly WireEvent[];
      readonly select: number;
    }
  /** The detail of step [index]. */
  | { readonly type: 'detail'; readonly index: number; readonly detail: StepDetail };

/** What the viewer tells the extension. */
export type FromTrace =
  /** It is up: the trace, please. */
  | { readonly type: 'ready' }
  /** A step was selected in the list. */
  | { readonly type: 'select'; readonly index: number };

type Fields = Record<string, unknown>;
const isObject = (m: unknown): m is Fields => typeof m === 'object' && m !== null;
const isIndex = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v) && v >= 0;
const isStrings = (v: unknown): v is string[] => Array.isArray(v) && v.every((s) => typeof s === 'string');

/** Whether [m] is a [FromTrace] message. */
export function isFromTrace(m: unknown): m is FromTrace {
  if (!isObject(m)) {
    return false;
  }
  return m.type === 'ready' || (m.type === 'select' && isIndex(m.index));
}

const isRect = (r: unknown): boolean => r === null || (isObject(r) && ['x', 'y', 'width', 'height'].every((k) => typeof r[k] === 'number'));
const isPlace = (v: unknown): boolean => typeof v === 'number' && Number.isInteger(v) && v >= -1;

function isRow(r: unknown): r is StepRow {
  return (
    isObject(r) &&
    typeof r.label === 'string' &&
    typeof r.ok === 'boolean' &&
    isPlace(r.before) &&
    isPlace(r.after) &&
    Array.isArray(r.frames) &&
    r.frames.every((f) => isObject(f) && typeof f.frame === 'number' && isPlace(f.upTo)) &&
    isRect(r.outline)
  );
}

const isWire = (e: unknown): boolean => Array.isArray(e) && e.length === 3 && isIndex(e[0]) && (e[1] === 'o' || e[1] === 'r') && typeof e[2] === 'string';

/** Whether [m] is a [ToTrace] message. */
export function isToTrace(m: unknown): m is ToTrace {
  if (!isObject(m)) {
    return false;
  }
  if (m.type === 'open') {
    return (
      typeof m.title === 'string' &&
      isIndex(m.width) &&
      isIndex(m.height) &&
      Array.isArray(m.steps) &&
      m.steps.every(isRow) &&
      Array.isArray(m.events) &&
      m.events.every(isWire) &&
      typeof m.select === 'number' &&
      Number.isInteger(m.select) &&
      m.select >= -1
    );
  }
  if (m.type === 'detail') {
    const d = m.detail;
    return isIndex(m.index) && isObject(d) && isStrings(d.facts) && (d.tree === null || typeof d.tree === 'string') && isStrings(d.log) && typeof d.sequences === 'string';
  }
  return false;
}
