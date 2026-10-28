// The bytes between a twk app and its terminal cut into what they are:
// runs of text, control characters, and the escape sequences of ECMA-48
// as xterm.js parses them (ESC, CSI, SS3, OSC, DCS, APC, PM, SOS), each
// named for the sequence log: what the app wrote ([describeOutput]) and
// what the terminal sent, keys, the mouse and the answers to queries
// ([describeInput]). A sequence cut between two reads waits for the rest
// ([SequenceReader]), as twk_test's Vt and xterm.js do; DEC mode 2026
// (synchronized output) is found where it begins and ends ([syncChange]),
// which the log groups a frame by and a recording's player steps by.
// Pure: no node, no DOM; the webview's bundle may take it.

/** What an escape sequence is introduced by: ESC alone, or ESC and the byte that says which kind of string or sequence follows. */
export type TokenKind = 'text' | 'control' | 'esc' | 'ss3' | 'csi' | 'osc' | 'dcs' | 'apc' | 'pm' | 'sos' | 'mouse';

/** A piece of the stream: [raw] is its bytes as latin1, so as long as they are. */
export type Token =
  /** Text, decoded from UTF-8 (a character cut between reads put together). */
  | { readonly kind: 'text'; readonly raw: string; readonly text: string }
  /** A C0 control or DEL. */
  | { readonly kind: 'control'; readonly raw: string; readonly code: number }
  /** ESC, intermediates (0x20-0x2F), a final byte; or ESC alone at the end of input (the Escape key). */
  | { readonly kind: 'esc'; readonly raw: string; readonly intermediates: string; readonly final: string }
  /** ESC O and one byte. */
  | { readonly kind: 'ss3'; readonly raw: string; readonly final: string }
  /** CSI: a private prefix (`?`, `<`, `=`, `>`, or none), parameters, intermediates, the final byte. */
  | {
      readonly kind: 'csi';
      readonly raw: string;
      readonly prefix: string;
      readonly params: string;
      readonly intermediates: string;
      readonly final: string;
    }
  /** OSC, DCS, APC, PM or SOS: what is between its introducer and its end (BEL for OSC, or ST). */
  | { readonly kind: 'osc' | 'dcs' | 'apc' | 'pm' | 'sos'; readonly raw: string; readonly body: string }
  /** An X10 mouse report (input only): CSI M and three bytes, each 32 more than it says. */
  | { readonly kind: 'mouse'; readonly raw: string; readonly button: number; readonly x: number; readonly y: number };

const ESC = 0x1b;
const BEL = 0x07;

const latin1 = (bytes: Uint8Array, from: number, to: number): string => {
  let s = '';
  for (let i = from; i < to; i++) {
    s += String.fromCharCode(bytes[i]);
  }
  return s;
};

const strings: Record<number, 'osc' | 'dcs' | 'apc' | 'pm' | 'sos'> = { 0x5d: 'osc', 0x50: 'dcs', 0x5f: 'apc', 0x5e: 'pm', 0x58: 'sos' };

/**
 * Cuts a stream into [Token]s, read by read. Of what the app writes
 * ([input] false) a sequence cut off at the end of a read waits for the
 * next; of what the terminal sends ([input] true) each read is whole (a
 * key, a report, an answer), so a lone ESC at its end is the Escape key,
 * and `CSI M` takes the three bytes of an X10 mouse report.
 */
export class SequenceReader {
  private pending: Uint8Array = new Uint8Array(0);
  private readonly decoder = new TextDecoder('utf-8');

  constructor(private readonly input = false) {}

