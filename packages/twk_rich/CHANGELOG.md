# Changelog

## Unreleased

Fixed:

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
