# How twk_rich is tested

For those who work on the package. The [README](../README.md) is where to
start with using it.

Its tests use [twk_test](https://pub.dev/packages/twk_test), whose tester
(`testTwk`) runs the views and whose emulator the big text tests write their
frames to.

## Markdown

`test/markdown/spec_test.dart` parses the 652 examples of the CommonMark Spec
0.31.2 and the 23 of GFM 0.29's tables, task list items, strikethrough and
autolinks, resolves their references, and compares them, written as HTML
(`test/markdown/html.dart`), with the spec's. Every GFM example passes, and
571 CommonMark ones; the 81 left out are listed by why, and a test checks that
each still fails: raw HTML is text (72); a reference is parsed before its
label is known to be defined, which CommonMark's result depends on for a
reference within link text (1), brackets leaving emphasis in them unmatched
(1) and a full reference with an undefined label before another (2); character
references by names HTML 4 does not have are text (1); GFM's extended
autolinks make links of URLs and email addresses in the text (4).
`test/markdown/stream_test.dart` adds every example, and a document with a
block of every kind and a reference defined after it, split at every point and
a character at a time, and checks the blocks and the definitions against the
whole parse; and the blocks taken for the history, each once and in order, in
any pieces the blocks of the document, their references links where a
definition settled before (in the same piece too) and their text where none
has, one not settled not used, and `close` settling every block and the last
line, `add` after it an error. `test/markdown/parse_test.dart` checks the tree
beyond what the HTML shows: the values of each kind of block and inline,
definitions, reference links and resolving them.
`test/markdown/view_test.dart` runs `MarkdownView` through twk_test's
`testTwk`: each kind of block and inline in its style, links' OSC 8 targets
and a reference defined after it, code highlighted and wrapped or cut off,
tables (alignment, links, the wheel scrolling past them, their text selected),
the `Theme`'s styles and a new theme, the text selected and copied without the
bullets, CJK and wide text wrapped, a bullet the terminal draws two columns
wide; and a document streamed in pieces of 17 characters, every element of a
block settled before a piece keeping its widget and all of them updated less
than a tenth as often as a rebuild of every block would, a growing list
keeping its items' elements, a definition arriving late, numbers growing wider
and a code block growing; and `MarkdownView.blocks`, shown as the view of
their document shows them, resolved by the definitions given, a block kept
keeping its widgets. `test/markdown/pointer_test.dart` runs a view on a
terminal in memory that shows the pointer's shape: a hand over a link, a link
in a heading, an image, a reference defined after it and a link in a table,
the terminal's own over the text around them, the blank rows and out of the
view; the mouse's motion followed only while the view has a link (a block with
one kept as it was included), and neither followed nor a shape set where the
terminal does not show it. `test/markdown/markdown_links_test.dart` clicks
links and images for `onLinkTap` (a reference's title, an image in a link, a
press released elsewhere, `hyperlinks: false`, text streamed in) and checks
the headings' slugs and a `MarkdownController`'s `headings` and
`scrollToHeading` in a scroll view. `test/markdown/commit_test.dart` runs the
inline pattern as an app writes it, on a terminal of 30 × 8 below a line of
history: an answer taller than it streamed in pieces, after every piece the
history exactly the line and the blocks settled, each once and in order, and
the region a blank row, the live block and the prompt; each block built once
for the history and the live view updating no more elements than a
`MarkdownView` fed the same pieces; a reference defined before its block a
link in the history and one defined after it its text; and the same app full
screen showing the answer in place.

## Big text

`test/bigtext/big_text_test.dart` draws each font, what it covers and what
stands in, missing glyphs, braille and ASCII at an ambiguous width of 2,
fitting, alignment and the style, on a screen whose frames go through the
emulator of twk_test (`package:twk_test/vt.dart`, in
`test/bigtext/shot.dart`).

## Syntax highlighting

`test/highlight/samples_test.dart` lexes each language's sample,
`samples/<name>.txt`, to the tokens written beside it in
`samples/<name>.tokens` (a line of them per line of the sample, as
`tokens.dart` writes them), checks that the tokens give the text back, and
edits every line of each sample three ways and undoes the edit, each time
against the whole text lexed afresh; random text lexes in every language, its
tokens giving it back. A test per language (`dart_test.dart` to
`diff_test.dart`) checks what it tells apart and what goes on across lines;
`highlighter_test.dart` the scanner, the lines, finding languages by name and
alias, and the lines an edit lexes; `code_view_test.dart` `CodeView` on a
screen of the core's read cell by cell (`painted.dart`): the lines and their
numbers, the signs beside them (by number, with numbers and without, an empty
column, the widest sign at an ambiguous width of 1 and 2, a wrapped line,
signs moved, restyled and taken away, and a selection leaving them out), the
theme's colors dark and light and the terminal's without a theme, a
`SyntaxThemeScope`, tabs, cutting off and wrapping, and new code, language,
theme and settings; `code_view_controller_test.dart` its code selected and
copied without the gutter, the keys that scroll it while it is focused and
their hints, a `CodeViewController`'s `scrollToLine` and `linesInView`, the
lines it highlights, and what it finds, `n` and `N` going round.