  /** The tokens of [bytes], with what waited from the read before. */
  read(bytes: Uint8Array): Token[] {
    let data = bytes;
    if (this.pending.length > 0) {
      data = new Uint8Array(this.pending.length + bytes.length);
      data.set(this.pending);
      data.set(bytes, this.pending.length);
      this.pending = new Uint8Array(0);
    }
    const tokens: Token[] = [];
    let i = 0;
    let textFrom = -1;
    const flushText = (to: number) => {
      if (textFrom >= 0) {
        const raw = latin1(data, textFrom, to);
        const text = this.decoder.decode(data.subarray(textFrom, to), { stream: true });
        textFrom = -1;
        if (text !== '') {
          tokens.push({ kind: 'text', raw, text });
        }
      }
    };
    while (i < data.length) {
      const b = data[i];
      if (b === ESC) {
        flushText(i);
        const t = this.escape(data, i);
        if (t === undefined) {
          this.pending = data.slice(i);
          return tokens;
        }
        tokens.push(t.token);
        i = t.end;
      } else if (b < 0x20 || b === 0x7f) {
        flushText(i);
        tokens.push({ kind: 'control', raw: String.fromCharCode(b), code: b });
        i++;
      } else {
        if (textFrom < 0) {
          textFrom = i;
        }
        i++;
      }
    }
    flushText(data.length);
    return tokens;
  }

  /** What waits for the rest of a sequence, as latin1; empty when nothing does. */
  get waiting(): string {
    return latin1(this.pending, 0, this.pending.length);
  }

  /** The escape sequence at [i] and where it ends; undefined when [d] ends inside it (output) . */
  private escape(d: Uint8Array, i: number): { token: Token; end: number } | undefined {
    if (i + 1 >= d.length) {
      return this.input ? { token: { kind: 'esc', raw: '\x1b', intermediates: '', final: '' }, end: i + 1 } : undefined;
    }
    const b1 = d[i + 1];
    const kind = strings[b1];
    if (kind !== undefined) {
      return this.string(d, i, kind);
    }
    if (b1 === 0x5b) {
      return this.csi(d, i);
    }
    if (b1 === 0x4f) {
      if (i + 2 >= d.length) {
        // ESC O at the end of a key: Alt+O
        return this.input ? { token: { kind: 'esc', raw: latin1(d, i, i + 2), intermediates: '', final: 'O' }, end: i + 2 } : undefined;
      }
      return { token: { kind: 'ss3', raw: latin1(d, i, i + 3), final: String.fromCharCode(d[i + 2]) }, end: i + 3 };
    }
    let j = i + 1;
    while (j < d.length && d[j] >= 0x20 && d[j] <= 0x2f) {
      j++;
    }
    if (j >= d.length) {
      return this.input ? { token: { kind: 'esc', raw: latin1(d, i, j), intermediates: latin1(d, i + 1, j), final: '' }, end: j } : undefined;
    }
    return { token: { kind: 'esc', raw: latin1(d, i, j + 1), intermediates: latin1(d, i + 1, j), final: String.fromCharCode(d[j]) }, end: j + 1 };
  }

  private csi(d: Uint8Array, i: number): { token: Token; end: number } | undefined {
    let j = i + 2;
    const paramFrom = j;
    while (j < d.length && d[j] >= 0x30 && d[j] <= 0x3f) {
      j++;
    }
    const paramTo = j;
    while (j < d.length && d[j] >= 0x20 && d[j] <= 0x2f) {
      j++;
    }
    if (j >= d.length) {
      return this.input ? { token: { kind: 'esc', raw: latin1(d, i, j), intermediates: '', final: '[' }, end: j } : undefined;
    }
    let params = latin1(d, paramFrom, paramTo);
    let prefix = '';
    if (params !== '' && '<=>?'.includes(params[0])) {
      prefix = params[0];
      params = params.slice(1);
    }
    const final = String.fromCharCode(d[j]);
    const intermediates = latin1(d, paramTo, j);
    if (this.input && final === 'M' && prefix === '' && params === '' && intermediates === '') {
      // X10: CSI M Cb Cx Cy
      const end = j + 4;
      if (end <= d.length) {
        return { token: { kind: 'mouse', raw: latin1(d, i, end), button: d[j + 1] - 32, x: d[j + 2] - 32, y: d[j + 3] - 32 }, end };
      }
    }
    return { token: { kind: 'csi', raw: latin1(d, i, j + 1), prefix, params, intermediates, final }, end: j + 1 };
  }

