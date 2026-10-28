/// Effects over a subtree: [Effect], which shows its child through a
/// [CellEffect] run on the app's clock; the effects it comes with, those
/// that recolor the cells ([CellEffect.grade], [CellEffect.tint],
/// [CellEffect.dim], [CellEffect.desaturate], [CellEffect.scanlines]),
/// those that show a share of them ([CellEffect.sweep],
/// [CellEffect.dissolve], [CellEffect.typewriter]) and
/// [CellEffect.glitch], and how they compose; and what an effect is at a
/// point of its run, a [CellFilter] of [EffectCell]s.
///
/// @docImport '../layout/box.dart';
/// @docImport 'switcher.dart';
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show Alignment, Attr, Color, RenderEffect, RenderObject, StyleTable;

import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../layout/one_child.dart';
import '../style/color_mix.dart';
import 'animation_controller.dart';
import 'curves.dart';
import 'ticker.dart';

/// Shows [child] through [effect], a function over the cells of the
/// child's rectangle: each shows what the child painted there, what was
/// under it, or what the effect makes of them. As big as the child.
///
/// The effect runs from its start to its end in its [CellEffect.duration],
/// on the app's clock, when the Effect is first built, and again from its
/// start whenever it is given an effect that is not equal to the one it
/// had (or a new key); [onEnd] is called when a run ends. The app asks for
/// frames while it runs and for none once it has ended: the effect stays
/// as it is at its end, which for one that brings the child in is the
/// child as it paints. One of no duration is shown as it is at its end
/// from the first frame on.
///
/// The child repaints normally underneath, shown through the effect as it
/// does; a frame of the effect paints neither the child nor what is under
/// it. Without an effect, or where it leaves the cells as they are, the
/// child shows as it paints.
///
/// A panel that sweeps in from the left over half a second when it is
/// first shown:
///
/// ```dart
/// Effect(
///   effect: const CellEffect.sweep(duration: Duration(milliseconds: 500)),
///   child: Box(border: const Border.all(), child: Text('Ready')),
/// )
/// ```
///
/// See also:
///
///  * [Opacity] and [Dissolve], the same over the child of a widget that
///    an app animates itself.
final class Effect extends StatefulWidget {
  /// Shows [child] through [effect], run once from its start.
  const Effect({required this.effect, super.key, this.onEnd, this.child});

  /// What the child is shown through; null for nothing, the child as it
  /// paints.
  final CellEffect? effect;

  /// Called when a run of the effect ends.
  final void Function()? onEnd;

  /// What is shown through the effect; null for none, nothing to show.
  final Widget? child;

  @override
  State<Effect> createState() => _EffectState();
}

final class _EffectState extends State<Effect>
    with TickerProviderStateMixin<Effect> {
  late final _controller = AnimationController(vsync: this)
    ..addListener(_moved)
    ..addStatusListener(_statusChanged);

  // the controller is set going in initState and didUpdateWidget, which
  // build anyway
  var _quiet = false;

  // the filter built last: of that effect, that far into its run
  CellFilter? _filter;
  CellEffect? _filterOf;
  Duration _filterAt = Duration.zero;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(Effect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.effect != oldWidget.effect) {
      _run();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Runs the effect from its start, when it takes any time.
  void _run() {
    final duration = widget.effect?.duration ?? Duration.zero;
    _quiet = true;
    try {
      if (duration > Duration.zero) {
        _controller
          ..duration = duration
          ..forward(from: 0);
      } else {
        _controller.stop();
      }
    } finally {
      _quiet = false;
    }
  }

  void _moved() {
    if (!_quiet) {
      setState(() {});
    }
  }

  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onEnd?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final effect = widget.effect;
    final duration = effect?.duration ?? Duration.zero;
    final at = duration > Duration.zero
        ? duration * _controller.value
        : Duration.zero;
    if (effect != _filterOf || at != _filterAt) {
      _filterOf = effect;
      _filterAt = at;
      _filter = effect?.at(at);
    }
    return _EffectBox(filter: _filter, child: widget.child);
  }
}

/// What an [Effect] builds: its child through [filter].
final class _EffectBox extends SingleChildRenderObjectWidget {
  const _EffectBox({required this.filter, super.child});

