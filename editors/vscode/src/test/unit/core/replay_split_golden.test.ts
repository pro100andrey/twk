// The extension's keys of a recording (core/replay_input.ts) held to the
// golden of twk_dev's `twk record --replay`,
// packages/twk_dev/test/replay_split.golden.json, which twk_dev's
// replay_split_golden_test.dart holds lib/src/replay.dart to as well: the
// same recording types the same keys in both. A change to an answer made in
// the golden fails here until this side follows.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';

import { parseCast } from '../../../core/cast';
import { replaySteps } from '../../../core/replay_input';

/** From out/test/unit/core, where this runs compiled, to the repository's root. */
const goldenPath = path.resolve(__dirname, '../../../../../../packages/twk_dev/test/replay_split.golden.json');

interface Golden {
  readonly cases: readonly {
    readonly name: string;
    readonly events: readonly [number, string, string][];
    readonly steps: readonly { time: number; keys: string; reacts: boolean }[];
  }[];
}

const golden = JSON.parse(fs.readFileSync(goldenPath, 'utf8')) as Golden;

describe('the keys of a recording held to the golden', () => {
  for (const c of golden.cases) {
    it(c.name, () => {
      const cast = parseCast([JSON.stringify({ version: 2, width: 80, height: 24 }), ...c.events.map((e) => JSON.stringify(e))].join('\n'));
      assert.deepEqual(
        replaySteps(cast).map((s) => ({ time: s.time, keys: s.keys, reacts: s.reacts })),
        c.steps,
      );
    });
  }
});
