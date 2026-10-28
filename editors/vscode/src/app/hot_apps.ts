// The use cases of running and debugging twk apps, each in a twk terminal
// of its own, with hot reload and hot restart: an app the extension runs
// ([Runner]), or one Dart-Code debugs ([Debugger]), whose VM service the
// extension connects to beside the debugger. The app finds its terminal
// by TWK_SHELL in its environment; closing the terminal ends the app.
import * as path from 'node:path';

import { shellVariable } from '../core/address';
import { Disposable, Emitter } from '../core/events';
import { HotApp, HotStatus, describe } from '../core/hot';
import { AppService } from '../core/inspect';
import { projectOf } from '../core/project';
import { Vm } from '../core/vm';
import { DebugRequest } from './launch';
import { Clock, DartLaunch, DebugSession, Debugger, HotContext, Log, Runner, Settings, StatusSink } from './ports';
import { TwkTerminal } from './terminal';
import { Terminals } from './terminals';

/** An app the extension reloads and restarts. */
export interface Hot {
  readonly kind: 'run' | 'debug';
  readonly project: string;
  /** The terminal it runs in. */
  readonly terminal: TwkTerminal;
  reload(): Promise<HotStatus>;
  /** Settles once the app was started again. */
  restart(): Promise<void>;
  stop(): Promise<void>;
  /** Has it paint all of itself again. */
  redraw(): Promise<void>;
}

export interface HotAppsDeps {
  readonly terminals: Terminals;
  readonly runner: Runner;
  readonly debugger: Debugger;
  readonly connectVm: (uri: string) => Promise<Vm>;
  readonly status: StatusSink;
  readonly context: HotContext;
  readonly log: Log;
  readonly settings: Settings;
  readonly clock: Clock;
  /** The extension's environment: TWK_DEBUG is read from it. */
  readonly env: Readonly<Record<string, string | undefined>>;
}

/** An app's VM service, as an inspector takes it: the terminal it runs in, and its service, or undefined once it went away. */
export interface AppConnection {
  readonly terminal: TwkTerminal;
  readonly service: AppService | undefined;
}

/** The terminal of a debug launch, and the session that runs in it now. */
interface Served {
  readonly terminal: TwkTerminal;
  session: DebugSession | undefined;
}

export class HotApps {
  private readonly running = new Set<Hot>();
  private readonly debugged = new Map<string, Hot>();
  /** The terminals of the debug launches, by their `twkSession`. */
  private readonly served = new Map<string, Served>();
  private nextSession = 0;
  private readonly statuses = new Emitter<HotStatus>();
  /** An event for each status any app goes through. */
  readonly onStatus = this.statuses.event;
  private last: HotStatus | undefined;
  private readonly connections = new Emitter<AppConnection>();
  /** An app's VM service connected, or went away: a run's, a debug session's, each restart's anew. */
  readonly onApp = this.connections.event;
  private saveTimer: Disposable | undefined;
  private readonly savedProjects = new Set<string | undefined>();
  private readonly listening: Disposable[];

  constructor(private readonly deps: HotAppsDeps) {
    const { debugger: debug } = deps;
    this.listening = [
      debug.onStarted((session) => this.started(session)),
      debug.onVmService(({ session, uri }) => this.debugging(session, uri)),
      debug.onTerminated((id) => {
        const hot = this.debugged.get(id);
        if (hot) {
          this.debugged.delete(id);
          void hot.stop();
        }
        for (const served of this.served.values()) {
          if (served.session?.id === id) {
            served.session = undefined;
          }
        }
      }),
    ];
  }

  /** The apps reloaded and restarted now. */
  hots(): Hot[] {
    return [...this.running];
  }

  /** The last status of a reload or restart. */
  get status(): HotStatus | undefined {
    return this.last;
  }

  /** TWK_DEBUG ([given], else the extension's) with `keys` added: the app's own hot keys, Ctrl+G h and Ctrl+G H, on. */
  private debugKeys(given = this.deps.env.TWK_DEBUG): string {
    const debug = new Set((given ?? '').split(',').filter(Boolean));
    debug.add('keys');
    return [...debug].join(',');
  }

  private show(s: HotStatus): void {
    const { log } = this.deps;
    this.last = s;
    if (s.state === 'failed') {
      log.appendLine(`twk: hot reload failed:\n${s.errors}`);
    } else if (s.state === 'reloaded') {
      log.appendLine(describe(s));
    }
    this.deps.status.show(s, this.running.size > 0);
    this.statuses.fire(s);
  }

