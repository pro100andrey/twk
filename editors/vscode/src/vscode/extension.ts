// twk for VS Code, a prototype: a terminal of the extension's own (xterm.js
// in a webview) for each twk app it runs or debugs, which the app opens as
// its terminal through twk's own socket terminal (the `twk shell`
// protocol), told where by TWK_SHELL in its environment.
//
// The composition root: the adapters of this directory made here, given to
// the use cases of app/, and the commands bound to those.
import * as os from 'node:os';

import * as vscode from 'vscode';

import * as fs from 'node:fs';
import * as path from 'node:path';

import { HotApps, Hot } from '../app/hot_apps';
import { Inspector } from '../app/inspector';
import { LogPanel, LogPanels } from '../app/log_panel';
import { Player } from '../app/player';
import { Recording, Recordings } from '../app/recording';
import { activeScreen, screenText } from '../app/screens';
import { Terminals } from '../app/terminals';
import { TwkTerminal } from '../app/terminal';
import { WebviewTerminalView } from '../app/webview_view';
import { parseCast } from '../core/cast';
import { fileSink } from '../core/cast_file';
import { describeChoice, environmentOf } from '../core/capabilities';
import { InspectNode, toggleItems, togglesPicked } from '../core/inspect';
import { realClock } from '../core/events';
import { HotStatus } from '../core/hot';
import { startNodeProcess } from '../core/process';
import { describeSwitches, switchItems, switchesPicked } from '../core/switches';
import { HotRun } from '../core/runner';
import { TerminalShell } from '../core/shell';
import { VmClient } from '../core/vm';
import { chooseCapabilities } from './capabilities_pick';
import { VsCodeDebugger } from './debugger';
import { VsCodeDesktop } from './desktop';
import { registerLaunches } from './launch';
import { openLogPanel, openWebviewTerminal } from './panel';
import { RecordingStatus } from './recording';
import { VsCodeInspectorView, vsCodeOpener, vsCodePickingIndicator } from './inspector_view';
import { Configuration } from './settings';
import { StatusBar } from './status_bar';

/** What the extension gives its tests (`activate`'s result). */
export interface Api {
  /** The twk terminals open, the oldest first. */
  terminals(): TwkTerminal[];
  /** The webview of [terminal]. */
  view(terminal: TwkTerminal): WebviewTerminalView | undefined;
  /** The apps reloaded and restarted now. */
  hots(): Hot[];
  /** The last status of a reload or restart, as the status bar shows it. */
  status(): { text: string; status: HotStatus | undefined };
  /** An event for each status any app goes through. */
  onStatus: vscode.Event<HotStatus>;
  /** What the status bar says of the progress of the app in [terminal]. */
  progressOf(terminal: TwkTerminal): string | undefined;
  /** The inspector, and its tree view. */
  readonly inspector: Inspector;
  readonly inspectorView: VsCodeInspectorView;
  /** The recordings played back now, the oldest first. */
  players(): Player[];
  /** The recordings being made. */
  readonly recordings: Recordings;
  /** The sequence log open of [screen], where one is. */
  logOf(screen: TwkTerminal | Player): LogPanel | undefined;
}

/** What `deactivate` ends: the one place VS Code's module-level entry points make a module-level variable of. */
let shutdown: (() => Promise<void>) | undefined;

