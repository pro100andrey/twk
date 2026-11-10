// The log of the apps the extension runs, as `twk logs` shows it: the
// records an app serves (`LogSink.serve`, which the debug aid `logs` makes
// an app do), read over its socket (core/log_follow.ts) and shown in a
// webview of one panel (webview/app_logs.ts, spoken to in the messages of
// webview/app_logs_protocol.ts) with the levels to show, a word to filter
// by, pause and clear done there, a choice of the app, and the frames of a
// stack opened in the editor from here. [AppLogs] follows an app for each
// twk terminal it is told of (while the aid is on), keeps the last
// [AppLogs.keep] rows of them all, and [AppLogsPanel] sends them to the
// panel at most every [AppLogsPanel.interval] ms.
import * as path from 'node:path';
import { pathToFileURL } from 'node:url';

import { Packages, parseFrames, parsePackages, parseRecord, resolveUri } from '../core/app_log';
import { Clock, Disposable, Emitter, Event } from '../core/events';
import { LogEndpoints, LogFollower } from '../core/log_follow';
import { SourceSpot } from '../core/locator';
import { AppInfo, LogRow, ToAppLogs, isFromAppLogs } from '../webview/app_logs_protocol';
import { Settings, SourceOpener } from './ports';
import { WebviewPanelPort } from './webview_view';

/** Opens a new panel for the apps' log. */
export type AppLogsPanelFactory = (title: string) => WebviewPanelPort<ToAppLogs>;

/** A twk terminal an app runs in: what is followed for it ends with it. */
export interface AppTerminal {
  readonly name: string;
  readonly onDidDispose: Event<void>;
}

export interface AppLogsDeps {
  readonly endpoints: LogEndpoints;
  readonly clock: Clock;
  readonly settings: Settings;
  readonly opener: SourceOpener;
  /** A text file's contents, or undefined for none (the package configuration is read through it). */
  readonly readText: (file: string) => string | undefined;
}

interface App {
  readonly id: number;
  readonly name: string;
  readonly project: string;
  /** The terminals this app is followed for: the app ends with the last. */
  readonly terminals: Set<AppTerminal>;
  state: AppInfo['state'];
  follower: LogFollower | undefined;
}

/** A row, and the places of its stack's frames, from 1, where they are of code on the disk. */
interface Kept {
  readonly row: LogRow;
  readonly spots: readonly (SourceSpot | undefined)[];
}

export class AppLogs {
  /** The most rows kept, of all the apps. */
  static readonly keep = 5000;
  private static readonly slack = 500;

  private readonly apps = new Map<number, App>();
  private readonly followed = new Map<AppTerminal, App>();
  /** The live app of each project: its address file is one, so its apps are followed once, whatever terminals run them. */
  private readonly byProject = new Map<string, App>();
  /** The rows, with a slack of [AppLogs.slack] past [AppLogs.keep] trimmed at once. */
  private rows: Kept[] = [];
  private nextApp = 1;
  private nextRow = 1;
  private readonly packages = new Map<string, Packages>();
  private readonly rowEvents = new Emitter<readonly LogRow[]>();
  private readonly appEvents = new Emitter<void>();
  private readonly resets = new Emitter<void>();
  /** Rows were made. */
  readonly onRows = this.rowEvents.event;
  /** An app was followed, or went from a state to another. */
  readonly onApps = this.appEvents.event;
  /** Every row was forgotten. */
  readonly onReset = this.resets.event;

  constructor(private readonly deps: AppLogsDeps) {}

  /** The apps followed, and those that were, the oldest first. */
  appsInfo(): AppInfo[] {
    const all = [...this.apps.values()];
    return all.map((a) => ({
      id: a.id,
      label: all.filter((b) => b.name === a.name).length > 1 ? `${a.name} (${a.id})` : a.name,
      state: a.state,
    }));
  }

  /** The rows kept, the oldest first. */
  allRows(): LogRow[] {
    return this.rows.slice(-AppLogs.keep).map((k) => k.row);
  }

