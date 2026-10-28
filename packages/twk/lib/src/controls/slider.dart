/// A value chosen along a track: [Slider].
library;

import 'package:twk_core/twk_core.dart'
    show BorderType, BoxConstraints, PaintContext, RenderObject;

import '../data/chart_glyphs.dart';
import '../focus/focus.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart' show takeDrag;
import '../gestures/mouse.dart';
import '../scroll/thumb.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import 'pressable.dart';

/// A value from [min] to [max] chosen along a track, by the keys or by
/// dragging its thumb.
///
/// The track is a line with a thumb a cell wide on it, as far along as
/// [value] is from [min] to [max] (at the start for [min], at the end for
/// [max]), the line before the thumb in its color. The thumb is placed in
/// eighths of a cell, a cell it covers in part drawn with a block element,
/// as a `Scrollbar`'s thumb is; in whole cells where the canvas draws block
/// elements two columns wide (they are East Asian ambiguous). With
/// [divisions] the values are those of [divisions] even steps from [min] to
/// [max]; without, any between. A value below [min] or above [max] shows as
/// the nearest of them, one between divisions as the nearest division, one
/// that is not a number as [min].
///
/// While it has the focus, Right and Up take the value a step up, Left
/// and Down a step down: a division, or a hundredth of the range without
/// divisions; Page Up and Page Down a tenth of the range, a division at
/// least; Home and End to [min] and [max]. The wheel steps as the arrows
/// while it has the focus, and goes to the views around it while it has
/// not. Left and Right are hinted. A press of the left button on the
/// thumb grabs it; elsewhere on the track, it moves the thumb there and
/// grabs it. Dragged, the thumb moves as many cells as the mouse, wherever
/// the mouse goes until the release. A press of the track is its own: a
/// `GestureDetector` around it gets nothing of it.
///
/// Each calls [onChanged] with the value the slider is to take, once that
/// is another; the app builds it with that one. Keys that come before the
/// app builds it again step from the value the last one gave. Disabled
/// with no [onChanged]: then it takes neither the focus, which Tab passes
/// by, nor the mouse.
///
/// As wide as it may be and a row tall; taller where the constraints ask
/// for more rows, the track in the middle one. A repaint boundary: a new
/// value repaints nothing else. The styles, over the theme's background
/// and text: [style] for the thumb and the line before it, the theme's
/// text when null; [focusedStyle] for them while it has the focus,
/// [ThemeData.primary] when null; [trackStyle] for the line after the
/// thumb, [ThemeData.muted] when null; [disabledStyle] for all of it while
/// it is disabled, [ThemeData.muted] when null.
///
/// A screen reader reads it as a [SemanticsRole.slider] of its
/// [semanticsLabel] and the value it shows, to two decimals where it is
/// not whole (`slider Volume: 0.25`, `slider 0.25` without a label),
/// `disabled` while it is.
///
/// A volume from 0 to 100 in steps of 5, held by the app:
///
/// ```dart
/// final volume = ValueNotifier(50.0);
/// final slider = ValueListenableBuilder(
///   valueListenable: volume,
///   builder: (context, value, _) => Slider(
///     value: value,
///     max: 100,
///     divisions: 20,
///     semanticsLabel: 'Volume',
///     onChanged: (v) => volume.value = v,
///   ),
/// );
/// ```
///
/// See also:
///
///  * `NumberInput`, a number typed or stepped in a field.
///  * `ProgressBar`, a value shown along a bar, not chosen.
final class Slider extends StatefulWidget {
  /// A slider of [value], which [onChanged] changes; disabled when that is
  /// null.
  ///
  /// It asserts that [min] is below [max], and that [divisions], where
  /// given, is above 0.
  const Slider({
    required this.value,
    required this.onChanged,
    super.key,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.focusedStyle,
    this.trackStyle,
    this.disabledStyle,
    this.semanticsLabel,
  }) : assert(min < max, 'min not below max'),
       assert(divisions == null || divisions > 0, 'divisions below 1');

  /// The value the thumb shows.
  final double value;

  /// Called with the value the slider is to take; null for a disabled
  /// slider.
  final void Function(double value)? onChanged;

  /// The value at the start of the track; 0 by default.
  final double min;

  /// The value at the end of the track; 1 by default.
  final double max;