  final CellFilter? filter;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEffect(filter);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderEffect).filter = filter;
}

/// What an [Effect] lays out and paints: its child through [filter], the
/// child as it paints while there is none.
final class _RenderEffect extends RenderEffect {
  _RenderEffect(this._filter);

  CellFilter? _filter;
  CellFilter? get filter => _filter;
  set filter(CellFilter? f) {
    if (!identical(f, _filter)) {
      _filter = f;
      markNeedsPaint();
    }
  }

  final _cell = EffectCell._();

  @override
  bool get hasEffect => _filter != null;

  @override
  void beginEffect(StyleTable styles) => _cell
    .._styles = styles
    .._blending = _blendingOf(styles)
    .._width = width
    .._height = height;

  @override
  void effectCell(
    int x,
    int y,
    int glyph,
    int style,
    int underGlyph,
    int underStyle,
  ) {
    final cell = _cell
      .._x = x
      .._y = y
      .._childGlyph = glyph
      .._childStyle = style
      .._underGlyph = underGlyph
      .._underStyle = underStyle
      ..glyph = glyph
      ..style = style;
    _filter!(cell);
    effectGlyph = cell.glyph;
    effectStyle = cell.style;
  }
}

/// What a [CellEffect] does at a point of its run ([CellEffect.at]):
/// called for each cell of the child that shows, it sets what the cell
/// shows.
typedef CellFilter = void Function(EffectCell cell);

/// A cell of the child of an [Effect], as a [CellFilter] sees it: where it
/// is in the child's rectangle of [width] × [height], what the child
/// painted there and what was under it, as glyphs (a code point is its own
/// glyph, one column wide when it is; others are the ids of clusters, with
/// flags) in [styles]; and what it shows, [glyph] and [style], the child's
/// until a filter sets them. One cell is passed from cell to cell: a filter
/// keeps none.
///
/// A filter that shows the cells of the left half of the child as what is
/// under them:
///
/// ```dart
/// void leftHalfUnder(EffectCell cell) {
///   if (cell.x < cell.width ~/ 2) {
///     cell.showUnder();
///   }
/// }
/// ```
final class EffectCell {
  EffectCell._();

  var _x = 0;
  var _y = 0;
  var _width = 0;
  var _height = 0;
  late StyleTable _styles;
  // how many times the colors [styles] blends with have changed
  var _blending = 0;
  var _childGlyph = 0;
  var _childStyle = 0;
  var _underGlyph = 0;
  var _underStyle = 0;

  /// Its column in the child's rectangle, from 0 at the left.
  int get x => _x;

  /// Its row in the child's rectangle, from 0 at the top.
  int get y => _y;

  /// The width of the child's rectangle.
  int get width => _width;

  /// The height of the child's rectangle.
  int get height => _height;

  /// The table [style], [childStyle] and [underStyle] are styles of, which
  /// reads their colors and makes new ones.
  StyleTable get styles => _styles;

  /// The glyph the child painted in it.
  int get childGlyph => _childGlyph;

  /// The style the child painted it in, of [styles].
  int get childStyle => _childStyle;

  /// The glyph that was under it before the child painted.
  int get underGlyph => _underGlyph;

  /// The style of what was under it, of [styles].
  int get underStyle => _underStyle;

  /// The glyph it shows.
  var glyph = 0;

  /// The style it shows, of [styles].
  var style = 0;

  /// Shows what was under it.
  void showUnder() {
    glyph = _underGlyph;
    style = _underStyle;
  }
}

