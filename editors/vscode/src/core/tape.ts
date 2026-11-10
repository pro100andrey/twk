// A `.tape` (twk tape, VHS's language) as the editor needs it: its
// statements told from the text alone (for the lenses, the hovers and the
// preview), the files it writes, and what `twk tape --check` reports
// (`<tape>:<line>: ok <statement>`, packages/twk_dev/doc/tape.md). The
// language itself is read by twk tape only: nothing here parses a tape to
// judge it, a statement is a line's first word and its argument.

/** The statement of a tape line, lines from 0. */
export interface TapeStatement {
  readonly line: number;
  /** `Set`, `Type`, `Wait`..., or `Key` for a key (`Enter`, `Ctrl+C`, `Down@100ms 3`). */
  readonly keyword: string;
  /** The line without its comment, trimmed. */
  readonly source: string;
  /** Where the line's comment begins, if it has one. */
  readonly commentAt: number | undefined;
}

const keys = new Set([
  'Enter', 'Tab', 'Space', 'Backspace', 'Escape', 'Up', 'Down', 'Left', 'Right', 'Home', 'End', 'PageUp', 'PageDown', 'Insert', 'Delete',
  'Ctrl', 'Alt', 'Shift', ...Array.from({ length: 12 }, (_, i) => `F${i + 1}`),
]);
const words = new Set(['Output', 'Set', 'Env', 'Run', 'Type', 'Sleep', 'Wait', 'Hide', 'Show', 'Screenshot']);

/** The column where a comment begins in [line], or undefined: a `#` outside a quoted word and a Wait's `/pattern/` begins it. */
export function commentStart(line: string): number | undefined {
  const wait = /^\s*Wait\b[^/"'`#]*(?=\/)/.exec(line);
  let i = 0;
  if (wait) {
    // the pattern runs to the next slash that is not escaped
    for (i = wait[0].length + 1; i < line.length && line[i] !== '/'; i += line[i] === '\\' ? 2 : 1);
    i++;
  }
  let quote: string | undefined;
  for (; i < line.length; i++) {
    const c = line[i];
    if (quote) {
      if (c === quote) {
        quote = undefined;
      }
    } else if (c === '"' || c === "'" || c === '`') {
      quote = c;
    } else if (c === '#') {
      return i;
    }
  }
  return undefined;
}

/** The statements of [text], in order; a line of a comment or none is none. */
export function tapeStatements(text: string): TapeStatement[] {
  const out: TapeStatement[] = [];
  text.split(/\r?\n/).forEach((raw, line) => {
    const commentAt = commentStart(raw);
    const source = (commentAt === undefined ? raw : raw.slice(0, commentAt)).trim();
    const word = /^[A-Za-z][A-Za-z0-9]*/.exec(source)?.[0];
    if (word === undefined) {
      return;
    }
    const keyword = words.has(word) ? word : keys.has(word) ? 'Key' : word;
    out.push({ line, keyword, source, commentAt });
  });
  return out;
}

/** A file a tape writes: an `Output`, or a `Screenshot` (a still SVG). */
export interface TapeOutput {
  readonly kind: 'Output' | 'Screenshot';
  readonly file: string;
  readonly line: number;
}

/** The first argument of [source] after its keyword, unquoted. */
function argumentOf(source: string): string | undefined {
  const m = /^\S+\s+(?:"([^"]*)"|'([^']*)'|`([^`]*)`|(\S+))/.exec(source);
  return m ? (m[1] ?? m[2] ?? m[3] ?? m[4]) : undefined;
}

/** The files [text] writes, in the order of its statements. */
export function tapeOutputs(text: string): TapeOutput[] {
  const out: TapeOutput[] = [];
  for (const s of tapeStatements(text)) {
    if (s.keyword === 'Output' || s.keyword === 'Screenshot') {
      const file = argumentOf(s.source);
      if (file !== undefined) {
        out.push({ kind: s.keyword, file, line: s.line });
      }
    }
  }
  return out;
}

/** One statement of a check. */
export interface CheckedStatement {
  /** From 0. */
  readonly line: number;
  readonly ok: boolean;
  /** As the check told it. */
  readonly statement: string;
}

/** What `twk tape --check` said of a tape. */
export interface CheckReport {
  /** The exit code; null when the process was stopped by a signal. */
  readonly exit: number | null;
  readonly statements: readonly CheckedStatement[];
  /** The summary line: `passed, 7 statements`, `failed, 3 of 7 statements passed`. */
  readonly summary: string | undefined;
  /** What stderr said: where (a line from 0, when it says one) and what. */
  readonly error: { readonly line: number | undefined; readonly message: string } | undefined;
}

/**
 * The report of a check of [tape] (the name it was given) that ended with
 * [exit], from [output], what it wrote to stdout and stderr: the lines of
 * stdout are told by their form, the rest is stderr's.
 */
