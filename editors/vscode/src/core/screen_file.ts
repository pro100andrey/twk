// A screen file as twk_test's matchesScreenFile writes it
// (packages/twk_test/lib/src/screen_file.dart): a header with the size and
// the cursor, a layer of text, a layer of styles of a character a cell, and
// a legend naming the style of each character. Read here, held to the file
// twk_test's own test matches (packages/twk_test/test/screen_file.golden.txt,
// test/unit/core/screen_file.test.ts); the cells of a screen, the difference
// of two, and a style as CSS-ready fields. Pure, and imported by the
// webview, so with `.js` in its imports and nothing of node's.

/** A screen as the file holds it. */
export interface ScreenFile {
  readonly width: number;
  readonly height: number;
  /** Column and row of the cursor; null while hidden. */
  readonly cursor: readonly [number, number] | null;
  /** Each row's text: the text of its cells, a wide glyph once. */
  readonly text: readonly string[];
  /** Each row's styles: a character a cell, a space for none. */
  readonly styles: readonly string[];
  /** The style each character of [styles] stands for. */
  readonly legend: Readonly<Record<string, string>>;
}

/** A file that is no screen file, and why. */
export class ScreenFileError extends Error {}

const header = /^screen (\d+)×(\d+), cursor (?:at (\d+),(\d+)|hidden)$/;

/** The screen [source] holds; a [ScreenFileError] where it is not a screen file, saying what is wrong as twk_test does. */
export function parseScreenFile(source: string): ScreenFile {
  const lines = source.split(/\r?\n/);
  if (lines.length > 0 && lines[lines.length - 1] === '') {
    lines.pop();
  }
  const first = header.exec(lines[0] ?? '');
  if (!first) {
    throw new ScreenFileError('the first line is not "screen <columns>×<rows>, cursor …"');
  }
  const width = Number(first[1]);
  const height = Number(first[2]);
  const cursor: readonly [number, number] | null = first[3] === undefined ? null : [Number(first[3]), Number(first[4])];
  let i = 1;
  const layer = (name: string): string[] => {
    if (lines[i] !== name) {
      throw new ScreenFileError(`line ${i + 1} is not "${name}"`);
    }
    i++;
    const rows: string[] = [];
    for (let y = 0; y < height; y++, i++) {
      const line = [...(lines[i] ?? '')];
      if (line.length < 2 || line[0] !== '│' || line[line.length - 1] !== '│') {
        throw new ScreenFileError(`line ${i + 1} is not a row in │…│`);
      }
      rows.push(line.slice(1, -1).join(''));
    }
    return rows;
  };
  const text = layer('text');
  const styles = layer('styles');
  styles.forEach((row, y) => {
    const n = [...row].length;
    if (n !== width) {
      throw new ScreenFileError(`row ${y} of the styles has ${n} characters, not ${width}`);
    }
  });
  if (lines[i] !== 'legend') {
    throw new ScreenFileError(`line ${i + 1} is not "legend"`);
  }
  const legend: Record<string, string> = {};
  for (i++; i < lines.length; i++) {
    const line = [...lines[i]];
    if (line.length < 3 || line[1] !== ' ') {
      throw new ScreenFileError(`line ${i + 1} is not "<character> <style>"`);
    }
    legend[line[0]] = line.slice(2).join('');
  }
  return { width, height, cursor, text, styles, legend };
}

/** Whether the code point [cp] takes two cells: East Asian wide and fullwidth forms, and emoji presentations. */
function isWide(cp: number): boolean {
  return (
    (cp >= 0x1100 && cp <= 0x115f) ||
    (cp >= 0x2e80 && cp <= 0x303e) ||
    (cp >= 0x3041 && cp <= 0x33ff) ||
    (cp >= 0x3400 && cp <= 0x4dbf) ||
    (cp >= 0x4e00 && cp <= 0x9fff) ||
    (cp >= 0xa000 && cp <= 0xa4cf) ||
    (cp >= 0xac00 && cp <= 0xd7a3) ||
    (cp >= 0xf900 && cp <= 0xfaff) ||
    (cp >= 0xfe30 && cp <= 0xfe6f) ||
    (cp >= 0xff00 && cp <= 0xff60) ||
    (cp >= 0xffe0 && cp <= 0xffe6) ||
    (cp >= 0x1f300 && cp <= 0x1f64f) ||
    (cp >= 0x1f900 && cp <= 0x1f9ff) ||
    (cp >= 0x20000 && cp <= 0x3fffd)
  );
}

/**
 * The cells of a row of text, [width] of them: a glyph in the cell it
 * begins, `''` in the cell a wide glyph's second half covers. A row whose
 * glyphs do not add up to [width] (a width this approximation of twk's does
 * not agree with) is cut or padded with spaces to it, a glyph a cell.
 */
export function cellsOf(row: string, width: number): string[] {
  const glyphs = [...row];
  const cells: string[] = [];
  for (const g of glyphs) {
    cells.push(g);
    if (isWide(g.codePointAt(0)!)) {
      cells.push('');
    }
  }
  if (cells.length !== width) {
    cells.length = 0;
    cells.push(...glyphs);
  }
  while (cells.length < width) {
    cells.push(' ');
  }
  cells.length = width;
  return cells;
}

/** The style of the cell at column [x] of row [y]: `''` for none, null where the legend lacks its character. */
export function styleAt(file: ScreenFile, x: number, y: number): string | null {
  const char = [...file.styles[y]][x];
  return char === ' ' ? '' : (file.legend[char] ?? null);
}

/** A cell that differs between two screens. */
export interface CellChange {
  readonly x: number;
  readonly y: number;
  readonly text: readonly [string, string];
  /** The styles, null for a character the legend lacks. */
  readonly style: readonly [string | null, string | null];
}

