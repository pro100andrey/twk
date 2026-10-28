// What the twk terminal's webview makes of what an app writes, beyond what
// xterm.js does with it, as pure functions: the answers to the queries of
// twk's probe that xterm.js leaves (or that the capabilities deny), and the
// requests an app makes of the editor (a notification, its progress, the
// clipboard, a link), parsed. webview/answers.ts installs them on xterm.js's
// parser; nothing here imports anything but the capabilities' types.
import { Answers, Query } from './capabilities.js';

/** The DEC private modes DECRQM asks about that a capability can deny. */
const deniableModes: Readonly<Record<number, Query>> = {
  2026: 'synchronizedOutput',
  2027: 'graphemes',
  2048: 'inBandResize',
  69: 'margins',
  2031: 'colorSchemeReports',
};

/** The answer to DECRQM of [mode] (`CSI ? mode $ p`): "not recognised" where denied, else undefined (xterm.js's). */
export function modeReply(mode: number, answers: Answers): string | undefined {
  const query = deniableModes[mode];
  return query !== undefined && answers.deny.includes(query) ? `\x1b[?${mode};0$y` : undefined;
}

/** XTVERSION's answer (`DCS > | name ST`), or undefined: not answered. */
export function versionReply(answers: Answers): string | undefined {
  return answers.version === null ? undefined : `\x1bP>|${answers.version}\x1b\\`;
}

/** The answer to `CSI 16 t` for a cell of [width] x [height] pixels, or undefined: not answered (or not known). */
export function cellSizeReply(answers: Answers, cell: { readonly width: number; readonly height: number } | undefined): string | undefined {
  if (!answers.cellSize || !cell || cell.width <= 0 || cell.height <= 0) {
    return undefined;
  }
  return `\x1b[6;${Math.round(cell.height)};${Math.round(cell.width)}t`;
}

/** Whether the data of an OSC 10, 11 or 4 is a query (`?` where a colour would be). */
export function isColorQuery(data: string): boolean {
  return data.split(';').includes('?');
}

/** What an app asks of the editor through its terminal. */
export type TerminalRequest =
  /** OSC 777 `notify;title;body`. */
  | { readonly type: 'notify'; readonly title: string; readonly body: string }
  /** OSC 9;4: [state] 0 none, 1 a percent, 2 an error, 3 busy with no percent, 4 paused. */
  | { readonly type: 'progress'; readonly state: number; readonly percent: number | null }
  /** OSC 52: text for the clipboard. */
  | { readonly type: 'clipboard'; readonly text: string }
  /** An OSC 8 link activated (clicked) in the terminal. */
  | { readonly type: 'openLink'; readonly uri: string };

/** The data of an OSC 777 (`notify;title;body`) as a notification, or undefined: another of its kind. */
export function notificationOf(data: string): TerminalRequest | undefined {
  const [kind, title = '', ...body] = data.split(';');
  return kind === 'notify' ? { type: 'notify', title, body: body.join(';') } : undefined;
}

/** The data of an OSC 9 (`4;state;percent`) as progress, or undefined: an OSC 9 of another kind (iTerm2's notification). */
export function progressOf(data: string): TerminalRequest | undefined {
  const m = /^4;([0-4])(?:;(\d{1,3}))?$/.exec(data);
  if (!m) {
    return undefined;
  }
  const state = Number(m[1]);
  const percent = m[2] === undefined || state === 0 || state === 3 ? null : Math.min(100, Number(m[2]));
  return { type: 'progress', state, percent };
}

const strictUtf8 = new TextDecoder('utf-8', { fatal: true });

/**
 * The text an OSC 52 (`c;base64`, for the clipboard or any selection) puts
 * on the clipboard, or undefined: a query (`?`), or no base64 of UTF-8.
 */
export function clipboardOf(data: string): TerminalRequest | undefined {
  const at = data.indexOf(';');
  const payload = at < 0 ? '' : data.substring(at + 1);
  if (at < 0 || payload === '?' || !/^[A-Za-z0-9+/]*={0,2}$/.test(payload)) {
    return undefined;
  }
  try {
    const bytes = Uint8Array.from(atob(payload), (c) => c.charCodeAt(0));
    return { type: 'clipboard', text: strictUtf8.decode(bytes) };
  } catch {
    return undefined;
  }
}

/** The pointer's shape OSC 22 names, a CSS cursor's name, or null for the terminal's own (empty); undefined for what is no such name. */
export function pointerOf(data: string): string | null | undefined {
  if (data === '') {
    return null;
  }
  return /^[a-z][a-z-]*$/.test(data) ? data : undefined;
}

/** Whether a link an app put on its screen may be opened: http, https and mailto, never `command:` or `file:`. */
export function isSafeLink(uri: string): boolean {
  return /^(https?:\/\/|mailto:)/i.test(uri);
}

/** What the status bar says of an app's progress (OSC 9;4's [state] and [percent]) in the terminal of [source]; undefined for none (state 0). */
export function progressText(source: string, state: number, percent: number | null): string | undefined {
  const done = percent === null ? '' : ` ${percent}%`;
  switch (state) {
    case 1:
      return `$(loading~spin) ${source}${done}`;
    case 2:
      return `$(error) ${source}${done}`;
    case 3:
      return `$(loading~spin) ${source}`;
    case 4:
      return `$(debug-pause) ${source}${done}`;
    default:
      return undefined;
  }
}