  /**
   * An app started in [terminal], of the project at [project]: its log is
   * followed from now on, once, when the aid `logs` is on, as the app
   * asked to serve it is; not otherwise (the app serves none).
   */
  started(terminal: AppTerminal, project: string): void {
    if (this.followed.has(terminal) || !this.deps.settings.switches().debug.includes('logs')) {
      return;
    }
    this.follow(terminal, project);
  }

  /**
   * Follows the log of the app of [project] in [terminal], one app after
   * another, until the terminal is closed. The project's `logs` file names
   * the address of the latest app only, and says nothing of whose it is, so
   * a project is followed once, shown once, under the name of the terminal
   * that asked first; a second terminal of it joins that one, and it ends
   * with the last of them.
   */
  follow(terminal: AppTerminal, project: string): void {
    if (this.followed.has(terminal)) {
      return;
    }
    const joined = this.byProject.get(project);
    if (joined) {
      joined.terminals.add(terminal);
      this.followed.set(terminal, joined);
      terminal.onDidDispose(() => this.release(terminal, joined));
      return;
    }
    const app: App = { id: this.nextApp++, name: terminal.name, project, terminals: new Set([terminal]), state: 'waiting', follower: undefined };
    this.apps.set(app.id, app);
    this.followed.set(terminal, app);
    this.byProject.set(project, app);
    app.follower = new LogFollower(project, this.deps.endpoints, this.deps.clock, {
      connected: () => {
        app.state = 'connected';
        this.note(app, 'connected to the log of the app');
        this.appEvents.fire();
      },
      line: (text) => this.add(app, text),
      ended: () => {
        app.state = 'waiting';
        this.note(app, 'the app ended');
        this.appEvents.fire();
      },
    });
    terminal.onDidDispose(() => this.release(terminal, app));
    this.appEvents.fire();
  }

  private release(terminal: AppTerminal, app: App): void {
    this.followed.delete(terminal);
    app.terminals.delete(terminal);
    if (app.terminals.size > 0 || app.state === 'ended') {
      return;
    }
    app.follower?.dispose();
    app.follower = undefined;
    if (this.byProject.get(app.project) === app) {
      this.byProject.delete(app.project);
    }
    app.state = 'ended';
    this.note(app, 'the terminal of the app was closed');
    this.appEvents.fire();
  }

  private note(app: App, message: string): void {
    this.push({ id: this.nextRow++, app: app.id, time: Date.now(), level: 'note', message }, []);
  }

  private add(app: App, line: string): void {
    const r = parseRecord(line, Date.now());
    const frames = r.stack === undefined ? [] : parseFrames(r.stack);
    const packages = frames.some((f) => f.place?.uri.startsWith('package:')) ? this.packagesOf(app.project) : new Map<string, string>();
    const spots = frames.map((f): SourceSpot | undefined => {
      const uri = f.place && resolveUri(f.place.uri, packages);
      return uri && f.place ? { uri, line: f.place.line, column: f.place.column, exact: true, method: '' } : undefined;
    });
    this.push(
      {
        id: this.nextRow++,
        app: app.id,
        time: r.time,
        level: r.level,
        message: r.message,
        ...(r.error === undefined ? {} : { error: r.error }),
        ...(r.stack === undefined ? {} : { stack: frames.map((f, i) => ({ text: f.text, open: spots[i] !== undefined })) }),
      },
      spots,
    );
  }

  /** The packages of the project at [project]: the nearest `.dart_tool/package_config.json` from it up. */
  private packagesOf(project: string): Packages {
    let found = this.packages.get(project);
    if (!found) {
      found = new Map();
      for (let dir = project; ; dir = path.dirname(dir)) {
        const file = path.join(dir, '.dart_tool', 'package_config.json');
        const text = this.deps.readText(file);
        if (text !== undefined) {
          found = parsePackages(text, pathToFileURL(file).href);
          break;
        }
        if (path.dirname(dir) === dir) {
          break;
        }
      }
      this.packages.set(project, found);
    }
    return found;
  }

  private push(row: LogRow, spots: readonly (SourceSpot | undefined)[]): void {
    this.rows.push({ row, spots });
    if (this.rows.length > AppLogs.keep + AppLogs.slack) {
      this.rows.splice(0, this.rows.length - AppLogs.keep);
    }
    this.rowEvents.fire([row]);
  }

