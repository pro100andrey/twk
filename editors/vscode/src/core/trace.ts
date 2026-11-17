// A driver trace as twk_driver writes it (packages/twk_driver/DESIGN.md part
// 8, lib/src/trace.dart): `<name>.cast`, the pty's output as asciicast v2 with
// an event at each frame boundary and a marker for each step (core/cast.ts
// reads it), and `<name>.trace.jsonl`, a JSON line each of four kinds told by
// `type`: header, frame, step, tree. This file reads the lines and makes of
// them what the trace viewer shows: the steps as a list, the screens before,
// at and after a step as the cast events they are replayed to, the target's
// outline, the details, the tree, the log and the sequences of a step. Pure:
// no node, no DOM.
import { Cast } from './cast.js';
import { SequenceLog, wholeLog } from './seqlog.js';
import { logText } from './seqlog_save.js';

/** A rectangle of cells, from 0 at the top left. */
export interface Rect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

export interface TraceHeader {
  readonly program: string;
  readonly width: number;
  readonly height: number;
  readonly profile: string | null;
  readonly driven: boolean;
  readonly start: string | null;
}

/** A line of the frames table: [frame] ended at the cast event [castEvent]. */
export interface TraceFrame {
  readonly frame: number;
  readonly castEvent: number;
  readonly outputWritten: number;
  readonly raw: number;
}

export interface TraceTarget {
  readonly id: string | null;
  readonly type: string | null;
  readonly shown: Rect | null;
}

/** A step: an action of the driver. */
export interface TraceStep {
  readonly step: number;
  readonly action: string;
  readonly args: Readonly<Record<string, unknown>>;
  readonly finder: unknown;
  readonly target: TraceTarget | null;
  readonly hit: unknown;
  readonly frameBefore: number;
  readonly frame: number;
  /** The index of the step's marker among the cast's events. */
  readonly castEvent: number;
  /** Microseconds of the app's clock; of the driver's since the start. */
  readonly appTime: number | null;
  readonly realTime: number | null;
  readonly ok: boolean;
  readonly error: string | null;
  /** The key of the tree the step ended with, if it read one. */
  readonly tree: string | null;
  readonly log: readonly string[];
}

export interface TraceFile {
  readonly header: TraceHeader;
  readonly frames: readonly TraceFrame[];
  readonly steps: readonly TraceStep[];
  /** The trees by key, each kept once. */
  readonly trees: ReadonlyMap<string, string>;
}

type Json = Record<string, unknown>;

const isObject = (v: unknown): v is Json => typeof v === 'object' && v !== null && !Array.isArray(v);
const int = (v: unknown, fallback: number): number => (typeof v === 'number' && Number.isFinite(v) ? Math.trunc(v) : fallback);
const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);
const text = (v: unknown): string | null => (typeof v === 'string' ? v : null);

function rectOf(v: unknown): Rect | null {
  if (!isObject(v)) {
    return null;
  }
  const { x, y, width, height } = v;
  return [x, y, width, height].every((n) => typeof n === 'number' && Number.isFinite(n)) ? { x: x as number, y: y as number, width: width as number, height: height as number } : null;
}

function targetOf(v: unknown): TraceTarget | null {
  return isObject(v) ? { id: text(v.id), type: text(v.type), shown: rectOf(v.shown) } : null;
}

function stepOf(l: Json): TraceStep {
  return {
    step: int(l.step, 0),
    action: text(l.action) ?? '?',
    args: isObject(l.args) ? l.args : {},
    finder: l.finder ?? null,
    target: targetOf(l.target),
    hit: l.hit ?? null,
    frameBefore: int(l.frameBefore, 0),
    frame: int(l.frame, 0),
    castEvent: int(l.castEvent, -1),
    appTime: num(l.appTime),
    realTime: num(l.realTime),
    ok: l.result !== 'error',
    error: text(l.error),
    tree: text(l.tree),
    log: Array.isArray(l.log) ? l.log.filter((s): s is string => typeof s === 'string') : [],
  };
}

