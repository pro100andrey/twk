// The frames panel's webview view (`twk.frames`, in the panel beside
// Terminal and Problems) as the [FramesView] of app/frames.ts: the page of
// webview/frames.ts, spoken to in the messages of webview/frames_protocol.ts.
// What was shown last is sent again to a page that loaded again (the view
// was hidden and its page dropped).
import * as vscode from 'vscode';

import { FramesView } from '../app/frames';
import { Emitter } from '../core/events';
import { Metric } from '../core/frames';
import { FramesState, ToFrames, isFromFrames } from '../webview/frames_protocol';
import { logPage } from './panel';

/** The look of the bars: each a button as high as its share of the tallest, the slowest marked. */
const framesStyle = `
html, body { height: 100%; margin: 0; padding: 0; }
body { display: flex; flex-direction: column; font-family: var(--vscode-font-family); font-size: var(--vscode-font-size); color: var(--vscode-foreground); background: var(--vscode-panel-background, var(--vscode-editor-background)); }
#bar { display: flex; flex-wrap: wrap; gap: 6px 12px; align-items: center; padding: 4px 8px; border-bottom: 1px solid var(--vscode-panel-border, transparent); }
#bar label { display: inline-flex; gap: 4px; align-items: center; }
#bar button { color: var(--vscode-button-foreground); background: var(--vscode-button-background); border: none; padding: 2px 10px; cursor: pointer; }
#bar button:hover { background: var(--vscode-button-hoverBackground); }
#summary { opacity: 0.85; }
#chart { flex: 1; min-height: 0; display: flex; align-items: stretch; gap: 1px; padding: 6px 8px; overflow-x: auto; }
.message { opacity: 0.7; padding: 4px 0; }
button.bar { flex: 0 0 6px; min-width: 4px; display: flex; align-items: flex-end; padding: 0; border: none; background: transparent; cursor: pointer; }
button.bar:hover { background: var(--vscode-list-hoverBackground); }
button.bar:focus-visible { outline: 1px solid var(--vscode-focusBorder); }
.fill { display: block; width: 100%; background: var(--vscode-charts-blue, steelblue); }
.fill.slowest { background: var(--vscode-charts-orange, orange); }
.fill.unknown { background: var(--vscode-disabledForeground, gray); opacity: 0.5; }
`;

export class VsCodeFramesView implements FramesView, vscode.WebviewViewProvider, vscode.Disposable {
  static readonly id = 'twk.frames';
  private view: vscode.WebviewView | undefined;
  private last: FramesState | undefined;
  private readonly visibility = new Emitter<boolean>();
  readonly onVisible = this.visibility.event;
  private readonly metrics = new Emitter<Metric>();
  readonly onMetric = this.metrics.event;
  private readonly picks = new Emitter<number>();
  readonly onPick = this.picks.event;
  private readonly clears = new Emitter<void>();
  readonly onClear = this.clears.event;
  private readonly registration: vscode.Disposable;
  private listening: vscode.Disposable[] = [];

  constructor(private readonly extensionUri: vscode.Uri) {
    this.registration = vscode.window.registerWebviewViewProvider(VsCodeFramesView.id, this, { webviewOptions: { retainContextWhenHidden: true } });
  }

  get visible(): boolean {
    return this.view?.visible ?? false;
  }

  resolveWebviewView(view: vscode.WebviewView): void {
    this.listening.forEach((d) => d.dispose());
    this.view = view;
    view.webview.options = { enableScripts: true, localResourceRoots: [vscode.Uri.joinPath(this.extensionUri, 'out', 'media')] };
    view.webview.html = logPage(view.webview, this.extensionUri, 'frames.js', framesStyle, '<header id="bar"></header><main id="chart"></main>');
    this.listening = [
      view.webview.onDidReceiveMessage((m: unknown) => {
        if (!isFromFrames(m)) {
          return;
        }
        if (m.type === 'ready') {
          this.send();
        } else if (m.type === 'metric') {
          this.metrics.fire(m.metric);
        } else if (m.type === 'pick') {
          this.picks.fire(m.frame);
        } else {
          this.clears.fire();
        }
      }),
      view.onDidChangeVisibility(() => this.visibility.fire(view.visible)),
      view.onDidDispose(() => {
        if (this.view === view) {
          this.view = undefined;
          this.visibility.fire(false);
        }
      }),
    ];
    this.visibility.fire(view.visible);
  }

  show(state: FramesState): void {
    this.last = state;
    this.send();
  }

  private send(): void {
    if (this.view && this.last) {
      const message: ToFrames = { type: 'state', state: this.last };
      void this.view.webview.postMessage(message);
    }
  }

  /** Brings the view to the front of the panel. */
  focus(): Thenable<unknown> {
    return vscode.commands.executeCommand(`${VsCodeFramesView.id}.focus`);
  }

  dispose(): void {
    this.listening.forEach((d) => d.dispose());
    this.registration.dispose();
    [this.visibility, this.metrics, this.picks, this.clears].forEach((e) => e.dispose());
  }
}
