// asciicast v2, as twk_dev's `twk record` writes it and `twk play` and
// `twk tape` read it (packages/twk_dev/lib/src/cast.dart), its writes
// played by twk_test's `screenFrames`: a header line, then an event a
// line, `[time, code, data]`. This file must write what that one writes
// and read what it
// reads: packages/twk_dev/test/cast.golden.json holds both to the same
// lines (test/unit/core/cast_golden.test.ts here, cast_golden_test.dart
// there). Pure: no node, no DOM.
import { SequenceReader, syncChange } from './sequences.js';

/** The first line of a recording, as cast.dart's `CastHeader`. */
export interface CastHeader {
  readonly width: number;
  readonly height: number;
  /** Seconds since the Unix epoch. */
  readonly timestamp?: number;
  /** The longest pause a player keeps, in seconds. */
  readonly idleTimeLimit?: number;
  readonly command?: string;
  readonly title?: string;
  /** `TERM` and `SHELL` of the recorded terminal. */
  readonly env?: Readonly<Record<string, string>>;
}

/** What kind an event is: output, input, a resize, a marker. */
export type CastCode = 'o' | 'i' | 'r' | 'm';

export interface CastEvent {
  /** Seconds from the start. */
  readonly time: number;
  /** cast.dart's codes; another a recording may have is read as it is. */
  readonly code: string;
  readonly data: string;
}

export interface Cast {
  readonly header: CastHeader;
  readonly events: readonly CastEvent[];
}

/**
 * [s] as Dart's jsonEncode writes a string: `"`, `\` and the C0 controls
 * escaped (`\b \t \n \f \r` short, the rest `\u00xx`), everything else as
 * it is (JSON.stringify does the same, but for a lone surrogate, which a
 * decoded string here never has).
 */
function jsonString(s: string): string {
  return JSON.stringify(s);
}

/** [n] as Dart writes a double: always with a fraction (`2.0`, `1.5`). */
function dartDouble(n: number): string {
  const s = String(n);
  return Number.isInteger(n) && !s.includes('e') ? `${s}.0` : s;
}

/** The header's line, as cast.dart's `jsonEncode(header.toJson())`: version 2, then the fields that are set, in its order. */
export function encodeHeader(h: CastHeader): string {
  const fields = [`"version":2`, `"width":${h.width}`, `"height":${h.height}`];
  if (h.timestamp !== undefined) {
    fields.push(`"timestamp":${Math.trunc(h.timestamp)}`);
  }
  if (h.idleTimeLimit !== undefined) {
    fields.push(`"idle_time_limit":${dartDouble(h.idleTimeLimit)}`);
  }
  if (h.command !== undefined) {
    fields.push(`"command":${jsonString(h.command)}`);
  }
  if (h.title !== undefined) {
    fields.push(`"title":${jsonString(h.title)}`);
  }
  const env = Object.entries(h.env ?? {});
  if (env.length > 0) {
    fields.push(`"env":{${env.map(([k, v]) => `${jsonString(k)}:${jsonString(v)}`).join(',')}}`);
  }
  return `{${fields.join(',')}}`;
}

/** An event's line, as `CastEvent.encode`: `[1.234567, "o", "text"]`. */
export function encodeEvent(e: CastEvent): string {
  return `[${e.time.toFixed(6)}, ${jsonString(e.code)}, ${jsonString(e.data)}]`;
}

type Json = Record<string, unknown>;

const isObject = (v: unknown): v is Json => typeof v === 'object' && v !== null && !Array.isArray(v);

/** The header of [json], as `CastHeader.fromJson`: throws for one that is not of version 2 with a width and a height. */
export function headerOf(json: unknown): CastHeader {
  if (!isObject(json)) {
    throw new Error('the header is no JSON object');
  }
  if (json.version !== 2) {
    throw new Error(`asciicast version ${json.version === undefined ? 'null' : String(json.version)}; this reads version 2`);
  }
  const { width, height, timestamp, idle_time_limit: limit, command, title, env } = json;
  if (!Number.isInteger(width) || !Number.isInteger(height) || (width as number) < 1 || (height as number) < 1) {
    throw new Error('the header has no width and height');
  }
  const strings: Record<string, string> = {};
  if (isObject(env)) {
    for (const [k, v] of Object.entries(env)) {
      if (typeof v === 'string') {
        strings[k] = v;
      }
    }
  }
  return {
    width: width as number,
    height: height as number,
    ...(typeof timestamp === 'number' ? { timestamp: Math.trunc(timestamp) } : {}),
    ...(typeof limit === 'number' ? { idleTimeLimit: limit } : {}),
    ...(typeof command === 'string' ? { command } : {}),
    ...(typeof title === 'string' ? { title } : {}),
    ...(Object.keys(strings).length > 0 ? { env: strings } : {}),
  };
}

/** Lines as Dart's LineSplitter cuts them: at `\n`, `\r\n` or `\r`. */
function lines(text: string): string[] {
  const out = text.split(/\r\n|\r|\n/);
  if (out.length > 0 && out[out.length - 1] === '') {
    out.pop();
  }
  return out;
}

