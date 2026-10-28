/// Panes side by side or one below another, a divider between each two
/// that the mouse drags and the keys move: [SplitView], its [SplitPane]s,
/// and the [SplitController] that keeps their shares of the room.
///
/// @docImport 'dock.dart';
/// @docImport 'flex.dart';
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Axis,
        BorderType,
        BoxConstraints,
        ContainerParentDataMixin,
        ContainerRenderObjectMixin,
        DiagnosticPropertiesBuilder,
        GlyphRun,
        HitTestBehavior,
        HitTestResult,
        PaintContext,
        ParentData,
        RenderDivider,
        RenderObject;

import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../style/style.dart';
import 'box.dart';
import 'child_list.dart';

// Examples can assume:
// late Widget tree;
// late Widget editor;
// late Widget preview;
// late SplitController split;
// void save(List<double> shares) {}

/// The shares of the room that the panes of a [SplitView] get, and which
/// panes are collapsed: what an app saves to show the panes as they were,
/// and sets to restore them. A divider dragged or moved by the keys sets
/// them; set by the app, the view lays its panes out again. It notifies
/// its listeners of each change.
///
/// A controller that starts the tree at a quarter of the room, and saves
/// the shares each time the user moves a divider:
///
/// ```dart
/// final split = SplitController(fractions: [1, 3]);
/// split.addListener(() => save(split.fractions));
/// ```
///
/// A view given one listens to it while the view is in the tree; the app
/// that made it disposes of it.
final class SplitController extends ChangeNotifier {
  /// Panes that start with [fractions] of the room, equal shares when
  /// null, and with the panes of [collapsed] collapsed. Fractions for
  /// another number of panes than the view has are replaced by equal
  /// shares.
  SplitController({List<double>? fractions, Set<int> collapsed = const {}})
    : _fractions = fractions == null ? null : _normalized(fractions),
      _collapsed = {...collapsed} {
    _collapsed.forEach(RangeError.checkNotNegative);
  }

  List<double>? _fractions;
  Set<int> _collapsed;
  var _sizes = const <int>[];

  // the number of panes of the view it is given to; null before one
  int? _length;

  /// Each pane's share of the cells the panes get, the dividers' aside: 0
  /// to 1, 1 together. A collapsed pane's share is the one it gets back
  /// when expanded; the others share the room by theirs. Empty until set
  /// or given to a view, which starts it with equal shares.
  ///
  /// Set, the shares are scaled to make 1 together: an [ArgumentError] for
  /// one that is negative or not finite, for none above 0, or for another
  /// number of shares than the view has panes.
  List<double> get fractions => List.unmodifiable(_fractions ?? const []);

  set fractions(List<double> value) {
    final length = _length;
    if (length != null && value.length != length) {
      throw ArgumentError.value(value, 'fractions', 'not $length shares');
    }
    final f = _normalized(value);
    if (!_sameShares(f, _fractions)) {
      _fractions = f;
      notifyListeners();
    }
  }

  /// The collapsed panes, by index from 0: each gets no cells, its
  /// dividers kept to drag it out again. Set, a [RangeError] for an index
  /// of no pane.
  Set<int> get collapsed => Set.unmodifiable(_collapsed);

  set collapsed(Set<int> value) {
    value.forEach(_checkPane);
    if (value.length != _collapsed.length || !_collapsed.containsAll(value)) {
      _collapsed = {...value};
      notifyListeners();
    }
  }

  /// Whether pane [pane] is collapsed.
  bool isCollapsed(int pane) => _collapsed.contains(pane);

  /// Collapses pane [pane]; a [RangeError] for an index of no pane.
  void collapse(int pane) {
    _checkPane(pane);
    if (_collapsed.add(pane)) {
      notifyListeners();
    }
  }

  /// Expands pane [pane] to its share of the room; a [RangeError] for an
  /// index of no pane.
  void expand(int pane) {
    _checkPane(pane);
    if (_collapsed.remove(pane)) {
      notifyListeners();
    }
  }

  /// The cells along the view's axis that each pane got at its last
  /// layout, 0 for a collapsed one; empty before the first.
  List<int> get sizes => List.unmodifiable(_sizes);

  void _checkPane(int pane) {
    final length = _length;
    if (length == null) {
      RangeError.checkNotNegative(pane, 'pane');
    } else {
      RangeError.checkValidIndex(pane, this, 'pane', length);
    }
  }

  /// Fits it to a view of [n] panes: equal shares for those of another
  /// number, and no collapsed pane beyond them. Tells no listener: the
  /// view lays its panes out by it at once.
  void _fit(int n) {
    _length = n;
    if (_fractions?.length != n) {
      _fractions = n == 0 ? const [] : List.filled(n, 1 / n);
    }
    _collapsed.removeWhere((i) => i >= n);
  }

  /// Sets [fractions] and [collapsed] as a divider moved them.
  void _moved(List<double> fractions, Set<int> collapsed) {
    _fractions = fractions;
    _collapsed = collapsed;
    notifyListeners();
  }
}

