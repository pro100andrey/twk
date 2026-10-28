// The [Desktop] of VS Code: what an app asks of the editor through its twk
// terminal (core/emulation.ts's requests, as its capabilities allow), done
// with the VS Code API. A notification as VS Code's, the progress of each
// terminal's app in a status bar item of its own, the clipboard VS Code's,
// a link opened outside it (app/terminal.ts lets only http, https and
// mailto through).
import * as vscode from 'vscode';

import { progressText } from '../core/emulation';
import { Desktop } from '../app/ports';

export class VsCodeDesktop implements Desktop, vscode.Disposable {
  /** The status bar item of each terminal's app's progress, by its terminal. */
  private readonly progresses = new Map<object, vscode.StatusBarItem>();
  private items = 0;

  notify(source: string, title: string, body: string): void {
    void vscode.window.showInformationMessage(body === '' ? title : `${title}: ${body}`, { detail: source });
  }

  progress(owner: object, source: string, state: number, percent: number | null): void {
    const text = progressText(source, state, percent);
    let item = this.progresses.get(owner);
    if (text === undefined) {
      item?.dispose();
      this.progresses.delete(owner);
      return;
    }
    if (!item) {
      item = vscode.window.createStatusBarItem(`twk.progress.${this.items++}`, vscode.StatusBarAlignment.Left, 49);
      item.name = `twk progress of ${source}`;
      this.progresses.set(owner, item);
    }
    item.text = text;
    item.backgroundColor = state === 2 ? new vscode.ThemeColor('statusBarItem.errorBackground') : undefined;
    item.show();
  }

  /** What the status bar says of the progress of the app in the terminal [owner]; undefined, nothing. */
  progressOf(owner: object): string | undefined {
    return this.progresses.get(owner)?.text;
  }

  writeClipboard(text: string): void {
    void vscode.env.clipboard.writeText(text);
  }

  openLink(uri: string): void {
    void vscode.env.openExternal(vscode.Uri.parse(uri, true));
  }

  dispose(): void {
    this.progresses.forEach((i) => i.dispose());
    this.progresses.clear();
  }
}
