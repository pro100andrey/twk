// Running a tape from the editor: `twk tape --check` (a test: nothing
// written, each statement told) and `twk tape` (the .cast and the SVGs the
// tape names), the project's directory the working directory (the tape's
// paths are the current directory's). What a run says goes to the log, and
// the line it failed or was wrong at becomes a diagnostic of the file. The
// tape is judged by twk tape only; this reads what it says.
import * as path from 'node:path';

import { CheckReport, parseCheck } from '../core/tape';
import { TwkCommandDeps, runTwk } from './twk_command';

/** A problem at a line of a tape (from 0). */
export interface TapeDiagnostic {
  readonly line: number;
  readonly message: string;
}

/** Where the diagnostics of a tape file are shown. */
export interface DiagnosticsSink {
  set(file: string, diagnostics: readonly TapeDiagnostic[]): void;
  clear(file: string): void;
}

export interface TapesDeps extends TwkCommandDeps {
  /** The directory of the nearest pubspec.yaml above [file], where there is one. */
  projectOf(file: string): string | undefined;
  readonly diagnostics: DiagnosticsSink;
  /** The version of [file]'s text in the editor, changing with each edit; undefined where it is not open. */
  version(file: string): number | undefined;
  /** How long after SIGTERM before SIGKILL; see [TwkRunOptions.graceMs]. */
  readonly graceMs?: number;
}

/** What a run of `twk tape` ended with. */
export interface RunReport extends CheckReport {
  /** The directory it ran in: the tape's outputs are relative to it. */
  readonly cwd: string;
  /** Whether it was ended on request ([Tapes.run]'s `cancel`) and so did not finish. */
  readonly cancelled: boolean;
}

export class Tapes {
  private readonly running = new Map<string, Promise<RunReport>>();

  constructor(private readonly deps: TapesDeps) {}

  /** `twk tape --check` over [file]; [cancel] ends it (and what it started). */
  check(file: string, cancel?: AbortSignal): Promise<RunReport> {
    return this.once(file, true, cancel);
  }

  /** `twk tape` over [file]; [cancel] ends it (and what it started). */
  run(file: string, cancel?: AbortSignal): Promise<RunReport> {
    return this.once(file, false, cancel);
  }

  /** Whether [file] is being run or checked now. */
  busy(file: string): boolean {
    return this.running.has(file);
  }

  // One run of a file at a time: its program, its outputs, its diagnostics
  private once(file: string, check: boolean, cancel: AbortSignal | undefined): Promise<RunReport> {
    if (this.running.has(file)) {
      return Promise.reject(new Error(`${path.basename(file)} is being run already`));
    }
    const done = this.go(file, check, cancel).finally(() => this.running.delete(file));
    this.running.set(file, done);
    return done;
  }

  private async go(file: string, check: boolean, cancel: AbortSignal | undefined): Promise<RunReport> {
    const cwd = this.deps.projectOf(file) ?? path.dirname(file);
    // the diagnostics are of this text: if it changed meanwhile they are not set
    const version = this.deps.version(file);
    const run = await runTwk(this.deps, ['tape', ...(check ? ['--check'] : []), file], {
      cwd,
      label: check ? 'tape --check' : 'tape',
      echo: true,
      cancel,
      graceMs: this.deps.graceMs,
    });
    const parsed = parseCheck(file, run.output, run.exit.code);
    const report: RunReport = {
      ...parsed,
      cwd,
      cancelled: run.cancelled,
      error: parsed.error ?? (run.problems.length > 0 ? { line: undefined, message: `cannot start ${this.deps.command()[0]}: ${run.problems[0].message}` } : undefined),
    };
    if (this.deps.version(file) === version) {
      // a run that was ended says nothing of the tape
      if (run.cancelled) {
        this.deps.diagnostics.clear(file);
      } else {
        this.deps.diagnostics.set(file, diagnosticsOf(report));
      }
    }
    return report;
  }
}

/** The problems a report puts on lines of the tape: each failed statement, and the line stderr names. */
export function diagnosticsOf(report: CheckReport): TapeDiagnostic[] {
  const first = report.error?.message.split('\n')[0] ?? 'failed';
  const out: TapeDiagnostic[] = report.statements.filter((s) => !s.ok).map((s) => ({ line: s.line, message: first }));
  if (report.error?.line !== undefined && !out.some((d) => d.line === report.error?.line)) {
    out.push({ line: report.error.line, message: first });
  } else if (report.error && report.error.line === undefined && out.length === 0 && report.exit !== 0) {
    // the tape could not be read, or its program not started, or a file not written, after statements that passed or none: no line to blame but the first
    out.push({ line: 0, message: first });
  }
  return out;
}
