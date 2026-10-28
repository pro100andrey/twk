/// What the charts draw with: [ChartGlyphs], and the helpers they share.
library;

import 'package:twk_core/twk_core.dart'
    show BorderType, Canvas, ClusterScan, Color, TextSegmenter;

import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../style/style.dart';

/// The glyphs the charts draw bars and lines with, as the canvas they are
/// drawn on draws them: eighth blocks and box drawing where it draws each
/// one column wide, braille and [BorderType.ascii] where it does not (both
/// are East Asian ambiguous). Measured again only when the segmenter's
/// settings change.
final class ChartGlyphs {
  // the segmenter settings measured last; -1 before the first
  var _mode = -1;
  var _ambiguous = 0;
  var _eighths = true;
  final _narrowLines = <BorderType, bool>{};

  /// Measures the glyphs as [segmenter] does.
  void use(TextSegmenter segmenter) {
    if (segmenter.mode.index == _mode &&
        segmenter.ambiguousWidth == _ambiguous) {
      return;
    }
    _mode = segmenter.mode.index;
    _ambiguous = segmenter.ambiguousWidth;
    _segmenter = segmenter;
    _eighths = _oneColumn(const [..._upEighths, ..._acrossEighths], segmenter);
    _narrowLines.clear();
  }

  late TextSegmenter _segmenter;

  /// How many steps a cell of a bar that grows upwards shows: 8 (eighth
  /// blocks) or 4 (braille).
  int get upSteps => _eighths ? 8 : 4;

  /// The glyph of a cell of a bar that grows upwards, [k] of [upSteps]
  /// full from the bottom; a blank for 0.
  int up(int k) => k <= 0
      ? 0x20
      : (_eighths ? _upEighths : _upBraille)[(k > upSteps ? upSteps : k) - 1];

  /// How many steps a cell of a bar that grows to the right shows: 8
  /// (eighth blocks) or 2 (braille).
  int get acrossSteps => _eighths ? 8 : 2;

  /// The glyph of a cell of a bar that grows to the right, [k] of
  /// [acrossSteps] full from the left; a blank for 0.
  int across(int k) => k <= 0
      ? 0x20
      : (_eighths
            ? _acrossEighths
            : _acrossBraille)[(k > acrossSteps ? acrossSteps : k) - 1];

  /// [type], or [BorderType.ascii] where a piece of it is not one column.
  BorderType lines(BorderType type) =>
      _narrowLines.putIfAbsent(
        type,
        () => _oneColumn([
          for (var arms = 1; arms < 16; arms++)
            type.glyph(
              up: arms & 1 != 0,
              right: arms & 2 != 0,
              down: arms & 4 != 0,
              left: arms & 8 != 0,
            ),
        ], _segmenter),
      )
      ? type
      : BorderType.ascii;

  /// Draws a bar that grows to the right on the [w] x [h] cells from
  /// ([x], [y]) of [canvas], as a `Gauge` and a `ProgressBar` do: [ratio]
  /// of its width filled from the left in [pen], to the nearest of
  /// [acrossSteps] in a cell, a ratio beyond 0 and 1 counting as the
  /// nearest; or, given [run] (its first cell and its width, as [sweep]
  /// gives it), that run of full cells. The cells left are not drawn;
  /// [use] the canvas's segmenter first. Answers how many cells from [x]
  /// the ratio fills whole, 0 for a run.
  int blocks(
    Canvas canvas,
    int x,
    int y,
    int w,
    int h,
    double ratio,
    int pen, {
    (int, int)? run,
  }) {
    final steps = acrossSteps;
    final whole = across(steps);
    if (run case (final from, final width)) {
      canvas.fill(x + from, y, width, h, pen, whole);
      return 0;
    }
    final filled = (unitRatio(ratio) * w * steps).round();
    final full = filled ~/ steps;
    canvas.fill(x, y, full, h, pen, whole);
    final part = filled - full * steps;
    if (part > 0) {
      canvas.fill(x + full, y, 1, h, pen, across(part));
    }
    return full;
  }

  /// Where the run of a bar [width] cells wide whose value is not known is
  /// at [step]: its first cell and its width, a quarter of the bar (a cell
  /// at least) going a cell a step from one end to the other and back, the
  /// whole bar where it has no room to move. What [blocks] and [line] draw
  /// as their `run`.
  static (int, int) sweep(int width, int step) {
    final w = width ~/ 4 > 1 ? width ~/ 4 : 1;
    final room = width - w;
    if (room <= 0) {
      return (0, width);
    }
    final p = step % (2 * room);
    return (p <= room ? p : 2 * room - p, w);
  }

