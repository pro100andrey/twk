// Cells painted by hand: what the shell draws that no twk widget draws
// as the design has it (the stage's dots, the segmented choice, the list's
// gliding bar), through a small painter over twk's Canvas.
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show fitText;

/// [a] [k] of the way to [b], each channel rounded, as the design's `mix`
/// and twk's tokens blend: [b] at 1 and above, [a] at 0 and below; [b]
/// where either is not RGB. What the pages mix with; the shell and the
/// [Painter] mix with [Color.lerp], the same between RGB colors.
Color mix(Color a, Color b, double k) {
  if (k <= 0) {
    return a;
  }
  if (k >= 1 || !a.isRgb || !b.isRgb) {
    return b;
  }
  int channel(int x, int y) => (x + (y - x) * k).round();
  return Color.rgb(channel(a.r, b.r), channel(a.g, b.g), channel(a.b, b.b));
}

/// The columns [text] takes.
int widthOf(String text) => stringWidth(text);

/// What [cut] measures with, as [stringWidth] and [widthOf] do: the East
/// Asian ambiguous one column wide.
final _segmenter = TextSegmenter();

/// [text] cut to [width] columns, no cluster split: whole where it fits,
/// else its start and "…" as the core's [fitText] cuts it, the blanks
/// before the "…" left out ([start] false), or "…" and its end ([start]
/// true).
String cut(String text, int width, {bool start = false}) {
  if (!start) {
    final fit = fitText(_segmenter, text, width);
    return identical(fit, text) || !fit.endsWith('…')
        ? fit
        : '${fit.substring(0, fit.length - 1).trimRight()}…';
  }
  if (_segmenter.width(text) <= width) {
    return text;
  }
  if (width <= 0) {
    return '';
  }
  // the clusters' starts, then those that fit after the "…" from the end
  final starts = <int>[];
  final scan = ClusterScan();
  for (var i = 0; i < text.length; i = scan.end) {
    starts.add(i);
    _segmenter.scan(text, i, scan);
  }
  final room = width - _segmenter.width('…');
  var from = text.length;
  var used = 0;
  for (final at in starts.reversed) {
    final w = _segmenter.width(text.substring(at, from));
    if (used + w > room) {
      break;
    }
    used += w;
    from = at;
  }
  return '…${text.substring(from)}';
}

/// Draws into a rectangle of a [Canvas] in its own coordinates, clipped to
/// it.
final class Painter {
  Painter(this.canvas, this.width, this.height);

  final Canvas canvas;
  final int width;
  final int height;

  StyleTable get _styles => canvas.styles;

  /// Writes [text] at [x], [y] in [style], at most [max] columns of it;
  /// returns the columns it takes.
  int text(int x, int y, String text, Style style, {int? max}) {
    if (text.isEmpty) {
      return 0;
    }
    final shown = max == null ? text : cut(text, max);
    final w = stringWidth(shown);
    if (y < 0 || y >= height || x >= width || x + w <= 0) {
      return w;
    }
    canvas.text(x, y, shown, style.penIn(_styles));
    return w;
  }

  /// Fills [w] × [h] cells at [x], [y] with [glyph] in [style].
  void fill(int x, int y, int w, int h, Style style, [String glyph = ' ']) {
    if (w <= 0 || h <= 0) {
      return;
    }
    canvas.fill(x, y, w, h, style.penIn(_styles), glyph.runes.first);
  }

  /// Sets the background of [w] × [h] cells at [x], [y] to [color], their
  /// glyphs and text colors kept.
  void bg(int x, int y, int w, int h, Color color) => _each(
    x,
    y,
    w,
    h,
    (styles, s) => styles.style(
      fg: styles.fgOf(s),
      bg: color,
      attrs: styles.attrsOf(s),
      underlineColor: styles.underlineColorOf(s),
    ),
  );

  /// Sets the text color of [w] × [h] cells at [x], [y] to [color] and
  /// their attributes to [attrs], glyphs and backgrounds kept.
  void color(int x, int y, int w, int h, Color color, [int? attrs]) => _each(
    x,
    y,
    w,
    h,
    (styles, s) => styles.style(
      fg: color,
      bg: styles.bgOf(s),
      attrs: attrs ?? styles.attrsOf(s),
      underlineColor: styles.underlineColorOf(s),
    ),
  );

  /// Takes the colors of [w] × [h] cells at [x], [y] [k] of the way to
  /// [color], text and background alike: a barrier's shade, a fade.
  void tint(int x, int y, int w, int h, Color color, double k) {
    if (k <= 0) {
      return;
    }
    _each(
      x,
      y,
      w,
      h,
      (styles, s) => styles.style(
        fg: Color.lerp(_rgb(styles, styles.fgOf(s), fg: true), color, k),
        bg: Color.lerp(_rgb(styles, styles.bgOf(s), fg: false), color, k),
        attrs: styles.attrsOf(s),
        underlineColor: styles.underlineColorOf(s),
      ),
    );
  }

  /// [c] as RGB where the table knows it ([StyleTable.rgbOf]).
  static Color _rgb(StyleTable styles, Color c, {required bool fg}) {
    final v = styles.rgbOf(c, text: fg);
    return v == null ? c : Color.rgb(v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF);
  }