/** What differs between a golden and the actual screen. */
export interface ScreenDiff {
  /** Both sizes, where they differ (then nothing else is compared). */
  readonly size: readonly [readonly [number, number], readonly [number, number]] | null;
  /** Both cursors, where they differ. */
  readonly cursor: readonly [readonly [number, number] | null, readonly [number, number] | null] | null;
  /** The cells whose text or style differs, row by row. */
  readonly cells: readonly CellChange[];
}

/** The difference of [golden] and [actual], cell by cell. */
export function diffScreens(golden: ScreenFile, actual: ScreenFile): ScreenDiff {
  if (golden.width !== actual.width || golden.height !== actual.height) {
    return { size: [[golden.width, golden.height], [actual.width, actual.height]], cursor: null, cells: [] };
  }
  const same = (a: readonly [number, number] | null, b: readonly [number, number] | null) => (a === null || b === null ? a === b : a[0] === b[0] && a[1] === b[1]);
  const cells: CellChange[] = [];
  for (let y = 0; y < golden.height; y++) {
    const g = cellsOf(golden.text[y], golden.width);
    const a = cellsOf(actual.text[y], actual.width);
    for (let x = 0; x < golden.width; x++) {
      const gs = styleAt(golden, x, y);
      const as = styleAt(actual, x, y);
      if (g[x] !== a[x] || gs !== as) {
        cells.push({ x, y, text: [g[x], a[x]], style: [gs, as] });
      }
    }
  }
  return { size: null, cursor: same(golden.cursor, actual.cursor) ? null : [golden.cursor, actual.cursor], cells };
}

/** Whether [diff] is no difference. */
export const isSame = (diff: ScreenDiff): boolean => diff.size === null && diff.cursor === null && diff.cells.length === 0;

/** A style, read: the colours as CSS colours (null for the terminal's own), the attributes as flags. */
export interface CellStyle {
  readonly fg: string | null;
  readonly bg: string | null;
  readonly underlineColor: string | null;
  readonly bold: boolean;
  readonly dim: boolean;
  readonly italic: boolean;
  readonly underline: 'solid' | 'double' | 'wavy' | 'dotted' | 'dashed' | null;
  readonly blink: boolean;
  readonly reverse: boolean;
  readonly hidden: boolean;
  readonly strike: boolean;
  readonly overline: boolean;
  readonly link: string | null;
}

/** The 16 colours of the palette, as xterm.js's defaults. */
const ansi = [
  '#000000', '#cd0000', '#00cd00', '#cdcd00', '#0000ee', '#cd00cd', '#00cdcd', '#e5e5e5',
  '#7f7f7f', '#ff0000', '#00ff00', '#ffff00', '#5c5cff', '#ff00ff', '#00ffff', '#ffffff',
];
const names = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white'];

function indexed(n: number): string | null {
  if (n < 16) {
    return ansi[n];
  }
  if (n < 232) {
    const level = (v: number) => (v === 0 ? 0 : 55 + v * 40);
    const c = n - 16;
    return `rgb(${level(Math.floor(c / 36))}, ${level(Math.floor(c / 6) % 6)}, ${level(c % 6)})`;
  }
  if (n < 256) {
    const g = 8 + (n - 232) * 10;
    return `rgb(${g}, ${g}, ${g})`;
  }
  return null;
}

/** The CSS colour of a colour as twk_test names it (`red`, `brightRed`, `#102030`, `indexed(33)`, `default`); null for the terminal's own or a name not known. */
export function colorCss(name: string): string | null {
  if (/^#[0-9a-f]{6}$/.test(name)) {
    return name;
  }
  const n = /^indexed\((\d+)\)$/.exec(name);
  if (n) {
    return indexed(Number(n[1]));
  }
  const bright = name.startsWith('bright');
  const base = bright ? name.charAt(6).toLowerCase() + name.slice(7) : name;
  const i = names.indexOf(base);
  return i < 0 ? null : ansi[i + (bright ? 8 : 0)];
}

const underlines: Readonly<Record<string, CellStyle['underline']>> = {
  underline: 'solid',
  doubleUnderline: 'double',
  curlyUnderline: 'wavy',
  dottedUnderline: 'dotted',
  dashedUnderline: 'dashed',
};

/** The style [text], as twk_test's `cellStyle` names one (`bold red on #010203 link=https://…`), read. Words it does not know are ignored. */
export function parseStyle(text: string): CellStyle {
  let link: string | null = null;
  const at = text.indexOf('link=');
  let words = text;
  if (at >= 0 && (at === 0 || text[at - 1] === ' ')) {
    link = text.slice(at + 5);
    words = text.slice(0, at);
  }
  const s = { fg: null as string | null, bg: null as string | null, underlineColor: null as string | null, bold: false, dim: false, italic: false, underline: null as CellStyle['underline'], blink: false, reverse: false, hidden: false, strike: false, overline: false };
  const tokens = words.split(' ').filter((w) => w !== '');
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (t === 'on') {
      s.bg = colorCss(tokens[++i] ?? '');
    } else if (t.startsWith('ul=')) {
      s.underlineColor = colorCss(t.slice(3));
    } else if (t in underlines) {
      s.underline = underlines[t];
    } else if (t === 'bold' || t === 'dim' || t === 'italic' || t === 'blink' || t === 'reverse' || t === 'hidden') {
      s[t] = true;
    } else if (t === 'strike' || t === 'overline') {
      s[t] = true;
    } else if (t.startsWith('underline(')) {
      s.underline = 'solid';
    } else {
      s.fg = colorCss(t);
    }
  }
  return { ...s, link };
}
