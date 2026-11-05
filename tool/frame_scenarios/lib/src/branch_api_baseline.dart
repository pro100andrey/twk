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
/// a `StyleId` is that int at run time, so one call does for both. A
/// [Color] is its packed int at run time too, so a color comes back as the
/// int itself: its `value` is an extension member, which a dynamic call
/// does not find.
({int fg, int bg, int attrs, int underline, String? link}) cellStyleOf(
  StyleTable styles,
  int raw,
) {
  final dynamic table = styles;
  return (
    fg: table.fgOf(raw) as int,
    bg: table.bgOf(raw) as int,
    attrs: table.attrsOf(raw) as int,
    underline: table.underlineColorOf(raw) as int,
    link: table.linkOf(raw) as String?,
  );
}

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
