// The webview panels: VS Code's panel as the [WebviewPanelPort] a view
// speaks its protocol over; a twk terminal's page, which loads xterm.js and
// webview/main.ts, and a sequence log's, webview/log.ts.
import * as vscode from 'vscode';

import { Emitter } from '../core/events';
import { WebviewPanelPort, WebviewTerminalView } from '../app/webview_view';
import { ToAppLogs } from '../webview/app_logs_protocol';
import { ToLog } from '../webview/log_protocol';
import { ToScreen } from '../webview/screen_protocol';
import { ToWebview } from '../webview/protocol';

/** A webview panel of [viewType] titled [title], beside the editor, its page [page], as the port its view speaks over. */
function openPanel<To>(viewType: string, title: string, extensionUri: vscode.Uri, page: (w: vscode.Webview) => string): WebviewPanelPort<To> {
  const panel = vscode.window.createWebviewPanel(
    viewType,
    title,
    { viewColumn: vscode.ViewColumn.Beside, preserveFocus: false },
    {
      enableScripts: true,
      retainContextWhenHidden: true,
      localResourceRoots: [vscode.Uri.joinPath(extensionUri, 'out', 'media'), vscode.Uri.joinPath(extensionUri, 'node_modules', '@xterm')],
    },
  );
  panel.webview.html = page(panel.webview);
  return portOf(panel);
}

/** [panel], whoever made it, as the port a view speaks over. */
function portOf<To>(panel: vscode.WebviewPanel): WebviewPanelPort<To> {
  const messages = new Emitter<unknown>();
  const disposes = new Emitter<void>();
  const listening = [
    panel.webview.onDidReceiveMessage((m: unknown) => messages.fire(m)),
    panel.onDidDispose(() => {
      disposes.fire();
      listening.forEach((d) => d.dispose());
      messages.dispose();
      disposes.dispose();
    }),
  ];
  return {
    post: (m) => Promise.resolve(panel.webview.postMessage(m)),
    get active() {
      return panel.active;
    },
    setTitle: (title) => (panel.title = title),
    reveal: () => panel.reveal(),
    dispose: () => panel.dispose(),
    onMessage: messages.event,
    onDispose: disposes.event,
  };
}

/** A new panel titled [title], beside the editor, and the view of its webview: a twk terminal's, or a recording's played back. */
export function openWebviewTerminal(title: string, extensionUri: vscode.Uri): WebviewTerminalView {
  return new WebviewTerminalView(openPanel<ToWebview>('twk.terminal', title, extensionUri, (w) => html(w, extensionUri)));
}

/** A new panel titled [title] for a sequence log (webview/log.ts). */
export function openLogPanel(title: string, extensionUri: vscode.Uri): WebviewPanelPort<ToLog> {
  return openPanel<ToLog>('twk.sequenceLog', title, extensionUri, (w) => logPage(w, extensionUri));
}

/** A new panel titled [title] for the apps' log (webview/app_logs.ts). */
export function openAppLogsPanel(title: string, extensionUri: vscode.Uri): WebviewPanelPort<ToAppLogs> {
  return openPanel<ToAppLogs>('twk.appLogs', title, extensionUri, (w) => logPage(w, extensionUri, 'app_logs.js'));
}

/**
 * Fills [panel], the editor VS Code made for a screen file, with the page of
 * webview/screen.ts, and returns the port its editor speaks over.
 */
export function fillScreenPanel(panel: vscode.WebviewPanel, extensionUri: vscode.Uri): WebviewPanelPort<ToScreen> {
  panel.webview.options = { enableScripts: true, localResourceRoots: [vscode.Uri.joinPath(extensionUri, 'out', 'media')] };
  panel.webview.html = logPage(panel.webview, extensionUri, 'screen.js', screenStyle, '<header id="bar"></header><main id="screens"></main>');
  return portOf<ToScreen>(panel);
}

/** The screen file editor's look: a grid of cells in the terminal's font and colours. */
const screenStyle = `
html, body { margin: 0; padding: 0; }
body { --twk-fg: var(--vscode-terminal-foreground, var(--vscode-editor-foreground)); --twk-bg: var(--vscode-terminal-background, var(--vscode-editor-background)); font-family: var(--vscode-font-family); font-size: var(--vscode-font-size); color: var(--vscode-foreground); background: var(--vscode-editor-background); }
#bar { position: sticky; top: 0; z-index: 1; display: flex; flex-wrap: wrap; gap: 6px 14px; align-items: center; padding: 6px 8px; background: var(--vscode-editor-background); border-bottom: 1px solid var(--vscode-panel-border, transparent); }
#bar label { display: inline-flex; gap: 4px; align-items: center; }
#bar button { color: var(--vscode-button-foreground); background: var(--vscode-button-background); border: none; padding: 3px 10px; cursor: pointer; }
#bar button:hover { background: var(--vscode-button-hoverBackground); }
.status { opacity: 0.8; }
#screens { padding: 8px; }
.screens { display: flex; flex-wrap: wrap; gap: 16px; }
.caption { opacity: 0.7; margin-bottom: 2px; }
.grid { display: inline-block; font-family: var(--vscode-editor-font-family, monospace); font-size: var(--vscode-editor-font-size); line-height: 1.25; background: var(--twk-bg); color: var(--twk-fg); }
.grid .row { display: flex; white-space: pre; height: 1.25em; }
.grid .row span { display: inline-block; width: 1ch; overflow: visible; }
.grid .row span.wide { width: 2ch; }
.grid .row span.changed { outline: 1px solid var(--vscode-editorError-foreground, red); outline-offset: -1px; }
.grid .row span.cursor { box-shadow: inset 0 -2px var(--vscode-terminalCursor-foreground, currentColor); }
.legend, .diff { margin-top: 12px; font-family: var(--vscode-editor-font-family, monospace); }
.legend .sample { display: inline-block; min-width: 1.5ch; text-align: center; }
.bad { color: var(--vscode-editorError-foreground, red); padding: 8px; }
`;

