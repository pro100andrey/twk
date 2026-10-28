/// Colors mixed as the widgets' looks mix them: two theme colors
/// ([mixRgb]), two RGBs ([lerpRgb]), a color as an RGB ([rgbOf])
/// and a cell style taken towards a color ([shadeStyle]), as a barrier and
/// a shadow tint what they cover, and how two RGBs contrast
/// ([contrastRgb]). Internal: not exported.
library;

import 'dart:math' as math;

import 'package:twk_core/twk_core.dart' show Attr, Color, StyleTable;

/// [a] [k] of the way to [b] (`Color.lerp`), as the design mixes colors;
/// null where either is null or not RGB: a palette entry or the default
/// is what the terminal's theme makes it, which is not known here.
Color? mixRgb(Color? a, Color? b, double k) =>
    a != null && b != null && a.isRgb && b.isRgb ? Color.lerp(a, b, k) : null;

/// [a] [k] of the way to [b], each an RGB (`0xRRGGBB`), as `Color.lerp`
/// mixes them.
Color lerpRgb(int a, int b, double k) =>
    Color.lerp(rgbColor(a), rgbColor(b), k);

/// [rgb], an RGB (`0xRRGGBB`), as a [Color.rgb].
Color rgbColor(int rgb) =>
    Color.rgb(rgb >> 16 & 0xFF, rgb >> 8 & 0xFF, rgb & 0xFF);

/// [color] as an RGB (`0xRRGGBB`): its own, a palette entry's as [styles]
/// knows it ([StyleTable.paletteRgb]), [defaultRgb] for the default color.
int rgbOf(StyleTable styles, Color color, int defaultRgb) {
  if (color.isRgb) {
    return color.value & 0xFFFFFF;
  }
  return color.isDefault ? defaultRgb : styles.paletteRgb(color.index);
}

/// [style] with its background, its text color and the color of its
/// underline each taken [k] of the way to [to], an RGB; a default text
/// color the terminal has not told turns the text faint, a default
/// underline color stays the text's.
int shadeStyle(StyleTable styles, int style, int to, double k) {
  Color mix(int rgb) => lerpRgb(rgb, to, k);
  final bg = mix(
    rgbOf(styles, styles.bgOf(style), styles.defaultBackgroundRgb),
  );
  var fg = styles.fgOf(style);
  var attrs = styles.attrsOf(style);
  final fgRgb = styles.defaultForegroundRgb;
  if (fg.isDefault && fgRgb == null) {
    attrs |= Attr.dim;
  } else {
    fg = mix(rgbOf(styles, fg, fgRgb ?? 0));
  }
  var underline = styles.underlineColorOf(style);
  if (!underline.isDefault) {
    underline = mix(rgbOf(styles, underline, 0));
  }
  return styles.style(
    fg: fg,
    bg: bg,
    attrs: attrs,
    underlineColor: underline,
    link: styles.linkOf(style),
  );
}

/// The contrast of two RGBs (`0xRRGGBB`) as WCAG 2 has it: from 1 (the
/// same) to 21 (black on white); 4.5 is what body text needs.
double contrastRgb(int a, int b) {
  double channel(int c) {
    final v = c / 255;
    return v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4) as double;
  }

  double luminance(int rgb) =>
      0.2126 * channel(rgb >> 16 & 0xFF) +
      0.7152 * channel(rgb >> 8 & 0xFF) +
      0.0722 * channel(rgb & 0xFF);
  final (x, y) = (luminance(a), luminance(b));
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// The RGB (`0xRRGGBB`) of the palette color [index] as xterm shows it:
/// the 16 colors, the 6×6×6 cube from 16 and the greys from 232.
int xtermRgb(int index) {
  const sixteen = [
    0x000000, 0xcd0000, 0x00cd00, 0xcdcd00, 0x0000ee, 0xcd00cd, //
    0x00cdcd, 0xe5e5e5, 0x7f7f7f, 0xff0000, 0x00ff00, 0xffff00,
    0x5c5cff, 0xff00ff, 0x00ffff, 0xffffff,
  ];
  if (index < 16) {
    return sixteen[index];
  }
  if (index >= 232) {
    final v = 8 + 10 * (index - 232);
    return v << 16 | v << 8 | v;
  }
  int level(int i) => i == 0 ? 0 : 55 + 40 * i;
  final i = index - 16;
  return level(i ~/ 36) << 16 | level(i ~/ 6 % 6) << 8 | level(i % 6);
}
