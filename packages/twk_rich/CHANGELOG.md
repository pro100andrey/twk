# Changelog

## Unreleased

Fixed:

- GIF and APNG decoding: an animation's screen is at most 8 Mi pixels
  (`decodeGif`, `decodeApng` refuse more; a 16384 × 16384 screen took 1.4 GB
  and with restore-to-previous 5.5 GB), restoring to the previous canvas
  keeps only the frame's rectangle, not a second screen; an unknown block
  after frames ends a GIF as in browsers, instead of refusing it; a GIF
  frame past the screen is clipped to it; an LZW minimum code size above 8
  is refused, not decoded to wrong colours.
- `Image`: a file whose header says a width or a height of 0 is a
  `FormatException` shown in its place, not an `UnsupportedError` thrown by
  layout; the frames of a kitty animation a paint makes are counted
  (`RenderImage.framesPerPaint`, 4), the 4 ms of real time
  (`RenderImage.makeFor`) only a ceiling over that, so that a test counts
  them; `AnimatedImage.nextChangeAfter` announces the switch to a last frame
  of no delay, as `indexAt` makes it, so that a widget woken only by it does
  not stay on the frame before; `kittyImage` and `iterm2Image` say they take
  a GIF (kitty gets its first frame as PNG, iTerm2 the file, which it plays).

Added:

- `DiffView` is selected with the mouse below a `SelectionArea`
  (`selectable`, on by default): a drag across the rows, scrolling it past
  the edge, copies the lines' code as shown, the numbers and signs left
  out, side by side the two sides of a row joined by a tab; the selected
  part is drawn over the syntax colors. It is a `ListView` with `itemText`.
- Animated images: `decodeGif` (LZW, interlace, local palettes,
  transparency, disposal, delays and the NETSCAPE2.0 plays), `decodeApng`
  (frames composed by the dispose and blend operations; `decodePng` still
  reads the default image) and `decodeAnimation` for any file, giving an
  `AnimatedImage` of `ImageFrame`s; `decodeImage`, `imageSize` and
  `ImageFormat` read GIF. `Image` plays an animated GIF or APNG on the app's
  clock (a fake clock moves it in tests), in blocks and with every protocol
  by drawing and sending the current frame as it changes; it shows the first
  frame outside an app. Where the terminal plays kitty's animations
  (`TerminalCaps.kittyAnimation`, kitty itself) the frames are sent once and
  the terminal plays them: the first at once, the others made a frame or
  more at a time (4 ms of each of the app's frames) while it plays those it
  has, the app asking for no frames once all are sent. One that would take
  more than 64 MB in the terminal, decoded (its frames fitted to the box),
  is drawn frame by frame as on other terminals (kitty keeps 320 MB of
  images). On kitty's protocol without its animation (Konsole, Ghostty,
  WezTerm) the frames within that are kept on the terminal (`ImageKeep`):
  each is sent once, and placed again on the next plays; they go when the
  image leaves the tree or is drawn otherwise. Under a
  `TickerMode` that is off an animation stands on the frame it shows (a
  kitty one stopped by the terminal) and goes on from it when the mode is on
  again.
- An animation's memory is bounded: `AnimatedImage` composes a GIF's or
  APNG's frames as `bitmapAt` reaches them and keeps a window of the last
  (`windowBytes`, 32 MB, a parameter of `decodeGif`, `decodeApng` and
  `decodeAnimation`) instead of every frame up front (500 frames of 800 x 600
  were 1 GB before the first showed). Breaking: `AnimatedImage.frames` is
  gone for `frameCount`, `delays`, `bitmapAt(i)` and `frameAt`; a later
  frame whose data is invalid throws from `bitmapAt`, not from `decodeGif`
  (the first frame is still decoded at once). `Image` keeps what it drew of
  each frame drawn one by one (16 MB, the least recently shown dropped)
  instead of every frame for ever.
- `BlockMode.sextant`, `.octant`, `.braille` and `.ascii` beside `.half` and
  `.quadrant`, for `Image` and `BlockImage` where the terminal shows no
  images: 6, 8, 8 and 1 pixels a cell (`BlockMode.across` and `.down`). Sextants
  and octants pick the cell's best two colours as quadrants do, braille shows
  as dots in one colour the pixels brighter than the luma that parts the
  image's best in two (Otsu's method, transparent counted as black), so that
  a dark colour on a darker ground keeps its dots; ascii a ramp of
  characters. The
  glyphs are `Marker`'s (twk's charts), not tables of their own.
