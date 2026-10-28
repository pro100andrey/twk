// The webview's end: an xterm.js terminal whose input, size and output
// travel to the extension (vscode/panel.ts) as the messages of
// protocol.ts, which serves it to twk apps (core/shell.ts); what it
// answers and emulates beside xterm.js, as the extension says for each app
// (an `answers` message), is answers.ts's. Compiled on its own
// (tsconfig.webview.json) as ES modules for the browser, with the pure
// modules of core/ it takes; xterm.js, its fit addon and its image addon
// are the scripts the page loads before it.
import type { FitAddon as FitAddonType } from '@xterm/addon-fit';
import type { IImageAddonOptions, ImageAddon as ImageAddonType } from '@xterm/addon-image';
import type { Terminal as TerminalType } from '@xterm/xterm';

import type { Graphics } from '../core/capabilities.js';
import { Emulation } from './answers.js';
import { cellAt, cursorRowShown } from './pick.js';
import { FromWebview, PlayerControl, PlayerState, isToWebview } from './protocol.js';

declare const Terminal: typeof TerminalType;
declare const FitAddon: { FitAddon: typeof FitAddonType };
declare const ImageAddon: { ImageAddon: new (options?: IImageAddonOptions) => ImageAddonType };
declare function acquireVsCodeApi(): { postMessage(message: FromWebview): void };

const vscode = acquireVsCodeApi();
const post = (m: FromWebview) => vscode.postMessage(m);
const css = getComputedStyle(document.documentElement);
const color = (name: string, fallback: string) => css.getPropertyValue(name).trim() || fallback;
/** The emulation, once made: the link handler is given before the terminal is. */
let emulation: Emulation | undefined;
const term = new Terminal({
  allowProposedApi: true,
  // an OSC 8 link clicked: opened by the extension, where links are on
  linkHandler: { activate: (_event, uri) => emulation?.activateLink(uri), allowNonHttpProtocols: true },
  fontFamily: color('--vscode-editor-font-family', 'monospace'),
  fontSize: Number.parseInt(color('--vscode-editor-font-size', '14'), 10) || 14,
  theme: {
    background: color('--vscode-terminal-background', color('--vscode-editor-background', '#1e1e1e')),
    foreground: color('--vscode-terminal-foreground', color('--vscode-editor-foreground', '#cccccc')),
  },
});
const fit = new FitAddon.FitAddon();
term.loadAddon(fit);
const host = document.getElementById('terminal');
if (!host) {
  throw new Error('no #terminal in the page');
}
term.open(host);

/** A size the extension fixed, or null: fitted to the panel. */
let fixed: { columns: number; lines: number } | null = null;
const layout = () => {
  if (fixed) {
    term.resize(fixed.columns, fixed.lines);
  } else {
    try {
      fit.fit();
    } catch {
      // not laid out yet
    }
  }
};
new ResizeObserver(layout).observe(document.body);

/** The screen's element, which a cell's size and the pointer's shape are of. */
const screenElement = (): HTMLElement | null => host.querySelector<HTMLElement>('.xterm-screen');

emulation = new Emulation(term, {
  reply: (text) => post({ type: 'input', data: text, binary: false }),
  request: (request) => post({ type: 'request', request }),
  pointer: (shape) => {
    for (const e of [term.element, screenElement()]) {
      if (e) {
        e.style.cursor = shape ?? '';
      }
    }
  },
  cellSize: () => {
    const screen = screenElement();
    return screen && term.cols > 0 && term.rows > 0 ? { width: screen.clientWidth / term.cols, height: screen.clientHeight / term.rows } : undefined;
  },
});

/** The image addon, where images are shown, and for which protocol. */
let images: { readonly graphics: Graphics; readonly addon: ImageAddonType } | undefined;
const showImages = (graphics: Graphics) => {
  if (images?.graphics === graphics) {
    return;
  }
  images?.addon.dispose();
  images = undefined;
  if (graphics !== 'none') {
    // its size reports left off: a cell's size is the emulation's to answer
    const addon = new ImageAddon.ImageAddon({ enableSizeReports: false, sixelSupport: graphics === 'sixel', iipSupport: graphics === 'iterm2' });
    term.loadAddon(addon);
    images = { graphics, addon };
  }
};

// The keys of the extension's commands (twk: Hot Reload, Ctrl+Alt+R;
// Hot Restart, Ctrl+Alt+Shift+R; Cmd on macOS): xterm.js leaves them,
// and the webview passes them on to VS Code's key bindings. Where the app
// pushed kitty's keyboard flags, the keys they change are sent as the
// emulation encodes them, and neither xterm.js nor VS Code gets them.
term.attachCustomKeyEventHandler((e) => {
  if ((e.ctrlKey || e.metaKey) && e.altKey && e.code === 'KeyR') {
    return false;
  }
  const sent = emulation?.key({ key: e.key, code: e.code, ctrl: e.ctrlKey, alt: e.altKey, shift: e.shiftKey, meta: e.metaKey });
  if (sent === undefined) {
    return true;
  }
  if (e.type === 'keydown') {
    e.preventDefault();
    post({ type: 'input', data: sent, binary: false });
  }
  return false;
});

