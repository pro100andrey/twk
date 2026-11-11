// The project part of the terminal report: `twk doctor --json` run in the
// project (its nearest pubspec.yaml), the working directory the command
// finds it from. Exit 1 is a report too (the versions disagree); what it
// says is read by core/report.ts, judged by twk doctor only.
import { ProjectResult, parseDoctor } from '../core/report';
import { TwkCommandDeps, runTwk } from './twk_command';

export interface DoctorDeps extends TwkCommandDeps {
  /** How long `twk doctor` may take before it is ended. */
  readonly timeoutMs: number;
  /** How long after SIGTERM before SIGKILL; see [TwkRunOptions.graceMs]. */
  readonly graceMs?: number;
}

/** Asks `twk doctor` about a project. */
export class Doctor {
  private running: AbortController | undefined;

  constructor(private readonly deps: DoctorDeps) {}

  /**
   * The project part of the report for the project in [project], as the
   * latest ask: one that is still running is ended, and its answer is
   * undefined, so a slower older ask never takes the place of a newer one.
   * No project (undefined) is `none`, and ends the one running too.
   */
  async latest(project: string | undefined): Promise<ProjectResult | undefined> {
    this.running?.abort();
    const mine = new AbortController();
    if (project === undefined) {
      this.running = undefined;
      return { kind: 'none' };
    }
    this.running = mine;
    try {
      const result = await this.project(project, mine.signal);
      return mine.signal.aborted ? undefined : result;
    } finally {
      if (this.running === mine) {
        this.running = undefined;
      }
    }
  }

  /** The project part of the report for the project in [project]; failed, saying why, where `twk doctor` could not be run or read. */
  async project(project: string, cancel?: AbortSignal): Promise<ProjectResult> {
    let run;
    try {
      run = await runTwk(this.deps, ['doctor', '--json', '-C', project], { cwd: project, label: 'doctor', timeoutMs: this.deps.timeoutMs, graceMs: this.deps.graceMs, cancel });
    } catch (e) {
      return { kind: 'failed', message: e instanceof Error ? e.message : String(e) };
    }
    if (run.problems.length > 0) {
      return { kind: 'failed', message: `cannot start ${this.deps.command()[0]}: ${run.problems[0].message}` };
    }
    if (run.cancelled) {
      return { kind: 'failed', message: 'twk doctor was cancelled' };
    }
    const parsed = parseDoctor(run.output);
    if (parsed.kind === 'failed' && run.timedOut) {
      return { kind: 'failed', message: `twk doctor did not finish in ${this.deps.timeoutMs / 1000} s (${run.exit.signal ?? `exit ${run.exit.code}`})` };
    }
    return parsed;
  }
}