  /// Draws a line of [type] [cells] long from ([x], [y]) on [canvas], as a
  /// `LineGauge` does: [ratio] of it from the left in [filledPen], to the
  /// nearest half cell where the type has a line that ends in the middle of
  /// a cell, the rest of the same line in [unfilledPen]; or, given [run]
  /// (its first cell and its width), the line in [unfilledPen] with that
  /// run of it in [filledPen]. [BorderType.ascii] where the type's pieces
  /// are not one column ([lines]); [use] the canvas's segmenter first.
  void line(
    Canvas canvas,
    int x,
    int y,
    int cells,
    BorderType type, {
    required int filledPen,
    required int unfilledPen,
    double ratio = 0,
    (int, int)? run,
  }) {
    if (cells <= 0) {
      return;
    }
    final pieces = lines(type);
    final whole = pieces.glyph(left: true, right: true);
    final half = pieces.glyph(left: true);
    if (run case (final from, final width)) {
      canvas
        ..fill(x, y, cells, 1, unfilledPen, whole)
        ..fill(x + from, y, width, 1, filledPen, whole);
      return;
    }
    // in half cells where the type has a half, else in cells
    final halves = half != whole;
    final r = unitRatio(ratio);
    final filled = (r * cells * (halves ? 2 : 1)).round();
    final full = halves ? filled ~/ 2 : filled;
    canvas.fill(x, y, full, 1, filledPen, whole);
    var rest = full;
    if (halves && filled.isOdd) {
      canvas.fill(x + full, y, 1, 1, filledPen, half);
      rest++;
    }
    canvas.fill(x + rest, y, cells - rest, 1, unfilledPen, whole);
  }
}

// ▁▂▃▄▅▆▇█
const _upEighths = [
  0x2581,
  0x2582,
  0x2583,
  0x2584,
  0x2585,
  0x2586,
  0x2587,
  0x2588,
];

// ▏▎▍▌▋▊▉█
const _acrossEighths = [
  0x258F,
  0x258E,
  0x258D,
  0x258C,
  0x258B,
  0x258A,
  0x2589,
  0x2588,
];

// ⣀⣤⣶⣿
const _upBraille = [0x28C0, 0x28E4, 0x28F6, 0x28FF];

// ⡇⣿
const _acrossBraille = [0x2847, 0x28FF];

final _scan = ClusterScan();

/// Whether each of [codePoints] takes one column of a canvas whose text
/// [segmenter] measures, whatever its neighbours, on every terminal.
bool _oneColumn(List<int> codePoints, TextSegmenter segmenter) {
  for (final cp in codePoints) {
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

/// [value] as a label: whole numbers without decimals, others with at most
/// two.
String formatValue(double value) {
  if (!value.isFinite) {
    return '$value';
  }
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return '${value.toInt()}';
  }
  var s = value.toStringAsFixed(2);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) {
    s = s.substring(0, s.length - 1);
  }
  return s == '-0' ? '0' : s;
}

/// [style] over the terminal's default text color, no background: what a
/// repaint boundary that keeps an underlay paints over what is under it.
Style overUnder(Style style) =>
    const Style(fg: Color.defaultColor).merge(style);

/// [style] over the terminal's default colors: a style whose pen paints
/// both colors of a cell, as a repaint boundary must.
Style opaque(Style style) =>
    const Style(fg: Color.defaultColor, bg: Color.defaultColor).merge(style);

/// [style] over the theme's text at [context], which then depends on it,
/// with no background of the theme's: what a chart or a gauge paints its
/// cells in, over what is under it (`RenderObject.keepsUnderlay`).
Style overText(BuildContext context, Style style) =>
    Theme.of(context).text.merge(style);

/// [style] over the background and the text of the theme at [context]
/// ([ThemeData.background], [ThemeData.text]), which then depends on it:
/// what a canvas whose background is part of its drawing paints in (a
/// `DotCanvas`'s dots on it), so that the colors its style leaves unset
/// are the theme's.
Style overTheme(BuildContext context, Style style) {
  final theme = Theme.of(context);
  return theme.background.merge(theme.text).merge(style);
}
