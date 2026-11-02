/// What the scenarios use that an older core may lack, in one place: a
/// baseline build of the benchmark (`tool/bench.dart --baseline=REF`)
/// replaces this file with `branch_api_baseline.dart`, which says the core
/// of REF has none of it, and the scenarios that need it drop out of that
/// build.
library;

import 'package:twk_core/twk_core.dart';

/// Whether [RenderParagraph] takes the `ellipsis` it cuts with.
const hasParagraphEllipsis = true;

/// A [RenderParagraph] of [spans] cut off with [ellipsis] at [maxLines].
RenderParagraph cutParagraph(
  List<(String, Pen)> spans, {
  required int? maxLines,
  required String ellipsis,
}) => RenderParagraph(
  spans,
  overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
  maxLines: maxLines,
  ellipsis: ellipsis,
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
