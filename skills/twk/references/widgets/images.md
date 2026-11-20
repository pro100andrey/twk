<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Images

PNG, JPEG, GIF and APNG pictures, in the terminal’s graphics or in block characters.

[All widgets](../widgets.md)

## Image

A PNG, JPEG, GIF or APNG fitted to its cells; a GIF or APNG with frames plays on the app’s clock, each frame drawn as it comes, and kitty, which plays an animation itself, is sent all the frames once. A TickerMode that is off stands it on the frame it shows. Where the terminal has a graphics protocol (kitty, sixel, iTerm2) its pixels are placed over the cells (drawn: protocol); where it has none, or with forceBlocks, it is drawn in characters: half blocks, quadrants, sextants (Unicode 13), octants (Unicode 16), braille or plain ASCII. Left to detected, the default, it is sextants where the terminal is known to draw them itself (kitty, foot, Ghostty, WezTerm, Konsole, VTE and a few more) and half blocks elsewhere; TWK_IMAGE_BLOCKS names a mode for all images.

Package: `twk_rich`.

### Code

```dart
@override
Widget build(BuildContext context) => Image.file(
  'assets/lake.jpg', // 240 × 160 pixels
  width: 44,
  height: 12,
  // in blocks wherever it runs; without it the terminal's graphics
  // protocol where it has one: kitty, sixel or iTerm2
  forceBlocks: true,
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| picture | lake.jpg, logo.png, orbit.gif | lake.jpg |
| fit | contain, cover, fill, scaleDown | contain |
| alignment | center, topLeft, centerLeft, centerRight, bottomRight | center |
| drawn | detected, half, quadrant, sextant, octant, braille, ascii, protocol | detected |
| width | 8 cells to 80 cells | 44 |
| height | 3 rows to 30 rows | 12 |
