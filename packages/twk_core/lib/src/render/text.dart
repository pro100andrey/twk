part of 'render.dart';

// Examples can assume:
// late TextSegmenter segmenter;

// ------------------------------------------------------------------ text --

/// One line of text in one pen (shaped once per change, not per frame),
/// cut off at its right edge; [RenderParagraph] breaks text into lines. As
/// a repaint boundary it fills its bounds with [pen] first, which then
/// needs an opaque background.
///
/// It is as wide as its constraints allow and one row tall
/// ([sizedByParent]); its intrinsic width is the columns the canvas draws
/// its text in. It is drawn as stored in either [TextOrder].
///
/// ```dart
/// final styles = StyleTable();
/// final status = RenderText('Ready', styles.pen(const Pen()));
/// status.text = 'Saving…'; // laid out and painted on the next frame
/// ```
final class RenderText extends RenderObject {
  /// Shows [text] in the pen whose id is [pen]; a repaint boundary when
  /// [boundary] is set.
  RenderText(this._text, this._pen, {this.boundary = false});

  String _text;
  int _pen;

  /// The id of the pen the text is drawn in, in the style table it is
  /// painted with; a new one only repaints it.
  int get pen => _pen;
  set pen(int p) {
    if (p != _pen) {
      _pen = p;
      markNeedsPaint();
    }
  }

  /// Whether it is a repaint boundary ([isRepaintBoundary]), which fills
  /// its bounds with [pen] before the text. False by default.
  final bool boundary;
  // the shaped glyphs: a buffer of its own, kept across texts
  final _shapedText = GlyphBuffer();
  var _shaped = false;
  // the glyph table the run is of, and its sweeps when it was shaped
  GlyphTable? _runIn;
  var _runSweeps = 0;

  /// The line shown; new text is shaped again and laid out again, with a
  /// parent that asked how wide it is.
  String get text => _text;
  set text(String t) {
    if (t == _text) {
      return;
    }
    _text = t;
    _shaped = false;
    // laying it out repaints it; a parent that asked how wide it is is
    // laid out too
    markNeedsLayout();
  }

  @override
  bool get isRepaintBoundary => boundary;

  @override
  bool get sizedByParent => true;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..addValue(_text)
      ..add('pen', _pen);
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.constrainH(1);
  }

  // one line, as wide as the canvas draws it: no line break splits it, so
  // the narrowest and the widest it can use agree

  @override
  int computeMinIntrinsicWidth(int height) => _textWidth(this, _text);

  @override
  int computeMaxIntrinsicWidth(int height) => _textWidth(this, _text);

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void paint(PaintContext ctx) {
    if (boundary) {
      assert(_opaqueBackground(ctx, pen), _translucentBoundary);
      final canvas = ctx.canvas;
      canvas.fill(0, 0, width, height, canvas.styles.ownPen(pen));
    }
    final cv = ctx.canvas;
    if (!identical(cv.glyphs, _runIn) || cv.glyphs.sweeps != _runSweeps) {
      // since a sweep of the glyphs, the ids may be others': a text not on
      // the screen then (scrolled out, in a tab not shown) kept none
      _runIn = cv.glyphs;
      _runSweeps = cv.glyphs.sweeps;
      _shaped = false;
    }
    if (!_shaped) {
      cv.shapeInto(_text, _shapedText);
      _shaped = true;
    }
    cv.runBuffer(0, 0, _shapedText, pen);
  }
}

/// Where a [RenderParagraph] may break a line too long for it.
enum TextWrap {
  /// After a space, after a hyphen inside a word, and between two CJK
  /// characters (ideographs, kana, Hangul syllables) but not before
  /// closing punctuation or a small kana, nor after an opening bracket; a
  /// word longer than the line is broken between graphemes. Spaces at the
  /// end of a line hang beyond it: they are neither counted nor drawn.
  word,

  /// Between any two graphemes.
  grapheme,

