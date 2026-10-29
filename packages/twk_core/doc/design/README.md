# twk_core: design

How the core is built and why, how it is tested, what it does not do,
and how its demo, end to end runs and benchmark are run. The package's
[README](../../README.md) is the short version.

## What it is

A terminal UI core with no runtime dependencies (only `dart:*`): a packed
cell buffer, a diff driven by damaged spans, a minimal ANSI stream, its own
Unicode segmentation, an input parser, backends for Linux / macOS / Windows,
and a retained render tree, under the Flutter-like widget layer of
[`packages/twk`](../../../twk/doc/reference/README.md), the rich text of
[`packages/twk_rich`](../../../twk_rich/README.md) and the console for
command-line tools of [`packages/twk_cli`](../../../twk_cli/README.md).

Key properties:

* a frame with no changes costs **0 bytes**; a retained repaint touches only
  the cells that changed, and the presenter compares only damaged spans;
* cells are typed arrays, styles and glyphs are interned, so the hot path
  allocates next to nothing;
* atomic frames (DEC 2026), hardware scrolling (`DECSTBM + SU/SD`, DECSLRM),
  character insert/delete (ICH/DCH), `REP`, `ECH`/`EL`;
* when a terminal disagrees about a character's width, the error **never
  leaves the cells of that glyph**;
* three screen modes: fullscreen on the alternate screen; **inline**, a
  region of the normal screen under the terminal's history that grows with
  its content and never writes above itself ([§1.12](inline.md)); and a **fixed
  viewport**, a rectangle of the screen outside which nothing is written
  ([§1.13](viewport.md));
* images in reserved cells, placed with kitty graphics, sixel or iTerm2
  as the terminal shows them ([§1.14](images.md));
* where the output is no terminal (piped, in CI), **plain text**: no
  escape sequences, the last frame written as lines when the app ends
  ([§1.7](terminal.md));
* a `Terminal` over any byte link (`TerminalLink`), and a build for the
  web with dart2wasm, where xterm.js is the terminal ([§1.7](terminal.md)).

This is `packages/twk_core` of the twk repository: the packages built on
it, and the repository's tools and checks, are in [its
README](../../../../README.md). Paths here are this package's (`lib/`, `test/`,
`example/`); `tool/…` is the repository root's `tool/` (`../../tool/`) and
`packages/…` a package of the repository, and the commands of [§4](running.md) run from
the root.

## §1 Design

```
lib/src/
  unicode/        UAX #29 grapheme segmentation + widths, UAX #9
                  bidirectional text (tables from UCD 18.0)
  style.dart      colors, attributes, pens, style interning, SGR transitions
  surface.dart    cell grid + damage tracking + glyph interning
  canvas.dart     drawing: clip/translate, text, fills, glyph runs,
                  lines merged where they meet, images
  graphics.dart   images: the protocols, an encoded image, its placement
  presenter.dart  diff + minimal ANSI stream; images placed
  fill.dart       block fills and comparisons of typed arrays
  input/          input parser (state machine)
  terminal/       the terminal over a byte link: stdio, a terminal served
                  over a local socket (twk shell), plain output, any link
                  of the caller's; termios (libc) and Windows console
                  (kernel32) through dart:ffi
  platform/       dart:io and dart:ffi behind one conditional import,
                  with stand-ins for the web
  render/         retained render tree (Flutter-like): layout, paint,
                  hit testing, boxes, borders, flex, stacks, grids,
                  wraps, paragraphs, scrolling viewports, lazy lists,
                  effects
  app.dart        frame loop: input → layout/paint → present → write
  headless.dart   in-memory terminal backend, render tree → string
  log.dart        log sink: print, log() and uncaught errors while the UI
                  owns the screen; served on a local socket (twk logs)
```

The libraries of `lib/src` are in layers, each importing only its own and
those below it (`test/layers_test.dart` fails on any other edge): unicode ←
draw (cells, styles, the presenter, input; no `dart:io`) ← platform (the
only one with `dart:io` and `dart:ffi`) ← log ← render | terminal, which
don't import each other, ← app. Two public libraries sit on them:
`package:twk_core/twk_core.dart`, the whole core, and
`package:twk_core/terminal.dart`, the terminal without the render tree and
the app, for a logger, a prompt or a command-line tool that writes lines
and reads keys: `Terminal` and what it is opened with and says it is,
`colorModeFor`, `plainAsked` and `runsInCi`, styles and colours, the
`LineEncoder`, the input parser and its events, widths, the terminal's own
sequences and the log sink. Its names are `twk_core.dart`'s own
declarations, so a program may import both. A program importing it
compiles (`dart compile kernel`, median of seven runs) in 0.40 s to a
9.7 MB kernel, against 0.57 s and 11.2 MB for `twk_core.dart` and 0.26 s
and 8.6 MB for a program importing nothing.

## The pages

- [§1.1 A cell is two 32-bit words; §1.2 Styles and pens; §1.3 Damage
  without help from widgets](canvas.md)
- [§1.4 Presenter (diff → bytes)](presenter.md)
- [§1.5 Unicode and uncertain widths](unicode.md)
- [§1.6 Input](input.md)
- [§1.7 Terminal and platforms](terminal.md)
- [§1.8 Flutter-like layer](render.md)
- [§1.9 Fills: `setRange` instead of `fillRange`; §1.10 Text fast
  paths](fast-paths.md)
- [§1.11 Techniques for components](components.md)
- [§1.12 Inline mode](inline.md)
- [§1.13 Fixed viewport](viewport.md)
- [§1.14 Images](images.md)
- [§2 Testing](testing.md)
- [§3 Limitations](limitations.md)
- [§4 Running](running.md)

## §5 License

MIT, copyright 2026 Andrii Ivanov: [LICENSE](../../LICENSE). The third-party
material bundled here keeps its own licence, listed in [NOTICE](../../NOTICE):
the Unicode data the segmentation, width and bidi tables come from
(`lib/src/unicode/tables.g.dart` and `lib/src/unicode/bidi_data.g.dart`,
which `tool/gen_unicode.dart` writes with the licence in their headers,
and `test/data/GraphemeBreakTest.txt`), under the Unicode License v3. The
repository's [NOTICE](../../../../NOTICE) lists it with that of the other
packages.
