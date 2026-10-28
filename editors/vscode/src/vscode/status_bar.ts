// The [StatusSink] of the status bar: the status of the last reload or
// restart while an app is reloaded by the extension; a click shows the
// output, where a failed reload's errors are.
import * as vscode from 'vscode';

import { HotStatus, describe } from '../core/hot';
import { StatusSink } from '../app/ports';

const icons: Record<HotStatus['state'], string> = {
  running: '$(flame)',
  reloading: '$(sync~spin)',
  reloaded: '$(check)',
  failed: '$(error)',
  restarting: '$(debug-restart)',
  ended: '$(circle-slash)',
};

export class StatusBar implements StatusSink, vscode.Disposable {
  private readonly item = vscode.window.createStatusBarItem('twk.hot', vscode.StatusBarAlignment.Left, 50);

  constructor() {
    this.item.name = 'twk hot reload';
    this.item.command = 'twk.showOutput';
  }

  /** What it shows now. */
  get text(): string {
    return this.item.text;
  }

  show(s: HotStatus, appsRunning: boolean): void {
    this.item.text = `${icons[s.state]} ${describe(s)}`;
    this.item.tooltip = s.state === 'failed' ? `${s.errors}\n\nThe app runs on with the code it had.` : undefined;
    this.item.backgroundColor = s.state === 'failed' ? new vscode.ThemeColor('statusBarItem.errorBackground') : undefined;
    if (appsRunning || s.state === 'ended') {
      this.item.show();
    }
  }

  dispose(): void {
    this.item.dispose();
  }
}
