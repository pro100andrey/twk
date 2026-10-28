/// Rows and columns: [Flex], [Row] and [Column] lay their children out
/// along one axis; [Flexible], [Expanded] and [Spacer] share out the cells
/// the other children leave.
///
/// @docImport '../scroll/list_view.dart';
/// @docImport 'wrap.dart';
library;

import 'package:twk_core/twk_core.dart'
    show
        Axis,
        CrossAxisAlignment,
        FlexFit,
        FlexParentData,
        MainAxisAlignment,
        MainAxisSize,
        RenderFlex,
        RenderObject;

import '../framework/framework.dart';
import 'basic.dart';
import 'child_list.dart';

export 'package:twk_core/twk_core.dart'
    show Axis, CrossAxisAlignment, FlexFit, MainAxisAlignment, MainAxisSize;

// Examples can assume:
// late bool wide;

/// Lays its children out one after another along [direction], [gap] cells
/// apart: the inflexible ones first, each as long as it wants, then the
/// [Flexible] ones, which share the cells left by their flex factors. See
/// [RenderFlex].
///
/// A [Row] or a [Column] is the usual way to write one; a flex is for a
/// direction that changes, as with the terminal's width:
///
/// ```dart
/// Flex(
///   direction: wide ? Axis.horizontal : Axis.vertical,
///   gap: 1,
///   children: const [Text('Name'), Expanded(child: TextField())],
/// )
/// ```
final class Flex extends MultiChildRenderObjectWidget {
  /// Lays [children] out along [direction], [gap] cells apart (0 or
  /// more): from the start, as long as it may be, each child in the middle
  /// across, by default.
  const Flex({
    required this.direction,
    super.key,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.gap = 0,
    super.children,
  }) : assert(gap >= 0, 'a gap of 0 cells or more');

  /// The main axis.
  final Axis direction;

  /// Where the children go along the main axis, in the cells they leave
  /// free.
  final MainAxisAlignment mainAxisAlignment;

  /// Whether the flex is as long as it may be, or as its children.
  final MainAxisSize mainAxisSize;

  /// Where each child goes across the main axis.
  final CrossAxisAlignment crossAxisAlignment;

  /// Cells between one child and the next.
  final int gap;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  RenderFlex createRenderObject(BuildContext context) => RenderFlex(
    direction: direction,
    mainAxisAlignment: mainAxisAlignment,
    mainAxisSize: mainAxisSize,
    crossAxisAlignment: crossAxisAlignment,
    gap: gap,
  );

  @override
  void updateRenderObject(BuildContext context, RenderFlex renderObject) {
    renderObject
      ..direction = direction
      ..mainAxisAlignment = mainAxisAlignment
      ..mainAxisSize = mainAxisSize
      ..crossAxisAlignment = crossAxisAlignment
      ..gap = gap;
  }
}

/// A [Flex] that lays its children out side by side.
///
/// A label, a field that takes the rest of the row, and a button:
///
/// ```dart
/// Row(
///   gap: 1,
///   children: [
///     const Text('Search'),
///     const Expanded(child: TextField()),
///     Button('Go', onPressed: () {}),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [Column], the same down.
///  * [Wrap], which goes on to the next row where this one ends.
final class Row extends Flex {
  /// Lays [children] out from left to right; the rest as [Flex]'s.
  const Row({
    super.key,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.gap,
    super.children,
  }) : super(direction: Axis.horizontal);
}

/// A [Flex] that lays its children out one below another.
///
/// A title, a list that takes the rows left, and a status line:
///
/// ```dart
/// Column(
///   crossAxisAlignment: CrossAxisAlignment.stretch,
///   children: [
///     const Text('Files'),
///     Expanded(child: ListView(children: const [Text('a.txt')])),
///     const Text('1 file'),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [Row], the same across.
///  * [ListView], for more children than there are rows.
final class Column extends Flex {
  /// Lays [children] out from top to bottom; the rest as [Flex]'s.
  const Column({
    super.key,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.gap,
    super.children,
  }) : super(direction: Axis.vertical);
}

/// Makes [child] a flexible child of the [Flex] it is in: it gets [flex]
/// parts of the cells the inflexible children leave and takes as much of
/// them as [fit] says. It goes inside a [Flex] with no render object widget
/// in between.
///
/// A text that takes up to half of the row, and no more than it needs:
///
/// ```dart
/// const Row(
///   children: [
///     Flexible(child: Text('A name that may be long')),
///     Expanded(child: SizedBox()),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [Expanded], which fills its share.
final class Flexible extends ParentDataWidget<FlexParentData> {
  /// Makes [child] flexible: [flex] parts (0 or more, 1 by default), as
  /// much of them as it wants ([FlexFit.loose]) unless [fit] says.
  const Flexible({
    required super.child,
    super.key,
    this.flex = 1,
    this.fit = FlexFit.loose,
  }) : assert(flex >= 0, 'a flex factor of 0 or more');

  /// The child's parts of the cells the inflexible children leave, against
  /// the parts of the other flexible ones; with 0 it is laid out as an
  /// inflexible child.
  final int flex;

  /// Whether the child fills its share ([FlexFit.tight]) or takes up to it
  /// ([FlexFit.loose]).
  final FlexFit fit;

  @override
  void applyParentData(RenderObject renderObject) {
    final at = renderObject.parentData as FlexParentData;
    if (at.flex != flex || at.fit != fit) {
      at
        ..flex = flex
        ..fit = fit;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => Flex;
}

/// A [Flexible] that fills its share of the cells.
///
/// Two panes, the right one twice as wide as the left:
///
/// ```dart
/// const Row(
///   children: [
///     Expanded(child: Text('Tree')),
///     Expanded(flex: 2, child: Text('Editor')),
///   ],
/// )
/// ```
final class Expanded extends Flexible {
  /// Makes [child] fill [flex] parts of the cells left, 1 by default.
  const Expanded({required super.child, super.key, super.flex})
    : super(fit: FlexFit.tight);
}

/// Empty cells in a [Flex]: [flex] parts of the cells the inflexible
/// children leave.
///
/// A title on the left of a bar and the time on its right:
///
/// ```dart
/// const Row(children: [Text('Inbox'), Spacer(), Text('12:30')])
/// ```
final class Spacer extends StatelessWidget {
  /// Takes [flex] parts of the cells left, 1 by default.
  const Spacer({super.key, this.flex = 1})
    : assert(flex > 0, 'a flex factor above 0');

  /// The parts of the cells left it takes, against the other flexible
  /// children's: above 0.
  final int flex;

  @override
  Widget build(BuildContext context) =>
      Expanded(flex: flex, child: const SizedBox.shrink());
}
