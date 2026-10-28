part of 'render.dart';

// --------------------------------------------- borders, titles, dividers --

// the arms of a piece of line: the directions it reaches out in its cell
const _up = 1;
const _right = 2;
const _down = 4;
const _left = 8;

/// The lines a border or a divider is drawn with. Each has a piece for
/// every set of directions a line reaches out in its cell ([glyph]):
/// straight lines, corners, and the joints of three and four lines.
enum BorderType {
  /// `┌─┐ │ └─┘`
  single(' ╵╶└╷│┌├╴┘─┴┐┤┬┼'),

  /// `╭─╮ │ ╰─╯`: [single] with round corners.
  rounded(' ╵╶╰╷│╭├╴╯─┴╮┤┬┼'),

  /// `╔═╗ ║ ╚═╝`
  double(' ║═╚║║╔╠═╝═╩╗╣╦╬'),

  /// `┏━┓ ┃ ┗━┛`
  heavy(' ╹╺┗╻┃┏┣╸┛━┻┓┫┳╋'),

  /// `+-+ | +-+`
  ascii(' |-+||++-+-+++++'),

  /// Blanks: the lines keep their cells, which show their pen's
  /// background.
  none('                ');

  const BorderType(this._pieces);

  // the code point of each set of arms (up 1, right 2, down 4, left 8),
  // one UTF-16 unit each
  final String _pieces;

  /// The piece of line that reaches [up], [right], [down] and [left] in
  /// its cell: a straight line for two opposite arms, a corner for two at
  /// a right angle, a joint for three or four, a blank for none.
  int glyph({
    bool up = false,
    bool right = false,
    bool down = false,
    bool left = false,
  }) => _pieces.codeUnitAt(
    (up ? _up : 0) |
        (right ? _right : 0) |
        (down ? _down : 0) |
        (left ? _left : 0),
  );
}

/// The glyph runs a border or a divider draws its lines with: the pieces
/// of a [BorderType] as a canvas draws them, or those of
/// [BorderType.ascii] when it draws any of them two columns wide (box
/// drawing is East Asian ambiguous). Built again only when the type, the
/// ambiguous width or the length of a line changes.
final class _Lines {
  BorderType? _type;
  var _ambiguous = 0;
  var _drawn = '';
  final _pieces = List<GlyphRun?>.filled(16, null);
  GlyphRun? _line;

  /// Draws [type] as a canvas whose ambiguous width is [ambiguous].
  void use(BorderType type, int ambiguous) {
    if (type == _type && ambiguous == _ambiguous) {
      return;
    }
    _type = type;
    _ambiguous = ambiguous;
    final pieces = type._pieces;
    var narrow = true;
    for (var i = 0; i < pieces.length; i++) {
      narrow = narrow && codePointWidth(pieces.codeUnitAt(i), ambiguous) == 1;
    }
    _drawn = narrow ? pieces : BorderType.ascii._pieces;
    _pieces.fillRange(0, _pieces.length, null);
    _line = null;
  }

  /// One cell of line reaching out in [arms].
  GlyphRun piece(int arms) => _pieces[arms] ??= GlyphRun(
    Uint32List(1)..[0] = _drawn.codeUnitAt(arms),
    1,
  );

  /// A horizontal line [length] cells long.
  GlyphRun line(int length) {
    var l = _line;
    if (l == null || l.width != length) {
      final g = Uint32List(length)
        ..fillRange(0, length, _drawn.codeUnitAt(_left | _right));
      l = _line = GlyphRun(g, length);
    }
    return l;
  }

  /// Draws a vertical line down column [x], [height] cells long, in [pen].
  void column(Canvas canvas, int x, int height, int pen) {
    final run = piece(_up | _down);
    for (var y = 0; y < height; y++) {
      canvas.run(x, y, run, pen);
    }
  }

  /// Merges a vertical line down column [x] from row [y0] to row [y1], in
  /// [pen] over [under], with the lines in its cells ([Canvas.mergeRun]);
  /// an end that is [open] at the top (_up) or the bottom (_down) joins a
  /// line it lands on without reaching past it.
  void mergeColumn(
    Canvas canvas,
    int x,
    int y0,
    int y1,
    int pen,
    int under,
    int open,
  ) {
    final run = piece(_up | _down);
    for (var y = y0; y < y1; y++) {
      canvas.mergeRun(
        x,
        y,
        run,
        pen,
        under: under,
        trimFirst: y == y0 ? open & _up : 0,
        trimLast: y == y1 - 1 ? open & _down : 0,
      );
    }
  }
}

