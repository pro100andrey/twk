# Changelog

## 0.1.0

The first release.

- Markdown: `parseMarkdown`, CommonMark 0.31.2 and GFM's tables, task
  list items, strikethrough and autolinks, held to their specs'
  examples; `MarkdownStream`, a document that arrives in pieces, its
  settled blocks kept as they were and only what follows them parsed
  again; `MarkdownView`, a document as widgets, its links hyperlinks and
  its code blocks highlighted.
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
