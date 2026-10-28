// The sequence log's webview: the entries the extension makes of a
// screen's traffic (core/seqlog.ts, app/log_panel.ts), a row each, newest
// at the bottom; a frame of a synchronized update one row, opened by a
// click to its sequences. Filtered by direction (what the app wrote, what
// the terminal sent, the notes), with text runs left out or not, and by a
// word; paused (what comes meanwhile held, shown on resume); cleared.
// Compiled with the terminal's webview (tsconfig.webview.json).
import type { LogEntry } from '../core/seqlog.js';
import { FromLog, isToLog } from './log_protocol.js';

declare function acquireVsCodeApi(): { postMessage(message: FromLog): void };

const vscode = acquireVsCodeApi();
const bar = document.getElementById('bar')!;
const log = document.getElementById('log')!;

/** The most entries kept here, and the most rows shown. */
const keep = 20000;
const most = 3000;

let entries: LogEntry[] = [];
let held: LogEntry[] = [];
let paused = false;
let ended = false;
const opened = new Set<number>();
const filter = { out: true, in: true, note: true, text: true, word: '' };

function element<K extends keyof HTMLElementTagNameMap>(tag: K, props: Partial<HTMLElementTagNameMap[K]> = {}, ...children: (Node | string)[]): HTMLElementTagNameMap[K] {
  const e = Object.assign(document.createElement(tag), props);
  e.append(...children);
  return e;
}

const toggle = (label: string, key: 'out' | 'in' | 'note' | 'text') => {
  const box = element('input', { type: 'checkbox', checked: filter[key] });
  box.addEventListener('change', () => {
    filter[key] = box.checked;
    render();
  });
  return element('label', {}, box, label);
};
const word = element('input', { type: 'text', placeholder: 'filter: a word of the name or the bytes' });
word.addEventListener('input', () => {
  filter.word = word.value.toLowerCase();
  render();
});
const pause = element('button', { textContent: 'Pause', title: 'Hold what comes, to read what is shown' });
pause.addEventListener('click', () => {
  paused = !paused;
  pause.textContent = paused ? 'Resume' : 'Pause';
  if (!paused) {
    const h = held;
    held = [];
    add(h);
  }
  status();
});
const clear = element('button', { textContent: 'Clear', title: 'Forget every entry' });
clear.addEventListener('click', () => vscode.postMessage({ type: 'clear' }));
const statusLine = element('span', { id: 'status' });
bar.append(toggle('app wrote →', 'out'), toggle('terminal sent ←', 'in'), toggle('notes', 'note'), toggle('text runs', 'text'), word, pause, clear, statusLine);

function matches(e: LogEntry): boolean {
  if (!filter[e.direction] || (!filter.text && e.kind === 'text')) {
    return false;
  }
  if (filter.word === '') {
    return true;
  }
  const has = (x: LogEntry): boolean => x.name.toLowerCase().includes(filter.word) || x.raw.toLowerCase().includes(filter.word);
  return has(e) || (e.children ?? []).some(has);
}

const arrows = { out: '→', in: '←', note: '·' } as const;

function row(e: LogEntry, parent?: LogEntry): HTMLElement {
  const r = element(
    'div',
    { className: `row ${e.direction} ${e.kind}${parent ? ' child' : ''}`, title: `${e.bytes} bytes` },
    element('span', { className: 'time', textContent: (e.time / 1000).toFixed(3) }),
    element('span', { className: 'dir', textContent: arrows[e.direction] }),
    element('span', { className: 'name', textContent: e.kind === 'frame' ? `${opened.has(e.id) ? '▾' : '▸'} ${e.name}` : e.name }),
    element('span', { className: 'raw', textContent: e.raw }),
  );
  if (parent) {
    r.dataset.parent = String(parent.id);
  }
  if (e.kind === 'frame') {
    r.addEventListener('click', () => {
      if (opened.has(e.id)) {
        opened.delete(e.id);
      } else {
        opened.add(e.id);
      }
      log.querySelectorAll(`[data-parent="${e.id}"]`).forEach((c) => c.remove());
      r.replaceWith(...rowsOf(e));
      status();
    });
  }
  return r;
}

/** The rows of [e]: one, and below an opened frame its own. */
function rowsOf(e: LogEntry): HTMLElement[] {
  const rows = [row(e)];
  if (e.kind === 'frame' && opened.has(e.id)) {
    for (const c of e.children ?? []) {
      if (filter.text || c.kind !== 'text') {
        rows.push(row(c, e));
      }
    }
  }
  return rows;
}

const atBottom = () => log.scrollTop + log.clientHeight >= log.scrollHeight - 4;

/** Shows [more], held while paused. */
function add(more: readonly LogEntry[]): void {
  entries.push(...more);
  if (entries.length > keep) {
    entries = entries.slice(entries.length - keep);
  }
  if (paused) {
    held.push(...more);
    status();
    return;
  }
  const follow = atBottom();
  for (const e of more) {
    if (matches(e)) {
      log.append(...rowsOf(e));
    }
  }
  while (log.childElementCount > most) {
    log.firstElementChild?.remove();
  }
  if (follow) {
    log.scrollTop = log.scrollHeight;
  }
  status();
}

/** Shows the entries kept as the filter says, from scratch. */
function render(): void {
  const shown = entries.filter((e) => !held.includes(e) && matches(e)).slice(-most);
  log.replaceChildren(...shown.flatMap(rowsOf));
  log.scrollTop = log.scrollHeight;
  status();
}

function status(): void {
  const parts = [`${entries.length} entries`];
  if (paused) {
    parts.push(`paused, ${held.length} new`);
  }
  if (ended) {
    parts.push('its terminal was closed');
  }
  statusLine.textContent = parts.join(' · ');
  const last = Array.from(log.querySelectorAll('.row:not(.child) .name')).slice(-20).map((n) => n.textContent ?? '');
  vscode.postMessage({ type: 'shown', rows: log.childElementCount, held: held.length, last });
}

window.addEventListener('message', (event: MessageEvent<unknown>) => {
  const m = event.data;
  if (!isToLog(m)) {
    return;
  }
  switch (m.type) {
    case 'reset':
      document.title = m.title;
      entries = [...m.entries];
      held = [];
      opened.clear();
      render();
      break;
    case 'entries':
      add(m.entries);
      break;
    case 'ended':
      ended = true;
      status();
      break;
  }
});

vscode.postMessage({ type: 'ready' });
