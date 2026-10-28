part of 'render.dart';

// ------------------------------------------------------------------ flex --

/// A direction on the screen: the main axis of a [RenderFlex] or a
/// [RenderWrap], the axis a [RenderViewport] scrolls along, the line of a
/// [RenderDivider].
enum Axis {
  /// Across: along a row, from left to right.
  horizontal,

  /// Down: along a column, from top to bottom.
  vertical,
}

/// How long a [RenderFlex] is along its main axis.
enum MainAxisSize {
  /// As long as its children and the gaps between them, or as the
  /// constraints ask if that is more.
  min,

  /// As long as the constraints allow.
  max,
}

/// Where a [RenderFlex] puts its children along its main axis, in the
/// cells they and the gaps leave free. The free cells are shared out in
/// whole cells: those an even split leaves over go to the first spaces.
enum MainAxisAlignment {
  /// From the start.
  start,

  /// To the end.
  end,

  /// In the middle; the odd cell after them.
  center,

  /// The free cells between the children; a single child at the start.
  spaceBetween,

  /// The free cells around each child, half before it and half after.
  spaceAround,

  /// The free cells before, between and after the children.
  spaceEvenly,
}

/// Where a [RenderFlex] puts each child across its main axis.
enum CrossAxisAlignment {
  /// At the start.
  start,

  /// At the end.
  end,

  /// In the middle; the odd cell after it.
  center,

  /// Across the whole flex: each child is made as thick as the flex may
  /// be.
  stretch,
}

/// How a flexible child takes its share of the free cells.
enum FlexFit {
  /// All of it.
  tight,

  /// As much of it as the child wants.
  loose,
}

/// What a [RenderFlex] keeps on a child: its offset, its siblings, and how
/// it shares the cells the inflexible children leave.
final class FlexParentData extends ParentData with ContainerParentDataMixin {
  /// The data of a child not laid out yet: inflexible, at the origin.
  FlexParentData();

  /// The child's part of the free cells, against the other children's; 0
  /// makes it inflexible: laid out first, as long as it wants.
  var flex = 0;

  /// How a flexible child takes its share.
  FlexFit fit = FlexFit.tight;

  // the fixed length of a child of a RenderColumn or RenderRow
  int? _extent;

  /// The flex factor of a flexible child and a loose fit; the fixed length
  /// of a child of a [RenderColumn] or a [RenderRow].
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('flex', flex, defaultValue: 0);
    if (flex > 0) {
      properties.add('fit', fit, defaultValue: FlexFit.tight);
    }
    properties.add('extent', _extent, defaultValue: null);
  }
}

/// Lays [child] out, as a parent that uses its size, within [minW]..[maxW]
/// and [minH]..[maxH]; the constraints it was last given are reused when
/// they are the same, so a layout like the last allocates nothing.
void _layoutChild(
  RenderObject child,
  int minW,
  int maxW,
  int minH,
  int maxH,
) {
  final c = child._constraints;
  child.layout(
    c != null &&
            c.minW == minW &&
            c.maxW == maxW &&
            c.minH == minH &&
            c.maxH == maxH
        ? c
        : BoxConstraints(minW, maxW, minH, maxH),
    parentUsesSize: true,
  );
}

/// Part [k] of [free] cells split into [parts] even parts, the cells left
/// over going to the first parts.
int _part(int free, int parts, int k) =>
    free ~/ parts + (k < free % parts ? 1 : 0);