  /// Nowhere: a line ends only where the text breaks it; one too long is
  /// cut off.
  none,
}

/// Breaks [text] into lines of at most [width] columns, measured as
/// [segmenter] does (the terminal's: `segmenterOf(context)`, never a plain
/// `TextSegmenter()` for an ambiguous-wide terminal), as a
/// [RenderParagraph] of [wrap] does, as (start, end) offsets into
/// [text], in UTF-16 code units: the line's drawn text, without the spaces
/// that hang at a break by word and without the line break that ends it. A
/// text without a character has one empty line; a cluster wider than
/// [width] stands on a line of its own.
///
/// ```dart
/// final lines = breakLines(segmenter, 'well-known words', 8);
/// // [(0, 5), (5, 10), (11, 16)]: "well-" "known" "words"
/// ```
List<(int, int)> breakLines(
  TextSegmenter segmenter,
  String text,
  int width, {
  TextWrap wrap = TextWrap.word,
}) => TextPainter([
  (text, const Pen()),
], wrap: wrap)._lineRanges(segmenter, width < 1 ? 1 : width);

/// The order a tree draws text in, from left to right
/// ([PipelineTextOrder.textOrder]): where it holds right-to-left characters,
/// as they are stored or as they are read.
enum TextOrder {
  /// As stored: the characters of a line from left to right in the order
  /// they come, for a terminal that reorders right-to-left text itself
  /// (implicit mode), or that can't be told not to. Every paragraph counts
  /// as left to right.
  logical,

  /// As read: each line in the order the Unicode Bidirectional Algorithm
  /// (UAX #9, [BidiText]) displays it, its right-to-left runs reversed by
  /// grapheme and their brackets mirrored, for a terminal that does no
  /// bidi or was told not to (explicit mode).
  visual,
}

// the text order of each owner that was given one, and whether any was
// given visual order: until one is, a paragraph attached asks nothing
final _textOrders = Expando<TextOrder>('textOrder');
var _anyVisual = false;

/// The order a tree draws text in: [RenderParagraph] and the editing
/// widgets read it from their owner.
extension PipelineTextOrder on PipelineOwner {
  /// The order this owner's tree draws text in: [TextOrder.logical] until
  /// set. Set to another, the tree is laid out and painted again.
  TextOrder get textOrder => _textOrders[this] ?? TextOrder.logical;

  set textOrder(TextOrder order) {
    if (order == textOrder) {
      return;
    }
    _textOrders[this] = order;
    _anyVisual = _anyVisual || order == TextOrder.visual;
    final root = _root;
    if (root != null) {
      _reorder(root, order);
      markAllDirty();
    }
  }
}

/// Lays [o] and those below it out again, in [order] for paragraphs.
void _reorder(RenderObject o, TextOrder order) {
  if (o is RenderParagraph) {
    o._order = order;
  }
  o
    ..markNeedsLayout()
    ..visitChildren((c) => _reorder(c, order));
}

