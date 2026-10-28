/// Boxes that paint under or over a child: [ColoredBox] fills its cells
/// with a color, [DecoratedBox] draws a [BoxDecoration], and [Container]
/// puts the layout widgets with one child together as Flutter's does.
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Alignment,
        BoxConstraints,
        Color,
        DiagnosticPropertiesBuilder,
        EdgeInsets,
        HitTestBehavior,
        PaintContext,
        Pen,
        RenderObject,
        RenderObjectWithChildMixin,
        StyleTable;

import '../framework/framework.dart';
import '../gestures/ignore_pointer.dart';
import '../style/style.dart';
import 'basic.dart';
import 'box.dart';
import 'one_child.dart';
import 'overflow.dart';
import 'stack.dart';

// Examples can assume:
// late ThemeData theme;

/// Fills its cells with [color], then paints [child] over it: the
/// child's text takes the color as its background where it sets none. As
/// big as the child, or without one as small as the constraints allow; the
/// mouse hits it anywhere in its cells.
///
/// As Flutter's `ColoredBox`. A status line in blue:
///
/// ```dart
/// const ColoredBox(color: Color.blue, child: Text(' NORMAL '))
/// ```
///
/// See also:
///
///  * [Box], whose [Box.style] fills it with a whole [Style].
final class ColoredBox extends SingleChildRenderObjectWidget {
  /// Fills its cells with [color] under [child].
  const ColoredBox({required this.color, super.key, super.child});

  /// The background of its cells.
  final Color color;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderColoredBox(color);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderColoredBox).color = color;
}

/// Where a [DecoratedBox] paints its decoration: under its child or over
/// it.
enum DecorationPosition {
  /// Under the child, which goes inside the border as in a [Box].
  background,

  /// Over the child, which takes the whole box: the border and the titles
  /// are drawn over its edges.
  foreground,
}

/// What a [DecoratedBox] paints: a [style] that fills it, or a [gradient]
/// under it, a [border] around it and [titles] on its edges, as a [Box]
/// draws them.
///
/// Two decorations are equal when their style, border, gradient and
/// titles, in order, are.
///
/// A panel in the theme's surface color, a rounded border around it:
///
/// ```dart
/// BoxDecoration(
///   style: theme.surface,
///   border: const Border.all(type: .rounded),
/// )
/// ```
@immutable
final class BoxDecoration {
  /// Paints [style], [border], [titles] and [gradient], each left out
  /// when not given: with none, nothing.
  const BoxDecoration({
    this.style,
    this.border,
    this.titles = const [],
    this.gradient,
  });

  /// What the box is filled with, its background and the colors its
  /// border, titles and child take where theirs are unset; null leaves
  /// what is under it. With a [gradient], a style without a background:
  /// it would cover the gradient.
  final Style? style;

  /// The lines around the box; null for none.
  final Border? border;

  /// Text on the top and bottom edges.
  final List<BorderTitle> titles;

  /// The colors under the box, cell by cell ([GradientBackground]); over
  /// the child, those of its text ([GradientForeground]).
  final Gradient? gradient;

