/// The dots a [DotCanvas] draws, in layers over a grid of cells: [DotGrid].
library;

import 'dart:typed_data';

import 'package:twk_core/twk_core.dart'
    show
        Canvas,
        ClusterScan,
        Color,
        GlyphRun,
        Pen,
        StyleTable,
        TextMode,
        TextSegmenter;

import 'dot_canvas.dart';
import 'marker.dart';

/// Dots in layers over a grid of cells, drawn onto a [Canvas] as one glyph
/// per cell. What a [DotCanvas] draws into; kept from frame to frame, its
/// storage only grows.
///
/// Within a layer the dots set in a cell add up, and the cell takes the
/// color of the last of them. A later layer covers what the earlier ones
/// set in each cell it sets a dot in (with [Marker.halfBlock], in each
/// half: each half has a color of its own).
final class DotGrid {
  var _columns = 0;
  var _rows = 0;
  Marker _marker = Marker.braille;

  // the current layer: the dots set in each cell (a pattern of the
  // marker), the color of the last of them (with two colors, of the upper
  // half) and with two colors the color of the lower half
  var _bits = Uint8List(0);
  var _color = <Color>[];
  var _lower = <Color>[];

  // the layers before it, merged
  var _doneBits = Uint8List(0);
  var _doneColor = <Color>[];
  var _doneLower = <Color>[];

  // the cells [_lo, _hi) hold every dot of the current layer
  var _lo = 0;
  var _hi = 0;

  // the marker [reset] was given last, the segmenter settings it was
  // measured with, and the glyph of each pattern of the marker drawn
  Marker? _asked;
  TextMode _askedMode = TextMode.graphemes;
  var _askedAmbiguous = 0;
  var _glyphs = Int32List(0);

  // the pen of each text color and background, in _penTable
  StyleTable? _penTable;
  final _pens = <int, int>{};
  final _one = GlyphRun(Uint32List(1), 1);

  /// Cells across.
  int get columns => _columns;

  /// Cells down.
  int get rows => _rows;

  /// The marker the dots are drawn with: the one [reset] was given, or
  /// [Marker.braille] in its place when a glyph of that one does not take
  /// exactly one column of the canvas on its own.
  Marker get marker => _marker;

  /// Dots across.
  int get width => _columns * _marker.dotsAcross;

  /// Dots down.
  int get height => _rows * _marker.dotsDown;

  /// Empties the grid and sizes it for [columns] × [rows] cells of
  /// [marker], whose glyphs are measured by [segmenter], that of the canvas
  /// the grid is drawn on.
  void reset(int columns, int rows, Marker marker, TextSegmenter segmenter) {
    assert(columns >= 0 && rows >= 0, 'a grid of 0 cells or more');
    if (marker != _asked ||
        segmenter.mode != _askedMode ||
        segmenter.ambiguousWidth != _askedAmbiguous) {
      _asked = marker;
      _askedMode = segmenter.mode;
      _askedAmbiguous = segmenter.ambiguousWidth;
      _marker = _oneColumn(marker, segmenter) ? marker : Marker.braille;
      _glyphs = Int32List(_marker.patterns);
      for (var p = 0; p < _glyphs.length; p++) {
        _glyphs[p] = _marker.glyphOf(p);
      }
    }
    _columns = columns;
    _rows = rows;
    final n = columns * rows;
    if (n > _bits.length) {
      _bits = Uint8List(n);
      _doneBits = Uint8List(n);
      _color = List.filled(n, Color.defaultColor);
      _lower = List.filled(n, Color.defaultColor);
      _doneColor = List.filled(n, Color.defaultColor);
      _doneLower = List.filled(n, Color.defaultColor);
    } else {
      _bits.fillRange(0, n, 0);
      _doneBits.fillRange(0, n, 0);
    }
    _lo = n;
    _hi = 0;
  }