// The pick mode (twk: Pick a Widget, where the app can't pick itself):
// each click on the screen picks its cell, and neither xterm.js nor the
// app gets it, nor anything the mouse does until it is released, until the
// extension turns it off; Escape ends it, telling none.
let picking = false;
let pickHeld = false;
const setPicking = (on: boolean) => {
  picking = on;
  host.style.cursor = on ? 'crosshair' : '';
  const screen = screenElement();
  if (screen) {
    screen.style.cursor = on ? 'crosshair' : '';
  }
};
const swallow = (e: Event) => {
  e.preventDefault();
  e.stopImmediatePropagation();
};
host.addEventListener(
  'mousedown',
  (e) => {
    if (!picking) {
      return;
    }
    swallow(e);
    const screen = screenElement();
    const box = screen?.getBoundingClientRect();
    const cell = box && cellAt(e.clientX - box.left, e.clientY - box.top, box.width, box.height, term.cols, term.rows);
    if (e.button === 0 && cell) {
      pickHeld = true;
      const b = term.buffer.active;
      post({ type: 'picked', cell: { ...cell, cursorY: cursorRowShown(b.cursorY, b.baseY, b.viewportY) } });
    }
  },
  true,
);
for (const kind of ['mouseup', 'click', 'mousemove', 'wheel', 'contextmenu'] as const) {
  host.addEventListener(
    kind,
    (e) => {
      if (picking || pickHeld) {
        swallow(e);
        if (kind === 'mouseup') {
          pickHeld = false;
        }
      }
    },
    true,
  );
}
window.addEventListener(
  'keydown',
  (e) => {
    if (picking && e.key === 'Escape') {
      swallow(e);
      setPicking(false);
      post({ type: 'picked', cell: null });
    }
  },
  true,
);

// The bar of a recording played back: from the start, a frame back, play
// or pause, a frame on, and where it is; under the terminal, which keeps
// the recording's size.
let playerBar: { readonly bar: HTMLElement; readonly toggle: HTMLButtonElement; readonly where: HTMLElement } | undefined;
const showPlayer = (state: PlayerState | null) => {
  if (state === null) {
    playerBar?.bar.remove();
    playerBar = undefined;
    host.style.height = '';
    layout();
    return;
  }
  if (!playerBar) {
    const bar = document.createElement('div');
    bar.style.cssText = 'display:flex;gap:6px;align-items:center;height:28px;padding:0 8px;box-sizing:border-box;font-family:var(--vscode-font-family);font-size:var(--vscode-font-size);color:var(--vscode-foreground);border-top:1px solid var(--vscode-panel-border, transparent)';
    const button = (text: string, title: string, control: PlayerControl) => {
      const b = document.createElement('button');
      b.textContent = text;
      b.title = title;
      b.style.cssText = 'min-width:2.2em;color:var(--vscode-button-foreground);background:var(--vscode-button-background);border:none;cursor:pointer';
      b.addEventListener('click', () => {
        post({ type: 'control', control });
        term.focus();
      });
      bar.append(b);
      return b;
    };
    button('⏮', 'From the start (Home, r)', 'restart');
    button('◀', 'A frame back (Left, ,)', 'back');
    const toggle = button('▶', 'Play or pause (Space)', 'toggle');
    button('▶|', 'A frame on (Right, .)', 'step');
    const where = document.createElement('span');
    where.style.opacity = '0.8';
    bar.append(where);
    document.body.append(bar);
    host.style.height = 'calc(100% - 28px)';
    playerBar = { bar, toggle, where };
  }
  playerBar.toggle.textContent = state.playing ? '⏸' : '▶';
  playerBar.where.textContent = `frame ${state.frame}/${state.frames} · ${state.time.toFixed(2)} s / ${state.duration.toFixed(2)} s${state.playing ? '' : ' · paused'}`;
};

term.onData((data) => post({ type: 'input', data, binary: false }));
term.onBinary((data) => post({ type: 'input', data, binary: true }));
term.onResize(({ cols, rows }) => post({ type: 'resize', columns: cols, lines: rows }));

window.addEventListener('message', (event: MessageEvent<unknown>) => {
  const m = event.data;
  if (!isToWebview(m)) {
    return;
  }
  switch (m.type) {
    case 'output':
      term.write(m.data, () => post({ type: 'written', id: m.id }));
      break;
    case 'size':
      fixed = m.columns && m.lines ? { columns: m.columns, lines: m.lines } : null;
      layout();
      break;
    case 'snapshot': {
      const b = term.buffer.active;
      const rows: string[] = [];
      const backgrounds: string[] = [];
      const cell = b.getNullCell();
      for (let y = 0; y < term.rows; y++) {
        const line = b.getLine(b.viewportY + y);
        rows.push(line?.translateToString(true) ?? '');
        let bg = '';
        for (let x = 0; x < term.cols; x++) {
          bg += line?.getCell(x, cell)?.isBgDefault() === false ? '#' : ' ';
        }
        backgrounds.push(bg.trimEnd());
      }
      post({ type: 'snapshot', id: m.id, buffer: b.type, rows, backgrounds });
      break;
    }
    case 'focus':
      term.focus();
      break;
    case 'answers':
      emulation?.configure(m.answers);
      showImages(m.answers.graphics);
      break;
    case 'pick':
      setPicking(m.on);
      break;
    case 'player':
      showPlayer(m.state);
      break;
  }
});

layout();
post({ type: 'ready', columns: term.cols, lines: term.rows });
term.focus();