  /// The steps from [min] to [max] the values are on; null for any value
  /// between.
  final int? divisions;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// The thumb and the line before it; the theme's text when null.
  final Style? style;

  /// The thumb and the line before it while the slider has the focus;
  /// [ThemeData.primary] when null.
  final Style? focusedStyle;

  /// The line after the thumb; [ThemeData.muted] when null.
  final Style? trackStyle;

  /// All of it while the slider is disabled; [ThemeData.muted] when null.
  final Style? disabledStyle;

  /// What a screen reader calls the slider, what its value is of:
  /// `Volume`; null, or empty, for a slider read as its value alone.
  final String? semanticsLabel;

  @override
  State<Slider> createState() => _SliderState();
}

final class _SliderState extends State<Slider> {
  final GlobalKey _track = GlobalKey();

  // the value the last key or drag gave, until the slider is built again
  late double _value = widget.value;

  // a grab of the thumb: the cell it was pressed at and where the thumb
  // was then, in steps; null while there is none
  int? _grabAt;
  var _grabStart = 0;

  @override
  void didUpdateWidget(Slider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _value = widget.value;
  }

  double get _range => widget.max - widget.min;

  /// [value] within [Slider.min] and [Slider.max], on a division.
  double _fit(double value) {
    final Slider(:min, :max, :divisions) = widget;
    if (value.isNaN || value <= min) {
      return min;
    }
    if (value >= max) {
      return max;
    }
    if (divisions == null) {
      return value;
    }
    final k = ((value - min) / _range * divisions).round();
    return k == divisions ? max : min + _range * k / divisions;
  }

  /// How far along [value] is, from 0 to 1.
  double _ratio(double value) => (_fit(value) - widget.min) / _range;

  void _set(double value) {
    final v = _fit(value);
    if (v != _value) {
      _value = v;
      widget.onChanged?.call(v);
    }
  }

  /// [count] steps up, down when negative: divisions, or hundredths of the
  /// range.
  void _step(int count) {
    final divisions = widget.divisions;
    _set(_fit(_value) + count * _range / (divisions ?? 100));
  }

  /// [count] pages up, down when negative: tenths of the range, a division
  /// at least.
  void _page(int count) {
    final divisions = widget.divisions;
    if (divisions == null) {
      _set(_fit(_value) + count * _range / 10);
    } else {
      final steps = (divisions / 10).round();
      _step(count * (steps > 1 ? steps : 1));
    }
  }

  _RenderTrack? get _render =>
      _track.currentContext?.findRenderObject() as _RenderTrack?;

  void _press(PointerEvent event) {
    final render = _render;
    if (event.button != 0 || render == null) {
      return;
    }
    if (MouseTracker.of(context) case final mouse?) {
      takeDrag(mouse, 0);
      mouse.whenReleased(_released);
    }
    final steps = render.steps;
    final start = _RenderTrack.thumbAt(
      _ratio(_value),
      render.width,
      steps,
    );
    final at = event.x;
    _grabAt = at;
    if (at * steps < start + steps && (at + 1) * steps > start) {
      _grabStart = start;
    } else {
      _grabStart = at * steps;
      _moveTo(_grabStart, render);
    }
  }

  void _drag(PointerEvent event) {
    final render = _render;
    final grabAt = _grabAt;
    if (grabAt == null || render == null) {
      return;
    }
    _moveTo(_grabStart + (event.x - grabAt) * render.steps, render);
  }

  /// Takes the value of the thumb at [start], in steps.
  void _moveTo(int start, _RenderTrack render) {
    final room = (render.width - 1) * render.steps;
    if (room > 0) {
      _set(widget.min + _range * start / room);
    }
  }

  void _released() => _grabAt = null;

