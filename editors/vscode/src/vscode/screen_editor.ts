// The custom editor of screen files (twk_test's matchesScreenFile goldens):
// a read-only view of the file drawn with its colours, the screen a failed
// test left beside it against it, Accept Actual. Chosen for a file with
// "Open With..." (twk: Open Screen File as a twk Screen), as the default of
// none: a golden stays text in a diff.
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as vscode from 'vscode';

import { GoldenEditor, GoldenFiles, actualSuffix } from '../app/goldens';
import { fillScreenPanel } from './panel';

export const screenFileViewType = 'twk.screenFile';

/** The files of the disk, read as the editor shows them. */
export const diskFiles: GoldenFiles = {
  read: async (p) => {
    try {
      return await fs.readFile(p, 'utf8');
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === 'ENOENT') {
        return undefined;
      }
      throw e;
    }
  },
  modified: async (p) => {
    try {
      return (await fs.stat(p)).mtimeMs;
    } catch {
      return undefined;
    }
  },
  write: (p, text) => fs.writeFile(p, text),
  remove: (p) => fs.rm(p, { force: true }),
};

export class ScreenFileEditors implements vscode.CustomTextEditorProvider {
  constructor(private readonly extensionUri: vscode.Uri) {}

  resolveCustomTextEditor(document: vscode.TextDocument, panel: vscode.WebviewPanel): void {
    const file = document.uri.fsPath;
    const editor = new GoldenEditor(fillScreenPanel(panel, this.extensionUri), diskFiles, file, path.basename(file), (m) => void vscode.window.showInformationMessage(m));
    const watcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(path.dirname(file), `${path.basename(file)}{,${actualSuffix}}`));
    const refresh = () => void editor.refresh();
    const listening = [
      watcher,
      watcher.onDidChange(refresh),
      watcher.onDidCreate(refresh),
      watcher.onDidDelete(refresh),
      vscode.workspace.onDidChangeTextDocument((e) => e.document === document && refresh()),
    ];
    panel.onDidDispose(() => listening.forEach((d) => d.dispose()));
  }
}
