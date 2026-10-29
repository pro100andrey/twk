/// A small but strict terminal emulator used as the test oracle for the
/// presenter. It knows nothing about the core's buffers: it only consumes
/// bytes, like a real terminal, and models the behaviours that cause
/// artifacts in practice:
///
///  * autowrap with a pending-wrap flag (a printed char after the last
///    column wraps and may scroll the screen),
///  * background color erase (BCE) for EL/ECH/ED/SU/SD, switchable,
///  * DECSTBM scroll margins with SU/SD, IL/DL,
///  * optionally Konsole's lines ([Vt.konsoleLines]): each as long as what
///    was written or erased on it, DCH filling the end of that instead of
///    the right margin, ICH inserting blanks in the default colours,
///  * two-column glyphs: overwriting either half blanks the other half,
///  * optionally a normal screen: a scrollback that lines scrolled off the
///    top go to ([Vt.history]), rows the application must not touch
///    ([Vt.guardRows]) and a resize that keeps what the screen shows
///    ([Vt.resizeKeeping]),
///  * configurable cluster widths, so a terminal that *disagrees* with the
///    application can be simulated,
///  * images ([Vt.images]): kitty placements, which stay over the cells
///    they were placed on while text is printed or erased there and move
///    with them when they scroll, and sixel and iTerm2 images, whose pixels
///    are those of their cells, taken away with what is printed or erased
///    there; optionally Konsole's ([Vt.konsoleImages]), which a scroll up
///    moves up all of, and a scroll down none of, wherever the scrolled
///    rows are, and whose image data a deletion keeps.
///
/// Any byte sequence it doesn't understand is a test failure, as is any
/// wrap or scroll caused by printing (the presenter must never rely on them).
///
/// [Vt] is the emulator, [VtCell] a cell of its screen and [VtImage] an
/// image it shows.
///
/// @docImport 'package:twk_core/twk_core.dart';
/// @docImport 'src/tester.dart';
/// @docImport 'vt_terminal.dart';
library;

import 'dart:convert';

import 'package:twk_core/twk_core.dart'
    show ClusterScan, Color, GraphicsProtocol, TextSegmenter;

import 'src/screen_text.dart';

// Examples can assume:
// import 'dart:convert';
// import 'package:twk_core/twk_core.dart' show Attr, Color;

/// A cell of a [Vt]'s screen: the text printed in it and the colors and
/// attributes it was printed with.
///
/// A color is a number as [Color] packs one: `0` for the terminal's
/// default, `0x2000000 | index` for an entry of the palette,
/// `0x1000000 | 0xRRGGBB` for 24-bit RGB.
final class VtCell {
  /// The grapheme cluster shown, a space for a blank cell; the trailing
  /// half of a wide glyph ([role] -1) keeps the text it was blanked with.
  var text = ' ';

  /// The text's color; `0` for the terminal's default.
  var fg = 0;

  /// The background's color; `0` for the terminal's default.
  var bg = 0;

  /// The underline's color (SGR 58); `0` for the text's.
  var ul = 0;

  /// The attributes, [Attr]'s bits: bold, italic, the kind of underline
  /// and the rest.
  var attrs = 0;

  /// 0 = normal, 2 = leading half of a wide glyph, -1 = trailing half.
  var role = 0;

  /// Hyperlink (OSC 8) of the cell, null for none.
  String? link;

  /// The sixel or iTerm2 image whose pixels the cell has, null for none.
  VtImage? image;

  /// The kitty placement over the cell, null for none.
  VtImage? kitty;

  /// Makes this cell a blank on the background [bgColor]: a space without
  /// attributes, hyperlink or the pixels of an image. A kitty placement
  /// over it stays.
  void blank(int bgColor) {
    text = ' ';
    fg = 0;
    bg = bgColor;
    ul = 0;
    attrs = 0;
    role = 0;
    link = null; // erasing removes hyperlinks
    image = null; // and pixels, not kitty placements
  }

  /// Makes this cell show what [o] shows: its text, colors, attributes,
  /// hyperlink and images.
  void copyFrom(VtCell o) {
    text = o.text;
    fg = o.fg;
    bg = o.bg;
    ul = o.ul;
    attrs = o.attrs;
    role = o.role;
    link = o.link;
    image = o.image;
    kitty = o.kitty;
  }

  /// [fg] as a [Color]: [Color.defaultColor] for the terminal's own.
  ///
  /// ```dart
  /// final vt = Vt(4, 1)..feed(utf8.encode('\x1b[31mA'));
  /// assert(vt.cell(0, 0).fgColor == Color.red);
  /// ```
  Color get fgColor => colorOf(fg);

  /// [bg] as a [Color]: [Color.defaultColor] for the terminal's own.
  Color get bgColor => colorOf(bg);

  /// [ul] as a [Color]: [Color.defaultColor] for the text's.
  Color get ulColor => colorOf(ul);

  /// The text and its style, as a snapshot with styles marks them
  /// (`[bold red]a[/]`, see `matchesScreen` in package:twk_test).
  @override
  String toString() => markedCell(this);
}

/// An image the terminal shows ([Vt.images]): placement [placement] of
/// kitty image [id], or a sixel or iTerm2 image, of [bytes] bytes of
/// image data, over the [cells] cells it still has of the [cols] x [rows]
/// from ([x], [y]).
final class VtImage {
  VtImage._(
    this.protocol,
    this.bytes, {
    this.id = 0,
    this.placement = 0,
    this.crop,
  });

  /// The protocol it was sent in: kitty, sixel or iTerm2.
  final GraphicsProtocol protocol;

  /// kitty: the id of the image; `0` for a sixel or iTerm2 image.
  final int id;

  /// kitty: the id of the placement of the image; `0` for a sixel or
  /// iTerm2 image.
  final int placement;

  /// How many bytes of image data were sent for it, as decoded from their
  /// base64 where they were sent so.
  final int bytes;

  /// kitty: the part of the image shown, (x, y, width, height) in pixels;
  /// null for all of it.
  final (int, int, int, int)? crop;

  /// The column of the left of the rectangle around its cells, as
  /// [Vt.images] last found it.
  var x = 0;

  /// The row of the top of the rectangle around its cells, as [Vt.images]
  /// last found it.
  var y = 0;

  /// How many columns the rectangle around its cells is wide.
  var cols = 0;

  /// How many rows the rectangle around its cells is high.
  var rows = 0;

  /// How many cells of the rectangle still show it: fewer than [cols] ×
  /// [rows] where text was printed over a sixel or iTerm2 image, or part
  /// of it scrolled off.
  var cells = 0;

  @override
  String toString() =>
      '${protocol.name}${id == 0 ? '' : ' $id/$placement'} ${cols}x$rows '
      'at ($x, $y)${cells == cols * rows ? '' : ', $cells cells'}, '
      '$bytes bytes${crop == null ? '' : ', crop $crop'}';
}

