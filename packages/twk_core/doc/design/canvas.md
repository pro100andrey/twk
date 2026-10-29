# twk_core design: cells, pens and damage

[The design](README.md)

## §1.1 A cell is two 32-bit words

`cells[i] = glyph | flags`, `styles[i] = style id` (two `Uint32List`s).
The glyph id **is the code point** for single-code-point characters (ASCII,
Cyrillic, CJK, box drawing — no tables, no allocation); larger ids are
interned multi-code-point graphemes (emoji ZWJ sequences, flags, combining
marks). All values are < 2²⁹, so they are Smis on every VM configuration.
Comparing a cell is two integer comparisons (the diff compares two cells at
a time through a 64-bit view); fills and scrolls are block copies with
`setRange` ([§1.9](fast-paths.md)).

## §1.2 Styles and pens

Applications paint with **pens** (`Pen`): a `null` color inherits from the
cell underneath, alpha < 255 blends over the background (like Flutter text
over a background). Composition results are cached in a hash table over
typed arrays (`(style, pen) → style`); an opaque pen bypasses it entirely.
The SGR sequence of every style and the **shortest transition between two
styles** (an attribute delta that accounts for the shared `22` reset of
bold/dim, or `0;…` when shorter) are computed once and cached. Colors are
downgraded to what the terminal supports (truecolor → 256 → 16; macOS
Terminal.app has no truecolor). The terminal's default background and
text colors come from OSC 11 and OSC 10, so alpha over "default" blends
with the real colors (default-colored text with alpha stays default while
the text color is unknown). Its first 16 palette entries come from OSC 4,
so a blend with a palette color (`Color.blue` and kin: a tint, a gradient
between two of them) goes through the color the terminal shows, not
xterm's (`StyleTable.paletteRgb`, `setPaletteRgb`; an entry the terminal
didn't tell stays xterm's, and SGR still names the index; `rgbOf(color,
text:)` any color as the RGB it shows, the default ones as told or null). When the
terminal reports new ones (after a change of its color scheme, [§1.7](terminal.md)),
`TwkApp` blends with those and repaints everything.

## §1.3 Damage without help from widgets

Every canvas primitive extends the dirty span of the rows it writes, and the
presenter compares only those spans. The widget layer never has to compute
damage rectangles, so it can't get them wrong (hand-computed damage is a
common source of stale cells). `Surface.scrollRows` moves rows **together
with their damage** and records the move; the presenter replays it in
hardware and compares only the exposed rows.