- `Image` draws in sextants by default where the terminal is known to draw
  them itself (`TerminalInfo.sextants`, twk_core's `sextantsFor`: kitty,
  foot, Ghostty, WezTerm, Konsole 22.04, VTE 0.78, Contour, Rio) and in half
  blocks where it is not; `Image.blockMode` is null by default for that
  (`BlockImage`'s own default stays `.half`), `defaultBlockMode` is the
  decision. `TWK_IMAGE_BLOCKS` (`half`, `quadrant`, `sextant`, `octant`,
  `braille`, `ascii`) names the mode for every image of the process, under an
  `Image`'s own `blockMode`.

Fixed:

- `Image.forceBlocks` turned on lets go of the frames kept on a kitty terminal
  and of the animation it plays, as another source, fit or cell size does.
- `decodeGif` keeps the frames before the cut only for a file cut short, as
  its documentation says: a later frame of invalid data throws, it was dropped.
- A `MarkdownView` table answers its height to a parent that asks for
  intrinsic sizes (the inline screen's root) in the frame it is built, not
  one build late: no overflow on the first frame or on each appended row.
- A `CodeView` narrower than its gutter paints (its code clip was of a
  negative width, which fails `Canvas.clipRect`'s assert in debug).
- The inline chat example shows the newest lines of an answer's block that
  is taller than the room above the prompt, the start of it cut off, not
  the end of it cut off at the prompt (a `SingleChildScrollView` that sticks
  to its end).
- `changedWords`, and with it `DiffView`'s highlighting of the words a
  line changed, gives none for lines of more than 20000 words between
  them, which a diff of their words took up to a minute on in a frame
  (two random lines of 3.7 million characters); the line shows changed
  whole.
- `MarkdownView` given a `theme` draws its list markers in the glyphs of
  the app as they change, not in those it was first built in.
- `markdownLines`: a list's markers, a quote's bar and a table's columns
  give way where they would leave too few columns for a wide character, so
  no line is wider than `width` (`- 你好` at 3 columns was 4 wide).
- A paragraph of many lines is made into spans in time linear in them, not
  quadratic: 8000 lines took 0.5 s, now 25 ms.
- A `MarkdownView` with a `MarkdownController` finds its headings again
  only where they may have changed, each heading's text and slug kept by
  its node: a document of 2000 blocks streaming in spent 0.45 ms an append
  on them, now none to measure.
- A link destination nests 32 parentheses at most, as cmark takes it: one
  of more is no link, and text of `[a](` repeated is parsed in linear time
  (32000 of them took 2.5 s, now 32 ms).
- `MarkdownView` draws a table's rows itself, each made once and kept by
  its row, as a `Table` drew them: a table streaming in a row at a time
  lays out the row added alone (an append to 2000 rows took 23 ms, now
  1 ms; to 10 rows 0.5 ms, now 0.3), and no longer asks the terminal for
  the mouse's drags.
- `DiffView` asserts, in a debug run, that each hunk's `oldCount` and
  `newCount` are the lines it has, naming the hunk: the line numbers after
  a hunk built by hand with the wrong counts drifted without a word. A
  hunk `Diff.parse` reads from a patch cut short (or a header that counts
  too many) has the counts of the lines it got.

## 0.3.0

Breaking:

- `BoxConstraints`, `Flex`, `Row`, `Column` and `Wrap`:
  [twk_core's changelog](../twk_core/CHANGELOG.md).

Changed:

- Inlines of Markdown nest 64 deep at most; past that their delimiters stay text.
- A `MarkdownView` and its links follow `ThemeData.pointerMode`: `PointerMode.auto`
  asks for the mouse's motion in a local session and for none in a remote one,
  `PointerMode.off` shows no hand.

Fixed:

- A highlighted escape takes the whole character after its backslash.
- A `JsonView` filter marks the whole grapheme cluster it matched.

## 0.2.0

- Takes twk and twk_core at 0.2.0, which have breaking
  changes; nothing of this package changed.

## 0.1.0

The first release.

- Markdown: `parseMarkdown`, CommonMark 0.31.2 and GFM's tables, task
  list items, strikethrough and autolinks, held to their specs'
  examples; `MarkdownStream`, a document that arrives in pieces, its
  settled blocks kept as they were and only what follows them parsed
  again; `MarkdownView`, a document as widgets, its links hyperlinks and
  its code blocks highlighted; `markdownLines(segmenter, text, width, theme: theme)`, the
  same document as lines of styled spans (`List<List<Span>>`) wrapped to
  a width, for an app that draws it in a panel of its own.
- Syntax highlighting: lexers of the package's own, a line at a time,
  for Dart, JSON, YAML, shell, JavaScript and TypeScript, Python, Rust,
  Go and diffs (`languageNamed`, `highlight`, `SyntaxTheme`); `CodeView`
  and its controller, source shown with line numbers, signs and matches.
- Diffs: `diffLists` (Myers' algorithm in linear space), `Diff.parse` of
  a unified diff, `Diff.between` two texts, `changedWords`, and
  `DiffView`, unified or side by side, the words a line changed marked.
- `JsonView`: JSON or a Dart value as a tree that folds, filtered by its
  keys, its paths and values copied; `jsonLines` for a program's output.
- `BigText`: letters several cells tall in fonts of the package's own.
- QR codes: `QrSymbol.encode` and `QrSymbol.bytes` from the standard,
  drawn in half blocks by `QrCode`.
- `package:twk_rich/image.dart`, a library of its own: PNG and JPEG
  decoded, scaled to cells and encoded for kitty, iTerm2 and sixel, or
  drawn in block characters, and the `Image` widget.