/// The border of a [RenderDecoratedBox]: the lines it is drawn with, for
/// each side that has one its pen, and whether it [merge]s with the lines
/// already drawn. A side without a pen has no border.
///
/// ```dart
/// // a line under a heading, and nothing on the other sides
/// const underline = BoxBorder(bottom: Pen(fg: Color.rgb(90, 90, 90)));
/// const panel = BoxBorder.all(type: BorderType.rounded);
/// ```
final class BoxBorder {
  /// A border of [type], single lines unless given, on the sides given a
  /// pen; [merge] off unless given.
  const BoxBorder({
    this.type = BorderType.single,
    this.top,
    this.right,
    this.bottom,
    this.left,
    this.merge = false,
  });

  /// A border on every side, in [pen].
  const BoxBorder.all({
    this.type = BorderType.single,
    Pen pen = const Pen(),
    this.merge = false,
  }) : top = pen,
       right = pen,
       bottom = pen,
       left = pen;

  /// The lines the border is drawn with.
  final BorderType type;

  /// The pen of the top side; null for no line there.
  final Pen? top;

  /// The pen of the right side; null for no line there.
  final Pen? right;

  /// The pen of the bottom side; null for no line there.
  final Pen? bottom;

  /// The pen of the left side; null for no line there.
  final Pen? left;

  /// Whether the border joins the lines already drawn in its cells where
  /// it meets or crosses them (`├ ┬ ┼`), rather than covering them, and
  /// leaves the text in them, such as the title of a box whose edge it
  /// shares ([Canvas.mergeRun]).
  final bool merge;

  @override
  bool operator ==(Object other) =>
      other is BoxBorder &&
      other.type == type &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left &&
      other.merge == merge;
  @override
  int get hashCode => Object.hash(type, top, right, bottom, left, merge);
}

/// Text on the top or the bottom edge of a [RenderDecoratedBox], in [pen]:
/// the y of [alignment] picks the edge (-1 the top, 1 the bottom; not 0),
/// its x the place along it.
///
/// ```dart
/// const titles = [
///   BoxTitle(' Files '),
///   BoxTitle(' 3 of 12 ', alignment: Alignment.bottomRight),
/// ];
/// ```
final class BoxTitle {
  /// [text] on an edge, in the default pen at the left of the top edge
  /// unless given.
  const BoxTitle(
    this.text, {
    this.pen = const Pen(),
    this.alignment = Alignment.topLeft,
  });

  /// What the title says, cut off with `…` where its edge is too short.
  final String text;

  /// What the title is drawn in, over the border's pen and the box's
  /// background.
  final Pen pen;

  /// The edge ([Alignment.y] -1 for the top, 1 for the bottom) and the
  /// place along it ([Alignment.x]).
  final Alignment alignment;

  @override
  bool operator ==(Object other) =>
      other is BoxTitle &&
      other.text == text &&
      other.pen == pen &&
      other.alignment == alignment;
  @override
  int get hashCode => Object.hash(text, pen, alignment);
}

bool _onEdges(List<BoxTitle> titles) {
  for (var i = 0; i < titles.length; i++) {
    if (titles[i].alignment.y == 0) {
      return false;
    }
  }
  return true;
}

const _offEdge = 'a title on the top or the bottom edge: an alignment y of ±1';

/// The sides [b] has a border on, as arms: top up, bottom down.
int _sidesOf(BoxBorder? b) => b == null
    ? 0
    : (b.top != null ? _up : 0) |
          (b.right != null ? _right : 0) |
          (b.bottom != null ? _down : 0) |
          (b.left != null ? _left : 0);