/** The trace in [source], the JSON lines of a `.trace.jsonl`; throws, saying the line, for one that is no JSON object or has no header. A line of another type is left out. */
export function parseTrace(source: string): TraceFile {
  let header: TraceHeader | undefined;
  const frames: TraceFrame[] = [];
  const steps: TraceStep[] = [];
  const trees = new Map<string, string>();
  source.split(/\r?\n/).forEach((line, i) => {
    if (line.trim() === '') {
      return;
    }
    let l: unknown;
    try {
      l = JSON.parse(line);
    } catch (e) {
      throw new Error(`line ${i + 1}: ${e instanceof Error ? e.message : String(e)}`);
    }
    if (!isObject(l)) {
      throw new Error(`line ${i + 1}: no JSON object`);
    }
    switch (l.type) {
      case 'header': {
        const size = Array.isArray(l.size) ? l.size : [];
        header = {
          program: text(l.program) ?? '',
          width: int(size[0], 80),
          height: int(size[1], 24),
          profile: text(l.profile),
          driven: l.driven === true,
          start: text(l.start),
        };
        break;
      }
      case 'frame':
        frames.push({ frame: int(l.frame, 0), castEvent: int(l.castEvent, -1), outputWritten: int(l.outputWritten, 0), raw: int(l.raw, 0) });
        break;
      case 'step':
        steps.push(stepOf(l));
        break;
      case 'tree':
        if (typeof l.key === 'string' && typeof l.text === 'string') {
          trees.set(l.key, l.text);
        }
        break;
    }
  });
  if (!header) {
    throw new Error('no header line: this is no driver trace');
  }
  return { header, frames, steps, trees };
}

/** The path of the cast of the trace at [path] (`.trace.jsonl`), or of the trace of the cast (`.cast`); undefined for another file. */
export function siblingOf(path: string): { readonly cast: string; readonly trace: string } | undefined {
  if (path.endsWith('.trace.jsonl')) {
    return { cast: `${path.slice(0, -'.trace.jsonl'.length)}.cast`, trace: path };
  }
  if (path.endsWith('.cast')) {
    return { cast: path, trace: `${path.slice(0, -'.cast'.length)}.trace.jsonl` };
  }
  return undefined;
}

/** The paths of a trace named in [output] (a test's failure report): its `.trace.jsonl` ones. */
export function tracePathsIn(output: string): string[] {
  return [...output.matchAll(/(\S+\.trace\.jsonl)\b/g)].map((m) => m[1]);
}

/**
 * The cast event frame [frame] ended in: the cast replayed to it (inclusive)
 * is the frame's screen. A frame the table lacks is the last one before it;
 * before all, -1: nothing drawn.
 */
export function eventOfFrame(trace: TraceFile, frame: number): number {
  let best: TraceFrame | undefined;
  for (const f of trace.frames) {
    if (f.frame <= frame && (!best || f.frame >= best.frame)) {
      best = f;
    }
  }
  return best?.castEvent ?? -1;
}

/** A place in the cast to show the screen of: the events up to and including [upTo], the frame it is. */
export interface StepFrame {
  readonly frame: number;
  readonly upTo: number;
}

/** The screens of a step: before it, after it, and each frame it drew between. */
export interface StepScreens {
  readonly before: number;
  readonly after: number;
  readonly frames: readonly StepFrame[];
}

export function stepScreens(trace: TraceFile, step: TraceStep): StepScreens {
  const frames: StepFrame[] = [];
  for (let f = step.frameBefore + 1; f <= step.frame; f++) {
    frames.push({ frame: f, upTo: eventOfFrame(trace, f) });
  }
  return { before: eventOfFrame(trace, step.frameBefore), after: eventOfFrame(trace, step.frame), frames };
}

/** What a step is called in the list: `3 tap {"key":"inc"}`, its arguments cut. */
export function stepLabel(step: TraceStep): string {
  const args = Object.keys(step.args).length === 0 ? '' : ` ${JSON.stringify(step.args)}`;
  const label = `${step.step} ${step.action}${args}`;
  const chars = Array.from(label);
  return chars.length <= 80 ? label : `${chars.slice(0, 79).join('')}…`;
}

