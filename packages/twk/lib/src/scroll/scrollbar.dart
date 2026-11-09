/// [Scrollbar]: the track and the thumb of the [Scrollable] inside it, the
/// thumb dragged and the track pressed with the mouse.
library;

import 'package:meta/meta.dart' show internal;
import 'package:twk_core/twk_core.dart'
    show
        Axis,
        BorderType,
        BoxConstraints,
        Canvas,
        ContainerParentDataMixin,
        ContainerRenderObjectMixin,
        PaintContext,
        ParentData,
        PipelineOwner,
        RenderObject;

import '../binding/app_binding.dart';
import '../data/chart_glyphs.dart' show opaque, overUnder;
import '../foundation/change_notifier.dart';
import '../foundation/listenable_builder.dart' show ValueListenableBuilder;
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../gestures/mouse.dart';
import '../gestures/selection.dart' show inSelectionArea;
import '../layout/child_list.dart';
import '../style/style.dart';
import 'scrollable.dart';
import 'thumb.dart';

// how long a thumb stays after a move, by default
const _timeToFade = Duration(seconds: 1);

/// When a [Scrollbar] shows its thumb.
enum ScrollbarVisibility {
  /// While there is something to scroll.
  always,

  /// While there is something to scroll, from a move of the scrollable
  /// until [Scrollbar.timeToFade] after the last one, and while the thumb is
  /// dragged.
  onScroll,

  /// Never: the scrollbar takes no room, its child all of it.
  never,
}