const nonceOf = () => [...crypto.getRandomValues(new Uint8Array(16))].map((b) => b.toString(16).padStart(2, '0')).join('');

/** The log's look, in VS Code's colours and font. */
const logStyle = `
html, body { height: 100%; margin: 0; padding: 0; }
body { display: flex; flex-direction: column; font-family: var(--vscode-font-family); font-size: var(--vscode-font-size); color: var(--vscode-foreground); background: var(--vscode-editor-background); }
#bar { display: flex; flex-wrap: wrap; gap: 6px 12px; align-items: center; padding: 6px 8px; border-bottom: 1px solid var(--vscode-panel-border, transparent); }
#bar label { display: inline-flex; gap: 4px; align-items: center; white-space: nowrap; }
#bar button { color: var(--vscode-button-foreground); background: var(--vscode-button-background); border: none; padding: 3px 10px; cursor: pointer; }
#bar button:hover { background: var(--vscode-button-hoverBackground); }
#bar input[type=text] { color: var(--vscode-input-foreground); background: var(--vscode-input-background); border: 1px solid var(--vscode-input-border, transparent); padding: 2px 4px; min-width: 10em; }
#bar select { color: var(--vscode-dropdown-foreground); background: var(--vscode-dropdown-background); border: 1px solid var(--vscode-dropdown-border, transparent); }
#status { opacity: 0.8; }
#log { flex: 1; overflow: auto; font-family: var(--vscode-editor-font-family); font-size: var(--vscode-editor-font-size); }
.row { display: grid; grid-template-columns: 6em 1.5em minmax(16em, 1fr) minmax(10em, 1fr); gap: 0 8px; padding: 0 8px; white-space: pre; }
.row > span { overflow: hidden; text-overflow: ellipsis; }
.row.child { padding-left: 3em; opacity: 0.9; }
.row.frame { cursor: pointer; font-weight: 600; }
.row.note { font-style: italic; opacity: 0.8; }
.row.in .dir { color: var(--vscode-terminal-ansiGreen, green); }
.row.out .dir { color: var(--vscode-terminal-ansiBlue, blue); }
.raw { opacity: 0.7; }
.row.stacked { cursor: pointer; }
.row.stacked:hover { background: var(--vscode-list-hoverBackground); }
#log .row.debug, #log .row.info, #log .row.warning, #log .row.error, #log .row.note { grid-template-columns: 6.5em 6em 10em minmax(16em, 1fr); }
.row .time, .row .app { opacity: 0.7; }
.row.debug .lvl { opacity: 0.6; }
.row.info .lvl { color: var(--vscode-terminal-ansiCyan, cyan); }
.row.warning .lvl, .row.warning .msg { color: var(--vscode-editorWarning-foreground, orange); }
.row.error .lvl, .row.error .msg { color: var(--vscode-editorError-foreground, red); font-weight: 600; }
.row .msg { white-space: pre-wrap; }
.frame { padding: 0 8px 0 calc(6.5em + 6em + 10em + 40px); opacity: 0.75; white-space: pre; overflow: hidden; text-overflow: ellipsis; }
.frame.open { cursor: pointer; text-decoration: underline; color: var(--vscode-textLink-foreground); opacity: 1; }
.level.debug { opacity: 0.7; }
.row:hover { background: var(--vscode-list-hoverBackground); }
`;

/** The log's page: its module, styled by VS Code's colours. */
function logPage(w: vscode.Webview, extensionUri: vscode.Uri, script = 'log.js', style = logStyle, content = '<header id="bar"></header>\n<main id="log"></main>'): string {
  const uri = (...p: string[]) => w.asWebviewUri(vscode.Uri.joinPath(extensionUri, ...p)).toString();
  const nonce = nonceOf();
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${w.cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}' ${w.cspSource};">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>${style}</style>
</head>
<body>
${content}
<script nonce="${nonce}" type="module" src="${uri('out', 'media', 'webview', script)}"></script>
</body>
</html>`;
}

/**
 * The page: xterm.js and its addons, then the webview's module. The image
 * addon decodes sixel in WebAssembly ('wasm-unsafe-eval') and iTerm2's
 * images through blob: URLs.
 */
function html(w: vscode.Webview, extensionUri: vscode.Uri): string {
  const uri = (...p: string[]) => w.asWebviewUri(vscode.Uri.joinPath(extensionUri, ...p)).toString();
  const nonce = nonceOf();
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${w.cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}' 'wasm-unsafe-eval' ${w.cspSource}; img-src ${w.cspSource} blob: data:; font-src ${w.cspSource};">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="stylesheet" href="${uri('node_modules', '@xterm', 'xterm', 'css', 'xterm.css')}">
<style>html, body { height: 100%; margin: 0; padding: 0; overflow: hidden; } #terminal { height: 100%; padding: 4px; box-sizing: border-box; }</style>
</head>
<body>
<div id="terminal"></div>
<script nonce="${nonce}" src="${uri('node_modules', '@xterm', 'xterm', 'lib', 'xterm.js')}"></script>
<script nonce="${nonce}" src="${uri('node_modules', '@xterm', 'addon-fit', 'lib', 'addon-fit.js')}"></script>
<script nonce="${nonce}" src="${uri('node_modules', '@xterm', 'addon-image', 'lib', 'addon-image.js')}"></script>
<script nonce="${nonce}" type="module" src="${uri('out', 'media', 'webview', 'main.js')}"></script>
</body>
</html>`;
}