/** The index of the first step that failed, or 0 for none did (-1 for no steps). */
export function firstFailed(trace: TraceFile): number {
  const i = trace.steps.findIndex((s) => !s.ok);
  return i >= 0 ? i : trace.steps.length > 0 ? 0 : -1;
}

/** [micros] as `12.3 ms`, or `1.50 s`; `-` for none. */
export function formatMicros(micros: number | null): string {
  if (micros === null) {
    return '-';
  }
  return micros >= 1e6 ? `${(micros / 1e6).toFixed(2)} s` : `${(micros / 1e3).toFixed(1)} ms`;
}

const pretty = (v: unknown): string => JSON.stringify(v);

/** The facts of a step, a line each: what it did, to what, how it ended. */
export function stepFacts(step: TraceStep): string[] {
  const lines = [`${step.step} ${step.action}: ${step.ok ? 'ok' : 'failed'}`];
  if (Object.keys(step.args).length > 0) {
    lines.push(`args ${pretty(step.args)}`);
  }
  if (step.finder !== null) {
    lines.push(`finder ${pretty(step.finder)}`);
  }
  const t = step.target;
  if (t) {
    const at = t.shown ? ` at ${t.shown.x},${t.shown.y} ${t.shown.width}x${t.shown.height}` : '';
    lines.push(`target ${[t.type, t.id].filter((s) => s !== null).join(' ')}${at}`);
  }
  if (step.hit !== null) {
    lines.push(`hit ${pretty(step.hit)}`);
  }
  lines.push(`frames ${step.frameBefore} -> ${step.frame}`);
  lines.push(`app time ${formatMicros(step.appTime)}, driver time ${formatMicros(step.realTime)}`);
  if (step.error !== null) {
    lines.push(`error ${step.error}`);
  }
  return lines;
}

/**
 * The tree a step ended with, or the last one kept before it (a tree the
 * same as the last is not kept again, so a step that kept none saw that one).
 */
export function treeAt(trace: TraceFile, index: number): string | undefined {
  for (let i = index; i >= 0; i--) {
    const key = trace.steps[i].tree;
    if (key !== null) {
      return trace.trees.get(key);
    }
  }
  return undefined;
}

/** The cast events from a step's marker up to what it ended in, as the sequence log's rows (a line each, as `twk decode`). */
export function stepSequences(cast: Cast, trace: TraceFile, step: TraceStep): string {
  const from = step.castEvent + 1;
  const to = Math.max(eventOfFrame(trace, step.frame), step.castEvent);
  const log = new SequenceLog();
  const encoder = new TextEncoder();
  for (let i = Math.max(from, 0); i <= to && i < cast.events.length; i++) {
    const e = cast.events[i];
    if (e.code === 'o') {
      log.output(e.time * 1000, encoder.encode(e.data));
    }
  }
  return logText(log.all(), wholeLog);
}

/** The cast's events as the viewer replays them: output and resizes, each with its index among all the events. */
export type WireEvent = readonly [index: number, code: 'o' | 'r', data: string];

export function wireEvents(cast: Cast): WireEvent[] {
  const out: WireEvent[] = [];
  cast.events.forEach((e, i) => {
    if (e.code === 'o' || e.code === 'r') {
      out.push([i, e.code, e.data]);
    }
  });
  return out;
}

/** Where the `driverTest(` calls of a test file are, as lines from 0 (outside comments and strings is not told: a call in a comment is found too). */
export function driverTestLines(source: string): number[] {
  const out: number[] = [];
  source.split(/\r?\n/).forEach((line, i) => {
    if (/^\s*driverTest\s*\(/.test(line)) {
      out.push(i);
    }
  });
  return out;
}

/** The `.trace.jsonl` files in a terminal [line], with where each is in it. */
export function traceLinks(line: string): { readonly startIndex: number; readonly length: number; readonly path: string }[] {
  return [...line.matchAll(/[^\s'"]+\.trace\.jsonl/g)].map((m) => ({ startIndex: m.index, length: m[0].length, path: m[0] }));
}