/// A terminal emulator of [width] × [height] cells that fails on what a
/// terminal would show wrong: [feed] gives it the bytes an application
/// writes, and [cell], [lines] and the cursor ([cx], [cy]) read back what
/// the screen shows.
///
/// A sequence it does not take, and a print that wraps or scrolls, is an
/// error: kept in [errors], and thrown as a [StateError] when [strict].
///
/// A screen of 20 × 2 cells, fed a bold word and a move to the next row:
///
/// ```dart
/// final vt = Vt(20, 2)..feed('\x1b[1mhi\x1b[0m\x1b[2;1Hthere'.codeUnits);
/// assert(vt.lines.first == 'hi');
/// assert(vt.cell(0, 0).attrs & Attr.bold != 0);
/// assert(vt.cy == 1);
/// ```
///
/// See also:
///
///  * [TwkTester.vt], the emulator of a test's app, fed its frames.
///  * [VtTerminal], a terminal backend that writes into one.
final class Vt {
  /// A [width] × [height] screen, blank, the cursor at its top left.
  ///
  /// [bce] erases in the current background, as most terminals do; off,
  /// in the default one. [konsoleLines] keeps Konsole's line lengths,
  /// [konsoleImages] moves images as Konsole does.
  /// [segmenter] splits printed text into cells, by default as the
  /// application's [TextSegmenter] does. [strict] throws each error as it
  /// happens; off, they are only kept in [errors]. [allowLineFeed] takes
  /// LF, [scrollback] keeps the lines scrolled off the top in [history],
  /// and [relativeOnly] makes an absolute row an error, as drawing on the
  /// alternate screen is (going there to ask queries is not): the three of
  /// an inline region's normal screen. [cellPixelWidth] and [cellPixelHeight]
  /// are the size of a cell in pixels, for images.
  Vt(
    this.width,
    this.height, {
    this.bce = true,
    this.konsoleLines = false,
    this.konsoleImages = false,
    TextSegmenter? segmenter,
    this.strict = true,
    this.allowLineFeed = false,
    this.scrollback = false,
    this.relativeOnly = false,
    this.cellPixelWidth = 10,
    this.cellPixelHeight = 20,
  }) : segmenter = segmenter ?? TextSegmenter() {
    _grid = _newGrid(width, height);
    bottomMargin = height - 1;
    if (konsoleLines) {
      for (final row in _grid) {
        _lengths[row] = 0;
      }
    }
  }

  /// The screen's columns.
  int width;

  /// The screen's rows.
  int height;

  /// Background color erase: an erasure (EL, ECH, ED, scrolling, IL, DL)
  /// leaves blanks in the current background; off, in the default one.
  final bool bce;

  /// Konsole's line model: a row holds the cells up to its stored length
  /// (the end of what was printed on it, or erased on it short of the
  /// right margin in any colours, as Konsole's clearImage pads the line it
  /// erases; the cells past it show as default blanks), which an erasure
  /// to the right margin in the default colours cuts back to its start and
  /// one in other colours stretches to the margin. DCH works within that
  /// length: at or past it nothing happens, before it the deleted cells
  /// are taken out and as many blanks in the current colours and
  /// attributes are appended at its end, not at the right margin. ICH
  /// inserts blanks in the default colours, not the current background,
  /// and extends it, up to the margin.
  final bool konsoleLines;

  /// Konsole's images (its `Screen::scrollPlacements`): they are not
  /// carried by the rows they are on but kept apart, and moved by the
  /// whole screen's scroll up of every SU, DL and line feed at the bottom
  /// margin, those outside the scrolled rows too, and by no scroll down
  /// (SD, IL, a reverse index). A deletion (`a=d`, ED 2) takes the
  /// placements away and keeps the image data, which only an image sent
  /// under the same id replaces.
  final bool konsoleImages;

  /// Whether an error is thrown as a [StateError] when it happens, besides
  /// being kept in [errors].
  final bool strict;

  /// Accept LF (cursor down, scrolling at the bottom margin). Off by default:
  /// twk_core never emits LF (with the tty's ONLCR an LF would also return
  /// the cursor to column 0).
  final bool allowLineFeed;

  /// A normal screen: lines scrolled off its top (by LF or SU over the
  /// whole screen) are kept in [history] instead of being dropped.
  final bool scrollback;

  /// Absolute rows are an error (CUP, DECSTBM, ED 2, the alternate screen):
  /// an inline region doesn't know which screen row it starts on.
  final bool relativeOnly;

  /// A cell's width in pixels: a sixel image covers the cells its pixels
  /// reach into.
  final int cellPixelWidth;

  /// A cell's height in pixels, as [cellPixelWidth] is its width.
  final int cellPixelHeight;

  /// kitty: the images the terminal holds, by id, and their bytes.
  final kittyImages = <int, int>{};

  /// DEC mode 8452: a sixel image leaves the cursor to its right, on its
  /// last row, instead of below it.
  var sixelCursorRight = false;

  /// kitty: the keys and the data so far of an image sent in chunks.
  Map<String, String>? _kittyKeys;
  final _kittyData = <int>[];

  /// What DECSC saved: the cursor, its pending wrap and SGR.
  (int, int, bool, int, int, int, int)? _saved;

  /// The scrollback, oldest line first (see [scrollback]).
  final history = <List<VtCell>>[];

  /// Rows the application must not write to, erase or move (see
  /// [guardRows]); they stay guarded when they scroll.
  final _guarded = Set<List<VtCell>>.identity();

  /// How this terminal splits printed text into cells and how wide they are.
  final TextSegmenter segmenter;

  late List<List<VtCell>> _grid;

  /// [konsoleLines]: each row's stored length, by the row, held no longer
  /// than the row is; a row it lacks is as long as the screen is wide.
  /// Cells at or past it are default blanks.
  final _lengths = Expando<int>('line length');

  int _lengthOf(List<VtCell> row) => _lengths[row] ?? width;

  /// [konsoleLines]: the length of a row erased to the right margin from
  /// [x]: cut to [x] in the default colours, else the whole row.
  int _erasedLength(int x) => fg == 0 && _eraseBg == 0 ? x : width;

  /// The cursor's column, from 0.
  var cx = 0;

  /// The cursor's row, from 0.
  var cy = 0;

  /// Whether a character was printed in the last column and the cursor
  /// waits there: the next one printed wraps, with [autowrap].
  var pendingWrap = false;

  /// DEC mode 7: a character printed past the last column goes to the
  /// start of the next row; off, it overwrites the last column.
  var autowrap = true;

  /// DEC mode 25: whether the terminal shows the cursor.
  var cursorVisible = true;

  /// The top row of the scroll region (DECSTBM), from 0.
  var topMargin = 0;

  /// The bottom row of the scroll region (DECSTBM), from 0.
  late int bottomMargin;

  /// DECLRMM (DEC mode 69): whether DECSLRM sets [leftMargin] and
  /// [rightMargin].
  var leftRightMode = false;

  /// The left column of the scroll region (DECSLRM), from 0.
  var leftMargin = 0;

  /// The right column of the scroll region (DECSLRM), from 0.
  late int rightMargin = width - 1;

  /// How deep the synchronized updates (DEC mode 2026) are open: 1 between
  /// a begin and its end, 0 outside; anything else is an error.
  var syncDepth = 0;

