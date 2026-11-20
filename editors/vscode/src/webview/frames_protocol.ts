// The messages between the extension and the frames panel's webview
// (frames.ts), defined once for both ends and checked at each
// ([isFromFrames], [isToFrames]): postMessage carries anything.
import type { Bar, FramesSummary, Metric } from '../core/frames.js';

/** What the panel shows: the bars of the last frames, and the summary. */
export interface FramesState {
  /** Why there are no bars (no app, no frame yet); '' where there are. */
  readonly message: string;
  /** What the bars say beside it (an app that gives no times); '' for nothing. */
  readonly note: string;
  readonly metric: Metric;
  readonly bars: readonly Bar[];
  readonly summary: FramesSummary;
}

/** What the extension tells the panel. */
export type ToFrames = { readonly type: 'state'; readonly state: FramesState };

/** What the panel tells the extension. */
export type FromFrames =
  /** It is up: the state, please. */
  | { readonly type: 'ready' }
  /** The bars are to measure [metric]. */
  | { readonly type: 'metric'; readonly metric: Metric }
  /** A click on the bar of the frame [frame]. */
  | { readonly type: 'pick'; readonly frame: number }
  /** Forget the frames kept. */
  | { readonly type: 'clear' };

type Fields = Record<string, unknown>;

const isObject = (m: unknown): m is Fields => typeof m === 'object' && m !== null;
const isMetric = (v: unknown): v is Metric => v === 'time' || v === 'bytes';

/** Whether [m] is a [ToFrames] message. */
export function isToFrames(m: unknown): m is ToFrames {
  if (!isObject(m) || m.type !== 'state' || !isObject(m.state)) {
    return false;
  }
  const s = m.state;
  return typeof s.message === 'string' && typeof s.note === 'string' && isMetric(s.metric) && Array.isArray(s.bars) && isObject(s.summary);
}

/** Whether [m] is a [FromFrames] message. */
export function isFromFrames(m: unknown): m is FromFrames {
  if (!isObject(m)) {
    return false;
  }
  switch (m.type) {
    case 'ready':
    case 'clear':
      return true;
    case 'metric':
      return isMetric(m.metric);
    case 'pick':
      return typeof m.frame === 'number' && Number.isInteger(m.frame) && m.frame >= 0;
    default:
      return false;
  }
}
