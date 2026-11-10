// A test made of a recording: `twk test-from-cast <file.cast>`, run in the
// recording's project (the nearest pubspec.yaml, else its directory) as
// every other twk command of the editor is (twk_command.ts). The test is
// twk_dev's to write, from the recording's markers or, where it has none,
// its last screen; this runs it and reads which files it wrote.
import * as path from 'node:path';

import { TwkCommandDeps, runTwk } from './twk_command';

export interface CastTestsDeps extends TwkCommandDeps {
  /** The directory of the nearest pubspec.yaml above [file], where there is one. */
  projectOf(file: string): string | undefined;
  /** How long after SIGTERM before SIGKILL; see [TwkRunOptions.graceMs]. */
  readonly graceMs?: number;
}

/** What `twk test-from-cast` came to. */
export interface CastTestResult {
  /** The test it wrote, absolute; undefined where it wrote none. */
  readonly test?: string;
  /** The recording beside the test (a copy of it, or the file itself). */
  readonly cast?: string;
  /** What it said besides that (the reasons of a failure, the notes of a recording it could not check whole). */
  readonly said: string;
  /** Why no test was written. */
  readonly error?: string;
  readonly cancelled: boolean;
}

// twk writes `wrote <test> and <cast>` (paths relative to the project, as p.relative prints them); the test ends in _test.dart, the recording in .cast, so a ' and ' in a name does not split it
const WROTE = /^wrote (.+?_test\.dart) and (.+\.cast)$/;

export class CastTests {
  constructor(private readonly deps: CastTestsDeps) {}

  /** Makes a test of [file]; [cancel] ends the command and what it started. */
  async create(file: string, cancel?: AbortSignal): Promise<CastTestResult> {
    const cwd = this.deps.projectOf(file) ?? path.dirname(file);
    const run = await runTwk(this.deps, ['test-from-cast', file], { cwd, label: 'test-from-cast', echo: true, cancel, graceMs: this.deps.graceMs, timeoutMs: 120_000 });
    const lines = run.output.split(/\r?\n/).filter((l) => l.trim() !== '');
    // `wrote <test> and <cast>`, both relative to the project
    const wrote = lines.map((l) => WROTE.exec(l)).find((m) => m !== null);
    const said = lines.filter((l) => !WROTE.test(l)).join('\n');
    if (run.exit.code === 0 && wrote) {
      return { test: path.resolve(cwd, wrote[1]), cast: path.resolve(cwd, wrote[2]), said, cancelled: false };
    }
    const why = run.problems[0] ? `cannot start ${this.deps.command()[0]}: ${run.problems[0].message}` : run.timedOut ? 'timed out' : said || `exit ${run.exit.signal ?? run.exit.code}`;
    return { said, error: why, cancelled: run.cancelled };
  }
}
