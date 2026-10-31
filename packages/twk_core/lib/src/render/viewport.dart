part of 'render.dart';

/// The terminal's own colors: what a blank cell shows.
const _defaultColors = Pen(fg: Color.defaultColor, bg: Color.defaultColor);

/// A window onto its child, which is as long as it likes along [axis]: the
/// first [scrollOffset] rows of the child (columns, along a horizontal
/// axis) are scrolled off the start of the window, and what does not fit
/// is cut off. The child is laid out with no limit along the axis and
/// within the constraints across it; the viewport is as big as the child
/// within its constraints. Each layout keeps [scrollOffset] from 0 to the
/// child's extent along the axis less the viewport's, and tells
/// [onExtents] both.
///
/// It is its own repaint boundary, filled with [background] under the
/// child, which needs an opaque background. When it only scrolled since it
/// last painted, along a vertical axis, all of it on the surface and
/// nothing painted over it, it shifts its rows on the surface and declares
/// the scroll ([Surface.scrollRect]), so that the terminal scrolls in
/// hardware, and paints just the rows the scroll exposed; the repaint
/// boundaries inside it marked for paint repaint on their own. Otherwise,
/// and once anything inside it was marked for paint or laid out, it
/// paints all of it.
///
/// A column of paragraphs taller than the window, scrolled down a page:
///
/// ```dart
/// final viewport = RenderViewport(
///   child: RenderFlex(
///     direction: Axis.vertical,
///     children: [
///       for (var i = 0; i < 100; i++)
///         RenderParagraph([('Line $i', const Pen())]),
///     ],
///   ),
/// );
/// viewport.scrollOffset += 20;
/// ```
///
/// See also:
///
///  * [RenderList], which lays out only the items it shows.
///  * [RenderLog], lines of text kept at their end as they are added.
final class RenderViewport extends RenderObject
    with RenderObjectWithChildMixin {
  /// A window onto [child], if any, along [axis], vertical unless given,
  /// scrolled by [scrollOffset], 0 or more, from the start unless given;
  /// filled with the terminal's own colors unless [background] is given.
  RenderViewport({
    this._axis = Axis.vertical,
    this._scrollOffset = 0,
    this._background = _defaultColors,
    this.onExtents,
    RenderObject? child,
  }) : assert(_scrollOffset >= 0, 'an offset of 0 cells or more') {
    this.child = child;
  }

  Axis _axis;

  /// The axis it scrolls along, along which the child is laid out with no
  /// limit; a new one lays it out again.
  Axis get axis => _axis;
  set axis(Axis a) {
    if (a != _axis) {
      _axis = a;
      markNeedsLayout();
    }
  }

  int _scrollOffset;

  /// The cells of the child scrolled off the start, from 0 to the child's
  /// extent less the viewport's once laid out: one set out of that range
  /// is kept at its end. A new one repaints the viewport, shifting its
  /// rows where it can.
  int get scrollOffset => _scrollOffset;
  set scrollOffset(int o) {
    final v = o < 0 ? 0 : (o > _maxOffset ? _maxOffset : o);
    if (v != _scrollOffset) {
      _scrollOffset = v;
      _place();
      markNeedsPaint();
    }
  }

  Pen _background;

  /// What it is filled with under the child, with an opaque background; a
  /// new one repaints all of it.
  Pen get background => _background;
  set background(Pen p) {
    if (p != _background) {
      _background = p;
      _penIn = null;
      _fullRepaint = true;
      markNeedsPaint();
    }
  }

  /// Called by each layout with the viewport's extent along [axis] and the
  /// child's (0 without one): what the offset is kept within.
  void Function(int viewport, int content)? onExtents;

  // the largest offset since the last layout
  int _maxOffset = BoxConstraints.unbounded;

  // the id of the background's pen in _penIn
  StyleTable? _penIn;
  var _penId = 0;

  // what is on the surface from the last paint
  var _paintedOffset = 0;
  var _paintedWidth = 0;
  var _paintedHeight = 0;
  var _fullRepaint = true;

  @override
  bool get isRepaintBoundary => true;

  /// Opaque: it fills all of its cells.
  @override
  HitTestBehavior get hitTestBehavior => HitTestBehavior.opaque;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('axis', _axis, defaultValue: Axis.vertical)
      ..add('scrollOffset', _scrollOffset, defaultValue: 0)
      ..add('background', _background, defaultValue: _defaultColors);
  }

  @override
  void invalidatePaintCache() => _fullRepaint = true;

  var _noRoomReported = false;

  /// Logs a warning the first time the viewport is given no cells along
  /// its axis for content that has some, which then shows none of it.
  bool _debugReportNoRoom(int content, int extent, bool vertical) {
    if (extent == 0 && content > 0 && !_noRoomReported) {
      _noRoomReported = true;
      final unit = vertical ? 'rows' : 'columns';
      _warn(
        'A RenderViewport was given 0 $unit for $content $unit of content '
        'and shows none of it: in a ${vertical ? 'Column' : 'Row'} the '
        'children beside it took every one (put it in an Expanded).',
      );
    }
    return true;
  }

  @override
  void performLayout(BoxConstraints c) {
    final vertical = _axis == Axis.vertical;
    final ch = _child;
    var content = 0;
    if (ch == null) {
      width = c.minW;
      height = c.minH;
    } else {
      ch.layout(
        vertical
            ? BoxConstraints(c.minW, c.maxW, 0, BoxConstraints.unbounded)
            : BoxConstraints(0, BoxConstraints.unbounded, c.minH, c.maxH),
        parentUsesSize: true,
      );
      width = c.constrainW(ch.width);
      height = c.constrainH(ch.height);
      content = vertical ? ch.height : ch.width;
    }
    final extent = vertical ? height : width;
    assert(
      _debugReportNoRoom(content, extent, vertical),
      'reports a viewport given no room',
    );
    _maxOffset = _less(content, extent);
    if (_scrollOffset > _maxOffset) {
      _scrollOffset = _maxOffset;
    }
    _place();
    _fullRepaint = true;
    onExtents?.call(extent, content);
  }

  /// Puts the child [scrollOffset] cells before the start.
  void _place() {
    final ch = _child;
    if (ch != null) {
      final vertical = _axis == Axis.vertical;
      ch.parentData
        ..dx = vertical ? 0 : -_scrollOffset
        ..dy = vertical ? -_scrollOffset : 0;
    }
  }

  // what the child asks for

  @override
  int computeMinIntrinsicWidth(int height) =>
      _child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      _child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      _child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    if (!identical(styles, _penIn)) {
      _penIn = styles;
      _penId = styles.pen(_background);
    }
    final pen = _penId;
    assert(_opaqueBackground(ctx, pen), _translucentBoundary);
    // rows [from, to) to paint: all of them, those a scroll exposed, or
    // none when nothing moved
    var from = 0;
    var to = height;
    if (!_fullRepaint && width == _paintedWidth && height == _paintedHeight) {
      final shift = _scrollOffset - _paintedOffset;
      if (shift == 0) {
        to = 0;
      } else if (_axis == Axis.vertical && shift.abs() < height) {
        final (gx, gy) = globalOffset;
        // the surface can move only rows it has: a view partly off it (or
        // cut by an ancestor) paints all that shows instead
        if (canvas.clipContains(gx, gy, gx + width, gy + height)) {
          ctx.surface.scrollRect(gx, gx + width, gy, gy + height, shift);
          RenderObject._shiftUnderlays(
            this,
            gx,
            gx + width,
            gy,
            gy + height,
            shift,
          );
          if (shift > 0) {
            from = height - shift;
          } else {
            to = -shift;
          }
        }
      }
    }
    final ch = _child;
    if (from < to) {
      canvas
        ..save()
        ..clipRect(0, from, width, to - from)
        ..fill(0, from, width, to - from, pen);
      if (ch != null) {
        paintChild(ctx, ch);
      }
      canvas.restore();
    }
    if (to - from < height) {
      // the rows it kept show the boundaries inside it as they were: those
      // marked for paint since repaint on their own, all that is inside
      // painting all of its cells, since they were cut off here
      _paintedIn = 0;
      if (ch != null) {
        _forgetPaint(ch);
      }
    }
    _paintedOffset = _scrollOffset;
    _paintedWidth = width;
    _paintedHeight = height;
    _fullRepaint = false;
  }
}