/// [shares] scaled to make 1 together.
List<double> _normalized(List<double> shares) {
  var sum = 0.0;
  for (final s in shares) {
    if (!s.isFinite || s < 0) {
      throw ArgumentError.value(shares, 'fractions', 'a share of $s');
    }
    sum += s;
  }
  if (sum <= 0) {
    throw ArgumentError.value(shares, 'fractions', 'no share above 0');
  }
  return List.unmodifiable([for (final s in shares) s / sum]);
}

bool _sameShares(List<double> a, List<double>? b) {
  if (b == null || a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// A pane of a [SplitView]: its [child], the fewest and the most cells it
/// gets along the view's axis, and whether the user may collapse it.
///
/// A side bar 15 to 40 cells wide that a divider dragged over it can
/// collapse:
///
/// ```dart
/// SplitPane(child: tree, minSize: 15, maxSize: 40, collapsible: true)
/// ```
@immutable
final class SplitPane {
  /// A pane of [child], at least [minSize] cells (1 by default, 0 or more)
  /// and at most [maxSize] (no limit by default, [minSize] or more).
  const SplitPane({
    required this.child,
    this.minSize = 1,
    this.maxSize,
    this.collapsible = false,
  }) : assert(minSize >= 0, 'a minSize of 0 or more'),
       assert(
         maxSize == null || maxSize >= minSize,
         'a maxSize of minSize or more',
       );

  /// What the pane shows, laid out in the cells it gets.
  final Widget child;

  /// The fewest cells the pane gets while it is not collapsed, unless the
  /// room is short of what the panes take together.
  final int minSize;

  /// The most cells the pane gets; null for no limit.
  final int? maxSize;

  /// Whether a divider dragged over the pane past half its [minSize], or
  /// moved by the keys past it, collapses it. [SplitController.collapse]
  /// collapses any pane.
  final bool collapsible;
}

/// [panes] side by side ([Axis.horizontal], the default) or one below
/// another, with a line between each two, a divider, drawn with [type] in
/// [style] across the view.
///
/// The panes share the cells the dividers leave by the [controller]'s
/// fractions, which a new size of the view keeps: each gets at least its
/// [SplitPane.minSize] and at most its [SplitPane.maxSize] of them, the
/// others sharing the rest; cells all of them leave at their most stay
/// empty after the last one, and a room short of the least they take
/// together is shared by those. A collapsed pane gets no cells and is not
/// painted, hit by the mouse or focusable; its dividers stay, to drag it
/// out again.
///
/// A divider dragged with the left button follows the mouse, the panes on
/// either side of it growing and shrinking as far as their sizes let them:
/// dragged over a [SplitPane.collapsible] pane past half its least it
/// collapses the pane, and back out it expands it. Tab gives a divider the
/// focus: then Left and Right (Up and Down between panes one below
/// another) move it a cell, collapsing a collapsible pane it moves past
/// the least of and expanding a collapsed one it moves into, and Home and
/// End move it as far as it goes; a layer of the focus tree whose keys a
/// `KeyHintsBar` shows, the arrows hinted. While a divider has the focus or
/// is dragged, [focusedStyle] is merged over [style]. The controller's
/// fractions are set from the sizes each move leaves, a pane it collapses
/// keeping its share; keys that come before the panes are laid out again,
/// typed in one read, move the divider on from where the last one left it.
/// With [pointerShapes] the pointer over a divider is
/// [PointerShape.ewResize] (between panes one below another
/// [PointerShape.nsResize]), as [MouseRegion.cursor] sets it where the
/// terminal shows it, which then reports all motion of the mouse.
///
/// The dividers are drawn after the panes and join the lines in their
/// cells ([Divider.merge]). With [shareEdges] the panes on either side of
/// a divider are laid out over its cells too, so that boxes in them whose
/// borders merge ([Border.merge]) share their edges along it, joined where
/// they meet (`┬ ├ ┼`, also with the boxes of a split view inside a pane),
/// the divider drawn over those edges and joining their lines only, so
/// that the text of the [BorderTitle]s on them stays (a blank in one
/// takes the line); the sizes of a pane count them.
/// Otherwise a divider has cells of its own, between the panes.
///
/// It fills the room it gets; along an axis with no bound it is as long as
/// its panes want to be (their max intrinsic sizes), and across one as
/// long as the longest of them wants.
///
/// A file tree beside an editor, their shares in a controller the app
/// keeps (`split`), and a preview below them that the user can collapse:
///
/// ```dart
/// SplitView(
///   direction: Axis.vertical,
///   panes: [
///     SplitPane(
///       child: SplitView(
///         controller: split,
///         panes: [SplitPane(child: tree), SplitPane(child: editor)],
///       ),
///     ),
///     SplitPane(child: preview, collapsible: true),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [DockArea], panels the user can also move, tab and float.
///  * [Row] and [Column], for parts the user does not resize.
final class SplitView extends StatefulWidget {
  /// Lays [panes] out along [direction], across by default, their shares
  /// in [controller], or in one of the view's own.
  const SplitView({
    required this.panes,
    super.key,
    this.direction = Axis.horizontal,
    this.controller,
    this.shareEdges = false,
    this.type = BorderType.single,
    this.style = const Style(),
    this.focusedStyle,
    this.pointerShapes = true,
  });

  /// The panes, from the left or the top; a divider between each two.
  final List<SplitPane> panes;

  /// The axis the panes are laid out along.
  final Axis direction;

  /// The panes' shares of the room and which are collapsed; the view makes
  /// one of its own when null.
  final SplitController? controller;

  /// The lines the dividers are drawn with.
  final BorderType type;

  /// The dividers' lines.
  final Style style;

  /// Merged over [style] for a divider that has the focus or is dragged;
  /// [ThemeData.primary] when null.
  final Style? focusedStyle;

  /// Whether the panes on either side of a divider are laid out over its
  /// cells too, sharing their edges along it.
  final bool shareEdges;

  /// Whether the pointer over a divider has the shape of a resize along
  /// [direction]. False leaves it to the regions around the view.
  final bool pointerShapes;

  @override
  State<SplitView> createState() => _SplitViewState();
}

/// The panes as a divider's press found them: what each drag of it moves
/// the divider from.
final class _Grip {
  _Grip(
    this.divider,
    this.x,
    this.y,
    this.sizes,
    this.fractions,
    this.collapsed,
  );

  final int divider;

  /// The cell of the screen pressed.
  final int x;
  final int y;

  /// The panes' own cells, their shares and those collapsed.
  final List<int> sizes;
  final List<double> fractions;
  final Set<int> collapsed;
}

final class _SplitViewState extends State<SplitView> {
  final GlobalKey _layout = GlobalKey();
  SplitController? _own;

  // a node for each divider, and one above each pane that keeps the focus
  // from a collapsed one
  final _dividers = <FocusNode>[];
  final _panes = <FocusNode>[];

  _Grip? _grip;

  SplitController get _controller =>
      widget.controller ?? (_own ??= SplitController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _fit();
  }

  @override
  void didUpdateWidget(SplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.controller ?? _own!;
    if (!identical(_controller, before)) {
      before.removeListener(_changed);
      _controller.addListener(_changed);
    }
    _fit();
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    for (final node in [..._dividers, ..._panes]) {
      node.dispose();
    }
    _own?.dispose();
    super.dispose();
  }

  /// A node for each pane and each divider, and the controller fitted to
  /// the panes.
  void _fit() {
    final n = widget.panes.length;
    _controller._fit(n);
    while (_panes.length > n) {
      _panes.removeLast().dispose();
    }
    while (_panes.length < n) {
      _panes.add(FocusNode(canRequestFocus: false, skipTraversal: true));
    }
    while (_dividers.length > n - 1) {
      _dividers.removeLast().dispose();
    }
    while (_dividers.length < n - 1) {
      _dividers.add(FocusNode()..addListener(_focused));
    }
    if (_grip case _Grip(:final divider) when divider >= n - 1) {
      _grip = null;
    }
    _keepFocus();
  }

  /// Keeps the focus from the collapsed panes.
  void _keepFocus() {
    final c = _controller;
    for (var i = 0; i < _panes.length; i++) {
      _panes[i].descendantsAreFocusable = !c.isCollapsed(i);
    }
  }

  void _changed() {
    _keepFocus();
    setState(() {});
  }

  void _focused() => setState(() {});

  bool get _across => widget.direction == Axis.horizontal;

  _RenderSplit? get _split =>
      _layout.currentContext?.findRenderObject() as _RenderSplit?;

  /// The least and the most own cells of each pane: those of its
  /// [SplitPane] less the dividers' it shares.
  (List<int>, List<int>) _limits() {
    final panes = widget.panes;
    final n = panes.length;
    final lows = <int>[];
    final highs = <int>[];
    for (var i = 0; i < n; i++) {
      final edges = widget.shareEdges
          ? (i > 0 ? 1 : 0) + (i < n - 1 ? 1 : 0)
          : 0;
      final pane = panes[i];
      final low = pane.minSize > edges ? pane.minSize - edges : 0;
      final max = pane.maxSize;
      lows.add(low);
      highs.add(
        max == null
            ? BoxConstraints.unbounded
            : (max - edges > low ? max - edges : low),
      );
    }
    return (lows, highs);
  }

  void _down(int divider, PointerEvent event) {
    final split = _split;
    if (event.button != 0 || split == null || split.own.isEmpty) {
      return;
    }
    final c = _controller;
    setState(
      () => _grip = _Grip(
        divider,
        event.screenX,
        event.screenY,
        split.own,
        c._fractions!,
        {...c._collapsed},
      ),
    );
  }

  void _drag(int divider, PointerEvent event) {
    final grip = _grip;
    if (grip == null || grip.divider != divider) {
      return;
    }
    final delta = _across ? event.screenX - grip.x : event.screenY - grip.y;
    final move = _Move(grip.sizes, grip.collapsed, _limits(), widget.panes);
    _moveTo(move, grip.fractions, divider, move.nearest(divider, delta));
  }

  void _up(int divider) {
    if (_grip?.divider == divider) {
      setState(() => _grip = null);
    }
  }

  /// Moves [divider] by the keys: a step back (-1) or on (1), or as far as
  /// it goes back (-2) or on (2).
  void _key(int divider, int how) {
    final split = _split;
    if (split == null || split.own.isEmpty) {
      return;
    }
    final c = _controller;
    final limits = _limits();
    // the sizes the controller's shares give, not those of the last layout:
    // a key before the next one moves it from where the last key left it
    final sizes = split.ownBy(c._fractions!, [
      for (var i = 0; i < widget.panes.length; i++) c.isCollapsed(i),
    ], limits);
    final move = _Move(sizes, c._collapsed, limits, widget.panes);
    _moveTo(
      move,
      c._fractions!,
      divider,
      how.abs() == 1 ? move.next(divider, how) : move.farthest(divider, how),
    );
  }

  /// Gives the pane before [divider] [size] own cells and the pane after
  /// it the rest of the two, as [move] found them, and sets the controller
  /// from what that leaves.
  void _moveTo(_Move move, List<double> fractions, int divider, int? size) {
    if (size == null) {
      return;
    }
    final (sizes, collapsed) = move.apply(divider, size);
    final c = _controller;
    final shares = _shares(sizes, collapsed, fractions);
    if (!_sameShares(shares, c._fractions) ||
        collapsed.length != c._collapsed.length ||
        !collapsed.containsAll(c._collapsed)) {
      c._moved(shares, collapsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final panes = widget.panes;
    final n = panes.length;
    final c = _controller;
    final (lows, highs) = _limits();
    final focused = widget.style.merge(
      widget.focusedStyle ?? Theme.of(context).primary,
    );
    return _SplitLayout(
      key: _layout,
      direction: widget.direction,
      shareEdges: widget.shareEdges,
      fractions: c._fractions!,
      collapsed: [for (var i = 0; i < n; i++) c.isCollapsed(i)],
      lows: lows,
      highs: highs,
      controller: c,
      children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) _divider(i - 1, focused),
          Focus(focusNode: _panes[i], child: panes[i].child),
        ],
      ],
    );
  }

  Widget _divider(int k, Style focusedStyle) {
    final node = _dividers[k];
    final style = node.hasFocus || _grip?.divider == k
        ? focusedStyle
        : widget.style;
    final across = _across;
    return Focus(
      focusNode: node,
      child: KeyBindings(
        {
          across ? 'left' : 'up': () => _key(k, -1),
          across ? 'right' : 'down': () => _key(k, 1),
          'home': () => _key(k, -2),
          'end': () => _key(k, 2),
        },
        hints: across ? _acrossHints : _downHints,
        child: MouseRegion(
          cursor: !widget.pointerShapes
              ? null
              : (across ? PointerShape.ewResize : PointerShape.nsResize),
          behavior: HitTestBehavior.deferToChild,
          child: Listener(
            onDown: (event) => _down(k, event),
            onDrag: (event) => _drag(k, event),
            onUp: (event) => _up(k),
            child: across
                ? VerticalDivider(type: widget.type, style: style, merge: true)
                : Divider(type: widget.type, style: style, merge: true),
          ),
        ),
      ),
    );
  }

  static const _acrossHints = {
    'left': 'divider left',
    'right': 'divider right',
  };
  static const _downHints = {'up': 'divider up', 'down': 'divider down'};
}

/// The shares of the panes after a move left them [sizes] own cells and
/// [collapsed]: those collapsed keep theirs of [fractions], the others
/// share the rest by their sizes.
List<double> _shares(
  List<int> sizes,
  Set<int> collapsed,
  List<double> fractions,
) {
  final n = sizes.length;
  var kept = 0.0;
  var cells = 0;
  var shown = 0;
  for (var i = 0; i < n; i++) {
    if (collapsed.contains(i)) {
      kept += fractions[i];
    } else {
      cells += sizes[i];
      shown++;
    }
  }
  if (shown == 0) {
    return fractions;
  }
  final rest = kept < 1 ? 1 - kept : 1.0;
  final shares = List.of(fractions);
  for (var i = 0; i < n; i++) {
    if (!collapsed.contains(i)) {
      shares[i] = cells > 0 ? rest * sizes[i] / cells : rest / shown;
    }
  }
  return _normalized(shares);
}

/// Where a divider may go: the panes' own [sizes], those [collapsed], the
/// least and the most own cells of each and whether it is collapsible.
final class _Move {
  _Move(this.sizes, this.collapsed, (List<int>, List<int>) limits, this.panes)
    : lows = limits.$1,
      highs = limits.$2;

  final List<int> sizes;
  final Set<int> collapsed;
  final List<int> lows;
  final List<int> highs;
  final List<SplitPane> panes;

  /// Whether pane [i] may have [size] own cells: 0 when it is collapsible
  /// or collapsed, else from its least to its most.
  bool _fits(int i, int size) =>
      size == 0 && (panes[i].collapsible || collapsed.contains(i)) ||
      size >= lows[i] && size <= highs[i];

  /// Whether the pane before [divider] may have [size] own cells and the
  /// one after it the rest of the [total] of the two.
  bool _fitsBoth(int divider, int size, int total) =>
      _fits(divider, size) && _fits(divider + 1, total - size);

  /// The size of the pane before [divider] that may be nearest to its own
  /// [delta] cells on, the nearer to its size of two as near; null when
  /// there is none.
  int? nearest(int divider, int delta) {
    final now = sizes[divider];
    final total = now + sizes[divider + 1];
    final to = now + delta;
    int? best;
    for (var size = 0; size <= total; size++) {
      if (_fitsBoth(divider, size, total) &&
          (best == null ||
              (size - to).abs() < (best - to).abs() ||
              (size - to).abs() == (best - to).abs() &&
                  (size - now).abs() < (best - now).abs())) {
        best = size;
      }
    }
    return best;
  }

  /// The size of the pane before [divider] next to its own that it may
  /// have, smaller for a [direction] below 0, larger above; null when
  /// there is none.
  int? next(int divider, int direction) {
    final now = sizes[divider];
    final total = now + sizes[divider + 1];
    for (
      var size = now + direction.sign;
      size >= 0 && size <= total;
      size += direction.sign
    ) {
      if (_fitsBoth(divider, size, total)) {
        return size;
      }
    }
    return null;
  }

  /// The smallest size the pane before [divider] may have for a
  /// [direction] below 0, the largest above; null when it may have none
  /// but its own.
  int? farthest(int divider, int direction) {
    final now = sizes[divider];
    final total = now + sizes[divider + 1];
    final up = direction > 0;
    for (var i = 0; i <= total; i++) {
      final size = up ? total - i : i;
      if (size == now) {
        return null;
      }
      if (_fitsBoth(divider, size, total)) {
        return size;
      }
    }
    return null;
  }

  /// The sizes and the collapsed panes with the pane before [divider] at
  /// [size] own cells and the one after it at the rest of the two: one
  /// left with none collapsed, when it is collapsible or was.
  (List<int>, Set<int>) apply(int divider, int size) {
    final after = [...sizes];
    final total = after[divider] + after[divider + 1];
    after[divider] = size;
    after[divider + 1] = total - size;
    final now = {...collapsed};
    for (final i in [divider, divider + 1]) {
      if (after[i] == 0 && (panes[i].collapsible || collapsed.contains(i))) {
        now.add(i);
      } else {
        now.remove(i);
      }
    }
    return (after, now);
  }
}

/// The panes and the dividers of a [SplitView], laid out as [_RenderSplit]
/// says.
final class _SplitLayout extends MultiChildRenderObjectWidget {
  const _SplitLayout({
    required this.direction,
    required this.shareEdges,
    required this.fractions,
    required this.collapsed,
    required this.lows,
    required this.highs,
    required this.controller,
    super.key,
    super.children,
  });

  final Axis direction;
  final bool shareEdges;
  final List<double> fractions;
  final List<bool> collapsed;
  final List<int> lows;
  final List<int> highs;
  final SplitController controller;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  _RenderSplit createRenderObject(BuildContext context) =>
      _RenderSplit(controller).._configure(this);

  @override
  void updateRenderObject(BuildContext context, _RenderSplit renderObject) =>
      renderObject._configure(this);
}

final class _SplitData extends ParentData with ContainerParentDataMixin {}

/// What a [SplitView] lays out and paints: its panes with a divider
/// between each two, in the order of its children, Tab's order too; the
/// dividers, a cell across each, painted after all of the panes and hit
/// before them. Each pane gets its own cells, those between the dividers
/// beside it, and with [_shareEdges] those dividers' cells too; a
/// collapsed one is laid out with no room, not painted nor hit.
final class _RenderSplit extends RenderObject
    with ContainerRenderObjectMixin<_SplitData> {
  _RenderSplit(this._controller);

  SplitController _controller;
  Axis _direction = Axis.horizontal;
  var _shareEdges = false;
  var _fractions = const <double>[];
  var _collapsed = const <bool>[];
  var _lows = const <int>[];
  var _highs = const <int>[];

  /// The own cells of each pane at the last layout, the dividers' aside;
  /// empty before the first.
  List<int> get own => _own;
  var _own = const <int>[];

  // the cells the panes shared at the last layout, the dividers' aside;
  // null before the first and after one with no bound along the axis
  int? _room;

  /// The own cells of each pane that [fractions] and [collapsed] give, with
  /// the least and the most own cells of [limits], in the room of the last
  /// layout: those the next layout gives them while the room stays. [own]
  /// where the room had no bound, the panes as long as they want.
  List<int> ownBy(
    List<double> fractions,
    List<bool> collapsed,
    (List<int>, List<int>) limits,
  ) {
    final room = _room;
    return room == null
        ? _own
        : _ownCells(room, fractions, collapsed, limits.$1, limits.$2);
  }

  void _configure(_SplitLayout w) {
    if (!identical(w.controller, _controller) ||
        w.direction != _direction ||
        w.shareEdges != _shareEdges ||
        !_sameShares(w.fractions, _fractions) ||
        !_same(w.collapsed, _collapsed) ||
        !_same(w.lows, _lows) ||
        !_same(w.highs, _highs)) {
      _controller = w.controller;
      _direction = w.direction;
      _shareEdges = w.shareEdges;
      _fractions = w.fractions;
      _collapsed = w.collapsed;
      _lows = w.lows;
      _highs = w.highs;
      markNeedsLayout();
    }
  }

  int get _panes => _lows.length;

  bool get _across => _direction == Axis.horizontal;

  /// The dividers' cells along the axis.
  int get _dividers => _panes > 0 ? _panes - 1 : 0;

  /// The cells of the dividers beside pane [i] that it is laid out over.
  int _edges(int i) =>
      _shareEdges ? (i > 0 ? 1 : 0) + (i < _panes - 1 ? 1 : 0) : 0;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('direction', _direction, defaultValue: Axis.horizontal)
      ..add('own', _own);
    if (_shareEdges) {
      properties.addTag('shared edges');
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _SplitData) {
      child.parentData = _SplitData();
    }
  }

  /// The own cells of each pane out of [room], as [_ownCells] gives them.
  List<int> _share(int room) =>
      _ownCells(room, _fractions, _collapsed, _lows, _highs);

  /// The extent of pane [i] along the axis with [own] cells of its own.
  int _extent(int i, int own) => _collapsed[i] ? 0 : own + _edges(i);

  /// The own cells each pane wants at [cross] across: its max intrinsic
  /// size, less the dividers' cells it shares, within its least and most.
  List<int> _wantedOwn(int cross) {
    final own = List<int>.filled(_panes, 0);
    var i = 0;
    for (var child = firstChild; child != null && i < _panes; i++) {
      if (!_collapsed[i]) {
        final wants =
            (_across
                ? child.getMaxIntrinsicWidth(cross)
                : child.getMaxIntrinsicHeight(cross)) -
            _edges(i);
        own[i] = wants < _lows[i]
            ? _lows[i]
            : (wants > _highs[i] ? _highs[i] : wants);
      }
      child = _nextPane(child);
    }
    return own;
  }

  /// The cells along the axis the panes want at [cross] across.
  int _wanted(int cross) {
    var total = _dividers;
    for (final own in _wantedOwn(cross)) {
      total += own;
    }
    return total;
  }

  /// The most cells across that the panes want with [own] cells of their
  /// own, their min or max intrinsic sizes as [max] says.
  int _crossWanted(List<int> own, {required bool max}) {
    var most = 0;
    var i = 0;
    for (var child = firstChild; child != null && i < _panes; i++) {
      if (!_collapsed[i]) {
        final extent = _extent(i, own[i]);
        final wants = switch ((_across, max)) {
          (true, true) => child.getMaxIntrinsicHeight(extent),
          (true, false) => child.getMinIntrinsicHeight(extent),
          (false, true) => child.getMaxIntrinsicWidth(extent),
          (false, false) => child.getMinIntrinsicWidth(extent),
        };
        if (wants > most) {
          most = wants;
        }
      }
      child = _nextPane(child);
    }
    return most;
  }

  int _least() {
    var total = _dividers;
    for (var i = 0; i < _panes; i++) {
      if (!_collapsed[i]) {
        total += _lows[i];
      }
    }
    return total;
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      _across ? _least() : _crossWanted(_share(height - _dividers), max: false);

  @override
  int computeMaxIntrinsicWidth(int height) => _across
      ? _wanted(height)
      : _crossWanted(_share(height - _dividers), max: true);

  @override
  int computeMinIntrinsicHeight(int width) =>
      _across ? _crossWanted(_share(width - _dividers), max: false) : _least();

  @override
  int computeMaxIntrinsicHeight(int width) => _across
      ? _crossWanted(_share(width - _dividers), max: true)
      : _wanted(width);

  @override
  void performLayout(BoxConstraints c) {
    const unbounded = BoxConstraints.unbounded;
    final across = _across;
    final maxMain = across ? c.maxW : c.maxH;
    final maxCross = across ? c.maxH : c.maxW;
    final minMain = across ? c.minW : c.minH;
    final minCross = across ? c.minH : c.minW;
    var main = maxMain;
    final List<int> own;
    if (main < unbounded) {
      final room = _room = main - _dividers;
      own = _share(room);
    } else {
      // as long as the panes want, the cells the constraints add empty
      _room = null;
      own = _wantedOwn(maxCross);
      main = _dividers;
      for (final o in own) {
        main += o;
      }
      main = main < minMain ? minMain : main;
    }
    _own = own;
    var cross = maxCross;
    if (cross >= unbounded) {
      cross = _crossWanted(own, max: true);
      cross = cross < minCross ? minCross : cross;
    }
    // each pane its own cells after the divider before it, over that
    // divider's cell too when they share it, and the divider after it
    final sizes = List<int>.filled(_panes, 0);
    var at = 0;
    var child = firstChild;
    for (var i = 0; i < _panes && child != null; i++) {
      final start = i > 0 && _shareEdges ? at - 1 : at;
      final extent = _extent(i, own[i]);
      sizes[i] = extent;
      _place(child, start, extent, _collapsed[i] ? 0 : cross);
      at += own[i];
      child = childAfter(child);
      if (i < _dividers && child != null) {
        _place(child, at, 1, cross);
        at++;
        child = childAfter(child);
      }
    }
    width = across ? main : cross;
    height = across ? cross : main;
    _controller._sizes = List.unmodifiable(sizes);
    _markJoins();
  }

  /// Lays [child] out [extent] cells along the axis from [start] and
  /// [cross] across.
  void _place(RenderObject child, int start, int extent, int cross) {
    final at = child.parentData;
    if (_across) {
      child.layout(BoxConstraints.tight(extent, cross));
      at
        ..dx = start
        ..dy = 0;
    } else {
      child.layout(BoxConstraints.tight(cross, extent));
      at
        ..dx = 0
        ..dy = start;
    }
  }

  // the dividers of the split view across this one that joined this one's
  // dividers at the last layout, beside the pane this one fills; null for
  // none. Where along this one's axis its dividers were then, while they
  // joined any.
  RenderObject? _joinedBefore;
  RenderObject? _joinedAfter;
  var _joinsAt = const <int>[];

  /// Has the split view across this one whose pane this one fills paint
  /// the dividers beside that pane again when the joints they draw with
  /// this one's dividers ([_join]) changed: those dividers moved, or are
  /// no longer joined, or others are. This one is laid out on its own
  /// when they move; a layout that leaves them where they were marks
  /// nothing.
  void _markJoins() {
    RenderObject? before;
    RenderObject? after;
    RenderObject pane = this;
    for (var p = parent; p != null; pane = p, p = p.parent) {
      if (p is _RenderSplit) {
        if (!p._shareEdges &&
            p._direction != _direction &&
            identical(_filledBy(pane), this)) {
          before = p.childBefore(pane);
          after = p.childAfter(pane);
        }
        break;
      }
      // only what this one fills, as _filledBy finds it
      if (p.isRepaintBoundary || p.width != width || p.height != height) {
        break;
      }
    }
    final joined = before != null || after != null;
    final moved = joined && _joinsMoved();
    if (!moved &&
        identical(before, _joinedBefore) &&
        identical(after, _joinedAfter)) {
      return;
    }
    for (final d in [_joinedBefore, _joinedAfter]) {
      if (d != null &&
          d.owner != null &&
          !identical(d, before) &&
          !identical(d, after)) {
        d.markNeedsPaint();
      }
    }
    before?.markNeedsPaint();
    after?.markNeedsPaint();
    _joinedBefore = before;
    _joinedAfter = after;
    _joinsAt = joined ? _dividersAt() : const <int>[];
  }

  /// Whether this one's dividers are not where [_joinsAt] says.
  bool _joinsMoved() {
    final at = _joinsAt;
    var i = 0;
    for (var p = firstChild; p != null; p = _nextPane(p)) {
      final d = childAfter(p);
      if (d == null) {
        break;
      }
      if (i == at.length || at[i] != _along(d)) {
        return true;
      }
      i++;
    }
    return i != at.length;
  }

  /// Where along the axis each divider is.
  List<int> _dividersAt() => [
    for (var p = firstChild; p != null; p = _nextPane(p))
      if (childAfter(p) case final d?) _along(d),
  ];

  /// Where [child] is along the axis.
  int _along(RenderObject child) =>
      _across ? child.parentData.dx : child.parentData.dy;

  /// The pane after the divider after [pane]; null after the last.
  RenderObject? _nextPane(RenderObject pane) {
    final divider = childAfter(pane);
    return divider == null ? null : childAfter(divider);
  }

  @override
  void paint(PaintContext ctx) {
    for (var pane = firstChild; pane != null; pane = _nextPane(pane)) {
      if (pane.width > 0 && pane.height > 0) {
        paintChild(ctx, pane);
      }
    }
    for (var pane = firstChild; pane != null; pane = _nextPane(pane)) {
      if (childAfter(pane) case final divider?) {
        paintChild(ctx, divider);
        if (!_shareEdges) {
          _join(ctx, divider, pane, before: true);
          _join(ctx, divider, _nextPane(pane), before: false);
        }
      }
    }
  }

  /// Joins [divider] with the dividers of a split view across this one
  /// that fills [pane], the pane [before] it or after it, where they meet
  /// it: an arm reaching into the pane from the cell of each (`├ ┤ ┼`).
  /// With shared edges the dividers merge in the cells they share.
  void _join(
    PaintContext ctx,
    RenderObject divider,
    RenderObject? pane, {
    required bool before,
  }) {
    if (pane == null) {
      return;
    }
    final inner = _filledBy(pane);
    final line = switch (divider) {
      RenderMouseRegion(
        child: RenderListener(child: final RenderDivider line),
      ) =>
        line,
      _ => null,
    };
    if (inner == null ||
        inner._direction == _direction ||
        line == null ||
        line.type == BorderType.none) {
      return;
    }
    final canvas = ctx.canvas;
    // box drawing is East Asian ambiguous: two columns where those are
    final type = canvas.segmenter.ambiguousWidth == 1
        ? line.type
        : BorderType.ascii;
    final across = _across;
    final arm = type.glyph(
      up: !across && before,
      right: across && !before,
      down: !across && !before,
      left: across && before,
    );
    final run = _arm..glyphs[0] = arm;
    final pen = canvas.styles.pen(line.pen);
    final x = divider.parentData.dx;
    final y = divider.parentData.dy;
    for (var p = inner.firstChild; p != null; p = inner._nextPane(p)) {
      final d = inner.childAfter(p);
      if (d == null) {
        break;
      }
      // where the inner divider is along this one
      final at = across ? d.parentData.dy : d.parentData.dx;
      canvas.mergeRun(across ? x : at, across ? at : y, run, pen);
    }
  }

  final _arm = GlyphRun(Uint32List(1), 1);

  /// The split view that fills [o]: [o], or the one child of an object
  /// that does, at its top left and as big; null for none, and for one in
  /// a repaint boundary, whose dividers may move without this object
  /// painting again.
  static _RenderSplit? _filledBy(RenderObject o) {
    for (RenderObject? r = o; r != null;) {
      if (r.isRepaintBoundary) {
        return null;
      }
      if (r is _RenderSplit) {
        return r;
      }
      RenderObject? only;
      var count = 0;
      r.visitChildren((c) {
        only = c;
        count++;
      });
      final c = only;
      if (count != 1 ||
          c == null ||
          c.parentData.dx != 0 ||
          c.parentData.dy != 0 ||
          c.width != r.width ||
          c.height != r.height) {
        return null;
      }
      r = c;
    }
    return null;
  }

  /// The dividers first, from the last back, then the panes.
  @override
  bool hitTestChildren(HitTestResult result, int x, int y) {
    for (final dividers in const [true, false]) {
      var j = childCount - 1;
      for (var child = lastChild; child != null; child = childBefore(child)) {
        // the children at odd indices are the dividers
        if (j.isOdd == dividers) {
          final at = child.parentData;
          if (child.hitTest(result, x - at.dx, y - at.dy)) {
            return true;
          }
        }
        j--;
      }
    }
    return false;
  }
}

/// The own cells of each pane out of [room], none for one [collapsed]: by
/// their [fractions], within their least and most ([lows], [highs]), those
/// that reach a limit kept at it and the others sharing the rest; by their
/// least when the room is short of it. Whole cells: rounded down, the
/// cells left given one each to the largest remainders, the first of equal
/// ones first.
List<int> _ownCells(
  int room,
  List<double> fractions,
  List<bool> collapsed,
  List<int> lows,
  List<int> highs,
) {
  final n = lows.length;
  final own = List<int>.filled(n, 0);
  final free = [
    for (var i = 0; i < n; i++)
      if (!collapsed[i]) i,
  ];
  if (free.isEmpty || room <= 0) {
    return own;
  }
  final ideal = List<double>.filled(n, 0);
  var least = 0;
  for (final i in free) {
    least += lows[i];
  }
  if (least >= room) {
    for (final i in free) {
      ideal[i] = room * lows[i] / least;
    }
    _round(room, free, ideal, own, highs);
    return own;
  }
  var budget = room;
  while (free.isNotEmpty) {
    var weight = 0.0;
    for (final i in free) {
      weight += fractions[i];
    }
    var excess = 0.0;
    for (final i in free) {
      final share = weight > 0
          ? budget * fractions[i] / weight
          : budget / free.length;
      ideal[i] = share;
      excess +=
          (share < lows[i] ? lows[i] : (share > highs[i] ? highs[i] : share)) -
          share;
    }
    if (excess.abs() < 1e-9) {
      break;
    }
    // those beyond the limit the excess is of: the rest share what they
    // leave
    free.removeWhere((i) {
      final limit = excess > 0 ? lows[i] : highs[i];
      if (excess > 0 ? ideal[i] < limit : ideal[i] > limit) {
        own[i] = limit;
        budget -= limit;
        return true;
      }
      return false;
    });
  }
  _round(budget, free, ideal, own, highs);
  return own;
}

/// Gives each of [panes] its [ideal] cells in whole cells, [cells] of
/// them together, within its most of [highs].
void _round(
  int cells,
  List<int> panes,
  List<double> ideal,
  List<int> own,
  List<int> highs,
) {
  var left = cells;
  for (final i in panes) {
    final whole = (ideal[i] + 1e-9).floor();
    own[i] = whole;
    left -= whole;
  }
  final order = [...panes]
    ..sort((a, b) {
      final byRemainder = (ideal[b] - own[b]).compareTo(ideal[a] - own[a]);
      return byRemainder != 0 ? byRemainder : a.compareTo(b);
    });
  for (final i in order) {
    if (left <= 0) {
      break;
    }
    if (own[i] < highs[i]) {
      own[i]++;
      left--;
    }
  }
}

bool _same<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
