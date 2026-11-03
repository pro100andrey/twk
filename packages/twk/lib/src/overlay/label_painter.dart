/// A label a render object paints itself, as a `Text` would draw it:
/// [LabelPainter].
library;

import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        Canvas,
        ClusterScan,
        Pen,
        PipelineOwner,
        PipelineTextOrder,
        TextInvalidation,
        TextOrder,
        TextPainter,
        TextSegmenter,
        TextWrap;

/// One line of a user's label, kept by the render object that paints it: a
/// [TextPainter] of one line, uncut (the canvas's clip cuts it), made when
/// the label first paints and updated only when its text, its marks or its
/// pens change, and laid out again only then, or when the segmenter or the
/// owner's text order does. In visual order a right-to-left label is drawn
/// as it reads, with its marks in the same run, as a `Text` draws it.
///
/// Painting it again, the label unchanged, allocates nothing.
final class LabelPainter {
  /// A painter of no text; [set] gives it some.
  LabelPainter();

  final _painter = TextPainter(
    const [],
    wrap: TextWrap.none,
    maxLines: 1,
  );

  var _text = '';
  var _marks = const <int>[];
  var _markLength = 0;
  var _pen = const Pen();
  var _markPen = const Pen();
  // the segmenter the marks were split for
  (Object, int)? _markedFor;
  var _hasSpans = false;

  // what the last layout was for
  var _laid = false;
  TextOrder _laidOrder = TextOrder.logical;

  /// The columns of the label, as the last [layout] measured them.
  int get width => _painter.width;

  /// Sets what the painter draws: [text] in [pen], the pieces of it that
  /// start at [marks] (offsets in order, in UTF-16 code units) in
  /// [markPen]: [markLength] code units each, or the cluster there when it
  /// is 0, as [segmenter] splits them. A call that changes nothing costs
  /// nothing.
  void set(
    String text,
    Pen pen,
    TextSegmenter segmenter, {
    List<int> marks = const [],
    int markLength = 0,
    Pen? markPen,
  }) {
    final mark = markPen ?? pen;
    final key = marks.isEmpty
        ? null
        : (segmenter.mode, segmenter.ambiguousWidth);
    if (_hasSpans &&
        text == _text &&
        identical(marks, _marks) &&
        markLength == _markLength &&
        pen == _pen &&
        mark == _markPen &&
        key == _markedFor) {
      return;
    }
    _hasSpans = true;
    _text = text;
    _marks = marks;
    _markLength = markLength;
    _pen = pen;
    _markPen = mark;
    _markedFor = key;
    _painter.spans = _spans(segmenter);
  }

  List<(String, Pen)> _spans(TextSegmenter segmenter) {
    if (_marks.isEmpty) {
      return [(_text, _pen)];
    }
    final spans = <(String, Pen)>[];
    final scan = ClusterScan();
    var from = 0;
    for (final at in _marks) {
      if (at < from || at >= _text.length) {
        continue;
      }
      var end = at + _markLength;
      if (_markLength == 0) {
        segmenter.scan(_text, at, scan);
        end = scan.end;
      } else if (end > _text.length) {
        end = _text.length;
      }
      if (at > from) {
        spans.add((_text.substring(from, at), _pen));
      }
      spans.add((_text.substring(at, end), _markPen));
      from = end;
    }
    if (from < _text.length) {
      spans.add((_text.substring(from), _pen));
    }
    return spans;
  }

  /// Lays the label out, if its text, its marks, the segmenter or [order]
  /// changed since the last time; returns its [width].
  int layout(TextSegmenter segmenter, TextOrder order) {
    final changed = _painter.takeInvalidation() == TextInvalidation.layout;
    if (changed ||
        !_laid ||
        order != _laidOrder ||
        _painter.segmenterChanged(segmenter)) {
      _laid = true;
      _laidOrder = order;
      _painter.layout(
        const BoxConstraints(0, BoxConstraints.unbounded, 0, 1),
        segmenter: segmenter,
        order: order,
      );
    }
    return _painter.width;
  }

  /// Paints the label with its top left cell at ([x], [y]) of [canvas] for
  /// the tree of [owner], which gives the text order; laid out first if it
  /// must be.
  void paint(Canvas canvas, PipelineOwner? owner, int x, int y) {
    layout(canvas.segmenter, owner?.textOrder ?? TextOrder.logical);
    _painter.paint(canvas, x, y);
  }
}