  /** Opens the [frame] of the stack of the row [row]; false where it is not a place of code on the disk. */
  async open(row: number, frame: number): Promise<boolean> {
    const spot = this.rows.find((k) => k.row.id === row)?.spots[frame];
    if (!spot) {
      return false;
    }
    await this.deps.opener.open(spot);
    return true;
  }

  /** Forgets every row (and the apps that went away). */
  clear(): void {
    this.rows = [];
    for (const [id, app] of this.apps) {
      if (app.state === 'ended') {
        this.apps.delete(id);
      }
    }
    this.resets.fire();
  }

  dispose(): void {
    for (const app of this.apps.values()) {
      app.follower?.dispose();
    }
    this.followed.clear();
    this.byProject.clear();
    this.rowEvents.dispose();
    this.appEvents.dispose();
    this.resets.dispose();
  }
}

/** The panel of the apps' log: what [AppLogs] keeps, sent to its webview. */
export class AppLogsPanel implements Disposable {
  /** The longest the webview waits for new rows, in milliseconds. */
  static readonly interval = 100;

  private readonly listening: Disposable[];
  private ready = false;
  private timer: Disposable | undefined;
  private pending: LogRow[] = [];
  private disposed = false;
  private readonly disposes = new Emitter<void>();
  /** It was closed. */
  readonly onDidDispose = this.disposes.event;
  /** What the webview said it shows, last. */
  shown: { readonly rows: number; readonly held: number; readonly last: readonly string[] } | undefined;

  constructor(
    private readonly logs: AppLogs,
    readonly panel: WebviewPanelPort<ToAppLogs>,
    private readonly clock: Clock,
  ) {
    this.listening = [
      logs.onRows((rows) => {
        this.pending.push(...rows);
        this.later();
      }),
      logs.onApps(() => {
        if (this.ready) {
          void this.panel.post({ type: 'apps', apps: this.logs.appsInfo() });
        }
      }),
      logs.onReset(() => {
        this.pending = [];
        this.reset();
      }),
      panel.onMessage((m) => {
        if (!isFromAppLogs(m)) {
          return;
        }
        switch (m.type) {
          case 'shown':
            this.shown = m;
            break;
          case 'ready':
            // its first, or a webview loaded again: all of it
            this.ready = true;
            this.pending = [];
            this.reset();
            break;
          case 'clear':
            this.logs.clear();
            break;
          case 'open':
            void this.logs.open(m.row, m.frame);
            break;
        }
      }),
      panel.onDispose(() => this.dispose()),
    ];
  }

  private reset(): void {
    if (this.ready) {
      void this.panel.post({ type: 'reset', title: 'twk app logs', apps: this.logs.appsInfo(), rows: this.logs.allRows() });
    }
  }

  private later(): void {
    if (this.timer || !this.ready) {
      return;
    }
    this.timer = this.clock.setTimeout(() => {
      this.timer = undefined;
      this.flush();
    }, AppLogsPanel.interval);
  }

  /** Sends the rows made since the last, at once. */
  flush(): void {
    const rows = this.pending;
    this.pending = [];
    if (this.ready && rows.length > 0) {
      void this.panel.post({ type: 'rows', rows });
    }
  }

  reveal(): void {
    this.panel.reveal();
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.timer?.dispose();
    this.timer = undefined;
    this.listening.forEach((d) => d.dispose());
    this.panel.dispose();
    this.disposes.fire();
    this.disposes.dispose();
  }
}

/** The one panel of the apps' log, opened when asked for, shown again when asked again. */
export class AppLogsView implements Disposable {
  private open: AppLogsPanel | undefined;

  constructor(
    private readonly logs: AppLogs,
    private readonly panels: AppLogsPanelFactory,
    private readonly clock: Clock,
  ) {}

  show(): AppLogsPanel {
    if (this.open) {
      this.open.reveal();
      return this.open;
    }
    const panel = new AppLogsPanel(this.logs, this.panels('twk app logs'), this.clock);
    this.open = panel;
    panel.onDidDispose(() => (this.open = undefined));
    return panel;
  }

  /** The panel, where one is open. */
  get current(): AppLogsPanel | undefined {
    return this.open;
  }

  dispose(): void {
    this.open?.dispose();
  }
}
