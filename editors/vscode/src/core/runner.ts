// Runs a Dart file with hot reload and hot restart: `dart run` with the VM
// service on (its address written to a file of the run's own, nothing said
// on the app's output), and stdin, stdout and stderr pipes, so that a twk
// app takes the project's twk terminal (twk's Terminal.open finds the
// shell's address file when stdin is no tty). A reload goes over the VM
// service ([HotApp]); a restart ends the app this started, through its
// ChildProcess, and starts it again, the new one connecting to the same
// terminal. What `twk run` (twk_dev's HotRunner) does, without twk_dev:
// any project's apps run so, and the extension sees how each reload
// ended. No vscode import: its tests run under plain node. The process
// and the VM service connection come from the caller ([HotRunDeps]).
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { pathToFileURL } from 'node:url';

import { Clock, Disposable } from './events';
import { HotApp, HotStatus } from './hot';
import { AppProcess, ProcessStarter } from './process';
import { Vm } from './vm';

/** What a run starts its app with and connects to its VM service through. */
export interface HotRunDeps {
  readonly startProcess: ProcessStarter;
  readonly connectVm: (uri: string) => Promise<Vm>;
  /** The environment the app's is made of, [HotRunOptions.env] added. */
  readonly env: Readonly<Record<string, string | undefined>>;
  /** What the wait for the app's VM service is bounded by. */
  readonly clock: Clock;
}

export interface HotRunOptions {
  /** The file of the app's `main`. */
  file: string;
  /** The directory the app runs in. */
  cwd: string;
  /** The `dart` command; `dart` on the PATH by default. */
  dart?: string;
  /** Added to the extension's environment for the app. */
  env?: Record<string, string>;
  /** What the app writes to its stdout and stderr, and what the run says. */
  onOutput(text: string): void;
  onStatus(s: HotStatus): void;
  /** The app's VM service connected ([HotApp]), or the app went away (undefined): each app a restart starts again is a new one. */
  onApp?(app: HotApp | undefined): void;
}

/** How long an app is given to end on SIGTERM before it is killed. */
export const patience = 5000;

/**
 * How long a run waits for the app to name its VM service (the service
 * info file) before it goes on without hot reload: `dart run` compiles
 * the app first, which takes a while for a big one.
 */
export const serviceInfoPatience = 120000;

export class HotRun {
  /** The app running, or starting: one at a time. */
  process: AppProcess | undefined;
  /** The app's VM service, once connected. */
  hot: HotApp | undefined;
  private readonly dir = fs.mkdtempSync(path.join(os.tmpdir(), 'twk_vscode_run_'));
  private restarting = false;
  private stopping = false;
  private hotReady: Promise<HotApp | undefined> = Promise.resolve(undefined);
  /** Settles once the run has ended — the app ended by itself, or [stop] — with the app's exit code or signal. */
  readonly ended: Promise<number | string>;
  private end!: (r: number | string) => void;

  private constructor(
    private readonly options: HotRunOptions,
    private readonly deps: HotRunDeps,
  ) {
    this.ended = new Promise((resolve) => (this.end = resolve));
    void this.ended.then(() => fs.rmSync(this.dir, { recursive: true, force: true }));
  }

  static start(options: HotRunOptions, deps: HotRunDeps): HotRun {
    const run = new HotRun(options, deps);
    run.launch();
    return run;
  }

  /** Reloads the app's sources; the app keeps its state. */
  async reload(): Promise<HotStatus> {
    const hot = await this.hotReady;
    return hot ? hot.reload() : { state: 'ended' };
  }

  /**
   * Ends the app this started (SIGTERM, then SIGKILL after [patience]) and
   * starts it again; settles once the new one runs.
   */
  async restart(): Promise<void> {
    const app = this.process;
    if (!app || this.restarting || this.stopping) {
      return;
    }
    this.restarting = true;
    this.hot?.restarting();
    this.options.onStatus({ state: 'restarting' });
    await HotRun.kill(app);
  }

  /** Has the app paint all of itself again (`ext.twk.reassemble`): its terminal came back empty. */
  async redraw(): Promise<void> {
    await (await this.hotReady)?.redraw();
  }

  /** Ends the app and the run. */
  async stop(): Promise<void> {
    this.stopping = true;
    if (this.process) {
      await HotRun.kill(this.process);
    }
    await this.ended;
  }

