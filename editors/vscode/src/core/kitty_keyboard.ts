// kitty's keyboard protocol (https://sw.kovidgoyal.net/kitty/keyboard-protocol/),
// as the twk terminal's webview speaks it where its capabilities say so:
// the flags an app pushes, pops and sets, one stack for each screen, and
// the keys encoded as those flags ask. All five flags are done:
// disambiguation (1: what twk pushes unless an app asks for more,
// `KittyKeyboardFlags.disambiguate`), event types (2), alternate keys (4),
// all keys as escape codes (8) and associated text (16); the flags told back
// are those pushed that are done.
// Nothing here imports anything: the webview's bundle takes it.

/** The flags of the protocol this end does: all of them. */
export const supportedFlags = 31;

/** The flags' bits. */
export const flag = { disambiguate: 1, eventTypes: 2, alternateKeys: 4, allKeys: 8, associatedText: 16 } as const;

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

/** What a key does: goes down, repeats while held, comes up. */
export type KeyEventType = 'press' | 'repeat' | 'release';

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
  /** Down (the default), held down and repeating (`repeat`), or up. */
  readonly type?: KeyEventType;
  /** `KeyboardEvent.location`: 3 for the keypad. */
  readonly location?: number;
  /** Caps Lock and Num Lock are on. */
  readonly capsLock?: boolean;
  readonly numLock?: boolean;
  /** Part of an input method's composition (a dead key, an IME): the text is xterm.js's. */
  readonly composing?: boolean;
}

/** Modifier bits of the protocol (the field is 1 plus them). */
const mod = { shift: 1, alt: 2, ctrl: 4, capsLock: 64, numLock: 128 } as const;

/** The keys that type nothing which disambiguation encodes as `CSI number u`, by name. */
const functional: Readonly<Record<string, number>> = { Escape: 27, Enter: 13, Tab: 9, Backspace: 127 };

/** Keys xterm.js sends as kitty's legacy forms, `CSI number ; modifiers : event final`, by name: [number, final]. */
const legacyForm: Readonly<Record<string, readonly [number, string]>> = {
  ArrowUp: [1, 'A'],
  ArrowDown: [1, 'B'],
  ArrowRight: [1, 'C'],
  ArrowLeft: [1, 'D'],
  Home: [1, 'H'],
  End: [1, 'F'],
  F1: [1, 'P'],
  F2: [1, 'Q'],
  F3: [13, '~'],
  F4: [1, 'S'],
  Insert: [2, '~'],
  Delete: [3, '~'],
  PageUp: [5, '~'],
  PageDown: [6, '~'],
  F5: [15, '~'],
  F6: [17, '~'],
  F7: [18, '~'],
  F8: [19, '~'],
  F9: [20, '~'],
  F10: [21, '~'],
  F11: [23, '~'],
  F12: [24, '~'],
};

/** Keys reported only with all keys as escape codes: the modifier keys (by `code`; AltGr by `key`), lock keys and the rest of the functional ones. */
const modifierKeys: Readonly<Record<string, number>> = {
  ShiftLeft: 57441,
  ControlLeft: 57442,
  AltLeft: 57443,
  ShiftRight: 57447,
  ControlRight: 57448,
  AltRight: 57449,
};
const isoLevel3Shift = 57453;
const otherKeys: Readonly<Record<string, number>> = {
  CapsLock: 57358,
  ScrollLock: 57359,
  NumLock: 57360,
  PrintScreen: 57361,
  Pause: 57362,
  ContextMenu: 57363,
  MediaPlayPause: 57430,
  MediaStop: 57432,
  MediaTrackNext: 57435,
  MediaTrackPrevious: 57436,
  AudioVolumeDown: 57438,
  AudioVolumeUp: 57439,
  AudioVolumeMute: 57440,
};

