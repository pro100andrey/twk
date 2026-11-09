part of 'render.dart';

// ------------------------------------------------------------- overflow --

/// What a record of the log says when a [RenderFlex], a [RenderWrap] or a
/// [RenderGrid] overflowed: the record's `error`, so that a sink tells it
/// from the other warnings of the tree (`testTwk`'s `failOnOverflow` does).
final class OverflowReport {
  /// An overflow of [right] columns beyond the right edge and [bottom] rows
  /// beyond the bottom, either 0 for none.
  const OverflowReport(this.right, this.bottom);

  /// The columns the content needs beyond the right edge.
  final int right;

  /// The rows the content needs beyond the bottom edge.
  final int bottom;

  @override
  String toString() => 'overflow: ${_overflowSides(right, bottom)}';
}

String _overflowCells(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';

String _overflowSides(int right, int bottom) => [
  if (right > 0) '${_overflowCells(right, 'column')} on the right',
  if (bottom > 0) '${_overflowCells(bottom, 'row')} on the bottom',
].join(' and ');

/// The pen of the marker of an overflow: yellow on black.
const _overflowPen = Pen(fg: Color.yellow, bg: Color.black);

/// What a box that clips its children shows when they need more room than
/// it has, in debug mode: the report, once, when the overflow starts, and
/// the marker along the edge the children are cut off at.
///
/// The marker is a hatch, `▚` in yellow on black (`/` where the terminal
/// draws that wider than a cell), down the right edge and along the bottom
/// edge that is cut, with the number of cells cut off, `+3`, in the corner;
/// a box of no cell shows none. It is painted while
/// [PipelineOwner.debugOverflowIndicator] is on, which it is while asserts
/// are. A box that clips on purpose says so with [overflowIntended], and
/// shows neither the marker nor the report.
mixin _OverflowIndicator on RenderObject {
  // the cells cut off at the right and at the bottom, as the last layout
  // found them (debug only: they stay 0 with asserts off)
  var _overflowRight = 0;
  var _overflowBottom = 0;

  // the overflow in progress was reported
  var _overflowReported = false;

  var _overflowIntended = false;

  /// Whether the box clips its children on purpose: a strip that shows
  /// the start of what is longer than it, say. It then shows no marker
  /// and logs no warning when they overflow it. False by default.
  bool get overflowIntended => _overflowIntended;
  set overflowIntended(bool value) {
    if (_overflowIntended == value) {
      return;
    }
    _overflowIntended = value;
    _overflowReported = false;
    // the report comes from layout, the marker from paint
    markNeedsLayout();
    markNeedsPaint();
  }

  /// Notes, from layout and in an assert, the cells the content needs
  /// beyond the [right] and [bottom] edges (0 or less for none): marks the
  /// paint when they changed, and logs a warning for [name] the first time
  /// they are more than 0, again after they were gone. Returns true.
  bool _debugOverflow(String name, int right, int bottom) {
    final r = right > 0 ? right : 0;
    final b = bottom > 0 ? bottom : 0;
    // layout marks the paint of what it laid out
    _overflowRight = r;
    _overflowBottom = b;
    if (r == 0 && b == 0) {
      _overflowReported = false;
    } else if (!_overflowReported && !_overflowIntended) {
      _overflowReported = true;
      _warn(
        'A $name overflowed by ${_overflowSides(r, b)}.',
        error: OverflowReport(r, b),
      );
    }
    return true;
  }

  /// Whether the marker is over any of the cells [x], [y], [w] × [h] of
  /// this box: what a repaint boundary inside a child repainted on its own
  /// is painted over again then ([RenderObject.paintsOver]).
  bool _overflowOver(int x, int y, int w, int h) {
    final right = _overflowRight;
    final bottom = _overflowBottom;
    if ((right == 0 && bottom == 0) ||
        _overflowIntended ||
        !(owner?.debugOverflowIndicator ?? false)) {
      return false;
    }
    final bw = width;
    final bh = height;
    bool hits(int rx, int ry, int rw, int rh) =>
        x < rx + rw && rx < x + w && y < ry + rh && ry < y + h;
    return (right > 0 &&
            (hits(bw - 1, 0, 1, bh) ||
                hits(bw - '+$right'.length, 0, '+$right'.length, 1))) ||
        (bottom > 0 && hits(0, bh - 1, bw, 1));
  }

  /// Paints the marker over the edges of the box, after its children, when
  /// the content overflowed it and the owner shows markers.
  void paintOverflowIndicator(PaintContext ctx) {
    final right = _overflowRight;
    final bottom = _overflowBottom;
    if ((right == 0 && bottom == 0) || _overflowIntended) {
      return;
    }
    if (!(owner?.debugOverflowIndicator ?? false)) {
      return;
    }
    final w = width;
    final h = height;
    if (w < 1 || h < 1) {
      return;
    }
    final canvas = ctx.canvas;
    final pen = canvas.styles.pen(_overflowPen);
    final hatch = canvas.segmenter.width('▚') == 1 ? '▚' : '/';
    if (right > 0) {
      for (var y = 0; y < h; y++) {
        canvas.text(w - 1, y, hatch, pen);
      }
    }
    if (bottom > 0) {
      for (var x = 0; x < w; x++) {
        canvas.text(x, h - 1, hatch, pen);
      }
    }
    final label = canvas.styles.pen(
      const Pen(fg: Color.black, bg: Color.yellow),
    );
    if (right > 0) {
      final text = '+$right';
      canvas.text(w - text.length, 0, text, label);
    }
    if (bottom > 0) {
      final text = '+$bottom';
      canvas.text(w - text.length, h - 1, text, label);
    }
  }
}
