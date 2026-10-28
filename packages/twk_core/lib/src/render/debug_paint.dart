part of 'render.dart';

// ---------------------------------------------------------- debug paints --

// the debug paints of a PipelineOwner, as bits
const _debugRainbow = 1;
const _debugRelayout = 2;

/// The tints the debug paints cycle through: twelve hues round the colour
/// wheel.
const _debugTints = [
  Color.rgb(255, 0, 0),
  Color.rgb(255, 128, 0),
  Color.rgb(255, 255, 0),
  Color.rgb(128, 255, 0),
  Color.rgb(0, 255, 0),
  Color.rgb(0, 255, 128),
  Color.rgb(0, 255, 255),
  Color.rgb(0, 128, 255),
  Color.rgb(0, 0, 255),
  Color.rgb(128, 0, 255),
  Color.rgb(255, 0, 255),
  Color.rgb(255, 0, 128),
];

/// How much of a tint a repaint's cells take: enough to tell one hue from
/// the next, little enough to keep the text readable.
const _rainbowAlpha = 0x50;

/// How much of a tint an outline takes: more than a repaint's, to stand
/// out on it.
const _relayoutAlpha = 0xA0;

/// Blends the background of [tint], a pen with a translucent background
/// alone, over the background of the cells [x0, x1) × [y0, y1) of
/// [surface], keeping their glyphs, text colours and attributes; a
/// two-column glyph cut by either side is tinted whole, its halves keeping
/// one style.
void _tint(
  Surface surface,
  StyleTable styles,
  int tint,
  int x0,
  int y0,
  int x1,
  int y1,
) {
  final cells = surface.cells;
  final sty = surface.styles;
  final width = surface.width;
  for (var y = y0; y < y1; y++) {
    final row = y * width;
    var a = x0;
    var b = x1;
    if (a > 0 && (cells[row + a] & kCont) != 0) {
      a--;
    }
    if (b < width && (cells[row + b - 1] & kWide) != 0) {
      b++;
    }
    final end = row + b;
    for (var i = row + a; i < end;) {
      final s = sty[i];
      final j = runEndU32(sty, surface.styles64, i + 1, end, s);
      fillU32(sty, i, j, _tinted(styles, s, tint));
      i = j;
    }
    surface.markDirty(y, a, b);
  }
}

/// [style] with its background blended with [tint]'s, all else kept.
int _tinted(StyleTable styles, int style, int tint) => styles.style(
  fg: styles.fgOf(style),
  bg: styles.bgOf(styles.compose(style, tint)),
  attrs: styles.attrsOf(style),
  underlineColor: styles.underlineColorOf(style),
  link: styles.linkOf(style),
);

/// Has [o] and everything inside it count as not laid out since the
/// relayout highlight last looked ([PipelineOwner.debugRelayoutHighlight]).
void _forgetLayout(RenderObject o) => o
  .._laidOut = false
  ..visitChildren(_forgetLayout);
