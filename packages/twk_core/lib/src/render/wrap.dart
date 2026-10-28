part of 'render.dart';

// ------------------------------------------------------------------ wrap --

/// Where a [RenderWrap] puts the children of a run along its main axis, in
/// the cells they and the gaps leave free, or its runs across it. The free
/// cells are shared out in whole cells: those an even split leaves over go
/// to the first spaces.
enum WrapAlignment {
  /// From the start.
  start,

  /// To the end.
  end,

  /// In the middle; the odd cell after them.
  center,

  /// The free cells between them; a single one at the start.
  spaceBetween,

  /// The free cells around each, half before it and half after.
  spaceAround,

  /// The free cells before, between and after them.
  spaceEvenly,
}

/// Where a [RenderWrap] puts each child across its main axis, in its run.
enum WrapCrossAlignment {
  /// At the start of the run.
  start,

  /// At the end of the run.
  end,

  /// In the middle of the run; the odd cell after it.
  center,
}

/// What a [RenderWrap] keeps on a child: its offset and its siblings.
final class WrapParentData extends ParentData with ContainerParentDataMixin {
  /// The data of a child not laid out yet, at the origin.
  WrapParentData();
}

/// Lays its children out in runs (Yoga's flexWrap): one after another
/// along its main axis ([direction]), [gap] cells apart, each as long as it
/// wants up to the whole main axis, until the next would not fit; that one
/// starts a new run, [runGap] cells on across the main axis. Each run is
/// as thick as its thickest child. [alignment] places the children of each
/// run along it, [crossAxisAlignment] each child in its run, and
/// [runAlignment] the runs across the wrap.
///
/// The wrap is as long as its longest run and as thick as its runs and the
/// gaps between them, or as the constraints ask if that is more: what
/// [alignment] shares out is what a run leaves of the longest, or of the
/// length the constraints ask for. Runs that don't fit are cut off at the
/// bounds of the wrap and, in debug, reported once as a warning in the
/// [log].
///
/// Along an unbounded main axis (in a [RenderViewport]) nothing wraps: the
/// children make one run.
///
/// Tags a cell apart, on as many rows as they need:
///
/// ```dart
/// final tags = RenderWrap(
///   gap: 1,
///   children: [
///     for (final tag in ['dart', 'twk', 'terminal', 'unicode'])
///       RenderParagraph([('#$tag', const Pen())]),
///   ],
/// );
/// ```
///
/// See also:
///
///  * [RenderFlex], which keeps its children on one line and shares out
///    the cells they leave.
final class RenderWrap extends RenderObject
    with ContainerRenderObjectMixin<WrapParentData> {
  /// A wrap of [children] along [direction], horizontal unless given,
  /// [gap] cells apart in a run and [runGap] between runs, each 0 or more;
  /// everything at the start unless given.
  RenderWrap({
    List<RenderObject>? children,
    this._direction = Axis.horizontal,
    this._alignment = WrapAlignment.start,
    this._runAlignment = WrapAlignment.start,
    this._crossAxisAlignment = WrapCrossAlignment.start,
    this._gap = 0,
    this._runGap = 0,
  }) : assert(_gap >= 0 && _runGap >= 0, 'gaps of 0 cells or more') {
    addAll(children);
  }

  Axis _direction;

  /// The main axis, along which the children of a run go one after
  /// another; the runs go across it.
  Axis get direction => _direction;
  set direction(Axis d) {
    if (d != _direction) {
      _direction = d;
      markNeedsLayout();
    }
  }

  WrapAlignment _alignment;

  /// Where the children of each run go along it, in the cells they and the
  /// gaps leave of the wrap's length.
  WrapAlignment get alignment => _alignment;
  set alignment(WrapAlignment a) {
    if (a != _alignment) {
      _alignment = a;
      markNeedsLayout();
    }
  }

  WrapAlignment _runAlignment;

  /// Where the runs go across the wrap, in the cells they and the run gaps
  /// leave of its thickness.
  WrapAlignment get runAlignment => _runAlignment;
  set runAlignment(WrapAlignment a) {
    if (a != _runAlignment) {
      _runAlignment = a;
      markNeedsLayout();
    }
  }

  WrapCrossAlignment _crossAxisAlignment;

  /// Where each child goes across its run, when the run is thicker than
  /// the child.
  WrapCrossAlignment get crossAxisAlignment => _crossAxisAlignment;
  set crossAxisAlignment(WrapCrossAlignment a) {
    if (a != _crossAxisAlignment) {
      _crossAxisAlignment = a;
      markNeedsLayout();
    }
  }

  int _gap;

  /// The cells between one child of a run and the next, 0 or more.
  int get gap => _gap;
  set gap(int g) {
    assert(g >= 0, 'a gap of 0 cells or more');
    if (g != _gap) {
      _gap = g;
      markNeedsLayout();
    }
  }

  int _runGap;

  /// The cells between one run and the next, 0 or more.
  int get runGap => _runGap;
  set runGap(int g) {
    assert(g >= 0, 'a gap of 0 cells or more');
    if (g != _runGap) {
      _runGap = g;
      markNeedsLayout();
    }
  }

  // the runs of the last layout, three numbers each: its length along the
  // main axis, its thickness and its children; kept, so that a layout like
  // the last allocates nothing
  var _runs = Int32List(24);
  var _runCount = 0;

  // the cells the runs and the gaps between them took across the main axis
  var _thickness = 0;

  // the overflow was reported (debug)
  var _overflowReported = false;

  /// The direction and the settings that aren't the defaults; once laid
  /// out, the cells its runs and gaps need beyond it across the main axis,
  /// if any, with the [DiagnosticsFlag.overflow] flag.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..addTag(_direction.name)
      ..add('alignment', _alignment, defaultValue: WrapAlignment.start)
      ..add('runAlignment', _runAlignment, defaultValue: WrapAlignment.start)
      ..add(
        'crossAxisAlignment',
        _crossAxisAlignment,
        defaultValue: WrapCrossAlignment.start,
      )
      ..add('gap', _gap, defaultValue: 0)
      ..add('runGap', _runGap, defaultValue: 0);
    if (_constraints == null) {
      return;
    }
    final horizontal = _direction == Axis.horizontal;
    final over = _thickness - (horizontal ? height : width);
    if (over > 0) {
      final unit = horizontal ? 'row' : 'column';
      properties
        ..addMessage('overflow', '$over $unit${over == 1 ? '' : 's'}')
        ..flag(DiagnosticsFlag.overflow);
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! WrapParentData) {
      child.parentData = WrapParentData();
    }
  }

  /// Ends the run [_runCount] with [length], [thickness] and [children].
  void _addRun(int length, int thickness, int children) {
    var runs = _runs;
    final at = 3 * _runCount;
    if (at == runs.length) {
      runs = _runs = Int32List(2 * at)..setRange(0, at, runs);
    }
    runs[at] = length;
    runs[at + 1] = thickness;
    runs[at + 2] = children;
    _runCount++;
  }

  @override
  void performLayout(BoxConstraints c) {
    final horizontal = _direction == Axis.horizontal;
    final maxMain = horizontal ? c.maxW : c.maxH;
    final maxCross = horizontal ? c.maxH : c.maxW;
    _runCount = 0;
    var longest = 0;
    var thickness = 0;
    // the run being filled
    var length = 0;
    var thick = 0;
    var n = 0;
    for (var child = _firstChild; child != null;) {
      if (horizontal) {
        _layoutChild(child, 0, maxMain, 0, maxCross);
      } else {
        _layoutChild(child, 0, maxCross, 0, maxMain);
      }
      final long = horizontal ? child.width : child.height;
      final t = horizontal ? child.height : child.width;
      if (n > 0 && length + _gap + long > maxMain) {
        _addRun(length, thick, n);
        longest = length > longest ? length : longest;
        thickness += thick + _runGap;
        length = 0;
        thick = 0;
        n = 0;
      }
      length += (n > 0 ? _gap : 0) + long;
      thick = t > thick ? t : thick;
      n++;
      child = (child.parentData as WrapParentData).nextSibling;
    }
    if (n > 0) {
      _addRun(length, thick, n);
      longest = length > longest ? length : longest;
      thickness += thick;
    }
    _thickness = thickness;
    final main = horizontal ? c.constrainW(longest) : c.constrainH(longest);
    final cross = horizontal
        ? c.constrainH(thickness)
        : c.constrainW(thickness);
    width = horizontal ? main : cross;
    height = horizontal ? cross : main;
    assert(_debugReportOverflow(thickness - cross), 'reports the overflow');
    _place(main, cross);
  }

  /// Places the children in their runs, in a wrap [main] cells long and
  /// [cross] thick.
  void _place(int main, int cross) {
    final horizontal = _direction == Axis.horizontal;
    final runs = _runs;
    final count = _runCount;
    final freeCross = cross - _thickness < 0 ? 0 : cross - _thickness;
    var across = _before(_runAlignment, freeCross, count);
    var child = _firstChild;
    for (var r = 0; r < count; r++) {
      final length = runs[3 * r];
      final thick = runs[3 * r + 1];
      final n = runs[3 * r + 2];
      final free = main - length < 0 ? 0 : main - length;
      var along = _before(_alignment, free, n);
      for (var i = 0; i < n; i++) {
        final c = child!;
        final data = c.parentData as WrapParentData;
        final t = horizontal ? c.height : c.width;
        final at =
            across +
            switch (_crossAxisAlignment) {
              WrapCrossAlignment.start => 0,
              WrapCrossAlignment.end => thick - t,
              WrapCrossAlignment.center => (thick - t) ~/ 2,
            };
        data
          ..dx = horizontal ? along : at
          ..dy = horizontal ? at : along;
        along +=
            (horizontal ? c.width : c.height) +
            _gap +
            _after(_alignment, free, n, i);
        child = data.nextSibling;
      }
      across += thick + _runGap + _after(_runAlignment, freeCross, count, r);
    }
  }

  /// The cells [alignment] puts before the first of [n] children or runs,
  /// [free] cells free.
  static int _before(WrapAlignment alignment, int free, int n) =>
      switch (alignment) {
        WrapAlignment.start || WrapAlignment.spaceBetween => 0,
        WrapAlignment.end => free,
        WrapAlignment.center => free ~/ 2,
        WrapAlignment.spaceAround => _part(free, 2 * n, 0),
        WrapAlignment.spaceEvenly => _part(free, n + 1, 0),
      };

  /// The cells [alignment] puts after child or run [i] of [n], [free]
  /// cells free, besides the gap.
  static int _after(WrapAlignment alignment, int free, int n, int i) =>
      switch (alignment) {
        WrapAlignment.spaceBetween => n > 1 ? _part(free, n - 1, i) : 0,
        WrapAlignment.spaceAround =>
          _part(free, 2 * n, 2 * i + 1) + _part(free, 2 * n, 2 * i + 2),
        WrapAlignment.spaceEvenly => _part(free, n + 1, i + 1),
        _ => 0,
      };

  /// Logs a warning the first time runs overflow the wrap, with the cells
  /// they need beyond it.
  bool _debugReportOverflow(int over) {
    if (over > 0 && !_overflowReported) {
      _overflowReported = true;
      final horizontal = _direction == Axis.horizontal;
      final unit = '${horizontal ? 'row' : 'column'}${over == 1 ? '' : 's'}';
      final side = horizontal ? 'bottom' : 'right';
      _warn('A RenderWrap overflowed by $over $unit on the $side.');
    }
    return true;
  }

  // what the children ask for, worked out as the layout makes the runs

  @override
  int computeMinIntrinsicWidth(int height) => _direction == Axis.horizontal
      ? _longest(_minWidth, height)
      : _acrossRuns(_minWidth, _maxHeight, height);

  @override
  int computeMaxIntrinsicWidth(int height) => _direction == Axis.horizontal
      ? _inOneRun(_maxWidth, height)
      : _acrossRuns(_maxWidth, _maxHeight, height);

  @override
  int computeMinIntrinsicHeight(int width) => _direction == Axis.horizontal
      ? _acrossRuns(_minHeight, _maxWidth, width)
      : _longest(_minHeight, width);

  @override
  int computeMaxIntrinsicHeight(int width) => _direction == Axis.horizontal
      ? _acrossRuns(_maxHeight, _maxWidth, width)
      : _inOneRun(_maxHeight, width);

  /// The intrinsic size of [kind] along the main axis, [cross] across it,
  /// with each child in a run of its own: the most a child asks for.
  int _longest(int kind, int cross) {
    var most = 0;
    for (var child = _firstChild; child != null;) {
      final a = child._intrinsic(kind, cross);
      most = a > most ? a : most;
      child = (child.parentData as WrapParentData).nextSibling;
    }
    return most;
  }

  /// The intrinsic size of [kind] along the main axis, [cross] across it,
  /// with all the children in one run: what they ask for and the gaps.
  int _inOneRun(int kind, int cross) {
    var sum = _childCount > 1 ? _gap * (_childCount - 1) : 0;
    for (var child = _firstChild; child != null;) {
      sum += child._intrinsic(kind, cross);
      child = (child.parentData as WrapParentData).nextSibling;
    }
    return sum;
  }

  /// The intrinsic size of [kind] across the main axis, [main] long: the
  /// runs the children make, each as long as it asks to be ([mainKind]) up
  /// to [main], each run as thick as the most a child of it asks for at
  /// its length, and the gaps between them.
  int _acrossRuns(int kind, int mainKind, int main) {
    var sum = 0;
    var runs = 0;
    var length = 0;
    var thick = 0;
    var n = 0;
    for (var child = _firstChild; child != null;) {
      var long = child._intrinsic(mainKind, BoxConstraints.unbounded);
      if (long > main) {
        long = main;
      }
      if (n > 0 && length + _gap + long > main) {
        sum += thick;
        runs++;
        length = 0;
        thick = 0;
        n = 0;
      }
      length += (n > 0 ? _gap : 0) + long;
      final t = child._intrinsic(kind, long);
      thick = t > thick ? t : thick;
      n++;
      child = (child.parentData as WrapParentData).nextSibling;
    }
    if (n > 0) {
      sum += thick;
      runs++;
    }
    return sum + (runs > 1 ? _runGap * (runs - 1) : 0);
  }

  @override
  void paint(PaintContext ctx) {
    for (var child = _firstChild; child != null;) {
      paintChild(ctx, child);
      child = (child.parentData as WrapParentData).nextSibling;
    }
  }
}