/// Text in spans, each drawn with its own pen, broken into lines that fit
/// its width as [wrap] says, at most [maxLines] of them, each placed as
/// [align] says; where text is cut off, [overflow] says how it shows. It is
/// as wide as its widest line and as tall as its lines, within its
/// constraints.
///
/// The spans are given as (text, pen) and split into clusters once per
/// change, as the owner's segmenter splits them ([PipelineOwner.segmenter],
/// the canvas's): what a line holds is drawn exactly as wide as it was
/// measured. No line splits a grapheme: a wide glyph that doesn't fit at
/// the end of a line goes to the next. A line break in the text (`\n`,
/// `\r\n` and the like) ends a line; a tab is one blank, other controls
/// take no room. The pens are looked up in the style table it is painted
/// with once per table. Painting it again allocates nothing.
///
/// An edit of the spans is split again only about where the text changed,
/// from a place before it where the clusters are sure to split as they did
/// to one after it where they line up again, and the lines are broken
/// again from the first line that read what changed to one that starts
/// where a line did: the clusters and lines are those the spans give laid
/// out from scratch, at the cost of the lines the edit moved.
///
/// Its min intrinsic width is the widest piece no line break can split, its
/// max intrinsic width its widest line unbroken, and its intrinsic height
/// the lines it has at a width.
///
/// In visual order ([PipelineTextOrder.textOrder]) text with right-to-left
/// characters is broken into lines as stored, then each line drawn in the
/// order UAX #9 gives ([BidiText]): its runs at odd levels reversed by
/// grapheme, their brackets mirrored, an ellipsis where it stands among
/// them. [TextAlign.start] and [TextAlign.end] follow the direction of
/// each line's paragraph. Text without such characters, and any in logical
/// order, is drawn as stored. An edit resolves the levels again only
/// about where the text changed, from a place before it where the levels
/// are sure to resolve as they did to one after it, within its paragraph;
/// the rows whose clusters and levels are as they were are drawn as they
/// were, and only the others ordered again.
///
/// A message in two pens, broken at words, two lines at most:
///
/// ```dart
/// final message = RenderParagraph(
///   [
///     ('Error: ', const Pen(fg: Color.rgb(220, 60, 60))),
///     ('the file could not be saved, the disk is full', const Pen()),
///   ],
///   maxLines: 2,
///   overflow: TextOverflow.ellipsis,
/// );
/// ```
///
/// See also:
///
///  * [RenderText], the leaner object for one line in one pen.
///  * [textRangeAt], the text at a cell as the last layout placed it.
final class RenderParagraph extends RenderObject {
  /// [spans] as (text, pen); replace the list to change them.
  RenderParagraph(
    List<(String, Pen)> spans, {
    TextWrap wrap = TextWrap.word,
    TextOverflow overflow = TextOverflow.clip,
    int? maxLines,
    TextAlign align = TextAlign.left,
    String ellipsis = '\u2026',
  }) : _painter = TextPainter(
         spans,
         wrap: wrap,
         overflow: overflow,
         maxLines: maxLines,
         align: align,
         ellipsis: ellipsis,
       );

  // the layout engine: this object gives it the owner's segmenter and text
  // order, marks layout or paint by what its changes invalidated, and
  // paints it at its origin
  final TextPainter _painter;

  // the owner's text order, given to the painter at each layout
  TextOrder _order = TextOrder.logical;

  // marks what the painter says its last change invalidated
  void _sync() {
    switch (_painter.takeInvalidation()) {
      case TextInvalidation.layout:
        markNeedsLayout();
      case TextInvalidation.paint:
        markNeedsPaint();
      case TextInvalidation.none:
        break;
    }
  }

  /// The text as spans of (text, pen), in order; their texts joined are
  /// the paragraph's text. A new list whose texts differ is split and laid
  /// out again about where they changed; one with only new pens is only
  /// repainted. Replace the list to change them: the paragraph does not
  /// see a change made to it in place.
  List<(String, Pen)> get spans => _painter.spans;
  set spans(List<(String, Pen)> s) {
    _painter.spans = s;
    _sync();
  }

  /// Where a line too long for the paragraph may break, at words by
  /// default; a new one lays it out again.
  TextWrap get wrap => _painter.wrap;
  set wrap(TextWrap w) {
    _painter.wrap = w;
    _sync();
  }

  /// How text cut off shows, a line too long or the lines beyond
  /// [maxLines]: cut off at the edge by default. A new one lays it out
  /// again.
  TextOverflow get overflow => _painter.overflow;
  set overflow(TextOverflow o) {
    _painter.overflow = o;
    _sync();
  }

  /// The most lines it shows, 1 or more; null, the default, for as many as
  /// the text has. A new one lays it out again.
  int? get maxLines => _painter.maxLines;
  set maxLines(int? n) {
    _painter.maxLines = n;
    _sync();
  }

