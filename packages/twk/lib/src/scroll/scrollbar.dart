/// [Scrollbar]: the track and the thumb of the [Scrollable] inside it, the
/// thumb dragged and the track pressed with the mouse.
library;

import 'package:twk_core/twk_core.dart'
    show
        Axis,
        BoxConstraints,
        ContainerParentDataMixin,
        ContainerRenderObjectMixin,
        PaintContext,
        ParentData,
        PipelineOwner,
        RenderObject;

import '../binding/app_binding.dart';
import '../data/chart_glyphs.dart' show opaque;
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../gestures/mouse.dart';
import '../gestures/selection.dart' show inSelectionArea;
import '../layout/child_list.dart';
import '../style/style.dart';
import 'scrollable.dart';
import 'thumb.dart';

/// When a [Scrollbar] shows its thumb.
enum ScrollbarVisibility {
  /// While there is something to scroll.
  always,

  /// While there is something to scroll, from a move of the scrollable
  /// until [Scrollbar.hideAfter] after the last one, and while the thumb is
  /// dragged.
  onScroll,

  /// Never: the scrollbar takes no room, its child all of it.
  never,
}

/// Shows how far the outermost [Scrollable] inside [child] along [axis] is
/// scrolled, as a thumb on a track beside it, and scrolls it with the
/// mouse.
///
/// The track is a column at the right edge of [child], as tall as it, or
/// along a horizontal axis a row at its bottom, as wide as it; [child] has
/// the rest of the room.
///
/// Its thumb is as long as the window is of the content, a cell at least,
/// and as far along the track as the window is along the content: at its
/// start at the content's start and at its end at the content's end,
/// exactly; of a [Scrollable.reverse] one, whose start is at the bottom
/// (the right), at the end of the track at its start, the track pressed and
/// the thumb dragged as the screen shows it. Both are in eighths of a
/// cell, a cell the thumb covers in part drawn with a block element; in
/// whole cells where the canvas draws block elements two columns wide
/// (they are East Asian ambiguous). Where the extent of the content is an
/// estimate, as a `ListView`'s is where it has not been, so are the length
/// and the place of the thumb.
///
/// Dragging the thumb with the left button scrolls the content as far as
/// the thumb moves, wherever the mouse goes until the release; pressing
/// the track before or after the thumb scrolls a window that way. A press
/// of the bar is its own: a `GestureDetector` around it gets nothing of
/// it. The wheel over the bar scrolls the scrollable as over it.
///
/// [slim] draws the track as a thin line in [trackStyle] (the theme's
/// [ThemeData.faint] by default) and at rest the thumb a heavy one (`│` and
/// `┃`, `─` and `━` across), in whole cells; while the mouse is over the
/// bar or drags its thumb, the thumb as it is by default, the whole cell
/// in eighths, over the line: out of the way of the content until it is
/// reached for.
///
/// [visibility] says when the thumb shows; the track takes its room
/// whether it does or not, unless [ScrollbarVisibility.never]. The thumb is
/// drawn in [style]'s foreground and the track in its background, over the
/// theme's muted text and background. The bar is a repaint boundary: a move
/// of the scrollable that leaves the thumb where it is paints nothing of
/// it.
///
/// A list of a thousand items with a thumb that shows while it scrolls:
///
/// ```dart
/// Scrollbar(
///   visibility: ScrollbarVisibility.onScroll,
///   child: ListView.builder(
///     itemCount: 1000,
///     itemBuilder: (context, index) => Text('item $index'),
///   ),
/// )
/// ```
final class Scrollbar extends StatefulWidget {
  /// A scrollbar along [axis], vertical by default, for the scrollable in
  /// [child]; its thumb shows [ScrollbarVisibility.always] by default, or
  /// as [visibility] says, for [hideAfter] (a second by default) after a
  /// move.
  const Scrollbar({
    required this.child,
    super.key,
    this.axis = Axis.vertical,
    this.visibility = ScrollbarVisibility.always,
    this.hideAfter = const Duration(seconds: 1),
    this.style,
    this.slim = false,
    this.trackStyle,
  });

  /// What it is beside, with the scrollable it shows inside.
  final Widget child;

  /// The axis of the scrollable it shows.
  final Axis axis;

  /// When it shows its thumb.
  final ScrollbarVisibility visibility;