  /** A string of [kind]: OSC up to BEL or ST, the others up to ST, an ESC doubled inside tmux's passthrough. */
  private string(d: Uint8Array, i: number, kind: 'osc' | 'dcs' | 'apc' | 'pm' | 'sos'): { token: Token; end: number } | undefined {
    for (let j = i + 2; j < d.length; j++) {
      if (kind === 'osc' && d[j] === BEL) {
        return { token: { kind, raw: latin1(d, i, j + 1), body: latin1(d, i + 2, j) }, end: j + 1 };
      }
      if (d[j] !== ESC) {
        continue;
      }
      if (j + 1 >= d.length) {
        break;
      }
      if (d[j + 1] === 0x5c) {
        return { token: { kind, raw: latin1(d, i, j + 2), body: latin1(d, i + 2, j) }, end: j + 2 };
      }
      if (kind === 'dcs' && d[j + 1] === ESC) {
        j++;
      }
    }
    if (this.input) {
      return { token: { kind, raw: latin1(d, i, d.length), body: latin1(d, i + 2, d.length) }, end: d.length };
    }
    return undefined;
  }
}

/** Whether [t] begins (`CSI ? 2026 h`) or ends (`CSI ? 2026 l`) a synchronized update, once for each 2026 among its modes. */
export function syncChange(t: Token): number {
  if (t.kind !== 'csi' || t.prefix !== '?' || t.intermediates !== '' || (t.final !== 'h' && t.final !== 'l')) {
    return 0;
  }
  const n = t.params.split(';').filter((p) => p === '2026').length;
  return t.final === 'h' ? n : -n;
}

/** [raw] as the log shows it: ESC as `ESC`, other controls in caret notation, bytes above 0x7E in hex. */
export function visible(raw: string, max = 160): string {
  let s = '';
  for (const c of raw) {
    const code = c.charCodeAt(0);
    if (code === ESC) {
      s += s === '' || s.endsWith(' ') ? 'ESC ' : ' ESC ';
    } else if (code < 0x20) {
      s += `^${String.fromCharCode(code + 0x40)}`;
    } else if (code === 0x7f) {
      s += '^?';
    } else if (code > 0x7e && code <= 0xff) {
      s += `\\x${code.toString(16)}`;
    } else {
      s += c;
    }
    if (s.length > max) {
      return `${s.slice(0, max)}… (${raw.length} bytes)`;
    }
  }
  return s.trimEnd();
}

/** The numbers of [params] (`1;31`), a missing one as [fallback]. */
function numbers(params: string, fallback: number): number[] {
  return params === '' ? [fallback] : params.split(/[;:]/).map((p) => (p === '' ? fallback : Number.parseInt(p, 10)));
}

const controls: Record<number, string> = {
  0x00: 'NUL',
  0x07: 'BEL bell',
  0x08: 'BS backspace',
  0x09: 'HT tab',
  0x0a: 'LF line feed',
  0x0b: 'VT',
  0x0c: 'FF',
  0x0d: 'CR carriage return',
  0x0e: 'SO',
  0x0f: 'SI',
  0x7f: 'DEL',
};

/** The DEC private modes by number. */
export const decModes: Readonly<Record<number, string>> = {
  1: 'application cursor keys',
  3: '132 columns',
  5: 'reverse video',
  6: 'origin mode',
  7: 'autowrap',
  9: 'X10 mouse',
  12: 'cursor blinking',
  25: 'cursor visible',
  47: 'alternate screen',
  66: 'application keypad',
  69: 'left and right margins',
  1000: 'mouse buttons',
  1002: 'mouse drags',
  1003: 'mouse motion',
  1004: 'focus events',
  1005: 'UTF-8 mouse',
  1006: 'SGR mouse',
  1007: 'alternate scroll',
  1015: 'urxvt mouse',
  1016: 'SGR pixel mouse',
  1047: 'alternate screen',
  1048: 'cursor saved',
  1049: 'alternate screen, cursor saved',
  2004: 'bracketed paste',
  2026: 'synchronized output',
  2027: 'grapheme clusters',
  2031: 'colour scheme reports',
  2048: 'in-band resize',
  8452: 'sixel cursor at the right',
};

const ansiModes: Readonly<Record<number, string>> = { 4: 'insert mode', 20: 'automatic newline', 12: 'local echo off' };

const modeNames = (params: string, table: Readonly<Record<number, string>>) =>
  numbers(params, 0)
    .map((n) => `${n}${table[n] ? ` ${table[n]}` : ''}`)
    .join(', ');

const colors = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white'];

