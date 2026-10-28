# Performance survey: where the frames and events go

Where the core and twk spend time and allocate, per frame and per event,
measured; ranked by what a fix would give back. Nothing is optimised here:
each finding is a proposed task of its own (the list at the end).

Measured on 2026-10-20 at `6b3e5e8`, Dart 3.13.5, linux x64, 200 × 60 cells
unless said otherwise. The findings below are as they were then; what the
fixes gave is the next section.

## After the fixes

The proposed tasks 1–12 are done (commits below). Measured on 2026-10-20 at
`b2a8caa` against `b49907b` (this survey's commit): `tool/bench.dart
--baseline=b49907b` with the sibling core busy at most 1.0 %, so the times
count; `tool/alloc/bin/alloc.dart` at each commit.

| scenario | µs before | µs after | ratio | B alloc before | B alloc after | objects before → after |
|---|---:|---:|---:|---:|---:|---|
| tree | 77.4 | 5.51 | ×0.07 | 848 | 864 | 11.0 → 11.0 |
| ellipsis | 447 | 144 | ×0.32 | 37 510 | 2 061 | 282.5 → 29.1 |
| wrap | 480 | 175 | ×0.36 | 47 915 | 2 100 | 353.7 → 28.4 |
| keys (2000 events) | 602 | 282 | ×0.47 | 624 / event | 151 / event | 13.3 → 1.4 |
| full-frame | 210 | 115 | ×0.54 | 928 | 928 | 12.0 → 12.0 |
| log-line | 9.91 | 8.96 | ×0.90 | 934 | 933 | 14.0 → 14.0 |
| pens | 102 | 97.0 | ×0.95 | 2 378 | 2 377 | 12.0 → 12.0 |
| typing, repaint-all, spinner, list-scroll | — | — | ×0.97–1.01 | — | — | unchanged |
| idle | 0.41 | 0.44 | ×1.07 (×1.10 on a 9-round rerun) | 3 | 3 | 0.1 → 0.1 |

No scenario writes more bytes per frame. The apps (JIT, per unit as in the
table below):

| scenario | B before | B after | objects before → after | scavenges / 1000 before → after |
|---|---:|---:|---|---|
| table-100k, a key | 353 760 | 32 865 | 6 766 → 601 | 10.0 → 2.5 |
| textarea-10k, a key | 87 354 | 34 660 | 1 278 → 266 | 3.1 → 3.1 |
| markdown-stream, 6 chars | 43 718 | 30 829 | 751 → 532 | 1.5 → 1.5 |
| mouse-flood, an event | 3 526 | 1 951 | 76.2 → 37.8 | 10.0 → 6.7 |
| listview-scroll, a frame | 15 447 | 15 185 | 261 → 256 | 0 → 0 |
| gallery-switch (120 × 36) | 2 076 179 | 1 518 426 | — | — (perf-parser-width's run) |

By task: 1 `1636a5f` (paragraph paint from one buffer), 2 `d40a97b`
(re-wrap only the edited part; a 16 000-case differential test), 3
`99a3357` (paint only the marked rows of a boundary; a 400-seed
partial-vs-full fuzz), 4 and 5 `fb2d8fe` (ValueKey hash, Table rows), 6
`ef442b9` (culling), 7 `d89292e` (presenter runs; byte digests over 10
configurations), 8 and 12 `5af947b`, `f50a95f` (parser, `stringWidth`; a
differential over 12.6 M events), 9 `881f4a8`, `1bcd018` (mouse
coalescing, shared with `HeadlessTerminal`), 10 `7feb600` (TextArea rows),
11 `0372d12` (MarkdownStream). Mouse coalescing is not seen by
mouse-flood's per-event numbers (it sends one motion a read): 30 motions in
one read give one event.

### The second round

The next round this section listed, and what a code review of the first
round found, are done. Measured on 2026-10-20 at `b0993e5` against
`3ee254b` (the first round's end): `tool/bench.dart --baseline=3ee254b`
with the sibling core busy at most 0.2 % (list-scroll, log-line and tree
again over 9 rounds, at most 0.0 %), so the times count; `tool/alloc` at
`b0993e5`.

| scenario | µs before | µs after | ratio |
|---|---:|---:|---:|
| wrap-bidi (new) | 998 | 176 | ×0.18 |
| tree | 5.71 | 4.03 | ×0.71 |
| log-line | 10.1 | 10.0 | ×1.00 |
| pens | 103 | 98.0 | ×0.95 |
| list-scroll | 17.9 | 17.6 | ×0.99 |
| idle | 0.43 | 0.42 | ×0.99 |
| spinner, typing, repaint-all, full-frame, wrap, ellipsis, keys | — | — | ×0.97–1.01 |

No scenario writes more bytes per frame. What each item gave:

- **idle**: the ×1.07 of the first round is real (two 9-round runs) and
  comes from where AOT places the code, not from code the frame runs: 97 %
  of the frame is `Presenter.present`, compiled to the same size before and
  after, and the time rises and falls from commit to commit, back to the
  base at commits that change only the input parser and `unicode`, which
  an idle frame never runs. Nothing to remove; at `b0993e5` it is ×0.99 of
  `3ee254b`.
- **`ValueKey ==`**: `identical`, `is`, the value, then the runtime types:
  20.0 → 12.8 ns AOT for equal int keys (13.1 before the first round), 9.5
  ns for keys of unrelated types, the hash 13.8 → 11.1 ns. Keys of related
  types with equal values (`ValueKey<num>(1)` and `ValueKey<int>(1)`) are
  about 150 ns, as before the first round. `17b58c3`.
- **Contexts per Table key**: `RenderList._itemAt` and the element walks
  made a closure and a context per item and element visited; table-100k
  199.5 → 62.4 contexts a key, 601 → 498 objects, 32 865 → 29 881 B.
  About 50 of the rest are the scenario's tester. `17b58c3`, `b0993e5`.
- **`MarkdownView(data)`**: `appended:` names the piece added, and the view
  checks its length and the text's end only: 49 → 0.13 µs at 50 KB (8 →
  0.13 at 8 KB), a frame 195 → 150 µs. Without it the whole text is
  compared, as before. `74ab768`.
- **TextArea**: `onEdited` gets the controller's value, its text joined
  only when read (0 joins for 5 keys, against 5 with `onChanged`); a
  scroll moves the rows still in view and paints those that came in (8 →
  1 row a step). `e484dc8`.
- **A bidi paragraph**: its levels resolved again from a safe point before
  the edit to one after it, its clusters' offsets shifted, the rows that
  did not change copied: wrap-bidi 998 → 176 µs. `91ea1b5`.
- **An open popover** repaints its own rows, not the whole overlay (a label
  rebuilt beside it: 13 rows → its row and the popover's), and follows a
  moved target in the same frame (`RenderObject.beforePaint`). `c052500`,
  `b0993e5`.
- **A Column** paints the children its clip shows, found by bisection, and
  forgets paint through the children that painted: scrolling a 10 000-child
  Column a row 418 → 4 µs a frame. `9fd14c0`, `7d373cb`.
- From the review: `paintChild` keeps the paint caches of children a
  repaint misses; a boundary covered by a repaint of the one above is not
  painted twice; followers are counted per subtree, not kept in a list
  (`d07b18f`); a nested split marks the outer dividers only when its joins
  moved (`d5e1932`).

| scenario (alloc, JIT) | B before | B after | objects before → after |
|---|---:|---:|---|
| list-scroll, a frame | 4 809 | 4 032 | 70.2 → 42.5 |
| listview-scroll, a frame | 15 185 | 15 194 | 255.6 → 231.1 |
| table-100k, a key | 32 865 | 29 881 | 601.3 → 498.4 |
| markdown-stream, 6 chars | 30 829 | 29 678 | 532.3 → 501.5 |
| textarea-10k, a key | 34 660 | 34 691 | 265.5 → 266.5 (scavenges / 1000 3.1 → 0) |
| wrap-bidi (new), a frame | — | 26 135 | 49.1 |

### The third round

The three items the second round left, and two the round's new
`LogView` brought up (its scrollbar column made a log narrower than the
screen), are done. Measured on 2026-10-21 at `4047801` against `c848642` (the
second round's end): `tool/bench.dart --baseline=c848642` with the pinned
core's sibling busy at most 0.2 %, so the times count; `tool/alloc` at
`4047801` in a clean worktree. No scenario writes more bytes per frame,
and none is slower by more than 5 %.

| scenario | µs before | µs after | ratio | B a frame before → after |
|---|---:|---:|---:|---|
| log-bar (new: a log beside a scrollbar column, no DECSLRM) | 53.1 | 12.7 | ×0.24 | 6 104.3 → 292.6 written |
| wrap-bidi | 172 | 168 | ×0.98 | 26 715 → 2 996 allocated |
| log-line, typing, spinner, idle, repaint-all, full-frame, tree, wrap, ellipsis, pens, list-scroll, keys | — | — | ×0.98–1.03 | unchanged |

log-bar now costs close to what log-line does (12.7 µs against 9.1, its 297
bytes against 225): `33c6617` scrolls the rows whole and rewrites the
scrollbar's cells, `7f5e11e` moves the damage with the cells. A key in
textarea-10k allocates 34 854 B (269.6 objects), as before: the scenario
types within a row, which `4504f63` did not change.

- **A bidi paragraph's edit** no longer joins the text of its spans: a
  view reads them as one text, and only what the levels are resolved over
  is copied (fewer than a sentence's code units an edit, against 5 341
  before, `test/render/bidi_join_test.dart`); the 20 KB string a frame is
  gone. The from-scratch path still joins. `315b59f`.
- **A TextArea edit** paints the rows whose text changed: a line break, a
  join or a rewrap moves the rows after it on the screen, as a scroll
  does. Rows painted for a key mid-text in an 8-row area: a line break 5
  → 2, Backspace joining two lines 5 → 2, a word wrapped onto the next row
  5 → 2, its undo 4 → 1. A TextField's `onChanged` costs no join of its
  own: the field joins its text once a change to draw it, with or without
  `onChanged` (5 joins for 5 keys in a 10 010-character field, about 7 µs
  of the 530–600 µs a key takes there, JIT), so it got no `onEdited`.
  `4504f63`.
- **`ValueKey ==`** of related types with equal values compares the type
  arguments (`identical(other._type, T) || other._type == T`) in place of
  the runtime types, which built `Type`s: `ValueKey<num>(1) ==
  ValueKey<int>(1)` 154 → 19.5 ns AOT, `Object` and `int` 155 → 21.6,
  `dynamic` and `Object?` 164 → 24.3, equal int keys 14.0 → 12.0
  (busy, the same order in every run). `79ddf57`.
- **A rectangle scrolled on a terminal without DECSLRM** (Konsole, many
  others), as a log beside its scrollbar is, scrolls as whole rows where
  that is estimated to write less, the cells beside it that the shift
  left different written again: a line appended beside a scrollbar
  column, 40 × 12, 534 → 164 bytes (inline 537 → 169); every
  configuration of `presenter_diff_test` writes fewer bytes (BCE 4 725 711
  → 4 723 143). `33c6617`.
- **`Surface.scrollRect`** moves the damage inside the rectangle with its
  cells and marks only the rows the move brought in, so after a widened
  move the presenter compares the cells beside it and the new rows, not
  the whole log: log-bar 34.6 → 16.3 µs (busy; 33.0 → 18.9 in a run at
  15.6 %). `7f5e11e`.

### Left

- wrap-bidi still makes 20 `_ArrayIterator`s a frame (983 B), not on the
  edit's path: for-in loops in `packages/twk_core/lib/src/unicode/bidi.dart` or the paint.
- log-bar is still about 4 µs above log-line: the rectangle's rows copied
  one by one, the scan that decides to widen, and the scrollbar's column
  repainted and compared each frame.
- A `LogView` at its cap shifts every item's index with each line, and
  `RenderList.moveItem` marks each unpainted, so its window repaints every
  frame (the bytes stay those of a scroll).
- The third round's times, measured on a busy machine.

### Konsole's lines and `Color.lerp`

The SGR reset before ICH and DCH on Konsole's lines (`f799745`) and
`Color` as an `Object` with `Color.lerp` (`ae6cd9a`), against the commit
before them (`dbe8281`), with every change since, the sibling core idle
(0.7 %): no scenario writes more bytes, none is slower (×0.96–×1.00),
log-bar 12.4 → 11.9 µs, wrap-bidi 172 → 167, pens 98.9 → 95.8. The reset
costs bytes only on Konsole's caps, which no scenario runs.

Konsole's images (`6c79af8`: kitty images placed again after any scroll,
ids reused) and the parser leaving ESC and a split character to their
completion (`cbb3078`), against `d33641b`, the sibling idle (0.3 %): no
more bytes; every scenario ×0.99–×1.02 but log-line ×1.06 (±10 %). Run
three times more (log-line, log-bar, spinner): log-line ×1.10, ×1.00,
×1.00, its baseline itself 8.71–9.37 µs. With no image shown the scroll
path gains a field read and the image loops stay empty, so the ×1.06 is
the scenario's noise.

## How it was measured

Three instruments, each for what it is right for:

- **Time, AOT** — `tool/bench.dart`, the core's frame benchmark: the
  median of batches of frames, AOT, pinned to CPU 23. Its run for this
  survey had the sibling (CPU 11) busy at most 0.6 % (load 2.9–3.3), so
  its times count; a second run of `idle,spinner,typing` (9 rounds,
  sibling ≤ 0.8 %) gave ×1.00 for each against `HEAD`.

  ```bash
  taskset -c 23 dart run tool/bench.dart --baseline=HEAD
  ```

- **Allocations and GC** — `tool/alloc/` (new, committed with this
  survey): the scenarios of `tool/bench.dart` and apps of twk, twk_rich and
  the gallery, under the VM service of the process itself, no package
  added. Per frame (or event): the bytes and objects allocated, by class;
  the scavenges and old-space collections per 1000 steps, their time and
  the longest pause; with `--cpu`, where the time went, from the VM's CPU
  samples. Counts don't depend on the machine's load.

  ```bash
  (cd tool/alloc && dart pub get)                    # once
  dart run tool/alloc/bin/alloc.dart                 # every scenario
  dart run tool/alloc/bin/alloc.dart --only=wrap,table-100k --cpu
  dart run tool/alloc/bin/alloc_gallery.dart --size=120x36 2>/dev/null
  ```

  How it counts (`tool/alloc/lib/profiler.dart`): the VM's allocation
  profile counts the objects in the heap, garbage not yet collected
  included, so a step is counted in a window — a full collection, a
  reading, the steps, a reading — and a window a scavenge ran in is dropped
  and the next made half as long. The readings are taken by an isolate of
  another group (its own heap) over the service's WebSocket, and what a
  window of no steps reads (the service's own work on the isolate) is
  taken off every window. Checked: 7000 objects of a class allocated in a
  window read as exactly 7000 (112000 bytes); a frame reads the same at
  100 and at 2000 frames a window (spinner 339 B and 337 B). The VM's own
  classes (code, inline caches, type objects: the JIT's) are summed apart
  as `(vm)`.

  It runs JIT (an AOT executable has no service): what escapes is
  allocated in both, after a warm-up of ≥ 1.5 s. Its µs column is JIT
  time and only says where JIT time goes; `tool/bench.dart` is the clock.

- **Micro-benchmarks**, AOT, for two claims a profile could not settle
  (below, where used).

An app scenario runs the real binding on a `HeadlessTerminal` with a
`FakeClock` (what `TwkTester` runs, less the emulator); its step includes
the clock's own futures and timers: `app-idle`, a still app, is that alone —
**3.4 KB / 61 objects a step** to take off the app rows below — and the
terminal's copy of each frame written (a `Uint8List` of the frame's bytes).

## The numbers

### Core scenarios (`tool/bench.dart`)

| scenario | µs/frame AOT | B written | B alloc/frame | objects | where the time goes (JIT samples) |
|---|---:|---:|---:|---:|---|
| idle | 0.41 | 0 | 3 | 0.1 | — |
| spinner | 1.77 | 15 | 336 | 7.0 | — |
| typing | 3.69 | 17 | 562 | 7.0 | present 48 % (`_tryRowShift` 33 %), paint 33 % — 27 samples only |
| log-line | 10.5 | 220 | 933 | 14.0 | `setRange` 44 % (`Surface.scrollRows`), diff 22 % |
| list-scroll | 17.5 | 137 | 4 931 | 71.9 | `setRange` 45 % (scroll moves), layout 19 % |
| repaint-all | 50.4 | 15 | 928 | 12.0 | paint 62 %, `_detectScroll` 34 % |
| tree | 77.5 | 51 | 848 | 11.0 | paint 71 %, `_detectScroll` 27 % |
| pens | 103 | 337 | 2 376 | 12.0 | paint 70 %, `_detectScroll` 21 % |
| full-frame | 212 | 6 063 | 932 | 12.1 | `_diffRow` 44 % self, `blankStyleOf` 12 %, `_dominantBlank` 7 % |
| ellipsis | 449 | 544 | 37 512 | 283 | layout 58 % (`_split` 49 %), paint 30 % |
| wrap | 484 | 649 | 47 874 | 353 | layout 55 % (`_split` 46 %), paint 34 % |
| keys (per event) | 0.30 | — | 625 | 13.3 | `_csi` 66 %, `_params` 34 %, `List` growth 19 % |

GC: every scenario's collections are scavenges; none ran an old-space
collection. wrap: 1.5 scavenges per 1000 frames, longest 1.9 ms;
list-scroll 0.5, 3.0 ms; keys 38 per 1000 bursts of 2000 events, 1.2 ms.

### Apps (`tool/alloc`, JIT)

| scenario | unit | B alloc/unit | objects | frames/unit | scav / 1000 steps | longest | µs/unit JIT |
|---|---|---:|---:|---:|---:|---:|---:|
| app-idle (the harness) | step | 3 437 | 61 | 0 | 0 | — | 4.5 |
| app-spinner | step | 4 834 | 88 | 0.21 | 0 | — | 7.9 |
| listview-scroll (100k) | frame | 15 621 | 264 | 1 | 0 | — | 53 |
| table-100k, Down/Up | key | 360 744 | 6 892 | 1 | 12.5 | 1.2 ms | 606 |
| textarea-10k, a key | key | 87 486 | 1 280 | 1 | 3.1 | 1.6 ms | 150 |
| markdown-stream | 6 chars | 41 933 | 727 | 0.25 | 1.5 | 2.8 ms | 165 |
| mouse-flood | event | 3 528 | 76 | 0.01 | 10 (per 100 events) | 0.9 ms | 4.0 |
| gallery-switch (120 × 36) | switch | 2 057 027 | 33 754 | 18.5 | 54.5 | 0.9 ms | 10 030 |

GC is not where the time goes: no scenario runs an old-space collection,
and the longest scavenge seen anywhere is 3.6 ms (table-100k, an earlier
run). What allocation costs is the allocating and initialising, which the
profiles put inside the functions below, and the scavenges it brings on in
an app that already holds a large heap.

## Ranked findings

Ranked by expected gain on realistic screens at 60 fps × how many apps
meet it, then risk. Lines are of `6b3e5e8`.

### 1. A paragraph is shaped and wrapped from scratch on any edit

- **Where.** `packages/twk_core/lib/src/render/text.dart`: the `spans` setter drops the
  shaping on any text change (421-424); layout then re-segments every span
  (`_split`, 642-751), finds word breaks again (`_findWordBreaks`, 801),
  re-breaks every line (`_layoutLines`, 943-1029); paint copies one
  `GlyphRun` per line per span (`_buildSegments`, `_glyphs.sublist(a, b)`,
  1844). `_split` reallocates its five typed arrays at exactly the new size
  when the text grows (657-663). An intrinsic height asked runs a full
  `_countLines` (1289, 1292) besides.
- **Cost class.** Algorithmic: O(text) segmentation and breaking for a
  one-character edit. Constant: 162 `Uint32List` + 162 `GlyphRun` per frame
  (40.6 KB + 5.2 KB of wrap's 47.9 KB).
- **Measured.** wrap 484 µs/frame AOT (a word typed into a paragraph
  covering 85 % of the screen), ellipsis 449 µs; 47.9 KB / 353 objects a
  frame; layout 55 %, `_split` alone 46 %, paint 34 %.
- **Change.** (a) Paint the lines' glyphs from the paragraph's one buffer
  (a `Canvas.run` of an offset and a length, or views) instead of a copy
  per line; grow the arrays by 1.5–2×. (b) Incremental: diff the old and
  new spans for a common prefix and suffix, re-split from the hard line
  break before the edit, re-break from the line the edit is on and stop
  where line starts line up with the old ones again.
- **Gain.** (a) ~45 KB and ~320 objects a frame off (≈ 95 % of wrap's
  allocation), ~10 % of its time. (b) wrap and ellipsis from ~480 µs to
  tens of µs: the edit's line, not the paragraph.
- **Risk.** (a) low. (b) high: bidi reordering, `ellipsisStart` /
  `ellipsisMiddle` and `maxLines` look at all lines; do (a) first.

### 2. One change repaints its whole repaint boundary, and present compares all of it

- **Where.** `RenderObject.markNeedsPaint` climbs to the boundary
  (`packages/twk_core/lib/src/render/object.dart`, 539-546); `RenderFlex.paint` paints every
  child (`flex.dart`, 498-503); a root boundary is filled blank first
  (`pipeline.dart`, 304-308). Every cell painted is damage, so the
  presenter compares every row of it again (`Presenter._detectScroll`'s
  pre-check, `presenter.dart` 2270-2305, then `_diffRow`). `RenderList`
  does the same to itself on a repaint mark outside layout:
  `_fullRepaint = true` (`list.dart`, 305-309).
- **Cost class.** Algorithmic: O(boundary area) paint and compare for a
  change of a few cells.
- **Measured.** tree (one 8-character text of 360 changed, no inner
  boundary): 77.5 µs/frame AOT, paint 71 %, `equalRangeU32` 27 %; pens (a
  sentence re-highlighted) 103 µs, paint 70 %, compare 21 %; repaint-all
  50 µs. textarea-10k (finding 7) and markdown-stream (finding 4) pay the
  same at app level.
- **Change.** Record a damage rectangle at the boundary and have
  containers paint only the children that meet it, clipped to it (the
  `paintsOver` machinery already knows overlaps); or make a `RenderText`
  with an opaque background a boundary of its own. In `RenderList`, mark
  the item, not the list.
- **Gain.** tree from 78 µs to a few µs (one text's cells painted and
  compared); the same for every app whose widgets change one at a time —
  most of them.
- **Risk.** Medium: overlapping children and translucent pens need the
  damage widened, and the root boundary's fill.

### 3. Selecting a row of a Table rebuilds every row in view; and every keyed hash builds a `Type`

- **Where.** `TableState._changed` is `setState(() {})`
  (`packages/twk/lib/src/data/table.dart`, 607-609): the next build makes
  every visible row again — a `Listener` keyed `ValueKey<Object>(key)`
  (1249), a `_Row`, a `Text` and a `Style` per cell — and the ListView
  reconciles them all (`list_view.dart`, `_rebuildItems`, 406-468, hashing
  each key into `byKey`). `ValueKey.hashCode` is
  `Object.hash(runtimeType, value)` (`framework.dart`, 91).
- **Cost class.** Algorithmic: O(rows in view × columns) widgets per key
  press. Constant: `runtimeType` of a generic class materialises a `Type`
  on every hash.
- **Measured.** table-100k: 361 KB / 6 892 objects per Down, 606 µs JIT,
  12.5 scavenges per 1000 keys; `Object.runtimeType` is 34 % of its CPU
  samples. AOT micro-benchmark (`ValueKey<Object>`-shaped key, 1000 keys ×
  2000): `hashCode` with `runtimeType` 273 ns, with the type literal
  instead 7.6 ns; `==` 8 ns AOT but 600 ns JIT (`dart run`).
- **Change.** (a) `ValueKey.hashCode => Object.hash(ValueKey, value)`
  (equality still checks the type). (b) Give each row the selection
  through a listenable or an `InheritedModel` aspect, so a move rebuilds
  the row left and the row entered.
- **Gain.** (a) ~265 ns per keyed hash AOT, about 30 µs per keyed list
  rebuild of 60 rows, more in debug runs; trivial. (b) ~25× fewer widgets
  per key in a 50-row view: 361 KB → ~15 KB.
- **Risk.** (a) low. (b) low to medium: sort and column changes still
  rebuild all rows.

### 4. Scroll views paint their whole content, then walk it again

- **Where.** `RenderObject.paintChild` paints a child its clip leaves
  nothing of (`object.dart`, 755-766); `RenderViewport` paints the whole
  content into the rows a scroll exposed, then `_forgetPaint` visits every
  node of it (`viewport.dart` 199-216, `object.dart` 1088-1090).
- **Cost class.** Algorithmic: O(content nodes) per frame and per wheel
  step of any `SingleChildScrollView`, however little of it shows.
- **Measured.** markdown-stream (an 8 KB answer in a
  `SingleChildScrollView`): paint 38 % of its samples, under
  `RenderViewport.paint`, though three steps in four change no visible
  cell (0.25 frames written per step).
- **Change.** In `paintChild`, return after
  `child.invalidatePaintCache()` when the child's rectangle doesn't meet
  the clip; keep a per-node "a paint cache below" flag so `_forgetPaint`
  stops early.
- **Gain.** Paint O(visible) for every scroll view without
  virtualisation: chat logs, Markdown answers, forms, the gallery's pages.
- **Risk.** Low for the cull; medium for the flag. Objects with side
  effects in paint must still run them when culled
  (`TextArea`'s `showCaret`/`hideCaret`, `text_area.dart` 760-764).

### 5. The presenter encodes a changed cell through a chain of calls

- **Where.** `Presenter._diffRow` (`presenter.dart` 1462-1569):
  per changed cell, `_bridge`, `_moveTo` (usually a no-op return),
  `_emitHere` → `_setStyleFor` → `out.codePoint` → `byte` → `_ensure(1)`
  per byte; `stats.cellsWritten++` and `caps.repeatChar` re-read per cell;
  a blank run's end found by `_blankPen`'s scan again for each cell of a
  short run (1514-1519, 1729-1732).
- **Cost class.** Constant per cell.
- **Measured.** full-frame (every cell written, 6 KB out): 212 µs/frame
  AOT; `_diffRow` 44 % self, `StyleTable.blankStyleOf` 12 %,
  `_dominantBlank` 7 %, `_emitHere`/`_moveTo` 8 %, `ByteSink._ensure` 2 %.
- **Change.** A run loop for plain narrow cells of one style that differ
  from the front: reserve `4 × n` bytes once and write unchecked; counts in
  locals; `caps` hoisted; the blank run's end and style cached while the
  cursor is inside it.
- **Gain.** 30–50 % of full-frame (≈ 70–100 µs): every resize, first frame,
  page switch, and theme change.
- **Risk.** Medium: `forceUntil`, uncertain glyphs and erases must stay
  out of the run; `test/presenter_fuzz_test.dart` guards it.

### 6. The input parser allocates a dozen objects per escape sequence

- **Where.** `packages/twk_core/lib/src/input/parser.dart`: `String.fromCharCodes(b.sublist
  (pStart, pEnd))` per CSI (511); `_params` splits on `;` then `:` into
  nested lists (524-535); two closures and `String.fromCharCode(fin)` per
  sequence (545-549). A bracketed paste collects into a `List<int>`
  through `addAll(b.sublist(...))` (112).
- **Cost class.** Constant per event.
- **Measured.** keys: 625 B / 13.3 objects per event, 0.30 µs AOT; 38
  scavenges per 2 M events; `_csi` 66 % of its samples, `List` growth 19 %,
  `split` 17 %.
- **Change.** Parse the parameters from the bytes into a reused
  `Int32List` (with sub-parameter marks), a fast path for `ESC [ <` mouse
  reports, the final byte compared as an int; a `BytesBuilder` for paste.
- **Gain.** ~10× fewer allocations per event, ~2–3× faster decoding; what
  matters in a mouse-motion flood (finding 8) and a large paste.
- **Risk.** Low: the parser's tests are thorough.

### 7. A keystroke in a TextArea repaints all its rows and rebuilds its row cache

- **Where.** `TextRows.update` builds a new map of every cached line's rows
  on each edit (`packages/twk/lib/src/editing/text_rows.dart`, 87-98); the
  area is one render object painting every visible row
  (`text_area.dart`, `_paintRow`); with the width following the text
  `_widestLine` measures every line again (523-531); `onChanged` gets the
  whole buffer joined into a String per edit (`_told`, 256-260).
- **Cost class.** Algorithmic in the cached lines (a map entry and a
  record each) and the rows in view (paint and compare); O(document) with a
  following width or an `onChanged`.
- **Measured.** textarea-10k (10 000 lines, a key mid-document, width
  bounded, no `onChanged`): 87 KB / 1 280 objects per key, 150 µs JIT;
  paint 53 %, `equalRangeU32` 17 %; 60 `MapEntry`, 366 `_Record`, 483
  closure contexts and 56 row substrings per key.
- **Change.** Shift the cache's keys in place (or keep it as a list per
  line); repaint the rows the edit changed (finding 2); keep a width per
  line for `_widestLine` from `TextBuffer.changeSince`.
- **Gain.** ~5× fewer allocations per key; paint and compare of a row, not
  the area.
- **Risk.** Low to medium.

### 8. Every mouse motion is hit-tested and dispatched; a flood is not coalesced

- **Where.** The terminal delivers each parsed event
  (`packages/twk_core/lib/src/terminal/terminal.dart`, 1355-1357); `MouseTracker.dispatch`
  hit-tests each (`packages/twk/lib/src/gestures/mouse.dart`, 572), builds
  an `at` closure and walks `now.reversed` (711-725), finds a target's
  offset by walking to the root and allocates a `PointerEvent` per callback
  (780-795); `AppBinding._dispatch` copies `_listeners.reversed.toList()`
  for every event no Listener took (`app_binding.dart`, 995).
- **Cost class.** Constant per event, × events per frame in a flood.
- **Measured.** mouse-flood (100 motions a frame over 480 hover-lit cells):
  3.5 KB / 76 objects per event, 4 µs JIT per event, 10 scavenges per 1000
  frames.
- **Change.** Drop a no-button `move` when the next event of the same read
  is a `move` with the same modifiers; use the hit result's local
  coordinates (`HitTestResult.xAt`/`yAt`) for its targets; no list copies
  per event.
- **Gain.** A sweep in mode 1003 from N hit tests and callback rounds per
  read to 1.
- **Risk.** Low for moves; drags must keep every point, and a region
  crossed inside one read gets no enter/exit.

### 9. An answer streaming into Markdown re-parses its open block per piece

- **Where.** `MarkdownStream.add` re-parses every line of the blocks not
  settled with a new `BlockParser` (`packages/twk_rich/lib/src/markdown/
  stream.dart`, 157-159), compares the result deeply with the last
  (`_keep`, 172 and 231), and copies all blocks and the definitions per piece
  (189-190). `MarkdownView(data)` compares the whole document again
  (`markdown_view.dart`, 170-172).
- **Cost class.** Algorithmic: O(open block) per piece, O(block²) over a
  long list or code block; O(blocks) copies.
- **Measured.** markdown-stream (6 characters a frame, the whole of 8 000
  counted, through `MarkdownView.blocks`): 42 KB / 727 objects per piece,
  165 µs JIT; build 25 %, paint 38 % (finding 4).
- **Change.** Keep the parser's state at the last settled line; the
  block list as settled + open without a copy; `MarkdownView(data)` to
  compare only the join.
- **Gain.** Per-piece cost O(the open block's tail).
- **Risk.** Medium: lazy continuation and loose lists can change earlier
  lines of the open block.

### 10. `stringWidth` makes a segmenter for every call

- **Where.** `stringWidth` (`packages/twk_core/lib/src/unicode/unicode.dart`, 539-546)
  allocates a `TextSegmenter` and a `ClusterScan` per call; it is called
  per label by tabs, menus, options, select, table measure
  (`table.dart` 1048), code and Markdown views, and per rune by the
  gallery's `paint.dart` (45).
- **Cost class.** Constant per call.
- **Measured.** gallery-switch: 3 514 `TextSegmenter` + 3 514
  `ClusterScan` per page switch (337 KB of 2.06 MB).
- **Change.** An ASCII fast path (width = length less controls) and one
  shared segmenter per mode and ambiguous width.
- **Gain.** ~16 % of a page switch's allocation; less per frame for every
  widget that measures labels.
- **Risk.** Low.

### 11. Smaller, measured

- **The gallery's page switch** — 2.06 MB / 33 754 objects and 18.5 frames
  per switch (120 × 36), 10 ms JIT; `RenderEffect.paint` 31 % of samples
  (`_RenderEffect.effectCell`, `packages/twk/lib/src/animation/effect.dart`
  179), 2 088 boxed `double`s per switch. For the Effect task under way,
  not a separate one.
- **Hardware-scroll moves** — `Surface.scrollRows` / `scrollRect` move the
  cells, styles and damage arrays with `setRange` (`surface.dart`
  321-324): 44–45 % of log-line's and list-scroll's JIT samples, but AOT
  (micro-benchmark, 11 800 cells) 0.7 µs a move up, 2.5 µs down. list-scroll
  is 17.5 µs a frame AOT: low priority; a row-offset ring would remove the
  moves at a large cost in risk.
- **`_tryRowShift` on typing frames** — 33 % of typing's samples
  (`presenter.dart` 619, 1980-2050), of a 3.7 µs frame. Its worst case
  (O(16·w) per row) did not show in any scenario: the cost loop stops once
  it can't beat rewriting the tail. A second must-match check at the head
  of the change would cut the common case.
- **`ListView` scrolling** — 15.6 KB a row scrolled, of which the
  harness 3.4 KB and `RenderList` 4.9 KB: the rest is the row's item built
  and the one leaving dropped; nothing O(items). `RenderList._childAt` is a
  linear search per item (`list.dart`, 555-572: O(built²)), 8 % of
  list-scroll's samples.
- **Rebuild bookkeeping** — `Element._renewDependencies` drops the
  dependency set on every build and makes a new one (`framework.dart`
  514, 544); `updateChildren` allocates its keyed map and runs
  `retainAll` even when there is nothing to do. Visible in table-100k's
  allocations (`_Record`, closures), not in its time.

## Already good — don't touch

- Idle frames: 3 B and 0 bytes written; a still app runs no frame;
  `Ticker`s stop when idle; `Spinner` repaints, doesn't rebuild (0.21
  frames a step, ~1.4 KB a frame above the harness).
- Fills (`fill.dart`), the identical-cell skip in `_diffRow`, damage spans,
  the style tables and their caches, `_composeRuns`, the row hashes of
  `_detectScroll`, the reused output buffers.
- `dependOnInheritedWidgetOfExactType` is a map lookup, not a walk;
  dirty elements are sorted once per scope; `updateChildren` follows the
  head/keyed-middle/tail scheme.
- `ListView` and `Table.source` are truly lazy: 100k rows cost what the
  rows in view cost; the table's sort is cached by data identity.
- `TextBuffer` is a piece table; `TextArea` paints only the rows in view.
- `MarkdownStream` keeps settled blocks and the view reuses their widgets.

## Checked and set aside

- **GC pauses.** No scenario ran an old-space collection; the longest
  scavenge was 3.6 ms, most under 2 ms. Allocation volume costs time where
  it is allocated, which the findings above count.
- **Depth sort of the dirty lists** (`pipeline.dart` 332 sorts by
  `depth`, which walks to the root): not in any scenario's samples.
- **Focus traversal**: per Tab press, not per frame.

## Proposed tasks

| # | title | area | expected gain | risk |
|---|---|---|---|---|
| 1 | Paint a paragraph's lines from its one glyph buffer; grow its arrays geometrically | `packages/twk_core/lib/src/render/text.dart`, `packages/twk_core/lib/src/canvas.dart` | wrap/ellipsis −95 % allocation (−45 KB/frame), ~−10 % time | low |
| 2 | Re-shape and re-wrap only the edited part of a paragraph | `packages/twk_core/lib/src/render/text.dart` | wrap/ellipsis 480 µs → tens of µs | high |
| 3 | Paint only the damaged part of a repaint boundary | `packages/twk_core/lib/src/render/object.dart`, `pipeline.dart`, `flex.dart`, `list.dart` | tree 78 → ~5 µs; every app where one widget changes at a time | medium |
| 4 | `ValueKey.hashCode` without `runtimeType` | `packages/twk/lib/src/framework/framework.dart` | 273 → 8 ns per keyed hash | low |
| 5 | A Table selection move rebuilds two rows, not all | `packages/twk/lib/src/data/table.dart` | table key 361 KB → ~15 KB, ~25× fewer widgets | low–medium |
| 6 | Cull children outside the clip in `paintChild`; stop `_forgetPaint` early | `packages/twk_core/lib/src/render/object.dart`, `viewport.dart` | scroll-view paint O(visible) | low–medium |
| 7 | A run loop for changed cells in the presenter's diff | `packages/twk_core/lib/src/presenter.dart`, `packages/twk_core/lib/src/byte_sink.dart` | full-frame −30–50 % (≈ −70–100 µs) | medium |
| 8 | Decode CSI parameters without strings or lists | `packages/twk_core/lib/src/input/parser.dart` | −90 % allocation per event, 2–3× faster | low |
| 9 | Coalesce mouse motion within a read; no per-event walks and copies | `packages/twk_core/lib/src/terminal/terminal.dart`, `packages/twk/lib/src/gestures/mouse.dart`, `binding/app_binding.dart` | N hit tests per read → 1 | low |
| 10 | TextArea: shift its row cache in place, repaint the rows an edit changed | `packages/twk/lib/src/editing/text_rows.dart`, `text_area.dart` | −80 % allocation per key | low–medium |
| 11 | MarkdownStream keeps its parser state at the last settled line | `packages/twk_rich/lib/src/markdown/stream.dart`, `markdown_view.dart` | per-piece O(open tail) | medium |
| 12 | `stringWidth` without a segmenter per call | `packages/twk_core/lib/src/unicode/unicode.dart` | −16 % of a gallery page switch's allocation | low |

Each task measures itself with the scenario named in its finding:
`tool/bench.dart --only=<name>` for time, `tool/alloc/bin/alloc.dart
--only=<name>` for allocations, before and after.
