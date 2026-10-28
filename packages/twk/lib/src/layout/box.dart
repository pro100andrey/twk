/// Boxes drawn around a child and lines across: [Box], with a background,
/// a [Border] with [BorderTitle]s on its edges and padding; [Divider] and
/// [VerticalDivider].
///
/// @docImport 'basic.dart';
/// @docImport 'container.dart';
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Alignment,
        Axis,
        BorderType,
        BoxBorder,
        BoxTitle,
        EdgeInsets,
        RenderDecoratedBox,
        RenderDivider;

import '../framework/framework.dart';
import '../style/style.dart';
import 'one_child.dart';

export 'package:twk_core/twk_core.dart' show BorderType;

// Examples can assume:
// late BuildContext context;

/// A box around [child]: [style] fills it, [border] lines its sides,
/// [titles] sit on its top and bottom edges, and [padding] is between the
/// border and the child.
///
/// It is as big as the child and what surrounds it, and as wide as its
/// titles, as far as the constraints allow; without a child, as big as
/// they allow. A title too long for its edge is cut off with "…". See
/// [RenderDecoratedBox].
///
/// A rounded panel with a title, one cell between its border and the text:
///
/// ```dart
/// Box(
///   border: const Border.all(type: .rounded),
///   titles: const [BorderTitle(' Status ')],
///   padding: const .all(1),
///   child: const Text('All systems go'),
/// )
/// ```
///
/// See also:
///
///  * [Padding], for the space without the border.
///  * [Container], which adds a size, a margin and a shadow.
///  * [Divider], a line across without the box.
final class Box extends SingleChildRenderObjectWidget {
  /// A box around [child]; with every parameter left out, an empty one
  /// that fills nothing.
  const Box({
    super.key,
    this.style,
    this.border,
    this.titles = const [],
    this.padding = EdgeInsets.zero,
    super.child,
  });

  /// What the box is filled with: its background, and the colors its
  /// border, titles and child take where theirs are unset; null leaves
  /// what is under the box.
  final Style? style;

  /// The lines around the box; null for none.
  final Border? border;

  /// Text on the top and bottom edges; an edge with titles but no border
  /// takes a row of its own.
  final List<BorderTitle> titles;

  /// The empty cells between the border and the child.
  final EdgeInsets padding;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderDecoratedBox createRenderObject(BuildContext context) =>
      RenderDecoratedBox(
        background: style?.pen,
        border: border?._boxBorder,
        titles: _boxTitles,
        padding: padding,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderDecoratedBox renderObject,
  ) {
    renderObject
      ..background = style?.pen
      ..border = border?._boxBorder
      ..titles = _boxTitles
      ..padding = padding;
  }

  List<BoxTitle> get _boxTitles =>
      titles.isEmpty ? const [] : [for (final t in titles) t._boxTitle];
}

/// The border of a [Box]: the lines it is drawn with, for each side that
/// has one its style, and whether it [merge]s with the lines already drawn.
/// A side left null has no border.
///
/// A line under a heading, in the theme's border color:
///
/// ```dart
/// Border(bottom: Theme.of(context).border)
/// ```
@immutable
final class Border {
  /// A border of [type] on each side given a style; with none given, no
  /// border at all.
  const Border({
    this.type = BorderType.single,
    this.top,
    this.right,
    this.bottom,
    this.left,
    this.merge = false,
  });

  /// A border on every side, in [style].
  const Border.all({
    this.type = BorderType.single,
    Style style = const Style(),
    this.merge = false,
  }) : top = style,
       right = style,
       bottom = style,
       left = style;

  /// The lines the border is drawn with: [BorderType.single] by default.
  final BorderType type;

  /// The style of the top side; null for no line there.
  final Style? top;

  /// The style of the right side; null for no line there.
  final Style? right;

  /// The style of the bottom side; null for no line there.
  final Style? bottom;

  /// The style of the left side; null for no line there.
  final Style? left;

  /// Whether the border joins the lines drawn before it where it meets or
  /// crosses them (`├ ┬ ┼`: boxes stacked to share an edge) rather than
  /// covering them, leaving the text drawn in its cells (the titles of a
  /// box whose edge it shares). See [BoxBorder.merge].
  final bool merge;