/// An effect over the cells of the child of an [Effect]: what it does to
/// them at each point of its run, from its start to its end in [duration]
/// ([at]). An equal effect is the same one: an [Effect] given an effect
/// equal to the one it has does not run it again.
///
/// Those it comes with recolor cells, which they do from none of their
/// amount at the start to all of it at the end, or show a share of
/// them, more as they go, each run along a [Curve]; one of no duration is
/// as it is at its end. They compose: one after another
/// ([CellEffect.sequence]), at once ([CellEffect.parallel]), backwards
/// ([reversed]) and after a while ([delayed]). An app's own extends it.
///
/// Each that it comes with takes a [duration], zero by default, and a
/// curve to run along, [Curves.linear] by default.
///
/// A title that types itself out, then flickers for a moment:
///
/// ```dart
/// Effect(
///   effect: const CellEffect.sequence([
///     CellEffect.typewriter(duration: Duration(milliseconds: 800)),
///     CellEffect.glitch(amount: 0.1, duration: Duration(milliseconds: 300)),
///   ]),
///   child: Text('SYSTEM ONLINE'),
/// )
/// ```
///
/// An effect of one's own, which shows the child's cells from the top
/// row down, a row more each step of the run:
///
/// ```dart
/// final class RowsDown extends CellEffect {
///   const RowsDown(this.duration);
///
///   @override
///   final Duration duration;
///
///   @override
///   CellFilter? at(Duration elapsed) {
///     if (elapsed >= duration) {
///       return null;
///     }
///     final t = elapsed.inMicroseconds / duration.inMicroseconds;
///     return (cell) {
///       if (cell.y >= (t * cell.height).floor()) {
///         cell.showUnder();
///       }
///     };
///   }
/// }
/// ```
@immutable
abstract class CellEffect {
  /// An effect; a subclass's constructor can be const.
  const CellEffect();

  /// Maps the colors of the cells, text and background, by [map], which
  /// takes and gives RGB colors: at [amount] of the way from each color to
  /// what [map] makes of it. Text in the terminal's default color, which
  /// it has not told ([StyleTable.defaultForegroundRgb]), keeps it.
  /// [amount] is 1 by default.
  const factory CellEffect.grade(
    Color Function(Color rgb) map, {
    double amount,
    Duration duration,
    Curve curve,
  }) = _Grade;

  /// Tints the colors of the cells with [color], [amount] (half, by
  /// default) of the way to it.
  const factory CellEffect.tint(
    Color color, {
    double amount,
    Duration duration,
    Curve curve,
  }) = _Tint;

  /// Darkens the colors of the cells [amount] (half, by default) of the
  /// way to black; text in the terminal's default color, which it has not
  /// told, is made faint from half the way on.
  const factory CellEffect.dim({
    double amount,
    Duration duration,
    Curve curve,
  }) = _Dim;

  /// Takes the colors of the cells [amount] (all, by default) of the way
  /// to the gray of their lightness.
  const factory CellEffect.desaturate({
    double amount,
    Duration duration,
    Curve curve,
  }) = _Desaturate;

  /// Darkens the colors of every other row, the second, the fourth and on,
  /// [amount] (0.3 by default) of the way to black.
  const factory CellEffect.scanlines({
    double amount,
    Duration duration,
    Curve curve,
  }) = _Scanlines;

  /// Shows the child from the side or corner [from] points to across to
  /// the other (from the center, all at once), what is under it beyond the
  /// front of the sweep, and the child's colors coming in from the
  /// background under it over the [edge] cells behind the front (rows
  /// counted twice, as a cell is about twice as tall as it is wide).
  /// [from] is [Alignment.centerLeft] by default, [edge] 4 cells (1 at
  /// least).
  const factory CellEffect.sweep({
    Alignment from,
    int edge,
    Duration duration,
    Curve curve,
  }) = _Sweep;

  /// Shows a share of the cells of the child, the rest of them as what is
  /// under it: a scattered few more of them each frame.
  const factory CellEffect.dissolve({Duration duration, Curve curve}) =
      _Dissolve;

  /// Shows the cells of the child one after another, row by row from the
  /// left, what is under it after them; the one next to come in reversed
  /// as a cursor when [cursor], as by default.
  const factory CellEffect.typewriter({
    bool cursor,
    Duration duration,
    Curve curve,
  }) = _Typewriter;

  /// Replaces a scattered [amount] of the cells (0.2 by default) with a
  /// symbol, some reversed, others each 40 ms, ever fewer until none at the
  /// end; [seed] (0 by default) scatters them another way.
  const factory CellEffect.glitch({
    double amount,
    int seed,
    Duration duration,
    Curve curve,
  }) = _Glitch;

  /// [effects] one after another, each from where the one before it ends:
  /// one is shown from its start on, as it is at its end once it has
  /// ended, after those before it; until it starts, not at all.
  const factory CellEffect.sequence(List<CellEffect> effects) = _Sequence;