  /// The cursor's shape as DECSCUSR set it last: `0` for the terminal's
  /// default, `1` to `6` a blinking or steady block, underline or bar.
  var cursorShape = 0;

  /// How many times the alternate screen (DEC mode 1049) was entered or
  /// left.
  var altScreenSwitches = 0;

  /// Whether a row was written while on the alternate screen, which this
  /// emulator keeps no screen of its own for: an app drawn there. A probe
  /// that asks its queries there, which write no cell, isn't.
  var drawnOnAlternate = false;

  // whether the alternate screen was entered and not left since
  var _alternate = false;

  /// BDSM (ECMA-48 mode 8) reset by `CSI 8 l`: explicit mode, each
  /// character shown in the cell it is written to, which is all this
  /// emulator does either way; `CSI 8 h` sets it again (implicit mode).
  var bidiExplicit = false;

  /// The color text is printed in, as SGR set it last; as [VtCell.fg].
  var fg = 0;

  /// The background text is printed on, as SGR set it last; as
  /// [VtCell.bg].
  var bg = 0;

  /// The underline's color, as SGR 58 set it last; as [VtCell.ul].
  var ul = 0;

  /// The attributes text is printed with, as SGR set them last; as
  /// [VtCell.attrs].
  var attrs = 0;

  /// Count of wraps/scrolls caused by printing (should stay 0).
  var printWraps = 0;

  /// What went wrong, in order: a sequence not taken, a print that
  /// wrapped, a guarded row changed. Empty while the application writes
  /// only what a terminal shows right.
  final errors = <String>[];

  final _utf8 = const Utf8Decoder();
  final _pending = <int>[];

  static List<List<VtCell>> _newGrid(int w, int h) =>
      List<List<VtCell>>.generate(
        h,
        (_) => List<VtCell>.generate(w, (_) => VtCell()),
      );

  /// The cell at column [x] of row [y] of the screen, both from 0.
  VtCell cell(int x, int y) => _grid[y][x];

  /// Simulates a resize. Real terminals reflow or keep old content in
  /// arbitrary ways, so the new grid is filled with junk: the application
  /// must repaint every cell.
  void resize(int w, int h) {
    width = w;
    height = h;
    _grid = _newGrid(w, h);
    // the junk is stored: every row, new and without a length, as long as
    // the screen
    for (final row in _grid) {
      for (final c in row) {
        c
          ..text = '#'
          ..bg = 0x1000000 | 0x123456;
      }
    }
    cx = cx.clamp(0, w - 1);
    cy = cy.clamp(0, h - 1);
    topMargin = 0;
    bottomMargin = h - 1;
    leftMargin = 0;
    rightMargin = w - 1;
    pendingWrap = false;
  }

  /// Simulates a resize of a terminal that keeps what the screen shows:
  /// rows are cut or padded with blanks at the right (no reflow) and the
  /// cursor stays on its row. A screen shorter than the cursor's row
  /// scrolls the rows above it into [history] (rows below the cursor are
  /// cut); a taller one gains blank rows at the bottom (xterm) or, with
  /// [pull], takes lines back from [history] at the top (VTE).
  void resizeKeeping(int w, int h, {bool pull = false}) {
    for (final row in _grid) {
      _fit(row, w);
    }
    if (h < height && cy >= h) {
      final k = cy - h + 1;
      for (var i = 0; i < k; i++) {
        final row = _grid.removeAt(0);
        if (scrollback) {
          history.add(row);
        }
      }
      cy -= k;
    }
    if (_grid.length > h) {
      _grid.removeRange(h, _grid.length);
    }
    if (pull) {
      while (_grid.length < h && history.isNotEmpty) {
        _grid.insert(0, _fit(history.removeLast(), w));
        cy++;
      }
    }
    while (_grid.length < h) {
      final row = List<VtCell>.generate(w, (_) => VtCell());
      if (konsoleLines) {
        _lengths[row] = 0;
      }
      _grid.add(row);
    }
    width = w;
    height = h;
    cx = cx.clamp(0, w - 1);
    topMargin = 0;
    bottomMargin = h - 1;
    leftMargin = 0;
    rightMargin = w - 1;
    pendingWrap = false;
  }

  /// [row] cut or padded to [w] cells in place; a wide glyph cut in half
  /// becomes a blank, and a stored length past [w] ([konsoleLines]) is cut
  /// to it.
  List<VtCell> _fit(List<VtCell> row, int w) {
    final length = _lengths[row];
    if (length != null && length > w) {
      _lengths[row] = w;
    }
    if (row.length > w) {
      row.removeRange(w, row.length);
      if (w > 0 && row[w - 1].role == 2) {
        row[w - 1].blank(row[w - 1].bg);
      }
    }
    while (row.length < w) {
      row.add(VtCell());
    }
    return row;
  }

  /// Guards the top [count] rows of the screen and every line in
  /// [history]: writing to, erasing or moving one of them is an error,
  /// wherever scrolling or a resize takes it.
  void guardRows(int count) {
    _guarded.addAll(history);
    for (var y = 0; y < count; y++) {
      _guarded.add(_grid[y]);
    }
  }

  void _touch(List<VtCell> row) {
    if (_alternate && !drawnOnAlternate) {
      drawnOnAlternate = true;
      _absolute('drawing on the alternate screen');
    }
    if (_guarded.isNotEmpty && _guarded.contains(row)) {
      _err('a guarded row was changed');
    }
  }

  void _absolute(String what) {
    if (relativeOnly) {
      _err('$what addresses an absolute row');
    }
  }

  /// The text of every line, the scrollback first, without the blanks
  /// that end them.
  List<String> get lines => [
    for (final row in history) _text(row),
    for (final row in _grid) _text(row),
  ];

  static String _text(List<VtCell> row) =>
      row.map((c) => c.role == -1 ? '' : c.text).join().trimRight();

