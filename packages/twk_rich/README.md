# twk_rich — rich text for twk widgets

Rich text for widgets of [twk](../twk/README.md): Markdown, syntax
highlighting, diffs, big text, QR codes and JSON as a tree
that folds, in a package of its own so that apps which show none of it
do not carry it; and, in `package:twk_rich/image.dart`, a library of its
own that `lib/twk_rich.dart` does not export, PNG and JPEG images
decoded, scaled to cells and encoded for kitty, iTerm2 and sixel, or
drawn in block characters, and the `Image` widget
([below](#images-packagetwk_richimagedart)). It takes twk and [twk_core](../twk_core/README.md), the
rendering core in packages/twk_core of this repository, as path
dependencies, and [twk_test](../twk_test/README.md), whose tester (`testTwk`) runs the
tests of the views and whose emulator the big text tests write their
frames to, as a path dev dependency.

`lib/twk_rich.dart` exports one library per topic,
`lib/src/<topic>/<topic>.dart`, each with a doc comment naming what it is
for; a topic's tests are in `test/<topic>/`.

| topic       | provides |
|-------------|----------|
| `markdown`  | `parseMarkdown(text)`, the blocks of a document, and `MarkdownStream`, a document that arrives in pieces (`add`). A block is settled once a complete line closes it: whatever is added later, `blocks` holds it as the very object it was (`settled` counts those blocks). `add` parses again only the lines from the first block not settled, and of those blocks keeps each part equal to what it was, such as the finished items of a growing list. Text added in any pieces parses as it would whole; `close()` says that no more comes: the last line is complete without its line ending, every block settled, `add` after it a `StateError`. The tree is plain values, equal when their content is: blocks (`MdBlock`) `MdParagraph`, `MdHeading`, `MdCodeBlock` (fenced with an info string and its `language`, or indented), `MdThematicBreak`, `MdBlockQuote`, `MdList` (`MdListItem`s, bullet or ordered from a `start`, tight or loose; a task item `checked` or not) and `MdTable` (an `MdAlign` per column); inlines (`MdInline`) `MdText`, `MdCode`, `MdEmphasis`, `MdStrong`, `MdStrikethrough`, `MdLink`, `MdImage`, `MdReference`, `MdSoftBreak` and `MdHardBreak`. Link reference definitions are left out of the blocks and collected in `MarkdownStream.definitions`: `MdDefinition`s by the `normalizeLabel` of their label (case-folded, blanks collapsed), the first of a label kept; one in a block not settled may still change. Since a definition may come after the links that use it, a reference link or image (`[text][label]`, `[label][]`, `[label]`: `MdReferenceKind.full`, `collapsed`, `shortcut`) is an `MdReference` holding its label and parsed text, and the blocks do not depend on the definitions: `resolveReferences(blocks, definitions)` (`resolveInlines` for inlines) makes each a link or image where a definition matches its label and its literal text where none does, as is a link reference inside a link; a block without one comes back as itself. `MarkdownView(data, appended:, theme:, codeWrap: TextWrap.grapheme, tabWidth: 4, onLinkTap:, hyperlinks: true, controller:)` shows a document as widgets, its blocks one under another a blank row apart: a paragraph or a heading is a `Text.rich` that wraps by words (CJK text between its characters), emphasis, strong and struck text, code spans, links and images in their styles over the text's, a link, and an image (its description, else its source), a hyperlink (OSC 8) to its destination, under which the pointer is a hand (`PointerShape.pointer`, in a table too) where the terminal shows the pointer's shape, which only then, and while the view has a link, has the terminal report the mouse's motion, a reference a link once a definition of its label has arrived, before it or after, and its text until then, a line ending within a paragraph a space; a list item has its marker before its blocks, which wrap under their own first column (bullets `•`, `◦`, `▪` by depth, numbers aligned at their right, `☐` or `☑` for a task item), with a blank row between the items and blocks of a loose list; a block quote has a bar down its left side, its blocks in the quote style; a block of code is a `CodeView` (below) in the language the first word of its info string names, on the code block fill, a cell in from either side, its lines broken as `codeWrap` says; a table is a twk `Table` showing all its rows, aligned as its delimiter row says, with lines between the columns and under the header, the mouse going through it, so that the wheel over it scrolls what is around the view; a thematic break is a line across. With `onLinkTap(destination, title)`, a click (a press and a release of the left button on the same cell) on a link or an image goes to the app with its destination (an image's source) and title, a reference link's from its definition, the innermost of an image in a link, instead of to the terminal (a chat's own links, a help viewer's); links take no focus. The hyperlink (OSC 8) is still written unless `hyperlinks: false`, without which the hand pointer and the clicks still find the links of paragraphs and headings, those of tables only with it. The bullets, numbers, boxes and bars are not text: a `SelectionArea` the app puts around one view or many selects and copies the text of the blocks alone. New `data` that is the old with text added at its end is parsed again only where that text may change it (`MarkdownStream.add`); to see that it is, the view compares the old `data` with the start of the new, the whole of it, unless `appended:` gives the piece just added (as a chat knows it), when it checks only the length and that `data` ends with the piece, so a piece costs its own length, not the answer's; and a block it leaves as it was keeps its widgets, not built again unless a definition one of its references uses changed, as does an item a growing list keeps; other new `data` is parsed whole. A `MarkdownController` given as `controller:` lists the view's headings (`headings`, each a `MarkdownHeading`: `text`, `level` and its GitHub `slug`, lower case, punctuation dropped, blanks made `-`, a repeated one `-1`, `-2`; `markdownHeadings(blocks)` finds them in quotes and list items too), its listeners told after a build that changed them, also as text streams in, and `scrollToHeading('install')` (or `'#install'`) scrolls the `Scrollable`s around the view the least that shows that heading, returning whether there is one, so an app can follow a `#install` link from `onLinkTap`. `MarkdownView.blocks(blocks, definitions:, theme:, codeWrap:, tabWidth:, onLinkTap:, hyperlinks:, controller:)` shows blocks parsed already, their references resolved by `definitions`, with the same widgets, a block given again, the very same object, keeping them. The view takes the width it is given, which must be bounded, and is as tall as its blocks (in a `SingleChildScrollView` to scroll). An app in the inline mode puts each block of an answer that streams in into the terminal's history as it settles, so that an answer taller than the terminal is all there and the region holds only what still changes: `MarkdownStream.takeSettled()` gives the blocks settled since the last call, in order, each with its references resolved by the definitions of the blocks settled by then (one defined later, or in a block not settled, is its text there: holding a block back for it would hold back every block after it), and `live` the blocks it has not given. On each piece the app adds it (`close()` at the end) and adds what `takeSettled()` gives to the items of a twk `Static`, which builds each into `MarkdownView.blocks([block])` with a blank row above it (`Padding(padding: EdgeInsets.only(top: 1))`, as the blocks of a view are apart), above a `MarkdownView.blocks(answer.live, definitions: answer.definitions)` and the prompt: the `Static` writes the block to the history and fits the region to what is left in the same frame, the rows the block took given back (the doc comment of `MarkdownStream` has the code). The history takes whole blocks, so a list or a block of code is live until it ends, the region showing as much of it as fits; in the fullscreen mode the same app shows the answer in place. `MarkdownTheme`, a style per part, unset ones looking as the text around (`heading1` to `heading6`, `heading(level)`, `emphasis`, `strong`, `strikethrough`, `code`, `link`, `image`, `codeBlock`, `quote`, `quoteBar`, `marker`, `rule`, `tableHeader`, `tableBorder`; `copyWith`); `MarkdownTheme.from(ThemeData)`, a view's without one, in the colors of the `Theme`: headings bold, the first two `primary` (the first underlined), the third `accent`, the last `muted`; emphasis italic, strong text bold, struck text struck through; code `accent` on `surface`, code blocks on `surface`; links `primary` underlined, images `info` italic; quotes `muted`, their bar, rules and the lines of tables `border`; bullets and numbers `muted`; table headers bold |
| `highlight` | Source code split into tokens by lexers of this package's own, a line at a time. A `Language` (`name`, `aliases`, `lexer`) is found by `languageNamed(name)` (among `languages`, or those given) by its name or an alias in any case, as the info string of a Markdown fence names it, and a name none goes by gives `Language.plain`, each line one plain token: `dart`; `json` (`jsonc`); `yaml` (`yml`); `bash` (`sh`, `shell`, `zsh`); `javascript` (`js`, `jsx`, `mjs`, `cjs`) and `typescript` (`ts`, `tsx`, `mts`, `cts`); `python` (`py`, `py3`, `python3`); `rust` (`rs`); `go` (`golang`); `diff` (`patch`). A `Token` is text of a `TokenKind`: `plain`, `keyword`, `type`, `function`, `variable`, `constant`, `string`, `escape`, `number`, `comment`, `annotation`, `key`, `punctuation`, `operator`, and a diff's `inserted`, `deleted` and `heading` lines. A `Lexer`'s `lexLine` lexes a line held by a `TokenScanner` (which makes tokens of one kind that follow each other one token, and leaves what the lexer does not reach plain) from the state the line before ended in, and returns the state the line ends in: null at the start of the source, or a value, such as a `LexFrame`, a stack of the modes that nest (code in a string in code); equal states must lex the next line alike. What goes on across lines: block comments (nested in Dart and Rust); Dart's and Python's strings three quotes long and the code in them; JavaScript's and TypeScript's template literals and the code in them; Python's and JavaScript's strings whose line ends in a backslash; Rust's strings and raw strings; Go's raw strings; YAML's block scalars, quoted scalars and flow collections; Bash's strings, command substitutions, arithmetic and heredocs; a diff's hunks, whose headers count their lines, so in a hunk a line that starts with `---` or `+++` is a removed or an added one. Rules a reader may trip on: a JavaScript `/` starts a regular expression where a value goes (at the start of its line, after an operator, a keyword or punctuation other than a closing bracket) when another `/` closes it on the line, and divides elsewhere; JSX is not told apart, its tags lex as code; a Go name that starts with a capital is exported, not a type, so plain where nothing else tells what it is; Python's `match`, `case` and `type` are keywords only where they start a statement; Rust's lifetimes and labels are types and its macros functions; the command of each Bash command line is a function. `Highlighter(language, text)` keeps source lexed through edits: `replaceLines(start, end, lines)`, and `update(text)`, which replaces the lines between those that stayed the same, lex the lines put in, then those after them only until one starts in the state it started in before, and return how many lines they lexed; the lines not lexed keep their token lists as the very objects they were. `SyntaxTheme`, a `Style` per kind (`styleOf`, `spans`, `copyWith`), unset ones taking the style of the text around; `SyntaxTheme.from(ThemeData)` in the colors of the app's theme: keywords `accent`; functions and keys `primary`; types, escapes and operators `info`; strings and inserted lines `success`; numbers, constants and annotations `warning`; variables and deleted lines `error`; comments `muted` and italic; a diff's headings `info` and bold. `SyntaxTheme.of(context)` is that of the nearest `SyntaxThemeScope`, else `from` the `Theme` there. `CodeView(code, language:, lineNumbers:, firstLineNumber: 1, tabWidth: 4, wrap: TextWrap.none, signs:, controller:, focusNode:, autofocus: false, highlightStyle:, matchStyle:, currentMatchStyle:)`: a line of rich text per line in the styles of `SyntaxTheme.of`, with `lineNumbers` each line's number before it, right-aligned in the theme's `muted`, a blank between; a line break at the end of the code ends its last line, a tab moves to the next multiple of `tabWidth` columns, and a line wider than the view is cut off unless `wrap` says otherwise. `signs` are an app's own marks in the gutter (diagnostics, breakpoints, a change since the last commit): a `CodeSign(glyph, style:)` by the number of the line it is beside, as the gutter numbers them, in a column before the numbers (before the code without them), a blank after it, as wide as the widest sign as the canvas draws it, each sign at its left on the first row of its line in its `style` over the text's; a line without one has blanks there, and the column is there for an empty map too, so that the code does not move as signs come and go (none for null). Below a `SelectionArea` its code is selected and copied as a Text's is (the view is one `Selectable`), its lines joined by line breaks and its tabs as tabs; the signs and the numbers are left out. With a `controller:`, a `focusNode:` or `autofocus:` it scrolls its lines itself, a `ListView` that builds those in view, taking all the room it is given, which must be bounded: focused, the arrows, Page Up, Page Down, Home and End scroll it, hinted for a `KeyHintsBar`, and Left and Right scroll lines not wrapped across, `CodeView.sideStep` (4) columns at a time, as far as the widest; without any of them it is as tall as its lines. A `CodeViewController(query:)`, given to one view at a time, names lines by their numbers in the gutter: `scrollToLine(n, alignment:)` scrolls the least that shows line n, or puts it `alignment` down the window (0 the top, 0.5 the middle, 1 the bottom), also when asked before the view is laid out; `linesInView` gives `(first:, last:)`; `highlightLines(lines, style:)`, `highlightRange(first, last, style:)`, `unhighlightLines` and `clearHighlights` mark lines (an error, where a debugger stopped) across the view in their style or the view's `highlightStyle`, by default a tint of the theme's `primary`, `highlights` holding them; `query` finds text, ignoring the case while it is all in lower case, `matches` (`CodeMatch(line, start, end)`) drawn in `matchStyle` (reverse video), the current one (`currentMatch`, `currentMatchIndex`) in `currentMatchStyle` (`accent` in reverse video and bold); `nextMatch()` and `previousMatch()`, and `n` and `N` while there is a query, go round them, from the window without a current one, scrolling to show it, across too. It notifies its listeners of each change and of each scroll. New code lexes only the lines it changed (`update`), and a line whose tokens and sign are kept keeps its widget; a new language lexes it whole. A language is added as a file `lang/<name>.dart` with its lexer and `const <name>Language`, imported, exported and listed in `languages.dart` (the `Lexer` doc) |
| `bigtext`   | `BigText`, text in letters several cells tall (splash screens, clocks, the numbers of a dashboard), and its `RenderBigText`: each line set in `font`, or in the first of `fonts` (by default `BigFont.sizes`: `large`, `block`, `small`) it fits in, the last when it fits in none; as wide as its widest line and as tall as its lines, a blank row apart, each placed as `align` (`TextAlign`; `start` as `left`, `end` as `right`) says, in `style` merged onto the `DefaultTextStyle` above (the letters in its `fg`, over its `bg` where it sets one). The fonts (`BigFont.values`), drawn for this package: `large`, 5×8 pixels as full blocks two cells wide, 8 rows to a line; `block`, the same pixels as half blocks, 4 rows; both with both cases of the Latin and Cyrillic (Russian and Ukrainian) letters, digits, the ASCII punctuation and the degree sign; `thin`, light box drawing, 3 rows, and `small`, 3×5 pixels as half blocks, 3 rows, both with capitals of the Latin and Cyrillic letters, digits and the common punctuation. A character a font has no glyph for is drawn as one that stands for it (a letter as its other case, an accented one without its accent, a Cyrillic one as the Latin letter it looks like), or else as `missing` says: `MissingGlyph.box`, the font's box, or `plain`, itself on the middle row. Where the canvas draws blocks and box drawing two columns wide (East Asian ambiguous), the pixel fonts draw braille of the same pixels and `thin` ASCII, as big as before |
| `diff`      | `diffLists(a, b, maxCost:)`, the `DiffChange`s that make list `a` into `b`, in order, apart by items both keep (items equal by `==` and `hashCode`): each the items from `oldStart` up to `oldEnd` replaced by those from `newStart` up to `newEnd`. They are those of a shortest edit script, the fewest items removed and added, by Myers' algorithm in linear space, O((N+M)·D) time and O(N+M) memory, once the head and the tail the lists share and the items only one of them has are set aside; the search for where the edits divide gives up after `maxCost` edits (by default the larger of 256 and the square root of N+M) and divides them where it got furthest, as GNU diff and git do: past that bound the changes still make `a` into `b`, the items kept equal and in order, but may remove and add more than the fewest, each such division costing O((N+M)·`maxCost`). A `Diff` is `FileDiff`s (`oldPath` and `newPath`, null for none, `path`, the new one or the old one of a file deleted; `headers`; `hunks`; `oldLines` and `newLines` where the whole texts are known) of `DiffHunk`s (`oldStart`, `oldCount`, `newStart`, `newCount`, the `section` its header names, `lines`) of `DiffLine`s (`kind`, a `DiffLineKind`: `context`, `removed` or `added`; `text`; `oldNumber` and `newNumber`, from 1, on the sides that have it). `Diff.parse(text)` reads a unified diff of any number of files, as `diff -u` and `git diff` write it: a file's part starts at a `diff ` line, or at a `--- ` line that a `+++ ` line follows out of a hunk unless it is the first of a part a `diff --git` line started; its paths are those of its `--- ` and `+++ ` lines (`/dev/null` none), without the time after a tab and the quotes, or else of its `rename from` and `rename to` lines or its `diff --git` line, the `a/` and `b/` that start them taken off where both have theirs; a hunk takes as many lines of each side as its header counts, so a `--- ` line in it is a line removed, an empty line in it is an empty line of context and a `\` line (no line break at the end of the file) is left out; the lines of a part before its first hunk are its `headers`, other lines out of hunks are left out. It reads the text as it is, an escape sequence part of the line it is in, as in a diff of a file that holds them: the output of `git diff --color` goes through `stripAnsi` first, `Diff.parse(stripAnsi(output))`. `Diff.between(before, after, context: 3, path:)` finds the changes between two texts (lines split at `\n` and `\r\n`, a line break at the end ending the last line), each run of them a hunk with `context` lines before and after, runs at most 2 × `context` lines apart one hunk. `changedWords(before, after)`, the ranges of code units of each of two lines that the fewest words removed and added change, a word a run of letters, digits and `_` (every character outside ASCII a letter), a run of blanks, or any other character alone; null where the characters other than blanks both keep are fewer than 40 % of those they have. `DiffView(diff, layout:, language:, tabWidth: 4, theme:, controller:, focusNode:, autofocus:)` shows a diff in the rows of a `ListView`, which builds those in view (of a diff of fifty thousand lines, a window's worth) and scrolls as a list does: `DiffLayout.unified`, each line after a gutter of its old and its new number and its sign (`-` removed, `+` added), or `sideBySide`, the old side left of a `│` and the new side right of it, each line after its number and sign. In a run of lines removed and added the first removed pairs with the first added, the second with the second, and so on: side by side a pair shares a row, the other side blank where a line has none; the words a pair changed are marked over the syntax colors. A file with a path starts with a row that names it (`old → new` where it was renamed), and the unchanged lines a diff leaves out before a hunk, between hunks and, where the whole file is known, after the last are a row `⋯ N unchanged lines` with the section of the hunk after it. Each side is highlighted (`highlight`) as one source, lexed from its first line down as far as the rows shown need: the whole file for `Diff.between`, its lines in the hunks for `Diff.parse`; in `language`, by default the one the extension of the file's path names (`languageNamed`), in the `SyntaxTheme` there. A tab moves to the next multiple of `tabWidth` columns; a line wider than its column is cut off. It takes all the room it is given, which must be bounded. `DiffTheme`, the styles of the parts (`added`, `removed`, `addedWords`, `removedWords`, `addedSign`, `removedSign`, `lineNumbers`, `collapsed`, `file`, `divider`), unset ones leaving the style under them; `DiffTheme.from(ThemeData)`, a view's without one, in the colors of the `Theme`: added and removed rows on a tint of `success` and of `error` (their text color at alpha 0x30), the words changed on a stronger one (0x70), the signs in those colors, numbers `muted`, the rows of lines left out `muted` on `surface`, those of files bold `info` on `surface`, the divider `border` |
| `json_view` | `JsonView(value:, controller:, rootName: r'$', onPathCopied:, theme:, sortKeys: false, maxStringLength: 200, focusNode:, autofocus: false)` shows a JSON document or a Dart value as a tree that folds, in a `TreeView`'s rows: each object and array a row that folds (`▾ {`, `├─▸ "dependencies": { 4 keys },`, `[ 2 items ]` collapsed), its entries below it, indented and joined to it by guides, and a row that closes it; keys, strings, numbers, `true`, `false`, `null` and brackets each in its style of `theme` (a `SyntaxTheme`; the `SyntaxThemeScope`'s when null). `value` is a `Map`, a `List` (a `Set` shows as one), a `String`, a `num`, a `bool` or null; any other object shows as what its `toJson()` gives, or else as its `toString()` in a string, and a value inside itself as `<cycle>`. `JsonView.parse(source, …)` shows JSON text, or the `FormatException` it fails with and the place in it. `sortKeys` orders an object's keys, which are otherwise in the map's order; a string longer than `maxStringLength` characters is cut with `…` until Enter shows it whole. The keys are a `TreeView`'s (Up, Down, Left, Right, Page Up, Page Down, Home, End; `*` expands the value selected and everything below it) and, hinted while it has the focus: Enter and Space fold the object or array selected, or show a string cut whole and cut it again; `c` copies the path of the value selected (`jsonPath`, from `rootName`: `$.scripts[0]`) to the clipboard and calls `onPathCopied` with it, `y` copies the value as JSON, indented (OSC 52, as a `TextField` copies); `/` opens a field at the bottom whose text filters the keys as a `CommandPalette` does (`fuzzyMatch`): the entries whose keys match show, with what is below them and the objects above them expanded, the characters found standing out and the best match selected; Enter goes back to the tree, the filter kept, and Escape clears it and puts back what was expanded. A `JsonViewController(expandedDepth: 1)` holds what is expanded and selected, by path, kept as the value changes around it: `selectedPath`, `selectedValue` (as it was given), `isExpanded(path)`, `expandAll()` (waiting for a view without one), `collapseAll()` and `reveal(path)`, which expands what is above a value, selects it and scrolls to it; the view makes one of its own, which expands the top value only, when none is given. It takes all the room it is given, which must be bounded. `jsonPath(segments, root: r'$')` names the path of a value from its keys and indexes (`$.name`, `$["a key"]`, `$.scripts[0]`; `[0]` an index and `["0"]` a key), and `jsonLines(value, theme:, expandedDepth:, sortKeys: false, maxStringLength:)` gives the lines a view shows `value` in, every object and array expanded or those less than `expandedDepth` levels below the top, indented two blanks a level, each a list of `Span`s in the theme's styles (the terminal's own colors without one): for a program's output, as twk_cli's `cli.inspect` writes it |
| `qr`        | `QrSymbol.encode(text, level: QrErrorCorrection.medium, version:, mask:)`, text as a QR code (ISO/IEC 18004, Model 2), written from the standard: in the mode of fewest bits that holds all of it (`QrMode.numeric` for digits, `alphanumeric` for digits, capitals and ` $%*+-./:`, `byte` for its UTF-8 otherwise, with no ECI, as phones read it; `QrSymbol.bytes(bytes, level:, version:, mask:)` for bytes, each from 0 to 255), at one of the four levels of error correction (`low`, `medium`, `quartile`, `high`, restoring about 7, 15, 25 and 30 % of the codewords), in the smallest of the 40 versions it fits in, or in `version`, data that does not fit an `ArgumentError`. After the data the terminator and the pad codewords; the codewords split into the blocks of the version and level (Table 9), each with its Reed-Solomon codewords over GF(2⁸), interleaved, and placed up and down columns two wide around the function patterns: the finder patterns and their separators, the timing and alignment patterns (Annex E), the dark module, and the format information and, from version 7, the version information, each twice with its BCH code. The data is laid under the one of the eight masks the standard's four penalty rules score lowest, the first of those that tie, or under `mask`: runs of five or more modules of a color in a row or a column, blocks of 2 × 2 of a color, dark, light, three dark, light, dark with four light modules before or after it (those outside the symbol light, as the quiet zone is), and every 5 % the dark modules are off half. A symbol has its `version`, `size` (4 × version + 17 modules a side), `level`, `mode`, `mask` and `isDark(x, y)`. `QrCode(data, level:, quietZone: 4, dark:, light:)`, and `QrCode.symbol(symbol, quietZone: 4, dark:, light:)`, a symbol made already, draws one with `quietZone` light modules around it in half blocks, two modules to a cell one above the other, so that a module is about square: `dark` on `light`, black on white in 24-bit color by default whatever the theme, since a scanner looks for dark modules on a light ground; n columns and (n + 1) / 2 rows for a side of n modules with the quiet zone, or, where the canvas draws half blocks two columns wide, each module two blanks in its color, n rows of 2n columns. Within smaller constraints it is cut off, and data too long is an error in its place (`RenderQrCode`) |

`test/markdown/spec_test.dart` parses the 652 examples of the CommonMark
Spec 0.31.2 and the 23 of GFM 0.29's tables, task list items,
strikethrough and autolinks, resolves their references, and compares
them, written as HTML (`test/markdown/html.dart`), with the spec's. Every
GFM example passes, and 571 CommonMark ones; the 81 left out are listed
by why, and a test checks that each still fails: raw HTML is text (72);
a reference is parsed before its label is known to be defined, which
CommonMark's result depends on for a reference within link text (1),
brackets leaving emphasis in them unmatched (1) and a full reference
with an undefined label before another (2); character references by
names HTML 4 does not have are text (1); GFM's extended autolinks make
links of URLs and email addresses in the text (4).
`test/markdown/stream_test.dart` adds every example, and a document with
a block of every kind and a reference defined after it, split at every
point and a character at a time, and checks the blocks and the
definitions against the whole parse; and the blocks taken for the
history, each once and in order, in any pieces the blocks of the
document, their references links where a definition settled before
(in the same piece too) and their text where none has, one not settled
not used, and `close` settling every block and the last line, `add`
after it an error. `test/markdown/parse_test.dart`
checks the tree beyond what the HTML shows: the values of each kind of
block and inline, definitions, reference links and resolving them.
`test/markdown/view_test.dart` runs `MarkdownView` through twk_test's
`testTwk`: each kind of block and inline in its style, links' OSC 8
targets and a reference defined after it, code highlighted and wrapped
or cut off, tables (alignment, links, the wheel scrolling past them,
their text selected), the `Theme`'s styles and a new theme, the text
selected and copied without the bullets, CJK and wide text wrapped, a
bullet the terminal draws two columns wide; and a document streamed in
pieces of 17 characters, every element of a block settled before a
piece keeping its widget and all of them updated less than a tenth as
often as a rebuild of every block would, a growing list keeping its
items' elements, a definition arriving late, numbers growing wider and
a code block growing; and `MarkdownView.blocks`, shown as the view of
their document shows them, resolved by the definitions given, a block
kept keeping its widgets. `test/markdown/pointer_test.dart` runs a view
on a terminal in memory that shows the pointer's shape: a hand over a
link, a link in a heading, an image, a reference defined after it and a
link in a table, the terminal's own over the text around them, the
blank rows and out of the view; the mouse's motion followed only while
the view has a link (a block with one kept as it was included), and
neither followed nor a shape set where the terminal does not show it.
`test/markdown/markdown_links_test.dart` clicks links and images for
`onLinkTap` (a reference's title, an image in a link, a press released
elsewhere, `hyperlinks: false`, text streamed in) and checks the
headings' slugs and a `MarkdownController`'s `headings` and
`scrollToHeading` in a scroll view.
`test/markdown/commit_test.dart` runs the
inline pattern as an app writes it, on a terminal of 30 × 8 below a
line of history: an answer taller than it streamed in pieces, after every
piece the history exactly the line and the blocks settled, each once and
in order, and the region a blank row, the live block and the prompt;
each block built once for the history and the live view updating no
more elements than a `MarkdownView` fed the same pieces; a reference
defined before its block a link in the history and one defined after it
its text; and the same app full screen showing the answer in place.

`test/bigtext/big_text_test.dart` draws each
font, what it covers and what stands in, missing glyphs, braille and
ASCII at an ambiguous width of 2, fitting, alignment and the style, on a
screen whose frames go through the emulator of twk_test
(`package:twk_test/vt.dart`, in `test/bigtext/shot.dart`).

`test/highlight/samples_test.dart` lexes each language's sample,
`samples/<name>.txt`, to the tokens written beside it in
`samples/<name>.tokens` (a line of them per line of the sample, as
`tokens.dart` writes them), checks that the tokens give the text back,
and edits every line of each sample three ways and undoes the edit,
each time against the whole text lexed afresh; random text lexes in
every language, its tokens giving it back. A test per language
(`dart_test.dart` to `diff_test.dart`) checks what it tells apart and
what goes on across lines; `highlighter_test.dart` the scanner, the
lines, finding languages by name and alias, and the lines an edit lexes;
`code_view_test.dart` `CodeView` on a screen of the core's read cell by
cell (`painted.dart`): the lines and their numbers, the signs beside them
(by number, with numbers and without, an empty column, the widest sign
at an ambiguous width of 1 and 2, a wrapped line, signs moved, restyled
and taken away, and a selection leaving them out), the theme's colors
dark and light and the terminal's without a theme, a `SyntaxThemeScope`,
tabs, cutting off and wrapping, and new code, language, theme and
settings; `code_view_controller_test.dart` its code selected and copied
without the gutter, the keys that scroll it while it is focused and
their hints, a `CodeViewController`'s `scrollToLine` and `linesInView`,
the lines it highlights, and what it finds, `n` and `N` going round.

`test/diff/diff_lists_test.dart` checks `diffLists` against the fewest
edits a longest common subsequence gives, on 3000 random pairs of lists,
Myers' example and lists whose items only one of them has; with a
`maxCost` of 1, on 500 pairs, changes that still make one list into the
other, some longer than the fewest; and lists of 50,000 items.
`model_test.dart` checks `Diff.between` (hunks, context, runs merged
within twice the context, counts, line breaks) and `Diff.parse` (a git
diff of several files with renamed, new and deleted ones, lines in a
hunk that look like headers, empty context lines, the no-newline marker,
`diff -u` with times and CRLF, text with no diff, git's colored output
in `test/diff/fixtures` through twk's `stripAnsi` parsing to the same `Diff` as
its plain twin, tabs, carriage returns and wide characters kept, and
escape sequences kept in the lines of a plain diff), `words_test.dart`
`changedWords`. `diff_view_test.dart` runs `DiffView` through `testTwk`:
a fixed diff unified and side by side as text and in its colors, the
words marked over the syntax colors, the rows of lines left out before,
between and after the hunks, each side lexed as one source, the language
by path and given, tabs, the theme dark and light, and a diff of 50,000
lines that builds at most 26 `Text`s for a window of 20 rows and lexes
under a thousand lines at the start.

`test/qr/symbol_test.dart` checks the encoder against the standard's
worked example (`01234567` at 1-M: its 26 codewords) and against two
encoders of others, whose output `test/qr/generate.dart` wrote to
`test/qr/fixtures` (zint 2.16 and qrencode 4.1; `dart run
test/qr/generate.dart` writes them again): a case for each version and
level (`cases.dart`), data in one of the three modes, as much as the
version holds in it at the level or two thirds of that, bytes from 0x80
up among them; its symbol under each of the eight masks the very one
zint makes (a hash of its modules), and the mask the penalty rules choose
the one zint chooses (qrencode, whose symbol under a mask is zint's,
chooses another for 55 of the 160); the characters each version holds at
each level in each mode those qrencode puts in it. And the modes, the
versions chosen, data too long, the remainder bits of Table 1, the
alignment patterns, the generator polynomial of Annex A, the format and
version information and the masks. `qr_code_test.dart` draws `QrCode` on
a screen whose frames go through twk_test's emulator
(`test/bigtext/shot.dart`) and reads the modules back from its cells, a
half block's color in its half and the background's in the other:
versions 1 to 40 at each level, the quiet zone, the colors under either
theme and given, two columns to a module at an ambiguous width of 2, new
data, cutting off and data too long; and, where ZBar's `zbarimg` is
installed, decodes the modules read back, drawn as a bitmap, to the text:
digits, capitals, a URL, UTF-8 text, a Wi-Fi network and 700 bytes, at
each level and both widths.

`test/json_view/json_view_test.dart` runs `JsonView` through `testTwk`:
its rows (the top object expanded, `expandedDepth`, a value that is no
object or array, empty objects and arrays), each kind in its style of the
`SyntaxThemeScope` or of the `theme` given, the keys sorted, an object
through its `toJson` and a value inside itself; folding with Enter and
Space, on the row that closes an array too, a string cut and shown whole,
`*`, `expandAll` and `collapseAll`, what is expanded and selected kept by
path as the value changes, `expandAll` before a view, `reveal`; `c` and
`y` copying the path and the value (a cycle and an object as their JSON),
the keys hinted; the filter as it is typed, the entries below a match,
Enter and Escape; and JSON text, and text that is no JSON showing its
error, the line it is in and where. `lines_test.dart` checks `jsonPath`
(identifiers, other keys quoted, an index and a key of the same digits,
the root) and `jsonLines` (the indentation, `expandedDepth`, the styles of
a theme and of none, `sortKeys`, `maxStringLength`, `toJson`, keys that
are no strings, sets and cycles).

`test/exports_test.dart` checks that `lib/twk_rich.dart` exports the library
of every topic and that they load, and that `lib/` holds only it and
`image.dart`, which exports the declarations of `lib/src/image/` alone,
none of whose names `twk_rich.dart` exports.

The examples, from this directory: `dart run example/viewer.dart FILE`
shows a file. One whose name does not end in `.md` or `.markdown` and
that holds a diff, as `git diff` writes it, colors and all
(`Diff.parse(stripAnsi(text))`), or as `diff -u` does, shows as a
`DiffView`, its title naming the file, how many files the diff changes
and the lines added and removed (`2 files  +10 -4`); Tab switches it
between unified and side by side. Any other file shows as a
`MarkdownView` in a `SingleChildScrollView` under a `SelectionArea`, so a
drag selects its text and copies it (OSC 52). The arrows, Page Up, Page
Down, Home, End and the wheel scroll; q quits (`git diff --color >
/tmp/changes.diff`, then `dart run example/viewer.dart
/tmp/changes.diff`). `dart run example/chat.dart` is an agent chat in the
inline mode, below the shell's history, its answers scripted, with no
model behind them: what is sent and what the agent answers go to the
terminal's history through a `Static`, where the terminal scrolls and
selects them. An answer, Markdown with code, a list, a table and a quote
in it, streams a few characters at a time into a `MarkdownStream`; each
of its blocks goes to the history once it is complete (`takeSettled`),
the rest shown live above the prompt (`MarkdownView.blocks`), and the
region gives back the rows the block took in it. Enter sends, Esc stops
an answer, what came of it kept, and Ctrl+C quits, leaving the chat in
the history.
`test/example/` runs both through `testTwk`: the viewer on
`fixtures/guide.md`, a block of every kind, and on `fixtures/changes.diff`,
real `git diff --color` output, a tab in it at the code's tab stops, and
on a diff without colors and plain text; the chat inline below lines of
history, with the terminal's scrollback, mid-answer and after it, on a
terminal shorter than the answer, the answers in turn, Esc, and Ctrl+C.
End to end, from the repository's root:

```bash
# a diff unified, at its end, side by side, then q
python3 tool/pty_run.py --input '1.5:\t,2.2:\x1b[F,2.8:\t,3.4:q' --out /tmp/viewer.bin -- \
    dart run packages/twk_rich/example/viewer.dart packages/twk_rich/test/example/fixtures/changes.diff
dart run tool/replay.dart --fullscreen /tmp/viewer.bin 100 30

# a question and its answer in the history, then Ctrl+C
python3 tool/pty_run.py --input '1:how do I read a file?\r,4:\x03' --out /tmp/chat.bin -- \
    dart run packages/twk_rich/example/chat.dart
dart run tool/replay.dart --inline /tmp/chat.bin 100 30
```

The checks, from this directory:

```bash
dart pub get
dart analyze
dart test
dart format --output=none --set-exit-if-changed lib test example
```

## Images: `package:twk_rich/image.dart`

Images for apps on twk_core and twk, in a library of their own that
`package:twk_rich/twk_rich.dart` does not export, so that an app which
shows no image compiles none of it, nor carries the licences below:
PNG and JPEG files decoded, scaled to a box of cells, and encoded for the
terminal's graphics protocol — PNG for kitty and iTerm2, sixel — or drawn
with block characters in coloured cells where there is none; the `Image`
widget shows one in an app. The decoders and encoders use nothing but the
Dart SDK (dart:io's zlib inflates and deflates PNG on the VM; on the web,
which has no dart:io, an inflater of the package's own, and stored deflate
blocks, so that a PNG decodes in a browser too, where `Image.memory`
takes the bytes and `Image.file` throws); the widget depends on
twk_core and twk, and its tests on twk_test, as the rest of twk_rich does. The core places what it
encodes: its `TerminalImage` takes an `EncodedImage`'s `data`,
`pixelWidth` and `pixelHeight` for the protocol it was encoded for. Still
images only: an animated GIF is not read, and an APNG shows its default
image.

`lib/image.dart` exports one library per part, `lib/src/image/<part>.dart`;
its tests are in `test/image/`, its examples in `example/image/`:

| part         | provides |
|--------------|----------|
| `bitmap`     | `Bitmap(width, height)`, 8-bit RGBA pixels row by row, alpha not premultiplied (`pixels`; `pixel(x, y)` and `setPixel` as `0xAARRGGBB`; `isOpaque`); `Bitmap.fromRgba` over bytes of one's own |
| `png`        | `decodePng(bytes)`: every colour type at every bit depth PNG allows (grey 1, 2, 4, 8 and 16 bits, RGB 8 and 16, palette 1 to 8, grey and RGB with alpha 8 and 16), interlaced (Adam7) or not, with a tRNS chunk's transparency (alpha for palette entries, a grey or RGB colour key compared at the full depth); a 16-bit sample keeps its high byte. Gamma and colour space chunks (gAMA, cHRM, sRGB, iCCP) are ignored, the samples taken as they are, and so are the other ancillary chunks: an APNG decodes to its default image. Each chunk's CRC is checked; an unknown critical chunk, a file cut short or one that is not a PNG is a `FormatException`. `encodePng(image, level: 1)`: 8-bit RGB where the image is opaque, else RGBA, each row filtered with the filter whose bytes sum the least (libpng's choice), deflated at zlib `level`, by default 1, the fastest, since a terminal decodes the file at once. `isPng(bytes)` |
| `jpeg`       | `decodeJpeg(bytes)`: baseline, extended sequential (16-bit quantization tables) and progressive JPEG with restart intervals, of one component (grey), three (YCbCr, or RGB where an Adobe marker says so or the components are named R, G and B) or four (CMYK and YCCK, the inks inverted as Adobe stores them), any sampling factors from 1 to 4. Its samples are libjpeg's: the integer IDCT and colour conversion are libjpeg's own, so that it decodes as `djpeg -dct int -nosmooth` does, byte for byte; subsampled chroma is replicated, not interpolated. Not read: arithmetic coding, lossless, hierarchical and 12-bit JPEG, a height given by a DNL marker (each a `FormatException`); the Exif orientation and colour profiles are not applied. Entropy-coded data cut short decodes as zeros. `isJpeg(bytes)` |
| `image_file` | `decodeImage(bytes)`, a PNG or JPEG file by its first bytes (`ImageFormat.of`); `imageSize(bytes)`, its `(width:, height:)` from its header (IHDR, the frame's SOF) without decoding it |
| `scale`      | `CellSize(width, height)`, a cell's pixels; `CellSize.reported(w, h)` the size a terminal reports (the core's `TerminalCaps.cellPixelWidth` and `cellPixelHeight`), `CellSize.fallback` (10 × 20) where it reports none (0). `CellFit(imageWidth, imageHeight, columns:, rows:, cell:, fit:, bandHeight: 1)`: where an image goes in a box of cells — `ImageFit.contain` (all of it, as large as fits, aspect kept), `cover` (the box covered, aspect kept, as much cut from either side), `fill` (stretched), `scaleDown` (contained, never enlarged); its `columns` and `rows` are the cells it takes from the box's top left, `width` and `height` the pixels it is scaled to, `cropX`, `cropY`, `cropWidth`, `cropHeight` the part of the image shown, `scale(image)` the image so scaled; the box's height is taken down to a multiple of `bandHeight`. `resize(image, width, height, cropX:, cropY:, cropWidth:, cropHeight:)`: shrinking, each pixel the mean of those under it, weighed by how much of each is; growing, bilinear; alpha premultiplied, so that a transparent pixel's colour does not bleed |
| `sixel`      | `encodeSixel(image, colors: 256, dither: true, background:)`: the bytes a terminal takes between `ESC P` and `ESC \` — `0;1;0` (pixels not drawn keep what is under them), `q`, the raster attributes `"1;1;W;H`, the palette in percent, the bands of six rows a colour at a time, runs of four or more `!n`. The palette is the image's own colours where it has no more than `colors`, else median cut's (5 bits a channel, the box with the most pixels times its longest side split at its median), Floyd–Steinberg dithered where `dither` says. A pixel whose alpha is below 128 is not drawn; where `background` is given, every pixel is blended over it |
| `blocks`     | `BlockImage(image, columns:, rows:, cell:, fit:, mode:, background:)`, the fallback for a terminal without graphics: the image fitted to the box (`CellFit`) and drawn in `BlockCell`s, a `glyph` in `fg` on `bg` (`0xRRGGBB`, null for what is under the cell) — `BlockMode.half`, two pixels a cell, `▀` in the upper's colour on the lower's (`▄` where only the lower is drawn), or `quadrant`, four pixels a cell, the quadrant block that splits them best in two colours. `BlockImage.fromPixels(bitmap, mode:)` draws a bitmap's pixels as they are; `cells`, `cellAt(column, row)`; `toAnsi()`, the rows as text with 24-bit SGR colours, to print as they are |
| `protocols`  | `EncodedImage(data, pixelWidth:, pixelHeight:)`, what the core's `TerminalImage` takes. `kittyImage(file)`: a PNG file as it is, a JPEG one decoded and encoded as PNG. `iterm2Image(file)`: a PNG or JPEG file as it is, which iTerm2 decodes, its size read from its header. `pngImage(bitmap)`: a bitmap made or cut in memory, for either. `sixelImage(image, columns:, rows:, cell:, fit:, colors:, dither:, background:)`: scaled to the box, no taller than it in whole bands of six pixels (`CellFit(bandHeight: 6)`), so that the last band does not scroll the terminal, and encoded with `encodeSixel`. The core scales kitty and iTerm2 images to the cells it places them in itself; sixel is drawn at its pixels, so it is scaled here |
| `widget`     | `Image(source, width:, height:, fit:, alignment:, blockMode:, forceBlocks:)`, with `Image.memory(bytes)`, `Image.file(path)` (read when first laid out) and `Image.bitmap(bitmap)` for the `ImageSource`s; `RenderImage` lays it out and paints it. The box is `width` × `height` cells where given, within the constraints; an axis left out follows from the other by the image's aspect at the cell size the terminal reports (`TerminalCaps.cellPixelWidth`, `cellPixelHeight`; `CellSize.fallback` where it reports none), and without either it is the cells the image's pixels take, made smaller or larger within the constraints with its aspect kept. The image fills it as `fit` says (`CellFit`), placed by `alignment` in the cells it leaves. It is shown with the protocol of the presenter it is painted for (`TerminalCaps.graphics`, which the probe or `TWK_GRAPHICS` picks when the app starts): kitty and iTerm2 get a PNG of the fitted image as big as its cells, transparent past it, so that the terminal does not stretch it; sixel is scaled in whole bands of six pixels. Where the protocol is none, or with `forceBlocks`, it is drawn in `BlockImage` cells of `blockMode`, a transparent pixel leaving the cell under it. The file is read and its size taken from its header at the first layout, decoded at the first paint; what is drawn is kept until the box, the protocol or a property changes, so that the presenter places the same image again without sending it. A file that can't be read or decoded is an error shown in its place. Clipped, a kitty image shows what is left of it, a sixel or iTerm2 one is not shown |

### Its tests

The fixtures in `test/image/fixtures` are made by `tool/image/fixtures.py`, each image
with `<name>.rgba`, the pixels it decodes to. The PNGs are written there
with zlib and struct alone: every colour type at every bit depth,
interlaced and not (down to 1 × 1 and 2 × 3, whose Adam7 passes are
partly empty), tRNS of each kind, the IDAT split in several chunks,
ancillary chunks to skip, each row filtered with each of the five filters
in turn; their pixels are known from how they were made. The JPEGs are
made by libjpeg-turbo's `cjpeg` from a picture drawn there (4:4:4, 4:2:2,
4:2:0, 4:4:0, grey, RGB, 16-bit tables, restart intervals, optimized
tables, progressive with and without restarts, noise whose codes are 16
bits long), their pixels those `djpeg -dct int -nosmooth` decodes them to;
the CMYK one is made by Pillow and the YCCK one by ImageMagick, their
pixels what ImageMagick converts them to (within 1 of them).

`test/image/png_test.dart` decodes every PNG to its pixels and checks known
ones, rejects files cut short, failing a CRC or with an unknown critical
chunk, and round-trips noise, alpha, gradients and a single pixel through
`encodePng` at several levels. `test/image/jpeg_test.dart` decodes every JPEG
to libjpeg's pixels, data cut short as far as it goes, and rejects the
kinds it does not read. `test/image/sixel_test.dart` reads what `encodeSixel`
writes back as a terminal would (`test/image/sixel_reader.dart`, which fails on
a pixel drawn outside the raster attributes): an image of few colours in
them exactly, transparency undrawn, a background blended, runs, a
picture quantised with and without dithering within a mean error, fewer
colours, and `sixelImage`'s whole bands. `test/image/blocks_test.dart` checks
the cells of half blocks and quadrants, transparency, the fit and
`toAnsi`; `test/image/scale_test.dart` each `ImageFit`, bands, the fallback cell
and `resize`; `test/image/protocols_test.dart` the formats, `imageSize` and the
images for each protocol. `test/image/widget_test.dart` runs `Image` in an app
under `testTwk`, the terminal given each protocol and a cell size
(`pumpWidget(graphics:, cellPixels:)`), the emulator recording the
placements: its size from its pixels, a width or a height, both, and the
constraints, and its intrinsic sizes; the placement for kitty, sixel and
iTerm2, kitty's PNG padded to the cells, sixel's whole bands; half blocks
and quadrants in the image's colours, transparency over what is under it,
`forceBlocks`; each fit and alignment; the image kept through a repaint
and encoded anew for a new box or fit; PNG and JPEG files from memory and
from a path, and the errors of a file that is no image or none.
`test/image/zlib_web_test.dart` runs the web's zlib
(`lib/src/image/zlib_web.dart`) on the VM against dart:io's: what
dart:io deflates, at every level, it inflates, and what it deflates
dart:io inflates.

### Its examples

`example/image/viewer.dart` shows the PNG or JPEG file it is given below its
name and above the keys: `f` cycles the fit, `p` what it is drawn with —
the terminal's protocol, half blocks, quadrants — and `q` quits. The
protocol is the terminal's for the whole run, as the probe finds it when
the app starts or as `TWK_GRAPHICS` names it (`kitty`, `sixel`, `iterm2`,
`none`):

```bash
dart run example/image/viewer.dart photo.jpg
TWK_GRAPHICS=sixel dart run example/image/viewer.dart photo.png
```

`example/image/konsole_images.dart` shows a kitty image in a header above a log
that scrolls in hardware, for Konsole, which moves every image up on any
scroll up ([the core's doc/konsole-kitty.md](../twk_core/doc/konsole-kitty.md)):
the picture must stay in the header.

### Speed

On one core (`taskset -c 21`, its sibling 17 % busy), the median of
seven runs on a 1920 × 1080 photo: `decodePng` 104 ms (8-bit RGB),
`decodeJpeg` 60 ms (baseline 4:2:0) and 83 ms (progressive), `encodePng`
194 ms at level 1 (2.2 MB; 660 ms and 1.9 MB at level 6), `encodeSixel`
at the full size 155 ms dithered (1.8 MB) and 74 ms not, `sixelImage`
into 160 × 45 cells of 10 × 20 (1600 × 900 pixels) 178 ms, `resize` to
160 × 90 12 ms, `BlockImage` of 160 × 45 cells 16 ms in half blocks and
21 ms in quadrants.

`python3 tool/image/fixtures.py` writes the fixtures again, with
libjpeg-turbo's `cjpeg` and `djpeg`, ImageMagick and Pillow.

## License

MIT, copyright 2026 Andrii Ivanov: [LICENSE](LICENSE). The CommonMark and
GFM spec examples the Markdown tests run (`test/markdown/spec.json` and
`gfm.json`) are under CC BY-SA 4.0, as the specs are: [NOTICE](NOTICE).
The big-text fonts were drawn for this package and are MIT like the rest
of it.

`package:twk_rich/image.dart` is based in part on the work of the
Independent JPEG Group. Its JPEG decoder's integer IDCT, its YCbCr to RGB
tables and its refinement of progressive AC coefficients are translated
from libjpeg and keep the IJG's licence, whose README is
[README.ijg](README.ijg). Its walk through a scan, its decoding of the
blocks of baseline scans and of progressive scans' first passes, and its
colour transform of three components follow jpgjs, as pdf.js keeps it
(Apache License 2.0) and as package:image ports it to Dart (MIT License),
and keep those licences. [NOTICE](NOTICE) names the files and lines each
part follows and what was changed, and carries the licences. They apply
to an executable only where it imports `package:twk_rich/image.dart`;
one that imports `package:twk_rich/twk_rich.dart` alone compiles none of
that code.
