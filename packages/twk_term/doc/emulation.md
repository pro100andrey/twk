# What twk_term emulates

The [README](../README.md) is where to start. This is the dialect the emulator
speaks, and what it does not.

xterm's dialect, permissively: a sequence it doesn't know is ignored (`strict:
true` makes it a `FormatException`, for tests).

- **Screens**: the primary one with a scrollback (`scrollbackLimit` lines,
  1000 by default; lines scrolled off its top, by text or SU, while the top
  margin is its first row) and the alternate one (modes 47, 1047, 1049 with
  the cursor saved and restored), which keeps none.
- **Text**: UTF-8 (a malformed sequence printed as U+FFFD, a character split
  between writes put together), split into cells by the core's `TextSegmenter`
  — code point by code point like wcwidth by default, by grapheme clusters
  with `textMode: TextMode.graphemes` or once the program sets DEC mode 2027.
  Two-column glyphs take a leading and a trailing cell; overwriting either
  half blanks the other. A combining mark, a variation selector or the rest of
  an emoji sequence joins the cell left of the cursor, also when it comes in a
  later write; a VS16 that makes it two columns wide widens it. Autowrap with
  a pending wrap (DECAWM; a two-column glyph that doesn't fit in the last
  column wraps whole), insert mode (IRM), LNM, REP.
- **Cursor**: CUP, HVP, CUU, CUD, CUF, CUB, CNL, CPL, CHA, HPA, HPR, VPA, VPR,
  IND, RI, NEL, CR, LF, VT, FF, BS, HT, CHT, CBT, HTS, TBC, DECSC, DECRC,
  SCOSC, SCORC, origin mode (DECOM), its visibility (DECTCEM), blinking (12)
  and shape (DECSCUSR).
- **Editing**: ED (3 clears the scrollback), EL, ECH, ICH, DCH, IL, DL, SU,
  SD, DECSTBM, DECALN; erased and scrolled-in cells take the current
  background (BCE). DECSED and DECSEL as ED and EL.
- **Attributes**: SGR bold, dim, italic, underline in its styles (`4:0` to
  `4:5`, 21 double), blink, reverse, hidden, strike, overline; the 16 colors
  and their bright forms, 256 and 24-bit ones with `;` and `:` (`38;5;n`,
  `38;2;r;g;b`, `38:2::r:g:b`, `38:2:r:g:b`), and underline colors (58, 59).
  Reverse video of the whole screen (DECSCNM) is applied when it is painted.
- **Character sets**: G0 to G3 designated as ASCII, DEC special graphics or
  UK, SO, SI, SS2, SS3, LS2, LS3.
- **Modes the host acts on** (see below): DECCKM, DECKPAM/DECNKM, the mouse
  (X10 9, 1000, 1002, 1003; UTF-8 1005, SGR 1006, urxvt 1015), focus (1004),
  alternate scroll (1007), bracketed paste (2004), synchronized output (2026).
  XTSAVE and XTRESTORE, DECSTR, RIS.
- **Keys**: xterm's (`keySequence`), or the kitty keyboard protocol's once the
  program set its flags (`kittyKeySequence`): `CSI > flags u` pushes them,
  `CSI < n u` pops, `CSI = flags ; mode u` sets, ors or and-nots them, `CSI ?
  u` asks (`CSI ? flags u`); a stack of 16 for each screen, which RIS empties.
  Disambiguated keys, event types (repeats and releases), alternate keys (the
  capital of a letter typed with Shift), all keys as escape codes and their
  text, as kitty sends them.
- **Answers**: DA1 (`CSI ? 62 ; 22 ; 52 c`), DA2, DA3, XTVERSION (`twk_term
  0.2.0`), DSR 5 and 6, DECXCPR, DSR 15, 25, 26 and 996 (the color scheme,
  from the background), DECRQM for every mode it knows (0 for those it
  doesn't, 4 for 132 columns, smooth scrolling, reverse wraparound and xterm's
  meta and keypad variants), DECRQSS for SGR, DECSTBM, DECSCUSR, DECSCL and
  DECSCA, XTGETTCAP (no capability is told), XTWINOPS 14, 16 (once the host
  has set `cellPixelWidth` and `cellPixelHeight`), 18 and 19, OSC 4, 10, 11
  and 12 queries, ended as the query was (BEL or ST); of OSC 4, the first 256
  queries of a sequence, so that its replies are not many times its length.
- **OSC**: titles and icon names (0, 1, 2, with the title stack of XTWINOPS 22
  and 23), the palette (4, 104), the default colors (10, 11, 12 and their
  resets), the working directory (7, a `file:` URI only), hyperlinks (8, kept
  in the cells' styles, a URI of at most 2083 characters, VTE's limit; an
  erase takes them), notifications (9, 777) and progress (9;4), shell prompts
  (133), the pointer shape (22), the clipboard (52) — handed to the host as
  events, none executed. A title, an icon name, a notification's title and
  body and a pointer shape keep their first 4096 code units.

Not spoken: left and right margins (DECLRMM, reported unknown, so programs
don't use them), double-width and double-height lines (drawn single), 132
columns, sixel and other images (their strings skipped), rectangle operations
(DECFRA, DECERA, …), C1 controls as single bytes (in UTF-8 they are parts of
characters; as characters they print nothing).

## Resizing

`resize` rewraps the primary screen and its scrollback: lines the program's
text wrapped are joined and split again at the new width (a two-column glyph
never cut), the cursor staying on the character it was on, a wrap pending
where it ends up past the last column. The screen then shows the last lines
with the cursor's among them: the blank rows below the cursor go first, then
lines go to the scrollback when it gets shorter, and come back from it when it
gets taller. The alternate screen, which its program redraws on SIGWINCH, is
cut or padded, keeping the cursor's row. The margins are reset, the tab stops
extended.
