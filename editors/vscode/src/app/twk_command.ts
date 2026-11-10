// Running `twk` (whatever `twk.command` says it is) for the editor: the
// tape's Run and Check, and the doctor of the terminal report. One place
// starts it, collects what it says, and ends it: on a deadline or when asked
// to, the whole group it started (`dart run` starts the VM as a child), by
// SIGTERM and, if that is not heeded, SIGKILL. The SIGKILL is sent after the
// grace even where the leader exited on the SIGTERM, to the group on POSIX
// (a group id is not reused while any member lives, so it reaches only our
// group or none); on Windows only while the leader lives, as taskkill takes
// the pid alone, which may be someone else's once it is gone, so a child of a
// leader that exited there stays.
import { Exit, ProcessStarter } from '../core/process';
import { Log } from './ports';

export interface TwkCommandDeps {
  readonly start: ProcessStarter;
  /** The command that is `twk`, as the person configured it (`dart run twk_dev:twk`). */
  command(): readonly string[];
  readonly env: Readonly<Record<string, string | undefined>>;
  readonly log: Log;
}

export interface TwkRunOptions {
  /** The directory it runs in. */
  readonly cwd: string;
  /** What the log calls it in its closing line: `twk <label>: exit 0`. */
  readonly label: string;
  /** Ends the run after this long. */
  readonly timeoutMs?: number;
  /** Ends the run when it aborts. */
  readonly cancel?: AbortSignal;
  /** Whether what it writes goes to the log as it comes. */
  readonly echo?: boolean;
  /** How long after SIGTERM before SIGKILL; 3 s by default. */
  readonly graceMs?: number;
}

/** What a run of twk came to. */
export interface TwkRun {
  readonly exit: Exit;
  /** Everything it wrote, stdout and stderr as they came. */
  readonly output: string;
  /** What went wrong starting or talking to it (the command does not exist). */
  readonly problems: readonly Error[];
  readonly timedOut: boolean;
  readonly cancelled: boolean;
}

/** Runs `twk <args>` in [options].cwd; throws only where the command is empty. */
export async function runTwk(deps: TwkCommandDeps, args: readonly string[], options: TwkRunOptions): Promise<TwkRun> {
  const command = deps.command();
  if (command.length === 0) {
    throw new Error('twk.command is empty');
  }
  const log = deps.log;
  log.appendLine(`$ ${[...command, ...args].join(' ')}   (in ${options.cwd})`);
  let output = '';
  const problems: Error[] = [];
  const process = deps.start(command[0], [...command.slice(1), ...args], { cwd: options.cwd, env: deps.env, group: true });
  process.onOutput((t) => {
    output += t;
    if (options.echo) {
      log.append(t);
    }
  });
  process.onError((e) => problems.push(e));

  let timedOut = false;
  let cancelled = false;
  let escalation: NodeJS.Timeout | undefined;
  const end = () => {
    if (process.hasExited || escalation !== undefined) {
      return;
    }
    process.signal('SIGTERM');
    escalation = setTimeout(() => {
      if (!process.hasExited || globalThis.process.platform !== 'win32') {
        process.signal('SIGKILL');
      }
    }, options.graceMs ?? 3000);
    // the timer outlives the run (it ends the group after the leader), and holds nothing up
    escalation.unref();
  };
  const timer = options.timeoutMs === undefined ? undefined : setTimeout(() => ((timedOut = true), end()), options.timeoutMs);
  const onAbort = () => ((cancelled = true), end());
  if (options.cancel?.aborted) {
    onAbort();
  } else {
    options.cancel?.addEventListener('abort', onAbort);
  }
  let exit: Exit;
  try {
    exit = await process.exited;
  } finally {
    clearTimeout(timer);
    options.cancel?.removeEventListener('abort', onAbort);
  }
  if (options.echo && output !== '' && !output.endsWith('\n')) {
    log.appendLine('');
  }
  log.appendLine(`twk ${options.label}: ${exit.signal ?? `exit ${exit.code}`}`);
  return { exit, output, problems, timedOut, cancelled };
}
