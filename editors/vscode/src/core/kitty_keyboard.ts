// kitty's keyboard protocol (https://sw.kovidgoyal.net/kitty/keyboard-protocol/),
// as the twk terminal's webview speaks it where its capabilities say so:
// the flags an app pushes, pops and sets, one stack for each screen, and
// the keys encoded as those flags ask. Of the flags, disambiguation (1)
// alone is done: what twk pushes unless an app asks for more
// (`KittyKeyboardFlags.disambiguate`); the flags told back are those done.
// Nothing here imports anything: the webview's bundle takes it.

/** The flags of the protocol this end does: disambiguation. */
export const supportedFlags = 1;

/** The most a stack holds, as kitty: a push beyond drops the oldest. */
const stackLimit = 16;

export type Screen = 'normal' | 'alternate';

/** The protocol's state: a stack of flags for each screen, its top the flags in force. */
export class KittyKeyboard {
  private readonly stacks: Record<Screen, number[]> = { normal: [], alternate: [] };

  /** The flags in force on [screen]: 0, legacy keys, with none pushed. */
  flags(screen: Screen): number {
    return this.stacks[screen].at(-1) ?? 0;
  }

  /** `CSI > flags u`: [flags] pushed, of them those done. */
  push(screen: Screen, flags: number): void {
    const stack = this.stacks[screen];
    stack.push(flags & supportedFlags);
    if (stack.length > stackLimit) {
      stack.shift();
    }
  }

  /** `CSI < n u`: [count] popped (1 when not given); popping more than were pushed empties it. */
  pop(screen: Screen, count = 1): void {
    const stack = this.stacks[screen];
    stack.splice(Math.max(0, stack.length - Math.max(1, count)));
  }

  /** `CSI = flags ; mode u`: the top replaced (mode 1), or [flags] set (2) or reset (3) in it. */
  set(screen: Screen, flags: number, mode = 1): void {
    const stack = this.stacks[screen];
    const top = stack.at(-1) ?? 0;
    const next = mode === 2 ? top | flags : mode === 3 ? top & ~flags : flags;
    if (stack.length === 0) {
      stack.push(next & supportedFlags);
    } else {
      stack[stack.length - 1] = next & supportedFlags;
    }
  }

  /** The answer to `CSI ? u` on [screen]: the flags in force. */
  query(screen: Screen): string {
    return `\x1b[?${this.flags(screen)}u`;
  }

  /** Both stacks emptied: the terminal reset, or a new app. */
  reset(): void {
    this.stacks.normal = [];
    this.stacks.alternate = [];
  }
}

/** A key pressed, as a browser's KeyboardEvent tells it. */
export interface KeyPress {
  /** What it types (`a`, `A`, `!`), or its name (`Escape`, `Enter`). */
  readonly key: string;
  /** The key on the keyboard (`KeyA`, `Digit1`, `Escape`). */
  readonly code: string;
  readonly ctrl: boolean;
  readonly alt: boolean;
  readonly shift: boolean;
  readonly meta: boolean;
}

/** The keys that type nothing which disambiguation encodes as `CSI number u`, by name. */
const functional: Readonly<Record<string, number>> = { Escape: 27, Enter: 13, Tab: 9, Backspace: 127 };

/**
 * What [press] sends under [flags]: `CSI code ; modifiers u` for what
 * disambiguation makes unambiguous (Escape; a key with Ctrl or Alt; Enter,
 * Tab and Backspace with a modifier, which alone stay as in legacy mode),
 * or undefined: what xterm.js sends (text, arrows, function keys, whose
 * legacy forms are kitty's too). Keys with Meta (Cmd) are VS Code's.
 */
export function encodeKey(press: KeyPress, flags: number): string | undefined {
  if ((flags & supportedFlags) === 0 || press.meta) {
    return undefined;
  }
  const modifiers = (press.shift ? 1 : 0) | (press.alt ? 2 : 0) | (press.ctrl ? 4 : 0);
  const csi = (code: number) => (modifiers === 0 ? `\x1b[${code}u` : `\x1b[${code};${modifiers + 1}u`);
  const named = functional[press.key];
  if (named !== undefined) {
    return press.key === 'Escape' || modifiers !== 0 ? csi(named) : undefined;
  }
  if (!press.ctrl && !press.alt) {
    return undefined; // text, shifted or not
  }
  const base = baseKey(press);
  return base === undefined ? undefined : csi(base);
}

/**
 * The code point of the key [press] is, unshifted: kitty reports a key by
 * its lower case (Shift is among the modifiers). A letter or digit by where
 * it is ([KeyPress.code]), as Ctrl and Alt leave [KeyPress.key] what the
 * layout makes of it; another key by the one character it types.
 */
function baseKey(press: KeyPress): number | undefined {
  const letter = /^Key([A-Z])$/.exec(press.code);
  if (letter) {
    return letter[1].toLowerCase().charCodeAt(0);
  }
  const digit = /^Digit([0-9])$/.exec(press.code);
  if (digit) {
    return digit[1].charCodeAt(0);
  }
  if (press.code === 'Space' || press.key === ' ') {
    return 32;
  }
  const chars = [...press.key];
  if (chars.length !== 1) {
    return undefined; // a key of no character: Shift, an arrow, F1
  }
  return chars[0].toLowerCase().codePointAt(0);
}
