// The screen file editor's webview: a golden of matchesScreenFile drawn
// cell by cell in its own colours, with the Text and Styles toggles; where a
// failed test left its screen beside the file, the golden and that screen
// side by side with the cells that differ marked, and Accept Actual.
// Compiled with the terminal's webview (tsconfig.webview.json).
import { CellChange, ScreenFile, ScreenDiff, cellsOf, parseStyle, styleAt } from '../core/screen_file.js';
import { FromScreen, ScreenState, isToScreen } from './screen_protocol.js';

declare function acquireVsCodeApi(): { postMessage(message: FromScreen): void };

const vscode = acquireVsCodeApi();
const bar = document.getElementById('bar')!;
const body = document.getElementById('screens')!;

type Show = 'golden' | 'actual' | 'diff';
const view = { text: true, styles: true, show: 'diff' as Show };
let name = '';
let state: ScreenState | undefined;

function element<K extends keyof HTMLElementTagNameMap>(tag: K, props: Partial<HTMLElementTagNameMap[K]> = {}, ...children: (Node | string)[]): HTMLElementTagNameMap[K] {
  const e = Object.assign(document.createElement(tag), props);
  e.append(...children);
  return e;
}

/** The inline CSS of a cell of [style] (twk_test's name for it). */
function css(style: string): { readonly css: string; readonly link: string | null } {
  const s = parseStyle(style);
  const plainFg = 'var(--twk-fg)';
  const plainBg = 'var(--twk-bg)';
  let fg = s.fg ?? plainFg;
  let bg = s.bg ?? plainBg;
  if (s.reverse) {
    [fg, bg] = [s.bg ?? plainBg, s.fg ?? plainFg];
  }
  const decorations = [s.underline ? 'underline' : '', s.strike ? 'line-through' : '', s.overline ? 'overline' : ''].filter((d) => d !== '').join(' ');
  const parts = [`color:${s.hidden ? bg : fg}`, `background:${bg}`];
  if (s.bold) parts.push('font-weight:bold');
  if (s.dim) parts.push('opacity:0.6');
  if (s.italic) parts.push('font-style:italic');
  if (decorations) parts.push(`text-decoration:${decorations}`);
  if (s.underline && s.underline !== 'solid') parts.push(`text-decoration-style:${s.underline}`);
  if (s.underlineColor) parts.push(`text-decoration-color:${s.underlineColor}`);
  return { css: parts.join(';'), link: s.link };
}

function describe(style: string | null): string {
  return style === null ? 'a character the legend lacks' : style === '' ? 'none' : style;
}

/** [file]'s grid; the cells of [changes] marked. */
function grid(file: ScreenFile, changes: readonly CellChange[], title: string): HTMLElement {
  const marked = new Map(changes.map((c) => [c.y * file.width + c.x, c] as const));
  const root = element('div', { className: 'screen' }, element('div', { className: 'caption', textContent: title }));
  const rows = element('div', { className: 'grid' });
  for (let y = 0; y < file.height; y++) {
    const row = element('div', { className: 'row' });
    const texts = cellsOf(file.text[y], file.width);
    for (let x = 0; x < file.width; x++) {
      if (texts[x] === '' && x > 0) {
        continue;
      }
      const wide = x + 1 < file.width && texts[x + 1] === '';
      const style = styleAt(file, x, y) ?? '';
      const cell = element('span', { textContent: view.text ? (texts[x] === '' ? ' ' : texts[x]) : ' ' });
      if (view.styles) {
        const s = css(style);
        cell.style.cssText = s.css;
        if (s.link) {
          cell.title = `link ${s.link}`;
        }
      }
      if (wide) {
        cell.classList.add('wide');
      }
      const change = marked.get(y * file.width + x);
      if (change) {
        cell.classList.add('changed');
        cell.title = `(${x}, ${y}): - ${JSON.stringify(change.text[0])} ${describe(change.style[0])}, + ${JSON.stringify(change.text[1])} ${describe(change.style[1])}`;
      }
      if (file.cursor && file.cursor[0] === x && file.cursor[1] === y) {
        cell.classList.add('cursor');
      }
      row.append(cell);
    }
    rows.append(row);
  }
  root.append(rows);
  return root;
}

