/// A row of spans that the mouse hits by parts, found where the row's
/// paragraph draws them: [HitRow], and [segmenterOf], what measures text
/// where a widget is built.
library;

import 'package:twk_core/twk_core.dart'
    show RenderParagraph, TextOverflow, TextSegmenter, TextWrap;

import '../binding/app_binding.dart';
import '../focus/active_item.dart';
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
///
/// An app's own measuring and cutting (`fitText`, `stringWidth`'s kin) uses
/// it rather than a `TextSegmenter()`, which counts ambiguous letters one
/// column where the terminal may count two.
TextSegmenter segmenterOf(BuildContext context) =>
    context.findRenderObject()?.owner?.segmenter ??
    AppBinding.maybeOf(context)?.twkApp.owner.segmenter ??
    _detached;

final _detached = TextSegmenter();

/// One piece of a [HitRow]: `span`, a part of the target numbered
/// `target`, or of none with -1.
typedef HitSpan = ({Span span, int target});

/// The span of [spans], a text's as given, that the text at [offset] (in
/// UTF-16 code units into their texts joined, as a paragraph's
/// `cellAt` gives it) is of; -1 past their end. A paragraph splits the
/// spans it is given further (a gradient, a selection), never into other
/// text, so the offsets of its cells are those of the spans as given.
int spanIndexAt(List<Span> spans, int offset) {
  var at = 0;
  for (var i = 0; i < spans.length; i++) {
    at += spans[i].text.length;
    if (offset < at) {
      return i;
    }
  }
  return -1;
}

/// A row of spans, the parts of numbered targets (the segments of a
/// control, the crumbs of a path, the pages of a pager, the keys of a
/// bar), and which target the mouse is over where: the row's paragraph
/// says which text it drew at a column, as its last layout placed it, so
/// that a click finds the target drawn there whatever reorders or cuts
/// the row (right-to-left text in visual order, an ellipsis), in any text
/// mode and ambiguous width.
///
/// A widget's state keeps one: its build makes the row ([row]), styling
/// the target the mouse is over ([hovered]) as it likes, and the tap it is
/// told of asks which target was hit ([at]).
final class HitRow {
  /// The target the mouse is over, as the last row's [row] was told; -1
  /// for none.
  var hovered = -1;

  /// The pieces of the row as last built, and their spans, as its text
  /// was given them.
  var _pieces = const <HitSpan>[];
  var _spans = const <Span>[];

  /// The key of the row's text, which finds the paragraph it is drawn in.
  final GlobalKey _text = GlobalKey(debugLabel: 'HitRow');

  RenderParagraph? get _paragraph => switch (_text.currentContext) {
    final c? => c.findRenderObject() as RenderParagraph?,
    _ => null,
  };

  /// The target drawn at column [x] of the row as last laid out; -1 for
  /// none: between targets, beside the text, at an ellipsis (which stands
  /// for text it does not show), before the row is laid out.
  int at(int x) {
    final cell = _paragraph?.cellAt(x, 0);
    if (cell == null || cell.isEllipsis) {
      return -1;
    }
    final i = spanIndexAt(_spans, cell.start);
    return i < 0 ? -1 : _pieces[i].target;
  }

  /// The first column of [target] in the row as last laid out, the
  /// leftmost of its cells; -1 where it is not drawn (not in the row, cut
  /// off, under an ellipsis) or the row is not laid out.
  int startOf(int target) {
    final range = _rangeOf(target);
    if (range == null) {
      return -1;
    }
    return _paragraph?.columnsOf(range.$1, range.$2, 0)?.$1 ?? -1;
  }

  /// The text of [target] in the row as last built, from its first span's
  /// start to its last one's end, in UTF-16 code units; null where it has
  /// no span.
  (int, int)? _rangeOf(int target) {
    if (target < 0) {
      return null;
    }
    var at = 0;
    var start = -1;
    var end = -1;
    for (final (:span, target: t) in _pieces) {
      final next = at + span.text.length;
      if (t == target) {
        if (start < 0) {
          start = at;
        }
        end = next;
      }
      at = next;
    }
    return start < 0 ? null : (start, end);
  }

  /// [spans] on one row, in [style] under theirs, cut as [overflow] says
  /// where they do not fit (cut off by default): from its layout on, [at]
  /// finds the targets
  /// where they are drawn. With [onHover] the mouse over the row sets
  /// [hovered] and calls [onHover] with it each time it changes: on the
  /// target it comes over, -1 between targets and when it leaves. With
  /// [active], the target the keys of a focused row act on (-1 for none),
  /// the terminal's hidden cursor rests on its first cell as drawn
  /// ([ActiveItem.text]); a row whose keys move between its targets gives
  /// it at every build, -1 too, so that what it builds keeps its shape as
  /// the highlight comes and goes.
  Widget row(
    List<HitSpan> spans, {
    Style style = const Style(),
    TextOverflow overflow = TextOverflow.clip,
    void Function(int target)? onHover,
    int? active,
  }) {
    _pieces = spans;
    _spans = [for (final s in spans) s.span];
    Widget text = Text.rich(
      _spans,
      key: _text,
      style: style,
      wrap: TextWrap.none,
      overflow: overflow,
      maxLines: 1,
    );
    if (active != null) {
      // the hidden cursor on the active target
      text = ActiveItem(
        active: active >= 0,
        text: _rangeOf(active),
        child: text,
      );
    }
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