  /// [effects] at once, from the same start, each shown after those before
  /// it, as it is at its end once it has ended.
  const factory CellEffect.parallel(List<CellEffect> effects) = _Parallel;

  /// How long a run takes: zero for one that does not change.
  Duration get duration;

  /// What it does [elapsed] into its run, from zero to [duration]; null
  /// where it leaves the cells as they are. An [Effect] asks once a frame
  /// while it runs.
  CellFilter? at(Duration elapsed);

  /// This effect backwards: at each point of its run as this one is
  /// that long before its end. A dissolve reversed takes the child out.
  CellEffect get reversed => _Reversed(this);

  /// This effect after [delay], as it is at its start until then.
  CellEffect delayed(Duration delay) => _Delayed(this, delay);
}

/// [elapsed] as a share of [duration], from 0 to 1: 1 for no duration.
double _share(Duration elapsed, Duration duration) {
  final d = duration.inMicroseconds;
  if (d <= 0) {
    return 1;
  }
  final share = elapsed.inMicroseconds / d;
  return share <= 0 ? 0 : (share >= 1 ? 1 : share);
}

/// [t] clamped to 0..1.
double _unit(double t) => t <= 0 ? 0 : (t >= 1 ? 1 : t);

/// An effect this library comes with: run along [curve] in [duration],
/// [filterAt] each point of its run; equal to another of its type with
/// equal [_props].
abstract base class _Run extends CellEffect {
  const _Run({this.duration = Duration.zero, this.curve = Curves.linear});

  @override
  final Duration duration;

  final Curve curve;

  /// What tells it apart from another of its type, besides its run.
  List<Object?> get _props;

  @override
  CellFilter? at(Duration elapsed) =>
      filterAt(curve.transform(_share(elapsed, duration)), elapsed);

  /// What it does [t] of the way along its curve, [elapsed] into its run.
  CellFilter? filterAt(double t, Duration elapsed);

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType ||
        other is! _Run ||
        other.duration != duration ||
        other.curve != curve) {
      return false;
    }
    final a = _props;
    final b = other._props;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, duration, curve, Object.hashAll(_props));
}

// ---------------------------------------------------------------- colors --

/// The RGB of [color] as the core blends it: its own, that of a palette
/// entry, or the default background's or text color's
/// ([StyleTable.defaultBackgroundRgb], [StyleTable.defaultForegroundRgb]);
/// null for the default text color while the terminal has not told it.
int? _rgbOf(StyleTable styles, Color color, {required bool text}) =>
    text && color.isDefault
    ? styles.defaultForegroundRgb
    : rgbOf(styles, color, styles.defaultBackgroundRgb);

/// The styles a filter made, by what it made them of: kept while the
/// cells are of one table and the colors it blends with stay as they were
/// (a palette entry or default color the terminal told after the filter
/// was made, OSC 4, 10 or 11, makes them again).
final class _StyleCache {
  StyleTable? _table;
  var _blending = 0;
  final _styles = <int, int>{};

  /// The styles made for cells such as [cell].
  Map<int, int> of(EffectCell cell) {
    if (!identical(cell._styles, _table) || cell._blending != _blending) {
      _table = cell._styles;
      _blending = cell._blending;
      _styles.clear();
    }
    return _styles;
  }
}

/// How many times the colors [styles] blends with, its palette and its
/// default colors, have changed since an effect first painted with it.
int _blendingOf(StyleTable styles) {
  final known = _blendings[styles] ??= _Blending(styles);
  if (!known.matches(styles)) {
    known
      ..take(styles)
      ..changes += 1;
  }
  return known.changes;
}

final _blendings = Expando<_Blending>();

/// The colors a table blends with, as an effect last saw them.
final class _Blending {
  _Blending(StyleTable styles) {
    take(styles);
  }

  // the 256 palette entries, then the default background and text colors
  // (-1 for text while the terminal has not told it)
  final _rgbs = Int32List(258);
  var changes = 0;

