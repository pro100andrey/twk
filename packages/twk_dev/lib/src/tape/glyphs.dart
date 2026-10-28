/// The characters an SVG of a screen draws as shapes, not text, so that
/// they meet those of the next cell and the next row as a terminal draws
/// them: box-drawing lines and block elements.
library;

/// A box-drawing character's arms from the middle of its cell to the
/// middle of each side, each 0 for none, 1 light or 2 heavy; `round` for
/// a light corner drawn as an arc (`╭`).
typedef BoxArms = ({int up, int right, int down, int left, bool round});

/// The arms of box-drawing character [rune], null for one drawn as text
/// (double and dashed lines, mixed corners).
BoxArms? boxArms(int rune) {
  final code = _box[rune];
  if (code == null) {
    return null;
  }
  return (
    up: code >> 12,
    right: (code >> 8) & 0xf,
    down: (code >> 4) & 0xf,
    left: code & 0xf,
    round: rune >= 0x256d && rune <= 0x2570,
  );
}

/// A block element's parts: rectangles in eighths of a cell (left, top,
/// right, bottom), filled at `opacity` (a shade, `░`, is a fourth).
typedef Block = ({List<(int, int, int, int)> rects, double opacity});

/// The parts of block element [rune], null for another character.
Block? block(int rune) {
  if (rune < 0x2580 || rune > 0x259f) {
    return null;
  }
  const quadrants = {
    0x2596: [_ll],
    0x2597: [_lr],
    0x2598: [_ul],
    0x2599: [_ul, _ll, _lr],
    0x259a: [_ul, _lr],
    0x259b: [_ul, _ur, _ll],
    0x259c: [_ul, _ur, _lr],
    0x259d: [_ur],
    0x259e: [_ur, _ll],
    0x259f: [_ur, _ll, _lr],
  };
  if (quadrants[rune] case final rects?) {
    return (rects: rects, opacity: 1);
  }
  final rect = switch (rune) {
    0x2580 => (0, 0, 8, 4),
    // lower eighths: ▁ to ▇, and █
    <= 0x2588 => (0, 8 - (rune - 0x2580), 8, 8),
    // left eighths: ▉ to ▏
    <= 0x258f => (0, 0, 8 - (rune - 0x2588), 8),
    0x2590 => (4, 0, 8, 8),
    0x2594 => (0, 0, 8, 1),
    0x2595 => (7, 0, 8, 8),
    _ => (0, 0, 8, 8),
  };
  final opacity = switch (rune) {
    0x2591 => 0.25,
    0x2592 => 0.5,
    0x2593 => 0.75,
    _ => 1.0,
  };
  return (rects: [rect], opacity: opacity);
}

const _ul = (0, 0, 4, 4);
const _ur = (4, 0, 8, 4);
const _ll = (0, 4, 4, 8);
const _lr = (4, 4, 8, 8);

/// The arms of the box-drawing characters drawn as lines, a hex digit
/// each: up, right, down, left.
const _box = {
  // light: ─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼
  0x2500: 0x0101, 0x2502: 0x1010, 0x250c: 0x0110, 0x2510: 0x0011, //
  0x2514: 0x1100, 0x2518: 0x1001, 0x251c: 0x1110, 0x2524: 0x1011,
  0x252c: 0x0111, 0x2534: 0x1101, 0x253c: 0x1111,
  // heavy: ━ ┃ ┏ ┓ ┗ ┛ ┣ ┫ ┳ ┻ ╋
  0x2501: 0x0202, 0x2503: 0x2020, 0x250f: 0x0220, 0x2513: 0x0022,
  0x2517: 0x2200, 0x251b: 0x2002, 0x2523: 0x2220, 0x252b: 0x2022,
  0x2533: 0x0222, 0x253b: 0x2202, 0x254b: 0x2222,
  // rounded: ╭ ╮ ╯ ╰
  0x256d: 0x0110, 0x256e: 0x0011, 0x256f: 0x1001, 0x2570: 0x1100,
  // halves: ╴ ╵ ╶ ╷ ╸ ╹ ╺ ╻ ╼ ╽ ╾ ╿
  0x2574: 0x0001, 0x2575: 0x1000, 0x2576: 0x0100, 0x2577: 0x0010,
  0x2578: 0x0002, 0x2579: 0x2000, 0x257a: 0x0200, 0x257b: 0x0020,
  0x257c: 0x0201, 0x257d: 0x1020, 0x257e: 0x0102, 0x257f: 0x2010,
};
