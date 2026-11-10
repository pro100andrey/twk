// The project part of the terminal report: `twk doctor --json` run in the
// project (its nearest pubspec.yaml), the working directory the command
// finds it from. Exit 1 is a report too (the versions disagree); what it
// says is read by core/report.ts, judged by twk doctor only.
import { ProcessStarter } from '../core/process';
import { ProjectResult, parseDoctor } from '../core/report';
import { Log } from './ports';

export interface DoctorDeps {
  readonly start: ProcessStarter;
  /** The command that is `twk`, as the person configured it (`dart run twk_dev:twk`). */
  command(): readonly string[];
  readonly env: Readonly<Record<string, string | undefined>>;
  readonly log: Log;
  /** How long `twk doctor` may take before it is ended. */
  readonly timeoutMs: number;
}

/** Asks `twk doctor` about a project. */
export class Doctor {
  constructor(private readonly deps: DoctorDeps) {}

  /** The project part of the report for the project in [project]; failed, saying why, where `twk doctor` could not be run or read. */
  async project(project: string): Promise<ProjectResult> {
    const command = this.deps.command();
    const log = this.deps.log;
    if (command.length === 0) {
      return { kind: 'failed', message: 'twk.tape.command is empty' };
    }
    const args = [...command.slice(1), 'doctor', '--json', '-C', project];
    log.appendLine(`$ ${[...command, 'doctor', '--json', '-C', project].join(' ')}   (in ${project})`);
    let output = '';
    const problems: Error[] = [];
    const process = this.deps.start(command[0], args, { cwd: project, env: this.deps.env });
    process.onOutput((t) => (output += t));
    process.onError((e) => problems.push(e));
    const timer = setTimeout(() => process.signal('SIGTERM'), this.deps.timeoutMs);
    const exit = await process.exited.finally(() => clearTimeout(timer));
    if (problems.length > 0) {
      return { kind: 'failed', message: `cannot start ${command[0]}: ${problems[0].message}` };
    }
    log.appendLine(`twk doctor: ${exit.signal ?? `exit ${exit.code}`}`);
    const parsed = parseDoctor(output);
    if (parsed.kind === 'failed' && exit.signal !== null) {
      return { kind: 'failed', message: `twk doctor did not finish in ${this.deps.timeoutMs / 1000} s (${exit.signal})` };
    }
    return parsed;
  }
}
