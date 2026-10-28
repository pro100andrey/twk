/// Runs that wrap: [Wrap] lays its children out one after another and
/// starts a new run where the next would not fit.
///
/// @docImport 'flex.dart';
library;

import 'package:twk_core/twk_core.dart'
    show Axis, RenderWrap, WrapAlignment, WrapCrossAlignment;

import '../framework/framework.dart';
import 'child_list.dart';

export 'package:twk_core/twk_core.dart' show WrapAlignment, WrapCrossAlignment;

/// Lays its children out in runs: one after another along [direction],
/// [gap] cells apart, each as long as it wants up to the whole main axis,
/// until the next would not fit, which starts a new run [runGap] cells on
/// (Yoga's flexWrap); tags, buttons, key hints that flow onto the next row
/// as the terminal narrows. [alignment] places the children of each run,
/// [crossAxisAlignment] each child in its run, [runAlignment] the runs.
/// It is as long as its longest run and as thick as its runs, or as the
/// constraints ask if that is more. See [RenderWrap].
///
/// Tags a cell apart, flowing onto the next row where the room ends:
///
/// ```dart
/// const Wrap(
///   gap: 1,
///   children: [Text('[dart]'), Text('[twk]'), Text('[terminal]')],
/// )
/// ```
///
/// See also:
///
///  * [Row] and [Column], which keep their children on one line.
final class Wrap extends MultiChildRenderObjectWidget {
  /// Lays [children] out in runs along [direction], across by default,
  /// [gap] and [runGap] cells apart, each 0 or more.
  const Wrap({
    super.key,
    this.direction = Axis.horizontal,
    this.alignment = WrapAlignment.start,
    this.runAlignment = WrapAlignment.start,
    this.crossAxisAlignment = WrapCrossAlignment.start,
    this.gap = 0,
    this.runGap = 0,
    super.children,
  }) : assert(gap >= 0 && runGap >= 0, 'gaps of 0 cells or more');

  /// The main axis, along which a run goes.
  final Axis direction;

  /// Where the children of a run go along it, in the cells they leave of
  /// the wrap's length.
  final WrapAlignment alignment;

  /// Where the runs go across the main axis, in the cells they leave of
  /// the wrap's thickness.
  final WrapAlignment runAlignment;

  /// Where each child goes across the main axis, in its run.
  final WrapCrossAlignment crossAxisAlignment;

  /// Cells between one child of a run and the next.
  final int gap;

  /// Cells between one run and the next.
  final int runGap;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  RenderWrap createRenderObject(BuildContext context) => RenderWrap(
    direction: direction,
    alignment: alignment,
    runAlignment: runAlignment,
    crossAxisAlignment: crossAxisAlignment,
    gap: gap,
    runGap: runGap,
  );

  @override
  void updateRenderObject(BuildContext context, RenderWrap renderObject) {
    renderObject
      ..direction = direction
      ..alignment = alignment
      ..runAlignment = runAlignment
      ..crossAxisAlignment = crossAxisAlignment
      ..gap = gap
      ..runGap = runGap;
  }
}
