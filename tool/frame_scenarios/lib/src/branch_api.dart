/// What the scenarios use that an older core may lack, in one place: a
/// baseline build of the benchmark (`tool/bench.dart --baseline=REF`)
/// replaces this file with `branch_api_baseline.dart`, which says the core
/// of REF has none of it, and the scenarios that need it drop out of that
/// build.
library;

import 'package:twk_core/twk_core.dart';

/// Whether [RenderParagraph] takes the `ellipsis` it cuts with.
const hasParagraphEllipsis = true;

/// Whether [RenderParagraph] takes `keepsPaint`.
const hasKeepsPaint = true;

/// A [RenderParagraph] of [spans] cut off with [ellipsis] at [maxLines],
/// keeping its paint when [keepsPaint].
RenderParagraph cutParagraph(
  List<(String, Pen)> spans, {
  required int? maxLines,
  required String ellipsis,
  bool keepsPaint = false,
}) => RenderParagraph(
  spans,
  overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
  maxLines: maxLines,
  ellipsis: ellipsis,
  keepsPaint: keepsPaint,
);

/// What [styles] holds of the style a cell of [Surface.styles] has, [raw]:
/// its colors and underline color as packed ints, its attributes and link.
({int fg, int bg, int attrs, int underline, String? link}) cellStyleOf(
  StyleTable styles,
  int raw,
) => (
  fg: styles.fgOf(StyleId(raw)).value,
  bg: styles.bgOf(StyleId(raw)).value,
  attrs: styles.attrsOf(StyleId(raw)),
  underline: styles.underlineColorOf(StyleId(raw)).value,
  link: styles.linkOf(StyleId(raw)),
);

/// Constraints of up to [width] × [height] cells, on a core whose
/// constructor takes its bounds by name or, an older one, by position: the
/// call is dynamic, so that this file builds against both.
BoxConstraints constraintsUpTo(int width, int height) {
  const Function make = BoxConstraints.new;
  try {
    return Function.apply(make, const [], {#maxW: width, #maxH: height})
        as BoxConstraints;
    // the only way to tell a core by its constructor
    // ignore: avoid_catching_errors
  } on NoSuchMethodError {
    return Function.apply(make, [0, width, 0, height]) as BoxConstraints;
  }
}
