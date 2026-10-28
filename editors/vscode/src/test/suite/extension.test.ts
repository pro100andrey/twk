// The twk terminals in VS Code, with a real twk app: packages/twk's
// example/counter.dart, started by the extension (twk.runFile) or debugged
// by Dart-Code (twk.debugFile, a `"type": "twk"` launch as F5 starts it),
// each in a terminal of its own that it finds by TWK_SHELL.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';

import * as vscode from 'vscode';

import type { Api } from '../../vscode/extension';
import type { HotStatus } from '../../core/hot';
import type { Snapshot } from '../../app/ports';
import type { TwkTerminal } from '../../app/terminal';
import type { InspectNode } from '../../core/inspect';
import type { Player } from '../../app/player';

const project = path.resolve(__dirname, '../../../../../packages/twk');

/** Polls [f] until it gives a value, for at most [ms]: the app's frames come when they come. */
async function until<T>(what: string, f: () => Promise<T | undefined>, ms = 90000): Promise<T> {
  const end = Date.now() + ms;
  for (;;) {
    const v = await f();
    if (v !== undefined) {
      return v;
    }
    if (Date.now() > end) {
      throw new Error(`no ${what} in ${ms} ms`);
    }
    await new Promise((r) => setTimeout(r, 100));
  }
}

/** Waits until [terminal] shows [text], on the [buffer] screen if given. */
async function shows(terminal: TwkTerminal, text: string, buffer?: Snapshot['buffer']): Promise<Snapshot> {
  let last: Snapshot | undefined;
  try {
    return await until(`"${text}" on the ${buffer ?? 'any'} screen`, async () => {
      const s = (last = await terminal.snapshot());
      return s.rows.some((r) => r.includes(text)) && (!buffer || s.buffer === buffer) ? s : undefined;
    });
  } catch (e) {
    throw new Error(`${String(e)}; the ${last?.buffer} screen:\n${last?.rows.join('\n')}`);
  }
}

/** The terminal opened last: the one of the run or session just started. */
function newest(api: Api): TwkTerminal {
  const terminal = api.terminals().at(-1);
  assert.ok(terminal, 'a twk terminal');
  return terminal;
}

/** The project's address file, which the extension writes no more. */
const addressFile = path.join(project, '.dart_tool', 'twk', 'shell');

let scratches = 0;

/**
 * A copy of the counter the tests edit, in the project's .dart_tool (which
 * git ignores): example/counter.dart stays as it is, whatever a test does.
 * A file of its own each time: VS Code keeps the text of one it opened.
 */
function scratchCounter(): vscode.Uri {
  const tests = path.join(project, '.dart_tool', 'twk_vscode_test');
  if (scratches === 0) {
    fs.rmSync(tests, { recursive: true, force: true });
  }
  const dir = path.join(tests, String(scratches++));
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, 'counter.dart');
  fs.copyFileSync(path.join(project, 'example', 'counter.dart'), file);
  return vscode.Uri.file(file);
}

/** Replaces [from] with [to] in [file] as typed in its editor, and saves it as Ctrl+S does. */
async function edit(file: vscode.Uri, from: string, to: string): Promise<void> {
  const doc = await vscode.workspace.openTextDocument(file);
  const at = doc.getText().indexOf(from);
  assert.ok(at >= 0, `"${from}" in ${file.fsPath}`);
  const change = new vscode.WorkspaceEdit();
  change.replace(file, new vscode.Range(doc.positionAt(at), doc.positionAt(at + from.length)), to);
  assert.ok(await vscode.workspace.applyEdit(change));
  assert.ok(await doc.save());
}

/** Waits for the status bar's hot reload status to be [state], or one [f] accepts. */
function status(api: Api, state: HotStatus['state'], f: (s: HotStatus) => boolean = () => true): Promise<HotStatus> {
  return until(`the status "${state}" (now "${api.status().text}")`, async () => {
    const s = api.status().status;
    return s?.state === state && f(s) ? s : undefined;
  });
}

