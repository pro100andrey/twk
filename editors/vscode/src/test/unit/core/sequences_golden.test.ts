// The extension's sequence names (core/sequences.ts) and log (core/seqlog.ts)
// held to the golden of twk_dev's `twk decode`,
// packages/twk_dev/test/decode.golden.json, which twk_dev's
// decode_golden_test.dart holds lib/src/decode.dart to as well: bytes cut
// into tokens and named, for what the app writes and for what the terminal
// sends, and bytes into the entries and frames of a log. A change to a name
// made in the golden fails here until this side follows.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';

import { SequenceLog } from '../../../core/seqlog';
import { SequenceReader, describeInput, describeOutput } from '../../../core/sequences';

/** From out/test/unit/core, where this runs compiled, to the repository's root. */
const goldenPath = path.resolve(__dirname, '../../../../../../packages/twk_dev/test/decode.golden.json');

interface Golden {
  readonly reads: readonly {
    readonly name: string;
    readonly direction: 'out' | 'in';
    readonly chunks: readonly string[];
    readonly tokens: readonly { kind: string; raw: string; name: string }[];
    readonly waiting?: string;
  }[];
  readonly logs: readonly {
    readonly name: string;
    readonly events: readonly { time: number; direction: 'out' | 'in' | 'note' | 'end'; bytes?: string; note?: string }[];
    readonly entries: readonly unknown[];
  }[];
}

const golden = JSON.parse(fs.readFileSync(goldenPath, 'utf8')) as Golden;

const bytesOf = (hex: string): Uint8Array => Uint8Array.from(hex.match(/../g) ?? [], (h) => Number.parseInt(h, 16));
const hexOf = (latin1: string): string => [...latin1].map((c) => c.charCodeAt(0).toString(16).padStart(2, '0')).join('');

describe('the sequence names held to the golden', () => {
  for (const c of golden.reads) {
    it(`reads: ${c.name}`, () => {
      const tokens: { kind: string; raw: string; name: string }[] = [];
      const reader = new SequenceReader(c.direction === 'in');
      for (const chunk of c.chunks) {
        // the terminal's reads are whole each, as the log reads them
        for (const t of (c.direction === 'in' ? new SequenceReader(true) : reader).read(bytesOf(chunk))) {
          tokens.push({ kind: t.kind, raw: hexOf(t.raw), name: c.direction === 'in' ? describeInput(t) : describeOutput(t) });
        }
      }
      assert.deepEqual(tokens, c.tokens);
      assert.equal(c.direction === 'in' ? '' : hexOf(reader.waiting), c.waiting ?? '');
    });
  }

  for (const c of golden.logs) {
    it(`log: ${c.name}`, () => {
      const log = new SequenceLog();
      for (const e of c.events) {
        if (e.direction === 'out') {
          log.output(e.time, bytesOf(e.bytes ?? ''));
        } else if (e.direction === 'in') {
          log.input(e.time, bytesOf(e.bytes ?? ''));
        } else if (e.direction === 'end') {
          log.finish(e.time);
        } else {
          log.note(e.time, e.note ?? '');
        }
      }
      assert.deepEqual(JSON.parse(JSON.stringify(log.all())), c.entries);
    });
  }
});