/// A box with a [background], a [border] with [titles] on its top and
/// bottom edges, and [padding] between the border and its child.
///
/// Its [insets] are a cell for each side with a border, a row for an edge
/// with titles but no border, and the padding. It is as big as its child
/// and its insets, and as wide as its titles, within its constraints; the
/// child is laid out within the constraints less the insets, at [inner].
/// Without a child it is as big as the constraints allow, or along an axis
/// they leave unbounded as small. Its min intrinsic width leaves the
/// titles out, since they can be cut off; its max intrinsic width counts
/// them.
///
/// The border is drawn on the sides that have a pen; a corner where both
/// of its sides are, in the pen of the top or the bottom side; a side
/// whose neighbour has none runs on to the box's corner. Where the canvas
/// draws the pieces of the [BorderType] two columns wide (box drawing is
/// East Asian ambiguous), [BorderType.ascii] is drawn instead. A border
/// that [BoxBorder.merge]s draws each of its cells once, merged with the
/// line already in it ([Canvas.mergeRun]): it joins the lines it meets or
/// crosses, leaving the text drawn in its cells (the titles of a box
/// whose edge it shares), and the end of a side without a neighbour joins
/// a line it lands on without reaching past it (`┬`, not `┼`). The
/// background goes under the merged lines and that text, keeping them,
/// and fills the rest of the box.
///
/// Titles go on their edge between the side borders: those aligned left
/// one after another from its left end, a cell apart, those aligned right
/// likewise up to its right end, those in the center in its middle as far
/// as the others let them. Each gets the room those placed before it
/// leave: the left ones first, then the right ones from the last, then
/// those in the center. One that doesn't fit is cut off where a glyph
/// ends, with "…" (as wide as the ambiguous width) after the glyphs that
/// fit and no blank before it; a wide glyph is never split.
///
/// A [background] of null leaves what is under the box; new pens or a new
/// border type repaint it; new insets, title texts or title places lay it
/// out. Painting it again allocates nothing.
///
/// A rounded panel with a title, one cell between its border and the
/// text:
///
/// ```dart
/// final panel = RenderDecoratedBox(
///   border: const BoxBorder.all(type: BorderType.rounded),
///   titles: const [BoxTitle(' Status ')],
///   padding: const EdgeInsets.all(1),
///   child: RenderParagraph([('All systems go', const Pen())]),
/// );
/// ```
///
/// See also:
///
///  * [RenderDivider], a line across without the box.
///  * [RenderPadding], for the space without the border.
final class RenderDecoratedBox extends RenderObject
    with RenderObjectWithChildMixin {
  /// A box with [background], [border], [titles] and [padding] around
  /// [child]; with every one left out, an empty box that fills nothing.
  RenderDecoratedBox({
    this._background,
    this._border,
    this._titles = const [],
    this._padding = EdgeInsets.zero,
    RenderObject? child,
  }) : assert(_onEdges(_titles), _offEdge) {
    _titlesChanged();
    this.child = child;
  }

  Pen? _background;

  /// What the box is filled with first, under the border, the titles and
  /// the child; null leaves what is under the box. A new one only repaints
  /// it.
  Pen? get background => _background;
  set background(Pen? p) {
    if (p != _background) {
      _background = p;
      _pensIn = null;
      markNeedsPaint();
    }
  }

  BoxBorder? _border;

  /// The lines around the box, on the sides that have a pen; null for
  /// none. A border on other sides lays the box out again; new pens, a new
  /// type or [BoxBorder.merge] only repaint it.
  BoxBorder? get border => _border;
  set border(BoxBorder? b) {
    if (b == _border) {
      return;
    }
    final sides = _sidesOf(_border);
    _border = b;
    _pensIn = null;
    if (_sidesOf(b) != sides) {
      _measureInsets();
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  List<BoxTitle> _titles;

  /// The titles on the top and bottom edges, in order; none by default.
  /// New texts or alignments lay the box out again; new pens only repaint
  /// it.
  List<BoxTitle> get titles => _titles;
  set titles(List<BoxTitle> t) {
    assert(_onEdges(t), _offEdge);
    final old = _titles;
    var samePlaces = t.length == old.length;
    var samePens = true;
    for (var i = 0; samePlaces && i < t.length; i++) {
      samePlaces =
          t[i].text == old[i].text && t[i].alignment == old[i].alignment;
      samePens = samePens && t[i].pen == old[i].pen;
    }
    _titles = t;
    if (!samePlaces) {
      _titlesChanged();
      markNeedsLayout();
    } else if (!samePens) {
      _pensIn = null;
      markNeedsPaint();
    }
  }

  EdgeInsets _padding;

  /// The empty cells between the border and the child, none by default; a
  /// new one lays the box out again.
  EdgeInsets get padding => _padding;
  set padding(EdgeInsets p) {
    if (p != _padding) {
      _padding = p;
      _measureInsets();
      markNeedsLayout();
    }
  }

  /// The background; the border's type, its sides unless it has all four,
  /// its pen when the sides share one, and whether it merges; the titles'
  /// texts; the padding.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('background', _background, defaultValue: null);
    final border = _border;
    if (border != null) {
      final sides = [
        ('top', border.top),
        ('right', border.right),
        ('bottom', border.bottom),
        ('left', border.left),
      ];
      final present = [
        for (final (side, pen) in sides)
          if (pen != null) side,
      ];
      final pens = {for (final (_, pen) in sides) ?pen};
      final words = [
        border.type.name,
        if (present.length < 4) ...present,
        if (pens.length == 1 && pens.first != const Pen())
          describePen(pens.first),
        if (border.merge) 'merged',
      ];
      properties.addMessage('border', words.join(' '));
    }
    if (_titles.isNotEmpty) {
      properties.addMessage(
        _titles.length == 1 ? 'title' : 'titles',
        [for (final t in _titles) describeText(t.text)].join(' '),
      );
    }
    if (_padding != EdgeInsets.zero) {
      properties.addMessage('padding', describeInsets(_padding));
    }
  }

  // the insets, and the sides with a border as arms (top up, bottom down)
  var _insetL = 0;
  var _insetT = 0;
  var _insetR = 0;
  var _insetB = 0;
  var _sides = 0;

  // each title: its columns, the column it starts at and the columns it
  // is shown in (0: not shown); measured as a segmenter of _measuredMode
  // and _measuredAmbiguous measures (null: not yet)
  var _titleAt = Int32List(0);
  TextMode? _measuredMode;
  var _measuredAmbiguous = 0;

  // each title shaped by _shapedBy for _shapedIn (null: to be shaped)
  final _runs = <GlyphRun?>[];
  GlyphTable? _shapedIn;
  TextSegmenter? _shapedBy;

  // the ids in _pensIn of the background, the top, right, bottom and left
  // sides (-1: none), then of each title
  StyleTable? _pensIn;
  var _pens = Int32List(5);

  final _lines = _Lines();
  GlyphRun? _ellipsis;

  /// The cells between the box's edges and its child: a cell for each side
  /// with a border, a row for an edge with titles but no border, and the
  /// padding.
  EdgeInsets get insets => EdgeInsets.only(
    left: _insetL,
    top: _insetT,
    right: _insetR,
    bottom: _insetB,
  );

  /// Where the child goes in the box as laid out: (x, y, width, height),
  /// the box less its [insets].
  (int, int, int, int) get inner => (
    _insetL,
    _insetT,
    _less(width, _insetL + _insetR),
    _less(height, _insetT + _insetB),
  );

  @override
  void attach(PipelineOwner o) {
    super.attach(o);
    // titles measured otherwise than the new owner measures them: laid out
    // again
    final seg = o.segmenter;
    if (_titles.isNotEmpty &&
        _measuredMode != null &&
        (_measuredMode != seg.mode ||
            _measuredAmbiguous != seg.ambiguousWidth)) {
      markNeedsLayout();
    }
  }

  void _titlesChanged() {
    final n = _titles.length;
    _runs
      ..length = n
      ..fillRange(0, n, null);
    if (_titleAt.length < 3 * n) {
      _titleAt = Int32List(3 * n);
    }
    _pensIn = null;
    _measureInsets();
  }

  void _measureInsets() {
    var top = false;
    var bottom = false;
    for (var i = 0; i < _titles.length; i++) {
      if (_titles[i].alignment.y > 0) {
        bottom = true;
      } else {
        top = true;
      }
    }
    final s = _sides = _sidesOf(_border);
    final p = _padding;
    _insetL = ((s & _left) != 0 ? 1 : 0) + p.left;
    _insetT = ((s & _up) != 0 || top ? 1 : 0) + p.top;
    _insetR = ((s & _right) != 0 ? 1 : 0) + p.right;
    _insetB = ((s & _down) != 0 || bottom ? 1 : 0) + p.bottom;
  }

  /// Measures each title as the canvas of the owner draws it; returns the
  /// columns the titles of the fuller edge take, a cell apart, with the
  /// side borders (0 without titles).
  int _measureTitles() {
    final seg = owner?.segmenter ?? _detachedSegmenter;
    _measuredMode = seg.mode;
    _measuredAmbiguous = seg.ambiguousWidth;
    var top = -1;
    var bottom = -1;
    for (var i = 0; i < _titles.length; i++) {
      final w = _titleAt[3 * i] = _textWidth(this, _titles[i].text);
      if (_titles[i].alignment.y > 0) {
        bottom += w + 1;
      } else {
        top += w + 1;
      }
    }
    final most = top > bottom ? top : bottom;
    if (most < 0) {
      return 0;
    }
    return most +
        ((_sides & _left) != 0 ? 1 : 0) +
        ((_sides & _right) != 0 ? 1 : 0);
  }

  /// Places the measured titles on the box as wide as it is.
  void _placeTitles() {
    final n = _titles.length;
    final x0 = (_sides & _left) != 0 ? 1 : 0;
    final x1 = width - ((_sides & _right) != 0 ? 1 : 0);
    for (var edge = -1; edge <= 1; edge += 2) {
      // the left ones from the left end
      var at = x0;
      for (var i = 0; i < n; i++) {
        final a = _titles[i].alignment;
        if (a.x < 0 && (a.y > 0 ? 1 : -1) == edge) {
          final shown = _show(i, at, x1 - at);
          at += shown > 0 ? shown + 1 : 0;
        }
      }
      final from = at;
      // the right ones up to the right end, the last first
      var to = x1;
      for (var i = n - 1; i >= 0; i--) {
        final a = _titles[i].alignment;
        if (a.x > 0 && (a.y > 0 ? 1 : -1) == edge) {
          final w = _titleAt[3 * i];
          final room = to - from;
          final shown = _show(i, to - (w < room ? w : room), room);
          to -= shown > 0 ? shown + 1 : 0;
        }
      }
      // those in the center in the middle, between the others
      var total = -1;
      for (var i = 0; i < n; i++) {
        final a = _titles[i].alignment;
        if (a.x == 0 && (a.y > 0 ? 1 : -1) == edge) {
          total += _titleAt[3 * i] + 1;
        }
      }
      if (total < 0) {
        continue;
      }
      at = x0 + (x1 - x0 - total) ~/ 2;
      at = at + total > to ? to - total : at;
      at = at < from ? from : at;
      for (var i = 0; i < n; i++) {
        final a = _titles[i].alignment;
        if (a.x == 0 && (a.y > 0 ? 1 : -1) == edge) {
          final shown = _show(i, at, to - at);
          at += shown > 0 ? shown + 1 : 0;
        }
      }
    }
  }

  /// Shows title [i] from column [x] in at most [room] columns; returns
  /// the columns it is shown in.
  int _show(int i, int x, int room) {
    final w = _titleAt[3 * i];
    final shown = w < room ? w : (room > 0 ? room : 0);
    _titleAt
      ..[3 * i + 1] = x
      ..[3 * i + 2] = shown;
    return shown;
  }

  @override
  void performLayout(BoxConstraints c) {
    final h = _insetL + _insetR;
    final v = _insetT + _insetB;
    final titles = _measureTitles();
    final child = _child;
    if (child == null) {
      width = c.maxW >= BoxConstraints.unbounded
          ? c.constrainW(h > titles ? h : titles)
          : c.maxW;
      height = c.maxH >= BoxConstraints.unbounded ? c.constrainH(v) : c.maxH;
    } else {
      _layoutChild(
        child,
        _less(c.minW, h),
        _less(c.maxW, h),
        _less(c.minH, v),
        _less(c.maxH, v),
      );
      final w = child.width + h;
      width = c.constrainW(w > titles ? w : titles);
      height = c.constrainH(child.height + v);
      child.parentData
        ..dx = _insetL
        ..dy = _insetT;
    }
    _placeTitles();
  }

  // what the child asks for inside the insets, plus the insets; the max
  // width at least what the titles take

  @override
  int computeMinIntrinsicWidth(int height) =>
      _insetL +
      _insetR +
      (_child?.getMinIntrinsicWidth(_less(height, _insetT + _insetB)) ?? 0);

  @override
  int computeMaxIntrinsicWidth(int height) {
    final w =
        _insetL +
        _insetR +
        (_child?.getMaxIntrinsicWidth(_less(height, _insetT + _insetB)) ?? 0);
    final titles = _measureTitles();
    return w > titles ? w : titles;
  }

  @override
  int computeMinIntrinsicHeight(int width) =>
      _insetT +
      _insetB +
      (_child?.getMinIntrinsicHeight(_less(width, _insetL + _insetR)) ?? 0);

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _insetT +
      _insetB +
      (_child?.getMaxIntrinsicHeight(_less(width, _insetL + _insetR)) ?? 0);

  /// Looks the pens up in [styles] unless they were.
  void _resolvePens(StyleTable styles) {
    if (identical(styles, _pensIn)) {
      return;
    }
    _pensIn = styles;
    final n = _titles.length;
    if (_pens.length < 5 + n) {
      _pens = Int32List(5 + n);
    }
    final b = _border;
    _pens
      ..[0] = _idIn(styles, _background)
      ..[1] = _idIn(styles, b?.top)
      ..[2] = _idIn(styles, b?.right)
      ..[3] = _idIn(styles, b?.bottom)
      ..[4] = _idIn(styles, b?.left);
    for (var i = 0; i < n; i++) {
      _pens[5 + i] = styles.pen(_titles[i].pen);
    }
  }

  static int _idIn(StyleTable styles, Pen? p) => p == null ? -1 : styles.pen(p);

  /// Opaque with a [background]; without one it leaves what is under it
  /// to be seen, and defers to its child but for the cells it draws
  /// ([hitTestSelf]).
  @override
  HitTestBehavior get hitTestBehavior => _background != null
      ? HitTestBehavior.opaque
      : HitTestBehavior.deferToChild;

  /// Anywhere with a [background]; without one, on its border and on the
  /// cells its titles are shown in.
  @override
  bool hitTestSelf(int x, int y) {
    if (_background != null) {
      return true;
    }
    final s = _sides;
    if (((s & _left) != 0 && x == 0) ||
        ((s & _right) != 0 && x == width - 1) ||
        ((s & _up) != 0 && y == 0) ||
        ((s & _down) != 0 && y == height - 1)) {
      return true;
    }
    for (var i = 0; i < _titles.length; i++) {
      final at = _titleAt[3 * i + 1];
      if (y == (_titles[i].alignment.y > 0 ? height - 1 : 0) &&
          x >= at &&
          x < at + _titleAt[3 * i + 2]) {
        return true;
      }
    }
    return false;
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    _resolvePens(canvas.styles);
    final border = _border;
    if (_sides != 0 && border!.merge) {
      _mergeBorder(canvas, border.type);
    } else {
      if (_pens[0] >= 0) {
        canvas.fill(0, 0, width, height, _pens[0]);
      }
      if (_sides != 0) {
        _paintBorder(canvas, border!.type);
      }
    }
    if (_titles.isNotEmpty) {
      _paintTitles(canvas);
    }
    final c = _child;
    if (c != null) {
      paintChild(ctx, c);
    }
  }

  /// The sides first, the lines across over them, then the corners.
  void _paintBorder(Canvas canvas, BorderType type) {
    final lines = _lines..use(type, canvas.segmenter.ambiguousWidth);
    final s = _sides;
    final w = width;
    final h = height;
    if ((s & _left) != 0) {
      lines.column(canvas, 0, h, _pens[4]);
    }
    if ((s & _right) != 0) {
      lines.column(canvas, w - 1, h, _pens[2]);
    }
    if ((s & _up) != 0) {
      canvas.run(0, 0, lines.line(w), _pens[1]);
      if ((s & _left) != 0) {
        canvas.run(0, 0, lines.piece(_right | _down), _pens[1]);
      }
      if ((s & _right) != 0) {
        canvas.run(w - 1, 0, lines.piece(_down | _left), _pens[1]);
      }
    }
    if ((s & _down) != 0) {
      canvas.run(0, h - 1, lines.line(w), _pens[3]);
      if ((s & _left) != 0) {
        canvas.run(0, h - 1, lines.piece(_up | _right), _pens[3]);
      }
      if ((s & _right) != 0) {
        canvas.run(w - 1, h - 1, lines.piece(_up | _left), _pens[3]);
      }
    }
  }

  /// The background inside the border, then each cell of the border once,
  /// merged with the line in it over the background: what
  /// [_paintBorder] leaves in a cell, joined with what was there.
  void _mergeBorder(Canvas canvas, BorderType type) {
    final lines = _lines..use(type, canvas.segmenter.ambiguousWidth);
    final s = _sides;
    final w = width;
    final h = height;
    final under = _pens[0];
    final x0 = (s & _left) != 0 ? 1 : 0;
    final x1 = (s & _right) != 0 ? w - 1 : w;
    final y0 = (s & _up) != 0 ? 1 : 0;
    final y1 = (s & _down) != 0 ? h - 1 : h;
    if (under >= 0 && x1 > x0 && y1 > y0) {
      canvas.fill(x0, y0, x1 - x0, y1 - y0, under);
    }
    // a side whose neighbour has none ends open there
    final open = (_up | _down) & ~s;
    if ((s & _right) != 0) {
      lines.mergeColumn(canvas, w - 1, y0, y1, _pens[2], under, open);
    }
    if ((s & _left) != 0 && x1 > 0) {
      lines.mergeColumn(canvas, 0, y0, y1, _pens[4], under, open);
    }
    if ((s & _down) != 0) {
      _mergeEdge(canvas, lines, h - 1, _up, _pens[3]);
    }
    if ((s & _up) != 0 && y1 > 0) {
      _mergeEdge(canvas, lines, 0, _down, _pens[1]);
    }
  }

  /// Merges the top or the bottom edge, at row [y] in [pen], its corners
  /// reaching [toward] the other edge; an end without a corner is open.
  void _mergeEdge(Canvas canvas, _Lines lines, int y, int toward, int pen) {
    final s = _sides;
    final under = _pens[0];
    var x0 = 0;
    var x1 = width;
    if ((s & _right) != 0) {
      x1--;
      canvas.mergeRun(x1, y, lines.piece(toward | _left), pen, under: under);
    }
    if ((s & _left) != 0 && x1 > 0) {
      x0 = 1;
      canvas.mergeRun(0, y, lines.piece(toward | _right), pen, under: under);
    }
    if (x1 > x0) {
      canvas.mergeRun(
        x0,
        y,
        lines.line(x1 - x0),
        pen,
        under: under,
        trimFirst: x0 == 0 ? _left : 0,
        trimLast: x1 == width ? _right : 0,
      );
    }
  }

  void _paintTitles(Canvas canvas) {
    final seg = canvas.segmenter;
    if (!identical(canvas.glyphs, _shapedIn) || !identical(seg, _shapedBy)) {
      _shapedIn = canvas.glyphs;
      _shapedBy = seg;
      _runs.fillRange(0, _runs.length, null);
    }
    final e = codePointWidth(0x2026, seg.ambiguousWidth);
    for (var i = 0; i < _titles.length; i++) {
      final shown = _titleAt[3 * i + 2];
      if (shown <= 0) {
        continue;
      }
      final x = _titleAt[3 * i + 1];
      final y = _titles[i].alignment.y > 0 ? height - 1 : 0;
      final pen = _pens[5 + i];
      final run = _runs[i] ??= canvas.shape(_titles[i].text);
      if (run.width <= shown) {
        canvas.run(x, y, run, pen);
        continue;
      }
      // the glyphs that fit before the ellipsis, or in all the room when
      // the ellipsis doesn't fit
      final room = shown - e;
      final fit = room < 0 ? shown : room;
      final g = run.glyphs;
      var k = 0;
      var w = 0;
      while (k < g.length) {
        final cells = (g[k] & kWide) != 0 ? 2 : 1;
        if (w + cells > fit) {
          break;
        }
        w += cells;
        k++;
      }
      if (room >= 0) {
        while (k > 0 && (g[k - 1] & kGlyphMask) == kBlank) {
          k--;
          w--;
        }
      }
      canvas
        ..save()
        ..clipRect(x, y, w, 1)
        ..run(x, y, run, pen)
        ..restore();
      if (room >= 0) {
        canvas.run(x + w, y, _ellipsisOf(e), pen);
      }
    }
  }

  GlyphRun _ellipsisOf(int width) {
    var e = _ellipsis;
    if (e == null || e.width != width) {
      e = _ellipsis = GlyphRun(
        Uint32List(1)..[0] = width == 2 ? 0x2026 | kWide : 0x2026,
        width,
      );
    }
    return e;
  }
}

/// A line across the room it gets, drawn with [type] in [pen]: a row as
/// wide as the constraints allow ([Axis.horizontal]) or a column as tall
/// ([Axis.vertical]), as short as they allow along an axis they leave
/// unbounded. Given more rows (columns), it draws the line in the middle
/// one, the odd one after it. Its intrinsic size is a row (a column) across
/// the line and nothing along it. Where the canvas draws the pieces of the
/// [BorderType] two columns wide, [BorderType.ascii] is drawn instead.
/// With [merge] the line is merged with the lines already in its cells
/// ([Canvas.mergeRun]): it joins those it crosses, leaves the text in its
/// cells (the title on the edge of a box it is drawn over), and each end
/// joins a line it lands on without reaching past it (`├───┤` across a
/// box).
///
/// ```dart
/// final rule = RenderDivider(pen: const Pen(fg: Color.rgb(90, 90, 90)));
/// final split = RenderDivider(direction: Axis.vertical, merge: true);
/// ```
///
/// See also:
///
///  * [RenderDecoratedBox], whose border it joins with [merge].
final class RenderDivider extends RenderObject {
  /// A line along [direction], horizontal unless given, of [type], single
  /// unless given, in [pen]; [merge] off unless given.
  RenderDivider({
    this._direction = Axis.horizontal,
    this._type = BorderType.single,
    this._pen = const Pen(),
    this._merge = false,
  });

  Axis _direction;

  /// Whether the line runs across ([Axis.horizontal]) or down
  /// ([Axis.vertical]); a new one lays it out again.
  Axis get direction => _direction;
  set direction(Axis d) {
    if (d != _direction) {
      _direction = d;
      // sized by its constraints alone, its new size would not reach the
      // parent
      parent?.markNeedsLayout();
      markNeedsLayout();
    }
  }

  BorderType _type;

  /// The lines the divider is drawn with; a new one only repaints it.
  BorderType get type => _type;
  set type(BorderType t) {
    if (t != _type) {
      _type = t;
      markNeedsPaint();
    }
  }

  Pen _pen;

  /// What the line is drawn in; a new one only repaints it.
  Pen get pen => _pen;
  set pen(Pen p) {
    if (p != _pen) {
      _pen = p;
      _penIn = null;
      markNeedsPaint();
    }
  }

  bool _merge;

  /// Whether the line joins the lines already drawn in its cells rather
  /// than covering them, leaving the text in them; off by default. A new
  /// value only repaints it.
  bool get merge => _merge;
  set merge(bool m) {
    if (m != _merge) {
      _merge = m;
      markNeedsPaint();
    }
  }

  // the id of the pen in _penIn
  StyleTable? _penIn;
  var _penId = 0;
  final _lines = _Lines();

  bool get _horizontal => _direction == Axis.horizontal;

  @override
  bool get sizedByParent => true;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('direction', _direction, defaultValue: Axis.horizontal)
      ..add('type', _type, defaultValue: BorderType.single)
      ..add('pen', _pen, defaultValue: const Pen());
    if (_merge) {
      properties.addTag('merged');
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    if (_horizontal) {
      width = c.maxW >= BoxConstraints.unbounded ? c.minW : c.maxW;
      height = c.constrainH(1);
    } else {
      width = c.constrainW(1);
      height = c.maxH >= BoxConstraints.unbounded ? c.minH : c.maxH;
    }
  }

  @override
  int computeMinIntrinsicWidth(int height) => _horizontal ? 0 : 1;

  @override
  int computeMaxIntrinsicWidth(int height) => _horizontal ? 0 : 1;

  @override
  int computeMinIntrinsicHeight(int width) => _horizontal ? 1 : 0;

  @override
  int computeMaxIntrinsicHeight(int width) => _horizontal ? 1 : 0;

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    if (!identical(styles, _penIn)) {
      _penIn = styles;
      _penId = styles.pen(_pen);
    }
    final lines = _lines..use(_type, canvas.segmenter.ambiguousWidth);
    if (_horizontal) {
      final y = (height - 1) ~/ 2;
      if (_merge) {
        canvas.mergeRun(
          0,
          y,
          lines.line(width),
          _penId,
          trimFirst: _left,
          trimLast: _right,
        );
      } else {
        canvas.run(0, y, lines.line(width), _penId);
      }
    } else if (_merge) {
      lines.mergeColumn(
        canvas,
        (width - 1) ~/ 2,
        0,
        height,
        _penId,
        -1,
        _up | _down,
      );
    } else {
      lines.column(canvas, (width - 1) ~/ 2, height, _penId);
    }
  }
}