  void _wheel(PointerEvent event) => _step(event.scrollX - event.scrollY);

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final shown = _fit(widget.value);
    final pressable = Pressable(
      enabled: enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      bindings: {
        'left': () => _step(-1),
        'down': () => _step(-1),
        'right': () => _step(1),
        'up': () => _step(1),
        'pageup': () => _page(1),
        'pagedown': () => _page(-1),
        'home': () => _set(widget.min),
        'end': () => _set(widget.max),
      },
      hints: const {'left': 'decrease', 'right': 'increase'},
      builder: (context, focused) {
        final theme = Theme.of(context);
        final base = opaque(theme.background.merge(theme.text));
        final Style thumb;
        final Style track;
        if (enabled) {
          thumb = focused
              ? widget.focusedStyle ?? theme.primary
              : widget.style ?? const Style();
          track = widget.trackStyle ?? theme.muted;
        } else {
          thumb = track = widget.disabledStyle ?? theme.muted;
        }
        return Listener(
          onDown: enabled ? _press : null,
          onDrag: enabled ? _drag : null,
          onScroll: enabled && focused ? _wheel : null,
          child: _Track(
            key: _track,
            ratio: _ratio(widget.value),
            thumbStyle: base.merge(thumb),
            trackStyle: base.merge(track),
          ),
        );
      },
    );
    return Semantics(
      role: SemanticsRole.slider,
      label: widget.semanticsLabel,
      value: shown == shown.roundToDouble()
          ? '${shown.round()}'
          : shown.toStringAsFixed(2),
      state: SemanticsState(disabled: !enabled),
      child: pressable,
    );
  }
}

/// The track of a [Slider], its thumb [ratio] of the way along.
final class _Track extends LeafRenderObjectWidget {
  const _Track({
    required this.ratio,
    required this.thumbStyle,
    required this.trackStyle,
    super.key,
  });

  final double ratio;
  final Style thumbStyle;
  final Style trackStyle;

  @override
  _RenderTrack createRenderObject(BuildContext context) => _RenderTrack(
    ratio: ratio,
    thumbStyle: thumbStyle,
    trackStyle: trackStyle,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTrack renderObject,
  ) {
    renderObject
      ..ratio = ratio
      ..thumbStyle = thumbStyle
      ..trackStyle = trackStyle;
  }
}

/// What a [Slider] lays out and paints: its track, the thumb [ratio] of
/// the way along it, in the styles given, none of them the theme's.
final class _RenderTrack extends RenderObject {
  _RenderTrack({
    required this._ratio,
    required this._thumbStyle,
    required this._trackStyle,
  });

  /// How far along the thumb is, from 0 to 1.
  double get ratio => _ratio;
  double _ratio;
  set ratio(double r) {
    if (r != _ratio) {
      _ratio = r;
      markNeedsPaint();
    }
  }

  /// The thumb and the line before it, opaque.
  Style get thumbStyle => _thumbStyle;
  Style _thumbStyle;
  set thumbStyle(Style s) {
    if (s != _thumbStyle) {
      _thumbStyle = s;
      markNeedsPaint();
    }
  }

  /// The line after the thumb, opaque.
  Style get trackStyle => _trackStyle;
  Style _trackStyle;
  set trackStyle(Style s) {
    if (s != _trackStyle) {
      _trackStyle = s;
      markNeedsPaint();
    }
  }

  final _glyphs = ChartGlyphs();

  /// The steps of a cell the thumb is placed in, as it painted last: 8, or
  /// 1 where the canvas draws block elements two columns wide.
  int get steps => _steps;
  var _steps = 8;

  /// The step the thumb starts at, [ratio] of the way along a track of
  /// [length] cells of [steps] steps each.
  static int thumbAt(double ratio, int length, int steps) =>
      length > 1 ? (ratio * (length - 1) * steps).round() : 0;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    final track = _trackStyle.penIn(styles);
    canvas.fill(0, 0, width, height, track);
    final g = _glyphs..use(canvas.segmenter);
    final steps = _steps = thumbSteps(canvas, vertical: false);
    if (width <= 0) {
      return;
    }
    final line = g.lines(BorderType.single).glyph(left: true, right: true);
    final y = height ~/ 2;
    final start = thumbAt(_ratio, width, steps);
    final end = start + steps;
    // the line before the cells of the thumb in its color, the line after
    // them in the track's
    final after = (end + steps - 1) ~/ steps;
    canvas
      ..fill(0, y, start ~/ steps, 1, _thumbStyle.penIn(styles), line)
      ..fill(after, y, width - after, 1, track, line);
    paintThumb(
      canvas,
      _thumbStyle,
      start: start,
      end: end,
      steps: steps,
      vertical: false,
      at: y,
    );
  }
}
