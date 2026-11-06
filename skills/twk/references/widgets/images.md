<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Images

PNG and JPEG pictures, in the terminal’s graphics or in block characters.

[All widgets](../widgets.md)

## Image

A PNG or JPEG fitted to its cells. Where the terminal has a graphics protocol (kitty, sixel, iTerm2) its pixels are placed over the cells; where it has none, or with forceBlocks, as here, it is drawn in half blocks or quadrants.

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
| picture | lake.jpg, logo.png | lake.jpg |
| fit | contain, cover, fill, scaleDown | contain |
| alignment | center, topLeft, centerLeft, centerRight, bottomRight | center |
| blocks | half, quadrant | half |
| width | 8 cells to 80 cells | 44 |
| height | 3 rows to 30 rows | 12 |
