// A process an app runs in, as the run (runner.ts) needs it: started with
// pipes, its output as text, ended by signal through its own handle. The
// node implementation is `startNodeProcess`; a test passes a fake.
import { spawn } from 'node:child_process';
import { StringDecoder } from 'node:string_decoder';

/** How a process ended: its exit code, or the signal that ended it. */
export interface Exit {
  readonly code: number | null;
  readonly signal: string | null;
}

/** A process started with stdin, stdout and stderr pipes. */
export interface AppProcess {
  readonly pid: number | undefined;
  /** Whether it has ended. */
  readonly hasExited: boolean;
  /** Settles once it has ended. */
  readonly exited: Promise<Exit>;
  /** [f] gets what it writes to stdout and stderr, as text. */
  onOutput(f: (text: string) => void): void;
  /** [f] gets what went wrong starting or talking to it. */
  onError(f: (e: Error) => void): void;
  /** Writes [text] to its stdin. */
  write(text: string): void;
  /**
   * Whether its group still has a member, once the process itself has ended
   * (POSIX: `kill(-pid, 0)`). False where there is no group to ask about: not
   * started as one, or Windows, where nothing is signalled after the exit.
   */
  groupAlive(): boolean;
  /** Sends it [signal]. */
  signal(signal: 'SIGTERM' | 'SIGKILL'): void;
}

export interface StartOptions {
  readonly cwd: string;
  /** The whole environment of the process. */
  readonly env: Readonly<Record<string, string | undefined>>;
  /**
   * Whether the process and what it starts are one group: [AppProcess.signal]
   * then reaches them all (a process group on POSIX, `taskkill /T` on
   * Windows). `dart run` starts the VM as a child, which a signal to `dart`
   * alone leaves running.
   */
  readonly group?: boolean;
}

/** Starts [command] with [args]: node's `spawn`, or a fake in a test. */
export type ProcessStarter = (command: string, args: readonly string[], options: StartOptions) => AppProcess;

/** A [ProcessStarter] over node's child_process. */
export const startNodeProcess: ProcessStarter = (command, args, options) => {
  // its own process group on POSIX, so that a signal can reach its children too
  const posixGroup = options.group === true && process.platform !== 'win32';
  const child = spawn(command, [...args], { cwd: options.cwd, stdio: ['pipe', 'pipe', 'pipe'], env: { ...options.env }, detached: posixGroup });
  let failed = false;
  const exited = new Promise<Exit>((resolve) => {
    child.on('exit', (code, signal) => resolve({ code, signal }));
    // a process that could not be started (ENOENT, EACCES) never exits
    child.on('error', (e: NodeJS.ErrnoException) => {
      if (child.pid === undefined) {
        failed = true;
        resolve({ code: typeof e.errno === 'number' ? e.errno : -1, signal: null });
      }
    });
  });
  // a stream's error unlistened to would end the extension host
  child.stdin.on('error', () => {});
  const decoders = [new StringDecoder('utf8'), new StringDecoder('utf8')];
  return {
    get pid() {
      return child.pid;
    },
    get hasExited() {
      return failed || child.exitCode !== null || child.signalCode !== null;
    },
    exited,
    onOutput(f) {
      // a character cut in two by the reads is kept until its last byte came
      child.stdout.on('data', (b: Buffer) => f(decoders[0].write(b)));
      child.stderr.on('data', (b: Buffer) => f(decoders[1].write(b)));
    },
    onError(f) {
      child.on('error', f);
    },
    write(text) {
      child.stdin.write(text);
    },
    groupAlive() {
      if (!posixGroup || child.pid === undefined) {
        return false;
      }
      try {
        process.kill(-child.pid, 0);
        return true;
      } catch {
        // ESRCH: no member left; EPERM: a group of someone else's, not ours
        return false;
      }
    },
    signal(signal) {
      if (options.group === true && process.platform === 'win32' && this.hasExited) {
        // the pid may be someone else's now
        return;
      }
      if (options.group !== true || child.pid === undefined) {
        child.kill(signal);
      } else if (process.platform === 'win32') {
        // the whole tree; taskkill ends them hard whatever the signal
        spawn('taskkill', ['/pid', String(child.pid), '/T', '/F'], { stdio: 'ignore' }).on('error', () => child.kill(signal));
      } else {
        try {
          process.kill(-child.pid, signal);
        } catch {
          // ESRCH: the group is gone already; nothing else to signal
        }
      }
    },
  };
};
