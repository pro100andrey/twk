# Performance survey: where the frames and events go

Where the core and twk spend time and allocate, per frame and per event:
what is measured and how, the figures, the costs that remain and what
would remove them.

Conditions of the figures unless said otherwise: Dart 3.13.5, linux x64,
an AMD Ryzen 7 8745HS kept for measuring, 200 x 60 cells, `tool/bench.dart`
pinned to CPU 15 with its SMT sibling (CPU 7) busy at most 0.2 % of the
rounds, so the times count. A scenario measured with the sibling busy is
said so.

## How it is measured

Three instruments, each for what it is right for:

- **Time, AOT** - `tool/bench.dart`, the core's frame benchmark. The
  scenarios live in `tool/frame_scenarios`. Each runs 64 frames into the
  test emulator (`package:twk_test/vt.dart`) before it is timed: a screen
  that differs from what was painted, or output the emulator rejects,
  stops the benchmark, so a broken scenario cannot report a fast number.
  Bytes written per frame are the mean over those frames: exact, the same
  on every machine. Times are the median of batches of frames, compiled
  with `dart compile exe`, one executable run per round (`--rounds`, 5 by
  default). With `--baseline=REF` it compiles itself against REF, checked
  out in a temporary git worktree, and runs the two executables
  alternately, so load that drifts during the run affects both alike. The
  report gives the load average and how busy the pinned core's sibling
  was.

  ```bash
  dart run tool/xtask.dart bench                       # the work against HEAD
  taskset -c 23 dart run tool/bench.dart --baseline=HEAD
  dart run tool/bench.dart --only=wrap,tree --size=120x36
  ```

  The xtask task `bench` takes the bench lock, pins the run to CPU 23
  (`BENCH_CPU`), takes the baseline from `BENCH_BASELINE` (`HEAD` unless
  set), and fails when a scenario writes more bytes per frame or is slower
  by more than 5 % while the sibling was idle. Slower while the sibling
  was busy is reported, not failed.

- **Allocations and GC** - `tool/alloc/`: the scenarios of
  `tool/bench.dart` and apps of twk, twk_rich and the gallery, under the VM
  service of the process itself. Per frame (or event): the bytes and
  objects allocated, by class; the scavenges and old-space collections per
  1000 steps, their time and the longest pause; with `--cpu`, where the time
  went, from the VM's CPU samples; with `--trace=CLASS,...`, where the
  objects of those classes were allocated. Counts do not depend on the
  machine's load.

  ```bash
  dart run tool/alloc/bin/alloc.dart                 # every scenario
  dart run tool/alloc/bin/alloc.dart --only=wrap,table-100k --cpu
  dart run tool/alloc/bin/alloc_gallery.dart --size=120x36 2>/dev/null
  ```

  How it counts (`tool/alloc/lib/profiler.dart`): the VM's allocation
  profile counts the objects in the heap, garbage not yet collected
  included, so a step is counted in a window - a full collection, a
  reading, the steps, a reading - and a window a scavenge ran in is
  dropped and the next made half as long. The readings are taken by an
  isolate of another group (its own heap) over the service's WebSocket,
  and what a window of no steps reads (the service's own work on the
  isolate) is taken off every window. The VM's own classes (code, inline
  caches, type objects: the JIT's) are summed apart as `(vm)`. An app
  runs on a synchronous clock of the tool's own (`lib/sync_clock.dart`), so
  its steps cost what the app does, not a test clock's turns of the event
  loop; `app-idle`, a still app, shows what is left of the tool's.

  It runs JIT (an AOT executable has no service): what escapes is
  allocated in both, after a warm-up of at least 1.5 s. Its microsecond
  column is JIT time and only says where JIT time goes; `tool/bench.dart`
  is the clock.

- **Micro-benchmarks**, AOT, for a claim a profile cannot settle, such as
  what a hash or a scroll move costs by itself.

## The figures

### Core scenarios (`tool/bench.dart`, AOT)

Time per frame, and bytes allocated per frame (JIT, `tool/alloc`) with
objects, all of one run of each tool. Bytes written per frame are the mean
over the scenario.

| scenario | what a frame is | us/frame | B written | B alloc | objects |
|---|---|---:|---:|---:|---:|
| idle | nothing changed | 0.27 | 0 | 3 | 0.1 |
| spinner | the spinner and the rate in the header | 1.04 | 15 | 336 | 7.0 |
| typing | a character typed or deleted mid-line | 2.27 | 17 | 563 | 7.0 |
| log-line | a line appended to the log, the count updated | 4.91 | 220 | 934 | 14.0 |
| log-bar | a line appended to the log beside a scrollbar column, no DECSLRM margins | 6.73 | 293 | 923 | 14.0 |
| list-scroll | a row scrolled in a list of 100k items of 1 to 3 rows | 8.00 | 137 | 2 724 | 22.1 |
| repaint-all | every object repainted, the spinner changed | 26.8 | 15 | 384 | 8.0 |
| tree | one text changed in rows x 6 texts, no inner boundary | 2.11 | 51 | 320 | 7.0 |
| pens | a sentence of the paragraph highlighted: new pens, no layout | 53.5 | 337 | 2 233 | 9.6 |
| full-frame | the screen forgotten: every cell written | 48.9 | 6 063 | 384 | 8.0 |
| ellipsis | the same paragraph cut off at 2/3 of the rows with an ellipsis | 61.9 | 544 | 1 500 | 14.6 |
| wrap | a word typed into a mixed-script paragraph, re-wrapped | 73.7 | 649 | 1 547 | 17.4 |
| wrap-bidi | a word typed into a Latin, Hebrew and Arabic paragraph in visual order | 88.9 | 764 | 1 817 | 25.4 |
| keys | 2000 key and mouse events decoded | 75.7 per 2000 | - | 76 per event | 1.2 per event |

