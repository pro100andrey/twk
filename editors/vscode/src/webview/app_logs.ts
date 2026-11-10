// The app log's webview: the records the apps of the extension serve
// (core/app_log.ts, app/app_logs.ts), a row each, newest at the bottom:
// the time, the level in its colour, the message, the error after it, and
// by a click on the row its stack, the frames that are code on the disk
// opened in the editor by a click. Filtered by level, by app and by a word;
// paused (what comes meanwhile held, shown on resume); cleared. Compiled
// with the terminal's webview (tsconfig.webview.json).
import { Level, formatTime, levels, matchesFilter } from '../core/app_log.js';
import { AppInfo, FromAppLogs, LogRow, isToAppLogs } from './app_logs_protocol.js';

declare function acquireVsCodeApi(): { postMessage(message: FromAppLogs): void };

const vscode = acquireVsCodeApi();
const bar = document.getElementById('bar')!;
const log = document.getElementById('log')!;

/** The most rows kept here, and the most shown. */
const keep = 5000;
const most = 2000;

let rows: LogRow[] = [];
let held: LogRow[] = [];
let apps: readonly AppInfo[] = [];
let paused = false;
const opened = new Set<number>();
const on = new Set<Level>(levels);
let app = 0;
let word = '';

function element<K extends keyof HTMLElementTagNameMap>(tag: K, props: Partial<HTMLElementTagNameMap[K]> = {}, ...children: (Node | string)[]): HTMLElementTagNameMap[K] {
  const e = Object.assign(document.createElement(tag), props);
  e.append(...children);
  return e;
}

const toggle = (level: Level) => {
  const box = element('input', { type: 'checkbox', checked: true });
  box.addEventListener('change', () => {
    if (box.checked) {
      on.add(level);
    } else {
      on.delete(level);
    }
    render();
  });
  return element('label', { className: `level ${level}` }, box, level);
};
const appSelect = element('select', { title: 'Which app' });
appSelect.addEventListener('change', () => {
  app = Number(appSelect.value);
  render();
});
const filter = element('input', { type: 'text', placeholder: 'filter: a word of the message, error or stack' });
filter.addEventListener('input', () => {
  word = filter.value.toLowerCase();
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
const clear = element('button', { textContent: 'Clear', title: 'Forget every row' });
clear.addEventListener('click', () => vscode.postMessage({ type: 'clear' }));
const statusLine = element('span', { id: 'status' });
bar.append(...levels.map(toggle), appSelect, filter, pause, clear, statusLine);

function showsApp(r: LogRow): boolean {
  return app === 0 || r.app === app;
}

function matches(r: LogRow): boolean {
  if (!showsApp(r)) {
    return false;
  }
  // a note (an app connected or went away) is shown whatever the levels
  return r.level === 'note' ? word === '' : matchesFilter({ ...r, level: r.level }, on, word);
}

const labelOf = (id: number) => apps.find((a) => a.id === id)?.label ?? `app ${id}`;

function row(r: LogRow): HTMLElement[] {
  const head = element(
    'div',
    { className: `row ${r.level}${r.stack ? ' stacked' : ''}`, title: new Date(r.time).toISOString() },
    element('span', { className: 'time', textContent: formatTime(r.time) }),
    element('span', { className: 'lvl', textContent: r.level }),
    element('span', { className: 'app', textContent: labelOf(r.app) }),
    element('span', { className: 'msg', textContent: `${r.stack ? `${opened.has(r.id) ? '▾' : '▸'} ` : ''}${r.message}${r.error === undefined ? '' : `: ${r.error}`}` }),
  );
  head.dataset.id = String(r.id);
  const out = [head];
  if (r.stack) {
    head.addEventListener('click', () => {
      if (opened.has(r.id)) {
        opened.delete(r.id);
      } else {
        opened.add(r.id);
      }
      log.querySelectorAll(`[data-of="${r.id}"]`).forEach((c) => c.remove());
      head.replaceWith(...row(r));
    });
    if (opened.has(r.id)) {
      r.stack.forEach((f, i) => {
        const line = element('div', { className: `frame${f.open ? ' open' : ''}`, textContent: f.text });
        line.dataset.of = String(r.id);
        if (f.open) {
          line.title = 'Open in the editor';
          line.addEventListener('click', () => vscode.postMessage({ type: 'open', row: r.id, frame: i }));
        }
        out.push(line);
      });
    }
  }
  return out;
}

const atBottom = () => log.scrollTop + log.clientHeight >= log.scrollHeight - 4;

/** Shows [more], held while paused. */
function add(more: readonly LogRow[]): void {
  rows.push(...more);
  if (rows.length > keep) {
    rows = rows.slice(rows.length - keep);
  }
  if (paused) {
    held.push(...more);
    status();
    return;
  }
  const follow = atBottom();
  for (const r of more) {
    if (matches(r)) {
      log.append(...row(r));
    }
  }
  while (log.querySelectorAll('.row').length > most && log.firstElementChild) {
    log.firstElementChild.remove();
  }
  if (follow) {
    log.scrollTop = log.scrollHeight;
  }
  status();
}

/** Shows the rows kept as the filters say, from scratch. */
function render(): void {
  const shown = rows.filter((r) => !held.includes(r) && matches(r)).slice(-most);
  log.replaceChildren(...shown.flatMap(row));
  log.scrollTop = log.scrollHeight;
  status();
}

function showApps(): void {
  appSelect.replaceChildren(
    element('option', { value: '0', textContent: 'all apps' }),
    ...apps.map((a) => element('option', { value: String(a.id), textContent: `${a.label} (${a.state})` })),
  );
  appSelect.value = apps.some((a) => a.id === app) ? String(app) : '0';
  app = Number(appSelect.value);
}

function status(): void {
  const parts = [`${rows.length} rows`];
  if (paused) {
    parts.push(`paused, ${held.length} new`);
  }
  if (apps.length === 0) {
    parts.push('no app followed: switch on the debug aid "logs" and run an app');
  }
  statusLine.textContent = parts.join(' · ');
  const last = Array.from(log.querySelectorAll('.row .msg')).slice(-20).map((n) => n.textContent ?? '');
  vscode.postMessage({ type: 'shown', rows: log.querySelectorAll('.row').length, held: held.length, last });
}

window.addEventListener('message', (event: MessageEvent<unknown>) => {
  const m = event.data;
  if (!isToAppLogs(m)) {
    return;
  }
  switch (m.type) {
    case 'reset':
      document.title = m.title;
      apps = m.apps;
      rows = [...m.rows];
      held = [];
      opened.clear();
      showApps();
      render();
      break;
    case 'apps':
      apps = m.apps;
      showApps();
      status();
      break;
    case 'rows':
      add(m.rows);
      break;
  }
});

vscode.postMessage({ type: 'ready' });