  /// How long the thumb stays after the last move of the scrollable, on
  /// the app's clock, when [visibility] is [ScrollbarVisibility.onScroll].
  final Duration hideAfter;

  /// The thumb's color ([Style.fg]) and the track's ([Style.bg]), over the
  /// theme's [ThemeData.muted] and [ThemeData.background].
  final Style? style;

  /// Whether the bar is a line at rest, the whole cell while the mouse is
  /// over it or drags its thumb.
  final bool slim;

  /// The color of the track's line of a [slim] bar ([Style.fg]);
  /// [ThemeData.faint] when null.
  final Style? trackStyle;

  @override
  State<Scrollbar> createState() => _ScrollbarState();
}

final class _ScrollbarState extends State<Scrollbar> {
  late final _track = _Track(
    AppBinding.maybeOf(context),
    MouseTracker.of(context),
  );

  // the mouse over the bar, which a slim one is wide for
  var _hovered = false;

  @override
  void dispose() {
    _track.dispose();
    super.dispose();
  }

  void _hover(bool over) {
    if (over != _hovered) {
      setState(() => _hovered = over);
    }
  }

  @override
  void didUpdateWidget(Scrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // no longer slim, nothing hears the mouse leave: slim again, not wide
    // where it is not
    if (!widget.slim) {
      _hovered = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final outer = context.dependOnInheritedWidgetOfExactType<ScrollbarScope>();
    final vertical = widget.axis == Axis.vertical;
    final theme = Theme.of(context);
    _track
      ..axis = widget.axis
      ..hideAfter = widget.hideAfter
      ..visibility = widget.visibility;
    return _Frame(
      axis: widget.axis,
      children: [
        ScrollbarScope(
          vertical: vertical ? _track.slot : outer?.vertical,
          horizontal: vertical ? outer?.horizontal : _track.slot,
          child: widget.child,
        ),
        if (widget.visibility != ScrollbarVisibility.never)
          _hoverable(
            Listener(
              onDown: _track.press,
              onDrag: _track.drag,
              onScroll: _track.wheel,
              scrollAxis: widget.axis,
              child: _Bar(
                track: _track,
                axis: widget.axis,
                style: opaque(
                  theme.background
                      .merge(theme.muted)
                      .merge(widget.style ?? const Style()),
                ),
                line: widget.slim ? widget.trackStyle ?? theme.faint : null,
                hovered: _hovered,
              ),
            ),
          ),
      ],
    );
  }

  /// [bar] telling [_hovered] where the bar is slim, which is wide while
  /// the mouse is over it, and giving the pointer the arrow inside a
  /// `SelectionArea`, over the area's I-beam; as it is otherwise, asking
  /// for no motion of the mouse.
  Widget _hoverable(Widget bar) {
    final arrow = inSelectionArea(context);
    return widget.slim || arrow
        ? MouseRegion(
            cursor: arrow ? PointerShape.arrow : null,
            onEnter: widget.slim ? (_) => _hover(true) : null,
            onExit: widget.slim ? (_) => _hover(false) : null,
            child: bar,
          )
        : bar;
  }
}

/// Where the thumb of a [Scrollbar] is on its track: it follows the
/// position the scrollable puts in [slot], and moves it as the thumb is
/// dragged and the track pressed. Its listener, the bar, is told when the
/// thumb it painted last is not where it would be now.
final class _Track with ChangeNotifier {
  _Track(this.binding, this.mouse) {
    slot.addListener(_follow);
  }

  /// The app on whose clock the thumb hides.
  final AppBinding? binding;

  /// The app's mouse, which tells when a drag ends.
  final MouseTracker? mouse;

  /// Where the scrollable puts its position ([ScrollbarScope]).
  final slot = ValueNotifier<ScrollPosition?>(null);

  /// The axis of the bar.
  Axis axis = Axis.vertical;

  /// See [Scrollbar.hideAfter].
  Duration hideAfter = Duration.zero;

  /// See [Scrollbar.visibility].
  ScrollbarVisibility get visibility => _visibility;
  ScrollbarVisibility _visibility = ScrollbarVisibility.always;
  set visibility(ScrollbarVisibility v) {
    if (v != _visibility) {
      _visibility = v;
      _changed();
    }
  }

