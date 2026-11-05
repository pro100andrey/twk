# twk_rich reference

What each library of the package provides. The [README](../README.md) says
what the package is for; [images.md](images.md) covers
`package:twk_rich/image.dart`.

`lib/twk_rich.dart` exports one library per topic,
`lib/src/<topic>/<topic>.dart`, each with a doc comment naming what it is for;
a topic's tests are in `test/<topic>/`.

## Markdown (`markdown`)

`parseMarkdown(text)`, the blocks of a document, and `MarkdownStream`, a
document that arrives in pieces (`add`). A block is settled once a complete
line closes it: whatever is added later, `blocks` holds it as the very object
it was (`settled` counts those blocks). `add` parses again only the lines from
the first block not settled, and of those blocks keeps each part equal to what
it was, such as the finished items of a growing list. Text added in any pieces
parses as it would whole; `close()` says that no more comes: the last line is
complete without its line ending, every block settled, `add` after it a
`StateError`. The tree is plain values, equal when their content is: blocks
(`MdBlock`) `MdParagraph`, `MdHeading`, `MdCodeBlock` (fenced with an info
string and its `language`, or indented), `MdThematicBreak`, `MdBlockQuote`,
`MdList` (`MdListItem`s, bullet or ordered from a `start`, tight or loose; a
task item `checked` or not) and `MdTable` (an `MdAlign` per column); inlines
(`MdInline`) `MdText`, `MdCode`, `MdEmphasis`, `MdStrong`, `MdStrikethrough`,
`MdLink`, `MdImage`, `MdReference`, `MdSoftBreak` and `MdHardBreak`. Link
reference definitions are left out of the blocks and collected in
`MarkdownStream.definitions`: `MdDefinition`s by the `normalizeLabel` of their
label (case-folded, blanks collapsed), the first of a label kept; one in a
block not settled may still change. Since a definition may come after the
links that use it, a reference link or image (`[text][label]`, `[label][]`,
`[label]`: `MdReferenceKind.full`, `collapsed`, `shortcut`) is an
`MdReference` holding its label and parsed text, and the blocks do not depend
on the definitions: `resolveReferences(blocks, definitions)` (`resolveInlines`
for inlines) makes each a link or image where a definition matches its label
and its literal text where none does, as is a link reference inside a link; a
block without one comes back as itself. `MarkdownView(data, appended:, theme:,
codeWrap: TextWrap.grapheme, tabWidth: 4, onLinkTap:, hyperlinks: true,
hyperlinkSchemes: MarkdownView.webSchemes, controller:)` shows a document as
widgets, its blocks one under another a blank row apart: a paragraph or a
heading is a `Text.rich` that wraps by words (CJK text between its
characters), emphasis, strong and struck text, code spans, links and images in
their styles over the text's, a link, and an image (its description, else its
source), a hyperlink (OSC 8) to its destination, under which the pointer is a
hand (`PointerShape.pointer`, in a table too) where the terminal shows the
pointer's shape, which only then, and while the view has a link, has the
terminal report the mouse's motion, a reference a link once a definition of
its label has arrived, before it or after, and its text until then, a line
ending within a paragraph a space; a list item has its marker before its
blocks, which wrap under their own first column (bullets `•`, `◦`, `▪` by
depth, numbers aligned at their right, `☐` or `☑` for a task item), with a
blank row between the items and blocks of a loose list; a block quote has a
bar down its left side, its blocks in the quote style; a block of code is a
`CodeView` (below) in the language the first word of its info string names, on
the code block fill, a cell in from either side, its lines broken as
`codeWrap` says; a table is a twk `Table` showing all its rows, aligned as its
delimiter row says, with lines between the columns and under the header, the
mouse going through it, so that the wheel over it scrolls what is around the
view; a thematic break is a line across. With `onLinkTap(destination, title)`,
a click (a press and a release of the left button on the same cell) on a link
or an image goes to the app with its destination (an image's source) and
title, a reference link's from its definition, the innermost of an image in a
link, instead of to the terminal (a chat's own links, a help viewer's); links
take no focus. The hyperlink (OSC 8) is still written unless `hyperlinks:
false`, and only for the `hyperlinkSchemes` of a destination (lower case; by
default `MarkdownView.webSchemes`, `http`, `https` and `mailto`): a link to
another (`javascript:`, `file:`, one without a scheme, `#install`, `notes.md`)
is shown as a link and left to `onLinkTap`, without which the hand pointer and
the clicks still find the links of paragraphs and headings, those of tables
only with it. The bullets, numbers, boxes and bars are not text: a
`SelectionArea` the app puts around one view or many selects and copies the
text of the blocks alone. New `data` that is the old with text added at its
end is parsed again only where that text may change it (`MarkdownStream.add`);
to see that it is, the view compares the old `data` with the start of the new,
the whole of it, unless `appended:` gives the piece just added (as a chat
knows it), when it checks only the length and that `data` ends with the piece,
so a piece costs its own length, not the answer's; and a block it leaves as it
was keeps its widgets, not built again unless a definition one of its
references uses changed, as does an item a growing list keeps; other new
`data` is parsed whole. A `MarkdownController` given as `controller:` lists
the view's headings (`headings`, each a `MarkdownHeading`: `text`, `level` and
its GitHub `slug`, lower case, punctuation dropped, blanks made `-`, a
repeated one `-1`, `-2`; `markdownHeadings(blocks)` finds them in quotes and
list items too), its listeners told after a build that changed them, also as
text streams in, and `scrollToHeading('install')` (or `'#install'`) scrolls
the `Scrollable`s around the view the least that shows that heading, returning
whether there is one, so an app can follow a `#install` link from `onLinkTap`.
`MarkdownView.blocks(blocks, definitions:, theme:, codeWrap:, tabWidth:,
onLinkTap:, hyperlinks:, hyperlinkSchemes:, controller:)` shows blocks parsed
already, their references resolved by `definitions`, with the same widgets, a
block given again, the very same object, keeping them. The view takes the
width it is given, which must be bounded, and is as tall as its blocks (in a
`SingleChildScrollView` to scroll). `renderMarkdown(segmenter, text, width,
theme, glyphs: Glyphs.unicode)` makes the same document lines of styled text,
`List<List<Span>>` wrapped to `width` columns (an empty line between blocks
has no spans), for an app that draws it itself in a panel that cuts and
colours by the cell: it parses, styles and words as the view does (wrapping by
words, CJK between characters; list markers, quote bars, table lines), the
styles of its spans resolved (the quote's, a heading's and an emphasis's
merged in), its links hyperlinks, to the web or an address, as the view's by
default; its marks (bullets, task boxes, rule, quote bar, table lines) those
of `glyphs`, which a widget passes from its `Theme`; code blocks are
highlighted in the language of their fence in the `syntax` styles of the
theme, over the code block's style (a view takes the `SyntaxTheme` at its
place instead), and the rule under a table's header ends with its last column.
An app in the inline mode puts each block of an answer that streams in into
the terminal's history as it settles, so that an answer taller than the
terminal is all there and the region holds only what still changes:
`MarkdownStream.takeSettled()` gives the blocks settled since the last call,
in order, each with its references resolved by the definitions of the blocks
settled by then (one defined later, or in a block not settled, is its text
there: holding a block back for it would hold back every block after it), and
`live` the blocks it has not given. On each piece the app adds it (`close()`
at the end) and adds what `takeSettled()` gives to the items of a twk
`Static`, which builds each into `MarkdownView.blocks([block])` with a blank
row above it (`Padding(padding: EdgeInsets.only(top: 1))`, as the blocks of a
view are apart), above a `MarkdownView.blocks(answer.live, definitions:
answer.definitions)` and the prompt: the `Static` writes the block to the
history and fits the region to what is left in the same frame, the rows the
block took given back (the doc comment of `MarkdownStream` has the code). The
history takes whole blocks, so a list or a block of code is live until it
ends, the region showing as much of it as fits; in the fullscreen mode the
same app shows the answer in place. `MarkdownTheme`, a style per part, unset
ones looking as the text around (`heading1` to `heading6`, `heading(level)`,
`emphasis`, `strong`, `strikethrough`, `code`, `link`, `image`, `codeBlock`,
`quote`, `quoteBar`, `marker`, `rule`, `tableHeader`, `tableBorder`, `syntax`,
the `SyntaxTheme` of `renderMarkdown`'s code; `copyWith`);
`MarkdownTheme.from(ThemeData)`, a view's without one, in the colors of the
`Theme`: headings bold, the first two `primary` (the first underlined), the
third `accent`, the last `muted`; emphasis italic, strong text bold, struck
text struck through; code `accent` on `surface`, code blocks on `surface`;
links `primary` underlined, images `info` italic; quotes `muted`, their bar,
rules and the lines of tables `border`; bullets and numbers `muted`; table
headers bold

## Syntax highlighting (`highlight`)

Source code split into tokens by lexers of this package's own, a line at a
time. A `Language` (`name`, `aliases`, `lexer`) is found by
`languageNamed(name)` (among `languages`, or those given) by its name or an
alias in any case, as the info string of a Markdown fence names it, and a name
none goes by gives `Language.plain`, each line one plain token: `dart`; `json`
(`jsonc`); `yaml` (`yml`); `bash` (`sh`, `shell`, `zsh`); `javascript` (`js`,
`jsx`, `mjs`, `cjs`) and `typescript` (`ts`, `tsx`, `mts`, `cts`); `python`
(`py`, `py3`, `python3`); `rust` (`rs`); `go` (`golang`); `diff` (`patch`). A
`Token` is text of a `TokenKind`: `plain`, `keyword`, `type`, `function`,
`variable`, `constant`, `string`, `escape`, `number`, `comment`, `annotation`,
`key`, `punctuation`, `operator`, and a diff's `inserted`, `deleted` and
`heading` lines. A `Lexer`'s `lexLine` lexes a line held by a `TokenScanner`
(which makes tokens of one kind that follow each other one token, and leaves
what the lexer does not reach plain) from the state the line before ended in,
and returns the state the line ends in: null at the start of the source, or a
value, such as a `LexFrame`, a stack of the modes that nest (code in a string
in code); equal states must lex the next line alike. What goes on across
lines: block comments (nested in Dart and Rust); Dart's and Python's strings
three quotes long and the code in them; JavaScript's and TypeScript's template
literals and the code in them; Python's and JavaScript's strings whose line
ends in a backslash; Rust's strings and raw strings; Go's raw strings; YAML's
block scalars, quoted scalars and flow collections; Bash's strings, command
substitutions, arithmetic and heredocs; a diff's hunks, whose headers count
their lines, so in a hunk a line that starts with `---` or `+++` is a removed
or an added one. Rules a reader may trip on: a JavaScript `/` starts a regular
expression where a value goes (at the start of its line, after an operator, a
keyword or punctuation other than a closing bracket) when another `/` closes
it on the line, and divides elsewhere; JSX is not told apart, its tags lex as
code; a Go name that starts with a capital is exported, not a type, so plain
where nothing else tells what it is; Python's `match`, `case` and `type` are
keywords only where they start a statement; Rust's lifetimes and labels are
types and its macros functions; the command of each Bash command line is a
function. `Highlighter(language, text)` keeps source lexed through edits:
`replaceLines(start, end, lines)`, and `update(text)`, which replaces the
lines between those that stayed the same, lex the lines put in, then those
after them only until one starts in the state it started in before, and return
how many lines they lexed; the lines not lexed keep their token lists as the
very objects they were. `SyntaxTheme`, a `Style` per kind (`styleOf`, `spans`,
`copyWith`), unset ones taking the style of the text around;
`SyntaxTheme.from(ThemeData)` in the colors of the app's theme: keywords
`accent`; functions and keys `primary`; types, escapes and operators `info`;
strings and inserted lines `success`; numbers, constants and annotations
`warning`; variables and deleted lines `error`; comments `muted` and italic; a
diff's headings `info` and bold. `SyntaxTheme.of(context)` is that of the
nearest `SyntaxThemeScope`, else `from` the `Theme` there. `CodeView(code,
language:, lineNumbers:, firstLineNumber: 1, tabWidth: 4, wrap: TextWrap.none,
signs:, controller:, focusNode:, autofocus: false, highlightStyle:,
matchStyle:, currentMatchStyle:)`: a line of rich text per line in the styles
of `SyntaxTheme.of`, with `lineNumbers` each line's number before it,
right-aligned in the theme's `muted`, a blank between; a line break at the end
of the code ends its last line, a tab moves to the next multiple of `tabWidth`
columns, and a line wider than the view is cut off unless `wrap` says
otherwise. `signs` are an app's own marks in the gutter (diagnostics,
breakpoints, a change since the last commit): a `CodeSign(glyph, style:)` by
the number of the line it is beside, as the gutter numbers them, in a column
before the numbers (before the code without them), a blank after it, as wide
as the widest sign as the canvas draws it, each sign at its left on the first
row of its line in its `style` over the text's; a line without one has blanks
there, and the column is there for an empty map too, so that the code does not
move as signs come and go (none for null). Below a `SelectionArea` its code is
selected and copied as a Text's is (the view is one `Selectable`), its lines
joined by line breaks and its tabs as tabs; the signs and the numbers are left
out. With a `controller:`, a `focusNode:` or `autofocus:` it scrolls its lines
itself, a `ListView` that builds those in view, taking all the room it is
given, which must be bounded: focused, the arrows, Page Up, Page Down, Home
and End scroll it, hinted for a `KeyHintsBar`, and Left and Right scroll lines
not wrapped across, `CodeView.sideStep` (4) columns at a time, as far as the
widest; without any of them it is as tall as its lines. A
`CodeViewController(query:)`, given to one view at a time, names lines by
their numbers in the gutter: `scrollToLine(n, alignment:)` scrolls the least
that shows line n, or puts it `alignment` down the window (0 the top, 0.5 the
middle, 1 the bottom), also when asked before the view is laid out;
`linesInView` gives `(first:, last:)`; `highlightLines(lines, style:)`,
`highlightRange(first, last, style:)`, `unhighlightLines` and
`clearHighlights` mark lines (an error, where a debugger stopped) across the
view in their style or the view's `highlightStyle`, by default a tint of the
theme's `primary`, `highlights` holding them; `query` finds text, ignoring the
case while it is all in lower case, `matches` (`CodeMatch(line, start, end)`)
drawn in `matchStyle` (reverse video), the current one (`currentMatch`,
`currentMatchIndex`) in `currentMatchStyle` (`accent` in reverse video and
bold); `nextMatch()` and `previousMatch()`, and `n` and `N` while there is a
query, go round them, from the window without a current one, scrolling to show
it, across too. It notifies its listeners of each change and of each scroll.
New code lexes only the lines it changed (`update`), and a line whose tokens
and sign are kept keeps its widget; a new language lexes it whole.
`dartSourceLines(excerpt, theme)`, the `SourceLines` of twk's `traceback`: the
lines of the source an error was thrown in highlighted as Dart in
`SyntaxTheme.from(theme)`, the file lexed from its top. A language is added as
a file `lang/<name>.dart` with its lexer and `const <name>Language`, imported,
exported and listed in `languages.dart` (the `Lexer` doc)

