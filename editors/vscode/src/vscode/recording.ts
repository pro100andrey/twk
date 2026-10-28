// The status bar while terminals are recorded.
import * as vscode from 'vscode';

import { Recordings } from '../app/recording';

/** The status bar while terminals are recorded: `● REC counter.dart`, a click stopping them. */
export class RecordingStatus implements vscode.Disposable {
  private readonly item = vscode.window.createStatusBarItem('twk.recording', vscode.StatusBarAlignment.Left, 51);
  private readonly listening: { dispose(): void };

  constructor(private readonly recordings: Recordings) {
    this.item.name = 'twk recording';
    this.item.command = 'twk.stopRecordings';
    this.item.color = new vscode.ThemeColor('statusBarItem.errorForeground');
    this.item.backgroundColor = new vscode.ThemeColor('statusBarItem.errorBackground');
    this.listening = recordings.onDidChange(() => this.show());
  }

  private show(): void {
    const all = this.recordings.all();
    if (all.length === 0) {
      this.item.hide();
      return;
    }
    this.item.text = `$(record) REC ${all.map((r) => r.screen.name).join(', ')}`;
    this.item.tooltip = 'twk: recording the terminal as asciicast; click to stop';
    this.item.show();
  }

  dispose(): void {
    this.listening.dispose();
    this.item.dispose();
  }
}