  bool matches(StyleTable styles) {
    if (_rgbs[256] != styles.defaultBackgroundRgb ||
        _rgbs[257] != (styles.defaultForegroundRgb ?? -1)) {
      return false;
    }
    for (var i = 0; i < 256; i++) {
      if (_rgbs[i] != styles.paletteRgb(i)) {
        return false;
      }
    }
    return true;
  }

  void take(StyleTable styles) {
    for (var i = 0; i < 256; i++) {
      _rgbs[i] = styles.paletteRgb(i);
    }
    _rgbs[256] = styles.defaultBackgroundRgb;
    _rgbs[257] = styles.defaultForegroundRgb ?? -1;
  }
}

/// The style [s] of [styles] with text [fg], background [bg] and
/// attributes [attrs], all else kept.
int _restyle(StyleTable styles, int s, Color fg, Color bg, int attrs) =>
    styles.style(
      fg: fg,
      bg: bg,
      attrs: attrs,
      underlineColor: styles.underlineColorOf(s),
      link: styles.linkOf(s),
    );

/// An effect that takes the colors of the cells it covers ([_covers])
/// [amount] of the way to those [_target] maps them to.
abstract base class _Recolor extends _Run {
  const _Recolor({required this.amount, super.duration, super.curve});

  final double amount;

  /// Where [rgb] goes, as an RGB.
  int _target(StyleTable styles, int rgb);

  /// Whether it recolors [cell].
  bool _covers(EffectCell cell) => true;

  /// Whether text of an unknown color is made faint from half the way on.
  bool get _faint => false;

  @override
  List<Object?> get _props => [amount];

  @override
  CellFilter? filterAt(double t, Duration elapsed) {
    final k = _unit(amount * t);
    return k <= 0 ? null : _RecolorFilter(this, k).call;
  }
}

/// A [_Recolor] [k] of the way, the styles it made kept by the styles
/// they were made of.
final class _RecolorFilter {
  _RecolorFilter(this.effect, this.k);

  final _Recolor effect;
  final double k;

  final _styles = _StyleCache();

  void call(EffectCell cell) {
    if (!effect._covers(cell)) {
      return;
    }
    final styles = cell.styles;
    cell.style = _styles.of(cell)[cell.style] ??= _recolor(styles, cell.style);
  }

  int _recolor(StyleTable styles, int s) {
    var fg = styles.fgOf(s);
    var attrs = styles.attrsOf(s);
    final text = _rgbOf(styles, fg, text: true);
    if (text != null) {
      fg = lerpRgb(text, effect._target(styles, text), k);
    } else if (effect._faint && k >= 0.5) {
      attrs |= Attr.dim;
    }
    final under = _rgbOf(styles, styles.bgOf(s), text: false)!;
    final bg = lerpRgb(under, effect._target(styles, under), k);
    return _restyle(styles, s, fg, bg, attrs);
  }
}

final class _Grade extends _Recolor {
  const _Grade(
    this.map, {
    super.amount = 1,
    super.duration,
    super.curve,
  });

  final Color Function(Color rgb) map;

  @override
  List<Object?> get _props => [amount, map];

  @override
  int _target(StyleTable styles, int rgb) =>
      _rgbOf(styles, map(rgbColor(rgb)), text: false)!;
}

final class _Tint extends _Recolor {
  const _Tint(
    this.color, {
    super.amount = 0.5,
    super.duration,
    super.curve,
  });

  final Color color;

  @override
  List<Object?> get _props => [amount, color];

  @override
  int _target(StyleTable styles, int rgb) =>
      _rgbOf(styles, color, text: false)!;
}

final class _Dim extends _Recolor {
  const _Dim({super.amount = 0.5, super.duration, super.curve});

  @override
  bool get _faint => true;

  @override
  int _target(StyleTable styles, int rgb) => 0;
}

final class _Desaturate extends _Recolor {
  const _Desaturate({super.amount = 1, super.duration, super.curve});

  @override
  int _target(StyleTable styles, int rgb) {
    final gray =
        (0.299 * (rgb >> 16 & 0xFF) +
                0.587 * (rgb >> 8 & 0xFF) +
                0.114 * (rgb & 0xFF))
            .round();
    return gray << 16 | gray << 8 | gray;
  }
}

final class _Scanlines extends _Recolor {
  const _Scanlines({super.amount = 0.3, super.duration, super.curve});

