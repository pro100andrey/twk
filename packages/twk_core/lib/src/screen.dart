/// [Screen], one terminal screen: its style and glyph tables, the
/// [Surface] painted into, the [Canvas] that paints it, and the [Presenter]
/// that turns what changed into bytes.
///
/// @docImport 'app.dart';
/// @docImport 'headless.dart';
library;

import 'dart:typed_data';

import 'package:meta/meta.dart' show visibleForTesting;

import 'canvas.dart';
import 'presenter.dart';
import 'style.dart';
import 'surface.dart';
import 'unicode/unicode.dart';

/// One terminal screen: a [Surface] of cells, painted through [canvas],
/// whose changes [render] turns into the bytes to write to the terminal.
///
/// It puts together what a frame needs and keeps them in step: [styles]
/// and [glyphs] intern what the cells hold, [surface] is the frame being
/// painted, and [presenter] keeps what the terminal shows and writes the
/// difference. [TwkApp] owns one for its terminal; a screen alone paints
/// and renders without a render tree or a terminal.
///
/// A screen 20 cells wide and 2 tall with a line of text, rendered:
///
/// ```dart
/// final screen = Screen(20, 2);
/// final pen = screen.styles.pen(const Pen(fg: Color.green));
/// screen.canvas.text(0, 0, 'Ready', pen);
/// final bytes = screen.render(); // what to write to the terminal
/// ```
///
/// See also:
///
///  * [renderToString], a render tree drawn as text.
///  * [HeadlessTerminal], a terminal in memory a [TwkApp] runs on.
final class Screen {
  /// A screen [width] cells wide and [height] rows tall, blank.
  ///
  /// [caps] is what the terminal supports, all off by default; [textMode]
  /// and [ambiguousWidth] are how the terminal measures text (graphemes,
  /// ambiguous characters one cell wide by default); [colorMode] the colors
  /// it shows, true color by default. [inline] makes the screen a region
  /// of the normal screen under the terminal's history, [viewport] a fixed
  /// rectangle of the screen (see [Presenter.inline], [Presenter.viewport]);
  /// with neither, the default, it is the whole (alternate) screen.
  /// [atLineStart] is whether the cursor is at the start of a line when an
  /// inline region starts: its first row is that line; false, the line
  /// after it.
  Screen(
    int width,
    int height, {
    TerminalCaps caps = const TerminalCaps(),
    TextMode textMode = TextMode.graphemes,
    int ambiguousWidth = 1,
    ColorMode colorMode = ColorMode.trueColor,
    bool inline = false,
    Viewport? viewport,
    bool atLineStart = true,
  }) : styles = StyleTable(
         colorMode: colorMode,
         styledUnderlines: caps.styledUnderlines,
       ),
       glyphs = GlyphTable(),
       surface = Surface(width, height) {
    canvas = Canvas(
      surface,
      styles,
      glyphs,
      segmenter: TextSegmenter(mode: textMode, ambiguousWidth: ambiguousWidth),
    );
    presenter = Presenter(
      width,
      height,
      styles,
      glyphs,
      caps: caps,
      inline: inline,
      viewport: viewport,
      atLineStart: atLineStart,
    );
  }

  /// The styles the screen's cells are painted in, interned; [StyleTable.pen]
  /// makes a style of a [Pen].
  final StyleTable styles;

  /// The graphemes of more than one code point the screen's cells hold,
  /// interned.
  final GlyphTable glyphs;

  /// The cells of the frame being painted, which [render] compares with
  /// what the terminal shows.
  final Surface surface;

  /// The canvas that paints [surface].
  late final Canvas canvas;

  /// What writes [surface]'s changes as bytes, and keeps what the terminal
  /// shows.
  late final Presenter presenter;

  /// How many cells wide the screen is.
  int get width => surface.width;

  /// How many rows tall the screen is.
  int get height => surface.height;

  /// Makes the screen [width] x [height] cells after the terminal was
  /// resized; the surface is cleared, to be painted again whole.
  ///
  /// The presenter forgets what the terminal shows, since the terminal may
  /// have cut or reflowed it, and the next [render] rewrites every
  /// cell; this holds even when the size returns to the last rendered one
  /// before the next frame. In the inline mode [height] is the region's,
  /// and the region is repainted even when its size is the same (see
  /// [Presenter.inline]); in a fixed viewport the size is the part of the
  /// viewport the screen has, and it is repainted likewise (see
  /// [Presenter.viewport]).
  void resize(int width, int height) {
    if (width == surface.width &&
        height == surface.height &&
        !presenter.inline &&
        presenter.viewport == null) {
      return;
    }
    surface.resize(width, height);
    presenter.resize(width, height);
    canvas.reset();
  }

