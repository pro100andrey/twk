// The packaged extension, installed from its .vsix into an extensions
// directory of its own (runInstalled.ts), not the source tree: it activates
// from what the .vsix ships, registers every command its package.json
// contributes, and runs a twk app in a terminal whose webview loads xterm.js
// from the four files the .vsix holds.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';

import * as vscode from 'vscode';

import type { Api } from '../../vscode/extension';


describe('the twk extension installed from its .vsix', () => {
  let api: Api;
  let ext: vscode.Extension<Api>;

  before(() => {
    const found = vscode.extensions.getExtension<Api>('twk.twk-vscode');
    assert.ok(found, 'the extension is installed');
    ext = found;
  });

  after(async () => {
    await Promise.all(api.hots().map((h) => h.stop()));
  });

  it('is the installed copy: in the extensions directory, with out/ and the xterm files and nothing of the sources', () => {
    const dir = process.env.TWK_EXTENSIONS_DIR;
    assert.ok(dir, 'TWK_EXTENSIONS_DIR');
    assert.ok(fs.realpathSync(ext.extensionPath).startsWith(fs.realpathSync(dir)), ext.extensionPath);
    assert.ok(fs.existsSync(path.join(ext.extensionPath, 'out', 'vscode', 'extension.js')));
    for (const f of ['lib/xterm.js', 'css/xterm.css']) {
      assert.ok(fs.existsSync(path.join(ext.extensionPath, 'node_modules', '@xterm', 'xterm', f)), f);
    }
    assert.ok(fs.existsSync(path.join(ext.extensionPath, 'node_modules', '@xterm', 'addon-fit', 'lib', 'addon-fit.js')));
    assert.ok(fs.existsSync(path.join(ext.extensionPath, 'node_modules', '@xterm', 'addon-image', 'lib', 'addon-image.js')));
    assert.ok(!fs.existsSync(path.join(ext.extensionPath, 'src')), 'no sources');
  });

  it('activates (the workspace holds a pubspec.yaml) and registers every command it contributes', async () => {
    api = await ext.activate();
    assert.ok(ext.isActive);
    const contributed = (ext.packageJSON.contributes.commands as { command: string }[]).map((c) => c.command);
    const registered = new Set(await vscode.commands.getCommands(true));
    assert.deepEqual(
      contributed.filter((c) => !registered.has(c)),
      [],
      'commands contributed and not registered',
    );
  });

  it('runs a twk app in its terminal: the webview draws it with the xterm.js the .vsix ships, keys reach it', async () => {
    const root = vscode.workspace.workspaceFolders?.[0].uri.fsPath;
    assert.ok(root, 'a workspace');
    const counter = vscode.Uri.file(path.join(root, 'example', 'counter.dart'));
    await vscode.commands.executeCommand('twk.runFile', counter);
    const terminal = api.terminals().at(-1);
    assert.ok(terminal, 'a twk terminal');
    const deadline = Date.now() + 90000;
    const shown = async (text: string) => {
      for (;;) {
        const s = await terminal.snapshot();
        if (s.rows.some((r) => r.includes(text))) {
          return s;
        }
        if (Date.now() > deadline) {
          throw new Error(`no "${text}" in the terminal:\n${s.rows.join('\n')}`);
        }
        await new Promise((r) => setTimeout(r, 100));
      }
    };
    const first = await shown('Count: 0');
    assert.equal(first.buffer, 'alternate');
    terminal.type('\x1b[A');
    await shown('Count: 1');
    terminal.type('q');
    await shown('the app went away');
  });
});