function parseLine(line: string, index: number): unknown {
  try {
    return JSON.parse(line);
  } catch (e) {
    throw new Error(`line ${index + 1}: ${e instanceof Error ? e.message : String(e)}`);
  }
}

/** The recording in [text], as `Cast.parse`: throws for one that isn't asciicast v2, saying which line. */
export function parseCast(text: string): Cast {
  const all = lines(text);
  const first = all.findIndex((l) => l.trim() !== '');
  if (first < 0) {
    throw new Error('no header');
  }
  const header = headerOf(parseLine(all[first], first));
  const events: CastEvent[] = [];
  for (let i = first + 1; i < all.length; i++) {
    if (all[i].trim() === '') {
      continue;
    }
    const e = parseLine(all[i], i);
    if (Array.isArray(e) && e.length === 3 && typeof e[0] === 'number' && typeof e[1] === 'string' && typeof e[2] === 'string') {
      events.push({ time: e[0], code: e[1], data: e[2] });
    } else {
      throw new Error(`line ${i + 1}: no [time, code, data] event`);
    }
  }
  return { header, events };
}

/** The size of a resize event's data, `<width>x<height>`; undefined for another. */
export function sizeOf(e: CastEvent): { width: number; height: number } | undefined {
  if (e.code !== 'r') {
    return undefined;
  }
  const m = /^(\d+)x(\d+)$/.exec(e.data);
  return m ? { width: Number(m[1]), height: Number(m[2]) } : undefined;
}

/**
 * Writes a recording as it happens, as cast.dart's `CastWriter`: the header
 * at once, then each event, its time the real time since the start with
 * every pause longer than [idleLimit] seconds cut to it. Output and input
 * are decoded as UTF-8 a stream each (a character split between two
 * events put together, a malformed one U+FFFD); an empty one is no event.
 * Times are in microseconds, as Dart's Duration.
 */
export class CastWriter {
  private readonly output = new TextDecoder('utf-8');
  private readonly input = new TextDecoder('utf-8');
  private real = 0;
  private written = 0;
  /** How many events were written. */
  count = 0;

  constructor(
    private readonly write: (text: string) => void,
    header: CastHeader,
    /** The longest pause kept, in microseconds; undefined keeps each. */
    private readonly idleLimit?: number,
  ) {
    write(`${encodeHeader(header)}\n`);
  }

  /** The time written for the last event, in seconds. */
  get time(): number {
    return this.written / 1e6;
  }

  /** What the program wrote, at [at] µs since the start. */
  writeOutput(at: number, bytes: Uint8Array): void {
    this.event(at, 'o', this.output.decode(bytes, { stream: true }));
  }

  /** What was typed, at [at] µs. */
  writeInput(at: number, bytes: Uint8Array): void {
    this.event(at, 'i', this.input.decode(bytes, { stream: true }));
  }

  /** The terminal became [width] by [height] at [at] µs. */
  resize(at: number, width: number, height: number): void {
    this.event(at, 'r', `${width}x${height}`, true);
  }

  /** Writes what is left of a character cut off at the end, at [at] µs. */
  close(at: number): void {
    this.event(at, 'o', this.output.decode());
    this.event(at, 'i', this.input.decode());
  }

  private event(at: number, code: CastCode, data: string, always = false): void {
    if (data === '' && !always) {
      return;
    }
    const gap = at - this.real;
    const limit = this.idleLimit;
    this.written += limit === undefined || gap <= limit ? gap : limit;
    this.real = at;
    this.write(`${encodeEvent({ time: this.time, code, data })}\n`);
    this.count++;
  }
}

/**
 * A step of a recording played back: what the screen is sent, up to a
 * frame as `screenFrames` takes one (an output event that leaves no
 * synchronized update open), with the size it is resized to first.
 */
export interface CastStep {
  /** The time of its last event, in seconds, as the recording has it. */
  readonly time: number;
  readonly output: string;
  /** A resize before it, the last one since the step before. */
  readonly size?: { readonly width: number; readonly height: number };
  /** Its number among the frames, from 1; a step at the end that leaves an update open is none (0). */
  readonly frame: number;
}

/**
 * The steps of [cast]: its output events up to each frame, in the order
 * `screenFrames` shows them (a resize resizing, input and markers left out);
 * output after the last frame, inside an update never ended, is a step of
 * its own with no frame.
 */
export function castSteps(cast: Cast): CastStep[] {
  const reader = new SequenceReader(false);
  const steps: CastStep[] = [];
  let depth = 0;
  let output = '';
  let size: CastStep['size'];
  let time = 0;
  for (const e of cast.events) {
    const s = sizeOf(e);
    if (s) {
      size = s;
      continue;
    }
    if (e.code !== 'o') {
      continue;
    }
    output += e.data;
    time = e.time;
    for (const t of reader.read(new TextEncoder().encode(e.data))) {
      depth += syncChange(t);
    }
    if (depth > 0) {
      continue;
    }
    steps.push({ time, output, frame: steps.length + 1, ...(size ? { size } : {}) });
    output = '';
    size = undefined;
  }
  if (output !== '' || size) {
    steps.push({ time, output, frame: 0, ...(size ? { size } : {}) });
  }
  return steps;
}