  ScrollPosition? _position;

  // the offset the position had last, once it had extents
  int? _offset;

  // the cells of the bar along its axis and the steps of a cell, as it
  // painted last; the thumb it painted, its start and end in steps, -1 for
  // none
  var _length = 0;
  var _steps = 8;
  var _paintedStart = -1;
  var _paintedEnd = -1;

  // shown after a move of the scrollable until _hideAt on the app's clock,
  // when the frame callback _hiding hides it
  var _showing = false;
  Duration _hideAt = Duration.zero;
  int? _hiding;

  // a drag of the thumb: the cell along the bar it was pressed at and
  // where the thumb started then, in steps; null while there is none
  int? _grabAt;
  var _grabStart = 0;

  /// Whether the thumb is being dragged.
  bool get dragging => _grabAt != null;

  void _follow() {
    final p = slot.value;
    if (identical(p, _position)) {
      return;
    }
    _position?.removeListener(_moved);
    _position = p?..addListener(_moved);
    _offset = p != null && p.hasExtents ? p.offset : null;
    _grabAt = null;
    _changed();
  }

  void _moved() {
    final p = _position!;
    if (p.hasExtents) {
      final was = _offset;
      _offset = p.offset;
      if (was != null &&
          was != p.offset &&
          _visibility == ScrollbarVisibility.onScroll) {
        _show();
      }
    }
    _changed();
  }

  bool get _shown => switch (_visibility) {
    ScrollbarVisibility.always => true,
    ScrollbarVisibility.onScroll => _showing || _grabAt != null,
    ScrollbarVisibility.never => false,
  };

  /// The thumb on a track of [length] cells of [steps] steps each, its
  /// start and end in steps; null while there is nothing to scroll.
  (int, int)? _thumb(int length, int steps) {
    final p = _position;
    if (p == null || !p.hasExtents || p.maxOffset <= 0 || length <= 0) {
      return null;
    }
    final all = length * steps;
    final max = p.maxOffset;
    var size = _ratio(all, p.viewportExtent, max + p.viewportExtent);
    if (size < steps) {
      size = steps;
    }
    final offset = p.offset < 0 ? 0 : (p.offset > max ? max : p.offset);
    // along the bar: in reverse, the cells after the window are above it
    final start = _ratio(all - size, p.reverse ? max - offset : offset, max);
    return (start, start + size);
  }

  /// [a] × [b] / [c], rounded.
  static int _ratio(int a, int b, int c) => (2 * a * b + c) ~/ (2 * c);

  /// The thumb the bar paints on its [length] cells of [steps] steps each,
  /// as [_thumb] gives it; null while it is not shown.
  (int, int)? paint(int length, int steps) {
    _length = length;
    _steps = steps;
    final thumb = _shown ? _thumb(length, steps) : null;
    _paintedStart = thumb?.$1 ?? -1;
    _paintedEnd = thumb?.$2 ?? -1;
    return thumb;
  }

  /// Tells the bar when the thumb it painted is not the one it would paint
  /// now.
  void _changed() {
    final thumb = _shown ? _thumb(_length, _steps) : null;
    if ((thumb?.$1 ?? -1) != _paintedStart ||
        (thumb?.$2 ?? -1) != _paintedEnd) {
      notifyListeners();
    }
  }

  void _show() {
    _showing = true;
    final b = binding;
    if (b == null) {
      return;
    }
    _hideAt = b.twkApp.clock.elapsed + hideAfter;
    _hiding ??= b.scheduleFrameCallback(_hide, at: _hideAt);
  }

  void _hide(Duration time) {
    _hiding = null;
    if (time < _hideAt) {
      _hiding = binding!.scheduleFrameCallback(_hide, at: _hideAt);
      return;
    }
    _showing = false;
    _changed();
  }

  /// A press of the bar: the left button on the thumb grabs it, before or
  /// after it scrolls a window that way.
  void press(PointerEvent event) {
    final p = _position;
    final thumb = _thumb(_length, _steps);
    if (event.button != 0 || p == null || thumb == null) {
      return;
    }
    if (mouse case final mouse?) {
      takeDrag(mouse, 0);
    }
    final at = axis == Axis.vertical ? event.y : event.x;
    final (start, end) = thumb;
    final page = p.reverse ? -p.viewportExtent : p.viewportExtent;
    if ((at + 1) * _steps <= start) {
      p.jumpTo(p.offset - page);
    } else if (at * _steps >= end) {
      p.jumpTo(p.offset + page);
    } else {
      _grabAt = at;
      _grabStart = start;
      mouse?.whenReleased(_released);
      _changed();
    }
  }