## Big text (`bigtext`)

`BigText`, text in letters several cells tall (splash screens, clocks, the
numbers of a dashboard), and its `RenderBigText`: each line set in `font`, or
in the first of `fonts` (by default `BigFont.sizes`: `large`, `block`,
`small`) it fits in, the last when it fits in none; as wide as its widest line
and as tall as its lines, a blank row apart, each placed as `align`
(`TextAlign`; `start` as `left`, `end` as `right`) says, in `style` merged
onto the `DefaultTextStyle` above (the letters in its `fg`, over its `bg`
where it sets one). The fonts (`BigFont.values`), drawn for this package:
`large`, 5×8 pixels as full blocks two cells wide, 8 rows to a line; `block`,
the same pixels as half blocks, 4 rows; both with both cases of the Latin and
Cyrillic (Russian and Ukrainian) letters, digits, the ASCII punctuation and
the degree sign; `thin`, light box drawing, 3 rows, and `small`, 3×5 pixels as
half blocks, 3 rows, both with capitals of the Latin and Cyrillic letters,
digits and the common punctuation. A character a font has no glyph for is
drawn as one that stands for it (a letter as its other case, an accented one
without its accent, a Cyrillic one as the Latin letter it looks like), or else
as `missing` says: `MissingGlyph.box`, the font's box, or `plain`, itself on
the middle row. Where the canvas draws blocks and box drawing two columns wide
(East Asian ambiguous), the pixel fonts draw braille of the same pixels and
`thin` ASCII, as big as before