/** The keypad's keys by `code`, with all keys as escape codes: KP_0 is 57399. */
const keypad: Readonly<Record<string, number>> = {
  Numpad0: 57399,
  Numpad1: 57400,
  Numpad2: 57401,
  Numpad3: 57402,
  Numpad4: 57403,
  Numpad5: 57404,
  Numpad6: 57405,
  Numpad7: 57406,
  Numpad8: 57407,
  Numpad9: 57408,
  NumpadDecimal: 57409,
  NumpadDivide: 57410,
  NumpadMultiply: 57411,
  NumpadSubtract: 57412,
  NumpadAdd: 57413,
  NumpadEnter: 57414,
  NumpadEqual: 57415,
  NumpadComma: 57416,
};
/** The keypad's keys with Num Lock off, which a browser names by what they do. */
const keypadNavigation: Readonly<Record<string, number>> = {
  ArrowLeft: 57417,
  ArrowRight: 57418,
  ArrowUp: 57419,
  ArrowDown: 57420,
  PageUp: 57421,
  PageDown: 57422,
  Home: 57423,
  End: 57424,
  Insert: 57425,
  Delete: 57426,
  Clear: 57427,
};

/** `F13` to `F24` are 57376 and on: no legacy form. */
const functionKey = /^F(1[3-9]|2[0-4])$/;

/**
 * What [press] sends under [flags], by kitty's protocol, or undefined for
 * what xterm.js sends (which is kitty's legacy form of the key, so the same).
 *
 * - 1, disambiguate: `CSI code ; modifiers u` for Escape; a key with Ctrl or
 *   Alt; Enter, Tab and Backspace with a modifier (alone they stay legacy);
 *   F13 to F24.
 * - 2, event types: the modifiers' field takes `:2` for a repeat and `:3`
 *   for a release. Releases come for the keys that come as escape codes, the
 *   keys of the legacy forms (`CSI 1 ; 1:3 A`) and the keys that type text
 *   (`CSI 97 u` typed, `CSI 97 ; 1:3 u` released); a repeat of the keys
 *   that type is their text again, and Enter, Tab and Backspace are not
 *   released unless all keys are escape codes. Without it a repeat is a
 *   press and a release nothing.
 * - 4, alternate keys: `code : shifted : base` where the key's code is the
 *   layout's and the shifted key (with Shift) or the key of a US layout in
 *   that place differ.
 * - 8, all keys as escape codes: text, Enter, Tab and Backspace too, and
 *   modifier, lock, media and keypad keys, which come as escape codes alone.
 * - 16, associated text, with 8: the text the key typed, as code points
 *   after the modifiers, for a press and a repeat of a key typing text
 *   (not with Ctrl, Alt, nor Enter, Tab or Backspace).
 *
 * Caps Lock and Num Lock are among the modifiers only with 8. Keys with Meta
 * (Cmd) are VS Code's, and a key in an input method's
 * composition xterm.js's.
 */