  /// The mouse moved with the thumb grabbed: the thumb goes as many cells
  /// as the mouse, and the content with it.
  void drag(PointerEvent event) {
    final p = _position;
    final grabAt = _grabAt;
    final thumb = _thumb(_length, _steps);
    if (p == null || grabAt == null || thumb == null) {
      return;
    }
    final room = _length * _steps - (thumb.$2 - thumb.$1);
    if (room <= 0) {
      return;
    }
    final at = axis == Axis.vertical ? event.y : event.x;
    final start = _grabStart + (at - grabAt) * _steps;
    final along = _ratio(p.maxOffset, start < 0 ? 0 : start, room);
    p.jumpTo(p.reverse ? p.maxOffset - along : along);
  }

  void _released() {
    if (_grabAt != null) {
      _grabAt = null;
      if (_visibility == ScrollbarVisibility.onScroll) {
        _show();
      }
      // the thumb where it was, but a slim bar no longer wide
      notifyListeners();
    }
  }

  /// The wheel over the bar: it scrolls the scrollable.
  void wheel(PointerEvent event) {
    final p = _position;
    if (p != null) {
      scrollByWheel(p, event);
    }
  }

  @override
  void dispose() {
    final hiding = _hiding;
    if (hiding != null) {
      binding?.cancelFrameCallback(hiding);
    }
    slot.removeListener(_follow);
    _position?.removeListener(_moved);
    _position = null;
    super.dispose();
  }
}

/// The child of a [Scrollbar] and its bar, side by side.
final class _Frame extends MultiChildRenderObjectWidget {
  const _Frame({required this.axis, super.children});

  final Axis axis;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  _RenderFrame createRenderObject(BuildContext context) => _RenderFrame(axis);

  @override
  void updateRenderObject(BuildContext context, _RenderFrame renderObject) =>
      renderObject.axis = axis;
}

final class _FrameData extends ParentData with ContainerParentDataMixin {}

/// What a [_Frame] lays out and paints: its first child within the
/// constraints but for a cell across [axis], and its second, the bar, in
/// that cell at the far edge, along all of the first.
final class _RenderFrame extends RenderObject
    with ContainerRenderObjectMixin<_FrameData> {
  _RenderFrame(this._axis);

  Axis _axis;
  Axis get axis => _axis;
  set axis(Axis a) {
    if (a != _axis) {
      _axis = a;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _FrameData) {
      child.parentData = _FrameData();
    }
  }

  // the cells across the axis the bar takes
  int get _bar => childCount > 1 ? 1 : 0;

  bool get _vertical => _axis == Axis.vertical;

  /// [extent] less the bar's cells, unbounded as it is.
  int _less(int extent) => extent >= BoxConstraints.unbounded
      ? extent
      : (extent > _bar ? extent - _bar : 0);

  @override
  int computeMinIntrinsicWidth(int height) {
    final child = firstChild;
    if (child == null) {
      return 0;
    }
    return _vertical
        ? child.getMinIntrinsicWidth(height) + _bar
        : child.getMinIntrinsicWidth(_less(height));
  }

  @override
  int computeMaxIntrinsicWidth(int height) {
    final child = firstChild;
    if (child == null) {
      return 0;
    }
    return _vertical
        ? child.getMaxIntrinsicWidth(height) + _bar
        : child.getMaxIntrinsicWidth(_less(height));
  }

  @override
  int computeMinIntrinsicHeight(int width) {
    final child = firstChild;
    if (child == null) {
      return 0;
    }
    return _vertical
        ? child.getMinIntrinsicHeight(_less(width))
        : child.getMinIntrinsicHeight(width) + _bar;
  }

  @override
  int computeMaxIntrinsicHeight(int width) {
    final child = firstChild;
    if (child == null) {
      return 0;
    }
    return _vertical
        ? child.getMaxIntrinsicHeight(_less(width))
        : child.getMaxIntrinsicHeight(width) + _bar;
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = firstChild;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    final bar = childAfter(child);
    child.parentData
      ..dx = 0
      ..dy = 0;
    if (_vertical) {
      child.layout(
        BoxConstraints(_less(c.minW), _less(c.maxW), c.minH, c.maxH),
        parentUsesSize: true,
      );
      width = c.constrainW(child.width + _bar);
      height = child.height;
      if (bar != null) {
        final thick = width - child.width < _bar ? width - child.width : _bar;
        bar.layout(BoxConstraints.tight(thick, height));
        bar.parentData
          ..dx = width - thick
          ..dy = 0;
      }
    } else {
      child.layout(
        BoxConstraints(c.minW, c.maxW, _less(c.minH), _less(c.maxH)),
        parentUsesSize: true,
      );
      width = child.width;
      height = c.constrainH(child.height + _bar);
      if (bar != null) {
        final thick = height - child.height < _bar
            ? height - child.height
            : _bar;
        bar.layout(BoxConstraints.tight(width, thick));
        bar.parentData
          ..dx = 0
          ..dy = height - thick;
      }
    }
  }

  @override
  void paint(PaintContext ctx) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (child.width > 0 && child.height > 0) {
        paintChild(ctx, child);
      }
    }
  }
}

