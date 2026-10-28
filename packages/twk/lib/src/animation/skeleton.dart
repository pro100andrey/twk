/// Placeholders while content loads: [Skeleton], blocks where the content
/// will be, [Skeletonize], a subtree drawn as such blocks in the layout it
/// has, and [SkeletonTheme], how they look and how fast their shimmer
/// sweeps.
///
/// @docImport 'progress_bar.dart';
/// @docImport 'spinner.dart';
library;

import 'dart:typed_data';

import 'package:twk_core/twk_core.dart'
    show
        Attr,
        BoxConstraints,
        Color,
        GlyphRun,
        PaintContext,
        RenderObject,
        RenderObjectWithChildMixin,
        StyleTable,
        TextSegmenter,
        kBlank,
        kCont,
        kGlyphMask;

import '../binding/app_binding.dart';
import '../focus/exclude_focus.dart';
import '../framework/framework.dart';
import '../gestures/ignore_pointer.dart';
import '../layout/one_child.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import 'effect.dart';
import 'steps.dart';

/// How the [Skeleton]s and [Skeletonize]s below it look: the [glyph] their
/// cells show, in [style], and the shimmer that sweeps over them, a band
/// [band] cells wide in [highlight] crossing them from left to right each
/// [period]. Optional: without one they look as its defaults say.
///
/// Skeletons in a blue that sweep slower, in a band of four cells:
///
/// ```dart
/// SkeletonTheme(
///   style: const Style(fg: Color.rgb(0x40, 0x60, 0x90)),
///   period: const Duration(seconds: 3),
///   band: 4,
///   child: Skeleton.text(lines: 3),
/// )
/// ```
final class SkeletonTheme extends InheritedWidget {
  /// The look of the skeletons in [child]; each field left out is its
  /// default. Asserts that [band] is one cell at least.
  const SkeletonTheme({
    required super.child,
    super.key,
    this.period = defaultPeriod,
    this.glyph = defaultGlyph,
    this.style,
    this.highlight,
    this.band = defaultBand,
  }) : assert(band >= 1, 'a band of no cells');

  /// How long the shimmer takes to cross a skeleton by default: 1.5 s.
  static const defaultPeriod = Duration(milliseconds: 1500);

  /// What a skeleton's cells show by default: `░`, a light shade.
  static const defaultGlyph = '░';

  /// How wide the shimmer's band is by default: 8 cells.
  static const defaultBand = 8;

  /// How long the shimmer takes to cross a skeleton from its left edge to
  /// its right, then from the left again: a whole number of
  /// [Skeletonize.step]s, one at least.
  final Duration period;

  /// What each cell of a skeleton shows: one code point, one column wide.
  /// Where the canvas draws it two columns wide (`░` where the terminal
  /// draws East Asian ambiguous glyphs wide) or it is not one code point,
  /// a blank in reverse video stands for it.
  final String glyph;

  /// The glyph's color and attributes, over the theme's
  /// [ThemeData.muted]; null for that alone. Without a background, the
  /// cells keep the one the content had.
  final Style? style;

  /// The color ([Style.fg]) the shimmer brightens the glyph to at its
  /// middle; null for the theme's [ThemeData.text].
  final Style? highlight;

  /// How wide the shimmer's band is, in cells: brightest in its middle,
  /// fading to [style] at its edges.
  final int band;

  /// The nearest skeleton theme above [context], null for none. [context]
  /// depends on it.
  static SkeletonTheme? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SkeletonTheme>();

  @override
  bool updateShouldNotify(SkeletonTheme oldWidget) =>
      period != oldWidget.period ||
      glyph != oldWidget.glyph ||
      style != oldWidget.style ||
      highlight != oldWidget.highlight ||
      band != oldWidget.band;
}

/// Shows [child] as a skeleton while [enabled]: laid out as it is, so the
/// layout is the real one, each cell of it that shows something becoming
/// the [SkeletonTheme]'s glyph in its muted color, the blanks left as they
/// are. Give the child placeholder data of about the size of what will
/// come: a name, a line of text.
///
/// While enabled, the mouse passes the child by ([IgnorePointer]), its
/// focus nodes take no focus ([ExcludeFocus]), and a screen reader reads
/// it as `loading`, not what it holds. Turned off, the child shows as it
/// paints, its state kept.
///
/// With [shimmer], as by default, a band of brighter cells sweeps over it
/// from left to right each [SkeletonTheme.period], stepped by [step] on
/// the app's clock: every skeleton on the screen moves in the same frames,
/// on one timer. There is no shimmer on plain output, in the
/// screen-reader mode, or where the theme's colors (the glyph's and the
/// highlight's) are not RGB, as in [ThemeData.terminal]: the glyph alone.
/// The app asks for no frame while nothing shimmers. A [Skeleton] or a
/// skeletonize inside an enabled one is drawn by this one.
///
/// A profile that keeps its layout while it loads:
///
/// ```dart
/// final user = ValueNotifier<String?>(null);
/// final profile = ValueListenableBuilder(
///   valueListenable: user,
///   builder: (context, name, child) => Skeletonize(
///     enabled: name == null,
///     child: Text('User: ${name ?? 'Placeholder'}'),
///   ),
/// );
/// ```
///
/// See also:
///
///  * [Skeleton], a block of placeholder cells of its own.
///  * [Spinner] and [ProgressBar], which show that work goes on.
final class Skeletonize extends StatelessWidget {
  /// Shows [child] as a skeleton while [enabled], shimmering with
  /// [shimmer].
  const Skeletonize({
    required this.enabled,
    required this.child,
    super.key,
    this.shimmer = true,
  });