GC: every scenario's collections are scavenges; none ran an old-space
collection.

### Apps (`tool/alloc`, JIT)

Per unit (a key, a frame, a switch) of the app scenarios:

| scenario | unit | B alloc/unit | objects |
|---|---|---:|---:|
| app-idle, a still app | frame | 4 | 0.1 |
| app-spinner | frame | 602 | 10.9 |
| listview-scroll (100k) | frame | 6 879 | 86.4 |
| table-100k, Down/Up | key | 15 472 | 251 |
| selection-list (1000), Down/Up | key | 19 225 | 256 |
| textarea-10k, a key | key | 14 438 | 130 |
| field-in-dialog | frame | 7 158 | 109 |
| gauges-live | frame | 7 017 | 102 |
| markdown-stream | 6 chars | 21 564 | 392 |
| log-append, at its cap of 2000 lines | line | 27 194 | 389 |
| mouse-flood | event | 1 451 | 29.9 |
| gallery-switch (120 x 36) | switch | 1 309 838 | 20 637 |

No scenario runs an old-space collection, and the longest scavenge seen
anywhere is 4.8 ms (gauges-live). GC is not where the time goes: what allocation costs is
the allocating and initialising, which the profiles put inside the
functions that allocate, and the scavenges it brings on in an app that
already holds a large heap.

## How the frame path is built

These are properties of the code that the figures above rest on.

- **A paragraph** (`render/text.dart`) paints from one glyph buffer
  instead of a copy per line, and an edit re-wraps only the part it
  touched, found by comparing the old and new spans for a common prefix and
  suffix and stopping where line starts line up with the old ones again.
  A right-to-left paragraph resolves its levels again from a safe point
  ahead of the edit to one past it, shifts its clusters' offsets and copies
  the rows that did not change; an edit does not join the spans' text (a view
  reads them as one text, and only what the levels are resolved over is
  copied). The from-scratch path still joins.
- **A repaint boundary** paints only the rows marked, not the whole
  boundary, and the presenter compares only the damage. `paintChild`
  keeps the paint caches of children a repaint misses; a boundary covered
  by a repaint of the one above is not painted twice; followers are counted
  per subtree, not kept in a list.
- **Culling.** A `RenderFlex` (a Column) paints the children its clip shows,
  found by bisection, and forgets paint through the children that painted;
  `paintChild` returns early for a child the clip leaves nothing of.
  Scrolling a 10 000-child Column a row costs about 4 us a frame.
- **An open popover** repaints its own rows, not the whole overlay, and
  follows a moved target in the same frame (`RenderObject.beforePaint`).
- **The presenter** runs plain narrow cells of one style as a run, not a cell
  at a time. A rectangle scrolled on a terminal without DECSLRM (Konsole,
  many others), as a log beside its scrollbar is, scrolls as whole rows
  where that is estimated to write less, and the cells beside it that the
  shift left different are written again. `Surface.scrollRect` moves the
  damage inside the rectangle with its cells and marks only the rows the
  move brought in, so the presenter compares the cells beside it and the
  new rows, not the whole rectangle. On Konsole's lines an SGR reset precedes
  ICH and DCH (bytes only on those caps, which no scenario runs); kitty
  images are placed again after any scroll, ids reused.
- **The input parser** reads CSI parameters from the bytes without strings
  and lists, and leaves ESC and a split character to their completion; the
  terminal coalesces mouse motion within a read (30 motions in one read give
  one event), shared with `HeadlessTerminal`. `mouse-flood`'s per-event
  figures do not show it: the scenario sends one motion a read.
- **`stringWidth`** uses one shared segmenter, not one per call
  (`unicode/unicode.dart`).
- **`ValueKey`** hashes `Object.hash(ValueKey, value)`, with no `Type`
  built, and `==` tries `identical`, then `is`, then the value, then
  compares the type arguments in place (`identical(other._type, T) ||
  other._type == T`). About 12 ns AOT for equal int keys, 9.5 ns for keys
  of unrelated types, 19.5 ns for related types with equal values
  (`ValueKey<num>(1)` against `ValueKey<int>(1)`).
