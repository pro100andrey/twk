// The status bar item of the active twk terminal's size, profile and aids.
import * as vscode from 'vscode';

import { TerminalStatusSink } from '../app/ports';

/** `twk 44x7 · xterm.js · overlay`, a click opening twk: Choose twk Terminal Capabilities. */
export class TerminalStatusItem implements TerminalStatusSink, vscode.Disposable {
  private readonly item = vscode.window.createStatusBarItem('twk.terminal', vscode.StatusBarAlignment.Left, 49);

  constructor() {
    this.item.name = 'twk terminal';
    this.item.command = 'twk.chooseProfile';
  }

  /** What it shows now; undefined while hidden. */
  text: string | undefined;

  show(text: string | undefined, tooltip?: string): void {
    this.text = text;
    if (text === undefined) {
      this.item.hide();
      return;
    }
    this.item.text = text;
    this.item.tooltip = tooltip;
    this.item.show();
  }

  dispose(): void {
    this.item.dispose();
  }
}
