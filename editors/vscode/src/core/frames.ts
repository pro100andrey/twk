// What the frames panel shows of an app: the last frames it drew, each a
// time and a number of bytes, as the events `twk.frame` give them (posted
// while `ext.twk.flags` `frameEvents` is on; `DebugAids._frameData` in
// packages/twk/lib/src/binding/app_binding.dart), as bars, with the median,
// the count and the slowest. A frame's time comes from the event's `stats`
// (`FrameStats` of twk_core's app.dart: micros, build, layout, paint,
// present, bytes of that frame); an app that gives none (older) shows the
// bytes as the difference of `outputWritten` between two events, and the
// times as unknown. No vscode import: its tests run under plain node.
import { inspectorVersion } from './inspect.js';

/** The cost of one frame, as `FrameStats` has it: microseconds of the whole and of each phase, and the bytes written. */
export interface FrameStats {
  readonly micros: number;
  readonly build: number;
  readonly layout: number;
  readonly paint: number;
  readonly present: number;
  readonly bytes: number;
}

/** What a `twk.frame` event says, of a version this reads. */
export interface FrameEvent {
  /** How many frames the app has run (`TwkApp.framesRun`). */
  readonly frame: number;
  /** Whether this event is of a frame drawn; one that is not leaves the screen as it was. */
  readonly drawn: boolean;
  /** The app's cumulative bytes written at the end of the frame, null where the terminal does not count them. */
  readonly outputWritten: number | null;
  /** Absent in an app that does not give them. */
  readonly stats?: FrameStats;
}

const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const isCount = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v) && v >= 0;
const isMeasure = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v) && v >= 0;

/** The stats of an event; undefined for none, or for any a field of which is no measure (the app is then taken as one that gives none). */
function parseStats(v: unknown): FrameStats | undefined {
  if (!isRecord(v)) {
    return undefined;
  }
  const { micros, build, layout, paint, present, bytes } = v;
  if (isMeasure(micros) && isMeasure(build) && isMeasure(layout) && isMeasure(paint) && isMeasure(present) && isMeasure(bytes)) {
    return { micros, build, layout, paint, present, bytes };
  }
  return undefined;
}

/** What `twk.frame` carries; undefined for data of another version (an event of another is not taken for one) or without a frame count. */
export function parseFrameEvent(data: unknown): FrameEvent | undefined {
  if (!isRecord(data) || data.version !== inspectorVersion || !isCount(data.frame) || typeof data.drawn !== 'boolean') {
    return undefined;
  }
  const stats = parseStats(data.stats);
  return {
    frame: data.frame,
    drawn: data.drawn,
    outputWritten: isCount(data.outputWritten) ? data.outputWritten : null,
    ...(stats ? { stats } : {}),
  };
}

/** A frame drawn, as the panel keeps it. */
export interface FrameSample {
  readonly frame: number;
  /** The app's cumulative bytes at its end: where the sequence log finds it. Null where not counted. */
  readonly outputWritten: number | null;
  /** Microseconds of the frame; null where the app gave no stats. */
  readonly micros: number | null;
  /** Bytes it wrote; null where neither stats nor two counts say. */
  readonly bytes: number | null;
  readonly stats?: FrameStats;
}

/** What the bars measure. */
export type Metric = 'time' | 'bytes';

/** The last frames drawn, the newest last, at most [limit]. */
export class FrameHistory {
  private kept: FrameSample[] = [];
  /** How many frames were drawn since it began, those dropped from [kept] among them. */
  private seen = 0;
  /** The count of the event before, drawn or not: where a frame's bytes begin. */
  private lastWritten: number | null = null;

  constructor(private readonly limit = 100) {}

  /** The frames kept, the oldest first. */
  get samples(): readonly FrameSample[] {
    return this.kept;
  }

  /** How many frames were drawn since it began. */
  get total(): number {
    return this.seen;
  }

