// The extension's asciicast (core/cast.ts) held to the golden of twk_dev's,
// packages/twk_dev/test/cast.golden.json, which twk_dev's
// cast_golden_test.dart holds cast.dart and cast_frames.dart to as well:
// the lines a writer writes, what a reader reads of a file or the message
// it throws, and the frames a recording shows, played here into a headless
// xterm.js as the replay terminal plays them (castSteps), against the
// screens twk_test's emulator showed. A change to the format made in the
// golden fails here until this side follows.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';

import { Terminal } from '@xterm/headless';

import { CastHeader, CastWriter, castSteps, encodeHeader, headerOf, parseCast } from '../../../core/cast';

/** From out/test/unit/core, where this runs compiled, to the repository's root. */
const goldenPath = path.resolve(__dirname, '../../../../../../packages/twk_dev/test/cast.golden.json');

type GoldenEvent =
  | { readonly at: number; readonly output: string }
  | { readonly at: number; readonly input: string }
  | { readonly at: number; readonly resize: readonly [number, number] }
  | { readonly at: number; readonly close: true };

interface Golden {
  readonly writes: readonly {
    readonly name: string;
    readonly header: unknown;
    readonly idleLimitMicros: number | null;
    readonly events: readonly GoldenEvent[];
    readonly lines: readonly string[];
  }[];
  readonly reads: readonly {
    readonly name: string;
    readonly lines: readonly string[];
    readonly error?: string;
    readonly header?: unknown;
    readonly events?: readonly (readonly [number, string, string])[];
    readonly duration?: number;
  }[];
  readonly frames: readonly {
    readonly name: string;
    readonly lines: readonly string[];
    readonly frames: readonly { number: number; time: number; width: number; height: number; lines: readonly string[] }[];
  }[];
}

const golden = JSON.parse(fs.readFileSync(goldenPath, 'utf8')) as Golden;

const bytes = (hex: string) => Buffer.from(hex, 'hex');

/** The header as cast.dart's toJson gives it. */
const json = (h: CastHeader): unknown => JSON.parse(encodeHeader(h));

/** Writes [data] to [term], settled once it parsed it. */
const write = (term: Terminal, data: string) => new Promise<void>((resolve) => term.write(data, resolve));

/** The rows [term] shows, without the blanks that end them. */
function rows(term: Terminal): string[] {
  const b = term.buffer.active;
  return Array.from({ length: term.rows }, (_, y) => b.getLine(b.viewportY + y)?.translateToString(true) ?? '');
}

describe('asciicast, held to the golden of twk_dev', () => {
  describe('the writer writes', () => {
    for (const c of golden.writes) {
      it(c.name, () => {
        let out = '';
        const writer = new CastWriter((t) => (out += t), headerOf(c.header), c.idleLimitMicros ?? undefined);
        for (const e of c.events) {
          if ('output' in e) {
            writer.writeOutput(e.at, bytes(e.output));
          } else if ('input' in e) {
            writer.writeInput(e.at, bytes(e.input));
          } else if ('resize' in e) {
            writer.resize(e.at, e.resize[0], e.resize[1]);
          } else {
            writer.close(e.at);
          }
        }
        assert.deepEqual(out.split('\n').slice(0, -1), c.lines);
        assert.ok(out.endsWith('\n'));
      });
    }
  });

  describe('the reader reads', () => {
    for (const c of golden.reads) {
      it(c.name, () => {
        const file = c.lines.join('\n');
        if (c.error !== undefined) {
          assert.throws(() => parseCast(file), { message: c.error });
          return;
        }
        const cast = parseCast(file);
        assert.deepEqual(json(cast.header), c.header);
        assert.deepEqual(
          cast.events.map((e) => [e.time, e.code, e.data]),
          c.events,
        );
        assert.equal(cast.events.at(-1)?.time ?? 0, c.duration);
      });
    }
  });

  describe('a recording shows the frames castFrames does', () => {
    for (const c of golden.frames) {
      it(c.name, async () => {
        const cast = parseCast(c.lines.join('\n'));
        const steps = castSteps(cast);
        const frames = steps.filter((s) => s.frame > 0);
        assert.deepEqual(
          frames.map((s) => [s.frame, s.time]),
          c.frames.map((f) => [f.number, f.time]),
        );
        const term = new Terminal({ cols: cast.header.width, rows: cast.header.height, allowProposedApi: true, convertEol: false });
        try {
          const shown: unknown[] = [];
          for (const s of steps) {
            if (s.size) {
              term.resize(s.size.width, s.size.height);
            }
            await write(term, s.output);
            if (s.frame > 0) {
              shown.push({ number: s.frame, time: s.time, width: term.cols, height: term.rows, lines: rows(term) });
            }
          }
          assert.deepEqual(shown, c.frames);
        } finally {
          term.dispose();
        }
      });
    }
  });
});