  /// Sets the dot [x] across and [y] down from the top left in [color], in
  /// the current layer; a dot off the grid is left out.
  void set(int x, int y, Color color) {
    if (x < 0 || y < 0) {
      return;
    }
    final across = _marker.dotsAcross;
    final down = _marker.dotsDown;
    final col = x ~/ across;
    final row = y ~/ down;
    if (col >= _columns || row >= _rows) {
      return;
    }
    final i = row * _columns + col;
    final dy = y - row * down;
    _bits[i] |= 1 << (dy * across + x - col * across);
    if (dy == 1 && _marker.twoColors) {
      _lower[i] = color;
    } else {
      _color[i] = color;
    }
    if (i < _lo) {
      _lo = i;
    }
    if (i >= _hi) {
      _hi = i + 1;
    }
  }

  /// Ends the current layer: the dots set from here on cover those set
  /// before.
  void layer() {
    final two = _marker.twoColors;
    for (var i = _lo; i < _hi; i++) {
      final b = _bits[i];
      if (b == 0) {
        continue;
      }
      if (!two) {
        _doneBits[i] = b;
        _doneColor[i] = _color[i];
      } else {
        if (b & 1 != 0) {
          _doneColor[i] = _color[i];
        }
        if (b & 2 != 0) {
          _doneLower[i] = _lower[i];
        }
        _doneBits[i] |= b;
      }
      _bits[i] = 0;
    }
    _lo = _columns * _rows;
    _hi = 0;
  }

  /// Draws the cells at ([x], [y]) of [canvas]: the glyphs of their dots
  /// over [background], blanks where no dot is set.
  void paint(Canvas canvas, int x, int y, Color background) {
    final styles = canvas.styles;
    if (!identical(styles, _penTable)) {
      _penTable = styles;
      _pens.clear();
    }
    canvas.fill(x, y, _columns, _rows, _pen(Color.defaultColor, background));
    final two = _marker.twoColors;
    final run = _one;
    for (var row = 0; row < _rows; row++) {
      for (var col = 0; col < _columns; col++) {
        final i = row * _columns + col;
        final b = _bits[i];
        final done = _doneBits[i];
        int glyph;
        Color fg;
        var bg = background;
        if (!two) {
          if (b != 0) {
            glyph = _glyphs[b];
            fg = _color[i];
          } else if (done != 0) {
            glyph = _glyphs[done];
            fg = _doneColor[i];
          } else {
            continue;
          }
        } else {
          final upper = b & 1 != 0
              ? _color[i]
              : (done & 1 != 0 ? _doneColor[i] : null);
          final lower = b & 2 != 0
              ? _lower[i]
              : (done & 2 != 0 ? _doneLower[i] : null);
          if (upper == null && lower == null) {
            continue;
          }
          if (upper == null) {
            glyph = _glyphs[2];
            fg = lower!;
          } else if (lower == null || lower == upper) {
            glyph = _glyphs[lower == null ? 1 : 3];
            fg = upper;
          } else {
            glyph = _glyphs[1];
            fg = upper;
            bg = lower;
          }
        }
        run.glyphs[0] = glyph;
        canvas.run(x + col, y + row, run, _pen(fg, bg));
      }
    }
  }

  /// The pen of [fg] text over [bg] in [_penTable].
  int _pen(Color fg, Color bg) =>
      _pens[fg.value * 0x4000000 + bg.value] ??= _penTable!.pen(
        Pen(fg: fg, bg: bg),
      );
}

final _scan = ClusterScan();

/// Whether each glyph of [marker] takes one column of a canvas whose text
/// [segmenter] measures, whatever its neighbours, and does so on every
/// terminal.
bool _oneColumn(Marker marker, TextSegmenter segmenter) {
  var last = -1;
  for (var p = 1; p < marker.patterns; p++) {
    final cp = marker.glyphOf(p);
    if (cp == last) {
      continue;
    }
    last = cp;
    // the glyph twice: two clusters of a column each
    final two = String.fromCharCodes([cp, cp]);
    segmenter.scan(two, 0, _scan);
    if (_scan.end * 2 != two.length ||
        _scan.width != 1 ||
        _scan.joinsNext ||
        _scan.uncertain) {
      return false;
    }
  }
  return true;
}
