// The terminal report in the editor: a panel with what the twk terminal
// tells an app and answers as the settings have it, and the project's part
// from `twk doctor --json`. The work is core/report.ts's (what to say) and
// app/report.ts's (asking twk doctor).
import * as fs from 'node:fs';
import * as path from 'node:path';
import { randomBytes } from 'node:crypto';

import * as vscode from 'vscode';

import { Doctor } from '../app/report';
import { Log } from '../app/ports';
import { startNodeProcess } from '../core/process';
import { projectOf } from '../core/project';
import { ProjectResult, isRefresh, reportHtml, terminalReportOf } from '../core/report';
import { Configuration } from './settings';

/** How long `twk doctor` may take; its connects to the project's services time out at a few seconds each. */
const doctorTimeoutMs = 60_000;

/** The Dart project to report on: the active editor's file's, else the first folder open that has one. */
function projectToReport(): string | undefined {
  const file = vscode.window.activeTextEditor?.document.uri;
  const fromFile = file?.scheme === 'file' ? projectOf(file.fsPath) : undefined;
  if (fromFile !== undefined) {
    return fromFile;
  }
  for (const folder of vscode.workspace.workspaceFolders ?? []) {
    if (fs.existsSync(path.join(folder.uri.fsPath, 'pubspec.yaml'))) {
      return folder.uri.fsPath;
    }
  }
  return undefined;
}

/** The command `twk.showTerminalReport` (its result is the panel, for the tests). */
export function registerReport(context: vscode.ExtensionContext, settings: Configuration, log: Log): void {
  const doctor = new Doctor({
    start: startNodeProcess,
    command: () => vscode.workspace.getConfiguration('twk').get<string[]>('tape.command', ['dart', 'run', 'twk_dev:twk']),
    env: process.env,
    log,
    timeoutMs: doctorTimeoutMs,
  });
  let panel: vscode.WebviewPanel | undefined;
  let project: ProjectResult = { kind: 'none' };

  const render = () => {
    if (panel) {
      panel.webview.html = reportHtml(terminalReportOf(settings.capabilities(), settings.switches()), project, randomBytes(16).toString('hex'));
    }
  };
  const ask = async () => {
    const dir = projectToReport();
    project = dir === undefined ? { kind: 'none' } : await vscode.window.withProgress({ location: vscode.ProgressLocation.Window, title: 'twk doctor' }, () => doctor.project(dir));
    render();
  };

  context.subscriptions.push(
    { dispose: () => panel?.dispose() },
    // a setting of the terminal changed: its part is said again, the project's not asked again
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration('twk.terminal')) {
        render();
      }
    }),
    vscode.commands.registerCommand('twk.showTerminalReport', async () => {
      if (!panel) {
        const created = vscode.window.createWebviewPanel('twk.terminalReport', 'twk terminal report', { viewColumn: vscode.ViewColumn.Beside, preserveFocus: true }, { enableScripts: true });
        created.onDidDispose(() => (panel = undefined));
        created.webview.onDidReceiveMessage((m: unknown) => {
          if (isRefresh(m)) {
            void ask();
          }
        });
        panel = created;
      }
      render();
      panel.reveal(undefined, true);
      await ask();
      return panel;
    }),
  );
}