/// Lays its children out one after another along its main axis
/// ([direction]), [gap] cells apart. The inflexible ones (a
/// [FlexParentData.flex] of 0) come first, each as long as it wants up to
/// the whole main axis; the flexible ones share the cells left by their
/// flex factors, in whole cells, those left over going to the first
/// flexible children. Then [mainAxisAlignment] and [crossAxisAlignment]
/// place them. Children that don't fit are cut off at the bounds of the
/// flex and, in debug, reported once as a warning in the [log].
///
/// Along an unbounded main axis (in a [RenderViewport]) there are no cells
/// to share: each child is as long as it wants, the flexible ones too, and
/// the flex as long as they are, whatever its [mainAxisSize].
///
/// A child's flex factor and fit are on its [FlexParentData], set once it
/// is a child. A row with a label, a flexible middle and a label at the
/// end, a cell apart:
///
/// ```dart
/// RenderParagraph label(String s) => RenderParagraph([(s, const Pen())]);
/// final middle = RenderBox(pen: StyleTable().pen(const Pen()));
/// final bar = RenderFlex(
///   gap: 1,
///   children: [label('main'), middle, label('12:00')],
/// );
/// (middle.parentData as FlexParentData).flex = 1;
/// ```
///
/// See also:
///
///  * [RenderRow] and [RenderColumn], flexes of children each of a fixed
///    length or flexible, stretched across.
///  * [RenderWrap], which starts a new run where a child would not fit.
final class RenderFlex extends RenderObject
    with ContainerRenderObjectMixin<FlexParentData> {
  /// A flex of [children] along [direction], horizontal unless given,
  /// [gap] cells apart, 0 or more; as long as it may be, the children at
  /// the start and in the middle across unless given.
  RenderFlex({
    List<RenderObject>? children,
    this._direction = Axis.horizontal,
    this._mainAxisSize = MainAxisSize.max,
    this._mainAxisAlignment = MainAxisAlignment.start,
    this._crossAxisAlignment = CrossAxisAlignment.center,
    this._gap = 0,
  }) : assert(_gap >= 0, 'a gap of 0 cells or more') {
    addAll(children);
  }

  Axis _direction;

  /// The main axis, along which the children go one after another.
  Axis get direction => _direction;
  set direction(Axis d) {
    if (d != _direction) {
      _direction = d;
      markNeedsLayout();
    }
  }

  MainAxisSize _mainAxisSize;

  /// Whether the flex is as long as it may be along its main axis
  /// ([MainAxisSize.max]) or as its children and gaps ([MainAxisSize.min]).
  MainAxisSize get mainAxisSize => _mainAxisSize;
  set mainAxisSize(MainAxisSize s) {
    if (s != _mainAxisSize) {
      _mainAxisSize = s;
      markNeedsLayout();
    }
  }

  MainAxisAlignment _mainAxisAlignment;

  /// Where the children go along the main axis in the cells they and the
  /// gaps leave free.
  MainAxisAlignment get mainAxisAlignment => _mainAxisAlignment;
  set mainAxisAlignment(MainAxisAlignment a) {
    if (a != _mainAxisAlignment) {
      _mainAxisAlignment = a;
      markNeedsLayout();
    }
  }

  CrossAxisAlignment _crossAxisAlignment;

  /// Where each child goes across the main axis, or whether it is
  /// stretched across the flex.
  CrossAxisAlignment get crossAxisAlignment => _crossAxisAlignment;
  set crossAxisAlignment(CrossAxisAlignment a) {
    if (a != _crossAxisAlignment) {
      _crossAxisAlignment = a;
      markNeedsLayout();
    }
  }

  int _gap;

  /// The cells between one child and the next, 0 or more, on top of what
  /// [mainAxisAlignment] puts between them.
  int get gap => _gap;
  set gap(int g) {
    assert(g >= 0, 'a gap of 0 cells or more');
    if (g != _gap) {
      _gap = g;
      markNeedsLayout();
    }
  }

  // the overflow was reported (debug)
  var _overflowReported = false;

  // the children in order, for the bisection that finds those the clip
  // shows ([paint]); listed by the first paint that needs them after a
  // layout, since any change to the children lays this flex out
  List<RenderObject>? _children;
  var _childrenListed = false;

  /// The direction and the settings that aren't the defaults; once laid
  /// out, the cells its children and gaps need beyond it along the main
  /// axis, if any, with the [DiagnosticsFlag.overflow] flag.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..addTag(_direction.name)
      ..add('mainAxisSize', _mainAxisSize, defaultValue: MainAxisSize.max)
      ..add(
        'mainAxisAlignment',
        _mainAxisAlignment,
        defaultValue: MainAxisAlignment.start,
      )
      ..add(
        'crossAxisAlignment',
        _crossAxisAlignment,
        defaultValue: CrossAxisAlignment.center,
      )
      ..add('gap', _gap, defaultValue: 0);
    if (_constraints == null) {
      return;
    }
    final horizontal = _direction == Axis.horizontal;
    var used = _gaps;
    for (var c = _firstChild; c != null;) {
      used += horizontal ? c.width : c.height;
      c = (c.parentData as FlexParentData).nextSibling;
    }
    final over = used - (horizontal ? width : height);
    if (over > 0) {
      final unit = horizontal ? 'column' : 'row';
      properties
        ..addMessage('overflow', '$over $unit${over == 1 ? '' : 's'}')
        ..flag(DiagnosticsFlag.overflow);
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! FlexParentData) {
      child.parentData = FlexParentData();
    }
  }

  /// Adds [lines] as (child, fixed length along the main axis, or null for
  /// a flexible child).
  void _addLines(List<(RenderObject, int?)> lines) {
    for (final (child, extent) in lines) {
      add(child);
      final at = child.parentData as FlexParentData;
      if (extent == null) {
        at.flex = 1;
      } else {
        at._extent = extent;
      }
    }
  }

  int get _gaps => _childCount > 1 ? _gap * (_childCount - 1) : 0;

  /// The cells the flexible children, [total] flex factors in all, share
  /// of [free] cells before the cells left over.
  int _shared(int free, int total) {
    var shared = 0;
    for (var c = _firstChild; c != null;) {
      final at = c.parentData as FlexParentData;
      if (at._extent == null) {
        shared += free * at.flex ~/ total;
      }
      c = at.nextSibling;
    }
    return shared;
  }

  @override
  void performLayout(BoxConstraints c) {
    _childrenListed = false;
    final horizontal = _direction == Axis.horizontal;
    final maxMain = horizontal ? c.maxW : c.maxH;
    final maxCross = horizontal ? c.maxH : c.maxW;
    final minCross = _crossAxisAlignment == CrossAxisAlignment.stretch
        ? maxCross
        : 0;
    final bounded = maxMain < BoxConstraints.unbounded;
    // the inflexible children first
    var used = _gaps;
    var total = 0;
    var cross = 0;
    for (var child = _firstChild; child != null;) {
      final at = child.parentData as FlexParentData;
      final extent = at._extent;
      if (extent == null && at.flex > 0 && bounded) {
        total += at.flex;
      } else {
        final lo = extent ?? 0;
        final hi = extent ?? maxMain;
        if (horizontal) {
          _layoutChild(child, lo, hi, minCross, maxCross);
        } else {
          _layoutChild(child, minCross, maxCross, lo, hi);
        }
        used += horizontal ? child.width : child.height;
        final t = horizontal ? child.height : child.width;
        cross = t > cross ? t : cross;
      }
      child = at.nextSibling;
    }
    // then the flexible ones, in the cells left
    if (total > 0) {
      final free = maxMain - used < 0 ? 0 : maxMain - used;
      var leftover = free - _shared(free, total);
      for (var child = _firstChild; child != null;) {
        final at = child.parentData as FlexParentData;
        if (at._extent == null && at.flex > 0) {
          var share = free * at.flex ~/ total;
          if (leftover > 0) {
            share++;
            leftover--;
          }
          final lo = at.fit == FlexFit.tight ? share : 0;
          if (horizontal) {
            _layoutChild(child, lo, share, minCross, maxCross);
          } else {
            _layoutChild(child, minCross, maxCross, lo, share);
          }
          used += horizontal ? child.width : child.height;
          final t = horizontal ? child.height : child.width;
          cross = t > cross ? t : cross;
        }
        child = at.nextSibling;
      }
    }
    final main = _mainAxisSize == MainAxisSize.max && bounded
        ? maxMain
        : (horizontal ? c.constrainW(used) : c.constrainH(used));
    cross = horizontal ? c.constrainH(cross) : c.constrainW(cross);
    width = horizontal ? main : cross;
    height = horizontal ? cross : main;
    assert(_debugReportOverflow(used - main), 'reports the overflow');
    _place(main - used < 0 ? 0 : main - used, cross);
  }

  /// Places the children, [free] cells along the main axis left free by
  /// them, in a flex [cross] thick.
  void _place(int free, int cross) {
    final n = _childCount;
    if (n == 0) {
      return;
    }
    final horizontal = _direction == Axis.horizontal;
    // the free cells as even parts: before the first child, and after
    // each child
    final parts = switch (_mainAxisAlignment) {
      MainAxisAlignment.spaceBetween => n - 1,
      MainAxisAlignment.spaceAround => 2 * n,
      MainAxisAlignment.spaceEvenly => n + 1,
      _ => 0,
    };
    var at = switch (_mainAxisAlignment) {
      MainAxisAlignment.start || MainAxisAlignment.spaceBetween => 0,
      MainAxisAlignment.end => free,
      MainAxisAlignment.center => free ~/ 2,
      _ => _part(free, parts, 0),
    };
    var i = 0;
    for (var child = _firstChild; child != null;) {
      final data = child.parentData as FlexParentData;
      final thick = horizontal ? child.height : child.width;
      final across = switch (_crossAxisAlignment) {
        CrossAxisAlignment.end => cross - thick,
        CrossAxisAlignment.center => (cross - thick) ~/ 2,
        _ => 0,
      };
      data
        ..dx = horizontal ? at : across
        ..dy = horizontal ? across : at;
      at += (horizontal ? child.width : child.height) + _gap;
      if (parts > 0) {
        at += switch (_mainAxisAlignment) {
          MainAxisAlignment.spaceBetween => _part(free, parts, i),
          MainAxisAlignment.spaceAround =>
            _part(free, parts, 2 * i + 1) + _part(free, parts, 2 * i + 2),
          _ => _part(free, parts, i + 1),
        };
      }
      i++;
      child = data.nextSibling;
    }
  }

  /// Logs a warning the first time children overflow the flex, with the
  /// cells they need beyond it.
  bool _debugReportOverflow(int over) {
    if (over > 0 && !_overflowReported) {
      _overflowReported = true;
      final horizontal = _direction == Axis.horizontal;
      final unit = '${horizontal ? 'column' : 'row'}${over == 1 ? '' : 's'}';
      final side = horizontal ? 'right' : 'bottom';
      _warn('A RenderFlex overflowed by $over $unit on the $side.');
    }
    return true;
  }

  // what the children ask for, worked out as the layout shares the cells

  @override
  int computeMinIntrinsicWidth(int height) => _direction == Axis.horizontal
      ? _alongMain(_minWidth, height)
      : _acrossMain(_minWidth, _maxHeight, height);

  @override
  int computeMaxIntrinsicWidth(int height) => _direction == Axis.horizontal
      ? _alongMain(_maxWidth, height)
      : _acrossMain(_maxWidth, _maxHeight, height);

  @override
  int computeMinIntrinsicHeight(int width) => _direction == Axis.horizontal
      ? _acrossMain(_minHeight, _maxWidth, width)
      : _alongMain(_minHeight, width);

  @override
  int computeMaxIntrinsicHeight(int width) => _direction == Axis.horizontal
      ? _acrossMain(_maxHeight, _maxWidth, width)
      : _alongMain(_maxHeight, width);

  /// The intrinsic size of [kind] along the main axis, [cross] across it:
  /// the inflexible children and the gaps, plus the fewest cells whose
  /// shares give each flexible child what it asks for.
  int _alongMain(int kind, int cross) {
    var sum = _gaps;
    var total = 0;
    // the flexible child that asks the most per flex factor: asks / per
    var asks = 0;
    var per = 1;
    for (var child = _firstChild; child != null;) {
      final at = child.parentData as FlexParentData;
      final extent = at._extent;
      if (extent != null) {
        sum += extent;
      } else if (at.flex > 0) {
        total += at.flex;
        final a = child._intrinsic(kind, cross);
        if (a * per > asks * at.flex) {
          asks = a;
          per = at.flex;
        }
      } else {
        sum += child._intrinsic(kind, cross);
      }
      child = at.nextSibling;
    }
    return sum + (asks * total + per - 1) ~/ per;
  }

  /// The intrinsic size of [kind] across the main axis, [main] long: the
  /// most a child asks for at the length it would get. An inflexible
  /// child gets what it asks for ([mainKind]) up to [main], the flexible
  /// ones share the rest.
  int _acrossMain(int kind, int mainKind, int main) {
    var used = _gaps;
    var total = 0;
    var most = 0;
    for (var child = _firstChild; child != null;) {
      final at = child.parentData as FlexParentData;
      final extent = at._extent;
      if (extent == null && at.flex > 0) {
        total += at.flex;
      } else {
        var length =
            extent ?? child._intrinsic(mainKind, BoxConstraints.unbounded);
        if (extent == null && length > main) {
          length = main;
        }
        used += length;
        final a = child._intrinsic(kind, length);
        most = a > most ? a : most;
      }
      child = at.nextSibling;
    }
    if (total > 0) {
      final free = main - used < 0 ? 0 : main - used;
      var leftover = free - _shared(free, total);
      for (var child = _firstChild; child != null;) {
        final at = child.parentData as FlexParentData;
        if (at._extent == null && at.flex > 0) {
          var share = free * at.flex ~/ total;
          if (leftover > 0) {
            share++;
            leftover--;
          }
          final a = child._intrinsic(kind, share);
          most = a > most ? a : most;
        }
        child = at.nextSibling;
      }
    }
    return most;
  }

  /// Paints the children the clip shows. They follow each other along the
  /// main axis, none over another, so those are a run of them: all of them
  /// when the clip shows the first and the last, else the run is found by
  /// bisection over their offsets. A child out of the run is not visited,
  /// unless something inside it is [paintedWhenCutOff].
  @override
  void paint(PaintContext ctx) {
    final n = _childCount;
    final canvas = ctx.canvas;
    if (n < 3 ||
        (_endsIn(canvas, _firstChild!) && _startsIn(canvas, _lastChild!))) {
      for (var child = _firstChild; child != null;) {
        paintChild(ctx, child);
        child = (child.parentData as FlexParentData).nextSibling;
      }
      return;
    }
    final children = _inOrder();
    // the first child the clip shows a cell before the end of
    var lo = 0;
    var hi = n;
    while (lo < hi) {
      final m = (lo + hi) >> 1;
      if (_endsIn(canvas, children[m])) {
        hi = m;
      } else {
        lo = m + 1;
      }
    }
    final first = lo;
    // the first child after it the clip shows no cell from the start of on
    hi = n;
    while (lo < hi) {
      final m = (lo + hi) >> 1;
      if (_startsIn(canvas, children[m])) {
        lo = m + 1;
      } else {
        hi = m;
      }
    }
    final end = lo;
    // something inside a child cut off is painted however it is
    final cutOff = _cutOffPainters > (_paintedWhenCutOff ? 1 : 0);
    for (var i = cutOff ? 0 : first; i < first; i++) {
      if (children[i]._cutOffPainters != 0) {
        paintChild(ctx, children[i]);
      }
    }
    for (var i = first; i < end; i++) {
      paintChild(ctx, children[i]);
    }
    for (var i = cutOff ? end : n; i < n; i++) {
      if (children[i]._cutOffPainters != 0) {
        paintChild(ctx, children[i]);
      }
    }
  }

  /// The children in order, listed again after a layout.
  List<RenderObject> _inOrder() {
    final list = _children ??= [];
    if (!_childrenListed) {
      list.clear();
      for (var child = _firstChild; child != null;) {
        list.add(child);
        child = (child.parentData as FlexParentData).nextSibling;
      }
      _childrenListed = true;
    }
    assert(list.length == _childCount, 'the children listed are the children');
    return list;
  }

  /// Whether the clip has a cell of this flex before the end of [child]
  /// along the main axis, anywhere across.
  bool _endsIn(Canvas canvas, RenderObject child) {
    final at = child.parentData;
    return _direction == Axis.horizontal
        ? _clipMeets(canvas, -_far, -_far, at.dx + child.width + _far, 2 * _far)
        : _clipMeets(
            canvas,
            -_far,
            -_far,
            2 * _far,
            at.dy + child.height + _far,
          );
  }

  /// Whether the clip has a cell of this flex from the start of [child]
  /// on along the main axis, anywhere across.
  bool _startsIn(Canvas canvas, RenderObject child) {
    final at = child.parentData;
    return _direction == Axis.horizontal
        ? _clipMeets(canvas, at.dx, -_far, _far, 2 * _far)
        : _clipMeets(canvas, -_far, at.dy, 2 * _far, _far);
  }
}

// farther than any cell, in a test of the clip
const int _far = 1 << 30;

/// Whether the clip of [canvas] has a cell in the rectangle [x], [y],
/// [w] × [h] of its own; the canvas is left as it was.
bool _clipMeets(Canvas canvas, int x, int y, int w, int h) {
  canvas
    ..save()
    ..clipRect(x, y, w, h);
  // an empty clip is (0, 0, 0, 0)
  final (x0, _, x1, _) = canvas.clipBounds;
  canvas.restore();
  return x0 < x1;
}

/// A column of children of fixed heights and flexible ones, which share
/// the rows the fixed ones leave; each child is as wide as the column.
final class RenderColumn extends RenderFlex {
  /// [children] as (child, fixed height or null = flexible).
  RenderColumn(List<(RenderObject, int?)> children)
    : super(
        direction: Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ) {
    _addLines(children);
  }
}

/// A row of children of fixed widths and flexible ones, which share the
/// columns the fixed ones leave; each child is as tall as the row.
final class RenderRow extends RenderFlex {
  /// [children] as (child, fixed width or null = flexible).
  RenderRow(List<(RenderObject, int?)> children)
    : super(crossAxisAlignment: CrossAxisAlignment.stretch) {
    _addLines(children);
  }
}
