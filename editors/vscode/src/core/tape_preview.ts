// The preview of a tape: the stills its Screenshots wrote and the end (the
// animated SVG of an Output), a strip of frames in order, each going to the
// statement that made it on a click. Pure: the HTML for a webview.

import { escapeHtml } from './html';

/** One frame of the strip. */
export interface PreviewFrame {
  /** What it is called: the file's name. */
  readonly title: string;
  /** The `src` of its image (a webview URI), or undefined when the file was not written yet. */
  readonly src: string | undefined;
  /** The statement's line (from 0) a click goes to. */
  readonly line: number;
  /** Why it has no image, where it is not that the file is missing. */
  readonly note?: string;
}


/** The message a click posts. */
export interface PreviewClick {
  readonly line: number;
}

/** The page: [frames] in a strip under a CSP that allows images from [cspSource] and the one script, [nonce]'s. */
export function previewHtml(name: string, frames: readonly PreviewFrame[], cspSource: string, nonce: string): string {
  const body =
    frames.length === 0
      ? '<p>This tape writes no Screenshot and no .svg Output: nothing to preview.</p>'
      : frames
          .map(
            (f) =>
              `<figure data-line="${f.line}" tabindex="0" title="Go to line ${f.line + 1}">` +
              (f.src === undefined ? `<div class="missing">${f.note === undefined ? 'not written yet: Run the tape' : escapeHtml(f.note)}</div>` : `<img src="${escapeHtml(f.src)}" alt="${escapeHtml(f.title)}">`) +
              `<figcaption>${escapeHtml(f.title)} (line ${f.line + 1})</figcaption></figure>`,
          )
          .join('');
  return `<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src ${cspSource}; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'">
<title>${escapeHtml(name)}</title>
<style>body{font-family:var(--vscode-font-family);color:var(--vscode-foreground);padding:8px}
.strip{display:flex;flex-wrap:nowrap;gap:12px;overflow-x:auto;align-items:flex-start}
figure{margin:0;flex:none;cursor:pointer;border:1px solid var(--vscode-panel-border);padding:6px}
figure:hover,figure:focus{border-color:var(--vscode-focusBorder)}
img{display:block;max-height:70vh}figcaption,.missing{font-size:12px;margin-top:4px}</style></head>
<body><div class="strip">${body}</div>
<script nonce="${nonce}">const vscode=acquireVsCodeApi();
for(const f of document.querySelectorAll('figure'))
  {const go=()=>vscode.postMessage({line:Number(f.dataset.line)});f.addEventListener('click',go);
   f.addEventListener('keydown',e=>{if(e.key==='Enter')go();});}</script></body></html>`;
}

/** A click message from the page, checked. */
export function previewClick(message: unknown): PreviewClick | undefined {
  if (typeof message === 'object' && message !== null && 'line' in message && typeof message.line === 'number' && Number.isInteger(message.line) && message.line >= 0) {
    return { line: message.line };
  }
  return undefined;
}
