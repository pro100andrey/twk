/// The stand-in for `branch_api.dart` in a baseline build: the core it is
/// built against lacks what that file uses (see there).
library;

import 'package:twk_core/twk_core.dart';

/// The baseline's [RenderParagraph] has no `ellipsis`.
const hasParagraphEllipsis = false;

/// A [RenderParagraph] of [spans] cut off at [maxLines] with the core's own
/// ellipsis; [ellipsis] is not used.
RenderParagraph cutParagraph(
  List<(String, Pen)> spans, {
  required int? maxLines,
  required String ellipsis,
}) => RenderParagraph(
  spans,
  overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
  maxLines: maxLines,
);

/// As the baseline's core has it, the style id an int: what [styles] holds of the style a cell of [Surface.styles] has, [raw]:
/// its colors and underline color as packed ints, its attributes and link.
({int fg, int bg, int attrs, int underline, String? link}) cellStyleOf(
  StyleTable styles,
  int raw,
) => (
  fg: styles.fgOf(raw).value,
  bg: styles.bgOf(raw).value,
  attrs: styles.attrsOf(raw),
  underline: styles.underlineColorOf(raw).value,
  link: styles.linkOf(raw),
);