/// Shows how far the outermost [Scrollable] inside [child] is scrolled, as
/// a thumb on a track beside it, and scrolls it with the mouse. It is the
/// outermost of either axis, or the outermost along [axis] where that is
/// given, as for content that scrolls both ways, one bar to each.
///
/// The track is a column at the right edge of [child], as tall as it, for
/// a vertical scrollable, or for a horizontal one a row at its bottom, as
/// wide as it; [child] has the rest of the room. Where there is no
/// scrollable inside, [axis] says, else the track is a column.
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
/// reached for. The line is drawn only while there is something to
/// scroll, so a list that fits has a blank column beside it, not a second
/// line beside a panel's border.
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
  /// A scrollbar for the scrollable in [child], along its axis or [axis];
  /// its thumb shows [ScrollbarVisibility.always] by default, or as
  /// [visibility] says, for [timeToFade] (a second by default) after a move.
  const Scrollbar({
    required this.child,
    super.key,
    this.axis,
    this.visibility = ScrollbarVisibility.always,
    this.timeToFade = _timeToFade,
    this.style,
    this.slim = false,
    this.trackStyle,
  });

  /// What it is beside, with the scrollable it shows inside.
  final Widget child;

  /// The axis of the scrollable it shows; null for the outermost of either
  /// axis. Of content that scrolls along both, a bar to each is a bar with
  /// each axis given.
  final Axis? axis;

  /// When it shows its thumb.
  final ScrollbarVisibility visibility;

  /// How long the thumb stays after the last move of the scrollable, on
  /// the app's clock, when [visibility] is [ScrollbarVisibility.onScroll].
  final Duration timeToFade;

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
    final theme = Theme.of(context);
    _track
      ..declared = widget.axis
      ..timeToFade = widget.timeToFade
      ..visibility = widget.visibility;
    final look = (
      opaque(
        theme.background
            .merge(theme.muted)
            .merge(widget.style ?? const Style()),
      ),
      widget.slim ? widget.trackStyle ?? theme.faint : null,
    );
    return _Frame(
      track: _track,
      children: [
        ScrollbarScope.over(outer, widget.axis, _track.slot, widget.child),
        if (widget.visibility != ScrollbarVisibility.never)
          _hoverable(
            ValueListenableBuilder<Axis>(
              valueListenable: _track.axisOf,
              builder: (context, axis, _) => Listener(
                onPointerDown: _track.press,
                onPointerMove: _track.drag,
                onScroll: _track.wheel,
                scrollAxis: axis,
                child: _Bar(
                  track: _track,
                  vertical: look,
                  horizontal: look,
                  hovered: _hovered,
                ),
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

/// The bar of the scrollable inside what [builder] builds, drawn on that
/// widget's border along the axis of the outermost scrollable in it (its
/// right side, or its bottom): `Box`'s `scrollbar`. [builder] is given what
/// puts the scrollable's position within reach of the bar
/// ([ScrollbarScope]), to wrap the box's child in. The bar covers the
/// border's cells but [inset] at its ends (the corners) and is drawn in
/// the border's own style, [right] or [bottom]: the border's line where
/// there is nothing to scroll, and over it the thumb, a heavier line (`┃`,
/// `━`) at rest, the whole cell in eighths while the mouse is over it or
/// drags it, in [thumb]. It is dragged and pressed as a [Scrollbar]'s is.
@internal
final class BorderScrollbar extends StatefulWidget {
  /// A bar on the border of what [builder] builds.
  const BorderScrollbar({
    required this.right,
    required this.bottom,
    required this.thumb,
    required this.inset,
    required this.builder,
    this.bottomTitled = false,
    this.axis,
    this.visibility = ScrollbarVisibility.always,
    this.timeToFade = _timeToFade,
    this.type,
    super.key,
  });

  /// The border's lines: the track is its straight line, the thumb a
  /// heavier one of its own, or `#` for [BorderType.ascii]; null for the
  /// theme's ([Glyphs.lines]).
  final BorderType? type;

  /// The axis of the scrollable it shows; null for the outermost of either
  /// axis.
  final Axis? axis;

  /// When it shows its thumb.
  final ScrollbarVisibility visibility;

  /// See [Scrollbar.timeToFade].
  final Duration timeToFade;

  /// The style of the border's right side, opaque; null where it has none.
  final Style? right;

  /// The style of the border's bottom, opaque; null where it has none.
  final Style? bottom;

  /// Whether the bottom edge has a title, which a bar along it would cover.
  final bool bottomTitled;

  /// The thumb's color ([Style.fg]) over the border's.
  final Style thumb;

  /// The border's cells at the start and the end of the bar it leaves,
  /// along the right side and along the bottom.
  final ((int, int), (int, int)) inset;

  /// The widget with the border, its child wrapped by the function given.
  final Widget Function(BuildContext context, Widget Function(Widget) scope)
  builder;

  @override
  State<BorderScrollbar> createState() => _BorderScrollbarState();
}

final class _BorderScrollbarState extends State<BorderScrollbar> {
  late final _track = _Track(
    AppBinding.maybeOf(context),
    MouseTracker.of(context),
  );

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
  Widget build(BuildContext context) {
    final outer = context.dependOnInheritedWidgetOfExactType<ScrollbarScope>();
    _track
      ..declared = widget.axis
      ..timeToFade = widget.timeToFade
      ..visibility = widget.visibility;
    // the foreground opaque, the background the box's or none: what is
    // under the bar shows where the box gives none
    _Look look(Style? side) {
      final line = overUnder(side ?? const Style());
      return (line.merge(widget.thumb), line);
    }

    // the box as big as it would be on its own, the bar over its side
    return _BorderFrame(
      track: _track,
      inset: widget.inset,
      sides: (widget.right != null, widget.bottom != null),
      bottomTitled: widget.bottomTitled,
      children: [
        widget.builder(
          context,
          (child) =>
              ScrollbarScope.over(outer, widget.axis, _track.slot, child),
        ),
        MouseRegion(
          cursor: inSelectionArea(context) ? PointerShape.arrow : null,
          onEnter: (_) => _hover(true),
          onExit: (_) => _hover(false),
          child: ValueListenableBuilder<Axis>(
            valueListenable: _track.axisOf,
            builder: (context, axis, _) => Listener(
              onPointerDown: _track.press,
              onPointerMove: _track.drag,
              onScroll: _track.wheel,
              scrollAxis: axis,
              child: _Bar(
                track: _track,
                vertical: look(widget.right),
                horizontal: look(widget.bottom),
                hovered: _hovered,
                onBorder: true,
                borderType: Theme.of(context).glyphs.borderOf(widget.type),
              ),
            ),
          ),
        ),
      ],
    );
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

  /// The axis of the bar, which its frame lays it out by: [declared], else
  /// the axis of the scrollable in [slot], vertical while there is none.
  Axis get axis => axisOf.value;

  /// [axis], to listen to.
  final ValueNotifier<Axis> axisOf = ValueNotifier(Axis.vertical);

  /// The axis the bar is given; null for the scrollable's.
  Axis? get declared => _declared;
  Axis? _declared;
  set declared(Axis? a) {
    _declared = a;
    _axisNow();
  }

  /// Whether a scrollable is in [slot].
  bool get known => _position != null;

  void _axisNow() {
    axisOf.value = _declared ?? _position?.axis ?? Axis.vertical;
  }

  /// See [Scrollbar.timeToFade].
  Duration timeToFade = Duration.zero;

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
  // none, and whether there was something to scroll then
  var _length = 0;
  var _steps = 8;
  var _paintedStart = -1;
  var _paintedEnd = -1;
  var _paintedScrolls = false;

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
    _offset = p != null && p.hasExtents ? p.pixels : null;
    _grabAt = null;
    _axisNow();
    _changed();
  }

  void _moved() {
    final p = _position!;
    if (p.hasExtents) {
      final was = _offset;
      _offset = p.pixels;
      if (was != null &&
          was != p.pixels &&
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
    if (p == null || !p.hasExtents || p.maxScrollExtent <= 0 || length <= 0) {
      return null;
    }
    final all = length * steps;
    final max = p.maxScrollExtent;
    var size = _ratio(all, p.viewportDimension, max + p.viewportDimension);
    if (size < steps) {
      size = steps;
    }
    final offset = p.pixels < 0 ? 0 : (p.pixels > max ? max : p.pixels);
    // along the bar: in reverse, the cells after the window are above it
    final start = _ratio(all - size, p.reverse ? max - offset : offset, max);
    return (start, start + size);
  }

  /// Whether there is something to scroll: the content is longer than the
  /// window.
  bool get scrolls {
    final p = _position;
    return p != null && p.hasExtents && p.maxScrollExtent > 0;
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
    _paintedScrolls = scrolls;
    return thumb;
  }

  /// Tells the bar when the thumb it painted is not the one it would paint
  /// now, or there came to be something to scroll or ceased to be (a slim
  /// bar's line).
  void _changed() {
    final thumb = _shown ? _thumb(_length, _steps) : null;
    if ((thumb?.$1 ?? -1) != _paintedStart ||
        (thumb?.$2 ?? -1) != _paintedEnd ||
        scrolls != _paintedScrolls) {
      notifyListeners();
    }
  }

  void _show() {
    _showing = true;
    final b = binding;
    if (b == null) {
      return;
    }
    _hideAt = b.twkApp.clock.elapsed + timeToFade;
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
    final page = p.reverse ? -p.viewportDimension : p.viewportDimension;
    if ((at + 1) * _steps <= start) {
      p.jumpTo(p.pixels - page);
    } else if (at * _steps >= end) {
      p.jumpTo(p.pixels + page);
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
    final along = _ratio(p.maxScrollExtent, start < 0 ? 0 : start, room);
    p.jumpTo(p.reverse ? p.maxScrollExtent - along : along);
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
    axisOf.dispose();
    _position?.removeListener(_moved);
    _position = null;
    super.dispose();
  }
}

/// The child of a [Scrollbar] and its bar, side by side.
final class _Frame extends MultiChildRenderObjectWidget {
  const _Frame({required this.track, super.children});

  final _Track track;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  _RenderFrame createRenderObject(BuildContext context) => _RenderFrame(track);

  @override
  void updateRenderObject(BuildContext context, _RenderFrame renderObject) {}
}

final class _FrameData extends ParentData with ContainerParentDataMixin {}

/// What a [_Frame] lays out and paints: its first child within the
/// constraints but for a cell across the [_track]'s axis, and its second,
/// the bar, in that cell at the far edge, along all of the first. The axis
/// is known when the scrollable inside is built, before the layout, and a
/// change of it lays out again.
final class _RenderFrame extends RenderObject
    with ContainerRenderObjectMixin<_FrameData> {
  _RenderFrame(this._track);

  final _Track _track;

  @override
  void attach(PipelineOwner o) {
    super.attach(o);
    _track.axisOf.addListener(_axisChanged);
  }

  @override
  void detach() {
    _track.axisOf.removeListener(_axisChanged);
    super.detach();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _FrameData) {
      child.parentData = _FrameData();
    }
  }

  // the cells across the axis the bar takes
  int get _bar => childCount > 1 ? 1 : 0;

  bool get _vertical => _track.axis == Axis.vertical;

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

  // The axis changes while this frame lays its child out (a scrollable first
  // built in a LayoutBuilder): the layout in progress reads the axis after
  // the child, so it takes the change in, and a mark would be lost with it.
  var _laying = false;

  void _axisChanged() {
    if (!_laying) {
      markNeedsLayout();
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    _laying = true;
    try {
      _layoutFrame(c);
    } finally {
      _laying = false;
    }
  }

  void _layoutFrame(BoxConstraints c) {
    final child = firstChild;
    if (child == null) {
      width = c.minWidth;
      height = c.minHeight;
      return;
    }
    // a scrollable first built while the child is laid out (in a
    // LayoutBuilder) tells its axis then: the child with the room that axis
    // leaves it, again
    final vertical = _vertical;
    _layout(c, child, vertical: vertical);
    if (_vertical != vertical) {
      _layout(c, child, vertical: !vertical);
    }
  }

  void _layout(
    BoxConstraints c,
    RenderObject child, {
    required bool vertical,
  }) {
    final bar = childAfter(child);
    child.parentData
      ..dx = 0
      ..dy = 0;
    if (vertical) {
      child.layout(
        BoxConstraints(
          minWidth: _less(c.minWidth),
          maxWidth: _less(c.maxWidth),
          minHeight: c.minHeight,
          maxHeight: c.maxHeight,
        ),
        parentUsesSize: true,
      );
      width = c.constrainWidth(child.width + _bar);
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
        BoxConstraints(
          minWidth: c.minWidth,
          maxWidth: c.maxWidth,
          minHeight: _less(c.minHeight),
          maxHeight: _less(c.maxHeight),
        ),
        parentUsesSize: true,
      );
      width = child.width;
      height = c.constrainHeight(child.height + _bar);
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

/// The box of a [BorderScrollbar] and its bar: the box as big as it would
/// be on its own, the bar over its right side or its bottom, by the axis
/// of the track.
final class _BorderFrame extends MultiChildRenderObjectWidget {
  const _BorderFrame({
    required this.track,
    required this.inset,
    required this.sides,
    required this.bottomTitled,
    super.children,
  });

  final _Track track;
  final ((int, int), (int, int)) inset;

  /// Whether the border has a right side and a bottom.
  final (bool, bool) sides;
  final bool bottomTitled;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  _RenderBorderFrame createRenderObject(BuildContext context) =>
      _RenderBorderFrame(track, inset, sides, bottomTitled);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBorderFrame renderObject,
  ) {
    renderObject
      ..inset = inset
      ..sides = sides
      ..bottomTitled = bottomTitled;
  }
}

/// What a [_BorderFrame] lays out and paints. The axis is known when the
/// scrollable inside is built, before the layout, and a change of it lays
/// out again. Where there is a scrollable, the border has to have the side
/// its bar is on, and a bottom bar cannot share its edge with a title.
final class _RenderBorderFrame extends RenderObject
    with ContainerRenderObjectMixin<_FrameData> {
  _RenderBorderFrame(this._track, this._inset, this._sides, this._titled);

  final _Track _track;

  ((int, int), (int, int)) _inset;
  ((int, int), (int, int)) get inset => _inset;
  set inset(((int, int), (int, int)) i) {
    if (i != _inset) {
      _inset = i;
      markNeedsLayout();
    }
  }

  (bool, bool) _sides;
  (bool, bool) get sides => _sides;
  set sides((bool, bool) s) {
    if (s != _sides) {
      _sides = s;
      markNeedsLayout();
    }
  }

  bool _titled;
  bool get bottomTitled => _titled;
  set bottomTitled(bool t) {
    if (t != _titled) {
      _titled = t;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _FrameData) {
      child.parentData = _FrameData();
    }
  }

  @override
  void attach(PipelineOwner o) {
    super.attach(o);
    _track.axisOf.addListener(_axisChanged);
  }

  @override
  void detach() {
    _track.axisOf.removeListener(_axisChanged);
    super.detach();
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      firstChild?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      firstChild?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      firstChild?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      firstChild?.getMaxIntrinsicHeight(width) ?? 0;

  // The axis changes while this frame lays its child out (a scrollable first
  // built in a LayoutBuilder): the layout in progress reads the axis after
  // the child, so it takes the change in, and a mark would be lost with it.
  var _laying = false;

  void _axisChanged() {
    if (!_laying) {
      markNeedsLayout();
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    _laying = true;
    try {
      _layoutFrame(c);
    } finally {
      _laying = false;
    }
  }

  void _layoutFrame(BoxConstraints c) {
    final child = firstChild;
    if (child == null) {
      width = c.minWidth;
      height = c.minHeight;
      return;
    }
    child.parentData
      ..dx = 0
      ..dy = 0;
    child.layout(c, parentUsesSize: true);
    width = child.width;
    height = child.height;
    final bar = childAfter(child);
    if (bar == null) {
      return;
    }
    final vertical = _track.axis == Axis.vertical;
    assert(
      !_track.known || (vertical ? _sides.$1 : _sides.$2),
      vertical
          ? 'a scrollbar on a side the border has: the right, for a '
                'vertical scrollable'
          : 'a scrollbar on a side the border has: the bottom, for a '
                'horizontal scrollable',
    );
    assert(
      !_track.known || vertical || !_titled,
      'a horizontal scrollbar on the bottom border, which has a title: '
      'the bar would cover it',
    );
    if (!(vertical ? _sides.$1 : _sides.$2)) {
      bar.layout(const BoxConstraints.tight(0, 0));
      return;
    }
    final (start, end) = vertical ? _inset.$1 : _inset.$2;
    final along = (vertical ? height : width) - start - end;
    final length = along > 0 ? along : 0;
    final thick = (vertical ? width : height) > 0 ? 1 : 0;
    if (vertical) {
      bar.layout(BoxConstraints.tight(thick, length));
      bar.parentData
        ..dx = width - thick
        ..dy = start;
    } else {
      bar.layout(BoxConstraints.tight(length, thick));
      bar.parentData
        ..dx = start
        ..dy = height - thick;
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

/// The thumb's color and the track's, opaque, and the color of the track's
/// line of a slim bar, null for a bar that is not slim.
typedef _Look = (Style style, Style? line);

/// The track and the thumb of a [Scrollbar], where [track] says, as
/// [vertical] or [horizontal] says by the track's axis.
final class _Bar extends LeafRenderObjectWidget {
  const _Bar({
    required this.track,
    required this.vertical,
    required this.horizontal,
    required this.hovered,
    this.onBorder = false,
    this.borderType,
  });

  final _Track track;

  /// How the bar looks along a vertical axis.
  final _Look vertical;

  /// How the bar looks along a horizontal axis.
  final _Look horizontal;

  /// Whether the mouse is over the bar.
  final bool hovered;

  /// Whether the bar is drawn on a border ([BorderScrollbar]): its line
  /// always, over the cells under it, which it does not fill.
  final bool onBorder;

  /// The lines of the border the bar is on ([onBorder]).
  final BorderType? borderType;

  @override
  _RenderBar createRenderObject(BuildContext context) =>
      _RenderBar(track, vertical, horizontal, onBorder: onBorder)
        ..borderType = borderType
        ..glyphs = Theme.of(context).glyphs
        ..hovered = hovered;

  @override
  void updateRenderObject(BuildContext context, _RenderBar renderObject) {
    renderObject
      ..vertical = vertical
      ..horizontal = horizontal
      ..borderType = borderType
      ..glyphs = Theme.of(context).glyphs
      ..hovered = hovered;
  }
}

/// What a [_Bar] lays out and paints: as big as the constraints let it be,
/// the thumb where its track says, painted again when the track says it is
/// not where it was.
final class _RenderBar extends RenderObject {
  _RenderBar(
    this._track,
    this._vertical,
    this._horizontal, {
    required this._onBorder,
  });

  final _Track _track;

  // a bar on a border, which the bar never stops being
  final bool _onBorder;

  _Look _vertical;
  _Look get vertical => _vertical;
  set vertical(_Look l) {
    if (l != _vertical) {
      _vertical = l;
      markNeedsPaint();
    }
  }

  _Look _horizontal;
  _Look get horizontal => _horizontal;
  set horizontal(_Look l) {
    if (l != _horizontal) {
      _horizontal = l;
      markNeedsPaint();
    }
  }

  BorderType? _borderType;
  BorderType? get borderType => _borderType;
  set borderType(BorderType? t) {
    if (t != _borderType) {
      _borderType = t;
      markNeedsPaint();
    }
  }

  // a bar on a border keeps the cells' background under it
  @override
  bool get keepsUnderlay => _onBorder;

  Glyphs _glyphs = Glyphs.unicode;
  Glyphs get glyphs => _glyphs;
  set glyphs(Glyphs g) {
    if (g != _glyphs) {
      _glyphs = g;
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
    width = c.maxWidth < BoxConstraints.unbounded ? c.maxWidth : c.minWidth;
    height = c.maxHeight < BoxConstraints.unbounded ? c.maxHeight : c.minHeight;
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final vertical = _track.axis == Axis.vertical;
    final (style, line) = vertical ? _vertical : _horizontal;
    final marks = ThemeMarks.ofObject(this, canvas.segmenter);
    if (!_onBorder) {
      canvas.fill(0, 0, width, height, style.penIn(canvas.styles));
    }
    // slim: the track a line while there is something to scroll, under the
    // mouse too; at rest the thumb a heavier one in whole cells, wide the
    // whole cell in eighths
    final wide = line == null || _hovered || _track.dragging;
    final type = _onBorder ? _borderType : null;
    if (line != null && (_onBorder || _track.scrolls)) {
      canvas.fill(
        0,
        0,
        width,
        height,
        style.merge(line).penIn(canvas.styles),
        type != null
            ? marks.line(type, vertical: vertical, glyphs: _glyphs)
            : marks.cell(
                vertical ? Marks.trackVertical : Marks.trackHorizontal,
                _glyphs,
              )!,
      );
    }
    final eighths = wide && _glyphs.partialBlocks && type != BorderType.ascii;
    final steps = eighths ? thumbSteps(canvas, vertical: vertical) : 1;
    final thumb = _track.paint(vertical ? height : width, steps);
    if (thumb == null) {
      return;
    }
    final (start, end) = thumb;
    paintThumb(
      canvas,
      style,
      start: start,
      end: end,
      steps: steps,
      vertical: vertical,
      thickness: vertical ? width : height,
      glyph: eighths
          ? null
          : type != null
          ? _borderThumbRune(canvas, type, vertical: vertical)
          : marks.cell(
              vertical ? Marks.thumbVertical : Marks.thumbHorizontal,
              _glyphs,
            ),
    );
  }

  // the thumb: a heavier line than the border's, `#` on ascii's
  int _borderThumbRune(
    Canvas canvas,
    BorderType type, {
    required bool vertical,
  }) {
    if (type == BorderType.ascii) {
      return 0x23;
    }
    final heavy = type == BorderType.heavy;
    final cp = heavy
        ? 0x2588
        : BorderType.heavy.glyph(
            up: vertical,
            down: vertical,
            left: !vertical,
            right: !vertical,
          );
    return ThemeMarks.ofObject(this, canvas.segmenter).fixed(cp, 0x23);
  }
}