describe('twk terminal', () => {
  let api: Api;

  before(async () => {
    const ext = vscode.extensions.getExtension<Api>('twk.twk-vscode');
    assert.ok(ext, 'the extension is there');
    api = await ext.activate();
  });

  after(async () => {
    await vscode.commands.executeCommand('workbench.action.closeAllEditors');
  });

  it('runs a twk app in a terminal of its own: frames out, keys in, the terminal back when it ends', async () => {
    const file = vscode.Uri.file(path.join(project, 'example', 'counter.dart'));
    const before = api.terminals().length;
    const pid = await vscode.commands.executeCommand<number>('twk.runFile', file);
    assert.ok(pid, 'the app started');
    assert.equal(api.terminals().length, before + 1, 'a new terminal');
    const terminal = newest(api);
    assert.equal(terminal.name, 'counter.dart');

    const first = await shows(terminal, 'Count: 0', 'alternate');
    assert.ok(first.rows[0].startsWith('╭'), first.rows.join('\n'));
    terminal.type('\x1b[A');
    await shows(terminal, 'Count: 1', 'alternate');
    terminal.type('q');
    await shows(terminal, 'the app went away', 'normal');
    assert.equal(fs.existsSync(addressFile), false, 'nothing written into the project');
  });

  it("answers the probe's color queries (OSC 10, 11), which headless xterm.js does not", async () => {
    const terminal = await vscode.commands.executeCommand<TwkTerminal>('twk.openTerminal');
    assert.ok(terminal);
    await shows(terminal, 'TWK_SHELL=');
    let answers = '';
    const listening = terminal.onDidInput((b) => (answers += Buffer.from(b).toString('latin1')));
    try {
      await terminal.write(Buffer.from('\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b[c'));
      await until('answer to DA1', async () => (answers.includes('\x1b[?') ? true : undefined), 10000);
      assert.match(answers, /\x1b\]10;rgb:[0-9a-f/]+/);
      assert.match(answers, /\x1b\]11;rgb:[0-9a-f/]+/);
    } finally {
      listening.dispose();
      await terminal.dispose();
    }
  });

  it('closed while its app runs: the app ends with it, through its own process', async () => {
    const file = vscode.Uri.file(path.join(project, 'example', 'counter.dart'));
    const pid = await vscode.commands.executeCommand<number>('twk.runFile', file);
    const old = newest(api);
    await shows(old, 'Count: 0', 'alternate');
    const [hot] = api.hots().filter((h) => h.terminal === old);
    assert.ok(hot, 'its app');
    api.view(old)!.panel.dispose(); // as the person closing its tab
    assert.ok(old.isClosed);
    await until('the app ended', async () => (api.hots().includes(hot) ? undefined : true));
    assert.throws(() => process.kill(pid, 0), /ESRCH/, 'its process gone');
    assert.deepEqual(await old.snapshot(), { buffer: 'normal', rows: [] }, 'a closed terminal shows nothing, and throws nothing');
    await old.write(Buffer.from('x')); // settles, sent to nobody
  });
});

describe("the terminal's switches", () => {
  let api: Api;
  const twk = () => vscode.workspace.getConfiguration('twk');

  before(async () => {
    api = await vscode.extensions.getExtension<Api>('twk.twk-vscode')!.activate();
    await Promise.all(api.hots().map((h) => h.stop()));
  });

  after(async () => {
    await Promise.all(api.hots().map((h) => h.stop()));
    await twk().update('terminal.debugAids', undefined, vscode.ConfigurationTarget.Global);
    await twk().update('terminal.screenReader', undefined, vscode.ConfigurationTarget.Global);
    await vscode.commands.executeCommand('workbench.action.closeAllEditors');
  });

  it("turn the debug aids and the screen reader on in the app it runs, from its next start on, over the app's own", async () => {
    await twk().update('terminal.debugAids', ['overlay'], vscode.ConfigurationTarget.Global);
    const file = vscode.Uri.file(path.join(project, 'example', 'counter.dart'));
    await vscode.commands.executeCommand<number>('twk.runFile', file);
    const terminal = newest(api);
    assert.match(terminal.title(), /\+ overlay/);
    const overlaid = await shows(terminal, 'cells compared', 'alternate');
    assert.ok(overlaid.rows[0].startsWith('╭'), overlaid.rows.join('\n'));

    await twk().update('terminal.debugAids', [], vscode.ConfigurationTarget.Global);
    await twk().update('terminal.screenReader', true, vscode.ConfigurationTarget.Global);
    const [hot] = api.hots().filter((h) => h.terminal === terminal);
    await hot.restart();
    // read out: the text alone, no box drawn round it, no overlay
    const read = await until('the counter read out', async () => {
      const s = await terminal.snapshot();
      return s.rows.some((r) => r.includes('Count: 0')) && !s.rows.some((r) => r.includes('╭')) ? s : undefined;
    });
    assert.ok(!read.rows.some((r) => r.includes('cells compared')), read.rows.join('\n'));
    terminal.type('\x1b[A');
    await shows(terminal, 'Count: 1');

    await twk().update('terminal.screenReader', false, vscode.ConfigurationTarget.Global);
    await hot.restart();
    const drawn = await shows(terminal, 'Count: 0', 'alternate');
    await until('the box drawn again', async () => ((await terminal.snapshot()).rows[0]?.startsWith('╭') ? true : undefined));
    assert.ok(!drawn.rows.some((r) => r.includes('cells compared')), 'off: the app\'s own say');
    await hot.stop();
  });
});

