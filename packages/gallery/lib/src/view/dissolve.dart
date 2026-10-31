// A new page materialises: its backgrounds at once, its glyphs each from a
// time of its own, fading in from the background (the design's dissolve).
import 'dart:math' as math;

import 'package:twk/twk.dart';

import '../motion.dart';

/// The design's page transition over an [Effect]'s child: in 300 ms each
/// cell's glyph comes in at a time of its own, its color from the
/// background's; the backgrounds are there at once, so the layout does not
/// flicker. [serial] tells one run from the next: an effect of another
/// serial runs again; serial 0 is the gallery as it opens, none.
final class PageDissolve extends CellEffect {
  const PageDissolve(this.serial);

  final int serial;

  static const int _attrsGone =
      Attr.underlineMask | Attr.strike | Attr.overline | Attr.reverse;

  /// None at first: the gallery opens without one.
  @override
  Duration get duration =>
      serial == 0 ? Duration.zero : const Duration(milliseconds: 300);

  @override
  CellFilter? at(Duration elapsed) {
    final k = serial == 0
        ? 1
        : elapsed.inMicroseconds / duration.inMicroseconds;
    if (k >= 1) {
      return null;
    }
    final made = <int, int>{};
    return (cell) {
      final local = (k - _hash(cell.x, cell.y) * 0.6) / 0.4;
      if (local >= 1) {
        return;
      }
      final styles = cell.styles;
      final s = cell.style;
      if (local <= 0) {
        cell
          ..glyph = 0x20
          ..style = made[-s - 1] ??= styles.style(
            fg: styles.fgOf(s),
            bg: styles.bgOf(s),
            attrs: styles.attrsOf(s) & ~_attrsGone,
          );
        return;
      }
      // the palette's and the default colors as the terminal shows them
      // (StyleTable.rgbOf), so that the terminal's own colors fade too; a
      // default text color it has not told comes in at once
      final fg = _rgb(styles.rgbOf(styles.fgOf(s), text: true));
      final bg = _rgb(styles.rgbOf(styles.bgOf(s)));
      if (fg == null || bg == null) {
        return;
      }
      final step = (easeOut(local) * 16).round();
      cell.style = made[s * 17 + step] ??= styles.style(
        fg: Color.lerp(bg, fg, step / 16),
        bg: bg,
        attrs: styles.attrsOf(s),
        underlineColor: styles.underlineColorOf(s),
      );
    };
  }

  static Color? _rgb(int? v) =>
      v == null ? null : Color.rgb(v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF);

  /// A number from 0 to 1 that looks random and is the same for a cell.
  static double _hash(int x, int y) {
    final s = math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
    return s - s.floorToDouble();
  }

  @override
  bool operator ==(Object other) =>
      other is PageDissolve && other.serial == serial;

  @override
  int get hashCode => serial.hashCode;
}