  /** Takes [e]: kept as a frame where it is of one drawn; returns it. */
  add(e: FrameEvent): FrameSample | undefined {
    const before = this.lastWritten;
    this.lastWritten = e.outputWritten;
    if (!e.drawn) {
      return undefined;
    }
    const bytes = e.stats ? e.stats.bytes : e.outputWritten !== null && before !== null && e.outputWritten >= before ? e.outputWritten - before : null;
    const sample: FrameSample = {
      frame: e.frame,
      outputWritten: e.outputWritten,
      micros: e.stats ? e.stats.micros : null,
      bytes,
      ...(e.stats ? { stats: e.stats } : {}),
    };
    this.seen++;
    this.kept.push(sample);
    if (this.kept.length > this.limit) {
      this.kept = this.kept.slice(this.kept.length - this.limit);
    }
    return sample;
  }

  clear(): void {
    this.kept = [];
    this.seen = 0;
    this.lastWritten = null;
  }
}

/** [s]'s value for [metric]; null where unknown. */
export function valueOf(s: FrameSample, metric: Metric): number | null {
  return metric === 'time' ? s.micros : s.bytes;
}

/** One bar: a frame, its value and its height as a share of the tallest (0 for an unknown value). */
export interface Bar {
  readonly frame: number;
  readonly value: number | null;
  /** From 0 to 1. */
  readonly height: number;
  /** What it says when pointed at. */
  readonly title: string;
}

/** What the panel says of the frames shown. */
export interface FramesSummary {
  readonly metric: Metric;
  /** How many frames the bars show. */
  readonly count: number;
  /** How many frames were drawn since the panel began. */
  readonly total: number;
  /** Of the values known: the median (the mean of the two middle ones where even); undefined for none. */
  readonly median?: number;
  /** The frame with the greatest value (the latest of equals); undefined for none known. */
  readonly slowest?: { readonly frame: number; readonly value: number };
}

/** [micros] as a person reads it: `850 µs`, `2.4 ms`. */
export function formatMicros(micros: number): string {
  return micros < 1000 ? `${Math.round(micros)} µs` : `${(micros / 1000).toFixed(micros < 10000 ? 1 : 0)} ms`;
}

/** [bytes] as a person reads it: `812 B`, `1.2 kB`. */
export function formatBytes(bytes: number): string {
  return bytes < 1000 ? `${Math.round(bytes)} B` : `${(bytes / 1000).toFixed(bytes < 10000 ? 1 : 0)} kB`;
}

/** [value] in the unit of [metric]. */
export function formatValue(value: number, metric: Metric): string {
  return metric === 'time' ? formatMicros(value) : formatBytes(value);
}

/** The median of [values]; undefined for none. */
export function median(values: readonly number[]): number | undefined {
  if (values.length === 0) {
    return undefined;
  }
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 === 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/** The bars of [samples] for [metric], the oldest first. */
export function barsOf(samples: readonly FrameSample[], metric: Metric): Bar[] {
  const values = samples.map((s) => valueOf(s, metric));
  const top = Math.max(0, ...values.filter((v): v is number => v !== null));
  return samples.map((s, i) => {
    const value = values[i];
    const phases = s.stats ? ` (build ${formatMicros(s.stats.build)}, layout ${formatMicros(s.stats.layout)}, paint ${formatMicros(s.stats.paint)}, present ${formatMicros(s.stats.present)})` : '';
    return {
      frame: s.frame,
      value,
      height: value === null || top === 0 ? 0 : value / top,
      title: `frame ${s.frame}: ${value === null ? `${metric} unknown` : formatValue(value, metric)}${metric === 'time' ? phases : ''}`,
    };
  });
}

/** The median, the count and the slowest of [samples] for [metric]; [total] is how many frames were drawn since the start. */
export function summarize(samples: readonly FrameSample[], metric: Metric, total = samples.length): FramesSummary {
  const known: { frame: number; value: number }[] = [];
  for (const s of samples) {
    const value = valueOf(s, metric);
    if (value !== null) {
      known.push({ frame: s.frame, value });
    }
  }
  let slowest: { frame: number; value: number } | undefined;
  for (const k of known) {
    if (!slowest || k.value >= slowest.value) {
      slowest = k;
    }
  }
  const m = median(known.map((k) => k.value));
  return { metric, count: samples.length, total, ...(m === undefined ? {} : { median: m }), ...(slowest ? { slowest } : {}) };
}