/** The SGR attributes of one number. */
const sgrNames: Readonly<Record<number, string>> = {
  0: 'reset',
  1: 'bold',
  2: 'dim',
  3: 'italic',
  5: 'blink',
  7: 'inverse',
  8: 'hidden',
  9: 'strikethrough',
  21: 'double underline',
  22: 'not bold or dim',
  23: 'not italic',
  24: 'not underlined',
  25: 'not blinking',
  27: 'not inverse',
  28: 'not hidden',
  29: 'not struck',
  39: 'fg default',
  49: 'bg default',
  53: 'overline',
  55: 'not overlined',
  59: 'underline colour default',
};

const underlines = ['off', 'single', 'double', 'curly', 'dotted', 'dashed'];

/** What SGR [params] set, briefly: `bold, fg red`, `fg #ff8800`, `reset`. */
export function describeSgr(params: string): string {
  const out: string[] = [];
  const ps = params.split(';');
  for (let i = 0; i < ps.length; i++) {
    const [head, ...sub] = ps[i].split(':');
    const n = head === '' ? 0 : Number.parseInt(head, 10);
    const color = (which: string): void => {
      // 38;5;n, 38;2;r;g;b, and their colon forms
      const rest = sub.length > 0 ? sub : ps.slice(i + 1);
      const mode = Number.parseInt(rest[0] ?? '', 10);
      if (mode === 5) {
        out.push(`${which} ${rest[1] ?? '?'}`);
        if (sub.length === 0) {
          i += 2;
        }
      } else if (mode === 2) {
        // a colon form may name a colour space first: 38:2::r:g:b
        const rgb = sub.length >= 5 ? rest.slice(2, 5) : rest.slice(1, 4);
        out.push(`${which} #${rgb.map((v) => (Number.parseInt(v, 10) || 0).toString(16).padStart(2, '0')).join('')}`);
        if (sub.length === 0) {
          i += 4;
        }
      } else {
        out.push(`${which} ?`);
      }
    };
    const plain = sgrNames[n];
    if (plain !== undefined) {
      out.push(plain);
    } else if (n === 4) {
      out.push(sub.length > 0 ? `underline ${underlines[Number(sub[0])] ?? sub[0]}` : 'underline');
    } else if (n === 38 || n === 48 || n === 58) {
      color(n === 38 ? 'fg' : n === 48 ? 'bg' : 'underline colour');
    } else if (n >= 30 && n <= 37) {
      out.push(`fg ${colors[n - 30]}`);
    } else if (n >= 40 && n <= 47) {
      out.push(`bg ${colors[n - 40]}`);
    } else if (n >= 90 && n <= 97) {
      out.push(`fg bright ${colors[n - 90]}`);
    } else if (n >= 100 && n <= 107) {
      out.push(`bg bright ${colors[n - 100]}`);
    } else {
      out.push(String(n));
    }
  }
  return out.join(', ');
}

const erase = ['to the end', 'to the start', 'all', 'and the scrollback'];

