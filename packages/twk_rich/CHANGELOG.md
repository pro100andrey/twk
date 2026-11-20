# Changelog

## Unreleased

Added:

- Animated images: `decodeGif`, `decodeApng` and `decodeAnimation` for any
  file give an `AnimatedImage` of `ImageFrame`s (GIF: interlace, local
  palettes, transparency, disposal, delays and the NETSCAPE2.0 plays; APNG:
  frames composed by the dispose and blend operations; `decodePng` still
  reads the default image). `decodeImage`, `imageSize` and `ImageFormat` read
  GIF. `Image` plays an animated GIF or APNG on the app's clock (a fake clock
  moves it in tests), in blocks and with every protocol, and shows the first
  frame outside an app; under a `TickerMode` that is off it stands on the
  frame it shows. `kittyImage` and `iterm2Image` take a GIF too.
- Where the terminal plays kitty's animations (`TerminalCaps.kittyAnimation`,
  kitty itself) the frames are sent once and the terminal plays them; an
  animation that would take more than 64 MB in the terminal is drawn frame by
  frame as on other terminals. On kitty's protocol without its animation
  (Konsole, Ghostty, WezTerm) the frames are kept on the terminal
  (`ImageKeep`), each sent once and placed again on the next plays.
- An animation's memory is bounded: `AnimatedImage` composes frames as
  `bitmapAt(i)` reaches them and keeps a window of the last (`windowBytes`,
  32 MB, a parameter of `decodeGif`, `decodeApng` and `decodeAnimation`), with
  `frameCount`, `delays` and `frameAt` beside it; a later frame of invalid
  data throws from `bitmapAt`, not from the decoder. An animation's screen is
  at most 8 Mi pixels (`decodeGif` and `decodeApng` refuse more), an unknown
  block after frames ends a GIF as in browsers, a frame past the screen is
  clipped and an LZW minimum code size above 8 is refused. `Image` keeps what
  it drew of each frame drawn one by one (16 MB, the least recently shown
  dropped).
- `Image`: a file whose header says a width or a height of 0 is a
  `FormatException` shown in its place, not an `UnsupportedError` thrown by
  layout.
- `BlockMode.sextant`, `.octant`, `.braille` and `.ascii` beside `.half` and
  `.quadrant`, for `Image` and `BlockImage` where the terminal shows no
  images: 6, 8, 8 and 1 pixels a cell (`BlockMode.across` and `.down`).
  Sextants and octants pick the cell's best two colours as quadrants do,
  braille shows as dots in one colour the pixels brighter than the luma that
  parts the image's best in two, ascii a ramp of characters.
- `Image` draws in sextants by default where the terminal is known to draw
  them itself (`TerminalInfo.sextants`: kitty, foot, Ghostty, WezTerm, Konsole
  22.04, VTE 0.78, Contour, Rio) and in half blocks where it is not;
  `Image.blockMode` is null by default for that (`BlockImage`'s own default
  stays `.half`). `TWK_IMAGE_BLOCKS` (`half`, `quadrant`, `sextant`, `octant`,
  `braille`, `ascii`) names the mode for every image of the process, under an
  `Image`'s own `blockMode`.
- `DiffView` is selected with the mouse below a `SelectionArea`
  (`selectable`, on by default): a drag across the rows, scrolling it past
  the edge, copies the lines' code as shown, the numbers and signs left out,
  side by side the two sides of a row joined by a tab. It is a `ListView`
  with `itemText`.

Changed:

- `MarkdownView` draws a table's rows itself, each made once and kept by its
  row: a table streaming in a row at a time lays out only the row added, and
  it no longer asks the terminal for the mouse's drags.
- `MarkdownView` with a `MarkdownController` finds its headings again only
  where they may have changed, and a paragraph of many lines is made into
  spans in linear time: long streamed documents cost much less per append.
- `DiffView` asserts, in a debug run, that each hunk's `oldCount` and
  `newCount` are the lines it has, naming the hunk. A hunk `Diff.parse` reads
  from a patch cut short (or a header that counts too many) has the counts of
  the lines it got.

Fixed:

- `MarkdownView` given a `theme` draws its list markers in the glyphs of the
  app as they change, not in those it was first built in.
- `markdownLines`: a list's markers, a quote's bar and a table's columns give
  way where they would leave too few columns for a wide character, so no line
  is wider than `width` (`- 你好` at 3 columns was 4 wide).
- A link destination nests 32 parentheses at most, as cmark takes it: one of
  more is no link, and text of `[a](` repeated is parsed in linear time.
- `changedWords`, and with it `DiffView`'s highlighting of the words a line
  changed, gives none for lines of more than 20000 words between them, which
  took up to a minute in a frame; the line shows changed whole.
- A `CodeView` narrower than its gutter paints (its code clip was of a
  negative width, which failed an assert in debug).

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
