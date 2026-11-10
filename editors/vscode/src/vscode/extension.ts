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
import { AppLogs, AppLogsView } from '../app/app_logs';
import { Inspector } from '../app/inspector';
import { LogPanel, LogPanels } from '../app/log_panel';
import { Player } from '../app/player';
import { InputReplay, ReplayMode } from '../app/replay_input';
import { CastTests } from '../app/cast_test';
import { Tapes } from '../app/tape';
import { Recording, Recordings } from '../app/recording';
import { activeScreen, screenText } from '../app/screens';
import { Terminals } from '../app/terminals';
import { TwkTerminal } from '../app/terminal';
import { WebviewTerminalView } from '../app/webview_view';
import { parseCast } from '../core/cast';
import { fileSink } from '../core/cast_file';
import { nodeLogEndpoints } from '../core/log_socket';
import { describeChoice, environmentOf } from '../core/capabilities';
import { InspectNode, toggleItems, togglesPicked } from '../core/inspect';
import { editorCommandOf } from '../core/editor';
import { Disposable, realClock } from '../core/events';
import { HotStatus } from '../core/hot';
import { LogFilter } from '../core/seqlog';
import { isFilter } from '../webview/log_protocol';
import { startNodeProcess } from '../core/process';
import { projectOf } from '../core/project';
import { describeSwitches, switchItems, switchesPicked } from '../core/switches';
import { HotRun } from '../core/runner';
import { TerminalShell } from '../core/shell';
import { VmClient } from '../core/vm';
import { chooseCapabilities } from './capabilities_pick';
import { TwkMainLenses } from './code_lens';
import { ScreenFileEditors, screenFileViewType } from './screen_editor';
import { VsCodeDebugger } from './debugger';
import { VsCodeDesktop } from './desktop';
import { registerLaunches } from './launch';
import { openAppLogsPanel, openLogPanel, openWebviewTerminal } from './panel';
import { RecordingStatus } from './recording';
import { VsCodeInspectorView, DetailItem, VsCodeNodeDetailsView, copyText, vsCodeOpener, vsCodePickingIndicator } from './inspector_view';
import { Configuration } from './settings';
import { registerReport } from './report';
import { registerCreate } from './create';
import { cancellable, registerTape, twkCommand } from './tape';
import { StatusBar } from './status_bar';
import { TerminalStatus } from '../app/terminal_status';
import { TerminalStatusItem } from './terminal_status';

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
  /** What the status bar says of the active twk terminal (`twk 44x7 · xterm.js`); undefined while no terminal is open. */
  terminalStatus(): string | undefined;
  /** An event for each status any app goes through. */
  onStatus: vscode.Event<HotStatus>;
  /** What the status bar says of the progress of the app in [terminal]. */
  progressOf(terminal: TwkTerminal): string | undefined;
  /** The inspector, and its tree view. */
  readonly inspector: Inspector;
  readonly inspectorView: VsCodeInspectorView;
  readonly nodeView: VsCodeNodeDetailsView;
  /** The recordings played back now, the oldest first. */
  players(): Player[];
  /** The last recording's keys typed into an app, running or ended. */
  inputReplay(): InputReplay | undefined;
  /** The recordings being made. */
  readonly recordings: Recordings;
  /** The apps' logs, and their panel. */
  readonly appLogs: AppLogs;
  readonly appLogsView: AppLogsView;
  /** The .tape commands' use case, and the diagnostics it sets. */
  readonly tapes: Tapes;
  readonly tapeDiagnostics: vscode.DiagnosticCollection;
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
    startShell: (pane, serves) =>
      TerminalShell.start(pane, { ...serves, temporaryRoot: os.tmpdir(), tcp: process.platform === 'win32', log: (message) => log.appendLine(message) }),
    settings,
    log,
    desktop,
  });
  const terminalItem = new TerminalStatusItem();
  const terminalStatus = new TerminalStatus(terminals, terminalItem);
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
    editor: editorCommandOf(vscode.env.appRoot, process.platform, fs.existsSync),
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
  const nodeView = new VsCodeNodeDetailsView();
  const inspector = new Inspector({
    apps: hot.onApp,
    view: inspectorView,
    details: nodeView,
    opener: vsCodeOpener,
    picking: vsCodePickingIndicator,
    notice: { say: (text) => void vscode.window.setStatusBarMessage(text, 5000) },
    clock: realClock,
    log,
  });
  context.subscriptions.push(inspectorView, nodeView, { dispose: () => inspector.dispose() });
  // The log the apps serve (the debug aid `logs`): followed for each app
  // the extension runs, once its VM service is connected
  const appLogs = new AppLogs({
    endpoints: nodeLogEndpoints,
    clock: realClock,
    settings,
    opener: vsCodeOpener,
    readText: (file) => {
      try {
        return fs.readFileSync(file, 'utf8');
      } catch {
        return undefined;
      }
    },
  });
  const appLogsView = new AppLogsView(appLogs, (title) => openAppLogsPanel(title, context.extensionUri), realClock);
  context.subscriptions.push(
    appLogsView,
    { dispose: () => appLogs.dispose() },
    hot.onApp(({ terminal, service }) => {
      const app = service && hot.hots().find((h) => h.terminal === terminal);
      if (app) {
        appLogs.started(terminal, app.project);
      }
    }),
  );
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
    terminalStatus,
    terminalItem,
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
    // no word of it to a window that is closing
    replayListener?.dispose();
    inputReplay?.stop();
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

  const command = (name: string, f: (uri?: vscode.Uri, ...rest: unknown[]) => Promise<unknown>) =>
    context.subscriptions.push(
      vscode.commands.registerCommand(name, async (uri?: vscode.Uri, ...rest: unknown[]) => {
        try {
          return await f(uri, ...rest);
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
  const lenses = new TwkMainLenses();
  context.subscriptions.push(lenses, vscode.languages.registerCodeLensProvider({ language: 'dart', scheme: 'file' }, lenses));
  context.subscriptions.push(vscode.window.registerCustomEditorProvider(screenFileViewType, new ScreenFileEditors(context.extensionUri)));
  registerCreate(context, log);
  const tape = registerTape(context, log);
  registerReport(context, settings, log);
  command('twk.openScreenFile', async (uri) => {
    const file = uri ?? vscode.window.activeTextEditor?.document.uri;
    if (!file) {
      throw new Error('no screen file open');
    }
    await vscode.commands.executeCommand('vscode.openWith', file, screenFileViewType);
  });
  // A key VS Code would take while a twk terminal is focused (Ctrl+W, G, N,
  // F, R, T, O and Ctrl+Shift+C, the ones package.json binds; Ctrl+P and the
  // Ctrl+K chords stay VS Code's): package.json binds it to this, which does nothing, in place of VS Code's
  // command. The terminal's xterm.js has the key already, and sends it to the app.
  command('twk.keyToApp', () => Promise.resolve());
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
  context.subscriptions.push(
    vscode.commands.registerCommand('twk.node.copyValue', async (item?: DetailItem) => {
      const text = item ? copyText(item) : undefined;
      if (text !== undefined) {
        await vscode.env.clipboard.writeText(text);
      }
    }),
  );
  command('twk.inspector.refresh', () => inspector.refresh());
  // the pick mode's button, pressed (stopPicking) while it is on
  command('twk.inspector.showRenderTree', () => inspector.showTree('render'));
  command('twk.inspector.showWidgetTree', () => inspector.showTree('element'));
  command('twk.inspector.pick', () => inspector.pick());
  command('twk.inspector.stopPicking', () => inspector.stopPicking());
  nodeCommand('twk.inspector.goToSource', (node) => inspector.goToSource(node.id));
  nodeCommand('twk.inspector.goToBuild', (node) => inspector.goToBuild(node.id));
  command('twk.inspector.toggles', async () => {
    const flags = await inspector.flags();
    const picks = await vscode.window.showQuickPick(toggleItems(flags), {
      title: 'What twk draws over the app (the next app in its terminal too)',
      canPickMany: true,
    });
    if (picks) {
      await inspector.setFlags(togglesPicked(picks.map((p) => p.label), flags));
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

  command('twk.showAppLogs', async () => appLogsView.show());
  command('twk.showLog', async () => logs.show(theScreen()));
  // Saves a sequence log to a file: the file given or picked (a `.cast` is the bytes with their times, as asciicast; any other
  // the rows as text), the filter given or the one its webview applies; answers what it wrote
  const saveLog = async (panel: LogPanel, uri?: vscode.Uri, options?: { readonly format?: unknown; readonly filter?: unknown }) => {
    const folder = vscode.workspace.workspaceFolders?.[0]?.uri;
    const base = `${path.basename(panel.screen.name, '.dart')}.sequence-log.txt`;
    const file =
      uri ??
      (await vscode.window.showSaveDialog({
        title: `Save the sequence log of ${panel.screen.name}`,
        ...(folder ? { defaultUri: vscode.Uri.joinPath(folder, base) } : {}),
        filters: { 'sequence log (text rows)': ['txt', 'log'], 'asciicast (bytes with times)': ['cast'] },
      }));
    if (!file) {
      return undefined;
    }
    const format = options?.format === 'text' || options?.format === 'cast' ? options.format : file.fsPath.endsWith('.cast') ? 'cast' : 'text';
    const filter: LogFilter | undefined = isFilter(options?.filter) ? options.filter : undefined;
    const content = format === 'cast' ? panel.cast(Date.now() / 1000, environmentOf(settings.capabilities().capabilities).TERM, filter) : panel.text(filter);
    fs.writeFileSync(file.fsPath, content);
    vscode.window.setStatusBarMessage(`twk: the sequence log of ${panel.screen.name} saved to ${path.basename(file.fsPath)}`, 5000);
    return { file: file.fsPath, format, bytes: Buffer.byteLength(content) };
  };
  command('twk.saveLog', async (uri, options) => {
    const screen = theScreen();
    return saveLog(logs.of(screen) ?? logs.show(screen), uri, options as { format?: unknown; filter?: unknown } | undefined);
  });
  context.subscriptions.push(
    logs.onDidAskSave((panel) => {
      saveLog(panel).catch((e: unknown) => void vscode.window.showErrorMessage(`twk: ${e instanceof Error ? e.message : String(e)}`));
    }),
  );
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
  // Leaves a marker in the recording of the twk terminal: a place for the
  // player to go to; returns its label
  command('twk.addMarker', async () => {
    const terminal = theTerminal();
    const made = recordings.of(terminal);
    if (!made) {
      void vscode.window.showInformationMessage(`twk: ${terminal.name} is not being recorded; start twk: Record first.`);
      return undefined;
    }
    const label = made.mark();
    vscode.window.setStatusBarMessage(`twk: ${label} left in the recording of ${terminal.name}`, 3000);
    return label;
  });
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
    // the bar's Test button: the same command as the explorer's
    player.onDidAskTest(() => void vscode.commands.executeCommand('twk.testFromCast', file));
    // the bar's Keys button: the same command as the explorer's
    player.onDidAskInput(() => void vscode.commands.executeCommand('twk.replayInput', file));
    logs.follow(player);
    player.onDidDispose(() => players.delete(player));
    await player.start();
    return player;
  });

  // A recording's keys typed into the app of the twk terminal: at their
  // times, or a step each time asked (the status bar's item and
  // twk.replayInputStep); one replay at a time
  let inputReplay: InputReplay | undefined;
  let replayListener: Disposable | undefined;
  const replayItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 98);
  context.subscriptions.push(replayItem);
  /** The start of [keys] as the tooltip shows it: a step can hold a whole paste. */
  const previewKeys = (keys: string | undefined) => {
    const shown = JSON.stringify((keys ?? '').slice(0, 40));
    return (keys ?? '').length > 40 ? `${shown}...` : shown;
  };
  const showReplay = (r: InputReplay) => {
    const { typed, total, ended } = r.state;
    void vscode.commands.executeCommand('setContext', 'twk.replayingInput', ended === undefined);
    if (ended !== undefined) {
      replayItem.hide();
      vscode.window.setStatusBarMessage(`twk: keys of ${r.name} ${ended === 'done' ? `typed, ${total}` : `not all typed (${typed} of ${total}): ${ended}`}`, 5000);
      return;
    }
    replayItem.text = `$(keyboard) ${r.name} ${typed}/${total}`;
    replayItem.tooltip = r.mode === 'steps' ? `Type the next keys (${previewKeys(r.next)}); twk: Stop Typing a Recording's Keys ends it` : 'Click to stop typing the recording\'s keys';
    replayItem.command = r.mode === 'steps' ? 'twk.replayInputStep' : 'twk.replayInputStop';
    replayItem.show();
  };
  command('twk.replayInput', async (uri, mode) => {
    const terminal = theTerminal();
    if (!terminal.shell?.serving) {
      throw new Error(`no app is connected to ${terminal.name}: run one in it first`);
    }
    const file =
      uri ??
      (
        await vscode.window.showOpenDialog({
          title: 'Type the keys of an asciicast recording into the app',
          canSelectMany: false,
          filters: { asciicast: ['cast'], 'all files': ['*'] },
        })
      )?.[0];
    if (!file) {
      return undefined;
    }
    const chosen =
      mode === 'timed' || mode === 'steps'
        ? mode
        : (
            await vscode.window.showQuickPick(
              [
                { label: 'At their recorded times', mode: 'timed' as ReplayMode },
                { label: 'Step by step', description: 'a click on the status bar item types the next keys', mode: 'steps' as ReplayMode },
              ],
              { title: `Type the keys of ${path.basename(file.fsPath)} into ${terminal.name}` },
            )
          )?.mode;
    if (!chosen) {
      return undefined;
    }
    const name = path.basename(file.fsPath);
    const cast = parseCast(fs.readFileSync(file.fsPath, 'utf8'));
    // the old one's ending is not shown: the new one's item replaces it
    replayListener?.dispose();
    inputReplay?.stop();
    const replay = new InputReplay(
      name,
      cast,
      {
        name: terminal.name,
        type: (text) => terminal.type(text),
        get hasApp() {
          return terminal.shell?.serving === true;
        },
        onDidDispose: terminal.onDidDispose,
      },
      chosen,
      realClock,
    );
    inputReplay = replay;
    const listener = replay.onDidChange(() => {
      showReplay(replay);
      if (replay.isEnded) {
        listener.dispose();
      }
    });
    replayListener = listener;
    replay.start();
    if (!replay.isEnded) {
      showReplay(replay);
    }
    return replay;
  });
  command('twk.replayInputStep', async () => inputReplay?.step());
  command('twk.replayInputStop', async () => inputReplay?.stop());

  // A test of a recording: `twk test-from-cast`, run in the recording's
  // project; the test it wrote is opened
  const castTests = new CastTests({ start: startNodeProcess, command: twkCommand, projectOf, env: process.env, log });
  command('twk.testFromCast', async (uri) => {
    const file =
      uri ??
      (
        await vscode.window.showOpenDialog({
          title: 'Create a test from an asciicast recording',
          canSelectMany: false,
          filters: { asciicast: ['cast'], 'all files': ['*'] },
        })
      )?.[0];
    if (!file) {
      return undefined;
    }
    const name = path.basename(file.fsPath);
    const result = await cancellable(`twk test-from-cast ${name}`, (cancel) => castTests.create(file.fsPath, cancel));
    if (result.busy) {
      void vscode.window.showInformationMessage(`twk: ${name}: already writing its test`);
    } else if (result.cancelled) {
      void vscode.window.showInformationMessage(`twk: ${name}: test cancelled`);
    } else if (result.test === undefined) {
      void vscode.window.showErrorMessage(`twk: ${name}: ${(result.error ?? '').split('\n')[0]}`, 'Show Output').then((b) => b && log.show(true));
    } else {
      await vscode.window.showTextDocument(vscode.Uri.file(result.test), { preview: false });
      if (result.said !== '') {
        void vscode.window.showWarningMessage(`twk: ${name}: ${result.said.split('\n')[0]}`, 'Show Output').then((b) => b && log.show(true));
      }
    }
    return result;
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
    terminalStatus: () => terminalItem.text,
    onStatus: statuses.event,
    progressOf: (terminal) => desktop.progressOf(terminal),
    inspector,
    inspectorView,
    nodeView,
    players: () => [...players],
    inputReplay: () => inputReplay,
    recordings,
    appLogs,
    appLogsView,
    tapes: tape.tapes,
    tapeDiagnostics: tape.diagnostics.collection,
    logOf: (screen) => logs.of(screen),
  };
}

export async function deactivate(): Promise<void> {
  const end = shutdown;
  shutdown = undefined;
  await end?.();
}
