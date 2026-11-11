// The terminal's colours from VS Code's theme: the --vscode-terminal-*
// variables the webview's page carries (VS Code sets them on the root
// element and sets them again when the theme changes). xterm.js answers
// the apps' OSC 10 and 11 queries with the theme it is given, so twk's
// light/dark detection sees the real background. Pure: [read] gives a
// variable's value, which main.ts takes from the computed style.
import type { ITheme } from '@xterm/xterm';

/** The ANSI colours' names in VS Code's terminal.ansi* keys, in the order of colours 0 to 15. */
export const ansiNames = [
  'Black',
  'Red',
  'Green',
  'Yellow',
  'Blue',
  'Magenta',
  'Cyan',
  'White',
  'BrightBlack',
  'BrightRed',
  'BrightGreen',
  'BrightYellow',
  'BrightBlue',
  'BrightMagenta',
  'BrightCyan',
  'BrightWhite',
] as const;

/** xterm.js's names of the 16 colours, in the same order. */
const ansiKeys = [
  'black',
  'red',
  'green',
  'yellow',
  'blue',
  'magenta',
  'cyan',
  'white',
  'brightBlack',
  'brightRed',
  'brightGreen',
  'brightYellow',
  'brightBlue',
  'brightMagenta',
  'brightCyan',
  'brightWhite',
] as const;

/** Colours of the page that are the terminal's where its own are unset (the panel's, then the editor's). */
const fallbackBackground = '#1e1e1e';
const fallbackForeground = '#cccccc';

/**
 * The xterm.js theme of VS Code's terminal colours. [read] is given a
 * variable's name (`--vscode-terminal-background`) and answers its value,
 * or an empty string where unset. A colour VS Code does not define is left
 * out of the theme, so xterm.js keeps its own default for it; the
 * background and foreground fall back to the editor's.
 */
export function terminalTheme(read: (name: string) => string): ITheme {
  const get = (name: string): string | undefined => read(`--vscode-${name}`).trim() || undefined;
  const theme: Record<string, string> = {
    background: get('terminal-background') ?? get('editor-background') ?? fallbackBackground,
    foreground: get('terminal-foreground') ?? get('editor-foreground') ?? fallbackForeground,
  };
  const set = (key: string, value: string | undefined) => {
    if (value !== undefined) {
      theme[key] = value;
    }
  };
  const cursor = get('terminalCursor-foreground');
  set('cursor', cursor);
  set('cursorAccent', get('terminalCursor-background'));
  set('selectionBackground', get('terminal-selectionBackground'));
  set('selectionForeground', get('terminal-selectionForeground'));
  set('selectionInactiveBackground', get('terminal-inactiveSelectionBackground'));
  ansiNames.forEach((name, i) => set(ansiKeys[i], get(`terminal-ansi${name}`)));
  return theme;
}

/** Whether two themes are the same colours. */
export function sameTheme(a: ITheme, b: ITheme): boolean {
  const ka = Object.keys(a);
  return ka.length === Object.keys(b).length && ka.every((k) => (a as Record<string, unknown>)[k] === (b as Record<string, unknown>)[k]);
}
