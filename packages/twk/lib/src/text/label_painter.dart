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
        TextOverflow,
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
  // what is laid out of it: the text one line ([_oneLine])
  var _shown = '';
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
  int? _laidRoom;
  var _laidEllipsis = '\u2026';

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
    _shown = _oneLine(text);
    _marks = marks;
    _markLength = markLength;
    _pen = pen;
    _markPen = mark;
    _markedFor = key;
    _painter.spans = _spans(segmenter);
  }

  List<(String, Pen)> _spans(TextSegmenter segmenter) {
    final text = _shown;
    if (_marks.isEmpty) {
      return [(text, _pen)];
    }
    final spans = <(String, Pen)>[];
    final scan = ClusterScan();
    var from = 0;
    for (final at in _marks) {
      if (at < from || at >= text.length) {
        continue;
      }
      var end = at + _markLength;
      if (_markLength == 0) {
        segmenter.scan(text, at, scan);
        end = scan.end;
      } else if (end > text.length) {
        end = text.length;
      }
      if (at > from) {
        spans.add((text.substring(from, at), _pen));
      }
      spans.add((text.substring(at, end), _markPen));
      from = end;
    }
    if (from < text.length) {
      spans.add((text.substring(from), _pen));
    }
    return spans;
  }

  /// Lays the label out, if its text, its marks, the segmenter, [order],
  /// [room] or [ellipsis] changed since the last time; returns its [width].
  ///
  /// With a [room] (in columns) the label is cut to it at its end, as a
  /// `Text` with `TextOverflow.ellipsis` cuts it: with [ellipsis] where that
  /// fits in the room, plainly where it does not. Without, it is laid out
  /// uncut, and the canvas's clip cuts it.
  int layout(
    TextSegmenter segmenter,
    TextOrder order, {
    int? room,
    String ellipsis = '\u2026',
  }) {
    final changed = _painter.takeInvalidation() == TextInvalidation.layout;
    if (changed ||
        !_laid ||
        order != _laidOrder ||
        room != _laidRoom ||
        ellipsis != _laidEllipsis ||
        _painter.segmenterChanged(segmenter)) {
      _laid = true;
      _laidOrder = order;
      _laidRoom = room;
      _laidEllipsis = ellipsis;
      if (room != null) {
        _painter
          ..ellipsis = ellipsis
          ..overflow = segmenter.width(ellipsis) <= room
              ? TextOverflow.ellipsis
              : TextOverflow.clip;
      } else if (_painter.overflow != TextOverflow.clip) {
        _painter.overflow = TextOverflow.clip;
      }
      _painter.layout(
        BoxConstraints(
          maxW: room == null ? BoxConstraints.unbounded : (room < 0 ? 0 : room),
          maxH: 1,
        ),
        segmenter: segmenter,
        order: order,
      );
    }
    return _painter.width;
  }

  /// Paints [text] in [pen] at ([x], [y]) as [set] and [paint] do, and
  /// returns the columns it takes: a `Canvas.text` that draws a user's text
  /// as a `Text` does.
  int draw(
    Canvas canvas,
    PipelineOwner? owner,
    int x,
    int y,
    String text,
    Pen pen, {
    int? room,
    String ellipsis = '\u2026',
  }) {
    set(text, pen, canvas.segmenter);
    paint(canvas, owner, x, y, room: room, ellipsis: ellipsis);
    return _painter.width;
  }

  /// Paints the label with its top left cell at ([x], [y]) of [canvas] for
  /// the tree of [owner], which gives the text order; laid out first if it
  /// must be, at [room] with [ellipsis] as [layout] says.
  void paint(
    Canvas canvas,
    PipelineOwner? owner,
    int x,
    int y, {
    int? room,
    String ellipsis = '\u2026',
  }) {
    layout(
      canvas.segmenter,
      owner?.textOrder ?? TextOrder.logical,
      room: room,
      ellipsis: ellipsis,
    );
    if (room != null && _painter.overflow == TextOverflow.clip) {
      // no room for the ellipsis: cut plainly at the room, which the
      // painter leaves to the canvas's clip
      canvas
        ..save()
        ..clipRect(x, y, room < 0 ? 0 : room, 1);
      _painter.paint(canvas, x, y);
      canvas.restore();
      return;
    }
    _painter.paint(canvas, x, y);
  }
}

/// [text] with each line break in it (LF, VT, FF, CR, NEL, LS, PS) a zero
/// width space: a label is one line, which its painter would end at the
/// first break and cut there, where the canvas drew it whole and dropped
/// them. The painter drops a zero width space as the canvas dropped those,
/// and the offsets of the text, which the marks are, stay as they were.
String _oneLine(String text) {
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if ((c >= 0x0A && c <= 0x0D) || c == 0x85 || c == 0x2028 || c == 0x2029) {
      final b = StringBuffer();
      for (final unit in text.codeUnits) {
        b.writeCharCode(
          (unit >= 0x0A && unit <= 0x0D) ||
                  unit == 0x85 ||
                  unit == 0x2028 ||
                  unit == 0x2029
              ? 0x200B
              : unit,
        );
      }
      return b.toString();
    }
  }
  return text;
}

/// [LabelPainter]s by index, made when first asked for and kept: the
/// painters of the labels of a render object that has any number of them.
final class LabelPainters {
  final _painters = <LabelPainter>[];

  /// The painter of the label at [index].
  LabelPainter operator [](int index) {
    while (_painters.length <= index) {
      _painters.add(LabelPainter());
    }
    return _painters[index];
  }
}
