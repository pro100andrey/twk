# Changelog

## Unreleased

Breaking:

- `Flex`, `Row`, `Column` and `Wrap` take `spacing` and `runSpacing`, and
  `RenderFlex` and `RenderWrap` have them, as Flutter names them: they were
  `gap` and `runGap`.

- Inlines of Markdown nest 64 deep at most, past which their
  delimiters stay text, where nesting some thousands deep overflowed the stack.
- A highlighted escape takes the whole character after its backslash, where one
  beyond U+FFFF was split between two tokens, in every language.
- A `JsonView` filter marks the whole grapheme cluster it matched, where a key
  with a character beyond U+FFFF or a combining mark lost it.

- A `MarkdownView` asks for the mouse's motion by `PointerMode.auto` in a local
  session, as every hand does now, and for none in a remote one.

- A link in a `MarkdownView` shows the hand by `ThemeData.pointerMode`, as a
  `Text`'s link does: `PointerMode.auto` asks the terminal for no motion, where
  a view with a link always did, and `PointerMode.off` shows none.

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
