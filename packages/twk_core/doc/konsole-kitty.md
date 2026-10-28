# Kitty graphics on Konsole: what twk sends against what Konsole does

Konsole answers kitty's graphics query (`a=q`) with `OK`, so the probe
(`lib/src/terminal/terminal.dart`) picks `GraphicsProtocol.kitty` there and
the presenter (`lib/src/presenter.dart`, `_presentImages`) sends its images
with `kittyPlace` and `kittyDelete` (`lib/src/graphics.dart`). This is what
Konsole does with each of them, read in its source at the version in use
(`konsole --version`: 26.08.2, tag `v26.08.2` of
invent.kde.org/utilities/konsole): `src/Vt102Emulation.cpp`
(`apc_put`, `processGraphicsToken`), `src/Screen.cpp` (`addPlacement`,
`scrollUp`, `scrollDown`, `delPlacements`, `clearEntireScreen`) and
`src/terminalDisplay/TerminalPainter.cpp` (`drawImagesBelowText`,
`drawImagesAboveText`).

## What twk sends

| command | bytes |
|---|---|
| probe | `ESC _G i=31,s=1,v=1,a=q,t=d,f=24;AAAA ESC \` |
| an image sent and placed | `a=T,f=100,t=d,i=<id>,p=<placement>,c=<cols>,r=<rows>[,x,y,w,h],C=1,q=2` then the PNG in base64, in chunks of 4096 characters: `m=1` on all but the last, `m=0` on the last, the keys on the first only |
| placed again (moved, scrolled) | `a=p,i=<id>,p=<placement>,c,r[,x,y,w,h],C=1,q=2` |
| one placement taken away | `a=d,d=i,i=<id>,p=<placement>,q=2` |
| an image taken away | `a=d,d=I,i=<id>,q=2` |

Never sent: other media (`t=f`, `t=t`, `t=s`), raw pixels (`f=24`, `f=32`)
outside the probe, compression (`o=z`), image numbers (`I`), z-index (`z`),
cell offsets (`X`, `Y`), unicode placeholders (`U=1`), relative placements
(`P`, `Q`), animation (`a=f`, `a=a`, `a=c`) and the other deletions.

## Against Konsole

| key or action | twk | Konsole 26.08.2 | on screen |
|---|---|---|---|
| query `a=q` | `t=d,f=24`, 1 x 1 | decodes it, answers `ESC _G i=31;OK ESC \` | as kitty |
| medium `t` | `d` only | `d`; others answer `ENOTSUPPORTED` (with `q=2` the path would be read as data) | as kitty |
| format `f` | `100` (PNG) | `QPixmap::loadFromData`; also 24 and 32 | as kitty |
| compression `o` | none | `z` by `qUncompress` | — |
| chunks `m` | 4096 base64 characters (a multiple of 4), keys on the first | keeps the first chunk's keys (`savedKeys`), decodes base64 four characters at a time as they arrive | as kitty |
| quiet `q` | `2` | `2` answers nothing, errors included | as kitty |
| id `i`, placement `p` | both, `p` ≥ 1 | a placement of the same `i` and `p` replaces the one before (`Screen::addPlacement`) | as kitty |
| size in cells `c`, `r` | both, always | scales the (cropped) image to `c` x `r` cells of its font, aspect ignored, nearest pixel (`Qt::FastTransformation`) | as kitty; `package:twk_rich/image.dart` scales to the cells first, so it is close to 1:1 |
| crop `x`, `y`, `w`, `h` | where a clip cuts the image | `QPixmap::copy` of that rectangle | as kitty |
| cursor `C` | `1` | `C=1` leaves the cursor where it is; without it, Konsole moves it right of the image or below, scrolling | as kitty |
| z-index `z` | none (0) | drawn over the text from `z` ≥ 0, below it under 0 | as kitty |
| offsets `X`, `Y` | none | pixel offsets in the cell | — |
| unicode placeholders `U` | none | not implemented | — |
| delete `a=d,d=i` / `d=I` | by id, and placement | takes the placements away (lower and upper case alike) | as kitty |
| image data after `d=I` | expected freed | **kept** in `_graphicsImages` until a reset (RIS) or an image sent under the same id | memory: every image ever sent stays in Konsole |
| ED 2 | before a full repaint | takes away the placements on the screen (`delPlacements('a')`), keeps the data | as kitty, but the data stays |
| text printed or erased over an image | the presenter takes the image away itself | kitty placements stay (sixel and iTerm2 ones go) | as kitty |
| scroll up: SU, DL, a line feed at the bottom margin | DECSTBM + SU over the scrolled rows (fullscreen), DL and IL (inline); the images in those rows placed again | **every** placement moves up, those outside the scrolled rows and margins too (`Screen::scrollUp(from, n)` calls `scrollPlacements(n)` for the whole screen) | **wrong**: an image beside a scrolled list (a header's, a sidebar's) climbs a row per line scrolled and goes off the top |
| scroll down: SD, IL, a reverse index | as above | **no** placement moves (`Screen::scrollDown` leaves them) | the presenter places those in the rows again anyway: right |
| alternate screen | images on it | placements per screen; entering clears them | as kitty |

The same scroll applies to Konsole's sixel and iTerm2 images, which twk
sends there only when `TWK_GRAPHICS` says so: a scroll up of other rows
moves them too.

## What twk does about it

A capability, `TerminalCaps.konsoleImages`, set by the probe where the
terminal is Konsole (its XTVERSION, `Konsole 26.08.2`, or else
`KONSOLE_VERSION`; not inside a multiplexer), as `konsoleLines` is for its
line model. With it the presenter:

- places every kitty image again after a scroll of any rows
  (`_imagesMoved`), not only those in the scrolled rows: one `a=p` each,
  in the same synchronized update (Konsole has DEC mode 2026), so the
  image never shows where Konsole moved it;
- scrolls no rows in hardware while it shows a sixel or iTerm2 image
  (`_scrollsImage`): the rows are written instead;
- gives a new kitty image the id of one it deleted (`_freeImageIds`), so
  that Konsole replaces that image's data instead of keeping it: Konsole
  then holds as many images as twk showed at once at most, not every one
  it ever showed.

The test emulator models Konsole's images (`Vt(konsoleImages: true)`,
`packages/twk_test/lib/vt.dart`): a scroll up moves every image up, a
scroll down none, a deletion keeps the data. The tests are
`test/graphics/konsole_images_test.dart` (each with the capability off,
which shows Konsole's move), the Konsole cases of
`test/graphics/graphics_fuzz_test.dart`, and
`packages/twk_test/test/vt_konsole_images_test.dart` for the emulator.

## Seeing it in Konsole

```sh
cd packages/twk_rich
dart run example/image/konsole_images.dart
```

A blue header with a picture at its left, 8 x 4 cells: a gradient in a
white frame crossed by a white diagonal, and beside it
`graphics=kitty konsoleImages=true`. Below, a log scrolls up a line every
0.12 s for 40 lines, then down for 10; then the picture changes colour 12
times. The picture stays in the header, whole and framed, the whole time;
without the capability it climbed a row with each line scrolled up and was
gone off the top after five. The app ends by itself ten seconds
later, or at a key.