/** A CSI the app wrote, named. */
function describeCsiOut(t: Extract<Token, { kind: 'csi' }>): string {
  const { prefix, params, intermediates, final } = t;
  const n = numbers(params, 1);
  const key = `${prefix}${intermediates}${final}`;
  switch (key) {
    case 'A':
      return `CUU cursor up ${n[0]}`;
    case 'B':
      return `CUD cursor down ${n[0]}`;
    case 'C':
      return `CUF cursor right ${n[0]}`;
    case 'D':
      return `CUB cursor left ${n[0]}`;
    case 'E':
      return `CNL cursor down ${n[0]}, to column 1`;
    case 'F':
      return `CPL cursor up ${n[0]}, to column 1`;
    case 'G':
      return `CHA cursor to column ${n[0]}`;
    case 'H':
    case 'f':
      return `CUP cursor to row ${n[0]}, column ${n[1] ?? 1}`;
    case 'J':
      return `ED erase the screen ${erase[numbers(params, 0)[0]] ?? params}`;
    case 'K':
      return `EL erase the line ${erase[numbers(params, 0)[0]] ?? params}`;
    case '?J':
      return `DECSED erase the screen ${erase[numbers(params, 0)[0]] ?? params}, keeping protected cells`;
    case '?K':
      return `DECSEL erase the line ${erase[numbers(params, 0)[0]] ?? params}, keeping protected cells`;
    case 'L':
      return `IL insert ${n[0]} lines`;
    case 'M':
      return `DL delete ${n[0]} lines`;
    case 'P':
      return `DCH delete ${n[0]} characters`;
    case '@':
      return `ICH insert ${n[0]} blanks`;
    case 'X':
      return `ECH erase ${n[0]} characters`;
    case 'S':
      return `SU scroll up ${n[0]}`;
    case 'T':
      return `SD scroll down ${n[0]}`;
    case 'b':
      return `REP repeat the last character ${n[0]} times`;
    case 'd':
      return `VPA cursor to row ${n[0]}`;
    case 'm':
      return `SGR ${describeSgr(params)}`;
    case 'r':
      return params === '' ? 'DECSTBM scrolling region: all' : `DECSTBM scrolling region rows ${n[0]} to ${n[1] ?? 'the bottom'}`;
    case 's':
      return params === '' ? 'SCOSC save the cursor' : `DECSLRM margins columns ${n[0]} to ${n[1] ?? 'the right'}`;
    case 'u':
      return 'SCORC restore the cursor';
    case 'c':
      return 'DA1 query: primary device attributes';
    case '>c':
      return 'DA2 query: secondary device attributes';
    case 'n':
      return n[0] === 6 ? 'DSR query: the cursor position' : n[0] === 5 ? 'DSR query: status' : `DSR ${params}`;
    case '?n':
      return n[0] === 996 ? 'query: the colour scheme' : `DSR ? ${params}`;
    case 't':
      return describeWindowOps(params);
    case 'h':
      return `SM set ${modeNames(params, ansiModes)}`;
    case 'l':
      return `RM reset ${modeNames(params, ansiModes)}`;
    case '?h':
      return `DECSET ${modeNames(params, decModes)}`;
    case '?l':
      return `DECRST ${modeNames(params, decModes)}`;
    case '?$p':
      return `DECRQM query: mode ${modeNames(params, decModes)}`;
    case '$p':
      return `DECRQM query: ANSI mode ${modeNames(params, ansiModes)}`;
    case ' q':
      return `DECSCUSR cursor shape ${['default', 'blinking block', 'block', 'blinking underline', 'underline', 'blinking bar', 'bar'][numbers(params, 0)[0]] ?? params}`;
    case '>q':
      return 'XTVERSION query: the terminal name and version';
    case '?u':
      return 'kitty keyboard query: the flags';
    case '>u':
      return `kitty keyboard push flags ${numbers(params, 0)[0]}`;
    case '<u':
      return `kitty keyboard pop ${n[0]}`;
    case '=u':
      return `kitty keyboard set flags ${numbers(params, 0)[0]}${n[1] && n[1] !== 1 ? ` (mode ${n[1]})` : ''}`;
    case '?S':
      return `XTSMGRAPHICS ${['', 'colour registers', 'sixel geometry', 'ReGIS geometry'][n[0]] ?? params} query`;
    case '!p':
      return 'DECSTR soft reset';
    case '>m':
      return `XTMODKEYS ${params}`;
    default:
      return `CSI ${key}${params === '' ? '' : ` ${params}`}`;
  }
}

/** XTWINOPS (CSI ... t). */
function describeWindowOps(params: string): string {
  const [op, ...rest] = numbers(params, 0);
  switch (op) {
    case 8:
      return `XTWINOPS resize to ${rest[0]} rows, ${rest[1]} columns`;
    case 14:
      return 'XTWINOPS query: the window size in pixels';
    case 16:
      return 'XTWINOPS query: a cell size in pixels';
    case 18:
      return 'XTWINOPS query: the size in cells';
    case 22:
      return 'XTWINOPS push the title';
    case 23:
      return 'XTWINOPS pop the title';
    default:
      return `XTWINOPS ${params}`;
  }
}