function legend(file: ScreenFile): HTMLElement {
  const list = element('div', { className: 'legend' });
  for (const [char, style] of Object.entries(file.legend)) {
    const s = css(style);
    const sample = element('span', { className: 'sample', textContent: char });
    sample.style.cssText = s.css;
    list.append(element('div', {}, sample, ` ${style}`));
  }
  return list;
}

function differences(diff: ScreenDiff): HTMLElement {
  const lines: string[] = [];
  const at = (c: readonly [number, number] | null) => (c ? `at ${c[0]},${c[1]}` : 'hidden');
  if (diff.size) {
    lines.push(`the size: - ${diff.size[0][0]}×${diff.size[0][1]}, + ${diff.size[1][0]}×${diff.size[1][1]}`);
  }
  if (diff.cursor) {
    lines.push(`the cursor: - ${at(diff.cursor[0])}, + ${at(diff.cursor[1])}`);
  }
  for (const c of diff.cells.slice(0, 200)) {
    lines.push(`(${c.x}, ${c.y}): - ${JSON.stringify(c.text[0])} ${describe(c.style[0])}, + ${JSON.stringify(c.text[1])} ${describe(c.style[1])}`);
  }
  if (diff.cells.length > 200) {
    lines.push(`… and ${diff.cells.length - 200} more cells`);
  }
  return element('pre', { className: 'diff', textContent: lines.join('\n') });
}

function toggle(label: string, key: 'text' | 'styles'): HTMLElement {
  const box = element('input', { type: 'checkbox', checked: view[key] });
  box.addEventListener('change', () => {
    view[key] = box.checked;
    render();
  });
  return element('label', {}, box, label);
}

function choice(label: string, value: Show): HTMLElement {
  const radio = element('input', { type: 'radio', name: 'show', checked: view.show === value });
  radio.addEventListener('change', () => {
    view.show = value;
    render();
  });
  return element('label', {}, radio, label);
}

function render(): void {
  bar.replaceChildren();
  body.replaceChildren();
  if (!state) {
    return;
  }
  if (state.kind === 'bad') {
    body.append(element('p', { className: 'bad', textContent: `${name}: ${state.message}` }));
    return;
  }
  const { golden, actual, diff, stale } = state;
  bar.append(element('span', { textContent: `${golden.width}×${golden.height}, cursor ${golden.cursor ? `at ${golden.cursor[0]},${golden.cursor[1]}` : 'hidden'}` }), toggle('Text', 'text'), toggle('Styles', 'styles'));
  const changes = diff?.cells ?? [];
  if (actual && diff) {
    const same = diff.size === null && diff.cursor === null && diff.cells.length === 0;
    bar.append(choice('Golden', 'golden'), choice('Actual', 'actual'), choice('Diff', 'diff'));
    const accept = element('button', { textContent: 'Accept Actual', title: 'Make the screen of the failed test the golden (what TWK_UPDATE_GOLDENS=1 writes)' });
    accept.addEventListener('click', () => vscode.postMessage({ type: 'accept' }));
    bar.append(element('span', { className: 'status', textContent: same ? 'the failed test left a screen like the golden' : `${diff.cells.length} cells differ` }), accept);
  } else if (stale) {
    bar.append(element('span', { className: 'status', textContent: 'a .actual older than the golden is beside it: ignored' }));
  }
  const screens = element('div', { className: 'screens' });
  if (actual && diff && view.show === 'diff') {
    if (diff.size === null) {
      screens.append(grid(golden, changes, 'golden'), grid(actual, changes, 'actual'));
    }
    body.append(screens, differences(diff));
  } else if (actual && view.show === 'actual') {
    screens.append(grid(actual, [], 'actual'));
    body.append(screens, legend(actual));
  } else {
    screens.append(grid(golden, [], 'golden'));
    body.append(screens, legend(golden));
  }
}

window.addEventListener('message', (e: MessageEvent<unknown>) => {
  if (isToScreen(e.data)) {
    name = e.data.name;
    state = e.data.state;
    render();
  }
});
vscode.postMessage({ type: 'ready' });
