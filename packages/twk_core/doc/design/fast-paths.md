# twk_core design: fills and text fast paths

[The design](README.md)

## §1.9 Fills: `setRange` instead of `fillRange`

`fillRange` on Dart typed lists is an element-by-element loop, while
`setRange` within one list is a `memmove`. `lib/src/fill.dart` fills 16
elements and doubles the block with `setRange`. Whole rows are filled as one
block (not row by row), and runs of equal styles are found by scanning
64-bit words.

## §1.10 Text fast paths

* a run of printable ASCII is written in one tight loop (style from a
  micro-cache, damage once per run); the last character of the run goes to
  the full segmenter when a combining mark follows it;
* a single BMP character (box drawing, Cyrillic, CJK) skips the UAX #29
  machine when its own rules say it can't join a neighbour: `GCB=Other` and
  the next code point is not Extend/ZWJ/SpacingMark (in legacy mode: the
  next one is not zero-width); the canvas reference test runs in both
  modes and compares against the full segmenter.