export function activate(context: vscode.ExtensionContext): Api {
  const log = vscode.window.createOutputChannel('twk');
  const settings = new Configuration();
  const bar = new StatusBar();
  const desktop = new VsCodeDesktop();
  context.subscriptions.push(log, bar, desktop);

  const terminals = new Terminals({
    views: (title) => openWebviewTerminal(title, context.extensionUri),
    startShell: (pane, serves) => TerminalShell.start(pane, { ...serves, temporaryRoot: os.tmpdir(), tcp: process.platform === 'win32' }),
    settings,
    log,
    desktop,
  });
  const debug = new VsCodeDebugger();
  context.subscriptions.push(debug);
  const connectVm = (uri: string) => VmClient.connect(uri, realClock);
  const hot = new HotApps({
    terminals,
    runner: (options) => {
      const run = HotRun.start(options, { startProcess: startNodeProcess, connectVm, env: process.env, clock: realClock });
      return {
        get pid() {
          return run.process?.pid;
        },
        reload: () => run.reload(),
        restart: () => run.restart(),
        stop: () => run.stop(),
        redraw: () => run.redraw(),
        ended: run.ended,
      };
    },
    debugger: debug,
    connectVm,
    status: bar,
    context: (running) => void vscode.commands.executeCommand('setContext', 'twk.hotApp', running),
    log,
    settings,
    clock: realClock,
    env: process.env,
  });
  const statuses = new vscode.EventEmitter<HotStatus>();
  const forwarding = hot.onStatus((s) => statuses.fire(s));
  context.subscriptions.push(
    statuses,
    forwarding,
    registerLaunches(
      (request) => hot.debugLaunch(request),
      (message) => void vscode.window.showErrorMessage(`twk: ${message}`),
    ),
  );
  const inspectorView = new VsCodeInspectorView();
  const inspector = new Inspector({
    apps: hot.onApp,
    view: inspectorView,
    opener: vsCodeOpener,
    picking: vsCodePickingIndicator,
    notice: { say: (text) => void vscode.window.setStatusBarMessage(text, 5000) },
    clock: realClock,
    log,
  });
  context.subscriptions.push(inspectorView, { dispose: () => inspector.dispose() });
  const recordings = new Recordings({
    clock: realClock,
    epochSeconds: () => Date.now() / 1000,
    term: () => environmentOf(settings.capabilities().capabilities).TERM,
    redrawOf: (terminal) => {
      const app = hot.hots().find((h) => h.terminal === terminal);
      return app ? () => app.redraw() : undefined;
    },
  });
  const recordingStatus = new RecordingStatus(recordings);
  const logs = new LogPanels((title) => openLogPanel(title, context.extensionUri), realClock);
  const players = new Set<Player>();
  context.subscriptions.push(
    terminals.onDidCreate((t) => logs.follow(t)),
    recordingStatus,
    recordings.onDidChange(() => void vscode.commands.executeCommand('setContext', 'twk.recording', recordings.all().length > 0)),
    recordings.onDidEnd(({ terminal, end }) => {
      if (end.error) {
        void vscode.window.showErrorMessage(`twk: the recording of ${terminal.name} failed: ${end.error.message}`);
      }
    }),
  );
  shutdown = async () => {
    inspector.dispose();
    logs.dispose();
    players.forEach((p) => p.dispose());
    await recordings.dispose();
    await hot.dispose();
    await terminals.dispose();
  };

  const editorFile = (uri?: vscode.Uri) => uri?.fsPath ?? vscode.window.activeTextEditor?.document.uri.fsPath;
  function dartFile(uri?: vscode.Uri): string {
    const file = editorFile(uri);
    if (!file?.endsWith('.dart')) {
      throw new Error('no Dart file of a project open');
    }
    return file;
  }

  const command = (name: string, f: (uri?: vscode.Uri) => Promise<unknown>) =>
    context.subscriptions.push(
      vscode.commands.registerCommand(name, async (uri?: vscode.Uri) => {
        try {
          return await f(uri);
        } catch (e) {
          void vscode.window.showErrorMessage(`twk: ${e instanceof Error ? e.message : String(e)}`);
          return undefined;
        }
      }),
    );

  // A terminal for an app started anywhere with its TWK_SHELL (which it
  // shows): no project's address file names it.
  command('twk.openTerminal', () => terminals.createForAnyApp());
  command('twk.runFile', (uri) => hot.runFile(dartFile(uri)));
  command('twk.debugFile', (uri) => hot.debugFile(dartFile(uri)));
  command('twk.hotReload', () => hot.reloadAll());
  command('twk.hotRestart', () => hot.restartAll());
  command('twk.showOutput', async () => log.show(true));
  // the switch panel: a preset, or each switch; the running apps take it
  // with a hot restart
  command('twk.chooseProfile', async () => {
    const choice = await chooseCapabilities(settings.capabilities());
    if (!choice) {
      return;
    }
    const said = `twk: the next app to connect gets "${describeChoice(choice)}"`;
    if (hot.hots().length === 0) {
      void vscode.window.showInformationMessage(said);
      return;
    }
    const restart = 'Hot Restart';
    if ((await vscode.window.showInformationMessage(`${said}; the apps running take it with a hot restart`, restart)) === restart) {
      await hot.restartAll();
    }
  });

  command('twk.chooseSwitches', async () => {
    const picks = await vscode.window.showQuickPick(switchItems(settings.switches()), {
      title: 'What the twk terminal switches on in the next app to connect (a hot restart too)',
      canPickMany: true,
    });
    if (picks) {
      const switches = switchesPicked(picks.map((p) => p.label));
      const c = vscode.workspace.getConfiguration('twk');
      await c.update('terminal.screenReader', switches.screenReader, vscode.ConfigurationTarget.Workspace);
      await c.update('terminal.debugAids', switches.debug, vscode.ConfigurationTarget.Workspace);
      const on = describeSwitches(switches);
      void vscode.window.showInformationMessage(`twk: the next app to connect gets ${on === '' ? 'no switches' : on}`);
    }
  });

  // The inspector: a node of its view given by its menus, else the one
  // selected in it
  const nodeOf = (n?: unknown): InspectNode => {
    const given = typeof n === 'object' && n !== null && 'id' in n && typeof n.id === 'number' ? inspectorView.node(n.id) : undefined;
    const node = given ?? inspectorView.treeView.selection[0];
    if (!node) {
      throw new Error('no node of the twk inspector selected');
    }
    return node;
  };
  const nodeCommand = (name: string, f: (node: InspectNode) => Promise<unknown>) =>
    context.subscriptions.push(
      vscode.commands.registerCommand(name, async (n?: unknown) => {
        try {
          return await f(nodeOf(n));
        } catch (e) {
          void vscode.window.showErrorMessage(`twk: ${e instanceof Error ? e.message : String(e)}`);
          return undefined;
        }
      }),
    );
  command('twk.inspector.refresh', () => inspector.refresh());
  // the pick mode's button, pressed (stopPicking) while it is on
  command('twk.inspector.pick', () => inspector.pick());
  command('twk.inspector.stopPicking', () => inspector.stopPicking());
  nodeCommand('twk.inspector.goToSource', (node) => inspector.goToSource(node.id));
  nodeCommand('twk.inspector.goToBuild', (node) => inspector.goToBuild(node.id));
  command('twk.inspector.toggles', async () => {
    const picks = await vscode.window.showQuickPick(toggleItems(await inspector.flags()), {
      title: 'What twk draws over the app (the next app in its terminal too)',
      canPickMany: true,
    });
    if (picks) {
      await inspector.setFlags(togglesPicked(picks.map((p) => p.label)));
    }
  });

  // The screens the commands on "the twk terminal" take: the active one,
  // else the newest
  const screens = () => [...terminals.all(), ...players];
  const theScreen = () => {
    const s = activeScreen(screens());
    if (!s) {
      throw new Error('no twk terminal open');
    }
    return s;
  };
  const theTerminal = (): TwkTerminal => {
    const t = activeScreen(terminals.all());
    if (!(t instanceof TwkTerminal)) {
      throw new Error('no twk terminal of an app open');
    }
    return t;
  };

  command('twk.showLog', async () => logs.show(theScreen()));
  command('twk.copyScreen', async () => {
    const screen = theScreen();
    const text = screenText(await screen.view.snapshot());
    desktop.writeClipboard(text);
    const rows = text === '' ? 0 : text.split('\n').length - 1;
    vscode.window.setStatusBarMessage(`twk: the screen of ${screen.name} copied, ${rows} lines`, 5000);
    return text;
  });
  // Starts recording the twk terminal, to the file given or picked; stops
  // it when it is recorded already
  command('twk.record', async (uri) => {
    const terminal = theTerminal();
    const made = recordings.of(terminal);
    if (made) {
      return stopped(terminal.name, made, await made.stop());
    }
    const folder = vscode.workspace.workspaceFolders?.[0]?.uri;
    const base = `${path.basename(terminal.name, '.dart')}.cast`;
    const file =
      uri ??
      (await vscode.window.showSaveDialog({
        title: `Record ${terminal.name} as asciicast`,
        ...(folder ? { defaultUri: vscode.Uri.joinPath(folder, base) } : {}),
        filters: { asciicast: ['cast'] },
      }));
    if (!file) {
      return undefined;
    }
    return recordings.start(terminal, fileSink(file.fsPath));
  });
  const stopped = (name: string, recording: Recording, end: { events: number; seconds: number; error?: Error }) => {
    if (!end.error) {
      vscode.window.setStatusBarMessage(`twk: ${name} recorded, ${end.seconds.toFixed(1)} s, ${end.events} events`, 5000);
    }
    return recording;
  };
  command('twk.stopRecordings', async () => {
    for (const r of recordings.all()) {
      stopped(r.screen.name, r, await r.stop());
    }
  });
  // Plays a recording back in a terminal of its own: the file given (the
  // explorer's menu), or picked
  command('twk.play', async (uri) => {
    const file =
      uri ??
      (
        await vscode.window.showOpenDialog({
          title: 'Play an asciicast recording in a twk terminal',
          canSelectMany: false,
          filters: { asciicast: ['cast'], 'all files': ['*'] },
        })
      )?.[0];
    if (!file) {
      return undefined;
    }
    const cast = parseCast(fs.readFileSync(file.fsPath, 'utf8'));
    const name = path.basename(file.fsPath);
    const player = new Player(name, cast, openWebviewTerminal(`${name} · twk replay`, context.extensionUri), realClock);
    players.add(player);
    logs.follow(player);
    player.onDidDispose(() => players.delete(player));
    await player.start();
    return player;
  });

  context.subscriptions.push(
    vscode.workspace.onDidSaveTextDocument((doc) => hot.saved(doc.uri.fsPath)),
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration('twk.terminal.columns') || e.affectsConfiguration('twk.terminal.lines')) {
        terminals.applySize();
      }
      if (['profile', 'capabilities', 'screenReader', 'debugAids'].some((s) => e.affectsConfiguration(`twk.terminal.${s}`))) {
        terminals.retitle();
      }
    }),
  );

  return {
    terminals: () => terminals.all(),
    view: (terminal) => (terminal.view instanceof WebviewTerminalView ? terminal.view : undefined),
    hots: () => hot.hots(),
    status: () => ({ text: bar.text, status: hot.status }),
    onStatus: statuses.event,
    progressOf: (terminal) => desktop.progressOf(terminal),
    inspector,
    inspectorView,
    players: () => [...players],
    recordings,
    logOf: (screen) => logs.of(screen),
  };
}

export async function deactivate(): Promise<void> {
  const end = shutdown;
  shutdown = undefined;
  await end?.();
}