  /// The images on the screen, top to bottom, each where it is: the
  /// rectangle around the cells it still has.
  List<VtImage> get images {
    final found = <VtImage>[];
    final seen = Set<VtImage>.identity();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final c = _grid[y][x];
        for (final image in [c.kitty, c.image]) {
          if (image == null) {
            continue;
          }
          if (seen.add(image)) {
            found.add(
              image
                ..x = x
                ..y = y
                ..cols = 1
                ..rows = 1
                ..cells = 0,
            );
          }
          if (x < image.x) {
            image
              ..cols += image.x - x
              ..x = x;
          }
          image
            ..cols = x - image.x + 1 > image.cols ? x - image.x + 1 : image.cols
            ..rows = y - image.y + 1
            ..cells += 1;
        }
      }
    }
    return found;
  }

  void _err(String m) {
    errors.add(m);
    if (strict) {
      throw StateError(m);
    }
  }

  // ------------------------------------------------------------------ feed --

  /// Takes [bytes] as the terminal takes what an application writes:
  /// prints their text, runs their control sequences. A sequence cut off at
  /// the end of [bytes] waits for the rest in the next call.
  void feed(List<int> bytes) {
    var i = 0;
    final text = <int>[];
    void flushText() {
      if (text.isEmpty) {
        return;
      }
      _print(_utf8.convert(text));
      text.clear();
    }

    final data = <int>[..._pending, ...bytes];
    _pending.clear();
    while (i < data.length) {
      final b = data[i];
      if (b == 0x1B) {
        flushText();
        final end = _escape(data, i);
        if (end < 0) {
          _pending.addAll(data.sublist(i));
          return;
        }
        i = end;
      } else if (b == 0x0D) {
        flushText();
        cx = 0;
        pendingWrap = false;
        i++;
      } else if (b == 0x0A && allowLineFeed) {
        flushText();
        pendingWrap = false;
        _lineFeed();
        i++;
      } else if (b < 0x20 || b == 0x7F) {
        flushText();
        _err('raw control byte 0x${b.toRadixString(16)}');
        i++;
      } else {
        text.add(b);
        i++;
      }
    }
    flushText();
  }

  /// Parses an escape sequence at [i]; returns the index after it, or -1 if
  /// incomplete.
  int _escape(List<int> d, int i) {
    if (i + 1 >= d.length) {
      return -1;
    }
    final b1 = d[i + 1];
    if (b1 == 0x5D) {
      // OSC up to BEL or ST; OSC 8 (hyperlinks) is modelled, the rest
      // (queries, titles, clipboard) has no screen effect
      for (var j = i + 2; j < d.length; j++) {
        int end;
        if (d[j] == 0x07) {
          end = j + 1;
        } else if (d[j] == 0x1B && j + 1 < d.length && d[j + 1] == 0x5C) {
          end = j + 2;
        } else {
          continue;
        }
        _osc(String.fromCharCodes(d.sublist(i + 2, j)));
        return end;
      }
      return -1;
    }
    if (b1 == 0x50 || b1 == 0x5F) {
      // DCS / APC up to ST alone: a sixel image, kitty's graphics, what
      // tmux passes on to the terminal outside (ESC ESC is one ESC in it),
      // taken as that terminal takes it; others, and what screen passes
      // through, have no screen effect
      final tmux = _startsWith(d, i + 2, 'tmux;');
      var undoubled = false;
      for (var j = i + 2; j < d.length; j++) {
        if (d[j] != 0x1B) {
          continue;
        }
        if (j + 1 == d.length) {
          return -1;
        }
        final next = d[j + 1];
        if (next == 0x5C) {
          if (undoubled) {
            _err('an ESC not doubled in tmux passthrough');
          } else if (tmux) {
            _passedOn(d, i + 7, j);
          } else if (b1 == 0x5F) {
            if (i + 2 < j && d[i + 2] == 0x47) {
              _kitty(d.sublist(i + 3, j));
            }
          } else {
            _sixel(d.sublist(i + 2, j));
          }
          return j + 2;
        }
        if (next == 0x1B) {
          j++;
        } else if (tmux) {
          undoubled = true;
        }
      }
      return -1;
    }
    if (b1 == 0x37) {
      _saved = (cx, cy, pendingWrap, fg, bg, ul, attrs); // DECSC
      return i + 2;
    }
    if (b1 == 0x38) {
      // DECRC
      if (_saved case (
        final x,
        final y,
        final wrap,
        final f,
        final b,
        final u,
        final a,
      )) {
        cx = x;
        cy = y;
        pendingWrap = wrap;
        fg = f;
        bg = b;
        ul = u;
        attrs = a;
      } else {
        _err('DECRC without DECSC');
      }
      return i + 2;
    }
    if (b1 != 0x5B) {
      _err('unsupported escape ESC ${String.fromCharCode(b1)}');
      return i + 2;
    }
    var j = i + 2;
    var private = false;
    if (j < d.length && d[j] == 0x3F) {
      private = true;
      j++;
    } else if (j < d.length && (d[j] == 0x3C || d[j] == 0x3D || d[j] == 0x3E)) {
      // CSI > / < / = ... (kitty keyboard push/pop, queries): no screen effect
      while (j < d.length && !(d[j] >= 0x40 && d[j] <= 0x7E)) {
        j++;
      }
      if (j >= d.length) {
        return -1;
      }
      return j + 1;
    }
    final paramStart = j;
    while (j < d.length && (d[j] >= 0x30 && d[j] <= 0x3F)) {
      j++;
    }
    final paramEnd = j;
    var intermediate = 0;
    while (j < d.length && d[j] >= 0x20 && d[j] <= 0x2F) {
      intermediate = d[j];
      j++;
    }
    if (j >= d.length) {
      return -1;
    }
    final params = String.fromCharCodes(d.sublist(paramStart, paramEnd));
    final fin = d[j];
    if (intermediate == 0x24 && fin == 0x70) {
      return j + 1;
    } // DECRQM query
    if (intermediate == 0x20 && fin == 0x71) {
      cursorShape = params.isEmpty ? 0 : int.parse(params); // DECSCUSR
      return j + 1;
    }
    if (intermediate != 0) {
      final c = String.fromCharCode(intermediate);
      _err('unsupported CSI with intermediate $c');
      return j + 1;
    }
    _csi(private, params, fin);
    return j + 1;
  }

  List<int> _nums(String p, {int count = 1, int dflt = 1}) {
    final parts = p.isEmpty ? <String>[] : p.split(';');
    return <int>[
      for (var k = 0; k < (parts.length > count ? parts.length : count); k++)
        if (k < parts.length && parts[k].isNotEmpty)
          int.parse(parts[k])
        else
          dflt,
    ];
  }

  void _csi(bool private, String params, int fin) {
    final f = String.fromCharCode(fin);
    if (private) {
      if (f == 'p' || f == 'u') {
        return;
      } // DECRQM query, kitty keyboard query
      final mode = int.parse(params);
      final on = f == 'h';
      if (f != 'h' && f != 'l') {
        _err('unsupported private CSI $params$f');
      }
      if (mode == 69) {
        leftRightMode = on;
        if (!on) {
          leftMargin = 0;
          rightMargin = width - 1;
        }
        return;
      }
      const screenNeutral = <int>{
        1049,
        1000,
        1002,
        1003,
        1006,
        2004,
        1004,
        2048,
        2027,
        2031,
      };
      if (screenNeutral.contains(mode)) {
        if (mode == 1049) {
          altScreenSwitches++;
          _alternate = on;
        }
        return;
      }
      switch (mode) {
        case 8452:
          sixelCursorRight = on;
        case 2026:
          syncDepth += on ? 1 : -1;
          if (syncDepth < 0 || syncDepth > 1) {
            _err('unbalanced 2026');
          }
        case 25:
          cursorVisible = on;
        case 7:
          autowrap = on;
        default:
          _err('unsupported private mode $mode');
      }
      return;
    }
    if ((f == 'h' || f == 'l') && params == '8') {
      bidiExplicit = f == 'l'; // BDSM
      return;
    }
    switch (f) {
      case 'H':
      case 'f':
        _absolute('CUP');
        final n = _nums(params, count: 2);
        cy = (n[0] - 1).clamp(0, height - 1);
        cx = (n[1] - 1).clamp(0, width - 1);
        pendingWrap = false;
      case 'A':
        cy = (cy - _nums(params)[0]).clamp(0, height - 1);
        pendingWrap = false;
      case 'B':
        cy = (cy + _nums(params)[0]).clamp(0, height - 1);
        pendingWrap = false;
      case 'C':
        cx = (cx + _nums(params)[0]).clamp(0, width - 1);
        pendingWrap = false;
      case 'D':
        cx = (cx - _nums(params)[0]).clamp(0, width - 1);
        pendingWrap = false;
      case 'G':
        cx = (_nums(params)[0] - 1).clamp(0, width - 1);
        pendingWrap = false;
      case 'K':
        final mode = _nums(params, dflt: 0)[0];
        final from = mode == 0 ? cx : 0;
        final to = mode == 1 ? cx + 1 : width;
        _eraseCells(cy, from, to);
      case 'X':
        final n = _nums(params)[0];
        _eraseCells(cy, cx, (cx + n).clamp(0, width));
      case 'J':
        final mode = _nums(params, dflt: 0)[0];
        if (mode == 0) {
          // from the cursor to the end of the screen
          _eraseCells(cy, cx, width);
          for (var y = cy + 1; y < height; y++) {
            _eraseCells(y, 0, width);
          }
        } else if (mode == 2) {
          _absolute('ED 2');
          for (var y = 0; y < height; y++) {
            _eraseCells(y, 0, width);
          }
          // kitty deletes the images on the screen, and frees them;
          // Konsole keeps their data
          _deleteKitty((_) => true, free: konsoleImages ? null : {});
        } else {
          _err('unsupported ED $mode');
        }
      case 'L':
        _insertLines(_nums(params)[0]);
      case 'M':
        _deleteLines(_nums(params)[0]);
      case '@':
        _insertChars(_nums(params)[0]);
      case 'P':
        _deleteChars(_nums(params)[0]);
      case 'S':
        _scrollUp(_nums(params)[0]);
      case 'T':
        _scrollDown(_nums(params)[0]);
      case 'r':
        _absolute('DECSTBM');
        final n = _nums(params, count: 2, dflt: 0);
        final top = n[0] == 0 ? 1 : n[0];
        final bottom = n[1] == 0 ? height : n[1];
        if (top >= bottom) {
          _err('bad DECSTBM $params');
        }
        topMargin = top - 1;
        bottomMargin = bottom - 1;
        cx = 0;
        cy = 0;
        pendingWrap = false;
      case 'b':
        final last = _last;
        if (last == null) {
          _err('REP without a preceding character');
        } else if (last.runes.length > 1) {
          // terminals disagree on what "the preceding character" of a
          // combining sequence is
          _err('REP after a multi-code-point cluster');
        } else {
          for (var k = _nums(params)[0]; k > 0; k--) {
            _putCluster(last, _lastWidth);
          }
        }
      case 's':
        if (!leftRightMode) {
          _err('SCOSC (save cursor) is not expected');
        } else {
          final n = _nums(params, count: 2, dflt: 0);
          final l = n[0] == 0 ? 1 : n[0];
          final r = n[1] == 0 ? width : n[1];
          if (l >= r) {
            _err('bad DECSLRM $params');
          }
          leftMargin = l - 1;
          rightMargin = r - 1;
          cx = 0;
          cy = 0;
          pendingWrap = false;
        }
      case 't':
        // XTWINOPS title stack push/pop, the sizes in pixels or cells
        // asked: no screen effect
        final op = _nums(params, dflt: 0)[0];
        if (op != 22 && op != 23 && op != 14 && op != 16 && op != 18) {
          _err('unsupported CSI ${params}t');
        }
      case 'm':
        _sgr(params);
      case 'c':
        break; // DA1 query
      case 'n' when params == '6':
        break; // cursor position query
      default:
        _err('unsupported CSI $params$f');
    }
  }

  void _sgr(String params) {
    final parts = params.isEmpty ? <String>['0'] : params.split(';');
    for (var k = 0; k < parts.length; k++) {
      final part = parts[k];
      if (part.contains(':')) {
        final sub = [
          for (final x in part.split(':'))
            if (x.isEmpty) 0 else int.parse(x),
        ];
        if (sub[0] == 58 && sub.length == 3 && sub[1] == 5) {
          ul = 0x2000000 | sub[2]; // 58:5:i
        } else if (sub[0] == 58 && sub.length == 6 && sub[1] == 2) {
          // 58:2:<colorspace>:r:g:b
          ul = 0x1000000 | (sub[3] << 16) | (sub[4] << 8) | sub[5];
        } else if (sub[0] == 4 && sub.length == 2) {
          attrs = (attrs & ~(7 << 3)) | ((sub[1] & 7) << 3);
        } else {
          _err('unsupported colon SGR $part');
        }
        continue;
      }
      final p = part.isEmpty ? 0 : int.parse(part);
      int color() {
        final kind = int.parse(parts[++k]);
        if (kind == 5) {
          return 0x2000000 | int.parse(parts[++k]);
        }
        if (kind == 2) {
          final r = int.parse(parts[++k]);
          final g = int.parse(parts[++k]);
          final b = int.parse(parts[++k]);
          return 0x1000000 | (r << 16) | (g << 8) | b;
        }
        _err('bad extended color');
        return 0;
      }

      switch (p) {
        case 0:
          fg = bg = ul = attrs = 0;
        case 1:
          attrs |= 1;
        case 2:
          attrs |= 2;
        case 3:
          attrs |= 4;
        case 4:
          attrs = (attrs & ~(7 << 3)) | (1 << 3);
        case 5:
          attrs |= 1 << 6;
        case 7:
          attrs |= 1 << 7;
        case 8:
          attrs |= 1 << 8;
        case 9:
          attrs |= 1 << 9;
        case 22:
          attrs &= ~3;
        case 23:
          attrs &= ~4;
        case 24:
          attrs &= ~(7 << 3);
        case 25:
          attrs &= ~(1 << 6);
        case 27:
          attrs &= ~(1 << 7);
        case 28:
          attrs &= ~(1 << 8);
        case 29:
          attrs &= ~(1 << 9);
        case 39:
          fg = 0;
        case 49:
          bg = 0;
        case 53:
          attrs |= 1 << 10;
        case 55:
          attrs &= ~(1 << 10);
        case 38:
          fg = color();
        case 48:
          bg = color();
        case 58:
          // terminals that know SGR 58 differ on the semicolon form; the
          // colon form is the one they share
          _err('SGR 58 with semicolons');
          ul = color();
        case 59:
          ul = 0;
        default:
          if (p >= 30 && p <= 37) {
            fg = 0x2000000 | (p - 30);
          } else if (p >= 40 && p <= 47) {
            bg = 0x2000000 | (p - 40);
          } else if (p >= 90 && p <= 97) {
            fg = 0x2000000 | (p - 90 + 8);
          } else if (p >= 100 && p <= 107) {
            bg = 0x2000000 | (p - 100 + 8);
          } else {
            _err('unsupported SGR $p');
          }
      }
    }
  }

  /// Whether the bytes of [d] from [i] on are those of [s].
  static bool _startsWith(List<int> d, int i, String s) {
    if (i + s.length > d.length) {
      return false;
    }
    for (var k = 0; k < s.length; k++) {
      if (d[i + k] != s.codeUnitAt(k)) {
        return false;
      }
    }
    return true;
  }

  /// Current hyperlink (OSC 8), applied to printed cells.
  String? link;

  void _osc(String body) {
    if (body.startsWith('1337;File=')) {
      _iterm2(body.substring(10));
      return;
    }
    if (!body.startsWith('8;')) {
      return;
    }
    final semi = body.indexOf(';', 2);
    if (semi < 0) {
      _err('bad OSC 8');
      return;
    }
    final uri = body.substring(semi + 1);
    link = uri.isEmpty ? null : uri;
  }

  // --------------------------------------------------------------- images --

  /// What tmux passes on, bytes [from, to) of [d] with every ESC doubled,
  /// taken as the terminal outside takes it.
  void _passedOn(List<int> d, int from, int to) {
    final inner = <int>[];
    for (var k = from; k < to; k++) {
      inner.add(d[k]);
      if (d[k] == 0x1B && k + 1 < to && d[k + 1] == 0x1B) {
        k++;
      }
    }
    feed(inner);
    if (_pending.isNotEmpty) {
      _err('a sequence cut off in tmux passthrough');
      _pending.clear();
    }
  }

  /// A kitty graphics command (`APC G keys ; payload ST`): a transmission,
  /// possibly in chunks (`m=1` on all but the last), a placement, a
  /// deletion or a query; one with no id keeps nothing.
  void _kitty(List<int> body) {
    final semi = body.indexOf(0x3B);
    final keys = <String, String>{
      for (final kv in String.fromCharCodes(
        semi < 0 ? body : body.sublist(0, semi),
      ).split(','))
        if (kv.indexOf('=') case final e when e > 0)
          kv.substring(0, e): kv.substring(e + 1),
    };
    final payload = semi < 0 ? const <int>[] : body.sublist(semi + 1);
    final started = _kittyKeys;
    final more = keys['m'] == '1';
    if (started != null) {
      _kittyData.addAll(payload);
      if (!more) {
        _kittyKeys = null;
        _kittyCommand(started, _kittyData);
      }
      return;
    }
    if (more) {
      _kittyKeys = keys;
      _kittyData
        ..clear()
        ..addAll(payload);
      return;
    }
    _kittyCommand(keys, payload);
  }

  void _kittyCommand(Map<String, String> keys, List<int> payload) {
    int key(String k) => int.tryParse(keys[k] ?? '') ?? 0;
    final action = keys['a'] ?? 't';
    final id = key('i');
    if (action == 'q' || id == 0) {
      return;
    }
    if (keys['q'] != '2') {
      _err('a kitty command the terminal answers (no q=2)');
    }
    switch (action) {
      case 't' || 'T':
        if ((keys['t'] ?? 'd') != 'd') {
          _err('kitty data not sent in the command (t=${keys['t']})');
          return;
        }
        final List<int> data;
        try {
          data = base64.decode(String.fromCharCodes(payload));
        } on FormatException {
          _err('kitty data not in base64');
          return;
        }
        kittyImages[id] = data.length;
        if (action == 'T') {
          _kittyPlace(keys, id);
        }
      case 'p':
        if (!kittyImages.containsKey(id)) {
          _err('a kitty placement of image $id, which the terminal lacks');
          return;
        }
        _kittyPlace(keys, id);
      case 'd':
        final p = key('p');
        switch (keys['d'] ?? 'a') {
          case final d when d == 'i' || d == 'I':
            _deleteKitty(
              (k) => k.id == id && (p == 0 || k.placement == p),
              free: d == 'I' && !konsoleImages ? {id} : null,
            );
          case final d:
            _err('unsupported kitty deletion d=$d');
        }
      default:
        _err('unsupported kitty action a=$action');
    }
  }

  /// Places kitty image [id] at the cursor over the cells (`c`, `r`) the
  /// keys say, replacing the placement of the same id.
  void _kittyPlace(Map<String, String> keys, int id) {
    int key(String k) => int.tryParse(keys[k] ?? '') ?? 0;
    final cols = key('c');
    final rows = key('r');
    if (cols <= 0 || rows <= 0) {
      _err('a kitty placement not sized in cells (c, r)');
      return;
    }
    if (keys['C'] != '1') {
      _err('a kitty placement that moves the cursor (no C=1)');
    }
    final p = key('p');
    if (p != 0) {
      _deleteKitty((k) => k.id == id && k.placement == p);
    }
    final crop = keys.containsKey('w') || keys.containsKey('h')
        ? (key('x'), key('y'), key('w'), key('h'))
        : null;
    _show(
      VtImage._(
        GraphicsProtocol.kitty,
        kittyImages[id]!,
        id: id,
        placement: p,
        crop: crop,
      ),
      cols,
      rows,
    );
  }

  /// Deletes the kitty placements on the screen that [which] picks; with
  /// [free] the images they were of go too, and those of the ids in it,
  /// once no placement shows them.
  void _deleteKitty(bool Function(VtImage) which, {Set<int>? free}) {
    final ids = {...?free};
    for (final row in _grid) {
      for (final c in row) {
        final k = c.kitty;
        if (k != null && which(k)) {
          c.kitty = null;
          ids.add(k.id);
        }
      }
    }
    if (free != null) {
      for (final row in _grid) {
        for (final c in row) {
          ids.remove(c.kitty?.id);
        }
      }
      ids.forEach(kittyImages.remove);
    }
  }

  /// A DCS string: a sixel image (`P1;P2;P3 q "Pan;Pad;Ph;Pv …`) at the
  /// cursor, over the cells its pixels reach into; others have no screen
  /// effect.
  void _sixel(List<int> body) {
    var k = 0;
    while (k < body.length &&
        ((body[k] >= 0x30 && body[k] <= 0x39) || body[k] == 0x3B)) {
      k++;
    }
    if (k >= body.length || body[k] != 0x71) {
      return;
    }
    final size = RegExp(r'^"\d+;\d+;(\d+);(\d+)').firstMatch(
      String.fromCharCodes(body, k + 1, body.length < k + 64 ? null : k + 64),
    );
    if (size == null) {
      _err('a sixel image without its size (raster attributes)');
      return;
    }
    final cols = (int.parse(size[1]!) + cellPixelWidth - 1) ~/ cellPixelWidth;
    final rows = (int.parse(size[2]!) + cellPixelHeight - 1) ~/ cellPixelHeight;
    final x = cx;
    final y = cy;
    _show(VtImage._(GraphicsProtocol.sixel, body.length), cols, rows);
    if (sixelCursorRight) {
      cx = (x + cols).clamp(0, width - 1);
      cy = (y + rows - 1).clamp(0, height - 1);
    } else {
      _below(y + rows, 'a sixel image');
    }
  }

  /// An iTerm2 image (`OSC 1337 ; File = args : base64`), shown inline,
  /// sized in cells.
  void _iterm2(String s) {
    final colon = s.indexOf(':');
    if (colon < 0) {
      _err('an iTerm2 file without its data');
      return;
    }
    final args = <String, String>{
      for (final a in s.substring(0, colon).split(';'))
        if (a.indexOf('=') case final e when e > 0)
          a.substring(0, e): a.substring(e + 1),
    };
    final cols = int.tryParse(args['width'] ?? '');
    final rows = int.tryParse(args['height'] ?? '');
    if (args['inline'] != '1' || cols == null || rows == null) {
      _err('an iTerm2 file not shown inline in cells');
      return;
    }
    final List<int> data;
    try {
      data = base64.decode(s.substring(colon + 1));
    } on FormatException {
      _err('iTerm2 data not in base64');
      return;
    }
    if (int.tryParse(args['size'] ?? '') != data.length) {
      _err('an iTerm2 file whose size is not that of its data');
    }
    final y = cy;
    _show(VtImage._(GraphicsProtocol.iterm2, data.length), cols, rows);
    if (args['doNotMoveCursor'] != '1') {
      _below(y + rows, 'an iTerm2 image');
    }
  }

  /// Shows [image] over [cols] x [rows] cells from the cursor, which must
  /// be on the screen and blank (the application erased them).
  void _show(VtImage image, int cols, int rows) {
    if (cx + cols > width || cy + rows > height) {
      _err(
        'a ${image.protocol.name} image of ${cols}x$rows cells at '
        '($cx, $cy) reaches past the screen',
      );
    }
    var text = false;
    for (var y = cy; y < cy + rows && y < height; y++) {
      _touch(_grid[y]);
      for (var x = cx; x < cx + cols && x < width; x++) {
        final c = _grid[y][x];
        text = text || c.text != ' ';
        if (image.protocol == GraphicsProtocol.kitty) {
          c.kitty = image;
        } else {
          c.image = image;
        }
      }
    }
    if (text) {
      _err('${image.protocol.name} image over text');
    }
  }

  /// An image moved the cursor to the start of row [y], below it: one
  /// past the bottom margin scrolls the screen, an error.
  void _below(int y, String what) {
    cx = 0;
    pendingWrap = false;
    if (y > bottomMargin) {
      _err('$what scrolled the screen');
      for (var k = y - bottomMargin; k > 0; k--) {
        _scrollUp(1);
      }
      cy = bottomMargin;
    } else {
      cy = y;
    }
  }

  // ------------------------------------------------------------- printing --

  void _print(String s) {
    final scan = ClusterScan();
    for (var i = 0; i < s.length; i = scan.end) {
      segmenter.scan(s, i, scan);
      final cluster = s.substring(i, scan.end);
      final w = scan.width;
      if (w == 0) {
        // zero-width: attaches to the previous cell (like real terminals)
        _err('zero-width cluster printed: ${cluster.runes.toList()}');
        continue;
      }
      _putCluster(cluster, w);
    }
  }

  String? _last;
  var _lastWidth = 1;

  void _putCluster(String cluster, int w) {
    _last = cluster;
    _lastWidth = w;
    if (pendingWrap) {
      if (autowrap) {
        printWraps++;
        _err('print after last column wrapped');
        cx = 0;
        _lineFeed();
      }
      pendingWrap = false;
    }
    if (w == 2 && cx == width - 1) {
      if (autowrap) {
        printWraps++;
        _err('wide glyph at last column wrapped');
        cx = 0;
        _lineFeed();
      } else {
        _err('wide glyph at last column');
        return;
      }
    }
    _touch(_grid[cy]);
    _breakWide(cy, cx);
    if (w == 2) {
      _breakWide(cy, cx + 1);
    }
    _grid[cy][cx]
      ..text = cluster
      ..fg = fg
      ..bg = bg
      ..ul = ul
      ..attrs = attrs
      ..role = w == 2 ? 2 : 0
      ..link = link
      ..image = null;
    if (w == 2) {
      _grid[cy][cx + 1]
        ..text = ''
        ..fg = fg
        ..bg = bg
        ..ul = ul
        ..attrs = attrs
        ..role = -1
        ..link = link
        ..image = null;
    }
    if (konsoleLines && _lengthOf(_grid[cy]) < cx + w) {
      _lengths[_grid[cy]] = cx + w;
    }
    cx += w;
    if (cx >= width) {
      cx = width - 1;
      pendingWrap = autowrap;
    }
  }

  /// Overwriting either half of a wide glyph blanks the other half.
  void _breakWide(int y, int x) {
    final c = _grid[y][x];
    if (c.role == 2 && x + 1 < width) {
      _grid[y][x + 1]
        ..text = ' '
        ..role = 0;
      c
        ..role = 0
        ..text = ' ';
    } else if (c.role == -1 && x > 0) {
      _grid[y][x - 1]
        ..text = ' '
        ..role = 0;
      c
        ..role = 0
        ..text = ' ';
    }
  }

  /// ICH: insert n blanks at the cursor; the rest of the row moves right and
  /// whatever passes the right edge is lost.
  void _insertChars(int count) {
    pendingWrap = false;
    final row = _grid[cy];
    _touch(row);
    if (row[cx].role == -1) {
      _err('ICH inside a wide glyph');
    }
    final n = count.clamp(0, width - cx);
    for (var x = width - 1; x >= cx + n; x--) {
      row[x].copyFrom(row[x - n]);
    }
    // Konsole's are in the default colours
    final bg = konsoleLines ? 0 : _eraseBg;
    for (var x = cx; x < cx + n; x++) {
      row[x].blank(bg);
    }
    if (konsoleLines) {
      // padded to the cursor first, cut to the margin after
      final length = (_lengthOf(row) < cx ? cx : _lengthOf(row)) + n;
      _lengths[row] = length > width ? width : length;
    }
    // a wide glyph whose right half was pushed out disappears
    if (row[width - 1].role == 2) {
      row[width - 1].blank(row[width - 1].bg);
    }
  }

  /// DCH: delete n cells at the cursor; the rest of the row moves left and
  /// blanks fill in at the right edge ([konsoleLines]: at the line's end).
  void _deleteChars(int count) {
    pendingWrap = false;
    final row = _grid[cy];
    _touch(row);
    var n = count.clamp(0, width - cx);
    if (konsoleLines) {
      // the cells the line holds from the cursor, none past its end
      final held = _lengthOf(row) - cx;
      n = held <= 0 ? 0 : (n < held ? n : held);
    }
    if (row[cx].role == -1) {
      _err('DCH inside a wide glyph');
    }
    if (cx + n < width && row[cx + n].role == -1) {
      _err('DCH splits a wide glyph');
    }
    if (konsoleLines) {
      _deleteKonsole(row, n);
      return;
    }
    for (var x = cx; x < width - n; x++) {
      row[x].copyFrom(row[x + n]);
    }
    for (var x = width - n; x < width; x++) {
      row[x].blank(_eraseBg);
    }
  }

  /// DCH on Konsole's line of stored length L ([konsoleLines]): the [n]
  /// cells at the cursor go ([_deleteChars] keeps them within L, none at or
  /// past it), and as many blanks in the current colours and attributes
  /// come in at L, not at the margin.
  void _deleteKonsole(List<VtCell> row, int n) {
    final length = _lengthOf(row);
    for (var x = cx; x < length - n; x++) {
      row[x].copyFrom(row[x + n]);
    }
    for (var x = length - n; x < length; x++) {
      row[x]
        ..blank(bg)
        ..fg = fg
        ..ul = ul
        ..attrs = attrs;
    }
  }

  /// IL: insert n blank lines at the cursor's row; the rows below it move
  /// down within the scroll margins and those passing the bottom margin
  /// are lost. The cursor goes to the first column. Ignored outside the
  /// margins.
  void _insertLines(int count) {
    if (cy < topMargin || cy > bottomMargin) {
      return;
    }
    final images = _konsoleImages();
    if (!_fullWidthMargins) {
      _err('IL inside left/right margins');
    }
    for (var y = cy; y <= bottomMargin; y++) {
      _touch(_grid[y]);
    }
    final n = count.clamp(0, bottomMargin - cy + 1);
    for (var k = 0; k < n; k++) {
      final removed = _grid.removeAt(bottomMargin);
      _recycle(removed);
      _grid.insert(cy, removed);
    }
    _konsoleScrolled(images, 0);
    cx = 0;
    pendingWrap = false;
  }

  /// DL: delete n lines at the cursor's row; the rows below move up within
  /// the scroll margins and blank lines come in at the bottom margin. The
  /// cursor goes to the first column. Ignored outside the margins.
  void _deleteLines(int count) {
    if (cy < topMargin || cy > bottomMargin) {
      return;
    }
    final images = _konsoleImages();
    if (!_fullWidthMargins) {
      _err('DL inside left/right margins');
    }
    for (var y = cy; y <= bottomMargin; y++) {
      _touch(_grid[y]);
    }
    final n = count.clamp(0, bottomMargin - cy + 1);
    for (var k = 0; k < n; k++) {
      final removed = _grid.removeAt(cy);
      _recycle(removed);
      _grid.insert(bottomMargin, removed);
    }
    _konsoleScrolled(images, n);
    cx = 0;
    pendingWrap = false;
  }

  /// [konsoleImages]: the images of every cell of the screen, kitty's and
  /// the others', before a scroll; null without it.
  List<List<(VtImage?, VtImage?)>>? _konsoleImages() => konsoleImages
      ? [
          for (final row in _grid) [for (final c in row) (c.kitty, c.image)],
        ]
      : null;

  /// [konsoleImages]: puts [images], as [_konsoleImages] took them before
  /// a scroll, back on the screen [up] rows higher, the rows the scroll
  /// moved or not; those above the top are gone.
  void _konsoleScrolled(List<List<(VtImage?, VtImage?)>>? images, int up) {
    if (images == null) {
      return;
    }
    for (var y = 0; y < height; y++) {
      final row = _grid[y];
      for (var x = 0; x < width; x++) {
        final (kitty, image) = y + up < height
            ? images[y + up][x]
            : (null, null);
        row[x]
          ..kitty = kitty
          ..image = image;
      }
    }
  }

  void _lineFeed() {
    if (cy == bottomMargin) {
      _scrollUp(1);
    } else if (cy < height - 1) {
      cy++;
    }
  }

  int get _eraseBg => bce ? bg : 0;

  /// A row scrolled out at one margin comes in blank at the other, with no
  /// image.
  void _recycle(List<VtCell> row) {
    for (final c in row) {
      c
        ..blank(_eraseBg)
        ..kitty = null;
    }
    if (konsoleLines) {
      _lengths[row] = _erasedLength(0);
    }
  }

  void _eraseCells(int y, int x0, int x1) {
    if (x0 >= x1) {
      return;
    }
    _touch(_grid[y]);
    // erasing part of a wide glyph erases all of it
    final from = _grid[y][x0].role == -1 && x0 > 0 ? x0 - 1 : x0;
    final to = x1 < width && _grid[y][x1].role == -1 ? x1 + 1 : x1;
    for (var x = from; x < to; x++) {
      _grid[y][x].blank(_eraseBg);
    }
    if (konsoleLines) {
      final row = _grid[y];
      if (x1 >= width) {
        _lengths[row] = _erasedLength(from);
      } else if (_lengthOf(row) < to) {
        _lengths[row] = to;
      }
    }
  }

  bool get _fullWidthMargins => leftMargin == 0 && rightMargin == width - 1;

  /// SU/SD inside left/right margins: only those columns move.
  void _scrollColumns(int n) {
    final top = topMargin;
    final bottom = bottomMargin;
    final l = leftMargin;
    final r = rightMargin;
    for (var y = top; y <= bottom; y++) {
      _touch(_grid[y]);
      _lengths[_grid[y]] = null; // Konsole has no DECSLRM: the whole row
      if (_grid[y][l].role == -1 ||
          (r + 1 < width && _grid[y][r + 1].role == -1)) {
        _err('scroll margins cut a wide glyph');
      }
    }
    final rows = bottom - top + 1;
    final k = n.abs();
    for (var x = l; x <= r; x++) {
      final col = [for (var y = top; y <= bottom; y++) _grid[y][x]];
      final copy = [for (final c in col) VtCell()..copyFrom(c)];
      for (var i = 0; i < rows; i++) {
        final src = n > 0 ? i + k : i - k;
        if (src >= 0 && src < rows) {
          col[i].copyFrom(copy[src]);
        } else {
          col[i]
            ..blank(_eraseBg)
            ..kitty = null;
        }
      }
    }
  }

  void _scrollUp(int n) {
    final images = _konsoleImages();
    _scrollUpRows(n);
    _konsoleScrolled(images, n);
  }

  void _scrollUpRows(int n) {
    if (!_fullWidthMargins) {
      _scrollColumns(n);
      return;
    }
    final top = topMargin;
    final bottom = bottomMargin;
    if (scrollback && top == 0 && bottom == height - 1) {
      // the whole screen moves up: every row keeps its content, the top
      // one in the scrollback
      for (var k = 0; k < n; k++) {
        history.add(_grid.removeAt(0));
        final row = List<VtCell>.generate(
          width,
          (_) => VtCell()..blank(_eraseBg),
        );
        if (konsoleLines) {
          _lengths[row] = _erasedLength(0);
        }
        _grid.add(row);
      }
      return;
    }
    for (var y = top; y <= bottom; y++) {
      _touch(_grid[y]);
    }
    for (var k = 0; k < n; k++) {
      final removed = _grid.removeAt(top);
      _recycle(removed);
      _grid.insert(bottom, removed);
    }
  }

  void _scrollDown(int n) {
    final images = _konsoleImages();
    _scrollDownRows(n);
    _konsoleScrolled(images, 0);
  }

  void _scrollDownRows(int n) {
    if (!_fullWidthMargins) {
      _scrollColumns(-n);
      return;
    }
    final top = topMargin;
    final bottom = bottomMargin;
    for (var y = top; y <= bottom; y++) {
      _touch(_grid[y]);
    }
    for (var k = 0; k < n; k++) {
      final removed = _grid.removeAt(bottom);
      _recycle(removed);
      _grid.insert(top, removed);
    }
  }

  /// The rows of the screen, every cell's text with the blanks that end
  /// them, a line each.
  String dump() => [
    for (final row in _grid) row.map((c) => c.role == -1 ? '' : c.text).join(),
  ].join('\n');
}