describe("the terminal's capabilities", () => {
  let api: Api;
  const twk = () => vscode.workspace.getConfiguration('twk');
  const infoApp = vscode.Uri.file(path.resolve(project, '..', 'twk_core', 'test', 'terminal', 'info_app.dart'));

  before(async () => {
    api = await vscode.extensions.getExtension<Api>('twk.twk-vscode')!.activate();
    await Promise.all(api.hots().map((h) => h.stop()));
    process.env.TWK_INFO_WAIT = '1';
  });

  after(async () => {
    delete process.env.TWK_INFO_WAIT;
    await Promise.all(api.hots().map((h) => h.stop()));
    await twk().update('terminal.profile', undefined, vscode.ConfigurationTarget.Global);
    await twk().update('terminal.capabilities', undefined, vscode.ConfigurationTarget.Global);
    await vscode.commands.executeCommand('workbench.action.closeAllEditors');
  });

  /** What [terminal] answers to XTSMGRAPHICS's question of its sixel colours, which the image addon answers where it is loaded, before DA1. */
  async function sixelColors(terminal: TwkTerminal): Promise<string | undefined> {
    let answers = '';
    const listening = terminal.onDidInput((b) => (answers += Buffer.from(b).toString('latin1')));
    try {
      await terminal.write(Buffer.from('\x1b[?1;1;0S\x1b[c'));
      await until('the answer to DA1', async () => (answers.includes('c') ? true : undefined), 10000);
      return /\x1b\[\?1;0;(\d+)S/.exec(answers)?.[1];
    } finally {
      listening.dispose();
    }
  }

  /** What info_app.dart, run in a new terminal, shows twk found out, by name. */
  async function found(): Promise<{ terminal: TwkTerminal; found: Map<string, string> }> {
    await vscode.commands.executeCommand<number>('twk.runFile', infoApp);
    const terminal = newest(api);
    const s = await shows(terminal, 'bidi=', 'alternate');
    const found = new Map(s.rows.filter((r) => r.includes('=')).map((r) => r.split('=') as [string, string]));
    return { terminal, found };
  }

  it('everything: kitty keyboard answered, sixel declared, the cell size of the real webview, its progress in the status bar', async () => {
    await twk().update('terminal.profile', 'everything', vscode.ConfigurationTarget.Global);
    const { terminal, found: f } = await found();
    assert.match(terminal.title(), /· everything/);
    assert.equal(f.get('kittyKeyboard'), 'true');
    assert.equal(f.get('kittyKeyboardFlags'), '1');
    assert.equal(f.get('graphics'), 'sixel');
    assert.equal(f.get('notifications'), 'osc777');
    assert.equal(f.get('repeatChar'), 'true');
    assert.ok(Number(f.get('cellPixelWidth')) > 0 && Number(f.get('cellPixelHeight')) > Number(f.get('cellPixelWidth')), `a cell of ${f.get('cellPixelWidth')}x${f.get('cellPixelHeight')}`);
    await until('its progress', async () => (api.progressOf(terminal) === '$(loading~spin) info_app.dart 40%' ? true : undefined), 10000);
    assert.equal(await sixelColors(terminal), '256', 'the image addon loaded, sixel on');
    // a sixel image, through the image addon: the terminal draws on after it
    await terminal.write(Buffer.from('\x1bPq#0;2;100;0;0#0~~~~~~\x1b\\\x1b[20;1Hafter the image'));
    await shows(terminal, 'after the image', 'alternate');
    terminal.type('\x1b[27u');
    await shows(terminal, 'the app went away', 'normal');
    await until('its progress gone', async () => (api.progressOf(terminal) === undefined ? true : undefined), 10000);
  });

  it('a switch changed from its preset: no cell size, no progress, 16 colors, in the title too', async () => {
    await twk().update('terminal.profile', 'xterm.js', vscode.ConfigurationTarget.Global);
    await twk().update('terminal.capabilities', { colors: '16', cellSize: false, progress: false }, vscode.ConfigurationTarget.Global);
    const { terminal, found: f } = await found();
    assert.match(terminal.title(), /· xterm\.js, 16 colors, no cell size, no progress/);
    assert.equal(f.get('colorMode'), 'ansi16');
    assert.equal(f.get('cellPixelWidth'), '0');
    assert.equal(f.get('progressReports'), 'false');
    assert.equal(f.get('kittyKeyboard'), 'false');
    assert.equal(api.progressOf(terminal), undefined, 'its OSC 9;4 dropped');
    assert.equal(await sixelColors(terminal), undefined, 'no image addon');
    terminal.type('q');
    await shows(terminal, 'the app went away', 'normal');
  });
});

describe('hot reload and hot restart of an app the extension runs', () => {
  let api: Api;

  before(async () => {
    api = await vscode.extensions.getExtension<Api>('twk.twk-vscode')!.activate();
    // the apps the tests before left, each ended through the extension
    await Promise.all(api.hots().map((h) => h.stop()));
  });

  after(async () => {
    await Promise.all(api.hots().map((h) => h.stop()));
    await vscode.commands.executeCommand('workbench.action.closeAllEditors');
  });

  it('a save reloads it with its state kept; a compile error leaves it running and says so; a restart starts it afresh', async () => {
    const file = scratchCounter();
    const pid = await vscode.commands.executeCommand<number>('twk.runFile', file);
    assert.ok(pid, 'the app started');
    const terminal = newest(api);
    await shows(terminal, 'Count: 0', 'alternate');
    await status(api, 'running');
    terminal.type('\x1b[A');
    await shows(terminal, 'Count: 1', 'alternate');

    // the new text, the count kept
    await edit(file, "'Count: '", "'Clicks: '");
    await shows(terminal, 'Clicks: 1', 'alternate');
    const reloaded = await status(api, 'reloaded');
    assert.match(api.status().text, /reloaded \(\d+ librar(y|ies), \d+ ms\)/, JSON.stringify(reloaded));

    // a semicolon left out: reported, the app going on with the code it had
    await edit(file, 'var _n = 0;', 'var _n = 0');
    const failed = await status(api, 'failed');
    assert.match((failed as { errors: string }).errors, /Expected ';'/);
    assert.match(api.status().text, /reload failed/);
    terminal.type('\x1b[A');
    await shows(terminal, 'Clicks: 2', 'alternate');

    // put right, by the command (twk: Hot Reload, Ctrl+Alt+R)
    await edit(file, 'var _n = 0', 'var _n = 0;');
    await status(api, 'reloaded');
    await edit(file, "'Clicks: '", "'Taps: '");
    await shows(terminal, 'Taps: 2', 'alternate');
    const [byCommand] = await vscode.commands.executeCommand<HotStatus[]>('twk.hotReload');
    assert.equal(byCommand.state, 'reloaded');

    // twk: Hot Restart: the app started again, in the same terminal, its count new
    const [hot] = api.hots();
    await vscode.commands.executeCommand('twk.hotRestart');
    await shows(terminal, 'Taps: 0', 'alternate');
    assert.equal(newest(api), terminal, 'the same terminal');
    assert.deepEqual(api.hots(), [hot], 'the same run');
    await status(api, 'running');
    terminal.type('\x1b[A');
    await shows(terminal, 'Taps: 1', 'alternate');

    terminal.type('q');
    await shows(terminal, 'the app went away', 'normal');
    await until('the run to end', async () => (api.hots().length === 0 ? true : undefined));
    await status(api, 'ended');
  });
});

/** The nodes of the inspector's tree, root first. */
function inspected(api: Api): InspectNode[] {
  const all = (n: InspectNode | null): InspectNode[] => (n ? [n, ...n.children.flatMap(all)] : []);
  return all(api.inspector.tree?.root ?? null);
}

/** Waits for the inspector's tree to have a Text that shows [text]. */
function inspectedText(api: Api, text: string): Promise<InspectNode> {
  return until(`a Text of "${text}" in the inspector (it says "${api.inspectorView.treeView.message ?? ''}")`, async () =>
    inspected(api).find((n) => n.name === 'Text' && n.properties.some((p) => p.value.includes(text))),
  );
}

/** The editor shown on [file], whose cursor is on [line] (from 0); the focus may be elsewhere (a pick keeps it in the terminal). */
function editorAt(file: vscode.Uri, line: number): Promise<vscode.TextEditor> {
  return until(`the editor of ${path.basename(file.fsPath)} at line ${line + 1}`, async () =>
    vscode.window.visibleTextEditors.find((e) => e.document.uri.fsPath === file.fsPath && e.selection.active.line === line),
  );
}

/** Whether [screen] shows a cell of a background of its own: twk's outline. */
const outlined = (screen: Snapshot) => (screen.backgrounds ?? []).some((r) => r.includes('#'));

/** Presses and releases the left button on [text]'s first cell (SGR), as a click on the terminal does for an app that reports the mouse. */
function clickOn(terminal: TwkTerminal, screen: Snapshot, text: string): void {
  const row = screen.rows.findIndex((r) => r.includes(text));
  assert.ok(row >= 0, `"${text}" on the screen:\n${screen.rows.join('\n')}`);
  const column = screen.rows[row].indexOf(text);
  terminal.type(`\x1b[<0;${column + 1};${row + 1}M\x1b[<0;${column + 1};${row + 1}m`);
}

/** The inspector's view on the screen, in Run and Debug. */
async function showInspector(): Promise<void> {
  await vscode.commands.executeCommand('workbench.view.debug');
  await vscode.commands.executeCommand('twk.inspector.focus');
}

describe('the twk inspector', () => {
  let api: Api;

  before(async () => {
    api = await vscode.extensions.getExtension<Api>('twk.twk-vscode')!.activate();
    await Promise.all(api.hots().map((h) => h.stop()));
  });

  after(async () => {
    await Promise.all(api.hots().map((h) => h.stop()));
    await vscode.commands.executeCommand('workbench.action.closeAllEditors');
  });

  it("shows the app's tree and follows it; the pick mode: each press picks a widget, opened where it was made, until it is off, the outline gone; the aids drawn over it; after a reload", async () => {
    const file = scratchCounter();
    await vscode.commands.executeCommand('twk.runFile', file);
    const terminal = newest(api);
    await shows(terminal, 'Count: 0', 'alternate');
    await showInspector();
    await until('the inspector on the screen', async () => (api.inspectorView.visible ? true : undefined));
    await inspectedText(api, 'Count: 0');
    assert.ok(inspected(api).some((n) => n.name === 'Counter' && n.build === '_CounterState'));

    // the app's tree changes: twk tells, and the tree follows
    terminal.type('\x1b[A');
    await shows(terminal, 'Count: 1', 'alternate');
    await inspectedText(api, 'Count: 1');

    // the pick mode on: each press picks, the widget selected, outlined and
    // opened where it was made (its call in the build of the counter's state)
    const source = fs.readFileSync(file.fsPath, 'utf8').split('\n');
    const line = source.findIndex((l) => l.includes('Text.rich('));
    // a node selected by hand first: outlined, nothing opened
    const box = inspected(api).find((n) => n.name === 'Box')!;
    api.inspectorView.reveal(box.id);
    let screen = await until('the Box outlined', async () => {
      const s = await terminal.snapshot();
      return s.backgrounds?.[0]?.includes('#') ? s : undefined;
    });
    assert.ok(!vscode.window.visibleTextEditors.some((e) => e.document.uri.fsPath === file.fsPath), 'nothing opened');
    await vscode.commands.executeCommand('twk.inspector.pick');
    assert.equal(api.inspector.picking, true, 'its button pressed');
    clickOn(terminal, screen, 'Count: 1');
    const picked = await until('the widget picked, selected in the view', async () => {
      const n = api.inspectorView.treeView.selection[0];
      return n?.name === 'Text' ? n : undefined;
    });
    assert.ok(picked.properties.some((p) => p.value.includes('Count: 1')), JSON.stringify(picked));
    const editor = await editorAt(file, line);
    assert.equal(editor.selection.active.character, source[line].indexOf('Text.rich'));
    // the Text outlined in place of the Box
    const row = screen.rows.findIndex((r) => r.includes('Count: 1'));
    screen = await until('the Text outlined on the screen', async () => {
      const s = await terminal.snapshot();
      return s.backgrounds?.[row]?.indexOf('#') === s.rows[row].indexOf('Count') && !s.backgrounds[0].includes('#') ? s : undefined;
    });
    // a second pick, the mode on still: the Box, by its border
    clickOn(terminal, screen, '╭─');
    await until('the Box picked', async () => (api.inspectorView.treeView.selection[0]?.name === 'Box' ? true : undefined));
    await editorAt(file, source.findIndex((l) => l.includes('child: Box(')));
    assert.equal(api.inspector.picking, true);
    // off: the outline gone from the screen, the selection from the view
    // (twk gives back the outline of before the pick mode, the Box's: the
    // selection taken away takes it)
    await vscode.commands.executeCommand('twk.inspector.stopPicking');
    assert.equal(api.inspector.picking, false);
    await until('the outline gone from the screen', async () => (outlined(await terminal.snapshot()) ? undefined : true));
    assert.deepEqual(api.inspectorView.treeView.selection, []);
    // the app's own again: a press reaches it (the counter takes none, so it shows as it was)
    assert.equal((await api.inspector.flags()).select, false);

    // where it was made, from the tree
    const text = inspected(api).find((n) => n.name === 'Text')!;
    await vscode.commands.executeCommand('twk.inspector.goToSource', text);
    const made = await until('the editor of where it was made', async () => {
      const e = vscode.window.activeTextEditor;
      return e?.document.uri.fsPath === file.fsPath && e.selection.active.line === line ? e : undefined;
    });
    assert.equal(made.selection.active.character, source[line].indexOf('Text.rich'));
    const counter = inspected(api).find((n) => n.name === 'Counter')!;
    await vscode.commands.executeCommand('twk.inspector.goToBuild', counter);
    const build = vscode.window.activeTextEditor!;
    assert.equal(build.selection.active.line, source.findIndex((l) => l.includes('Widget build(')));

    // the frame overlay drawn over the app, and taken away
    assert.equal((await api.inspector.setFlags({ overlay: true })).overlay, true);
    await shows(terminal, 'median', 'alternate');
    await api.inspector.setFlags({ overlay: false });
    await until('the overlay gone', async () => ((await terminal.snapshot()).rows.some((r) => r.includes('median')) ? undefined : true));

    // a hot reload: the tree shows the new code
    await edit(file, "'Count: '", "'Clicks: '");
    await shows(terminal, 'Clicks: 1', 'alternate');
    await inspectedText(api, 'Clicks: 1');

    terminal.type('q');
    await shows(terminal, 'the app went away', 'normal');
    await until('no app inspected', async () => (api.inspector.tree === undefined && api.inspectorView.treeView.message?.startsWith('No twk app') ? true : undefined));
  });
});

describe('the sequence log, recording and replay, the screen copied', () => {
  let api: Api;
  /** Where the recordings go: git ignores the project's .dart_tool. */
  const casts = path.join(project, '.dart_tool', 'twk_vscode_test', 'casts');

  before(async () => {
    api = await vscode.extensions.getExtension<Api>('twk.twk-vscode')!.activate();
    await Promise.all(api.hots().map((h) => h.stop()));
    fs.rmSync(casts, { recursive: true, force: true });
    fs.mkdirSync(casts, { recursive: true });
  });

  after(async () => {
    await Promise.all(api.hots().map((h) => h.stop()));
    api.players().forEach((p) => p.dispose());
    await vscode.commands.executeCommand('workbench.action.closeAllEditors');
  });

  it("logs the app's sequences and the keys in a webview of its own, copies the screen, records it and plays it back", async () => {
    const file = vscode.Uri.file(path.join(project, 'example', 'counter.dart'));
    await vscode.commands.executeCommand<number>('twk.runFile', file);
    const terminal = newest(api);
    await shows(terminal, 'Count: 0', 'alternate');

    // the log, of the active terminal, in its webview
    await vscode.commands.executeCommand('twk.showLog');
    const log = await until('its log', async () => api.logOf(terminal));
    await until('the log shown by its webview', async () => (log.shown && log.shown.rows > 0 ? true : undefined), 30000);
    terminal.type('\x1b[A');
    await shows(terminal, 'Count: 1', 'alternate');
    // the key, and what the app wrote for it (one cell: no synchronized update), in the webview's rows
    await until('the key and what it made in the webview', async () => {
      const last = log.shown?.last ?? [];
      const key = last.lastIndexOf('key Up');
      return key >= 0 && last.slice(key).includes('text "1"') ? true : undefined;
    }, 30000).catch((e: unknown) => {
      throw new Error(`${String(e)}; it shows ${JSON.stringify(log.shown)}`);
    });
    // what came before the log was opened: the app's start
    const names = log.entries().map((e) => e.name);
    assert.ok(names.some((n) => n.startsWith('DECSET 1049')), names.join('\n'));
    assert.ok(names.some((n) => /^frame \d+: /.test(n)), 'its first frame');
    assert.ok(names.some((n) => n.startsWith('DA1 query')), 'the probe');
    assert.ok(names.some((n) => n.startsWith('DA1 answer')), "the webview's answer");

    // the screen copied, to VS Code's clipboard
    const copied = await vscode.commands.executeCommand<string>('twk.copyScreen');
    assert.match(copied, /│ Count: 1 +│\n/);
    assert.ok(copied.startsWith('╭'), copied);
    assert.equal(await vscode.env.clipboard.readText(), copied);

    // recorded from now: Up, then stopped
    const cast = vscode.Uri.file(path.join(casts, 'counter.cast'));
    await vscode.commands.executeCommand('twk.record', cast);
    assert.ok(api.recordings.of(terminal), 'recorded');
    assert.match(terminal.title(), /● recording/);
    await until('the redraw recorded', async () => (fs.readFileSync(cast.fsPath, 'utf8').includes('Count: ') ? true : undefined), 30000);
    terminal.type('\x1b[A');
    await shows(terminal, 'Count: 2', 'alternate');
    await vscode.commands.executeCommand('twk.stopRecordings');
    assert.equal(api.recordings.of(terminal), undefined);
    assert.doesNotMatch(terminal.title(), /recording/);
    const lines = fs.readFileSync(cast.fsPath, 'utf8').trim().split('\n');
    assert.match(lines[0], /^\{"version":2,"width":\d+,"height":\d+,"timestamp":\d+,"idle_time_limit":2\.0,"title":"counter\.dart","env":\{"TERM":"xterm-256color"\}\}$/);
    assert.ok(lines.some((l) => l.includes('"i", "\\u001b[A"')), 'the key');
    terminal.type('q');
    await shows(terminal, 'the app went away', 'normal');

    // played back in a terminal of its own, at its size, to its end
    const player = await vscode.commands.executeCommand<Player>('twk.play', cast);
    assert.ok(player);
    assert.deepEqual(api.players(), [player]);
    await until('the end of the recording', async () => (player.state.frame === player.state.frames && !player.state.playing ? true : undefined), 30000);
    const replayed = await player.view.snapshot();
    assert.equal(replayed.buffer, 'alternate');
    assert.ok(replayed.rows.some((r) => r.includes('Count: 2')), replayed.rows.join('\n'));
    assert.equal(replayed.rows.length, JSON.parse(lines[0]).height);
    // a frame back, by the bar's message as the webview sends it, then on again
    player.control('back');
    await player.settled;
    await until('a frame back', async () => ((await player.view.snapshot()).rows.some((r) => r.includes('Count: 1')) ? true : undefined), 10000);
    player.control('step');
    await player.settled;
    await until('a frame on', async () => ((await player.view.snapshot()).rows.some((r) => r.includes('Count: 2')) ? true : undefined), 10000);
    // the replay's screen copied too, it being the active one now
    assert.match(await vscode.commands.executeCommand<string>('twk.copyScreen'), /Count: 2/);
    player.dispose();
    assert.deepEqual(api.players(), []);
  });
});

describe('twk terminal under Dart-Code', () => {
  let api: Api;
  const stops: { reason: string; threadId: number }[] = [];
  let isolateId: string | undefined;

  before(async function () {
    if (!vscode.extensions.getExtension('Dart-Code.dart-code')) {
      this.skip();
    }
    api = await vscode.extensions.getExtension<Api>('twk.twk-vscode')!.activate();
    vscode.debug.registerDebugAdapterTrackerFactory('dart', {
      createDebugAdapterTracker: () => ({
        onDidSendMessage: (m: { type: string; event?: string; body?: Record<string, unknown> }) => {
          if (m.type === 'event' && m.event === 'stopped' && m.body) {
            stops.push(m.body as { reason: string; threadId: number });
          }
          if (m.type === 'event' && m.event === 'dart.serviceExtensionAdded' && m.body?.extensionRPC === 'ext.twk.select') {
            isolateId = m.body.isolateId as string;
          }
        },
      }),
    });
  });

  it('stops at a breakpoint with the app on the twk terminal, which keeps its screen', async () => {
    const file = vscode.Uri.file(path.join(project, 'example', 'counter.dart'));
    // `setState` in `'up': () => setState(() => _n++),`: a breakpoint in the
    // closure, not in the map built by every build
    const breakpoint = new vscode.SourceBreakpoint(new vscode.Location(file, new vscode.Position(24, 18)));
    vscode.debug.addBreakpoints([breakpoint]);
    const started = await vscode.commands.executeCommand<boolean>('twk.debugFile', file);
    assert.equal(started, true);
    const session = vscode.debug.activeDebugSession;
    assert.ok(session);
    const terminal = newest(api);
    assert.equal(terminal.name, 'counter.dart');
    const shows = (text: string, buffer?: Snapshot['buffer']) =>
      until(`"${text}" on the ${buffer ?? 'any'} screen`, async () => {
        const s = await terminal.snapshot();
        return s.rows.some((r) => r.includes(text)) && (!buffer || s.buffer === buffer) ? s : undefined;
      });

    await shows('Count: 0', 'alternate');
    terminal.type('\x1b[A');
    const stop = await until('stop at the breakpoint', async () => stops.find((s) => s.reason === 'breakpoint'));
    const paused = await terminal.snapshot();
    assert.equal(paused.buffer, 'alternate');
    assert.ok(paused.rows.some((r) => r.includes('Count: 0')), paused.rows.join('\n'));

    vscode.debug.removeBreakpoints([breakpoint]);
    await session.customRequest('continue', { threadId: stop.threadId });
    const shown = await shows('Count: 1', 'alternate');

    // a cell of the terminal to the widget there: the inspector's
    // ext.twk.select, through Dart-Code's callService
    const x = shown.rows.findIndex((r) => r.includes('Count: 1'));
    const column = shown.rows[x].indexOf('Count');
    const select = await session.customRequest('callService', {
      method: 'ext.twk.select',
      params: { isolateId, x: String(column), y: String(x) },
    });
    assert.equal(typeof select.id, 'number', JSON.stringify(select));
    const node = await session.customRequest('callService', {
      method: 'ext.twk.properties',
      params: { isolateId, id: String(select.id) },
    });
    assert.match(node.name, /Text|RichText/, JSON.stringify(node));

    // the stop button: the shell puts the terminal back
    await vscode.debug.stopDebugging(session);
    await shows('the app went away', 'normal');
  });

  it('a save reloads the app debugged, a breakpoint set before hits after it, and a restart starts the session again', async () => {
    const file = scratchCounter();
    // `setState` in the Up key's closure, as above
    const breakpoint = new vscode.SourceBreakpoint(new vscode.Location(file, new vscode.Position(24, 18)));
    vscode.debug.addBreakpoints([breakpoint]);
    stops.length = 0;
    assert.equal(await vscode.commands.executeCommand<boolean>('twk.debugFile', file), true);
    const session = vscode.debug.activeDebugSession!;
    const terminal = newest(api);
    await shows(terminal, 'Count: 0', 'alternate');
    await status(api, 'running');

    await edit(file, "'Count: '", "'Clicks: '");
    await shows(terminal, 'Clicks: 0', 'alternate');
    await status(api, 'reloaded');

    terminal.type('\x1b[A');
    const stop = await until('stop at the breakpoint after the reload', async () => stops.find((s) => s.reason === 'breakpoint'));
    vscode.debug.removeBreakpoints([breakpoint]);
    await session.customRequest('continue', { threadId: stop.threadId });
    await shows(terminal, 'Clicks: 1', 'alternate');

    // the debug adapter has no restart of a Dart CLI app: the session ends
    // and the same launch starts again, the new app in the same terminal
    await vscode.commands.executeCommand('twk.hotRestart');
    const next = await until('a new debug session', async () => {
      const s = vscode.debug.activeDebugSession;
      return s && s.id !== session.id ? s : undefined;
    });
    await shows(terminal, 'Clicks: 0', 'alternate');
    assert.equal(newest(api), terminal, 'the same terminal');
    await status(api, 'running');
    await edit(file, "'Clicks: '", "'Taps: '");
    await shows(terminal, 'Taps: 0', 'alternate');

    await vscode.debug.stopDebugging(next);
    await shows(terminal, 'the app went away', 'normal');
    await until('no app reloaded', async () => (api.hots().length === 0 ? true : undefined));
  });
  it("inspects the app debugged over the extension's own VM service connection: its tree, followed, a pick, where a widget was made", async () => {
    const file = scratchCounter();
    assert.equal(await vscode.commands.executeCommand<boolean>('twk.debugFile', file), true);
    const session = vscode.debug.activeDebugSession!;
    const terminal = newest(api);
    await shows(terminal, 'Count: 0', 'alternate');
    await showInspector();
    await inspectedText(api, 'Count: 0');
    terminal.type('\x1b[A');
    await inspectedText(api, 'Count: 1');

    // a pick opens where the widget was made, twice; off, the outline gone
    const source = fs.readFileSync(file.fsPath, 'utf8').split('\n');
    await vscode.commands.executeCommand('twk.inspector.pick');
    const screen = await terminal.snapshot();
    clickOn(terminal, screen, 'Count: 1');
    await until('the widget picked', async () => (api.inspectorView.treeView.selection[0]?.name === 'Text' ? true : undefined));
    await editorAt(file, source.findIndex((l) => l.includes('Text.rich(')));
    clickOn(terminal, screen, '╭─');
    await until('the Box picked', async () => (api.inspectorView.treeView.selection[0]?.name === 'Box' ? true : undefined));
    await editorAt(file, source.findIndex((l) => l.includes('child: Box(')));
    await until('outlined', async () => (outlined(await terminal.snapshot()) ? true : undefined));
    await vscode.commands.executeCommand('twk.inspector.stopPicking');
    await until('the outline gone from the screen', async () => (outlined(await terminal.snapshot()) ? undefined : true));

    await vscode.debug.stopDebugging(session);
    await shows(terminal, 'the app went away', 'normal');
    await until('no app inspected', async () => (api.inspector.tree === undefined ? true : undefined));
  });

  it('F5 on a "type": "twk" configuration: debugged in a terminal of its own, with hot reload; its panel closed ends the session', async () => {
    const file = scratchCounter();
    const folder = vscode.workspace.getWorkspaceFolder(file);
    const before = api.terminals().length;
    // what F5 does with the configuration of launch.json
    assert.ok(await vscode.debug.startDebugging(folder, { type: 'twk', request: 'launch', name: 'twk: counter', program: file.fsPath }));
    const session = vscode.debug.activeDebugSession!;
    assert.equal(session.type, 'dart');
    assert.equal(session.configuration.console, 'debugConsole');
    assert.match(String(session.configuration.env.TWK_SHELL), /^unix:.*#[0-9a-f]+$/);
    assert.equal(api.terminals().length, before + 1, 'a new terminal');
    const terminal = newest(api);
    await shows(terminal, 'Count: 0', 'alternate');
    await status(api, 'running');
    await edit(file, "'Count: '", "'Clicks: '");
    await shows(terminal, 'Clicks: 0', 'alternate');

    const ended = new Promise<void>((resolve) => {
      const listening = vscode.debug.onDidTerminateDebugSession((s) => {
        if (s.id === session.id) {
          listening.dispose();
          resolve();
        }
      });
    });
    api.view(terminal)!.panel.dispose(); // as the person closing its tab
    await ended;
    await until('no app reloaded', async () => (api.hots().length === 0 ? true : undefined));
    assert.equal(fs.existsSync(addressFile), false, 'nothing written into the project');
  });

  it('a Dart configuration with "twkTerminal": true is debugged in a twk terminal too', async () => {
    const file = vscode.Uri.file(path.join(project, 'example', 'counter.dart'));
    const folder = vscode.workspace.getWorkspaceFolder(file);
    assert.ok(await vscode.debug.startDebugging(folder, { type: 'dart', request: 'launch', name: 'dart in twk', program: file.fsPath, twkTerminal: true }));
    const session = vscode.debug.activeDebugSession!;
    const terminal = newest(api);
    await shows(terminal, 'Count: 0', 'alternate');
    await vscode.debug.stopDebugging(session);
    await shows(terminal, 'the app went away', 'normal');
  });
});