  @override
  bool _covers(EffectCell cell) => cell.y.isOdd;

  @override
  int _target(StyleTable styles, int rgb) => 0;
}

// ---------------------------------------------------------------- shares --

/// A scattered number from 0 to 0xFFFF for the cell at [x], [y] and
/// [salt].
int _scatter(int x, int y, int salt) {
  var h = (x * 0x45D9F3B + y * 0x119DE1F3 + salt * 0x27D4EB2D) & 0xFFFFFFFF;
  h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF;
  h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF;
  return (h ^ (h >> 16)) & 0xFFFF;
}

final class _Sweep extends _Run {
  const _Sweep({
    this.from = Alignment.centerLeft,
    this.edge = 4,
    super.duration,
    super.curve,
  });

  final Alignment from;
  final int edge;

  @override
  List<Object?> get _props => [from, edge];

  @override
  CellFilter? filterAt(double t, Duration elapsed) =>
      t >= 1 ? null : _SweepFilter(this, _unit(t)).call;
}

/// A [_Sweep] [t] of the way across, the styles it faded kept by the
/// styles they were made of and how far they were faded.
final class _SweepFilter {
  _SweepFilter(this.effect, this.t);

  final _Sweep effect;
  final double t;

  final _styles = _StyleCache();

  void call(EffectCell cell) {
    final from = effect.from;
    final ax = from.x.abs();
    final ay = 2 * from.y.abs();
    final w = cell.width - 1;
    final h = cell.height - 1;
    // how far the cell is from the side it comes in from, and how far the
    // farthest is
    final p =
        ax * (from.x > 0 ? w - cell.x : cell.x) +
        ay * (from.y > 0 ? h - cell.y : cell.y);
    final span = ax * w + ay * h + 1;
    final edge = effect.edge < 1 ? 1 : effect.edge;
    final k = (t * (span + edge) - p) / edge;
    if (k >= 1) {
      return;
    }
    if (k <= 0) {
      cell.showUnder();
      return;
    }
    final styles = cell.styles;
    final faded = (k * 255).round();
    cell.style =
        _styles.of(cell)[cell.style << 40 | cell.underStyle << 8 | faded] ??=
            _fade(styles, cell.style, cell.underStyle, faded / 255);
  }

  /// [s] coming in from the background of [under], [k] of the way.
  static int _fade(StyleTable styles, int s, int under, double k) {
    final bg = _rgbOf(styles, styles.bgOf(under), text: false)!;
    var fg = styles.fgOf(s);
    var attrs = styles.attrsOf(s);
    final text = _rgbOf(styles, fg, text: true);
    if (text != null) {
      fg = lerpRgb(bg, text, k);
    } else if (k < 0.5) {
      attrs |= Attr.dim;
    }
    final own = _rgbOf(styles, styles.bgOf(s), text: false)!;
    return _restyle(styles, s, fg, lerpRgb(bg, own, k), attrs);
  }
}

final class _Dissolve extends _Run {
  const _Dissolve({super.duration, super.curve});

  @override
  List<Object?> get _props => const [];

  @override
  CellFilter? filterAt(double t, Duration elapsed) {
    if (t >= 1) {
      return null;
    }
    final shown = (_unit(t) * 0x10000).round();
    return (cell) {
      if (_scatter(cell.x, cell.y, 0) >= shown) {
        cell.showUnder();
      }
    };
  }
}

final class _Typewriter extends _Run {
  const _Typewriter({this.cursor = true, super.duration, super.curve});

  final bool cursor;

  @override
  List<Object?> get _props => [cursor];

  @override
  CellFilter? filterAt(double t, Duration elapsed) {
    if (t >= 1) {
      return null;
    }
    final share = _unit(t);
    return (cell) {
      final front = (share * cell.width * cell.height).floor();
      final i = cell.y * cell.width + cell.x;
      if (i < front) {
        return;
      }
      if (i == front && cursor) {
        final styles = cell.styles;
        final s = cell.style;
        cell.style = _restyle(
          styles,
          s,
          styles.fgOf(s),
          styles.bgOf(s),
          styles.attrsOf(s) ^ Attr.reverse,
        );
        return;
      }
      cell.showUnder();
    };
  }
}