  /// Inline mode: the region becomes [height] rows tall. The surface is
  /// cleared (repaint everything), but the next [render] writes only what
  /// changed on the terminal, after making room for the rows the region
  /// gains or erasing those it loses.
  void resizeRegion(int height) {
    assert(presenter.inline, 'only an inline region changes height alone');
    surface.resize(surface.width, height);
    canvas.reset();
  }

  /// Inline mode: rows [from, to) of [rows] go to the terminal's history,
  /// above the region, with the next [render], and are never written
  /// again (see [Presenter.commit]).
  void commit(Surface rows, [int from = 0, int? to]) =>
      presenter.commit(rows, from, to);

  /// The bytes that hand the screen back when the app ends (a view valid
  /// until the next call), or null for none: in the inline mode the region
  /// stays and the cursor goes below it, or with [clear] the region is
  /// erased; a fixed viewport stays, or is erased, and the cursor goes
  /// back where the app found it (see [Presenter.leave]).
  Uint8List? leave({bool clear = false}) {
    final n = presenter.leave(clear: clear);
    return _handed(n == 0 ? null : presenter.out.view);
  }

  /// Encodes everything painted since the last call. Returns the bytes to
  /// write to the terminal (a view valid until the next call), or null when
  /// nothing changed. Then sweeps the styles if they are due
  /// ([sweepIfDue]).
  Uint8List? render() {
    final n = presenter.present(surface);
    final out = n == 0 ? null : presenter.out.view;
    sweepIfDue();
    return _handed(out);
  }

  // with asserts, the bytes [render] or [leave] handed out last, a copy
  Uint8List? _lastHanded;

  /// [bytes] as [render] and [leave] hand them out: with asserts, a copy,
  /// and the copy handed out before filled with `?`, so that bytes kept
  /// past the next call, which the presenter writes over, show as such
  /// rather than as the next frame's.
  Uint8List? _handed(Uint8List? bytes) {
    var out = bytes;
    assert(() {
      _lastHanded?.fillRange(0, _lastHanded!.length, 0x3F);
      out = _lastHanded = bytes == null ? null : Uint8List.fromList(bytes);
      return true;
    }(), 'bytes handed out as a copy');
    return out;
  }

  /// The fewest styles, or glyphs, in use the [styles], or the [glyphs],
  /// are swept past; a test's may be fewer.
  @visibleForTesting
  static var sweepFloor = 4096;

  // each swept once this many are in use
  var _stylesAt = 0;
  var _glyphsAt = 0;

  // surfaces other than the screen's whose styles are kept
  final _kept = <Surface>[];

  /// Keeps the styles and glyphs of [other]'s cells in a sweep, as those
  /// of the screen's surface: a surface painted with [styles] and
  /// [glyphs] that is kept from one frame to the next (an inline app's
  /// history, written a frame at a time).
  void keepStylesOf(Surface other) => _kept.add(other);

  /// Sweeps [styles] ([StyleTable.sweep]) when twice as many are in use as
  /// after their last sweep, and at least [sweepFloor], and [glyphs]
  /// ([GlyphTable.sweep]) the same: what no cell of the surface (of a
  /// surface kept, [keepStylesOf], of what keeps cells of either,
  /// [Surface.keep]) and nothing the presenter knows the terminal shows
  /// has is freed. As what is in use doubles between two sweeps, a style or
  /// a glyph costs its sweep once, and an app of a few hundred is never
  /// swept. [render] calls it.
  void sweepIfDue() {
    final stylesDue = styles.live > sweepFloor && styles.live > _stylesAt;
    final glyphsDue = glyphs.live > sweepFloor && glyphs.live > _glyphsAt;
    if (!stylesDue && !glyphsDue) {
      return;
    }
    void none(int _) {}
    void roots(void Function(int) glyph, void Function(int) style) {
      surface.markCells(glyph, style);
      for (final s in _kept) {
        s.markCells(glyph, style);
      }
      presenter.markCells(glyph, style);
    }

    if (stylesDue) {
      styles.sweep((mark) => roots(none, mark));
      _stylesAt = 2 * styles.live;
    }
    if (glyphsDue) {
      glyphs.sweep((mark) => roots(mark, none));
      _glyphsAt = 2 * glyphs.live;
    }
  }
}