## Diffs

`test/diff/diff_lists_test.dart` checks `diffLists` against the fewest edits a
longest common subsequence gives, on 3000 random pairs of lists, Myers'
example and lists whose items only one of them has; with a `maxCost` of 1, on
500 pairs, changes that still make one list into the other, some longer than
the fewest; and lists of 50,000 items. `model_test.dart` checks `Diff.between`
(hunks, context, runs merged within twice the context, counts, line breaks)
and `Diff.parse` (a git diff of several files with renamed, new and deleted
ones, lines in a hunk that look like headers, empty context lines, the
no-newline marker, `diff -u` with times and CRLF, text with no diff, git's
colored output in `test/diff/fixtures` through twk's `stripAnsi` parsing to
the same `Diff` as its plain twin, tabs, carriage returns and wide characters
kept, and escape sequences kept in the lines of a plain diff),
`words_test.dart` `changedWords`. `diff_view_test.dart` runs `DiffView`
through `testTwk`: a fixed diff unified and side by side as text and in its
colors, the words marked over the syntax colors, the rows of lines left out
before, between and after the hunks, each side lexed as one source, the
language by path and given, tabs, the theme dark and light, and a diff of
50,000 lines that builds at most 26 `Text`s for a window of 20 rows and lexes
under a thousand lines at the start.

## QR codes

`test/qr/symbol_test.dart` checks the encoder against the standard's worked
example (`01234567` at 1-M: its 26 codewords) and against two encoders of
others, whose output `test/qr/generate.dart` wrote to `test/qr/fixtures` (zint
2.16 and qrencode 4.1; `dart run test/qr/generate.dart` writes them again): a
case for each version and level (`cases.dart`), data in one of the three
modes, as much as the version holds in it at the level or two thirds of that,
bytes from 0x80 up among them; its symbol under each of the eight masks the
very one zint makes (a hash of its modules), and the mask the penalty rules
choose the one zint chooses (qrencode, whose symbol under a mask is zint's,
chooses another for 55 of the 160); the characters each version holds at each
level in each mode those qrencode puts in it. And the modes, the versions
chosen, data too long, the remainder bits of Table 1, the alignment patterns,
the generator polynomial of Annex A, the format and version information and
the masks. `qr_code_test.dart` draws `QrCode` on a screen whose frames go
through twk_test's emulator (`test/bigtext/shot.dart`) and reads the modules
back from its cells, a half block's color in its half and the background's in
the other: versions 1 to 40 at each level, the quiet zone, the colors under
either theme and given, two columns to a module at an ambiguous width of 2,
new data, cutting off and data too long; and, where ZBar's `zbarimg` is
installed, decodes the modules read back, drawn as a bitmap, to the text:
digits, capitals, a URL, UTF-8 text, a Wi-Fi network and 700 bytes, at each
level and both widths.

## JSON

`test/json_view/json_view_test.dart` runs `JsonView` through `testTwk`: its
rows (the top object expanded, `expandedDepth`, a value that is no object or
array, empty objects and arrays), each kind in its style of the
`SyntaxThemeScope` or of the `theme` given, the keys sorted, an object through
its `toJson` and a value inside itself; folding with Enter and Space, on the
row that closes an array too, a string cut and shown whole, `*`, `expandAll`
and `collapseAll`, what is expanded and selected kept by path as the value
changes, `expandAll` before a view, `reveal`; `c` and `y` copying the path and
the value (a cycle and an object as their JSON), the keys hinted; the filter
as it is typed, the entries below a match, Enter and Escape; and JSON text,
and text that is no JSON showing its error, the line it is in and where.
`lines_test.dart` checks `jsonPath` (identifiers, other keys quoted, an index
and a key of the same digits, the root) and `jsonLines` (the indentation,
`expandedDepth`, the styles of a theme and of none, `sortKeys`,
`maxStringLength`, `toJson`, keys that are no strings, sets and cycles).

## Exports

