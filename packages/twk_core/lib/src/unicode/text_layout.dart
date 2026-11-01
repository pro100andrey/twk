// How text is laid out in a width, as the core names it: where a line stands
// across it ([TextAlign]) and how a cut is shown ([TextOverflow]). Plain
// enums with no dependency, so that the paragraph of `render/` and the
// string helpers of `unicode/` (`fitText`, `padCells`) take the same ones.

/// Where a `RenderParagraph` puts each line across its width. A line wider
/// than the paragraph starts at the edge its paragraph starts at: the left
/// one, or the right one for a right-to-left paragraph in visual order
/// (`TextOrder.visual`).
enum TextAlign {
  /// At the left.
  left,

  /// In the middle; the odd cell after the line.
  center,

  /// At the right.
  right,

  /// Stretched to the whole width: the cells it lacks are shared out after
  /// the spaces between its words, the odd ones to the first. The last
  /// line, a line the text breaks, a line with an ellipsis and a line
  /// without spaces stay at the start, as `start` places them.
  justify,

  /// At the edge its paragraph starts at: the left one, or in visual order
  /// (`TextOrder.visual`) the right one for a paragraph that runs right to
  /// left (its first strong character is, rules P2 and P3 of UAX #9).
  start,

  /// At the edge its paragraph ends at: the other one.
  end,
}

/// How a `RenderParagraph` shows that it cut text off: a line too long for
/// it (or `fitText`), or the lines beyond its `RenderParagraph.maxLines`.
enum TextOverflow {
  /// It doesn't: the text is cut off at the edge.
  clip,

  /// "…" in place of the end.
  ellipsis,

  /// "…" in place of the start: the end is kept.
  ellipsisStart,

  /// "…" in place of the middle: the start and the end are kept (paths,
  /// names).
  ellipsisMiddle,
}
