# twk_core design: §1.6 Input

[The design](README.md)

A real state machine: a sequence may be split at any byte and several may
arrive in one read. With the kitty keyboard protocol (detected by the probe)
the Escape key arrives as `CSI 27 u`, so a sequence split across reads —
common over slow ssh — is never mistaken for Escape; without it a lone ESC
counts as Escape after 30 ms, while a sequence whose parameters already
arrived gets 500 ms, so a slow link can't turn its tail into typed text. An
ESC inside an unterminated OSC/DCS string aborts it, as in a terminal's own
parser, so a truncated reply can't swallow the input that follows. The ESC
timeout never cuts a bracketed paste: it ends with its end marker, or, when
no input arrives for 2 s (`pasteTimeout`), the marker is taken as lost and
the paste is delivered, so later keys aren't pasted text forever. Modified
keys, F1–F12, the kitty keyboard protocol (`CSI u`, press/repeat/release),
SGR mouse (including the wheel with modifiers), bracketed paste, focus,
query replies (DECRPM, DA1, OSC 10/11, CPR), in-band resize (mode 2048),
color scheme reports (mode 2031: `ColorSchemeReport`, `CSI ? 997 ; 1 n`
dark, `; 2 n` light).
Backspace and Ctrl+Backspace follow the tty's erase character (DEL, or ^H on
some setups). Text is grouped by grapheme. A key arrives as a `KeyEvent`
whose `code` is a `KeyCode`: `KeyCode.char` for
text, the grapheme in `char`, or the key it is — `enter`, `up`, `f5` —
with its `modifiers` and `kind`. `Key` is left to the widgets' keys.

`TerminalOptions.kittyKeyboardFlags` asks for more of the kitty keyboard
protocol: a sum of `KittyKeyboardFlags` bits, its progressive
enhancements. Disambiguation (1) is always among them, and by default it
is the only one, so keys come as presses only.
`TerminalInfo.kittyKeyboardFlags` tells what was pushed (0 without the
protocol). The others:

* `eventTypes` (2): keys come repeated and released too, as the key's
  `kind` (`CSI 97 ; 1:3 u`, `CSI 1 ; 1:3 A`: `:2` a repeat, `:3` a
  release). A key that types text repeats as its text again. Enter, Tab
  and Backspace are released unreported unless `allKeysAsEscapes`.
* `alternateKeys` (4): a key comes with the key Shift makes of it. The
  base layout key it also carries is not decoded.
* `allKeysAsEscapes` (8): every key comes as a sequence, modifier keys
  alone too (no `KeyEvent` for those).
* `associatedText` (16): with `allKeysAsEscapes`, a key comes with the
  text it types.

Under any of them a key that types text (no modifier but Shift) is still
the text it types, with no modifiers, as without the flags. That text is
the associated text where the key carries it, else, with Shift, the
shifted key of `alternateKeys`; where neither tells it, the key is its
unshifted key with Shift. A shortcut (Ctrl, Alt, Super) is its unshifted
key, its modifiers kept. With `eventTypes`,
what acts on keys must act on presses and repeats and leave releases
alone, or a field types each letter twice. `twk`'s widgets do: a
`TextField` types, deletes, moves and submits on no release, and
`KeyCombo.accepts`, `Shortcuts` and the binding's Tab and Ctrl+C take
none.