/** An OSC, named by its number. */
function describeOsc(body: string, input: boolean): string {
  const semi = body.indexOf(';');
  const ps = semi < 0 ? body : body.slice(0, semi);
  const pt = semi < 0 ? '' : body.slice(semi + 1);
  const query = pt === '?' || pt.endsWith(';?');
  switch (ps) {
    case '0':
      return `OSC 0 title and icon "${pt}"`;
    case '1':
      return `OSC 1 icon "${pt}"`;
    case '2':
      return `OSC 2 title "${pt}"`;
    case '4':
      return input ? `OSC 4 answer: palette ${pt}` : query ? `OSC 4 query: palette colour ${pt.split(';')[0]}` : `OSC 4 palette ${pt}`;
    case '7':
      return `OSC 7 the working directory ${pt}`;
    case '8': {
      const uri = pt.slice(pt.indexOf(';') + 1);
      return uri === '' ? 'OSC 8 link end' : `OSC 8 link to ${uri}`;
    }
    case '9':
      if (pt.startsWith('4;')) {
        const [state, percent] = pt.slice(2).split(';');
        return `OSC 9;4 progress ${['removed', 'set', 'error', 'indeterminate', 'paused'][Number(state)] ?? state}${percent ? ` ${percent}%` : ''}`;
      }
      return `OSC 9 notification "${pt}"`;
    case '10':
      return input ? `OSC 10 answer: foreground ${pt}` : query ? 'OSC 10 query: the foreground colour' : `OSC 10 foreground ${pt}`;
    case '11':
      return input ? `OSC 11 answer: background ${pt}` : query ? 'OSC 11 query: the background colour' : `OSC 11 background ${pt}`;
    case '12':
      return query ? 'OSC 12 query: the cursor colour' : `OSC 12 cursor colour ${pt}`;
    case '22':
      return `OSC 22 pointer shape ${pt === '' ? 'default' : pt}`;
    case '52':
      return pt.endsWith(';?') ? 'OSC 52 clipboard query' : `OSC 52 clipboard (${pt.length - pt.indexOf(';') - 1} base64 bytes)`;
    case '99':
      return `OSC 99 notification ${pt}`;
    case '104':
      return 'OSC 104 reset the palette';
    case '110':
      return 'OSC 110 reset the foreground';
    case '111':
      return 'OSC 111 reset the background';
    case '112':
      return 'OSC 112 reset the cursor colour';
    case '133':
      return `OSC 133 prompt mark ${pt}`;
    case '777':
      return pt.startsWith('notify;') ? `OSC 777 notification ${pt.slice(7)}` : `OSC 777 ${pt}`;
    case '1337':
      return pt.startsWith('File=') ? `OSC 1337 iTerm2 image (${body.length} bytes)` : `OSC 1337 ${pt.slice(0, 40)}`;
    default:
      return `OSC ${ps}${pt === '' ? '' : ` ${pt.slice(0, 60)}`}`;
  }
}

/** A DCS, named by what it begins with. */
function describeDcs(body: string, input: boolean): string {
  if (body.startsWith('tmux;')) {
    return 'DCS tmux passthrough';
  }
  if (input && body.startsWith('>|')) {
    return `XTVERSION answer: ${body.slice(2)}`;
  }
  if (input && /^[01]\$r/.test(body)) {
    return body[0] === '1' ? `DECRQSS answer: ${body.slice(3)}` : 'DECRQSS answer: not recognised';
  }
  if (input && /^[01]\+r/.test(body)) {
    return `XTGETTCAP answer ${body.slice(3)}`;
  }
  if (body.startsWith('$q')) {
    return `DECRQSS query: ${body.slice(2)}`;
  }
  if (body.startsWith('+q')) {
    return `XTGETTCAP query ${body.slice(2)}`;
  }
  if (/^[0-9;]*q/.test(body)) {
    return `DCS sixel image (${body.length} bytes)`;
  }
  return `DCS ${body.slice(0, 40)}`;
}

/** An ESC sequence of the app's, named. */
function describeEscOut(t: Extract<Token, { kind: 'esc' }>): string {
  const key = `${t.intermediates}${t.final}`;
  const names: Record<string, string> = {
    '7': 'DECSC save the cursor',
    '8': 'DECRC restore the cursor',
    c: 'RIS reset the terminal',
    D: 'IND index',
    E: 'NEL next line',
    M: 'RI reverse index',
    H: 'HTS set a tab stop',
    '=': 'DECKPAM application keypad',
    '>': 'DECKPNM normal keypad',
    '\\': 'ST string terminator',
    '(B': 'G0 charset ASCII',
    '(0': 'G0 charset DEC line drawing',
    '#8': 'DECALN fill with E',
  };
  return names[key] ?? `ESC ${key}`;
}