export function parseCheck(tape: string, output: string, exit: number | null): CheckReport {
  const statements: CheckedStatement[] = [];
  let summary: string | undefined;
  const prefix = `${tape}:`;
  const rest: string[] = [];
  for (const l of output.split(/\r?\n/)) {
    const m = l.startsWith(prefix) ? /^(\d+): (ok|FAIL) (.*)$/.exec(l.slice(prefix.length)) : null;
    if (m) {
      statements.push({ line: Number(m[1]) - 1, ok: m[2] === 'ok', statement: m[3] });
    } else if (l.startsWith(prefix) && /^ (passed|failed)\b/.test(l.slice(prefix.length))) {
      summary = l.slice(prefix.length).trim();
    } else {
      rest.push(l);
    }
  }
  const text = rest.join('\n').replace(/^\s*twk tape: /, '').trim();
  let error: CheckReport['error'];
  if (text !== '') {
    const m = text.startsWith(prefix) ? /^(\d+): ([^]*)$/.exec(text.slice(prefix.length)) : null;
    error = m ? { line: Number(m[1]) - 1, message: m[2] } : { line: undefined, message: text };
  }
  return { exit, statements, summary, error };
}

/** The keyword-and-text of what a statement means, as the hover and the docs say: the tape.md of twk_dev. */
const docs: Readonly<Record<string, string>> = {
  Output: '`Output <file>`: writes the session, once the tape has run, to a `.cast` file (asciicast v2) or an `.svg` file (an animated SVG); as many as wanted.',
  Set: '`Set <setting> <value>`: `Width` and `Height` (cells, 80 by 24), `Theme` (`dark`, `light`, `xterm` or a JSON object of colours), `FontSize`, `FontFamily`, `Padding`, `Framerate`, `TypingSpeed` (the pause after each character, 50 ms) and `WaitTimeout` (15 s). A Set comes before the first statement that does something, but TypingSpeed and WaitTimeout, which may come anywhere.',
  Env: '`Env <name> <value>`: in the program\'s environment.',
  Run: '`Run <program> [<argument>...]`: the program, looked for in `PATH`, its arguments words or quoted; `sh` when there is none, with `PS1=\'$ \'`.',
  Type: '`Type[@<time>] "<text>"`: types the text, a character at a time, the typing speed (or `@<time>`) after each.',
  Key: '`<key>[@<time>] [<count>]`: presses a key, `count` times: `Enter`, `Tab`, `Space`, `Backspace`, `Escape`, `Up`, `Down`, `Left`, `Right`, `Home`, `End`, `PageUp`, `PageDown`, `Insert`, `Delete`, `F1` to `F12`, and with `Ctrl+`, `Alt+`, `Shift+` before it those and a character (`Ctrl+C`, `Alt+Shift+Tab`).',
  Sleep: '`Sleep <time>`: waits.',
  Wait: '`Wait[+Screen|+Line][@<time>] /<regexp>/`: waits until the screen\'s text (rows a line each; `+Line`, the cursor\'s row) matches, or `"<text>"` shows; past the timeout the tape fails.',
  Hide: '`Hide`: the time between it and the next `Show` is cut from the recording.',
  Show: '`Show`: ends a `Hide`; the screen is drawn as it is then.',
  Screenshot: '`Screenshot <file.svg>`: writes the screen as it is to a still SVG.',
};

const settings: Readonly<Record<string, string>> = {
  Width: '`Set Width <cells>`: the terminal\'s width: 80.',
  Height: '`Set Height <cells>`: the terminal\'s height: 24.',
  Theme: '`Set Theme <name>`: the terminal\'s colours: `dark` (the default), `light`, `xterm`, or a JSON object of `#rrggbb` colours (`background`, `foreground`, `cursor`, `black` to `white`, `brightBlack` to `brightWhite`), dark\'s for those left out.',
  FontSize: '`Set FontSize <px>`: the SVG\'s text size: 16 px.',
  FontFamily: '`Set FontFamily "<css>"`: the SVG\'s fonts: monospace.',
  Padding: '`Set Padding <px>`: the space around the screen in the SVG: the font size.',
  Framerate: '`Set Framerate <n>`: the most frames a second the animated SVG takes: 50.',
  TypingSpeed: '`Set TypingSpeed <time>`: the pause after each character typed and each key: 50 ms; anywhere in the tape.',
  WaitTimeout: '`Set WaitTimeout <time>`: how long a Wait waits: 15 s; anywhere.',
};

/** The documentation (Markdown) of the statement at [source], or undefined for a word that is none. */
export function tapeHover(keyword: string, source: string): string | undefined {
  if (keyword === 'Set') {
    const setting = /^Set\s+(\w+)/.exec(source)?.[1];
    return (setting && settings[setting]) || docs.Set;
  }
  return docs[keyword];
}

/** The keywords of [tapeHover], for the grammar's tests and the completion of none. */
export const tapeKeywords: readonly string[] = Object.keys(docs).filter((k) => k !== 'Key');
