// The code lenses over a twk app's `main`: Run in twk Terminal and Debug in
// twk Terminal, next to Dart-Code's own Run | Debug over the same line,
// running the commands of the extension for that file. `twk.codeLens` turns
// them off.
import * as vscode from 'vscode';

import { findTwkMain } from '../core/main_find';
import { driverTestLines } from '../core/trace';

export class TwkMainLenses implements vscode.CodeLensProvider, vscode.Disposable {
  private readonly changed = new vscode.EventEmitter<void>();
  readonly onDidChangeCodeLenses = this.changed.event;
  private readonly listener: vscode.Disposable;

  constructor() {
    this.listener = vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration('twk.codeLens')) {
        this.changed.fire();
      }
    });
  }

  provideCodeLenses(document: vscode.TextDocument): vscode.CodeLens[] {
    if (!vscode.workspace.getConfiguration('twk').get<boolean>('codeLens', true)) {
      return [];
    }
    const main = findTwkMain(document.getText(), document.uri.fsPath);
    if (!main) {
      return [];
    }
    const at = new vscode.Range(main.line, main.column, main.line, main.column);
    return [
      new vscode.CodeLens(at, { title: 'Run in twk Terminal', command: 'twk.runFile', arguments: [document.uri] }),
      new vscode.CodeLens(at, { title: 'Debug in twk Terminal', command: 'twk.debugFile', arguments: [document.uri] }),
    ];
  }

  dispose(): void {
    this.listener.dispose();
    this.changed.dispose();
  }
}

/** Open Trace over each `driverTest(` of a test file: the traces a failed driver test kept (`twk.openTrace`). */
export class DriverTestLenses implements vscode.CodeLensProvider {
  provideCodeLenses(document: vscode.TextDocument): vscode.CodeLens[] {
    if (!vscode.workspace.getConfiguration('twk').get<boolean>('codeLens', true)) {
      return [];
    }
    return driverTestLines(document.getText()).map(
      (line) => new vscode.CodeLens(new vscode.Range(line, 0, line, 0), { title: 'Open Trace', command: 'twk.openTrace', arguments: [undefined, document.uri] }),
    );
  }
}
