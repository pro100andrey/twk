/// The thumb of a `Scrollbar` and of a `Slider`, placed on its track in
/// eighths of a cell, for a painter of an app's own too: [thumbSteps] and
/// [paintThumb].
library;

import 'package:twk_core/twk_core.dart' show Attr, Canvas;

import '../data/chart_glyphs.dart';
import '../style/style.dart';

// Examples can assume:
// late int offset;
// late int content;

/// The glyphs [thumbSteps] and [paintThumb] measure, again only when a
/// canvas's segmenter settings change.
final _glyphs = ChartGlyphs();

/// The steps of a cell that a thumb is placed in along a track of
/// [canvas], [vertical] or not: 8 where the canvas draws block elements
/// one column wide, else 1, whole cells, where it draws them two columns
/// wide (they are East Asian ambiguous). [paintThumb] takes the thumb's
/// start and end in these steps.
int thumbSteps(Canvas canvas, {required bool vertical}) {
  final g = _glyphs..use(canvas.segmenter);
  return (vertical ? g.upSteps : g.acrossSteps) == 8 ? 8 : 1;
}

/// Paints the cells of a track of [canvas] that a thumb from [start] to
/// [end] covers, in steps of [steps] a cell ([thumbSteps]) from the top
/// of the canvas when [vertical], else from its left; the track
/// [thickness] cells across from [at]. [style]'s foreground is the
/// thumb's color and its background the track's, the cells' own where
/// it has none. A cell the thumb covers whole is [glyph] in [style], or
/// without one a blank in the reverse of [style]; one it covers in part
/// a block element, as long as the part (`▃`, `▌`). Only the thumb's
/// cells are painted: the track is the caller's to fill first.
///
/// A [glyph] narrower than its cell, a half block (`▐`, `0x2590`) for a
/// slim thumb, goes with [steps] of 1, as the eighths of a cell covered
/// in part are of a whole cell across.
///
/// A thumb on the last column of a painter, for a window of its `height`
/// rows on `content` rows scrolled `offset` down, in eighths where the
/// canvas allows:
///
/// ```dart
/// final class Bar extends CellPainter {
///   @override
///   void paint(Canvas canvas, int width, int height) {
///     final steps = thumbSteps(canvas, vertical: true);
///     final all = height * steps;
///     final size = (all * height / content).round().clamp(steps, all);
///     final start = ((all - size) * offset / (content - height)).round();
///     paintThumb(
///       canvas,
///       const Style(fg: Color.cyan),
///       start: start,
///       end: start + size,
///       steps: steps,
///       vertical: true,
///       at: width - 1,
///     );
///   }
///
///   @override
///   bool shouldRepaint(Bar oldDelegate) => true;
/// }
/// ```
///
/// See also:
///
///  * `Scrollbar`, the track and thumb of a scrollable, dragged too.
void paintThumb(
  Canvas canvas,
  Style style, {
  required int start,
  required int end,
  required int steps,
  required bool vertical,
  int at = 0,
  int thickness = 1,
  int? glyph,
}) {
  final glyphs = _glyphs..use(canvas.segmenter);
  final pen = style.penIn(canvas.styles);
  final reversed = style
      .merge(const Style(attrs: Attr.reverse))
      .penIn(canvas.styles);
  for (var i = start ~/ steps; i * steps < end; i++) {
    final from = i * steps;
    final to = from + steps;
    // the steps of the cell the thumb covers: all of them, those at its
    // end where the thumb starts, those at its start where it ends; a
    // block of the thumb's color, or of the track's on the thumb's
    final k = (end < to ? end : to) - (start > from ? start : from);
    final (cp, p) = k == steps
        ? (glyph == null ? (0x20, reversed) : (glyph, pen))
        : start > from
        ? (vertical
              ? (glyphs.up(k), pen)
              : (glyphs.across(steps - k), reversed))
        : (vertical
              ? (glyphs.up(steps - k), reversed)
              : (glyphs.across(k), pen));
    if (vertical) {
      canvas.fill(at, i, thickness, 1, p, cp);
    } else {
      canvas.fill(i, at, 1, thickness, p, cp);
    }
  }
}