  /// The design's scrollbar thumb in [color] on column [x], twk's
  /// [paintThumb] in whole cells of a half block (`▐`): for a window of
  /// [view] rows from row [top] on [content] rows, scrolled [scroll] of
  /// the most it scrolls, as long as the window is of the content, a row
  /// at least; nothing where all of the content is in view.
  void thumb(int x, int top, int view, int content, num scroll, Color color) {
    if (content <= view || view <= 0) {
      return;
    }
    final size = (view * view / content).round().clamp(1, view);
    final at = top + (scroll / (content - view) * (view - size)).round();
    paintThumb(
      canvas,
      Style(fg: color),
      start: at,
      end: at + size,
      steps: 1,
      vertical: true,
      at: x,
      glyph: 0x2590,
    );
  }

  /// A line of [glyph] across, [w] long.
  void hline(int x, int y, int w, Color color, String glyph) =>
      fill(x, y, w, 1, Style(fg: color), glyph);

  /// A line of [glyph] down, [h] long.
  void vline(int x, int y, int h, Color color, String glyph) =>
      fill(x, y, 1, h, Style(fg: color), glyph);

  /// Gives each style of [w] × [h] cells at [x], [y] to [restyle].
  void _each(
    int x,
    int y,
    int w,
    int h,
    int Function(StyleTable styles, int style) restyle,
  ) {
    if (w <= 0 || h <= 0) {
      return;
    }
    canvas
      ..save()
      ..clipRect(x, y, w, h);
    final (x0, y0, x1, y1) = canvas.clipBounds;
    final surface = canvas.surface;
    final styles = canvas.styles;
    final sty = surface.styles;
    final stride = surface.width;
    final made = <int, int>{};
    for (var row = y0; row < y1; row++) {
      for (var i = row * stride + x0; i < row * stride + x1; i++) {
        final s = sty[i];
        sty[i] = made[s] ??= restyle(styles, s);
      }
      if (x1 > x0) {
        surface.markDirty(row, x0, x1);
      }
    }
    canvas.restore();
  }
}

/// Paints cells by hand: what [onPaint] draws with a [Painter]
/// of its size. As big as the constraints allow (`width` and `height`
/// where given); a terminal cursor where [cursor] says, the hidden one
/// resting where [rest] does.
final class CellPaint extends LeafRenderObjectWidget {
  const CellPaint(
    this.onPaint, {
    super.key,
    this.width,
    this.height,
    this.cursor,
    this.rest,
    this.hit = true,
  });

  final void Function(Painter p) onPaint;
  final int? width;
  final int? height;

  /// Where the terminal's cursor shows, a bar; none when null.
  final (int, int)? cursor;

  /// Where the hidden cursor rests while it has the focus ([restCursor]):
  /// the cell of what is selected in it; its first cell when null.
  final (int, int)? rest;

  /// Whether the mouse hits it, so that what is under it is not.
  final bool hit;

  @override
  RenderCellPaint createRenderObject(BuildContext context) =>
      RenderCellPaint(onPaint, width, height, cursor)
        ..rest = rest
        ..hit = hit;

  @override
  void updateRenderObject(BuildContext context, RenderCellPaint renderObject) {
    renderObject
      ..onPaint = onPaint
      ..cursor = cursor
      ..rest = rest
      ..hit = hit
      ..setSize(width, height);
  }
}

/// What a [CellPaint] lays out and paints.
final class RenderCellPaint extends RenderObject {
  RenderCellPaint(this._onPaint, this._width, this._height, this._cursor);

  void Function(Painter p) _onPaint;
  void Function(Painter p) get onPaint => _onPaint;
  set onPaint(void Function(Painter p) f) {
    _onPaint = f;
    markNeedsPaint();
  }

  int? _width;
  int? _height;
  void setSize(int? w, int? h) {
    if (w != _width || h != _height) {
      _width = w;
      _height = h;
      markNeedsLayout();
    }
  }

  (int, int)? _cursor;
  (int, int)? get cursor => _cursor;
  set cursor((int, int)? c) {
    if (c != _cursor) {
      _cursor = c;
      markNeedsPaint();
    }
  }

  (int, int)? _rest;
  (int, int)? get rest => _rest;
  set rest((int, int)? c) {
    if (c != _rest) {
      _rest = c;
      markNeedsPaint();
    }
  }

  PaintContext? _painted;

  /// Whether the mouse hits it.
  var hit = true;

  @override
  bool hitTestSelf(int x, int y) => hit;

  @override
  void performLayout(BoxConstraints c) {
    final w = _width;
    final h = _height;
    width = w != null
        ? c.constrainW(w)
        : (c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW);
    height = h != null
        ? c.constrainH(h)
        : (c.maxH < BoxConstraints.unbounded ? c.maxH : c.minH);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas
      ..save()
      ..clipRect(0, 0, width, height);
    _onPaint(Painter(canvas, width, height));
    canvas.restore();
    if (_rest case (final x, final y)) {
      restCursor(ctx, this, x, y);
    }
    final at = _cursor;
    if (at != null) {
      showCaret(ctx, this, at.$1, at.$2);
      _painted = ctx;
    } else if (_painted != null) {
      hideCaret(ctx, this);
      _painted = null;
    }
  }

  @override
  void detach() {
    final ctx = _painted;
    if (ctx != null) {
      hideCaret(ctx, this);
      _painted = null;
    }
    super.detach();
  }
}
