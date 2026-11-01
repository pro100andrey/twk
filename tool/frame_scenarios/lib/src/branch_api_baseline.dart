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