  private added(hot: Hot): void {
    this.running.add(hot);
    this.deps.context(true);
  }

  private removed(hot: Hot): void {
    this.running.delete(hot);
    this.deps.context(this.running.size > 0);
  }

  /**
   * Runs the Dart file with `dart run`, its stdin and stdout pipes, in a
   * new twk terminal (TWK_SHELL); what it prints goes to the log. With
   * the VM service on: a save reloads it, and it restarts in place.
   * Closing the terminal ends it.
   */
  async runFile(file: string): Promise<number | undefined> {
    const project = projectOf(file);
    if (!project) {
      throw new Error('no Dart file of a project open');
    }
    const terminal = await this.deps.terminals.create(path.basename(file));
    terminal.say(`\x1b[2mtwk: dart run ${path.relative(project, file)}\x1b[0m\r\n`);
    let hot: Hot | undefined;
    const run = this.deps.runner({
      file,
      cwd: project,
      env: { TWK_DEBUG: this.debugKeys(), [shellVariable]: terminal.variable },
      onOutput: (text) => this.deps.log.append(text),
      onStatus: (s) => hot !== undefined && this.running.has(hot) && this.show(s),
      onApp: (service) => this.connections.fire({ terminal, service }),
    });
    const started: Hot = {
      kind: 'run',
      project,
      terminal,
      reload: () => run.reload(),
      restart: () => run.restart(),
      stop: () => run.stop(),
      redraw: () => run.redraw(),
    };
    hot = started;
    this.added(started);
    const listening = [
      // the app ends with its terminal, and is started again no more
      terminal.onDidDispose(() => void run.stop()),
      terminal.onDidReload(() => void run.redraw()),
    ];
    void run.ended.then(() => {
      listening.forEach((d) => d.dispose());
      this.removed(started);
    });
    return run.pid;
  }

  /**
   * The launch that debugs [request]'s program with Dart-Code in the Debug
   * Console, in a new twk terminal (TWK_SHELL in its `env`): a breakpoint
   * stops the app, not the terminal. Closing the terminal ends the session.
   */
  async debugLaunch(request: DebugRequest): Promise<DartLaunch> {
    const { program } = request;
    const project = projectOf(program);
    if (!project) {
      throw new Error(`${program} is in no Dart project (pubspec.yaml)`);
    }
    const terminal = await this.deps.terminals.create(path.basename(program));
    const key = `twk-${this.nextSession++}`;
    const served: Served = { terminal, session: undefined };
    this.served.set(key, served);
    terminal.onDidDispose(() => {
      this.served.delete(key);
      if (served.session) {
        void this.deps.debugger.stop(served.session).catch((e: unknown) => this.deps.log.appendLine(`twk: stopping the session failed: ${String(e)}`));
      }
    });
    terminal.onDidReload(() => void (served.session && this.debugged.get(served.session.id)?.redraw()));
    terminal.say(`\x1b[2mtwk: debugging ${path.relative(project, program)}\x1b[0m\r\n`);
    return {
      type: 'dart',
      request: 'launch',
      name: request.name ?? `twk: ${path.basename(program)}`,
      program,
      cwd: request.cwd ?? project,
      console: 'debugConsole',
      env: { ...request.env, TWK_DEBUG: this.debugKeys(request.env.TWK_DEBUG), [shellVariable]: terminal.variable },
      twkSession: key,
      others: request.others,
    };
  }

  /** Debugs the Dart file in a new twk terminal ([debugLaunch]); whether the session started. */
  async debugFile(file: string): Promise<boolean> {
    if (!projectOf(file)) {
      throw new Error('no Dart file of a project open');
    }
    const launch = await this.debugLaunch({ program: file, env: {}, others: {} });
    const started = await this.deps.debugger.start(launch);
    if (!started) {
      // nothing will run in it
      await this.served.get(launch.twkSession)?.terminal.dispose();
    }
    return started;
  }

  /** A session of a launch of [debugLaunch] started: it ends with its terminal, or at once when that is gone. */
  private started(session: DebugSession): void {
    const served = this.served.get(session.configuration.twkSession);
    if (!served || served.terminal.isClosed) {
      void this.deps.debugger.stop(session).catch(() => {});
      return;
    }
    served.session = session;
  }