  /// Whether the child shows as a skeleton; false for the child as it
  /// paints.
  final bool enabled;

  /// What is shown, laid out as it is.
  final Widget child;

  /// Whether a band of brighter cells sweeps over the skeleton.
  final bool shimmer;

  /// How long the shimmer stays in a place before it moves on.
  static const step = Duration(milliseconds: 50);

  @override
  Widget build(BuildContext context) => Semantics(
    label: enabled ? 'loading' : null,
    child: ExcludeSemantics(
      excluding: enabled,
      child: ExcludeFocus(
        excluding: enabled,
        child: IgnorePointer(
          ignoring: enabled,
          child: _Skeleton(enabled: enabled, shimmer: shimmer, child: child),
        ),
      ),
    ),
  );
}

/// A block of placeholder cells where content will be: the
/// [SkeletonTheme]'s glyph in its muted color, shimmering as a
/// [Skeletonize] does, and read by a screen reader as `loading`.
///
/// [Skeleton.new] is a block [width] cells wide (null: as wide as it may
/// be) and [height] rows tall; [Skeleton.text] lines of text as wide as
/// they may be, the last shorter.
///
/// A row of a table whose values have not come yet:
///
/// ```dart
/// const Row(
///   gap: 1,
///   children: [
///     Text('User:'),
///     Skeleton(width: 12),
///     Text('Role:'),
///     Skeleton(width: 6),
///   ],
/// )
/// ```
final class Skeleton extends StatelessWidget {
  /// A block [width] cells wide, as wide as it may be when null, and
  /// [height] rows tall; its glyph in [style] over the theme's. Asserts
  /// that the width is not negative and the height a row at least.
  const Skeleton({super.key, this.width, this.height = 1, this.style})
    : lines = null,
      lastLine = 1,
      assert(width == null || width >= 0, 'a negative width'),
      assert(height >= 1, 'a block of no rows');

  /// [lines] rows as wide as they may be, the last of them, where there is
  /// more than one, [lastLine] of that width (a cell at least); its glyph
  /// in [style] over the theme's. Asserts that there is a line at least
  /// and that [lastLine] is from 0 to 1.
  const Skeleton.text({
    super.key,
    int this.lines = 1,
    this.lastLine = 0.6,
    this.style,
  }) : width = null,
       height = lines,
       assert(lines >= 1, 'text of no lines'),
       assert(lastLine >= 0 && lastLine <= 1, 'lastLine out of 0..1');

  /// How wide the block is, in cells; null for as wide as the constraints
  /// let it be (as narrow as they let it be where they are unbounded).
  final int? width;

  /// How many rows the block is tall.
  final int height;

  /// How many lines of text it stands for; null for a block.
  final int? lines;

  /// How much of the width the last line of text takes, where there is
  /// more than one: from 0 to 1.
  final double lastLine;

  /// The glyph's color and attributes, over the [SkeletonTheme]'s style;
  /// null for that alone.
  final Style? style;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'loading',
    child: _Skeleton(
      enabled: true,
      shimmer: true,
      style: style,
      child: _Blocks(
        width: width,
        height: height,
        lastLine: (lines ?? 1) > 1 ? lastLine : 1,
      ),
    ),
  );
}

// ------------------------------------------------------------- the effect --

/// Tells what is below it that a skeleton above it draws it.
final class _Skeletonized extends InheritedWidget {
  const _Skeletonized({required this.enabled, required super.child});

  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Skeletonized>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(_Skeletonized oldWidget) =>
      enabled != oldWidget.enabled;
}

/// What [Skeletonize] and [Skeleton] build: [child] through the effect of
/// a skeleton while [enabled] and no skeleton above draws it, shimmering
/// with [shimmer] where it can.
final class _Skeleton extends StatefulWidget {
  const _Skeleton({
    required this.enabled,
    required this.shimmer,
    required this.child,
    this.style,
  });