/** What [t], written by the app, is. */
export function describeOutput(t: Token): string {
  switch (t.kind) {
    case 'text':
      return `text "${t.text}"`;
    case 'control':
      return controls[t.code] ?? `^${String.fromCharCode(t.code + 0x40)}`;
    case 'esc':
      return describeEscOut(t);
    case 'ss3':
      return `SS3 ${t.final}`;
    case 'csi':
      return describeCsiOut(t);
    case 'osc':
      return describeOsc(t.body, false);
    case 'dcs':
      return describeDcs(t.body, false);
    case 'apc':
      return t.body.startsWith('G') ? `APC kitty graphics ${t.body.slice(1, t.body.indexOf(';') < 0 ? 40 : Math.min(t.body.indexOf(';'), 40))}` : `APC ${t.body.slice(0, 40)}`;
    case 'pm':
      return `PM ${t.body.slice(0, 40)}`;
    case 'sos':
      return `SOS ${t.body.slice(0, 40)}`;
    case 'mouse':
      return `CSI M ${t.button} ${t.x} ${t.y}`;
  }
}

/** The modifiers of xterm's and kitty's parameter (1 + shift 1, alt 2, ctrl 4, super 8...). */
function modifiers(m: number | undefined): string {
  if (m === undefined || Number.isNaN(m) || m <= 1) {
    return '';
  }
  const bits = m - 1;
  return ['Shift', 'Alt', 'Ctrl', 'Super', 'Hyper', 'Meta', 'CapsLock', 'NumLock']
    .filter((_, i) => bits & (1 << i))
    .map((s) => `${s}+`)
    .join('');
}

const cursorKeys: Record<string, string> = { A: 'Up', B: 'Down', C: 'Right', D: 'Left', H: 'Home', F: 'End', E: 'Begin', P: 'F1', Q: 'F2', R: 'F3', S: 'F4' };

const tildeKeys: Record<number, string> = {
  1: 'Home',
  2: 'Insert',
  3: 'Delete',
  4: 'End',
  5: 'PageUp',
  6: 'PageDown',
  7: 'Home',
  8: 'End',
  11: 'F1',
  12: 'F2',
  13: 'F3',
  14: 'F4',
  15: 'F5',
  17: 'F6',
  18: 'F7',
  19: 'F8',
  20: 'F9',
  21: 'F10',
  23: 'F11',
  24: 'F12',
  200: 'paste begins',
  201: 'paste ends',
};

const kittyCodes: Record<number, string> = { 9: 'Tab', 13: 'Enter', 27: 'Escape', 32: 'Space', 127: 'Backspace' };

/** A key of [code] (a Unicode code point, or one of kitty's). */
function keyName(code: number): string {
  return kittyCodes[code] ?? (code > 32 && code < 0x110000 ? String.fromCodePoint(code) : `key ${code}`);
}

/** A mouse button of SGR's or X10's [b], with what it says of the modifiers and motion. */
function mouseButton(b: number): string {
  const mods = `${b & 4 ? 'Shift+' : ''}${b & 8 ? 'Alt+' : ''}${b & 16 ? 'Ctrl+' : ''}`;
  const motion = b & 32 ? ' moved' : '';
  const base = b & ~(4 | 8 | 16 | 32);
  const name = base >= 64 ? ['wheel up', 'wheel down', 'wheel left', 'wheel right'][base - 64] ?? `button ${base}` : ['left', 'middle', 'right', 'none'][base] ?? `button ${base}`;
  return `${mods}${name}${motion}`;
}

