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
  /** Sends it [signal]. */
  signal(signal: 'SIGTERM' | 'SIGKILL'): void;
}

export interface StartOptions {
  readonly cwd: string;
  /** The whole environment of the process. */
  readonly env: Readonly<Record<string, string | undefined>>;
}

/** Starts [command] with [args]: node's `spawn`, or a fake in a test. */
export type ProcessStarter = (command: string, args: readonly string[], options: StartOptions) => AppProcess;

/** A [ProcessStarter] over node's child_process. */
export const startNodeProcess: ProcessStarter = (command, args, options) => {
  const child = spawn(command, [...args], { cwd: options.cwd, stdio: ['pipe', 'pipe', 'pipe'], env: { ...options.env } });
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
    signal(signal) {
      child.kill(signal);
    },
  };
};