/// What a glitched cell shows: one-column symbols.
const _symbols = r'!#$%&*+/<=>?@\^_|~';

final class _Glitch extends _Run {
  const _Glitch({
    this.amount = 0.2,
    this.seed = 0,
    super.duration,
    super.curve,
  });

  final double amount;
  final int seed;

  @override
  List<Object?> get _props => [amount, seed];

  @override
  CellFilter? filterAt(double t, Duration elapsed) {
    final share = amount * (1 - _unit(t));
    if (share <= 0) {
      return null;
    }
    final glitched = (_unit(share) * 0x10000).round();
    final salt = seed * 0x10000 + elapsed.inMilliseconds ~/ 40;
    return (cell) {
      if (_scatter(cell.x, cell.y, salt) >= glitched) {
        return;
      }
      final pick = _scatter(cell.y, cell.x, salt + 1);
      cell.glyph = _symbols.codeUnitAt(pick % _symbols.length);
      if (pick.isOdd) {
        final styles = cell.styles;
        final s = cell.style;
        cell.style = _restyle(
          styles,
          s,
          styles.fgOf(s),
          styles.bgOf(s),
          styles.attrsOf(s) ^ Attr.reverse,
        );
      }
    };
  }
}

// ----------------------------------------------------------- composition --

/// The filters of [filters] that are there, one after another; null for
/// none.
CellFilter? _all(List<CellFilter?> filters) {
  final there = [...filters.nonNulls];
  return switch (there.length) {
    0 => null,
    1 => there.single,
    _ => (cell) {
      for (final filter in there) {
        filter(cell);
      }
    },
  };
}

final class _Sequence extends CellEffect {
  const _Sequence(this.effects);

  final List<CellEffect> effects;

  @override
  Duration get duration =>
      effects.fold(Duration.zero, (sum, effect) => sum + effect.duration);

  @override
  CellFilter? at(Duration elapsed) {
    final filters = <CellFilter?>[];
    var start = Duration.zero;
    for (final effect in effects) {
      if (elapsed < start) {
        break;
      }
      final d = effect.duration;
      final into = elapsed - start;
      filters.add(effect.at(into < d ? into : d));
      start += d;
    }
    return _all(filters);
  }

  @override
  bool operator ==(Object other) =>
      other is _Sequence && sameList(other.effects, effects);

  @override
  int get hashCode => Object.hash(_Sequence, Object.hashAll(effects));
}

final class _Parallel extends CellEffect {
  const _Parallel(this.effects);

  final List<CellEffect> effects;

  @override
  Duration get duration => effects.fold(
    Duration.zero,
    (longest, effect) => effect.duration > longest ? effect.duration : longest,
  );

  @override
  CellFilter? at(Duration elapsed) => _all([
    for (final effect in effects)
      effect.at(elapsed < effect.duration ? elapsed : effect.duration),
  ]);

  @override
  bool operator ==(Object other) =>
      other is _Parallel && sameList(other.effects, effects);

  @override
  int get hashCode => Object.hash(_Parallel, Object.hashAll(effects));
}

final class _Reversed extends CellEffect {
  const _Reversed(this.effect);

  final CellEffect effect;

  @override
  Duration get duration => effect.duration;

  @override
  CellFilter? at(Duration elapsed) {
    final left = effect.duration - elapsed;
    return effect.at(left > Duration.zero ? left : Duration.zero);
  }

  @override
  CellEffect get reversed => effect;

  @override
  bool operator ==(Object other) =>
      other is _Reversed && other.effect == effect;

  @override
  int get hashCode => Object.hash(_Reversed, effect);
}

final class _Delayed extends CellEffect {
  const _Delayed(this.effect, this.delay);

  final CellEffect effect;
  final Duration delay;

  @override
  Duration get duration => delay + effect.duration;

  @override
  CellFilter? at(Duration elapsed) {
    final into = elapsed - delay;
    return effect.at(into > Duration.zero ? into : Duration.zero);
  }

  @override
  bool operator ==(Object other) =>
      other is _Delayed && other.effect == effect && other.delay == delay;

  @override
  int get hashCode => Object.hash(_Delayed, effect, delay);
}