/** A CSI the terminal sent, named. */
function describeCsiIn(t: Extract<Token, { kind: 'csi' }>): string {
  const { prefix, params, intermediates, final } = t;
  const n = numbers(params, 1);
  if (prefix === '<' && (final === 'M' || final === 'm') && intermediates === '') {
    const [b, x, y] = numbers(params, 0);
    const what = mouseButton(b);
    const act = b & 32 ? '' : b >= 64 ? '' : final === 'M' ? ' press' : ' release';
    return `mouse ${what}${act} at column ${x}, row ${y}`;
  }
  if (prefix === '' && intermediates === '') {
    if (cursorKeys[final] && (params === '' || n[0] === 1)) {
      return `key ${modifiers(n[1])}${cursorKeys[final]}`;
    }
    if (final === '~') {
      return tildeKeys[n[0]] && n[0] >= 200 ? tildeKeys[n[0]] : `key ${modifiers(n[1])}${tildeKeys[n[0]] ?? `~${n[0]}`}`;
    }
    if (final === 'u') {
      const [code] = params.split(';')[0].split(':').map(Number);
      return `key ${modifiers(Number(params.split(';')[1]?.split(':')[0]))}${keyName(code)} (kitty)`;
    }
    if (final === 'R') {
      return `CPR answer: the cursor at row ${n[0]}, column ${n[1] ?? 1}`;
    }
    if (final === 'I') {
      return 'focus in';
    }
    if (final === 'O') {
      return 'focus out';
    }
    if (final === 't') {
      const [op, a, b] = numbers(params, 0);
      if (op === 6) return `answer: a cell is ${b}x${a} pixels`;
      if (op === 4) return `answer: the window is ${b}x${a} pixels`;
      if (op === 8) return `answer: the size is ${b}x${a} cells`;
      if (op === 48) return `in-band resize: ${params}`;
    }
    if (final === 'Z') {
      return 'key Shift+Tab';
    }
  }
  if (prefix === '?' && final === 'c') {
    return `DA1 answer: ${params}`;
  }
  if (prefix === '>' && final === 'c') {
    return `DA2 answer: ${params}`;
  }
  if (prefix === '?' && intermediates === '$' && final === 'y') {
    const [mode, value] = numbers(params, 0);
    return `DECRPM answer: mode ${mode}${decModes[mode] ? ` ${decModes[mode]}` : ''} ${['not recognised', 'set', 'reset', 'permanently set', 'permanently reset'][value] ?? value}`;
  }
  if (prefix === '?' && final === 'u') {
    return `kitty keyboard answer: flags ${numbers(params, 0)[0]}`;
  }
  if (prefix === '?' && final === 'n') {
    return n[0] === 997 ? `colour scheme answer: ${n[1] === 1 ? 'dark' : n[1] === 2 ? 'light' : n[1]}` : `DSR answer ? ${params}`;
  }
  if (prefix === '?' && final === 'S') {
    return `XTSMGRAPHICS answer: ${params}`;
  }
  return `CSI ${prefix}${intermediates}${final}${params === '' ? '' : ` ${params}`}`;
}

/** What [t], sent by the terminal (typed, or answered), is. */
export function describeInput(t: Token): string {
  switch (t.kind) {
    case 'text':
      return t.text === ' ' ? 'key Space' : [...t.text].length === 1 ? `key ${t.text}` : `typed "${t.text}"`;
    case 'control':
      switch (t.code) {
        case 0x0d:
          return 'key Enter';
        case 0x09:
          return 'key Tab';
        case 0x7f:
        case 0x08:
          return 'key Backspace';
        case 0x00:
          return 'key Ctrl+Space';
        default:
          return `key Ctrl+${String.fromCharCode(t.code + 0x40)}`;
      }
    case 'esc':
      if (t.final === '' && t.intermediates === '') {
        return 'key Escape';
      }
      return `key Alt+${t.intermediates}${t.final === '\x7f' ? 'Backspace' : t.final}`;
    case 'ss3':
      return `key ${cursorKeys[t.final] ?? `SS3 ${t.final}`}`;
    case 'csi':
      return describeCsiIn(t);
    case 'osc':
      return describeOsc(t.body, true);
    case 'dcs':
      return describeDcs(t.body, true);
    case 'mouse': {
      const motion = t.button & 32;
      const act = motion || (t.button & 3) === 3 ? '' : ' press';
      return `mouse (X10) ${(t.button & 3) === 3 && !motion ? 'release' : mouseButton(t.button)}${act} at column ${t.x}, row ${t.y}`;
    }
    default:
      return `${t.kind.toUpperCase()} ${t.body.slice(0, 40)}`;
  }
}