  @override
  bool operator ==(Object other) {
    if (other is! BoxDecoration ||
        other.style != style ||
        other.border != border ||
        other.gradient != gradient ||
        other.titles.length != titles.length) {
      return false;
    }
    for (var i = 0; i < titles.length; i++) {
      if (other.titles[i] != titles[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(style, border, Object.hashAll(titles), gradient);
}

/// Paints [decoration] under [child] or over it, as [position] says.
///
/// Under it ([DecorationPosition.background]), it is a [Box]: the style
/// fills it, the border is drawn around the child, which goes inside it,
/// and the titles on its edges; a gradient goes under it all. Unlike
/// Flutter's, the border takes cells of its own: a child that covered it
/// would hide it.
///
/// Over it ([DecorationPosition.foreground]), the child takes the whole
/// box, and the border and the titles are drawn over its edges; the
/// mouse passes them by to the child. The style is not filled, which would
/// blank the child, but gives the lines and titles the colors theirs leave
/// unset; a gradient colors the child's text.
///
/// As big as a [Box] would be, or over the child as big as the child,
/// which gets the constraints the box was given.
///
/// A frame drawn over the edges of a text, which keeps its whole size:
///
/// ```dart
/// const DecoratedBox(
///   decoration: BoxDecoration(border: Border.all()),
///   position: DecorationPosition.foreground,
///   child: Text('three lines\nof text\nin a frame'),
/// )
/// ```
///
/// See also:
///
///  * [Box], what it is under its child, with padding as well.
///  * [Container], which takes a decoration with the other layout widgets.
final class DecoratedBox extends StatelessWidget {
  /// Paints [decoration] under [child], or over it with
  /// [DecorationPosition.foreground].
  const DecoratedBox({
    required this.decoration,
    super.key,
    this.position = DecorationPosition.background,
    this.child,
  });

  /// What is painted.
  final BoxDecoration decoration;

  /// Whether [decoration] goes under [child], the default, or over it.
  final DecorationPosition position;

  /// What is decorated; null for the decoration alone.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final d = decoration;
    final gradient = d.gradient;
    assert(
      gradient == null || d.style?.bg == null,
      'a gradient or a background, not both: the background covers it',
    );
    if (position == DecorationPosition.background) {
      final box = Box(
        style: d.style,
        border: d.border,
        titles: d.titles,
        child: child,
      );
      return gradient == null
          ? box
          : GradientBackground(gradient: gradient, child: box);
    }
    final style = d.style ?? const Style();
    final border = d.border;
    final lines = IgnorePointer(
      child: Box(
        border: border == null
            ? null
            : Border(
                type: border.type,
                top: _over(style, border.top),
                right: _over(style, border.right),
                bottom: _over(style, border.bottom),
                left: _over(style, border.left),
                merge: border.merge,
              ),
        titles: [
          for (final t in d.titles)
            BorderTitle(
              t.text,
              style: style.merge(t.style),
              alignment: t.alignment,
            ),
        ],
      ),
    );
    var content = child;
    if (content == null) {
      return lines;
    }
    if (gradient != null) {
      content = GradientForeground(gradient: gradient, child: content);
    }
    if (border == null && d.titles.isEmpty) {
      return content;
    }
    // the child keeps the constraints the box was given, a tight size
    // too, as it would without the lines
    return Stack(
      fit: StackFit.passthrough,
      children: [
        content,
        Positioned.fill(child: lines),
      ],
    );
  }

  static Style? _over(Style style, Style? side) =>
      side == null ? null : style.merge(side);
}

/// The layout widgets with one child, put together as Flutter's
/// `Container` puts them, from the inside out: [child], or without one a
/// box as big as the constraints allow (as small along an unbounded
/// axis); [Align] by [alignment]; [Padding] by [padding]; [ColoredBox] in
/// [color]; [DecoratedBox] with [decoration], then with
/// [foregroundDecoration] over it all; [ConstrainedBox] within
/// [constraints], tightened to [width] and [height]; [Padding] by
/// [margin]. Each is there only when what it takes is given. The padding
/// goes inside the decoration, the margin outside it; the decoration's
/// border takes cells of its own, inside the margin, around the padding.
///
/// [color] is a shorthand for a decoration that fills the box, and only
/// one of the two is given.
///
/// A card 30 cells wide, one cell from what is around it, its text one
/// cell in from its border:
///
/// ```dart
/// Container(
///   width: 30,
///   margin: const .all(1),
///   padding: const .x(1),
///   decoration: BoxDecoration(
///     style: theme.surface,
///     border: const Border.all(type: .rounded),
///   ),
///   child: const Text('Build passed'),
/// )
/// ```
///
/// See also:
///
///  * [Box], a border, a background and padding in one render object.
///  * [Padding], [Align], [SizedBox] and [DecoratedBox], each part alone.
final class Container extends StatelessWidget {
  /// Puts together the widgets of each parameter given; [color] or
  /// [decoration], not both, and [width] and [height] 0 or more.
  const Container({
    super.key,
    this.alignment,
    this.padding,
    this.color,
    this.decoration,
    this.foregroundDecoration,
    this.width,
    this.height,
    this.constraints,
    this.margin,
    this.child,
  }) : assert(
         color == null || decoration == null,
         'a color or a decoration, not both: the color is a decoration '
         'that fills the box',
       ),
       assert(
         (width ?? 0) >= 0 && (height ?? 0) >= 0,
         'a size of 0 cells or more',
       );

  /// Where the child goes, the container as big as it may be; the child
  /// takes the room as it is when null.
  final Alignment? alignment;

  /// The empty cells around the child, inside the decoration.
  final EdgeInsets? padding;

  /// The background of the box, inside the margin.
  final Color? color;

  /// What is painted under the child, inside the margin.
  final BoxDecoration? decoration;

  /// What is painted over the child, the decoration and the padding.
  final BoxDecoration? foregroundDecoration;

  /// The columns the box takes, the margin left out, as far as
  /// [constraints] allow.
  final int? width;

  /// The rows the box takes, the margin left out, as far as [constraints]
  /// allow.
  final int? height;

  /// The limits on the size of the box, the margin left out.
  final BoxConstraints? constraints;

  /// The empty cells around the box, outside the decoration.
  final EdgeInsets? margin;

  /// What the container holds; null for an empty box of the size the rest
  /// says.
  final Widget? child;

  /// [constraints] tightened to [width] and [height], each kept within
  /// them.
  BoxConstraints? get _constraints {
    final w = width;
    final h = height;
    final c = constraints;
    if (w == null && h == null) {
      return c;
    }
    if (c == null) {
      return BoxConstraints.tightFor(width: w, height: h);
    }
    return BoxConstraints(
      w == null ? c.minW : c.constrainW(w),
      w == null ? c.maxW : c.constrainW(w),
      h == null ? c.minH : c.constrainH(h),
      h == null ? c.maxH : c.constrainH(h),
    );
  }

  @override
  Widget build(BuildContext context) {
    final constraints = _constraints;
    var current = child;
    if (current == null && !(constraints?.isTight ?? false)) {
      current = const LimitedBox(
        maxWidth: 0,
        maxHeight: 0,
        child: SizedBox.expand(),
      );
    }
    final alignment = this.alignment;
    if (alignment != null) {
      current = Align(alignment: alignment, child: current);
    }
    final padding = this.padding;
    if (padding != null) {
      current = Padding(padding: padding, child: current);
    }
    final color = this.color;
    if (color != null) {
      current = ColoredBox(color: color, child: current);
    }
    final decoration = this.decoration;
    if (decoration != null) {
      current = DecoratedBox(decoration: decoration, child: current);
    }
    final foreground = foregroundDecoration;
    if (foreground != null) {
      current = DecoratedBox(
        decoration: foreground,
        position: DecorationPosition.foreground,
        child: current,
      );
    }
    if (constraints != null) {
      current = ConstrainedBox(constraints: constraints, child: current);
    }
    final margin = this.margin;
    if (margin != null) {
      current = Padding(padding: margin, child: current);
    }
    // a child, the box in its place or the box of tight constraints
    return current ?? const SizedBox.shrink();
  }
}

/// What a [ColoredBox] lays out and paints.
final class _RenderColoredBox extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderColoredBox(this._color);

  Color _color;
  Color get color => _color;
  set color(Color c) {
    if (c != _color) {
      _color = c;
      _penIn = null;
      markNeedsPaint();
    }
  }

  // the pen of the color in _penIn (null: to be looked up)
  StyleTable? _penIn;
  var _pen = 0;

  /// Opaque: it fills all of its cells.
  @override
  HitTestBehavior get hitTestBehavior => HitTestBehavior.opaque;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('color', _color);
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    child
      ..layout(c, parentUsesSize: true)
      ..parentData.dx = 0
      ..parentData.dy = 0;
    width = child.width;
    height = child.height;
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    if (!identical(styles, _penIn)) {
      _penIn = styles;
      _pen = styles.pen(Pen(bg: _color));
    }
    canvas.fill(0, 0, width, height, _pen);
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }
}