/// The track and the thumb of a [Scrollbar], where [track] says.
final class _Bar extends LeafRenderObjectWidget {
  const _Bar({
    required this.track,
    required this.axis,
    required this.style,
    required this.line,
    required this.hovered,
  });

  final _Track track;
  final Axis axis;

  /// The thumb's color and the track's, opaque.
  final Style style;

  /// The color of the track's line of a slim bar; null for a bar that is
  /// not slim.
  final Style? line;

  /// Whether the mouse is over the bar.
  final bool hovered;

  @override
  _RenderBar createRenderObject(BuildContext context) =>
      _RenderBar(track, axis, style)
        ..line = line
        ..hovered = hovered;

  @override
  void updateRenderObject(BuildContext context, _RenderBar renderObject) {
    renderObject
      ..axis = axis
      ..style = style
      ..line = line
      ..hovered = hovered;
  }
}

/// What a [_Bar] lays out and paints: as big as the constraints let it be,
/// the thumb where its track says, painted again when the track says it is
/// not where it was.
final class _RenderBar extends RenderObject {
  _RenderBar(this._track, this._axis, this._style);

  final _Track _track;

  Axis _axis;
  Axis get axis => _axis;
  set axis(Axis a) {
    if (a != _axis) {
      _axis = a;
      markNeedsPaint();
    }
  }

  Style _style;
  Style get style => _style;
  set style(Style s) {
    if (s != _style) {
      _style = s;
      markNeedsPaint();
    }
  }

  Style? _line;
  Style? get line => _line;
  set line(Style? s) {
    if (s != _line) {
      _line = s;
      markNeedsPaint();
    }
  }

  var _hovered = false;
  bool get hovered => _hovered;
  set hovered(bool h) {
    if (h != _hovered) {
      _hovered = h;
      markNeedsPaint();
    }
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  void attach(PipelineOwner o) {
    super.attach(o);
    _track.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _track.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.maxH < BoxConstraints.unbounded ? c.maxH : c.minH;
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final pen = _style.penIn(canvas.styles);
    canvas.fill(0, 0, width, height, pen);
    final vertical = _axis == Axis.vertical;
    // slim: the track a line, under the mouse too; at rest the thumb a
    // heavier one in whole cells, wide the whole cell in eighths
    final line = _line;
    final wide = line == null || _hovered || _track.dragging;
    if (line != null) {
      canvas.fill(
        0,
        0,
        width,
        height,
        _style.merge(line).penIn(canvas.styles),
        vertical ? 0x2502 : 0x2500,
      );
    }
    final steps = wide ? thumbSteps(canvas, vertical: vertical) : 1;
    final thumb = _track.paint(vertical ? height : width, steps);
    if (thumb == null) {
      return;
    }
    final (start, end) = thumb;
    paintThumb(
      canvas,
      _style,
      start: start,
      end: end,
      steps: steps,
      vertical: vertical,
      thickness: vertical ? width : height,
      glyph: wide ? null : (vertical ? 0x2503 : 0x2501),
    );
  }
}