`test/exports_test.dart` checks that `lib/twk_rich.dart` exports the library
of every topic and that they load, and that `lib/` holds only it and
`image.dart`, which exports the declarations of `lib/src/image/` alone, none
of whose names `twk_rich.dart` exports.

## The examples

`test/example/` runs both through `testTwk`: the viewer on
`fixtures/guide.md`, a block of every kind, and on `fixtures/changes.diff`,
real `git diff --color` output, a tab in it at the code's tab stops, and on a
diff without colors and plain text; the chat inline below lines of history,
with the terminal's scrollback, mid-answer and after it, on a terminal shorter
than the answer, the answers in turn, Esc, and Ctrl+C. End to end, from the
repository's root:

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

## The checks

From the package's directory:

```bash
dart pub get
dart analyze
dart test
dart format --output=none --set-exit-if-changed lib test example
```

## Images

The fixtures in `test/image/fixtures` are made by `tool/image/fixtures.py`,
each image with `<name>.rgba`, the pixels it decodes to. The PNGs are written
there with zlib and struct alone: every colour type at every bit depth,
interlaced and not (down to 1 × 1 and 2 × 3, whose Adam7 passes are partly
empty), tRNS of each kind, the IDAT split in several chunks, ancillary chunks
to skip, each row filtered with each of the five filters in turn; their pixels
are known from how they were made. The JPEGs are made by libjpeg-turbo's
`cjpeg` from a picture drawn there (4:4:4, 4:2:2, 4:2:0, 4:4:0, grey, RGB,
16-bit tables, restart intervals, optimized tables, progressive with and
without restarts, noise whose codes are 16 bits long), their pixels those
`djpeg -dct int -nosmooth` decodes them to; the CMYK one is made by Pillow and
the YCCK one by ImageMagick, their pixels what ImageMagick converts them to
(within 1 of them).

`test/image/png_test.dart` decodes every PNG to its pixels and checks known
ones, rejects files cut short, failing a CRC or with an unknown critical
chunk, and round-trips noise, alpha, gradients and a single pixel through
`encodePng` at several levels. `test/image/jpeg_test.dart` decodes every JPEG
to libjpeg's pixels, data cut short as far as it goes, and rejects the kinds
it does not read. `test/image/sixel_test.dart` reads what `encodeSixel` writes
back as a terminal would (`test/image/sixel_reader.dart`, which fails on a
pixel drawn outside the raster attributes): an image of few colours in them
exactly, transparency undrawn, a background blended, runs, a picture quantised
with and without dithering within a mean error, fewer colours, and
`sixelImage`'s whole bands. `test/image/blocks_test.dart` checks the cells of
half blocks and quadrants, transparency, the fit and `toAnsi`;
`test/image/scale_test.dart` each `ImageFit`, bands, the fallback cell and
`resize`; `test/image/protocols_test.dart` the formats, `imageSize` and the
images for each protocol. `test/image/widget_test.dart` runs `Image` in an app
under `testTwk`, the terminal given each protocol and a cell size
(`pumpWidget(graphics:, cellPixels:)`), the emulator recording the placements:
its size from its pixels, a width or a height, both, and the constraints, and
its intrinsic sizes; the placement for kitty, sixel and iTerm2, kitty's PNG
padded to the cells, sixel's whole bands; half blocks and quadrants in the
image's colours, transparency over what is under it, `forceBlocks`; each fit
and alignment; the image kept through a repaint and encoded anew for a new box
or fit; PNG and JPEG files from memory and from a path, and the errors of a
file that is no image or none. `test/image/zlib_web_test.dart` runs the web's
zlib (`lib/src/image/zlib_web.dart`) on the VM against dart:io's: what dart:io
deflates, at every level, it inflates, and what it deflates dart:io inflates.

`python3 tool/image/fixtures.py` writes the fixtures again, with
libjpeg-turbo's `cjpeg` and `djpeg`, ImageMagick and Pillow.

## Speed of the images

On one core (`taskset -c 21`, its sibling 17 % busy), the median of seven runs
on a 1920 × 1080 photo: `decodePng` 104 ms (8-bit RGB), `decodeJpeg` 60 ms
(baseline 4:2:0) and 83 ms (progressive), `encodePng` 194 ms at level 1 (2.2
MB; 660 ms and 1.9 MB at level 6), `encodeSixel` at the full size 155 ms
dithered (1.8 MB) and 74 ms not, `sixelImage` into 160 × 45 cells of 10 × 20
(1600 × 900 pixels) 178 ms, `resize` to 160 × 90 12 ms, `BlockImage` of 160 ×
45 cells 16 ms in half blocks and 21 ms in quadrants.