  /**
   * The debug session told the address of its VM service (Dart-Code's
   * `dart.debuggerUris`): the extension connects to it too, for twk's hot
   * reload. Dart-Code's own (`dart.hotReload`, the custom request
   * `hotReload`) reloads the sources and has twk rebuild nothing.
   */
  private debugging(session: DebugSession, uri: string): void {
    const served = this.served.get(session.configuration.twkSession);
    if (served && !this.debugged.has(session.id)) {
      void this.attachDebug(session, served.terminal, uri);
    }
  }

  private async attachDebug(session: DebugSession, terminal: TwkTerminal, uri: string): Promise<void> {
    const { debugger: debug, log } = this.deps;
    const { program, cwd } = session.configuration;
    const project = projectOf(program) ?? cwd;
    let app: HotApp | undefined;
    let restarting: Promise<void> | undefined;
    const hot: Hot = {
      kind: 'debug',
      project,
      terminal,
      reload: async () => (app ? app.reload() : { state: 'ended' }),
      // the debug adapter of a Dart CLI app has no restart of its own
      // (`supportsRestartRequest` false, no `hotRestart` custom request):
      // the session ends, and the same launch starts again, in the same
      // terminal; not once that was closed, the app having none then
      restart: () =>
        (restarting ??= (async () => {
          if (terminal.isClosed) {
            return;
          }
          app?.restarting();
          let ending: Disposable | undefined;
          try {
            const ended = new Promise<void>((resolve) => {
              ending = debug.onTerminated((id) => id === session.id && resolve());
            });
            await debug.stop(session);
            await ended;
            if (!terminal.isClosed) {
              await debug.start(session.configuration);
            }
          } finally {
            ending?.dispose();
            // one that failed may be tried again
            restarting = undefined;
          }
        })()),
      stop: async () => {
        this.removed(hot);
        if (app) {
          app.close();
          this.connections.fire({ terminal, service: undefined });
        }
      },
      redraw: async () => app?.redraw(),
    };
    this.debugged.set(session.id, hot);
    this.added(hot);
    try {
      const vm = await this.deps.connectVm(uri);
      app = await HotApp.attach(
        vm,
        (s) => this.running.has(hot) && s.state !== 'ended' && this.show(s),
        () => void hot.restart().catch((e: unknown) => log.appendLine(`twk: restart failed: ${String(e)}`)),
      );
      if (!this.running.has(hot)) {
        app.close();
        return;
      }
      this.show({ state: 'running' });
      this.connections.fire({ terminal, service: app });
    } catch (e) {
      log.appendLine(`twk: no hot reload for the debug session: ${String(e)}`);
      // nothing to reload: the commands are off, and its end has nothing to stop
      this.debugged.delete(session.id);
      this.removed(hot);
    }
  }

  /** Each app the extension reloads, or the ones of [project] only. */
  private targets(project?: string): Hot[] {
    return [...this.running].filter((h) => !project || h.project === project);
  }

  private all(): Hot[] {
    const all = this.targets();
    if (!all.length) {
      throw new Error('no app running with hot reload: start one with "Run" or "Debug Dart File in twk Terminal"');
    }
    return all;
  }

  reloadAll(): Promise<HotStatus[]> {
    return Promise.all(this.all().map((h) => h.reload()));
  }

  async restartAll(): Promise<number> {
    const all = this.all();
    await Promise.all(all.map((h) => h.restart()));
    return all.length;
  }

  /**
   * A Dart file was saved: the apps of the project it is in reload, or
   * every app when it is in none of theirs (a package they depend on); the
   * saves of a "Save All" as one.
   */
  saved(file: string): void {
    if (!file.endsWith('.dart') || !this.running.size || !this.deps.settings.hotReloadOnSave()) {
      return;
    }
    const project = projectOf(file);
    this.savedProjects.add(project && this.targets(project).length ? project : undefined);
    this.saveTimer?.dispose();
    this.saveTimer = this.deps.clock.setTimeout(() => {
      const projects = [...this.savedProjects];
      this.savedProjects.clear();
      const reload = new Set(projects.includes(undefined) ? this.targets() : projects.flatMap((p) => this.targets(p)));
      reload.forEach((h) => void h.reload());
    }, 100);
  }

  /** Ends the apps the extension runs, each through its own process. */
  async dispose(): Promise<void> {
    this.listening.forEach((d) => d.dispose());
    this.saveTimer?.dispose();
    this.saveTimer = undefined;
    await Promise.all(this.hots().filter((h) => h.kind === 'run').map((h) => h.stop()));
    this.statuses.dispose();
    this.connections.dispose();
  }
}
