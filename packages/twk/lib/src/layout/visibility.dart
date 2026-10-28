/// Children that are there without being shown: [Offstage], which keeps
/// its child laid out and its state while it paints nothing, and
/// [Visibility], which hides its child as it is told, with its state, its
/// size, or neither.
library;

import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        DiagnosticPropertiesBuilder,
        HitTestResult,
        PaintContext,
        RenderObject,
        RenderObjectWithChildMixin;

import '../focus/focus.dart';
import '../framework/framework.dart';
import '../semantics/semantics.dart';
import 'basic.dart';
import 'one_child.dart';

// Examples can assume:
// late bool showLog;

/// Lays [child] out, but while [offstage] paints nothing of it, lets no
/// cell of it be hit, keeps the focus from the focus nodes in it
/// ([ExcludeFocus]) and leaves it out of what a screen reader reads
/// ([ExcludeSemantics]), as small as the constraints allow; otherwise it
/// is as big as the child and shows it as it is. The child's elements
/// and states stay as they are either way: going on stage again shows it
/// as it was left.
///
/// What is offstage still builds, lays out and runs (an animation in it
/// still asks for frames); a repaint boundary in it that repaints on its
/// own shows nothing, the child lying outside the cells of this widget
/// (below them) while it is offstage. A focus node in it that has the
/// focus as it goes offstage loses it, as from a node that can no longer
/// take it ([FocusNode.descendantsAreFocusable]); Tab passes the nodes in
/// it by. The child is under the focus node of an [ExcludeFocus], which
/// takes no focus itself: `Focus.of` in the child finds that one.
///
/// A log that keeps its lines and its scroll position while it is hidden:
///
/// ```dart
/// Offstage(offstage: !showLog, child: LogView(controller: LogController()))
/// ```
///
/// See also:
///
///  * [Visibility], which can also take the child out or keep its room.
final class Offstage extends StatelessWidget {
  /// Hides [child] while [offstage], true by default.
  const Offstage({super.key, this.offstage = true, this.child});

  /// Whether the child is hidden.
  final bool offstage;

  /// What is shown, or kept laid out but hidden; null for nothing.
  final Widget? child;

  @override
  Widget build(BuildContext context) =>
      _hide(hidden: offstage, keepsSize: false, child: child);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('offstage', offstage);
  }
}

/// Shows [child] while [visible], and otherwise, as Flutter's does:
///
///  * by default [replacement] in its place (an empty box), the child
///    taken out of the tree, its state with it;
///  * with [maintainState], an [Offstage] of it: laid out, its state kept,
///    not painted, hit, focused or read by a screen reader, taking no room;
///  * with [maintainSize] as well, the room it takes kept: laid out as when
///    visible, as big, but painted, hit, focused or read no more than
///    offstage.
///
/// Switching [visible] keeps the child's state with [maintainState]; one
/// of the two others switched keeps it no more than a widget of another
/// kind in its place does.
///
/// A count of warnings shown on demand, its room kept while it is hidden so
/// that the rest of the screen does not move:
///
/// ```dart
/// Visibility(
///   visible: showLog,
///   maintainState: true,
///   maintainSize: true,
///   child: const Text('3 warnings'),
/// )
/// ```
///
/// See also:
///
///  * [Offstage], what it is with [maintainState] alone.
final class Visibility extends StatelessWidget {
  /// Shows [child] while [visible], true by default; [maintainSize] only
  /// with [maintainState].
  const Visibility({
    required this.child,
    super.key,
    this.visible = true,
    this.replacement = const SizedBox.shrink(),
    this.maintainState = false,
    this.maintainSize = false,
  }) : assert(
         !maintainSize || maintainState,
         'a size is kept only with the state',
       );

  /// What is shown while [visible].
  final Widget child;

  /// Whether the child is shown.
  final bool visible;

  /// What is shown in place of the child while it is not visible and its
  /// state is not kept.
  final Widget replacement;

  /// Whether the child stays in the tree while it is not visible: laid
  /// out, its state kept, as [Offstage] keeps it.
  final bool maintainState;

  /// Whether the child takes its room while it is not visible; only with
  /// [maintainState].
  final bool maintainSize;

  @override
  Widget build(BuildContext context) {
    if (maintainSize) {
      return _hide(hidden: !visible, keepsSize: true, child: child);
    }
    if (maintainState) {
      return Offstage(offstage: !visible, child: child);
    }
    return visible ? child : replacement;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('visible', visible, defaultValue: true)
      ..add('maintainState', maintainState, defaultValue: false)
      ..add('maintainSize', maintainSize, defaultValue: false);
  }
}

/// [child], out of the focus and the semantics while [hidden], and not
/// painted or hit then, as big as it is with [keepsSize].
Widget _hide({
  required bool hidden,
  required bool keepsSize,
  required Widget? child,
}) => ExcludeFocus(
  excluding: hidden,
  child: ExcludeSemantics(
    excluding: hidden,
    child: _Hidden(hidden: hidden, keepsSize: keepsSize, child: child),
  ),
);

/// Paints nothing of [child], nor lets it be hit, while [hidden]; as big
/// as the child then with [keepsSize], else as small as it may be.
final class _Hidden extends SingleChildRenderObjectWidget {
  const _Hidden({
    required this.hidden,
    required this.keepsSize,
    super.child,
  });

  final bool hidden;
  final bool keepsSize;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHidden(hidden: hidden, keepsSize: keepsSize);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderHidden)
      ..hidden = hidden
      ..keepsSize = keepsSize;
  }
}

/// What an [Offstage] and a [Visibility] that keeps the size lay out and
/// paint: the child, laid out always, painted and hit while not hidden.
final class _RenderHidden extends RenderObject with RenderObjectWithChildMixin {
  _RenderHidden({required this._hidden, required this._keepsSize});

  bool _hidden;
  bool get hidden => _hidden;
  set hidden(bool on) {
    if (on != _hidden) {
      _hidden = on;
      // the size, and where the child is
      markNeedsLayout();
    }
  }

  bool _keepsSize;
  bool get keepsSize => _keepsSize;
  set keepsSize(bool on) {
    if (on != _keepsSize) {
      _keepsSize = on;
      markNeedsLayout();
    }
  }

  /// Whether it takes no more room than the constraints make it.
  bool get _shrunk => _hidden && !_keepsSize;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('hidden', _hidden, defaultValue: false)
      ..add('keepsSize', _keepsSize, defaultValue: false);
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    if (_shrunk) {
      child.layout(c);
      width = c.minW;
      height = c.minH;
    } else {
      child.layout(c, parentUsesSize: true);
      width = child.width;
      height = child.height;
    }
    // hidden, below its own cells: a repaint boundary in it that repaints
    // on its own is cut off by them, as all of it is
    child.parentData
      ..dx = 0
      ..dy = _hidden ? height : 0;
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      _shrunk ? 0 : child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      _shrunk ? 0 : child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      _shrunk ? 0 : child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _shrunk ? 0 : child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child != null && !_hidden) {
      paintChild(ctx, child);
    }
  }

  @override
  bool hitTestChildren(HitTestResult result, int x, int y) =>
      !_hidden && super.hitTestChildren(result, x, y);
}
