/// A row of spans that the mouse hits by parts, measured as the terminal
/// draws them: [HitRow], and [segmenterOf], what measures text where a
/// widget is built.
library;

import 'package:twk_core/twk_core.dart' show TextSegmenter, TextWrap;

import '../binding/app_binding.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../style/style.dart';
import 'widgets.dart';

/// What text is measured with where [context] is: the segmenter its
/// render objects are laid out with (`PipelineOwner.segmenter`), that of
/// the canvas they are painted on, so in the terminal's text mode and
/// ambiguous width. Called in a `LayoutBuilder`'s builder or after the
/// first build, the render object of [context] gives it; else the app's
/// owner does, and with neither one in graphemes, ambiguous characters
/// one column.
TextSegmenter segmenterOf(BuildContext context) =>
    context.findRenderObject()?.owner?.segmenter ??
    AppBinding.maybeOf(context)?.twkApp.owner.segmenter ??
    _detached;

final _detached = TextSegmenter();

/// One piece of a [HitRow]: `span`, a part of the target numbered
/// `target`, or of none with -1.
typedef HitSpan = ({Span span, int target});

/// A row of spans, the parts of numbered targets (the segments of a
/// control, the crumbs of a path, the pages of a pager), and where each
/// target is along it as it is drawn: the spans measured with the
/// segmenter the row is painted with ([segmenterOf]), so that a click or
/// the mouse over a column finds the target drawn there in any text mode
/// and ambiguous width.
///
/// A widget's state keeps one: its build makes the row ([row]), styling
/// the target the mouse is over ([hovered]) as it likes, and the tap it is
/// told of asks which target was hit ([at]).
final class HitRow {
  /// The target the mouse is over, as the last row's [row] was told; -1
  /// for none.
  var hovered = -1;

  /// The first column of each target and the one after its last, in
  /// pairs; -1 for a target not in the row.
  var _extents = const <int>[];

  /// The target at column [x] of the row as last built; -1 for none.
  int at(int x) {
    final e = _extents;
    for (var t = 0; t + 1 < e.length; t += 2) {
      if (x >= e[t] && x < e[t + 1]) {
        return t ~/ 2;
      }
    }
    return -1;
  }

  /// The first column of [target] in the row as last built; -1 where it is
  /// not in it.
  int startOf(int target) {
    final k = 2 * target;
    return target >= 0 && k < _extents.length ? _extents[k] : -1;
  }

  /// The columns the row as last built takes.
  int get width => _width;
  var _width = 0;

  /// [spans] on one row, in [style] under theirs, measured with
  /// [segmenter]: from here on [at] finds the targets where they are
  /// drawn. With [onHover] the mouse over the row sets [hovered] and calls
  /// [onHover] with it each time it changes: on the target it comes over,
  /// -1 between targets and when it leaves.
  Widget row(
    List<HitSpan> spans,
    TextSegmenter segmenter, {
    Style style = const Style(),
    void Function(int target)? onHover,
  }) {
    var targets = 0;
    for (final s in spans) {
      if (s.target >= targets) {
        targets = s.target + 1;
      }
    }
    final extents = List.filled(2 * targets, -1);
    var x = 0;
    for (final s in spans) {
      final w = segmenter.width(s.span.text);
      final t = s.target;
      if (t >= 0) {
        if (extents[2 * t] < 0) {
          extents[2 * t] = x;
        }
        extents[2 * t + 1] = x + w;
      }
      x += w;
    }
    _extents = extents;
    _width = x;
    final Widget text = Text.rich(
      [for (final s in spans) s.span],
      style: style,
      wrap: TextWrap.none,
      maxLines: 1,
    );
    if (onHover == null) {
      return text;
    }
    void hover(int target) {
      if (target != hovered) {
        hovered = target;
        onHover(target);
      }
    }

    return MouseRegion(
      onEnter: (event) => hover(at(event.x)),
      onHover: (event) => hover(at(event.x)),
      onExit: (_) => hover(-1),
      child: text,
    );
  }
}
