// Running `twk` (whatever `twk.command` says it is) for the editor: the
// tape's Run and Check, and the doctor of the terminal report. One place
// starts it, collects what it says, and ends it: on a deadline or when asked
// to, the whole group it started (`dart run` starts the VM as a child), by
// SIGTERM and, if that is not heeded, SIGKILL. Once the leader has exited the
// group is polled; the moment it is empty the SIGKILL is dropped (an emptied
// group's id can be a new group's), and it is sent when the grace is over to
// a group the last poll found alive. What a signal may do after the leader's
// exit on Windows is decided in core/process.ts, not here.
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
  /** How often the group of a leader that exited is looked at; 50 ms by default. */
  readonly pollMs?: number;
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
      stopWatching();
      if (!process.hasExited || groupLives) {
        process.signal('SIGKILL');
      }
    }, options.graceMs ?? 3000);
    // the timers outlive the run (they end the group after the leader), and hold nothing up
    escalation.unref();
  };
  // after the leader's exit: whether the last look found its group alive
  let groupLives = false;
  let watch: NodeJS.Timeout | undefined;
  const stopWatching = () => {
    clearInterval(watch);
    watch = undefined;
  };
  const look = () => {
    groupLives = process.groupAlive();
    if (!groupLives) {
      // nothing left to end, and its id may be someone else's from now on
      stopWatching();
      clearTimeout(escalation);
    }
  };
  void process.exited.then(() => {
    if (escalation === undefined) {
      return;
    }
    look();
    if (groupLives) {
      watch = setInterval(look, options.pollMs ?? 50);
      watch.unref();
    }
  });
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
