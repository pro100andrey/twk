// The keys of the terminal's selection and clipboard, as terminals have
// them: copy the selection, paste. Pure, so a unit test runs it; main.ts
// hangs it on xterm.js's key handler. Keys are told by where they are
// ([ClipboardKey.code]: `KeyC`), not by the character they type, which a
// Russian or Greek layout makes another one.

/** What of a keyboard event the choice needs. */
export interface ClipboardKey {
  /** The event's `code`: the key's place, whatever the layout. */
  readonly code: string;
  readonly ctrl: boolean;
  readonly alt: boolean;
  readonly shift: boolean;
  readonly meta: boolean;
}

/**
 * What the key [k] asks of the clipboard, or undefined: it is the app's.
 * Ctrl+C and Ctrl+V stay the app's (^C, ^V) as in every terminal; the
 * keys that are not are Ctrl+Shift+C and Ctrl+Shift+V (Ctrl+Insert and
 * Shift+Insert too), and Cmd+C and Cmd+V on macOS ([mac]).
 */
export function clipboardAction(k: ClipboardKey, mac: boolean): 'copy' | 'paste' | undefined {
  if (k.alt) {
    return undefined;
  }
  if (mac && k.meta && !k.ctrl && !k.shift) {
    return k.code === 'KeyC' ? 'copy' : k.code === 'KeyV' ? 'paste' : undefined;
  }
  if (k.meta) {
    return undefined;
  }
  if (k.ctrl && k.shift && !mac) {
    return k.code === 'KeyC' ? 'copy' : k.code === 'KeyV' ? 'paste' : undefined;
  }
  if (k.ctrl && !k.shift && k.code === 'Insert') {
    return 'copy';
  }
  if (k.shift && !k.ctrl && k.code === 'Insert') {
    return 'paste';
  }
  return undefined;
}