  /// Where each line goes across the paragraph's width, at the left by
  /// default; a new one only repaints it.
  TextAlign get align => _painter.align;
  set align(TextAlign a) {
    _painter.align = a;
    _sync();
  }

  /// The mark that stands for text cut off, `…` by default; `...` is
  /// three columns, which the cut takes from the room as it does the
  /// columns of `…`. A new one lays it out again.
  String get ellipsis => _painter.ellipsis;
  set ellipsis(String e) {
    _painter.ellipsis = e;
    _sync();
  }

  /// The start of the text; how many spans there are, or the pen when there
  /// is one; and the settings that aren't the defaults.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    final spans = _painter.spans;
    // enough of the text for an excerpt
    final text = StringBuffer();
    for (var i = 0; i < spans.length && text.length < 100; i++) {
      text.write(spans[i].$1);
    }
    properties.addValue('$text');
    if (spans.length > 1) {
      properties.add('spans', spans.length);
    } else if (spans.isNotEmpty) {
      properties.add('pen', spans.first.$2, defaultValue: const Pen());
    }
    properties
      ..add('wrap', wrap, defaultValue: TextWrap.word)
      ..add('overflow', overflow, defaultValue: TextOverflow.clip)
      ..add('maxLines', maxLines, defaultValue: null)
      ..add('align', align, defaultValue: TextAlign.left);
  }

  @override
  void attach(PipelineOwner o) {
    super.attach(o);
    // split by another segmenter: split and laid out again
    if (_painter.segmenterChanged(o.segmenter) && _constraints != null) {
      markNeedsLayout();
    }
    final order = _anyVisual ? o.textOrder : TextOrder.logical;
    if (order != _order) {
      _order = order;
      if (_constraints != null) {
        markNeedsLayout();
      }
    }
  }

  TextSegmenter get _segmenter => owner?.segmenter ?? _detachedSegmenter;

  @override
  void performLayout(BoxConstraints c) {
    _painter.layout(c, segmenter: _segmenter, order: _order);
    width = _painter.width;
    height = _painter.height;
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      _painter.minIntrinsicWidth(_segmenter);

  @override
  int computeMaxIntrinsicWidth(int height) =>
      _painter.maxIntrinsicWidth(_segmenter);

  @override
  int computeMinIntrinsicHeight(int width) =>
      _painter.intrinsicHeight(width, segmenter: _segmenter);

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _painter.intrinsicHeight(width, segmenter: _segmenter);

  @override
  void paint(PaintContext ctx) => _painter.paint(ctx.canvas, 0, 0);

  /// How many times this paragraph has found where its clusters start in
  /// its text, which [textRangeAt] does the first time it is asked after
  /// the text is split, and a layout in visual order of text it reorders.
  int get debugOffsetsFound => _painter.debugOffsetsFound;

  /// How many clusters this paragraph has split its text into, counting
  /// each split: all of them when it first splits it, about those an edit
  /// touched after; only the head of a one-line text cut at its end (see
  /// `TextPainter`) until something needs the rest.
  int get debugClustersSplit => _painter.debugClustersSplit;

  /// How many lines this paragraph has broken its clusters into, counting
  /// each layout: all of them at a new width, about those an edit touched
  /// after.
  int get debugLinesBroken => _painter.debugLinesBroken;

  /// How many code units of its text this paragraph has resolved the
  /// bidirectional levels of in visual order, counting each time: all of
  /// it the first time, about what an edit can have changed after.
  int get debugLevelsResolved => _painter.debugLevelsResolved;

  /// How many code units of its text this paragraph has copied into
  /// strings to resolve the bidirectional levels of in visual order,
  /// counting each time: the text of its spans joined the first time,
  /// about what an edit can have changed after.
  int get debugBidiUnitsCopied => _painter.debugBidiUnitsCopied;

  /// How many rows this paragraph has ordered for drawing in visual order,
  /// counting each paint after a change: all of them the first time, those
  /// a change can have touched after.
  int get debugLinesOrdered => _painter.debugLinesOrdered;

  /// For tests: what differs between the clusters and lines this paragraph
  /// keeps up with its edits and those of its spans split and broken from
  /// scratch at the width it last broke them at; null when nothing does.
  /// It splits and breaks again what changed first, as a layout would.
  String? debugDiffFromFresh() => _painter.debugDiffFromFresh(_segmenter);

  /// The columns of row [y] drawing the text from [start] to [end], as
  /// offsets into the text of the spans joined, in UTF-16 code units, as
  /// the last layout placed it: the first and the one past the last of
  /// the cells whose cluster has text in the range, a cell of a gap a
  /// justified row stretches with its space; null where none on the row
  /// does: the range empty, cut off, under an ellipsis (which draws none
  /// of the text it stands for), on another row, before a layout. The
  /// reverse of [textRangeAt]. In visual order ([TextOrder.visual]) the
  /// columns of a range are where it is drawn, which for text a row
  /// reorders may hold cells of other text between them.
  ///
  /// ```dart
  /// final p = RenderParagraph([
  ///   ('one ', const Pen()),
  ///   ('two', const Pen()),
  /// ], wrap: TextWrap.none)..layout(const BoxConstraints(maxW: 20, maxH: 1));
  /// final two = p.columnsOf(4, 7, 0); // (4, 7)
  /// ```
  ///
  /// It makes a record per call, as [cellAt] does: a call per pointer
  /// event or change, none per frame.
  (int, int)? columnsOf(int start, int end, int y) =>
      _painter.columnsOf(start, end, y);

  /// The text at column [x] of row [y] as the last layout placed it, as
  /// offsets (start, end) into the text of the spans joined, in UTF-16
  /// code units: the cluster drawn there, at either cell of a wide one (at
  /// an ellipsis, the clusters it stands for; in a gap a justified row
  /// stretches, the space before it). Left of a row's text it is the empty
  /// range where the row starts; right of it, and past the width, the
  /// empty range where the next row starts, after the spaces the row hangs
  /// and its line break, which right of the last row is the end of the
  /// text. Above the first row it is (0, 0), below the last (length,
  /// length). What takes no cell (a zero-width control, the CR of CR LF)
  /// goes with the cluster after it, so that the ranges tile the text. In
  /// visual order ([TextOrder.visual]) it is the cluster drawn there too,
  /// and the sides of a row keep their logical meaning: left of the text
  /// the start, right of it the next row's, in either direction.
  (int, int) textRangeAt(int x, int y) => _painter.textRangeAt(x, y);

  /// The text at column [x] of row [y] as the last layout placed it, and
  /// whether the cell is an ellipsis, in one query; null where
  /// [textRangeAt] is the empty range: beside a row's text, above or below
  /// the rows, before a layout.
  ///
  /// `start` and `end` are [textRangeAt]'s. At a cell of an ellipsis
  /// `isEllipsis` is true and they are the clusters it stands for, which
  /// are not drawn.
  ///
  /// ```dart
  /// final p = RenderParagraph(
  ///   [('abcdefgh', const Pen())],
  ///   wrap: TextWrap.none,
  ///   overflow: TextOverflow.ellipsis,
  ///   maxLines: 1,
  /// )..layout(const BoxConstraints(minW: 5, maxW: 5, maxH: 100));
  /// final b = p.cellAt(1, 0); // (start: 1, end: 2, isEllipsis: false)
  /// final cut = p.cellAt(4, 0); // (start: 4, end: 8, isEllipsis: true)
  /// final none = p.cellAt(9, 0); // null
  /// ```
  ///
  /// It makes a record per call, which the caller's pattern may not keep:
  /// a call per pointer event, none per frame.
  ({int start, int end, bool isEllipsis})? cellAt(int x, int y) =>
      _painter.cellAt(x, y);
}