  /** Ends [app], through its handle: SIGTERM, which has a twk app put its terminal back, then SIGKILL. */
  static async kill(app: AppProcess): Promise<void> {
    if (app.hasExited) {
      return;
    }
    app.signal('SIGTERM');
    const timer = setTimeout(() => app.signal('SIGKILL'), patience);
    await app.exited;
    clearTimeout(timer);
  }

  private launch(): void {
    const info = path.join(this.dir, 'service.json');
    fs.rmSync(info, { force: true });
    const { file, cwd, onOutput } = this.options;
    const app = this.deps.startProcess(
      this.options.dart ?? 'dart',
      [
        'run',
        '--enable-vm-service=0',
        '--no-serve-devtools',
        '-DSILENT_VM_SERVICE=true',
        `--write-service-info=${pathToFileURL(info)}`,
        file,
      ],
      { cwd, env: { ...this.deps.env, ...this.options.env } },
    );
    this.process = app;
    onOutput(`twk: dart run ${path.relative(cwd, file)} (pid ${app.pid})\n`);
    app.onOutput(onOutput);
    app.onError((e) => onOutput(`twk: ${e.message}\n`));
    const exited = app.exited.then(({ code, signal }) => {
        onOutput(`twk: the app exited (${signal ?? code})\n`);
        if (this.hot) {
          this.hot.close();
          this.hot = undefined;
          this.options.onApp?.(undefined);
        }
        if (this.restarting && !this.stopping) {
          this.restarting = false;
          this.launch();
        } else {
          this.process = undefined;
          this.options.onStatus({ state: 'ended' });
          this.end(signal ?? code ?? 0);
        }
      });
    this.hotReady = this.connect(app, info, exited);
  }

  /** Connects to [app]'s VM service once [info] names it. */
  private async connect(app: AppProcess, info: string, exited: Promise<void>): Promise<HotApp | undefined> {
    let gone = false;
    void exited.then(() => (gone = true));
    const uri = await this.serviceUri(info, exited);
    if (!uri || gone) {
      return undefined;
    }
    try {
      const vm = await this.deps.connectVm(uri);
      const hot = await HotApp.attach(
        vm,
        (s) => s.state !== 'ended' && this.process === app && this.options.onStatus(s),
        () => void this.restart(),
      );
      if (this.process !== app || gone) {
        hot.close();
        return undefined;
      }
      this.hot = hot;
      this.options.onStatus({ state: 'running' });
      this.options.onApp?.(hot);
      return hot;
    } catch (e) {
      this.options.onOutput(`twk: no hot reload: ${String(e)}\n`);
      return undefined;
    }
  }

  /**
   * The VM service's address once [info] names it: looked for as the
   * run's directory changes (a watch, not a poll); undefined once the app
   * ended, or after [serviceInfoPatience], said so.
   */
  private serviceUri(info: string, exited: Promise<void>): Promise<string | undefined> {
    return new Promise((resolve) => {
      let done = false;
      let watcher: fs.FSWatcher | undefined;
      let timer: Disposable | undefined;
      const finish = (uri: string | undefined) => {
        if (!done) {
          done = true;
          watcher?.close();
          timer?.dispose();
          resolve(uri);
        }
      };
      const look = () => {
        const uri = serviceInfoUri(info);
        if (uri) {
          finish(uri);
        }
      };
      try {
        watcher = fs.watch(path.dirname(info), look);
        watcher.on('error', () => {});
      } catch {
        // no watch here: the bound alone ends the wait
      }
      timer = this.deps.clock.setTimeout(() => {
        if (!done) {
          this.options.onOutput(`twk: no hot reload: the app named no VM service in ${serviceInfoPatience / 1000} s\n`);
          finish(undefined);
        }
      }, serviceInfoPatience);
      void exited.then(() => finish(undefined));
      look();
    });
  }
}

/** The `uri` of the service info file [file] (`--write-service-info`), once all of it is written. */
function serviceInfoUri(file: string): string | undefined {
  let info: unknown;
  try {
    info = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    // not written yet, or not all of it
    return undefined;
  }
  if (typeof info !== 'object' || info === null || !('uri' in info)) {
    return undefined;
  }
  return typeof info.uri === 'string' ? info.uri : undefined;
}
