/// The stand-in for `branch_api.dart` in a baseline build: the core it is
/// built against lacks what that file uses (see there).
// cellStyleOf calls the baseline's core dynamically: its doc says why
// ignore_for_file: avoid_dynamic_calls
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

/// What [styles] holds of the style a cell of [Surface.styles] has, [raw]:
/// its colors and underline color as packed ints, its attributes and link.
///
/// The calls are dynamic: the baseline's core takes the id as an int, the
/// repository's, which this file is analyzed against, as a `StyleId`, and
/// a `StyleId` is that int at run time, so one call does for both.
({int fg, int bg, int attrs, int underline, String? link}) cellStyleOf(
  StyleTable styles,
  int raw,
) {
  final dynamic table = styles;
  return (
    fg: table.fgOf(raw).value as int,
    bg: table.bgOf(raw).value as int,
    attrs: table.attrsOf(raw) as int,
    underline: table.underlineColorOf(raw).value as int,
    link: table.linkOf(raw) as String?,
  );
}