  final bool enabled;
  final bool shimmer;
  final Style? style;
  final Widget child;

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

final class _SkeletonState extends State<_Skeleton> {
  AppBinding? _binding;
  Steps? _steps;
  _Painter? _painter;

  // the shimmer moves: set by each build, read by the paint hook
  var _shimmering = false;

  static final _detached = TextSegmenter();

  @override
  void dispose() {
    _steps?.stop();
    super.dispose();
  }

  void _stepped() => setState(() {});

  /// Starts the shimmer again where it was stopped while the app was read
  /// out ([AppBinding.screenReader]): the app is painted again after it.
  void _painted() {
    final binding = _binding;
    if (_shimmering && binding != null && !binding.screenReader) {
      _steps?.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final above = _Skeletonized.of(context);
    final enabled = widget.enabled && !above;
    final binding = _binding = AppBinding.maybeOf(context);
    final app = binding?.twkApp;
    final skeletons = SkeletonTheme.maybeOf(context);
    final theme = Theme.of(context);
    var style = theme.muted;
    for (final over in [skeletons?.style, widget.style]) {
      if (over != null) {
        style = style.merge(over);
      }
    }
    final glyph = _glyphOf(
      skeletons?.glyph ?? SkeletonTheme.defaultGlyph,
      app?.owner.segmenter ?? _detached,
    );
    final highlight = (skeletons?.highlight ?? theme.text).fg;
    final fg = style.fg;
    final rgb = fg != null && fg.isRgb && highlight != null && highlight.isRgb;
    final look = _Look(
      glyph: glyph ?? kBlank,
      fg: fg ?? Color.defaultColor,
      bg: style.bg,
      attrs: glyph == null ? style.attrs | Attr.reverse : style.attrs,
      highlight: rgb ? highlight : null,
      band: skeletons?.band ?? SkeletonTheme.defaultBand,
    );
    final painter = _painter = _painter?.look == look
        ? _painter!
        : _Painter(look);
    final shimmering = _shimmering =
        enabled &&
        widget.shimmer &&
        rgb &&
        binding != null &&
        !(app?.terminal.info.plain ?? false);
    final steps = _steps ??= Steps(
      Skeletonize.step,
      _stepped,
      binding: binding,
    );
    if (shimmering && !binding!.screenReader) {
      steps.start();
    } else {
      // also where a step came in the screen-reader mode, after it asked
      // for the next one
      steps.stop();
    }
    CellEffect? effect;
    if (enabled) {
      final period = skeletons?.period ?? SkeletonTheme.defaultPeriod;
      final count = period.inMicroseconds ~/ Skeletonize.step.inMicroseconds;
      final n = count > 1 ? count : 1;
      effect = _SkeletonEffect(
        painter,
        shimmering ? (steps.current % n) / n : null,
      );
    }
    return _Skeletonized(
      enabled: enabled || above,
      child: _PaintHook(
        onPaint: _painted,
        child: Effect(effect: effect, child: widget.child),
      ),
    );
  }

  /// [glyph] as the code point a cell shows, where it is one that the
  /// canvas [segmenter] measures draws one column wide; null otherwise.
  static int? _glyphOf(String glyph, TextSegmenter segmenter) {
    final runes = glyph.runes;
    if (runes.length != 1 || segmenter.width(glyph) != 1) {
      return null;
    }
    final cp = runes.single;
    return cp == kBlank ? null : cp;
  }
}

/// How a skeleton's cells look: [glyph] in [fg] with [attrs], on [bg] or
/// the background the content had; the shimmer brightening [fg] to
/// [highlight] (null for no shimmer) over [band] cells.
final class _Look {
  const _Look({
    required this.glyph,
    required this.fg,
    required this.bg,
    required this.attrs,
    required this.highlight,
    required this.band,
  });

  final int glyph;
  final Color fg;
  final Color? bg;
  final int attrs;
  final Color? highlight;
  final int band;

  @override
  bool operator ==(Object other) =>
      other is _Look &&
      other.glyph == glyph &&
      other.fg == fg &&
      other.bg == bg &&
      other.attrs == attrs &&
      other.highlight == highlight &&
      other.band == band;

  @override
  int get hashCode => Object.hash(glyph, fg, bg, attrs, highlight, band);
}

/// How bright the shimmer gets, in steps from the glyph's color to the
/// highlight.
const _levels = 4;

/// Paints the cells of a skeleton as [look] has them: the styles it made,
/// kept by the style of the content and how bright they are, for as long
/// as the cells are of one table.
final class _Painter {
  _Painter(this.look);

  final _Look look;

  StyleTable? _table;
  final _styles = <int, int>{};

