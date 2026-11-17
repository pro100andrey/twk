// The trace viewer's page: the steps of a driver trace as a list (passed,
// failed), the screen before, between and after the selected step drawn by
// xterm.js from the cast's events with the target's cells outlined, and the
// step's facts, tree, log and sequences in tabs. The extension (app/
// trace_viewer.ts) tells it the steps and the cast once and the detail of
// each step as it is selected. Compiled with the terminal's webview
// (tsconfig.webview.json); xterm.js is the script the page loads before it.
import type { Terminal as TerminalType } from '@xterm/xterm';

import type { WireEvent } from '../core/trace.js';
import { FromTrace, StepDetail, StepRow, isToTrace } from './trace_protocol.js';

declare const Terminal: typeof TerminalType;
declare function acquireVsCodeApi(): { postMessage(message: FromTrace): void };

const vscode = acquireVsCodeApi();
const css = getComputedStyle(document.documentElement);
const color = (name: string, fallback: string) => css.getPropertyValue(name).trim() || fallback;
const byId = (id: string): HTMLElement => {
  const e = document.getElementById(id);
  if (!e) {
    throw new Error(`no #${id} in the page`);
  }
  return e;
};
const stepsList = byId('steps');
const screenBar = byId('screenbar');
const host = byId('terminal');
const outline = byId('outline');
const tabsBar = byId('tabs');
const detailPane = byId('detail');

const term = new Terminal({
  fontFamily: color('--vscode-editor-font-family', 'monospace'),
  fontSize: Number.parseInt(color('--vscode-editor-font-size', '14'), 10) || 14,
  cursorBlink: false,
  disableStdin: true,
  scrollback: 0,
});
term.open(host);

let events: readonly WireEvent[] = [];
let rows: readonly StepRow[] = [];
let columns = 80;
let lines = 24;
let selected = -1;
let place: { readonly kind: 'before' | 'after' | 'frame'; readonly frame?: number } = { kind: 'after' };
const details = new Map<number, StepDetail>();
let tab: 'facts' | 'tree' | 'log' | 'sequences' = 'facts';

function element<K extends keyof HTMLElementTagNameMap>(tag: K, props: Partial<HTMLElementTagNameMap[K]> = {}, ...children: (Node | string)[]): HTMLElementTagNameMap[K] {
  const e = Object.assign(document.createElement(tag), props);
  e.append(...children);
  return e;
}

/** The terminal reset and the cast's events up to and including [upTo] written to it. */
function draw(upTo: number): void {
  term.reset();
  term.resize(columns, lines);
  let text = '';
  for (const [index, code, data] of events) {
    if (index > upTo) {
      break;
    }
    if (code === 'r') {
      term.write(text);
      text = '';
      const m = /^(\d+)x(\d+)$/.exec(data);
      if (m) {
        term.resize(Number(m[1]), Number(m[2]));
      }
    } else {
      text += data;
    }
  }
  term.write(text, placeOutline);
}

/** The target's cells outlined, over the screen's cells. */
function placeOutline(): void {
  const rect = rows[selected]?.outline;
  const screen = host.querySelector('.xterm-screen');
  if (!rect || !screen || term.cols === 0 || term.rows === 0) {
    outline.hidden = true;
    return;
  }
  const w = screen.clientWidth / term.cols;
  const h = screen.clientHeight / term.rows;
  outline.hidden = false;
  outline.style.left = `${(screen as HTMLElement).offsetLeft + 4 + rect.x * w}px`;
  outline.style.top = `${(screen as HTMLElement).offsetTop + 4 + rect.y * h}px`;
  outline.style.width = `${rect.width * w}px`;
  outline.style.height = `${rect.height * h}px`;
}

function showScreen(): void {
  const row = rows[selected];
  if (!row) {
    return;
  }
  const upTo = place.kind === 'before' ? row.before : place.kind === 'after' ? row.after : (row.frames.find((f) => f.frame === place.frame)?.upTo ?? row.after);
  draw(upTo);
  const buttons: HTMLButtonElement[] = [];
  const add = (label: string, p: typeof place, on: boolean, title: string) => {
    const b = element('button', { textContent: label, title, className: on ? 'on' : '' });
    b.addEventListener('click', () => {
      place = p;
      showScreen();
    });
    buttons.push(b);
  };
  add('before', { kind: 'before' }, place.kind === 'before', 'The screen before the step');
  for (const f of row.frames) {
    add(`frame ${f.frame}`, { kind: 'frame', frame: f.frame }, place.kind === 'frame' && place.frame === f.frame, 'A frame the step drew');
  }
  add('after', { kind: 'after' }, place.kind === 'after', 'The screen after the step');
  screenBar.replaceChildren(...buttons);
}

function showDetail(): void {
  const d = details.get(selected);
  const text = d === undefined ? '' : tab === 'facts' ? d.facts.join('\n') : tab === 'tree' ? (d.tree ?? 'no tree kept') : tab === 'log' ? (d.log.length > 0 ? d.log.join('\n') : 'no log records in the step') : d.sequences === '' ? 'no sequences in the step' : d.sequences;
  detailPane.textContent = text;
  detailPane.classList.toggle('error', false);
  for (const b of Array.from(tabsBar.querySelectorAll('button'))) {
    b.classList.toggle('on', b.dataset.tab === tab);
  }
}

for (const name of ['facts', 'tree', 'log', 'sequences'] as const) {
  const b = element('button', { textContent: name });
  b.dataset.tab = name;
  b.addEventListener('click', () => {
    tab = name;
    showDetail();
  });
  tabsBar.append(b);
}

function select(index: number): void {
  selected = index;
  place = { kind: 'after' };
  for (const [i, b] of Array.from(stepsList.querySelectorAll('button')).entries()) {
    b.classList.toggle('selected', i === index);
  }
  showScreen();
  if (details.has(index)) {
    showDetail();
  } else {
    detailPane.textContent = '';
    vscode.postMessage({ type: 'select', index });
  }
}

window.addEventListener('message', (event: MessageEvent<unknown>) => {
  const m = event.data;
  if (!isToTrace(m)) {
    return;
  }
  if (m.type === 'open') {
    events = m.events;
    rows = m.steps;
    columns = m.width;
    lines = m.height;
    details.clear();
    stepsList.replaceChildren(
      ...rows.map((r, i) => {
        const b = element('button', { textContent: r.label, title: r.label, className: r.ok ? 'passed' : 'failed' });
        b.addEventListener('click', () => select(i));
        return b;
      }),
    );
    if (m.select >= 0) {
      select(m.select);
    } else {
      draw(-1);
    }
  } else {
    details.set(m.index, m.detail);
    if (m.index === selected) {
      showDetail();
    }
  }
});

vscode.postMessage({ type: 'ready' });
