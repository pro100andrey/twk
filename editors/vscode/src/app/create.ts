// A new project and the files for coding agents: `twk create` and
// `twk agents`, run as every other twk command of the editor is
// (twk_command.ts). They have no logic of their own: the templates are what
// `twk create --list` says, the files are what the CLI writes, and what it
// wrote, removed and left (a file the person changed) is what it prints.
//
// Where twk_dev is run from: `twk.command`, `dart run twk_dev:twk` by
// default, which needs a pubspec.yaml that depends on twk_dev in the
// directory it runs in. A folder without one (a new project is made in a
// folder with none) cannot run it, so when `twk.command` is that default
// and the folder has no twk_dev (read from its package_config.json or
// pubspec.yaml before anything is run; dart's words about it are only a last
// hint, for a folder whose files say nothing), the command is run as
// `dart pub global run twk_dev:twk`, the package activated on the machine.
// Where that is not there either, the result says `missing`, and the
// editor offers the person to activate it: nothing is installed by this.
import { TwkCommandDeps, TwkRun, runTwk } from './twk_command';

export interface CreateDeps extends TwkCommandDeps {
  /** What `twk.command` is when the person never set it. */
  readonly defaultCommand: readonly string[];
  /** The command for a folder that has no twk_dev of its own: the globally activated package. */
  readonly globalCommand: readonly string[];
  /** How long after SIGTERM before SIGKILL; see [TwkRunOptions.graceMs]. */
  readonly graceMs?: number;
  /** Whether the folder can run twk_dev itself; undefined where that is not known (the output of the run then tells). */
  hasTwkDev?(cwd: string): boolean | undefined;
}

/** A template of `twk create`, as `--list` names it. */
export interface TwkTemplate {
  readonly name: string;
  readonly description: string;
}

/** The files for agents `twk create --agents` takes; `none` is no choice. */
export interface AgentsChoice {
  readonly flag: 'agents-md' | 'skill';
  readonly label: string;
  readonly description: string;
}

export const agentsChoices: readonly AgentsChoice[] = [
  { flag: 'skill', label: 'The twk skill', description: '.agents/skills/twk and .claude/skills/twk' },
  { flag: 'agents-md', label: 'AGENTS.md', description: 'a block that points at the skill' },
];

/** What a run of `twk create` or `twk agents` came to. */
export interface TwkOutcome {
  /** Why it did not succeed; undefined where it did. */
  readonly error?: string;
  /** Everything it said, without empty lines. */
  readonly lines: readonly string[];
  readonly cancelled: boolean;
  /** twk_dev is not there to run (neither in the folder nor activated on the machine). */
  readonly missing: boolean;
}

export interface CreateOutcome extends TwkOutcome {
  /** The project's directory as given; where it was made. */
  readonly dir: string;
}

export interface AgentsOutcome extends TwkOutcome {
  /** The line that says what was done. */
  readonly summary?: string;
  /** The lines that name files left as they are (the person's own or changed). */
  readonly left: readonly string[];
}

// what `dart run` says in a folder without twk_dev or without a pubspec, and `dart pub global run` of a package not activated
const NO_TWK_DEV = /Could not find package `twk_dev`|Found no `pubspec\.yaml`|No active package twk_dev/;

const sameCommand = (a: readonly string[], b: readonly string[]) => a.length === b.length && a.every((w, i) => w === b[i]);

export class Creator {
  constructor(private readonly deps: CreateDeps) {}

  /** The templates `twk create --list` names; throws with its words where it says none. */
  async templates(cwd: string, cancel?: AbortSignal): Promise<TwkTemplate[]> {
    const { run, missing } = await this.run(['create', '--list'], { cwd, label: 'create --list', cancel });
    const templates = run.output
      .split(/\r?\n/)
      .map((l) => /^(\S+) {2,}(.+?)\s*$/.exec(l))
      .filter((m) => m !== null)
      .map((m) => ({ name: m[1], description: m[2] }));
    if (run.exit.code !== 0 || templates.length === 0) {
      throw new Error(missing ? 'twk_dev is not available' : this.why(run));
    }
    return templates;
  }

  /** `twk create <dir> --template <template> --agents <agents>`, run in [cwd] (a directory that exists). */
  async create(request: { dir: string; template: string; agents: readonly string[] }, cwd: string, cancel?: AbortSignal): Promise<CreateOutcome> {
    const agents = request.agents.length === 0 ? 'none' : request.agents.join(',');
    const { run, missing } = await this.run(['create', request.dir, `--template=${request.template}`, `--agents=${agents}`], {
      cwd,
      label: 'create',
      cancel,
      timeoutMs: 120_000,
    });
    return { dir: request.dir, ...this.outcome(run, missing) };
  }

  /** `twk agents` in [project]. */
  async agents(project: string, cancel?: AbortSignal): Promise<AgentsOutcome> {
    const { run, missing } = await this.run(['agents'], { cwd: project, label: 'agents', cancel, timeoutMs: 120_000 });
    const outcome = this.outcome(run, missing);
    return {
      ...outcome,
      summary: outcome.error === undefined ? outcome.lines.find((l) => l.startsWith('twk agents')) : undefined,
      left: outcome.lines.filter((l) => l.startsWith('Left as they are')),
    };
  }

  private outcome(run: TwkRun, missing: boolean): TwkOutcome {
    const lines = run.output.split(/\r?\n/).filter((l) => l.trim() !== '');
    const ok = run.exit.code === 0 && run.problems.length === 0;
    return { lines, cancelled: run.cancelled, missing, error: ok ? undefined : run.cancelled ? 'cancelled' : missing ? 'twk_dev is not available' : this.why(run) };
  }

  private why(run: TwkRun): string {
    if (run.problems[0]) {
      return `cannot start ${this.deps.command()[0]}: ${run.problems[0].message}`;
    }
    if (run.timedOut) {
      return 'timed out';
    }
    return run.output.trim().split(/\r?\n/).filter((l) => l.trim() !== '').join('\n') || `exit ${run.exit.signal ?? run.exit.code}`;
  }

  private async run(args: readonly string[], options: { cwd: string; label: string; cancel?: AbortSignal; timeoutMs?: number }): Promise<{ run: TwkRun; missing: boolean }> {
    const base = { ...options, graceMs: this.deps.graceMs, echo: true };
    const global = (): Promise<{ run: TwkRun; missing: boolean }> => this.runGlobal(args, options, base);
    if (this.canFallBack() && this.deps.hasTwkDev?.(options.cwd) === false) {
      return global();
    }
    const first = await runTwk(this.deps, args, base);
    const lacking = (r: TwkRun) => r.exit.code !== 0 && !r.cancelled && NO_TWK_DEV.test(r.output);
    if (!lacking(first) || !this.canFallBack()) {
      return { run: first, missing: lacking(first) };
    }
    return global();
  }

  private async runGlobal(args: readonly string[], options: { label: string }, base: object): Promise<{ run: TwkRun; missing: boolean }> {
    const run = await runTwk({ ...this.deps, command: () => this.deps.globalCommand }, args, { ...(base as { cwd: string; label: string }), label: `${options.label} (global twk_dev)` });
    return { run, missing: run.exit.code !== 0 && !run.cancelled && NO_TWK_DEV.test(run.output) };
  }

  private canFallBack(): boolean {
    return sameCommand(this.deps.command(), this.deps.defaultCommand);
  }
}