- **`Table`, `ListView` and `SelectionList`** rebuild the rows a selection
  move touches (a `SelectionList` item that looks as it did keeps its
  widget), a `ListView` rebuilt takes each item's element where it was,
  and the element walks and `RenderList._itemAt` make no closure and
  context per item visited. Table-100k allocates about 62 contexts a key,
  some 50 of the rest being the scenario's tester.
- **`TextArea`** repaints the rows whose text changed: a line break, a join
  or a rewrap moves the rows after it on the screen, as a scroll does (a
  key mid-text in an 8-row area paints 2 rows for a line break, a join and a
  word wrapped onto the next row, 1 for the undo of one); a scroll moves the
  rows still in view and paints those that came in. `onEdited` gets the
  controller's value, its text joined only when read, where `onChanged` gets
  the joined text each edit. A `TextField`'s `onChanged` costs no join of its
  own: the field joins its text once a change to draw it.
- **`MarkdownView(data)`** with `appended:` naming the piece added checks
  only its length and the text's end (0.13 us at 50 KB); without it the
  whole text is compared. `MarkdownStream` keeps settled blocks and the view
  reuses their widgets.
- **Idle** costs nothing: idle frames are 3 B and write no bytes;
  a still app runs no frame; `Ticker`s stop when idle; `Spinner` repaints,
  it does not rebuild.

## Costs that remain

Ordered by what removing them would give back.

- **A paragraph's edit through the bidi path** still allocates 1 817 B a
  frame in wrap-bidi, the most of the paragraph scenarios: of its 7 lists,
  3 are the `BidiText` an edit resolves again (`_resolveEdit`), 2 the
  scenario's own and 2 the pipeline's dirty lists; JIT boxes 7.5 integers
  of `Presenter._rowHash` besides.
- **A `LogView` at its cap** shifts every item's index with each line, and
  `RenderList.moveItem` marks each unpainted, so its window repaints every
  frame: log-append writes 273 B a line and allocates 27.2 KB, the most of
  the app scenarios a frame.
- **log-bar is about 4 us above log-line**: the rectangle's rows are copied
  one by one, a scan decides whether to widen, and the scrollbar's column is
  repainted and compared each frame.
- **Hardware-scroll moves**: `Surface.scrollRows` / `scrollRect` move the
  cells, styles and damage arrays with `setRange` (`surface.dart`): 44-45 %
  of log-line's and list-scroll's JIT samples, but AOT (micro-benchmark, 11
  800 cells) 0.7 us a move up, 2.5 us down. Low priority; a row-offset ring
  would remove the moves at a large cost in risk.
- **`_tryRowShift` on typing frames** (`presenter.dart`): 41 % of typing's
  samples (59 % with what it calls), of a 2.3 us frame. Its worst case (O(16 w) per row) did not show
  in any scenario: the cost loop stops once it can't beat rewriting the
  tail. A second must-match check at the head of the change would cut the
  common case.
- **`ListView` scrolling** allocates 6.9 KB a row scrolled (the item built
  and the one leaving dropped; nothing is O(items)). `RenderList._childAt`
  is a linear search from the nearer end for an item it has
  (`render/list.dart`, O(built^2) over a pass; one past its ends is found
  missing at once), 2 % of list-scroll's samples.
- **Rebuild bookkeeping**: `updateChildren` copies its set with `retainAll`
  even when there is nothing to retain (`framework.dart`). Visible in
  table-100k's allocations (`_Record`, closures), not in its time.
- **idle's time** moves with where AOT places the code, not with code the
  frame runs: 97 % of the frame is `Presenter.present`, and the time rises
  and falls between builds that change only the input parser and `unicode`,
  which an idle frame never runs. Nothing to remove.

## Already good - don't touch

- Idle frames, as above.
- Fills (`fill.dart`), the identical-cell skip in `_diffRow`, damage spans,
  the style tables and their caches, `_composeRuns`, the row hashes of
  `_detectScroll`, the reused output buffers.
- `dependOnInheritedWidgetOfExactType` is a map lookup, not a walk; dirty
  elements are sorted once per scope; `updateChildren` follows the
  head/keyed-middle/tail scheme.
- `ListView` and `Table.source` are truly lazy: 100k rows cost what the
  rows in view cost; the table's sort is cached by data identity.
- `TextBuffer` is a piece table; `TextArea` paints only the rows in view.

## Checked and set aside

- **GC pauses.** No scenario ran an old-space collection; the longest
  scavenge was 4.8 ms, most under 2 ms. Allocation volume costs time where
  it is allocated, which the costs above count.
- **Depth sort of the dirty lists** (`pipeline.dart` sorts by `depth`,
  which walks to the root): not in any scenario's samples.
- **Focus traversal**: per Tab press, not per frame.
- **A TextField's `onChanged` join**: about 7 us of the 530-600 us a key
  takes in a 10 010-character field (JIT), 5 joins for 5 keys, so it has no
  `onEdited`.

Each cost is measured with the scenario that shows it: `tool/bench.dart
--only=<name>` for time, `tool/alloc/bin/alloc.dart --only=<name>` for
allocations.