  /// What a cell shows with the shimmer's middle at [middle] columns from
  /// the left edge, none when null.
  void paint(EffectCell cell, double? middle) {
    final c = cell.childGlyph;
    if ((c & kCont) == 0) {
      final g = c & kGlyphMask;
      if (g == kBlank || g == 0) {
        return;
      }
    }
    if (c == cell.underGlyph && cell.childStyle == cell.underStyle) {
      // not the child's: what was under it shows through
      return;
    }
    var level = 0;
    if (middle != null) {
      final half = look.band / 2;
      final k = 1 - (cell.x + 0.5 - middle).abs() / half;
      level = k <= 0 ? 0 : (k * _levels).round();
    }
    final styles = cell.styles;
    if (!identical(styles, _table)) {
      _table = styles;
      _styles.clear();
    }
    cell
      ..glyph = look.glyph
      ..style = _styles[cell.childStyle * (_levels + 1) + level] ??= styles
          .style(
            fg: level == 0
                ? look.fg
                : Color.lerp(look.fg, look.highlight!, level / _levels),
            bg: look.bg ?? styles.bgOf(cell.childStyle),
            attrs: look.attrs,
          );
  }
}

/// The effect of a skeleton: its cells as [painter] paints them, the
/// shimmer [phase] of the way across (null for none). An effect of no
/// duration, so an [Effect] given the next phase shows it at once.
final class _SkeletonEffect extends CellEffect {
  const _SkeletonEffect(this.painter, this.phase);

  final _Painter painter;
  final double? phase;

  @override
  Duration get duration => Duration.zero;

  @override
  CellFilter at(Duration elapsed) {
    final phase = this.phase;
    final band = painter.look.band;
    return (cell) => painter.paint(
      cell,
      // from wholly off the left edge to wholly off the right one
      phase == null ? null : phase * (cell.width + band) - band / 2,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _SkeletonEffect &&
      identical(other.painter, painter) &&
      other.phase == phase;

  @override
  int get hashCode => Object.hash(painter, phase);
}

// ------------------------------------------------------------ the hooks --

/// Shows [child], calling [onPaint] as it paints.
final class _PaintHook extends SingleChildRenderObjectWidget {
  const _PaintHook({required this.onPaint, super.child});

  final void Function() onPaint;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintHook(onPaint);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderPaintHook).onPaint = onPaint;
}

/// What a [_PaintHook] lays out and paints: its child, as big as it is.
final class _RenderPaintHook extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderPaintHook(this.onPaint);

  void Function() onPaint;

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    child.layout(c, parentUsesSize: true);
    width = child.width;
    height = child.height;
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void paint(PaintContext ctx) {
    onPaint();
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }
}

// ------------------------------------------------------------- the blocks --

/// The cells of a [Skeleton]: a mark in each, which the effect around it
/// always shows as the skeleton's glyph; [width] wide (null: as wide as it
/// may be), [height] rows, the last of them [lastLine] of the width where
/// there are more.
final class _Blocks extends LeafRenderObjectWidget {
  const _Blocks({
    required this.width,
    required this.height,
    required this.lastLine,
  });

  final int? width;
  final int height;
  final double lastLine;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBlocks(width, height, lastLine);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderBlocks)
      ..blockWidth = width
      ..rows = height
      ..lastLine = lastLine;
  }
}

/// What [_Blocks] lays out and paints.
final class _RenderBlocks extends RenderObject {
  _RenderBlocks(this._blockWidth, this._rows, this._lastLine);

  int? _blockWidth;
  int? get blockWidth => _blockWidth;
  set blockWidth(int? w) {
    if (w != _blockWidth) {
      _blockWidth = w;
      markNeedsLayout();
    }
  }

  int _rows;
  int get rows => _rows;
  set rows(int r) {
    if (r != _rows) {
      _rows = r;
      markNeedsLayout();
    }
  }

  double _lastLine;
  double get lastLine => _lastLine;
  set lastLine(double l) {
    if (l != _lastLine) {
      _lastLine = l;
      markNeedsPaint();
    }
  }

  // the mark the effect around it shows as the glyph
  static final _mark = GlyphRun(Uint32List(1)..[0] = 0x23, 1);

  @override
  int computeMinIntrinsicWidth(int height) => _blockWidth ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) => _blockWidth ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) => _rows;

  @override
  int computeMaxIntrinsicHeight(int width) => _rows;

  @override
  void performLayout(BoxConstraints c) {
    final w = _blockWidth;
    width = w != null
        ? c.constrainW(w)
        : (c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW);
    height = c.constrainH(_rows);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final pen = const Style().penIn(canvas.styles);
    for (var y = 0; y < height; y++) {
      var w = width;
      if (y == _rows - 1 && _lastLine < 1) {
        final short = (width * _lastLine).round();
        w = short < 1 ? (width < 1 ? width : 1) : short;
      }
      for (var x = 0; x < w; x++) {
        canvas.run(x, y, _mark, pen);
      }
    }
  }
}