export function encodeKey(press: KeyPress, flags: number): string | undefined {
  flags &= supportedFlags;
  if (flags === 0 || press.meta || press.composing || press.key === 'Meta') {
    return undefined;
  }
  const events = (flags & flag.eventTypes) !== 0;
  const all = (flags & flag.allKeys) !== 0;
  let type = press.type ?? 'press';
  if (!events) {
    if (type === 'release') {
      return undefined;
    }
    type = 'press';
  }
  const modifiers = (press.shift ? mod.shift : 0) | (press.alt ? mod.alt : 0) | (press.ctrl ? mod.ctrl : 0);
  const reported = modifiers | (all && press.capsLock ? mod.capsLock : 0) | (all && press.numLock ? mod.numLock : 0);
  /** The sequence of [code] (and its alternates, or text) as asked: event type 1 and no modifiers are left out. */
  const csi = (code: string | number, final = 'u', text = ''): string => {
    const field = type !== 'press' ? `${reported + 1}:${type === 'repeat' ? 2 : 3}` : reported !== 0 ? `${reported + 1}` : '';
    const tail = text !== '' ? `;${field};${text}` : field !== '' ? `;${field}` : '';
    return `\x1b[${code}${tail}${final}`;
  };

  if (all) {
    const lone = press.key === 'AltGraph' ? isoLevel3Shift : modifierKeys[press.code] ?? otherKeys[press.key] ?? otherKeys[press.code];
    if (lone !== undefined) {
      return csi(lone);
    }
    const pad = keypadCode(press);
    if (pad !== undefined) {
      return csi(pad);
    }
  }
  if (functionKey.test(press.key)) {
    return csi(57376 + Number(press.key.slice(1)) - 13);
  }
  const legacy = legacyForm[press.key];
  if (legacy !== undefined) {
    // what xterm.js sends for a press is kitty's; the rest it does not tell
    return type === 'press' ? undefined : csi(legacy[0], legacy[1]);
  }
  const named = functional[press.key];
  if (named !== undefined) {
    if (press.key === 'Escape' || modifiers !== 0 || all) {
      return csi(named);
    }
    return undefined; // Enter, Tab and Backspace alone: legacy, and no release
  }
  const typesText = !press.ctrl && !press.alt;
  if (!all && typesText && type !== 'release') {
    return undefined; // text, shifted or not, and what repeats of it: xterm.js's
  }
  const keys = keyCodes(press, (flags & flag.alternateKeys) !== 0);
  if (keys === undefined) {
    return undefined;
  }
  let text = '';
  if (all && (flags & flag.associatedText) !== 0 && typesText && type !== 'release') {
    const chars = [...press.key];
    if (chars.length === 1) {
      text = String(chars[0].codePointAt(0));
    }
  }
  return csi(keys, 'u', text);
}

/** The keypad key [press] is, or undefined: by what it is, else (Num Lock off) what it does. */
function keypadCode(press: KeyPress): number | undefined {
  if (press.location !== 3) {
    return undefined;
  }
  return keypadNavigation[press.key] ?? keypad[press.code];
}

/**
 * The key's code and, with [alternates], the alternate codes after it:
 * `code`, `code:shifted`, `code::base`, `code:shifted:base`. kitty reports a
 * key by its lower case (Shift is among the modifiers), and, with
 * alternates, by the character the layout makes of it, the shifted key and
 * the key a US layout has there as alternates, as far as they differ. A
 * letter or digit is by where it is ([KeyPress.code]) without them, as Ctrl
 * and Alt leave [KeyPress.key] what the layout makes of it; another key by
 * the one character it types.
 */
function keyCodes(press: KeyPress, alternates: boolean): string | undefined {
  const position = positionKey(press);
  const chars = press.key === ' ' ? [' '] : [...press.key];
  const typed = chars.length === 1 ? chars[0] : undefined;
  if (position === undefined && typed === undefined) {
    return undefined; // a key of no character: Shift, an arrow, F1
  }
  if (!alternates) {
    return String(position ?? typed!.toLowerCase().codePointAt(0));
  }
  // macOS Option types another letter (å): then it is where the key is
  const option = press.alt && typed !== undefined && typed.codePointAt(0)! > 0x7f;
  const layout = typed !== undefined && !option && (/\p{L}/u.test(typed) || !press.shift) ? typed.toLowerCase().codePointAt(0)! : undefined;
  const code = layout ?? position ?? typed!.toLowerCase().codePointAt(0)!;
  const shifted = press.shift && typed !== undefined && !option ? typed.codePointAt(0)! : undefined;
  const base = position !== undefined && position !== code ? position : undefined;
  const shiftedOf = shifted !== undefined && shifted !== code ? shifted : undefined;
  const alt = [shiftedOf, base].map((c) => (c === undefined ? '' : String(c)));
  return base !== undefined ? `${code}:${alt[0]}:${alt[1]}` : shiftedOf !== undefined ? `${code}:${alt[0]}` : String(code);
}

/** The code point of the letter or digit [press] is by where it is, or the space; undefined for any other key. */
function positionKey(press: KeyPress): number | undefined {
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
  return undefined;
}
