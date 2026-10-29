# twk_core design: §1.4 Presenter (diff → bytes)

[The design](README.md)

* cursor model: picks the shortest of `CUP`, `CHA`, `CUF/CUB`, `CUD/CUU`,
  `CR`; adjacent cells are written without moves; short gaps in the same
  style are rewritten instead of skipped;
* a parameter equal to its default is left out: a count of 1 (`CUU`,
  `CUD`, `CUF`, `CUB`, `ICH`, `DCH`, `IL`, `DL`, `SU`, `SD` as `CSI A` and
  the like), column 1 of `CUP` (`CSI y H`, `CSI H`), and SGR 0 (`CSI m`);
* a visible cursor is hidden while a frame draws and shown again at its
  end; a frame that only moves it leaves it shown (it jumps once, so
  hiding it would prevent no flicker); on the whole screen a hidden one
  is put at `cursorX`, `cursorY` too, where the frame left it elsewhere,
  not where it wrote last: a terminal that marks the cursor's row
  (iTerm2's cursor guide) or follows it (macOS zoom) keeps still, and an
  idle frame still writes nothing (an inline region and a fixed viewport
  leave it as they need it);
* SGR only on a style change; blanks compare by how they look (background,
  attributes visible on a space and the colour of lines drawn on it), so a
  space inside text doesn't toggle SGR; a blank that needs an SGR change
  anyway takes the style of the text written right after it when a blank
  looks the same in both, so that text needs no SGR of its own;
* long blank runs use `ECH`/`EL` (BCE-aware: without BCE, erasing is used
  only for the default background);
* hardware scrolling with `DECSTBM + SU/SD` for recorded moves, declared
  scrolls (`scrollRegion`) and auto-detected ones (row hashes; a hash
  collision costs bytes, never correctness, because the diff runs against
  the shifted model). Recorded moves are replayed in order, each checked
  against the state the previous ones left. **SGR is reset before SU**
  (otherwise the exposed rows would be filled with a stray background);
* frames are wrapped in `DEC 2026`; autowrap is off (`DECAWM`), so no width
  error can wrap text into the next row or scroll the screen; a change
  within one row (≤ 64 bytes) is not wrapped — it can't tear, and the
  wrapper would cost 16 bytes;
* a full frame (the first one, after a resize or `invalidate()`) with
  `DEC 2026`: the most common blank style is painted with one `ED 2`
  (BCE), then only the other cells are written — no flash, because the
  frame is atomic;
* `REP` (`CSI n b`) for runs of one character (box lines `────`) — only for
  single code points and only on terminals known to support it (kitty,
  foot, alacritty, Ghostty, WezTerm, Windows Terminal, xterm, VTE ≥ 0.62);
* scroll detection first checks cheaply whether at least 3 rows changed
  (otherwise a scroll can't pay off and no hashes are computed); the diff
  reuses the result of that check, and the row hashes of the screen are
  cached between frames (tests verify the cache against a recomputation
  with `assert`);
* a frame with no changes is **0 bytes**.