## Diffs (`diff`)

`diffLists(a, b, maxCost:)`, the `DiffChange`s that make list `a` into `b`, in
order, apart by items both keep (items equal by `==` and `hashCode`): each the
items from `oldStart` up to `oldEnd` replaced by those from `newStart` up to
`newEnd`. They are those of a shortest edit script, the fewest items removed
and added, by Myers' algorithm in linear space, O((N+M)·D) time and O(N+M)
memory, once the head and the tail the lists share and the items only one of
them has are set aside; the search for where the edits divide gives up after
`maxCost` edits (by default the larger of 256 and the square root of N+M) and
divides them where it got furthest, as GNU diff and git do: past that bound
the changes still make `a` into `b`, the items kept equal and in order, but
may remove and add more than the fewest, each such division costing
O((N+M)·`maxCost`). A `Diff` is `FileDiff`s (`oldPath` and `newPath`, null for
none, `path`, the new one or the old one of a file deleted; `headers`;
`hunks`; `oldLines` and `newLines` where the whole texts are known) of
`DiffHunk`s (`oldStart`, `oldCount`, `newStart`, `newCount`, the `section` its
header names, `lines`) of `DiffLine`s (`kind`, a `DiffLineKind`: `context`,
`removed` or `added`; `text`; `oldNumber` and `newNumber`, from 1, on the
sides that have it). `Diff.parse(text)` reads a unified diff of any number of
files, as `diff -u` and `git diff` write it: a file's part starts at a `diff `
line, or at a `--- ` line that a `+++ ` line follows out of a hunk unless it
is the first of a part a `diff --git` line started; its paths are those of its
`--- ` and `+++ ` lines (`/dev/null` none), without the time after a tab and
the quotes, or else of its `rename from` and `rename to` lines or its `diff
--git` line, the `a/` and `b/` that start them taken off where both have
theirs; a hunk takes as many lines of each side as its header counts, so a
`--- ` line in it is a line removed, an empty line in it is an empty line of
context and a `\` line (no line break at the end of the file) is left out; the
lines of a part before its first hunk are its `headers`, other lines out of
hunks are left out. It reads the text as it is, an escape sequence part of the
line it is in, as in a diff of a file that holds them: the output of `git diff
--color` goes through `stripAnsi` first, `Diff.parse(stripAnsi(output))`.
`Diff.between(before, after, context: 3, path:)` finds the changes between two
texts (lines split at `\n` and `\r\n`, a line break at the end ending the last
line), each run of them a hunk with `context` lines before and after, runs at
most 2 × `context` lines apart one hunk. `changedWords(before, after)`, the
ranges of code units of each of two lines that the fewest words removed and
added change, a word a run of letters, digits and `_` (every character outside
ASCII a letter), a run of blanks, or any other character alone; null where the
characters other than blanks both keep are fewer than 40 % of those they have.
`DiffView(diff, layout:, language:, tabWidth: 4, theme:, controller:,
focusNode:, autofocus:)` shows a diff in the rows of a `ListView`, which
builds those in view (of a diff of fifty thousand lines, a window's worth) and
scrolls as a list does: `DiffLayout.unified`, each line after a gutter of its
old and its new number and its sign (`-` removed, `+` added), or `sideBySide`,
the old side left of a `│` and the new side right of it, each line after its
number and sign. In a run of lines removed and added the first removed pairs
with the first added, the second with the second, and so on: side by side a
pair shares a row, the other side blank where a line has none; the words a
pair changed are marked over the syntax colors. A file with a path starts with
a row that names it (`old → new` where it was renamed), and the unchanged
lines a diff leaves out before a hunk, between hunks and, where the whole file
is known, after the last are a row `⋯ N unchanged lines` (the mark is the
theme's `glyphs.omitted`, a file's `→` its `arrowRight`, the `│` of the side
by side its `separator`) with the section of the hunk after it. Each side is
highlighted (`highlight`) as one source, lexed from its first line down as far
as the rows shown need: the whole file for `Diff.between`, its lines in the
hunks for `Diff.parse`; in `language`, by default the one the extension of the
file's path names (`languageNamed`), in the `SyntaxTheme` there. A tab moves
to the next multiple of `tabWidth` columns; a line wider than its column is
cut off. It takes all the room it is given, which must be bounded.
`DiffTheme`, the styles of the parts (`added`, `removed`, `addedWords`,
`removedWords`, `addedSign`, `removedSign`, `lineNumbers`, `collapsed`,
`file`, `divider`), unset ones leaving the style under them;
`DiffTheme.from(ThemeData)`, a view's without one, in the colors of the
`Theme`: added and removed rows on a tint of `success` and of `error` (their
text color at alpha 0x30), the words changed on a stronger one (0x70), the
signs in those colors, numbers `muted`, the rows of lines left out `muted` on
`surface`, those of files bold `info` on `surface`, the divider `border`

## JSON (`json_view`)

`JsonView(value:, controller:, rootName: r'$', onPathCopied:, theme:,
sortKeys: false, maxStringLength: 200, focusNode:, autofocus: false)` shows a
JSON document or a Dart value as a tree that folds, in a `TreeView`'s rows:
each object and array a row that folds (`▾ {`, `├─▸ "dependencies": { 4 keys
},`, `[ 2 items ]` collapsed), its entries below it, indented and joined to it
by guides, and a row that closes it; keys, strings, numbers, `true`, `false`,
`null` and brackets each in its style of `theme` (a `SyntaxTheme`; the
`SyntaxThemeScope`'s when null). `value` is a `Map`, a `List` (a `Set` shows
as one), a `String`, a `num`, a `bool` or null; any other object shows as what
its `toJson()` gives, or else as its `toString()` in a string, and a value
inside itself as `<cycle>`. `JsonView.parse(source, …)` shows JSON text, or
the `FormatException` it fails with and the place in it. `sortKeys` orders an
object's keys, which are otherwise in the map's order; a string longer than
`maxStringLength` characters is cut with `…` until Enter shows it whole. The
keys are a `TreeView`'s (Up, Down, Left, Right, Page Up, Page Down, Home, End;
`*` expands the value selected and everything below it) and, hinted while it
has the focus: Enter and Space fold the object or array selected, or show a
string cut whole and cut it again; `c` copies the path of the value selected
(`jsonPath`, from `rootName`: `$.scripts[0]`) to the clipboard and calls
`onPathCopied` with it, `y` copies the value as JSON, indented (OSC 52, as a
`TextField` copies); `/` opens a field at the bottom whose text filters the
keys as a `CommandPalette` does (`fuzzyMatch`): the entries whose keys match
show, with what is below them and the objects above them expanded, the
characters found standing out and the best match selected; Enter goes back to
the tree, the filter kept, and Escape clears it and puts back what was
expanded. A `JsonViewController(expandedDepth: 1)` holds what is expanded and
selected, by path, kept as the value changes around it: `selectedPath`,
`selectedValue` (as it was given), `isExpanded(path)`, `expandAll()` (waiting
for a view without one), `collapseAll()` and `reveal(path)`, which expands
what is above a value, selects it and scrolls to it; the view makes one of its
own, which expands the top value only, when none is given. It takes all the
room it is given, which must be bounded. `jsonPath(segments, root: r'$')`
names the path of a value from its keys and indexes (`$.name`, `$["a key"]`,
`$.scripts[0]`; `[0]` an index and `["0"]` a key), and `jsonLines(value,
theme:, expandedDepth:, sortKeys: false, maxStringLength:)` gives the lines a
view shows `value` in, every object and array expanded or those less than
`expandedDepth` levels below the top, indented two blanks a level, each a list
of `Span`s in the theme's styles (the terminal's own colors without one): for
a program's output

## QR codes (`qr`)

`QrSymbol.encode(text, level: QrErrorCorrection.medium, version:, mask:)`,
text as a QR code (ISO/IEC 18004, Model 2), written from the standard: in the
mode of fewest bits that holds all of it (`QrMode.numeric` for digits,
`alphanumeric` for digits, capitals and ` $%*+-./:`, `byte` for its UTF-8
otherwise, with no ECI, as phones read it; `QrSymbol.bytes(bytes, level:,
version:, mask:)` for bytes, each from 0 to 255), at one of the four levels of
error correction (`low`, `medium`, `quartile`, `high`, restoring about 7, 15,
25 and 30 % of the codewords), in the smallest of the 40 versions it fits in,
or in `version`, data that does not fit an `ArgumentError`. After the data the
terminator and the pad codewords; the codewords split into the blocks of the
version and level (Table 9), each with its Reed-Solomon codewords over GF(2⁸),
interleaved, and placed up and down columns two wide around the function
patterns: the finder patterns and their separators, the timing and alignment
patterns (Annex E), the dark module, and the format information and, from
version 7, the version information, each twice with its BCH code. The data is
laid under the one of the eight masks the standard's four penalty rules score
lowest, the first of those that tie, or under `mask`: runs of five or more
modules of a color in a row or a column, blocks of 2 × 2 of a color, dark,
light, three dark, light, dark with four light modules before or after it
(those outside the symbol light, as the quiet zone is), and every 5 % the dark
modules are off half. A symbol has its `version`, `size` (4 × version + 17
modules a side), `level`, `mode`, `mask` and `isDark(x, y)`. `QrCode(data,
level:, quietZone: 4, dark:, light:)`, and `QrCode.symbol(symbol, quietZone:
4, dark:, light:)`, a symbol made already, draws one with `quietZone` light
modules around it in half blocks, two modules to a cell one above the other,
so that a module is about square: `dark` on `light`, black on white in 24-bit
color by default whatever the theme, since a scanner looks for dark modules on
a light ground; n columns and (n + 1) / 2 rows for a side of n modules with
the quiet zone, or, where the canvas draws half blocks two columns wide, each
module two blanks in its color, n rows of 2n columns. Within smaller
constraints it is cut off, and data too long is an error in its place
(`RenderQrCode`)

## The examples

From the package's directory: `dart run example/viewer.dart FILE` shows a
file. One whose name does not end in `.md` or `.markdown` and that holds a
diff, as `git diff` writes it, colors and all (`Diff.parse(stripAnsi(text))`),
or as `diff -u` does, shows as a `DiffView`, its title naming the file, how
many files the diff changes and the lines added and removed (`2 files  +10
-4`); Tab switches it between unified and side by side. Any other file shows
as a `MarkdownView` in a `SingleChildScrollView` under a `SelectionArea`, so a
drag selects its text and copies it (OSC 52). The arrows, Page Up, Page Down,
Home, End and the wheel scroll; q quits (`git diff --color >
/tmp/changes.diff`, then `dart run example/viewer.dart /tmp/changes.diff`).
`dart run example/chat.dart` is an agent chat in the inline mode, below the
shell's history, its answers scripted, with no model behind them: what is sent
and what the agent answers go to the terminal's history through a `Static`,
where the terminal scrolls and selects them. An answer, Markdown with code, a
list, a table and a quote in it, streams a few characters at a time into a
`MarkdownStream`; each of its blocks goes to the history once it is complete
(`takeSettled`), the rest shown live above the prompt (`MarkdownView.blocks`),
and the region gives back the rows the block took in it. Enter sends, Esc
stops an answer, what came of it kept, and Ctrl+C quits, leaving the chat in
the history.
