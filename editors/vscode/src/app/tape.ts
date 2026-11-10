// Running a tape from the editor: `twk tape --check` (a test: nothing
// written, each statement told) and `twk tape` (the .cast and the SVGs the
// tape names), the project's directory the working directory (the tape's
// paths are the current directory's). What a run says goes to the log, and
// the line it failed or was wrong at becomes a diagnostic of the file. The
// tape is judged by twk tape only; this reads what it says.
import * as path from 'node:path';

import { ProcessStarter } from '../core/process';
import { CheckReport, parseCheck } from '../core/tape';
import { Log } from './ports';

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

export interface TapesDeps {
  readonly start: ProcessStarter;
  /** The command that is `twk`, as the person configured it (`dart run twk_dev:twk`). */
  command(): readonly string[];
  /** The directory of the nearest pubspec.yaml above [file], where there is one. */
  projectOf(file: string): string | undefined;
  readonly env: Readonly<Record<string, string | undefined>>;
  readonly diagnostics: DiagnosticsSink;
  readonly log: Log;
}

/** What a run of `twk tape` ended with. */
export interface RunReport extends CheckReport {
  /** The directory it ran in: the tape's outputs are relative to it. */
  readonly cwd: string;
}

export class Tapes {
  private readonly running = new Map<string, Promise<RunReport>>();

  constructor(private readonly deps: TapesDeps) {}

  /** `twk tape --check` over [file]. */
  check(file: string): Promise<RunReport> {
    return this.once(file, true);
  }

  /** `twk tape` over [file]. */
  run(file: string): Promise<RunReport> {
    return this.once(file, false);
  }

  /** Whether [file] is being run or checked now. */
  busy(file: string): boolean {
    return this.running.has(file);
  }

  // One run of a file at a time: its program, its outputs, its diagnostics
  private once(file: string, check: boolean): Promise<RunReport> {
    if (this.running.has(file)) {
      return Promise.reject(new Error(`${path.basename(file)} is being run already`));
    }
    const done = this.go(file, check).finally(() => this.running.delete(file));
    this.running.set(file, done);
    return done;
  }

  private async go(file: string, check: boolean): Promise<RunReport> {
    const command = this.deps.command();
    const log = this.deps.log;
    if (command.length === 0) {
      throw new Error('twk.tape.command is empty');
    }
    const cwd = this.deps.projectOf(file) ?? path.dirname(file);
    const tape = ['tape', ...(check ? ['--check'] : []), file];
    log.appendLine(`$ ${[...command, ...tape].join(' ')}   (in ${cwd})`);
    let output = '';
    const problems: Error[] = [];
    const process = this.deps.start(command[0], [...command.slice(1), ...tape], { cwd, env: this.deps.env });
    process.onOutput((t) => {
      output += t;
      log.append(t);
    });
    process.onError((e) => problems.push(e));
    const exit = await process.exited;
    if (output !== '' && !output.endsWith('\n')) {
      log.appendLine('');
    }
    const parsed = parseCheck(file, output, exit.code);
    const report: RunReport = {
      ...parsed,
      cwd,
      error: parsed.error ?? (problems.length > 0 ? { line: undefined, message: `cannot start ${command[0]}: ${problems[0].message}` } : undefined),
    };
    log.appendLine(`twk tape${check ? ' --check' : ''}: ${exit.signal ?? `exit ${exit.code}`}`);
    this.deps.diagnostics.set(file, diagnosticsOf(report));
    return report;
  }
}

/** The problems a report puts on lines of the tape: each failed statement, and the line stderr names. */
export function diagnosticsOf(report: CheckReport): TapeDiagnostic[] {
  const first = report.error?.message.split('\n')[0] ?? 'failed';
  const out: TapeDiagnostic[] = report.statements.filter((s) => !s.ok).map((s) => ({ line: s.line, message: first }));
  if (report.error?.line !== undefined && !out.some((d) => d.line === report.error?.line)) {
    out.push({ line: report.error.line, message: first });
  } else if (report.error && report.error.line === undefined && report.statements.length === 0) {
    // the tape could not be read, or its program not started: no line to blame but the first
    out.push({ line: 0, message: first });
  }
  return out;
}