  BoxBorder get _boxBorder => BoxBorder(
    type: type,
    top: top?.pen,
    right: right?.pen,
    bottom: bottom?.pen,
    left: left?.pen,
    merge: merge,
  );

  @override
  bool operator ==(Object other) =>
      other is Border &&
      other.type == type &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left &&
      other.merge == merge;

  @override
  int get hashCode => Object.hash(type, top, right, bottom, left, merge);
}

/// Text on the top or the bottom edge of a [Box], in [style]: the y of
/// [alignment] picks the edge (-1 the top, 1 the bottom), its x the place
/// along it.
///
/// A name on the top left of a box and a count on its bottom right:
///
/// ```dart
/// const Box(
///   border: Border.all(),
///   titles: [
///     BorderTitle(' Files '),
///     BorderTitle(' 12 ', alignment: Alignment.bottomRight),
///   ],
/// )
/// ```
@immutable
final class BorderTitle {
  /// Shows [text] in [style], at [alignment]: the top left by default.
  const BorderTitle(
    this.text, {
    this.style = const Style(),
    this.alignment = Alignment.topLeft,
  });

  /// The title, on one line; cut off with "…" where the edge is too short.
  final String text;

  /// The title's style; the colors it leaves unset are those of the
  /// box's [Box.style].
  final Style style;

  /// The edge (its y: -1 the top, 1 the bottom) and the place along it
  /// (its x) of the title.
  final Alignment alignment;

  BoxTitle get _boxTitle =>
      BoxTitle(text, pen: style.pen, alignment: alignment);

  @override
  bool operator ==(Object other) =>
      other is BorderTitle &&
      other.text == text &&
      other.style == style &&
      other.alignment == alignment;

  @override
  int get hashCode => Object.hash(text, style, alignment);
}

/// A line across the room it gets, one row tall, drawn with [type] in
/// [style]; with [merge] it joins the lines drawn before it, its ends
/// meeting a line they land on in a joint (`├───┤` across a [Box] it is
/// stacked on). See [RenderDivider].
///
/// Two sections of a column, a line between them:
///
/// ```dart
/// const Column(
///   children: [Text('Inbox'), Divider(), Text('Archive')],
/// )
/// ```
///
/// See also:
///
///  * [VerticalDivider], the same down.
final class Divider extends LeafRenderObjectWidget {
  /// A line across, of [type] in [style]; with [merge], joined to the
  /// lines it meets.
  const Divider({
    super.key,
    this.type = BorderType.single,
    this.style = const Style(),
    this.merge = false,
  }) : _direction = Axis.horizontal;

  const Divider._down({
    super.key,
    this.type = BorderType.single,
    this.style = const Style(),
    this.merge = false,
  }) : _direction = Axis.vertical;

  /// The line it is drawn with: [BorderType.single] by default.
  final BorderType type;

  /// The style of the line.
  final Style style;

  /// Whether the line's ends join the lines they land on (`├ ┤`) rather
  /// than covering them; off by default.
  final bool merge;

  final Axis _direction;

  @override
  RenderDivider createRenderObject(BuildContext context) => RenderDivider(
    direction: _direction,
    type: type,
    pen: style.pen,
    merge: merge,
  );

  @override
  void updateRenderObject(BuildContext context, RenderDivider renderObject) {
    renderObject
      ..direction = _direction
      ..type = type
      ..pen = style.pen
      ..merge = merge;
  }
}

/// A line down the room it gets, one column wide, drawn with [type] in
/// [style]; with [merge] it joins the lines drawn before it. See
/// [RenderDivider].
///
/// Two panes side by side, a line between them:
///
/// ```dart
/// const Row(
///   children: [
///     Expanded(child: Text('Left')),
///     VerticalDivider(),
///     Expanded(child: Text('Right')),
///   ],
/// )
/// ```
final class VerticalDivider extends Divider {
  /// A line down, of [type] in [style]; with [merge], joined to the lines
  /// it meets.
  const VerticalDivider({super.key, super.type, super.style, super.merge})
    : super._down();
}
