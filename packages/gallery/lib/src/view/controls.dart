// The inspector's controls (doc/design.md, "The inspector"): a segmented
// choice, the pill switch, twk's slider and colour swatches, and key
// hints.
import 'package:twk/twk.dart';

import '../paint.dart';
import 'tokens.dart';

/// Where a segment of a [segmented] choice is: at `x`, `y`, `w` cells,
/// the choice `i`.
typedef SegmentHit = ({int x, int y, int w, int i});

/// The segments of [labels] laid out from [x], [y] within [maxW]: side by
/// side, on to another row where the next does not fit.
List<SegmentHit> segmentsOf(int x, int y, int maxW, List<String> labels) {
  final hits = <SegmentHit>[];
  var cx = x;
  var cy = y;
  for (var i = 0; i < labels.length; i++) {
    final w = widthOf(labels[i]) + 2;
    if (cx > x && cx + w > x + maxW) {
      cx = x;
      cy++;
    }
    hits.add((x: cx, y: cy, w: w, i: i));
    cx += w;
  }
  return hits;
}

/// A segmented choice: [labels] side by side on a sunken track, the
/// chosen one ([index]) raised on the selection colour, filled with the
/// primary colour while [focused]; the highlight at [hx], [hw] of the
/// chosen one's row (gliding there). Returns the rows it took.
int segmented(
  Painter p,
  List<SegmentHit> hits,
  List<String> labels,
  int index,
  Tokens t, {
  required bool focused,
  required int hx,
  required int hw,
  bool disabled = false,
}) {
  final track = t.dark ? t.well : t.surface;
  final rows = <int, int>{};
  for (final h in hits) {
    final end = h.x + h.w;
    if ((rows[h.y] ?? 0) < end) {
      rows[h.y] = end;
    }
  }
  final x0 = hits.first.x;
  for (final MapEntry(key: ry, value: end) in rows.entries) {
    p.fill(x0, ry, end - x0, 1, Style(bg: track));
  }
  final chosen = hits[index.clamp(0, hits.length - 1)];
  if (disabled) {
    // the choices dim, the chosen one a little less, on a faded highlight
    p.bg(chosen.x, chosen.y, chosen.w, 1, t.lit(track, t.selection, 0.4));
    for (final h in hits) {
      final on = h.i == index;
      p.text(h.x + 1, h.y, labels[h.i], Style(fg: on ? t.muted : t.dim));
    }
    return hits.last.y - hits.first.y + 1;
  }
  p.bg(hx, chosen.y, hw, 1, focused ? t.primary : t.selection);
  for (final h in hits) {
    final on = h.i == index;
    final under = h.y == chosen.y && h.x >= hx && h.x + h.w <= hx + hw;
    final fg = on
        ? (focused ? t.onPrimary : t.text)
        : (under && focused ? t.onPrimary : t.muted);
    p.text(
      h.x + 1,
      h.y,
      labels[h.i],
      Style(fg: fg, attrs: on ? Attr.bold : 0),
    );
  }
  return hits.last.y - hits.first.y + 1;
}

/// twk's Switch as a pill, five cells, as twk draws it
/// ([Switch.pillSpans]): the knob [pos] of the way along (0 off, 1 on);
/// [under] is the background around it.
void toggle(
  Painter p,
  int x,
  int y,
  double pos,
  Tokens t, {
  required Color under,
  bool disabled = false,
}) {
  var cx = x;
  for (final span in Switch.pillSpans(t.theme, at: pos, enabled: !disabled)) {
    cx += p.text(cx, y, span.text, Style(bg: under).merge(span.style));
  }
}

const _left = ['', '▏', '▎', '▍', '▌', '▋', '▊', '▉', '█'];

/// twk's Slider, [w] cells: a light line, the thumb a cell wide [ratio] of
/// the way along in eighths of a cell, it and the line before it in the
/// text colour (primary while [focused]), the line after it muted.
void slider(
  Painter p,
  int x,
  int y,
  int w,
  double ratio,
  Tokens t, {
  required bool focused,
  bool disabled = false,
}) {
  final thumb = disabled
      ? t.muted
      : focused
      ? t.primary
      : t.text;
  final r = ratio.clamp(0.0, 1.0);
  final start = w > 1 ? (r * (w - 1) * 8).round() : 0;
  final end = start + 8;
  final after = (end + 7) >> 3;
  for (var i = 0; i < start >> 3; i++) {
    p.text(x + i, y, '─', Style(fg: thumb));
  }
  for (var i = after; i < w; i++) {
    p.text(x + i, y, '─', Style(fg: t.muted));
  }
  for (var i = start >> 3; i * 8 < end && i < w; i++) {
    final from = i * 8;
    final k = (end < from + 8 ? end : from + 8) - (start > from ? start : from);
    if (k == 8) {
      p.text(x + i, y, ' ', Style(fg: thumb, attrs: Attr.reverse));
    } else if (start > from) {
      p.text(x + i, y, _left[8 - k], Style(fg: thumb, attrs: Attr.reverse));
    } else {
      p.text(x + i, y, _left[k], Style(fg: thumb));
    }
  }
}

/// Colour swatches, two cells each a cell apart, the chosen one ([index])
/// marked under it.
void swatches(
  Painter p,
  int x,
  int y,
  List<Color> colors,
  int index,
  Tokens t, {
  required bool focused,
}) {
  for (var i = 0; i < colors.length; i++) {
    final sx = x + i * 3;
    p.text(sx, y, '██', Style(fg: colors[i]));
    if (i == index) {
      p.text(sx, y + 1, '▔▔', Style(fg: focused ? t.primary : t.text));
    }
  }
}

/// Key hints: each key bold, then what it does, muted, three blanks
/// between two; those that do not fit in [maxW] left out.
void keyHints(
  Painter p,
  int x,
  int y,
  int maxW,
  List<(String, String)> pairs,
  Tokens t,
) {
  var cx = x;
  final end = x + maxW;
  for (final (k, hint) in pairs) {
    final need = widthOf(k) + 1 + widthOf(hint);
    if (cx + need > end) {
      break;
    }
    cx += p.text(cx, y, k, Style(fg: t.text, attrs: Attr.bold));
    cx += p.text(cx, y, ' $hint', Style(fg: t.muted));
    cx += 3;
  }
}
