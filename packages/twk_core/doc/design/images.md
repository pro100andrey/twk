# twk_core design: §1.14 Images

[The design](README.md)

`Canvas.image(x, y, cols, rows, image)` reserves a rectangle of cells
(`kSkip`, which the diff never writes, erases or compares) and records
an `ImagePlacement` of a `TerminalImage(protocol, data, pixelWidth:,
pixelHeight:)` on the surface (`Surface.images`); the presenter writes it
in the protocol it was encoded for (`GraphicsProtocol.kitty`, `sixel`,
`iterm2`, or `none`), the terminal's (`TerminalCaps.graphics`). `data`
is the encoded image (`package:twk_rich/image.dart` makes it): a PNG file for
kitty, sent in base64 chunks of 4096 bytes; an image file for iTerm2;
for sixel the bytes between `ESC P` and `ESC \`, raster attributes
included, no taller than the cells. The image is drawn over blanks in
the cells' styles, so a background is filled first; the same
`TerminalImage` object across frames is the same image (a new object is
sent again), and a cell's size in pixels is `TerminalCaps.cellPixelWidth`
and `cellPixelHeight` (0 where the terminal told none).

* kitty: an image is sent once by id (`a=T`; again after a full frame,
  whose `ED 2` deletes it) and placed by a placement id, placed again
  after any scroll, `IL`/`DL` or commit that moves its cells, so it is
  where its cells are whether or not the terminal moved it; cut off by a
  clip, it shows the part left (its pixel size must cover its cells);
  drawn over, its placement is deleted, and an image no placement shows
  is freed. Handing the terminal back (exit, suspend) frees every image;
* sixel and iTerm2: their pixels belong to the cells, so no hardware
  scroll passes over them (recorded, declared and detected scrolls
  rewrite those rows instead) and they are sent again where they went;
  written between `DECSC` and `DECRC`, sixel with DEC mode 8452 and
  iTerm2 with `doNotMoveCursor=1`, so the cursor model holds; cut off by
  a clip, they are not shown (the cells stay blank); drawn over, they
  are dropped, their pixels left in the cells still reserved until they
  are painted again;
* a frame that writes images is a synchronized update; a frame without
  images does no work for them (`PresentStats.images` counts those a
  frame sent or placed again).

The protocol: `TerminalOptions.graphics`, else `TWK_GRAPHICS` (`kitty`,
`sixel`, `iterm2`, `none`), else what the probe finds ([§1.7](terminal.md)):
kitty's where it answers kitty's graphics query, iTerm2's where its name
(XTVERSION) or its environment says iTerm2 or WezTerm, sixel where DA1 lists
it. Inside tmux, which answers the queries itself, sixel is tmux's own
(3.4), and kitty's or iTerm2's go to the terminal outside through its
passthrough (`allow-passthrough on`) where the environment names one that
has it; inside GNU screen, none.
