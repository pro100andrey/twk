/// Turns the difference between the desired screen (a [Surface]) and what
/// the terminal shows (the presenter's front buffer) into a minimal ANSI byte
/// stream.
///
/// Correctness rules (each one is exercised by test/presenter_fuzz_test.dart
/// against an independent terminal emulator):
///  * only damaged row spans are compared, widened so a two-column glyph is
///    never split; the front buffer is updated for exactly those spans;
///  * SGR is reset *before* a hardware scroll and before erase operations
///    with a background the terminal might not apply (BCE);
///  * the cursor column is treated as unknown after a glyph whose width
///    terminals disagree on, after the last column, and after DECSTBM;
///    a wide uncertain glyph is preceded by `ECH 2` (covers a narrower
///    rendering) and the cells it could overflow into when rendered wider
///    (see [GlyphTable.maxWidthOf]) are rewritten after it, so a disagreement
///    can't leave stale cells or shift the rest of the row;
///  * in the inline mode no row above the region is written but the rows
///    committed to the history, as they go in, and no row is addressed
///    absolutely (see [Presenter.inline], [Presenter.commit]);
///  * in a fixed viewport no cell outside it is written, erased or moved
///    (see [Presenter.viewport]);
///  * nothing is written when nothing changed.
///
/// @docImport 'app.dart';
/// @docImport 'canvas.dart';
/// @docImport 'screen.dart';
/// @docImport 'terminal/sequences.dart';
/// @docImport 'terminal/terminal.dart';
library;

import 'dart:typed_data';

import 'byte_sink.dart';
import 'fill.dart';
import 'graphics.dart';
import 'line_encoder.dart';
import 'style.dart';
import 'surface.dart';
import 'terminal/sequences.dart' show Multiplexer;

// Examples can assume:
// late TerminalBackend terminal;

/// Front buffer: a blank the presenter wrote under an image it shows; a
/// reserved cell ([kSkip]) the rows copied is whatever the terminal has.
const int _kUnder = kSkip | kBlank;

/// Sets the row flags `a[start, end)` to [value]. Not `fillRange`, which
/// on a typed list calls `[]=` out of line for every element: clearing the
/// flags of 60 rows that way took about an eighth of a spinner frame.
@pragma('vm:prefer-inline')
void _fillFlags(Uint8List a, int start, int end, int value) {
  for (var i = start; i < end; i++) {
    a[i] = value;
  }
}

/// What the presenter may assume about the terminal.
///
/// Each capability on lets the presenter write fewer bytes, or draw what
/// it could not otherwise (images); one on that the terminal lacks shows
/// wrong cells. The defaults are what nearly every terminal has; the
/// probe of [Terminal.open] fills them in from the terminal's answers and
/// the environment ([TerminalInfo.caps]).
///
/// A terminal known to repeat characters and to show kitty images:
///
/// ```dart
/// const caps = TerminalCaps(
///   repeatChar: true,
///   graphics: GraphicsProtocol.kitty,
///   cellPixelWidth: 10,
///   cellPixelHeight: 20,
/// );
/// final screen = Screen(80, 24, caps: caps);
/// ```
final class TerminalCaps {
  /// Capabilities as given; left out, those nearly every terminal has:
  /// synchronized output, background color erase, hardware scrolling,
  /// full frames cleared and ICH/DCH, without REP, Konsole's lines and
  /// images, left and right margins or a graphics protocol.
  const TerminalCaps({
    this.synchronizedOutput = true,
    this.backgroundColorErase = true,
    this.hardwareScroll = true,
    this.clearFullFrames = true,
    this.repeatChar = false,
    this.insertDelete = true,
    this.konsoleLines = false,
    this.konsoleImages = false,
    this.leftRightMargins = false,
    this.graphics = GraphicsProtocol.none,
    this.graphicsMultiplexer = Multiplexer.none,
    this.cellPixelWidth = 0,
    this.cellPixelHeight = 0,
  });

  /// Wrap frames in DEC mode 2026 (ignored by terminals that lack it).
  final bool synchronizedOutput;

  /// Erase operations (EL, ECH, SU) fill with the current background.
  /// False for e.g. GNU screen without `defbce`: then erasures are only used
  /// with the default background.
  final bool backgroundColorErase;

  /// Use DECSTBM + SU/SD for scrolled regions.
  final bool hardwareScroll;

  /// For a full repaint (first frame, resize), paint the dominant background
  /// with one `ED 2` and write only the other cells. Only used together with
  /// [synchronizedOutput] (an unsynchronized clear would flash).
  final bool clearFullFrames;

  /// The terminal implements REP (`CSI n b`, repeat the preceding
  /// character): runs of one character are sent once plus a count.
  final bool repeatChar;

  /// Use ICH/DCH (insert/delete characters, VT102) when a row's change is a
  /// shift of its tail - typing or deleting in the middle of a line.
  final bool insertDelete;

  /// The terminal's lines are Konsole's: each as long as what was written
  /// on it. Its ICH inserts blanks in the default colours, not the current
  /// background, and its DCH appends its blanks, in the current colours and
  /// attributes, at the end of the line, mid-row on a short one, not at the
  /// right margin. The presenter then shifts a row only with the default
  /// SGR, whose blanks look the same wherever they land and on a terminal
  /// that does as xterm does: a wrong guess costs bytes, never cells.
  final bool konsoleLines;

  /// The terminal's images are Konsole's: they are not carried by the rows
  /// they are on, and every scroll up (SU, DL, a line feed at the bottom
  /// margin) moves all of them up, those outside the scrolled rows too,
  /// while no scroll down moves any. The presenter then places every
  /// kitty image again after a scroll, and scrolls no rows in hardware
  /// while it shows a sixel or iTerm2 image. A kitty image deleted keeps
  /// its data in Konsole until one sent under the same id replaces it:
  /// the presenter gives a new image the id of one it deleted.
  final bool konsoleImages;

  /// The terminal has DECLRMM/DECSLRM (left/right margins, DEC mode 69,
  /// detected with DECRQM): a scroll view narrower than the screen scrolls
  /// in hardware too.
  final bool leftRightMargins;

  /// How the terminal shows images ([Canvas.image]); with
  /// [GraphicsProtocol.none], and for an image encoded for another
  /// protocol, their cells stay blank.
  final GraphicsProtocol graphics;

  /// The multiplexer image sequences pass through to the terminal
  /// outside ([passthroughSequence]); none where it shows the images
  /// itself, as tmux 3.4 shows sixel.
  final Multiplexer graphicsMultiplexer;

  /// A cell's width in pixels, which an image is scaled to cells by; 0
  /// when not known.
  final int cellPixelWidth;

  /// A cell's height in pixels (see [cellPixelWidth]); 0 when not known.
  final int cellPixelHeight;
}

/// A rectangle of the terminal's screen that an app draws in and owns
/// ([TwkApp.viewport], [Presenter.viewport]): nothing outside it is
/// written.
///
/// ```dart
/// // a status panel in the 40 x 5 cells at the top left
/// final app = TwkApp(terminal, viewport: const Viewport.fixed(0, 0, 40, 5));
/// ```
final class Viewport {
  /// The [width] x [height] cells from column [left] of row [top], counted
  /// from 0 at the screen's top left.
  const Viewport.fixed(this.left, this.top, this.width, this.height)
    : assert(
        left >= 0 && top >= 0 && width >= 0 && height >= 0,
        'a viewport has no negative coordinate or size',
      );

  /// The screen column of the viewport's first column.
  final int left;

  /// The screen row of the viewport's first row.
  final int top;

  /// How many columns the viewport has; the screen may cut it.
  final int width;

  /// How many rows the viewport has; the screen may cut it.
  final int height;
}

/// Cursor shapes (DECSCUSR). [terminalDefault] restores the user's setting.
///
/// The presenter sets one ([Presenter.cursorShape]) while the cursor is
/// visible; a text field wants [bar].
enum CursorShape {
  /// Whatever shape the user set the terminal to.
  terminalDefault(0),

  /// A blinking block.
  blinkingBlock(1),

  /// A steady block.
  block(2),

  /// A blinking underline.
  blinkingUnderline(3),

  /// A steady underline.
  underline(4),

  /// A blinking bar, between two cells.
  blinkingBar(5),

  /// A steady bar, between two cells.
  bar(6);

  const CursorShape(this.code);

  /// The shape's number in DECSCUSR (`CSI code SP q`).
  final int code;
}

/// Statistics of the last [Presenter.present] call.
///
/// See also:
///
///  * [FrameStats], what the frames of an app cost.
final class PresentStats {
  /// Statistics of no present yet, all zero.
  PresentStats();

  /// The bytes the frame wrote.
  var bytes = 0;

  /// The cells compared with what the terminal shows.
  var cellsCompared = 0;

  /// The cells written.
  var cellsWritten = 0;

  /// The rows a hardware scroll moved.
  var scrolledRows = 0;

  /// Rows whose tail was shifted with ICH/DCH.
  var shiftedRows = 0;

  /// Hardware scroll operations (DECSTBM + SU/SD) in the frame.
  var scrollOps = 0;

  /// Of those, scrolls of a narrower-than-screen rectangle (DECSLRM).
  var rectScrollOps = 0;

  /// Of those, scrolls of a narrower-than-screen rectangle the terminal has
  /// no margins for, scrolled as whole rows (the cells beside it re-diffed).
  var widenedScrollOps = 0;

  /// Inline mode: rows written above the region ([Presenter.commit]).
  var committedRows = 0;

  /// Images drawn: sent, or placed again (kitty).
  var images = 0;
}

/// Writes what changed on a [Surface] as the bytes that make the terminal
/// show it: the shortest cursor moves, SGR only where the style changes,
/// erases for blank runs, hardware scrolls for moved rows, images, all in
/// one synchronized update.
///
/// It keeps what the terminal shows (its front buffer) and compares only
/// the damaged spans of the surface with it ([present]), then clears the
/// surface's damage. [caps] says what it may use; [inline] and [viewport]
/// choose the screen mode. The bytes are in [out] until the next call.
///
/// ```dart
/// final styles = StyleTable();
/// final glyphs = GlyphTable();
/// final surface = Surface(20, 2);
/// final presenter = Presenter(20, 2, styles, glyphs);
/// Canvas(surface, styles, glyphs).text(0, 0, 'hi', styles.pen(const Pen()));
/// presenter.present(surface); // the first frame: every cell
/// presenter.present(surface); // 0: nothing changed
/// ```
///
/// See also:
///
///  * [Screen], a surface, its canvas and a presenter together.
final class Presenter {
  /// A presenter for a surface [width] x [height], of [styles] and
  /// [glyphs], that knows nothing of what the terminal shows: the first
  /// frame writes every cell.
  ///
  /// [caps] is what the terminal supports, [autoScroll] whether moved rows
  /// are looked for. [inline] makes the surface a region of the normal
  /// screen, [viewport] a fixed rectangle of it (not both); with neither,
  /// it is the whole screen. [atLineStart] is whether the cursor is at the
  /// start of a line when an inline region starts: false, the region
  /// starts on the line after it.
  Presenter(
    this.width,
    this.height,
    this.styles,
    this.glyphs, {
    this.caps = const TerminalCaps(),
    this.autoScroll = true,
    this.inline = false,
    this.viewport,
    bool atLineStart = true,
  }) : assert(
         !inline || viewport == null,
         'an inline region is no fixed viewport',
       ),
       _ox = viewport?.left ?? 0,
       _oy = viewport?.top ?? 0,
       _fc = Uint32List(width * height),
       _fs = Uint32List(width * height) {
    _fc64 = view64(_fc);
    _fs64 = view64(_fs);
    if (inline) {
      _lineAbove = !atLineStart;
      _cy = atLineStart ? 0 : -1;
    }
    _forgetScreen();
  }

  /// How many cells wide the surface presented is.
  int width;

  /// How many rows tall the surface presented is.
  int height;

  /// The styles of the cells, whose SGR sequences are written.
  final StyleTable styles;

  /// The clusters of more than one code point the cells hold.
  final GlyphTable glyphs;

  /// What the terminal supports; a change applies from the next frame.
  TerminalCaps caps;

  /// Detect scrolled content (rows that moved by up to [maxAutoScroll])
  /// and scroll it in hardware.
  bool autoScroll;

  /// The most rows a block may have moved by for [autoScroll] to find it,
  /// 32 by default.
  var maxAutoScroll = 32;

  /// The inline mode: the surface is a region of the normal screen whose
  /// first row is the line the cursor is on when the presenter starts (the
  /// line after it unless `atLineStart`), below what the screen showed
  /// before. No row above the region is ever written but the rows
  /// [commit] puts in there, and none is addressed absolutely: every move
  /// is relative to the cursor (never CUP), a scroll inside the region is
  /// a DL and an IL at the edges of the rows that move (the rows below
  /// them end where they were; no DECSTBM, no DECSLRM), and a full frame
  /// erases from the region's first row down (`ED 0`) instead of the whole
  /// screen. A change of the surface's height alone grows or shrinks the
  /// region and keeps what it shows: rows it gains are made room for with
  /// line feeds below it (the screen scrolls its history up once the
  /// region reaches the bottom), rows it loses are erased. [resize] means
  /// the terminal was resized: the cursor stayed on its line, so moving up
  /// by its row in the region finds the region again, which is repainted
  /// from scratch. See [leave].
  final bool inline;

  /// Inline mode: the cursor is on the line above the region (it started
  /// after text on its line), so the first frame begins with a line feed.
  var _lineAbove = false;

  /// Inline mode: a frame has put the region on the screen.
  var _entered = false;

  /// Inline mode: how many of the region's rows, from its first, are known
  /// to be on the screen; the screen may have more rows below them, all
  /// blank.
  var _onScreen = 0;

  /// Inline mode: the region shrank to this many rows, and the rows below
  /// it are erased by the next frame; -1 for none.
  var _eraseFrom = -1;

  /// Inline mode: how many rows the terminal's screen has, 0 when unknown.
  /// Known, it lets the rows [commit] gives go in above the region while
  /// it moves down as it is (see [commit]).
  var screenHeight = 0;

  /// A fixed viewport: the surface is the part of this rectangle of the
  /// screen that the screen has, its first cell on column [Viewport.left]
  /// of row [Viewport.top], and no cell outside it is ever written, erased
  /// or moved. Cells are addressed with its offset; no erase reaches past
  /// it (no `ED`; `EL`, `ICH` and `DCH` only where it ends at the screen's
  /// right edge, see [screenWidth]); a scroll moves its own cells only
  /// (DECSTBM where it is as wide as the screen; a surface's own moves
  /// with DECSLRM margins otherwise, where the terminal has them; else
  /// none); and a glyph whose width terminals disagree on, which could
  /// reach past its right edge, is drawn as blanks. Between frames the
  /// screen is as its owner left it: a frame turns autowrap off while it
  /// draws and on again at its end, the first one saves the cursor
  /// (DECSC, SGR reset) and each that leaves it hidden puts it back
  /// (DECRC), as [leave] does. Null for the whole screen or an [inline]
  /// region.
  final Viewport? viewport;

  /// Fixed viewport: the screen column and row of the surface's first
  /// cell; 0 otherwise.
  final int _ox;
  final int _oy;

  /// Fixed viewport: how many columns the terminal's screen has. Unless
  /// the viewport ends at its right edge, erasing to the end of a row or
  /// shifting a row's tail would reach past it.
  var screenWidth = 0;

  /// Fixed viewport: the surface ends left of the screen's right edge, as
  /// of the last [present].
  var _shortOfEdge = false;

  /// Fixed viewport: the cursor is saved (DECSC) where the app found it;
  /// [leave] puts it back and the next frame saves it again.
  var _saved = false;

  /// Inline mode: rows committed for the next frame ([commit]), as wide as
  /// the region: cells, styles and their 64-bit views; and blank rows as
  /// many, what the terminal shows where they are written.
  var _pc = Uint32List(0);
  var _ps = Uint32List(0);
  var _pc64 = Uint64List(0);
  var _ps64 = Uint64List(0);
  var _committed = 0;
  var _blankCells = Uint32List(0);
  var _blankStyles = Uint32List(0);
  var _blankCells64 = Uint64List(0);
  var _blankStyles64 = Uint64List(0);

  /// The bytes of the last [present] or [leave], valid until the next
  /// call.
  final out = ByteSink();

  /// What the last [present] compared and wrote.
  final stats = PresentStats();

  // front buffer: what the terminal shows
  Uint32List _fc;
  Uint32List _fs;
  late Uint64List _fc64;
  late Uint64List _fs64;
  var _frontInvalid = true;

  /// DECAWM off was sent in a frame that was kept (set again after the
  /// screen is forgotten: something else may have turned it back on);
  /// never in a fixed viewport, whose frames turn it on again.
  var _autowrapOff = false;

  // terminal state model
  var _cx = -1; // -1 = unknown
  var _cy = -1;
  var _sgr = -1; // -1 = unknown
  // open hyperlink (OSC 8) on the terminal: link id, 0 none, -1 unknown.
  // Kept apart from _sgr because SGR 0 does not close a hyperlink.
  var _link = 0;

  /// Whether the cursor is shown when a frame ends, at [cursorX],
  /// [cursorY]; hidden by default.
  var cursorVisible = false;

  /// The column of the surface the visible cursor is put in.
  var cursorX = 0;

  /// The row of the surface the visible cursor is put in.
  var cursorY = 0;

  /// The row of the surface the terminal's cursor is on, shown or not, as
  /// what was written so far left it; -1 where that is not known (before
  /// the first frame, once the screen was forgotten). In the [inline]
  /// mode it is how a tool that sees the terminal's screen finds the
  /// region on it: its first row is that many rows above the cursor's.
  int get cursorRow => _cy;

  /// Shape of the visible cursor (a text field wants [CursorShape.bar]).
  CursorShape cursorShape = CursorShape.terminalDefault;
  CursorShape? _shapeSent = CursorShape.terminalDefault; // null: unknown
  var _cursorShown = true; // assume the terminal shows it until we hide it

  // declared scroll for the next frame
  var _scrollTop = 0;
  var _scrollBottom = 0;
  var _scrollBy = 0;

  // scroll detection: row hashes of the surface (_hb) and of the front
  // buffer (_hf). After a frame in which every row was hashed, the front
  // equals the surface, so _hb becomes next frame's _hf for free.
  var _hb = Int64List(0);
  var _hf = Int64List(0);
  var _hfValid = false;
  var _hashedThisFrame = false;
  var _usedRows = Uint8List(0);

  /// At most this many independently moved row blocks are scrolled in
  /// hardware per frame (auto-detection).
  var maxScrollBlocks = 4;

  /// Per row: 0, diffed over its damage; [_wholeRow], over all of it;
  /// [_damageRow], over its damage without a row shift (ICH/DCH).
  var _forceRow = Uint8List(0);
  static const _wholeRow = 1;
  static const _damageRow = 2;

  /// Per row of the last move [_widens] looked at: the span of the cells
  /// outside the rectangle that the shifted front has other than the
  /// surface (empty when lo >= hi).
  var _besideLo = Int32List(0);
  var _besideHi = Int32List(0);

  /// Rows the scroll pre-check found identical to the front buffer this
  /// frame (valid until the front changes): the diff skips them entirely.
  var _rowSame = Uint8List(0);

  /// The images on the terminal, as last drawn (see [_presentImages]).
  var _shown = <_Shown>[];

  /// kitty: the id of each image the terminal has or had last, and those
  /// it has (sent since the screen was last forgotten).
  final _kittyIds = Map<TerminalImage, int>.identity();
  final _kittySent = Set<TerminalImage>.identity();
  var _lastImageId = 0;
  var _lastPlacementId = 0;

  /// kitty on Konsole ([TerminalCaps.konsoleImages]): the ids of the
  /// images deleted, which Konsole keeps the data of until an image sent
  /// under the same id replaces it, for the next images.
  final _freeImageIds = <int>[];

  /// An id for a kitty image not sent yet: one of an image deleted on
  /// Konsole, else a new one.
  int _newImageId() =>
      _freeImageIds.isNotEmpty ? _freeImageIds.removeLast() : ++_lastImageId;

  /// kitty: [id] is deleted and no image of the presenter's has it; on
  /// Konsole the next image takes it.
  void _imageIdFreed(int id) {
    if (caps.konsoleImages) {
      _freeImageIds.add(id);
    }
  }

  /// The front buffer may have blanks under images ([_kUnder]).
  var _marked = false;

  /// Forget what the terminal shows, after something else wrote to it: the
  /// next frame rewrites every cell (with [TerminalCaps.clearFullFrames],
  /// after one `ED 2` inside the synchronized update, so nothing flashes)
  /// and sets the cursor visibility and shape again. In the [inline] mode
  /// the cursor must be on the row the presenter left it on: the region is
  /// found from it and repainted after an `ED 0` from its first row.
  void invalidate() {
    _forgetScreen();
    _cursorShown = true;
    _shapeSent = null;
  }

  /// The cells on screen are unknown (first frame, resize); the cursor
  /// state is still what was last sent.
  void _forgetScreen() {
    _autowrapOff = false;
    _marked = false;
    _hfValid = false;
    fillU32(_fc, 0, _fc.length, kInvalid);
    fillU32(_fs, 0, _fs.length, 0);
    _frontInvalid = true;
    _cx = -1;
    if (inline) {
      // the cursor stays on its line: the region is found from it
      _onScreen = _lineAbove ? 0 : 1;
      _eraseFrom = -1;
    } else {
      _cy = -1;
    }
    _sgr = -1;
    _link = -1;
  }

  /// Presents a surface [w] x [h] from the next frame on, after the
  /// terminal was resized: the cells it shows are forgotten, and the next
  /// frame writes every one. Inline rows
  /// committed and not written yet are cut or padded to the new width.
  void resize(int w, int h) {
    if (w != width && _committed > 0) {
      // committed rows not written yet: cut or padded to the new width
      final n = _committed;
      final cells = _pc;
      final styles = _ps;
      final old = width;
      width = w;
      _setCommitted(Uint32List(n * w), Uint32List(n * w));
      _copyRows(cells, styles, old, 0, n, 0);
    }
    width = w;
    height = h;
    _fc = Uint32List(w * h);
    _fs = Uint32List(w * h);
    _fc64 = view64(_fc);
    _fs64 = view64(_fs);
    _forgetScreen();
  }

  /// Declares that the content of rows [top, bottom) moved by [rows]
  /// (positive = up, like a log scrolling) since the last frame, for apps
  /// that repaint instead of moving rows with [Surface.scrollRows] (which
  /// records the move itself and takes precedence). Applied at the start of
  /// the next [present].
  void scrollRegion(int top, int bottom, int rows) {
    _scrollTop = top;
    _scrollBottom = bottom;
    _scrollBy = rows;
  }

  /// Renders the damage of [back] into [out]; returns the number of bytes.
  /// Clears the damage of [back].
  int present(Surface back) {
    out.reset();
    final st = stats
      ..bytes = 0
      ..cellsCompared = 0
      ..cellsWritten = 0
      ..scrolledRows = 0
      ..shiftedRows = 0
      ..scrollOps = 0
      ..rectScrollOps = 0
      ..widenedScrollOps = 0
      ..committedRows = 0
      ..images = 0;
    if (back.width != width || back.height != height) {
      if (inline && back.width == width) {
        _resizeRegion(back.height);
      } else {
        resize(back.width, back.height);
      }
      _scrollBy = 0;
    }
    final w = width;
    final h = height;
    if (viewport != null) {
      _shortOfEdge = _ox + w != screenWidth;
    }
    if (_forceRow.length < h) {
      _forceRow = Uint8List(h);
      _rowSame = Uint8List(h);
      _besideLo = Int32List(h);
      _besideHi = Int32List(h);
    }
    _fillFlags(_forceRow, 0, h, _frontInvalid ? _wholeRow : 0);
    _fillFlags(_rowSame, 0, h, 0);
    _hashedThisFrame = false;
    var touched = false; // any row diffed or scrolled this frame
    // the screen was forgotten: the images on it too
    final lost = _frontInvalid;

    final sync = caps.synchronizedOutput;
    if (sync) {
      out.ascii('\x1b[?2026h');
    }
    if (!_autowrapOff) {
      // Autowrap off: a glyph a terminal renders wider than we think can
      // then never wrap into the next row (or scroll the screen) - it is
      // clipped at the right edge. Restored by the backend on exit, or by
      // the frame's end in a fixed viewport.
      out.ascii('\x1b[?7l');
    }
    // a visible cursor jumping around while cells are drawn flickers
    final hidden = _cursorShown;
    if (hidden) {
      out.ascii('\x1b[?25l');
    }
    final bodyStart = out.length;

    // ---- full frame: the dominant background in one erase ----------------
    var cleared = false;
    if (inline) {
      final committed = _committed > 0;
      if (committed && !_insertsCommitted) {
        _printCommitted();
      }
      cleared = _placeRegion();
      if (_committed > 0) {
        _insertCommitted();
      }
      cleared = cleared || committed;
    } else if (viewport != null) {
      if (!_saved) {
        _saveCursor();
      }
    } else if (_frontInvalid && sync && caps.clearFullFrames) {
      final bg = _dominantBlank(back);
      if (bg >= 0) {
        _setStyle(bg);
        out.ascii('\x1b[2J');
        fillU32(_fc, 0, _fc.length, kBlank);
        fillU32(_fs, 0, _fs.length, bg);
        cleared = true;
      }
    }
    var rowsEmitted = 0;

    // ---- hardware scroll -----------------------------------------------
    final moves = back.pendingScrolls;
    if (moves.isNotEmpty) {
      // rows moved on the surface: replay the moves on the terminal, or
      // re-diff the moved rows when that isn't possible
      // Replay in order, checking each move against the terminal state the
      // previous replays produced. After the first move that can't be
      // replayed, every later move is re-diffed instead (rows a skipped move
      // left stale could otherwise flow into rows a later move shifts).
      var replaying = !_frontInvalid && caps.hardwareScroll;
      // a move widened to whole rows left rows to re-diff (_forceRow): a
      // later move carries their stale cells along its rows
      var widened = false;
      for (var k = 0; k < moves.length; k += 5) {
        final top = moves[k];
        final bottom = moves[k + 1];
        final by = moves[k + 2];
        final x0 = moves[k + 3];
        final x1 = moves[k + 4];
        if (replaying) {
          // DECSTBM scrolls the screen's whole rows
          final full = x0 == 0 && x1 == w && _wholeRows;
          // DECSTBM and DECSLRM both need at least two rows / columns
          if (bottom - top >= 2 &&
              (full ||
                  (!inline &&
                      caps.leftRightMargins &&
                      x1 - x0 >= 2 &&
                      !_cutsWideGlyph(top, bottom, x0, x1))) &&
              (_shown.isEmpty || !_scrollsImage(top, bottom, x0, x1))) {
            if (widened) {
              _carryForced(top, bottom);
            }
            if (full) {
              _hardwareScroll(top, bottom, by, forceRows: false);
            } else {
              _hardwareScrollRect(top, bottom, by, x0, x1);
            }
            continue;
          }
          if (_widens(back, top, bottom, by, x0, x1)) {
            if (widened) {
              _carryForced(top, bottom);
            }
            // the rows' cells outside [x0, x1) moved too: those that
            // differ are damage where no later move carries them along,
            // else the whole rows are re-diffed
            final last = k + 5 == moves.length;
            _hardwareScroll(top, bottom, by, forceRows: !last);
            if (last) {
              _damageBeside(back, top, bottom);
            }
            stats.widenedScrollOps++;
            widened = true;
            continue;
          }
          replaying = false;
        }
        _fillFlags(_forceRow, top, bottom, _wholeRow);
      }
    } else if (!_frontInvalid && caps.hardwareScroll && _wholeRows) {
      if (_scrollBy != 0) {
        final top = _scrollTop < 0 ? 0 : _scrollTop;
        final bottom = _scrollBottom > h ? h : _scrollBottom;
        final n = _scrollBy.abs();
        if (bottom - top >= 2 &&
            n < bottom - top &&
            (_shown.isEmpty || !_scrollsImage(top, bottom, 0, w))) {
          _hardwareScroll(top, bottom, _scrollBy);
        }
      } else if (autoScroll) {
        _detectScroll(back);
      }
    }
    _scrollBy = 0;

    // ---- images ------------------------------------------------------------
    var imagesWritten = false;
    if (back.images.isNotEmpty || _shown.isNotEmpty) {
      final before = out.length;
      _presentImages(back, lost: lost);
      imagesWritten = out.length > before;
    }

    // ---- rows ------------------------------------------------------------
    final bc = back.cells;
    final bs = back.styles;
    final fc = _fc;
    final fs = _fs;
    // ICH/DCH move the cells up to the screen's right edge
    final shifts = caps.insertDelete && !_shortOfEdge;
    // in locals: the fields would be loaded again for every row
    final forceRow = _forceRow;
    final rowSame = _rowSame;
    final dirtyLo = back.dirtyLo;
    final dirtyHi = back.dirtyHi;
    for (var y = 0; y < h; y++) {
      int lo;
      int hi;
      if (forceRow[y] == _wholeRow) {
        lo = 0;
        hi = w;
      } else {
        lo = dirtyLo[y];
        hi = dirtyHi[y];
        if (lo >= hi || rowSame[y] != 0) {
          continue;
        }
        if (lo < 0) {
          lo = 0;
        }
        if (hi > w) {
          hi = w;
        }
      }
      final row = y * w;
      if (lo > 0 &&
          ((bc[row + lo] & kCont) != 0 || (fc[row + lo] & kCont) != 0)) {
        lo--;
      }
      if (hi < w &&
          ((bc[row + hi] & kCont) != 0 || (fc[row + hi] & kCont) != 0)) {
        hi++;
      }
      touched = true;
      final before = out.length;
      if (shifts && forceRow[y] == 0 && hi - lo >= 6) {
        // the whole tail moved on the terminal: diff (and commit) up to the
        // row end; keep lo, so the front stays an exact copy of the surface
        if (_tryRowShift(bc, bs, back.cells64, back.styles64, y, lo, hi) >= 0) {
          hi = w;
        }
      }
      _diffRow(bc, bs, back.cells64, back.styles64, y, lo, hi);
      if (out.length > before) {
        rowsEmitted++;
      }
      fc.setRange(row + lo, row + hi, bc, row + lo);
      fs.setRange(row + lo, row + hi, bs, row + lo);
    }
    if (_shown.isNotEmpty) {
      _markUnder(back);
    } else if (_marked) {
      _unmark();
    }
    back.clearDamage();
    _frontInvalid = false;
    if (_hashedThisFrame) {
      // the front now equals the surface whose rows were just hashed
      final t = _hf;
      _hf = _hb;
      _hb = t;
      _hfValid = true;
    } else if (touched || stats.scrolledRows > 0) {
      _hfValid = false;
    }
    if (_marked) {
      _hfValid = false; // the blanks under images aren't reserved cells
    }
    assert(
      !_hfValid || _frontHashesCorrect(),
      'cached front row hashes must match the front buffer',
    );

    // ---- cursor ------------------------------------------------------------
    final bodyChanged = out.length > bodyStart;
    var cursorChanged = false;
    // an empty screen has no cell to show the cursor on
    if (cursorVisible && w > 0 && h > 0) {
      final cx = cursorX.clamp(0, w - 1);
      final cy = cursorY.clamp(0, h - 1);
      if (bodyChanged ||
          !_cursorShown ||
          _cx != cx ||
          _cy != cy ||
          cursorShape != _shapeSent) {
        // nothing drawn: the shown cursor jumps once, so hiding it around
        // the move prevents no flicker
        final keepShown = hidden && !bodyChanged;
        if (keepShown) {
          out.length -= 6; // the prefix's ESC [ ? 2 5 l
        }
        _moveTo(cx, cy);
        if (cursorShape != _shapeSent) {
          out
            ..csi(cursorShape.code, 0x20) // CSI n SP q
            ..byte(0x71);
          _shapeSent = cursorShape;
        }
        if (!keepShown) {
          out.ascii('\x1b[?25h');
        }
        _cursorShown = true;
        cursorChanged = true;
      }
    } else if (_cursorShown) {
      _cursorShown = false; // hidden by the prefix
      cursorChanged = true;
    }

    if (!bodyChanged && !cursorChanged) {
      // idle frame: not a single byte, mode prefixes included (they count
      // as not sent)
      out.length = 0;
    } else if (viewport == null) {
      _autowrapOff = true;
    } else {
      _endViewportFrame();
    }
    if (out.length > 0 && sync) {
      if (rowsEmitted <= 1 &&
          !cleared &&
          !imagesWritten &&
          stats.scrolledRows == 0 &&
          out.length - bodyStart <= 64) {
        // a change within one row can't tear: skip the 2026 wrapper
        out.removePrefix(8); // ESC [ ? 2 0 2 6 h
      } else {
        out.ascii('\x1b[?2026l');
      }
    }
    st.bytes = out.length;
    return out.length;
  }

  // -------------------------------------------------------------- viewport --

  /// The surface's rows are whole rows of the screen, which DECSTBM
  /// scrolls: always but in a fixed viewport narrower than the screen.
  bool get _wholeRows => _ox == 0 && !_shortOfEdge;

  /// Fixed viewport: saves the cursor where it is (DECSC), with SGR reset
  /// and no hyperlink open, so that putting it back ([_restoreCursor])
  /// leaves both so whether or not the terminal saves them.
  void _saveCursor() {
    if (_sgr != 0 || _link != 0) {
      _resetSgr();
    }
    out
      ..byte(0x1B)
      ..byte(0x37); // DECSC
    _saved = true;
  }

  /// Fixed viewport: ends a frame that wrote anything: autowrap on again
  /// and, unless it is shown, the cursor put back ([_restoreCursor]).
  void _endViewportFrame() {
    out.ascii('\x1b[?7h');
    if (!_cursorShown) {
      _restoreCursor();
    }
  }

  /// Fixed viewport: puts the cursor back where [_saveCursor] found it
  /// (DECRC).
  void _restoreCursor() {
    if (_sgr != 0 || _link != 0) {
      _resetSgr();
    }
    out
      ..byte(0x1B)
      ..byte(0x38); // DECRC
    _cx = _cy = -1;
  }

  /// Fixed viewport: [leave] once a frame saved the cursor.
  void _leaveViewport({required bool clear}) {
    if (_sgr != 0 || _link != 0) {
      _resetSgr();
    }
    if (clear && width > 0) {
      final edge = _ox + width == screenWidth;
      for (var y = 0; y < height; y++) {
        _moveTo(0, y);
        if (edge) {
          out.ascii('\x1b[K');
        } else {
          out.csi(width, 0x58); // ECH
        }
      }
    }
    _restoreCursor();
    _saved = false;
  }

  /// Fixed viewport: draws glyph [c] at column [x], which a terminal might
  /// draw past the right edge, as blanks of its style [s] instead.
  @pragma('vm:never-inline')
  int _emitBlanks(int c, int s, int x) {
    _setStyleFor(kBlank, s);
    final adv = (c & kWide) != 0 ? 2 : 1;
    for (var k = 0; k < adv; k++) {
      out.byte(0x20);
    }
    stats.cellsWritten++;
    _cx = x + adv >= width ? -1 : x + adv;
    return adv;
  }

  // ---------------------------------------------------------------- inline --

  /// Inline mode: the region becomes [h] rows tall. The rows it keeps keep
  /// what the terminal shows, the rows it gains are blank there (the screen
  /// below the region always is), the rows it loses are erased by
  /// [_placeRegion].
  void _resizeRegion(int h) {
    final w = width;
    final keep = (h < height ? h : height) * w;
    final fc = Uint32List(w * h)..setRange(0, keep, _fc);
    final fs = Uint32List(w * h)..setRange(0, keep, _fs);
    fillU32(fc, keep, fc.length, kBlank);
    if (h < height) {
      _eraseFrom = h;
    }
    height = h;
    _fc = fc;
    _fs = fs;
    _fc64 = view64(fc);
    _fs64 = view64(fs);
    _hfValid = false;
  }

  /// Inline mode, before the rows are diffed: erases what has to go (from
  /// the region's first row on a full frame, below its last row after it
  /// shrank) and makes room for every row of the region. Returns whether
  /// anything was written.
  bool _placeRegion() {
    final start = out.length;
    if (_frontInvalid || _eraseFrom >= 0 || _onScreen < height) {
      // erased cells and lines scrolled in take the current background
      if (_sgr != 0 || _link != 0) {
        _resetSgr();
      }
    }
    if (_frontInvalid) {
      if (_lineAbove) {
        out.byte(0x0A);
        _lineAbove = false;
        _cy = 0;
      } else {
        _moveTo(0, 0);
      }
      out.ascii('\x1b[J');
      _onScreen = 1;
      _entered = true;
      fillU32(_fc, 0, _fc.length, kBlank);
      fillU32(_fs, 0, _fs.length, 0);
    } else if (_eraseFrom >= 0) {
      _moveTo(0, _eraseFrom);
      out.ascii('\x1b[J');
    }
    _eraseFrom = -1;
    if (_onScreen < height) {
      // line feeds below the lowest row on the screen: once the region
      // reaches the bottom, the screen scrolls its history up
      _moveToRow(_onScreen - 1);
      for (var y = _onScreen; y < height; y++) {
        out.byte(0x0A);
      }
      _cy = height - 1;
      _cx = -1; // a tty that turns LF into CR LF moves it to column 0
      _onScreen = height;
    }
    return out.length > start;
  }

  /// Inline mode: the bytes that hand the screen back when the app ends:
  /// the region stays as it is and the cursor goes to the start of the line
  /// below it, or with [clear] the region is erased and the cursor goes to
  /// its first row. SGR is reset either way. A fixed viewport likewise
  /// stays, or with [clear] is erased, and the cursor goes back where the
  /// first frame found it (the next frame saves it again). Returns the
  /// number of bytes in [out]: in the fullscreen mode (the alternate
  /// screen is left) only those that delete the kitty images, as with
  /// [clear]; none before the first frame.
  int leave({bool clear = false}) {
    out.reset();
    final fixed = viewport != null;
    if ((!inline && !fixed) || clear) {
      _freeImages();
    }
    if (fixed) {
      if (_saved) {
        _leaveViewport(clear: clear);
      }
      return out.length;
    }
    if (!inline || !_entered) {
      return out.length;
    }
    if (_sgr != 0 || _link != 0) {
      _resetSgr();
    }
    if (clear || height == 0) {
      _moveTo(0, 0);
      if (clear) {
        out.ascii('\x1b[J');
      }
    } else {
      _moveTo(0, height - 1);
      out.byte(0x0A);
      _cy = height;
    }
    return out.length;
  }

  /// Inline mode: rows [from, to) of [rows] (to its last by default) go to
  /// the terminal's history: the next [present] writes them above the
  /// region, in its synchronized update, and nothing writes them again;
  /// they are the terminal's own lines, which its scrollback and selection
  /// work on. Rows of several calls before a frame go in the order given.
  ///
  /// With [screenHeight] known they go in at the region's first row with
  /// `IL`, after line feeds below its last row made room, so the region
  /// moves down as it is; as many at a time as the screen has rows besides
  /// the region's. Otherwise (and on a full frame, or without
  /// [TerminalCaps.hardwareScroll]) they are printed from the region's
  /// first row down after an `ED 0`, and the region is drawn again on the
  /// line after them. Either way the screen scrolls its history up into
  /// the scrollback as rows reach its bottom, and no row is addressed
  /// absolutely.
  ///
  /// The cells are copied. A row wider than the region is cut (a wide
  /// glyph across the edge is left out) and a narrower one padded with
  /// blanks, as are rows still waiting when the width changes ([resize]).
  void commit(Surface rows, [int from = 0, int? to]) {
    if (!inline) {
      throw StateError('only an inline region commits rows to the history');
    }
    final end = RangeError.checkValidRange(from, to, rows.height);
    final n = end - from;
    if (n == 0) {
      return;
    }
    final w = width;
    final need = (_committed + n) * w;
    if (_pc.length < need) {
      final cap = need > _pc.length * 2 ? need : _pc.length * 2;
      _setCommitted(
        Uint32List(cap)..setRange(0, _committed * w, _pc),
        Uint32List(cap)..setRange(0, _committed * w, _ps),
      );
    }
    _copyRows(rows.cells, rows.styles, rows.width, from, n, _committed);
    _committed += n;
  }

  void _setCommitted(Uint32List cells, Uint32List styles) {
    _pc = cells;
    _ps = styles;
    _pc64 = view64(cells);
    _ps64 = view64(styles);
  }

  /// Copies [n] rows, from row [from] of [cells] and [styles] ([srcW] cells
  /// wide), to the committed rows from row [to]: cut or padded with blanks
  /// to the region's width; a wide glyph the cut goes through is a blank.
  void _copyRows(
    Uint32List cells,
    Uint32List styles,
    int srcW,
    int from,
    int n,
    int to,
  ) {
    final w = width;
    final k = srcW < w ? srcW : w;
    final pc = _pc;
    final ps = _ps;
    for (var r = 0; r < n; r++) {
      final a = (from + r) * srcW;
      final b = (to + r) * w;
      pc.setRange(b, b + k, cells, a);
      ps.setRange(b, b + k, styles, a);
      if (k < w) {
        fillU32(pc, b + k, b + w, kBlank);
        fillU32(ps, b + k, b + w, 0);
      } else if (k > 0 && k < srcW && (pc[b + k - 1] & kWide) != 0) {
        pc[b + k - 1] = kBlank;
      }
    }
  }

  /// Inline mode: committed rows go in with `IL` (see [commit]).
  bool get _insertsCommitted =>
      !_frontInvalid &&
      caps.hardwareScroll &&
      height > 0 &&
      screenHeight > height;

  /// Inline mode, before the region is placed: writes the committed rows
  /// from the region's first row down, after erasing it, with a line feed
  /// after each; the region then starts on the line after them and is
  /// drawn again in full.
  @pragma('vm:never-inline')
  void _printCommitted() {
    if (_sgr != 0 || _link != 0) {
      _resetSgr();
    }
    if (_lineAbove) {
      out.byte(0x0A);
      _lineAbove = false;
      _cy = 0;
      _cx = -1;
    } else {
      _moveTo(0, 0);
    }
    out.ascii('\x1b[J');
    final n = _committed;
    _writeCommitted(0, n, lineFeeds: true);
    _moveToRow(n - 1);
    _lineFeed();
    _cy = 0;
    _committed = 0;
    _frontInvalid = true;
    _hfValid = false;
    _fillFlags(_forceRow, 0, height, _wholeRow);
    _imagesMoved(0, height, 0, width);
  }

  /// Inline mode, after the region is placed: puts the committed rows in
  /// above it while it moves down as it is. Line feeds below its last row
  /// make room, an `IL` at its first row pushes it down into that room,
  /// and the rows are written on the lines it left; as many at a time as
  /// the screen has rows besides the region's (more line feeds would push
  /// the region itself into the scrollback).
  @pragma('vm:never-inline')
  void _insertCommitted() {
    final h = height;
    final room = screenHeight - h;
    final n = _committed;
    for (var i = 0; i < n;) {
      final k = n - i < room ? n - i : room;
      if (_sgr != 0 || _link != 0) {
        _resetSgr(); // lines scrolled or inserted take the background
      }
      _moveToRow(h - 1);
      for (var j = 0; j < k; j++) {
        out.byte(0x0A);
      }
      _cy = h - 1 + k;
      _cx = -1;
      _moveToRow(0);
      _csiCount(k, 0x4C); // IL
      _cx = -1;
      // the cursor's row is committed row i, the region's first is i + k
      _cy = i;
      _writeCommitted(i, i + k, lineFeeds: false);
      _moveToRow(i + k);
      _cy = 0;
      // the rows on the screen are counted from the region's new first row
      _onScreen = _onScreen - k > h ? _onScreen - k : h;
      i += k;
    }
    _committed = 0;
    _imagesMoved(0, h, 0, width);
  }

  /// Writes committed rows [from, to) on the cursor's rows of the same
  /// numbers, each as a diff against a blank row (what the terminal shows
  /// there). With [lineFeeds] a line feed takes the cursor from one row to
  /// the next, which may not be on the screen yet; otherwise all of them
  /// are.
  void _writeCommitted(int from, int to, {required bool lineFeeds}) {
    final w = width;
    if (_blankCells.length < to * w) {
      _blankCells = Uint32List(to * w);
      fillU32(_blankCells, 0, to * w, kBlank);
      _blankStyles = Uint32List(to * w);
      _blankCells64 = view64(_blankCells);
      _blankStyles64 = view64(_blankStyles);
    }
    final fc = _fc;
    final fs = _fs;
    final fc64 = _fc64;
    final fs64 = _fs64;
    _fc = _blankCells;
    _fs = _blankStyles;
    _fc64 = _blankCells64;
    _fs64 = _blankStyles64;
    for (var y = from; y < to; y++) {
      if (lineFeeds && y > from) {
        _moveToRow(y - 1);
        _lineFeed();
      }
      _diffRow(_pc, _ps, _pc64, _ps64, y, 0, w);
    }
    _fc = fc;
    _fs = fs;
    _fc64 = fc64;
    _fs64 = fs64;
    stats.committedRows += to - from;
  }

  /// Inline mode: a line feed takes the cursor to the next row, the screen
  /// scrolling its history up when it was on the last; SGR is reset first,
  /// since a line scrolled in takes the current background.
  void _lineFeed() {
    if (_sgr != 0 || _link != 0) {
      _resetSgr();
    }
    out.byte(0x0A);
    _cy++;
    _cx = -1; // a tty that turns LF into CR LF moves it to column 0
  }

  // ---------------------------------------------------------------- images --

  /// Draws the images of [back] that the terminal doesn't show as they are
  /// ([Surface.images], after those whose cells were drawn over are
  /// dropped), over blanks in the styles of their cells, and takes away
  /// those it shows that [back] has no more. kitty places an image it has
  /// again by its placement id, which a move or a scroll takes; it is sent
  /// again only after the screen was forgotten ([lost]), and deleted from
  /// the terminal once no placement shows it. A sixel or iTerm2 image is
  /// sent again whenever it is drawn, after its cells are erased; one that
  /// goes is written over by the rows. An image the terminal can't show
  /// (another protocol, or sixel and iTerm2 cut by a clip) leaves its cells
  /// blank.
  @pragma('vm:never-inline')
  void _presentImages(Surface back, {required bool lost}) {
    final want = back.images;
    for (var i = want.length - 1; i >= 0; i--) {
      if (!_reservedStill(back, want[i])) {
        want.removeAt(i);
      }
    }
    final shown = _shown;
    if (lost) {
      _kittySent.clear();
    }
    for (final s in shown) {
      s
        ..kept = false
        ..moved = s.moved || lost;
    }
    final next = <_Shown>[];
    final draw = <ImagePlacement>[];
    for (final p in want) {
      final same = _restyled(back, p)
          ? -1
          : shown.indexWhere((s) => !s.kept && !s.moved && s.at.sameAs(p));
      if (same >= 0) {
        next.add(shown[same]..kept = true);
      } else {
        draw.add(p);
      }
    }
    final graphics = caps.graphics;
    final multiplexer = caps.graphicsMultiplexer;
    final kitty = graphics == GraphicsProtocol.kitty;
    final can = [
      for (final p in draw)
        p.image.protocol == graphics &&
            switch (graphics) {
              GraphicsProtocol.none => false,
              GraphicsProtocol.kitty =>
                p.whole ||
                    (p.image.pixelWidth >= p.cols &&
                        p.image.pixelHeight >= p.rows),
              GraphicsProtocol.sixel || GraphicsProtocol.iterm2 => p.whole,
            },
    ];
    // kitty: a placement of an image that moved is placed again
    final placements = List<int>.filled(draw.length, 0);
    if (kitty) {
      for (var k = 0; k < draw.length; k++) {
        final image = draw[k].image;
        final i = can[k]
            ? shown.indexWhere(
                (s) => !s.kept && s.drawn && identical(s.at.image, image),
              )
            : -1;
        if (i >= 0) {
          shown[i].kept = true;
          placements[k] = shown[i].placement;
        }
      }
      // those that go, and the images no placement shows any more
      bool used(TerminalImage image) {
        for (final n in next) {
          if (n.drawn && identical(n.at.image, image)) {
            return true;
          }
        }
        for (var k = 0; k < draw.length; k++) {
          if (can[k] && identical(draw[k].image, image)) {
            return true;
          }
        }
        return false;
      }

      for (final s in shown) {
        final image = s.at.image;
        final id = _kittyIds[image];
        if (s.kept || !s.drawn || id == null) {
          continue; // an id gone with another placement of the image
        }
        if (used(image)) {
          kittyDelete(
            out,
            id: id,
            placement: s.placement,
            multiplexer: multiplexer,
          );
        } else {
          kittyDelete(out, id: id, multiplexer: multiplexer);
          _kittyIds.remove(image);
          _kittySent.remove(image);
          _imageIdFreed(id);
        }
      }
    }
    for (var k = 0; k < draw.length; k++) {
      final p = draw[k];
      final image = p.image;
      // the cells of a sixel or iTerm2 image hold its pixels
      _blankUnder(back, p, all: !kitty);
      var placement = 0;
      if (can[k]) {
        _moveTo(p.left, p.top);
        switch (graphics) {
          case GraphicsProtocol.kitty:
            placement = placements[k] == 0 ? ++_lastPlacementId : placements[k];
            kittyPlace(
              out,
              p,
              id: _kittyIds[image] ??= _newImageId(),
              placement: placement,
              transmit: _kittySent.add(image),
              multiplexer: multiplexer,
            );
          case GraphicsProtocol.sixel:
            sixelDraw(out, p, multiplexer: multiplexer);
          case GraphicsProtocol.iterm2:
            iterm2Draw(out, p, multiplexer: multiplexer);
          case GraphicsProtocol.none:
        }
        stats.images++;
      }
      next.add(
        _Shown(
          ImagePlacement(
            image,
            p.x,
            p.y,
            p.cols,
            p.rows,
            p.left,
            p.top,
            p.right,
            p.bottom,
          ),
          placement,
          drawn: can[k],
        ),
      );
    }
    _shown = next;
  }

  /// Whether every cell [p] shows is still reserved: those of the rows
  /// damaged since the last frame are looked at.
  static bool _reservedStill(Surface back, ImagePlacement p) {
    final w = back.width;
    final cells = back.cells;
    for (var y = p.top; y < p.bottom; y++) {
      final lo = back.dirtyLo[y] > p.left ? back.dirtyLo[y] : p.left;
      final hi = back.dirtyHi[y] < p.right ? back.dirtyHi[y] : p.right;
      for (var i = y * w + lo; i < y * w + hi; i++) {
        if ((cells[i] & kSkip) == 0) {
          return false;
        }
      }
    }
    return true;
  }

  /// Whether a cell [p] shows has a blank of another look in [back] than
  /// the one the image was drawn over (the cells under an image moved
  /// there, still reserved): those of the rows damaged since the last
  /// frame are looked at.
  bool _restyled(Surface back, ImagePlacement p) {
    final w = width;
    final bs = back.styles;
    final fs = _fs;
    for (var y = p.top; y < p.bottom; y++) {
      final lo = back.dirtyLo[y] > p.left ? back.dirtyLo[y] : p.left;
      final hi = back.dirtyHi[y] < p.right ? back.dirtyHi[y] : p.right;
      for (var i = y * w + lo; i < y * w + hi; i++) {
        if (bs[i] != fs[i] &&
            styles.blankStyleOf(bs[i]) != styles.blankStyleOf(fs[i])) {
          return true;
        }
      }
    }
    return false;
  }

  /// Erases the cells [p] shows, in their styles in [back]: all of them
  /// with [all], otherwise those the front buffer doesn't have as blanks of
  /// the same look already; the front buffer then has them as blanks under
  /// an image.
  void _blankUnder(Surface back, ImagePlacement p, {required bool all}) {
    final w = width;
    final bs = back.styles;
    final fc = _fc;
    final fs = _fs;
    // a blank of the same look is there already (under an image, or
    // erased by a full frame)
    bool under(int i) =>
        !all &&
        (fc[i] == _kUnder || fc[i] == kBlank) &&
        styles.blankStyleOf(fs[i]) == styles.blankStyleOf(bs[i]);
    for (var y = p.top; y < p.bottom; y++) {
      final row = y * w;
      var x = p.left;
      while (x < p.right) {
        if (under(row + x)) {
          fc[row + x] = _kUnder; // a row shift must not move it
          fs[row + x] = bs[row + x];
          x++;
          continue;
        }
        final s = bs[row + x];
        final blank = styles.blankStyleOf(s);
        var end = x + 1;
        while (end < p.right &&
            !under(row + end) &&
            styles.blankStyleOf(bs[row + end]) == blank) {
          end++;
        }
        _moveTo(x, y);
        _setStyleFor(kBlank, s);
        if (styles.erasable(blank) &&
            (caps.backgroundColorErase || styles.bgOf(blank).isDefault)) {
          if (end == w && !_shortOfEdge) {
            out.ascii('\x1b[K');
          } else {
            out.csi(end - x, 0x58); // ECH
          }
        } else {
          for (var k = x; k < end; k++) {
            out.byte(0x20);
          }
          _cx = end >= w ? -1 : end;
        }
        stats.cellsWritten += end - x;
        fillU32(fc, row + x, row + end, _kUnder);
        fs.setRange(row + x, row + end, bs, row + x);
        _marked = true;
        x = end;
      }
    }
  }

  /// The cells of the images the terminal shows are blanks under them in
  /// the front buffer again, where the rows copied the reserved cells over
  /// them.
  @pragma('vm:never-inline')
  void _markUnder(Surface back) {
    final w = width;
    final bs = back.styles;
    final fc = _fc;
    final fs = _fs;
    for (final s in _shown) {
      final p = s.at;
      for (var y = p.top; y < p.bottom; y++) {
        for (var i = y * w + p.left; i < y * w + p.right; i++) {
          if (fc[i] != _kUnder) {
            fc[i] = _kUnder;
            fs[i] = bs[i];
          }
        }
      }
    }
    _marked = true;
  }

  /// No image is shown any more: the blanks left under them are reserved
  /// cells in the front buffer again, as on the surface.
  @pragma('vm:never-inline')
  void _unmark() {
    final fc = _fc;
    for (var i = 0; i < fc.length; i++) {
      if (fc[i] == _kUnder) {
        fc[i] = kSkip;
      }
    }
    _marked = false;
  }

  /// Whether a sixel or iTerm2 image the terminal shows has cells in rows
  /// [top, bottom) of columns [x0, x1): those are not scrolled in hardware
  /// (where a terminal takes the pixels of a scroll region is not known)
  /// but rewritten, and the image is sent again where it went. On Konsole
  /// ([TerminalCaps.konsoleImages]), which moves its images up on any
  /// scroll up, any image it shows.
  @pragma('vm:never-inline')
  bool _scrollsImage(int top, int bottom, int x0, int x1) {
    if (caps.graphics == GraphicsProtocol.kitty) {
      return false;
    }
    final all = caps.konsoleImages;
    for (final s in _shown) {
      final p = s.at;
      if (s.drawn && all) {
        return true;
      }
      if (s.drawn &&
          p.left < x1 &&
          x0 < p.right &&
          p.top < bottom &&
          top < p.bottom) {
        return true;
      }
    }
    return false;
  }

  /// The images the terminal shows in rows [top, bottom) of columns
  /// [x0, x1) may have moved with a scroll, or gone: kitty places them
  /// again. On Konsole ([TerminalCaps.konsoleImages]) all of them, which
  /// a scroll up moves wherever they are.
  @pragma('vm:never-inline')
  void _imagesMoved(int top, int bottom, int x0, int x1) {
    final all = caps.konsoleImages;
    for (final s in _shown) {
      final p = s.at;
      if (all ||
          (p.left < x1 && x0 < p.right && p.top < bottom && top < p.bottom)) {
        s.moved = true;
      }
    }
  }

  /// Deletes the kitty images from the terminal; it shows none from now
  /// on.
  void _freeImages() {
    for (final id in _kittyIds.values) {
      kittyDelete(out, id: id, multiplexer: caps.graphicsMultiplexer);
      _imageIdFreed(id);
    }
    _kittyIds.clear();
    _kittySent.clear();
    _shown = [];
  }

  // ------------------------------------------------------------------ rows --

  void _diffRow(
    Uint32List bc,
    Uint32List bs,
    Uint64List bc64,
    Uint64List bs64,
    int y,
    int lo,
    int hi,
  ) {
    final w = width;
    final row = y * w;
    final fc = _fc;
    final fs = _fs;
    final fc64 = _fc64;
    final fs64 = _fs64;
    final st = stats;
    final bce = caps.backgroundColorErase;
    final rep = caps.repeatChar;
    var lastWritten = -2; // column of the last cell written in this row
    // cells before this column must be rewritten even if unchanged: an
    // uncertain glyph may have overflowed into them
    var forceUntil = -1;
    var x = lo;
    st.cellsCompared += hi - lo;
    while (x < hi || x < forceUntil) {
      if (x >= w) {
        break;
      }
      // fast skip over identical cells (the common case), two cells per
      // comparison through the 64-bit views
      if (x >= forceUntil) {
        var i = row + x;
        final end = row + hi;
        if ((i & 1) == 1 && i < end && bc[i] == fc[i] && bs[i] == fs[i]) {
          i++;
        }
        if ((i & 1) == 0) {
          final lim = end & ~1;
          while (i < lim &&
              bc64[i >> 1] == fc64[i >> 1] &&
              bs64[i >> 1] == fs64[i >> 1]) {
            i += 2;
          }
        }
        while (i < end && bc[i] == fc[i] && bs[i] == fs[i]) {
          i++;
        }
        x = i - row;
        if (x >= hi) {
          break;
        }
      }
      final i = row + x;
      final c = bc[i];
      if ((c & kSkip) != 0) {
        x++;
        continue;
      }
      if ((c & kCont) != 0) {
        // the leading half paints this cell; make sure it was written
        if ((c != fc[i] || bs[i] != fs[i]) && lastWritten != x - 1 && x > 0) {
          _emit(bc, bs, y, x - 1);
          lastWritten = x - 1;
        }
        x++;
        continue;
      }
      final s = bs[i];
      if (c == fc[i] && x >= forceUntil) {
        final f = fs[i];
        if (s == f) {
          x++;
          continue;
        }
        if (c == kBlank) {
          final b = styles.blankStyleOf(s);
          if (b == styles.blankStyleOf(f)) {
            // a blank that looks the same on the terminal, and the blanks
            // after it that do: while their styles are the same as this
            // one's on either side, without looking a blank style up
            var j = i + 1;
            final end = row + hi;
            while (j < end && bc[j] == kBlank && fc[j] == kBlank) {
              final t = bs[j];
              final u = fs[j];
              if ((t != s && styles.blankStyleOf(t) != b) ||
                  (u != f && styles.blankStyleOf(u) != b)) {
                break;
              }
              j++;
            }
            x = j - row;
            continue;
          }
        }
      }

      // ---- erase a run of blanks with EL / ECH ---------------------------
      final blank = c == kBlank ? styles.blankStyleOf(s) : -1;
      if (blank >= 0 &&
          styles.erasable(blank) &&
          (bce || styles.bgOf(blank).isDefault)) {
        var end = x + 1;
        while (end < w &&
            bc[row + end] == kBlank &&
            styles.blankStyleOf(bs[row + end]) == blank) {
          end++;
        }
        final n = end - x;
        if (end == w && n >= 4) {
          _moveTo(x, y);
          _setStyleFor(kBlank, s);
          if (_shortOfEdge) {
            out.csi(n, 0x58); // ECH: EL would erase past the viewport
          } else {
            out.ascii('\x1b[K');
          }
          st.cellsWritten += n;
          lastWritten = w - 1;
          x = w;
          continue;
        }
        if (n >= 12) {
          _moveTo(x, y);
          _setStyleFor(kBlank, _blankPen(bc, bs, row, x, hi, s));
          out.csi(n, 0x58); // ECH
          st.cellsWritten += n;
          lastWritten = end - 1;
          x = end;
          continue;
        }
      }

      _bridge(bc, bs, row, x, y);
      _moveTo(x, y);
      final adv = _emitHere(
        c,
        c == kBlank ? _blankPen(bc, bs, row, x, hi, s) : s,
        x,
        y,
      );
      lastWritten = x;
      if (rep && c < kFirstInterned && c >= 0x20) {
        // c is a plain single-code-point narrow glyph (no flags): repeat it
        var k = 0;
        while (x + 1 + k < hi &&
            bc[row + x + 1 + k] == c &&
            bs[row + x + 1 + k] == s) {
          k++;
        }
        if (k > 0 && _utf8Length(c) * k > 3 + decimalDigits(k)) {
          out.csi(k, 0x62); // REP
          stats.cellsWritten += k;
          x += k;
          lastWritten = x;
          _cx = x + 1 >= width ? -1 : x + 1;
        }
      }
      if ((c & kUncertain) != 0) {
        final reach = x + glyphs.maxWidthOf(c);
        if (reach > forceUntil) {
          forceUntil = reach;
        }
      }
      x += adv;

      // ---- the changed cells after it, written in a run ------------------
      // With the cursor after the cell and the SGR state its style, what
      // the loop does for each next cell in that style is a plain narrow
      // glyph's bytes and the count, without a cursor move or SGR; the run
      // ends at a cell the loop would treat otherwise: not a plain glyph in
      // that style, unchanged (skipped), a blank that may start an erase,
      // or a cell REP may repeat.
      if (_cx == x && _cy == y && _sgr == s && x < hi && x >= forceUntil) {
        final o = out..reserve(4 * (hi - x));
        final start = row + x;
        final end = row + hi;
        final rowEnd = row + w;
        var j = start;
        while (j < end) {
          final cj = bc[j];
          if (cj >= kFirstInterned || bs[j] != s) {
            break;
          }
          if (cj == kBlank) {
            if (j + 1 < rowEnd && bc[j + 1] == kBlank) {
              break;
            }
            if (fc[j] == kBlank &&
                (fs[j] == s ||
                    styles.blankStyleOf(fs[j]) == styles.blankStyleOf(s))) {
              break;
            }
          } else if (cj == fc[j] && fs[j] == s) {
            break;
          }
          if (rep && j + 1 < end && bc[j + 1] == cj && bs[j + 1] == s) {
            break;
          }
          o.codePointReserved(cj);
          j++;
        }
        if (j > start) {
          st.cellsWritten += j - start;
          x += j - start;
          lastWritten = x - 1;
          _cx = x >= w ? -1 : x;
        }
      }
    }
  }

  /// If the cursor is a few columns left of [x] on row [y] and the cells in
  /// between are plain ASCII drawn in the current SGR state, rewriting them
  /// (1 byte each) is shorter than a cursor move (`ESC [ n C`, 4+ bytes).
  /// Those cells are unchanged, so rewriting them is harmless.
  @pragma('vm:prefer-inline')
  void _bridge(Uint32List bc, Uint32List bs, int row, int x, int y) {
    final from = _cx;
    if (_cy != y || from < 0 || x - from <= 0 || x - from > 3) {
      return;
    }
    for (var j = from; j < x; j++) {
      final c = bc[row + j];
      if (c < 0x20 || c >= 0x7F) {
        return;
      } // also excludes every flagged cell
      final s = bs[row + j];
      if (s != _sgr &&
          !(c == kBlank &&
              _sgr >= 0 &&
              styles.blankStyleOf(s) == styles.blankStyleOf(_sgr))) {
        return;
      }
    }
    for (var j = from; j < x; j++) {
      out.byte(bc[row + j]);
    }
    _cx = x;
  }

  @pragma('vm:prefer-inline')
  static int _utf8Length(int cp) =>
      cp < 0x80 ? 1 : (cp < 0x800 ? 2 : (cp < 0x10000 ? 3 : 4));

  // cells per blank style, indexed by style id (small dense ints)
  var _blankCounts = Int32List(64);

  /// The blank style covering most blank cells of [back] (as a blank looks),
  /// or -1 if no erasable style covers at least a quarter of the screen.
  int _dominantBlank(Surface back) {
    final c = back.cells;
    final st = back.styles;
    final n = c.length;
    var counts = _blankCounts;
    var best = -1;
    var bestCount = 0;
    var i = 0;
    while (i < n) {
      if (c[i] != kBlank) {
        i++;
        continue;
      }
      final raw = st[i];
      var j = i + 1;
      while (j < n && c[j] == kBlank && st[j] == raw) {
        j++;
      }
      final b = styles.blankStyleOf(raw); // may intern a new style
      if (b >= counts.length) {
        counts = _blankCounts = Int32List(b * 2)..setAll(0, counts);
      }
      final k = counts[b] += j - i;
      if (k > bestCount) {
        best = b;
        bestCount = k;
      }
      i = j;
    }
    counts.fillRange(0, counts.length, 0);
    if (best < 0 || bestCount * 4 < n) {
      return -1;
    }
    if (!styles.erasable(best)) {
      return -1;
    }
    if (!caps.backgroundColorErase && !styles.bgOf(best).isDefault) {
      return -1;
    }
    return best;
  }

  /// Positions the cursor at (x, y) and writes the cell there.
  void _emit(Uint32List bc, Uint32List bs, int y, int x) {
    _moveTo(x, y);
    _emitHere(bc[y * width + x], bs[y * width + x], x, y);
  }

  /// Writes the glyph of cell word [c] with style [s] at the cursor, which
  /// must be at (x, y). Returns the number of columns the cell occupies.
  int _emitHere(int c, int s, int x, int y) {
    final uncertain = (c & kUncertain) != 0;
    if (uncertain && _shortOfEdge && x + glyphs.maxWidthOf(c) > width) {
      return _emitBlanks(c, s, x);
    }
    _setStyleFor(c, s);
    final glyph = c & kGlyphMask;
    final wide = (c & kWide) != 0;
    if (wide && uncertain) {
      out.ascii('\x1b[2X');
    } // cover a 1-column rendering
    if (glyph < kFirstInterned) {
      out.codePoint(glyph);
    } else {
      out.bytes(glyphs.bytesOf(glyph));
    }
    stats.cellsWritten++;
    final adv = wide ? 2 : 1;
    final nx = x + adv;
    if (uncertain || nx >= width) {
      _cx = -1; // column unknown (width disagreement / pending wrap)
    } else {
      _cx = nx;
    }
    return adv;
  }

  /// Sets SGR for drawing cell word [c] with style [s]. A blank only needs
  /// an SGR state that *looks* the same on a space (same background, no
  /// visible attributes), so text with spaces doesn't flip styles per space.
  @pragma('vm:prefer-inline')
  void _setStyleFor(int c, int s) {
    if (s == _sgr) {
      return;
    }
    if ((c & kGlyphMask) == kBlank &&
        (c & kWide) == 0 &&
        _sgr >= 0 &&
        styles.blankStyleOf(_sgr) == styles.blankStyleOf(s)) {
      return;
    }
    _setStyle(s);
  }

  /// The style a blank of style [s] at column [x] (of the row at cell
  /// [row], diffed up to column [hi]) is drawn in. When the SGR state has
  /// to change for the blank anyway, that is the style of the next glyph
  /// the diff writes if a blank looks the same in it, so the glyph needs no
  /// SGR of its own; otherwise [s].
  int _blankPen(Uint32List bc, Uint32List bs, int row, int x, int hi, int s) {
    final cur = _sgr;
    if (s == cur) {
      return s;
    }
    final blank = styles.blankStyleOf(s);
    if (cur >= 0 && styles.blankStyleOf(cur) == blank) {
      return s;
    }
    // skip the blanks that look the same; the next cell must be a glyph
    // that looks the same as a blank and is written (differs from the front)
    final end = row + hi;
    var i = row + x + 1;
    while (i < end && bc[i] == kBlank && styles.blankStyleOf(bs[i]) == blank) {
      i++;
    }
    if (i >= end) {
      return s;
    }
    final t = bs[i];
    if ((bc[i] & (kCont | kSkip)) != 0 ||
        styles.blankStyleOf(t) != blank ||
        !_differs(bc, bs, i, _fc[i], _fs[i])) {
      return s;
    }
    return t;
  }

  @pragma('vm:prefer-inline')
  void _setStyle(int s) {
    if (s == _sgr) {
      return;
    }
    out.bytes(_sgr < 0 ? styles.sgrFromReset(s) : styles.transition(_sgr, s));
    _sgr = s;
    final l = styles.linkIdOf(s);
    if (l != _link) {
      _setLink(l);
    }
  }

  /// OSC 8: open hyperlink [l] (0 closes the current one).
  void _setLink(int l) {
    out.ascii('\x1b]8;;');
    if (l != 0) {
      out.bytes(_linkTargets[l] ??= LineEncoder.linkTarget(styles.linkUri(l)));
    }
    out.ascii('\x1b\\');
    _link = l;
  }

  /// The targets of the links written, percent-encoded
  /// ([LineEncoder.linkTarget]), by link id.
  final _linkTargets = <int, Uint8List>{};

  /// SGR 0 (attributes and colors to default; 0 is the default parameter)
  /// and no open hyperlink.
  void _resetSgr() {
    out.ascii('\x1b[m');
    _sgr = 0;
    if (_link != 0) {
      _setLink(0);
    }
  }

  // ---------------------------------------------------------------- cursor --

  /// `ESC [ n <final>` for a sequence whose parameter defaults to 1 (ICH,
  /// DCH, CUU, CUD, CUF, CUB, SU, SD): a count of 1 is left out.
  @pragma('vm:prefer-inline')
  void _csiCount(int n, int finalByte) {
    if (n == 1) {
      out
        ..byte(0x1B)
        ..byte(0x5B)
        ..byte(finalByte);
    } else {
      out.csi(n, finalByte);
    }
  }

  /// Bytes [_csiCount] writes for count [n].
  @pragma('vm:prefer-inline')
  static int _countBytes(int n) => n == 1 ? 3 : 3 + decimalDigits(n);

  /// Moves the cursor with the shortest sequence the model allows.
  void _moveTo(int x, int y) {
    if (_cy == y && _cx == x) {
      return;
    }
    assert(!inline || _cy >= 0, 'an inline region is addressed relatively');
    // the screen's column and row: a fixed viewport's are offset
    final sx = x + _ox;
    final sy = y + _oy;
    // absolute: ESC [ y ; x H, a column of 1 left out (ESC [ y H, and
    // ESC [ H for the home position); never for an inline region, which
    // doesn't know its screen row
    var best = inline
        ? 1 << 30
        : sx > 0
        ? 4 + decimalDigits(sy + 1) + decimalDigits(sx + 1)
        : (sy > 0 ? 3 + decimalDigits(sy + 1) : 3);
    var plan = 0; // 0 CUP, 1 horizontal only, 2 vertical + horizontal
    var hPlan = 0; // 0 none, 1 CR, 2 CUF, 3 CUB, 4 CHA
    var vCost = 0;
    if (_cy >= 0) {
      if (_cy != y) {
        vCost = _countBytes((y - _cy).abs());
      }
      // horizontal part
      var hBest = 3 + decimalDigits(sx + 1); // CHA
      var hp = 4;
      if (sx == 0) {
        hBest = 1;
        hp = 1;
      }
      if (_cx >= 0) {
        final dx = x - _cx;
        if (dx == 0) {
          hBest = 0;
          hp = 0;
        } else if (dx > 0 && _countBytes(dx) < hBest) {
          hBest = _countBytes(dx);
          hp = 2;
        } else if (dx < 0 && _countBytes(-dx) < hBest) {
          hBest = _countBytes(-dx);
          hp = 3;
        }
      }
      if (vCost + hBest < best) {
        best = vCost + hBest;
        plan = _cy == y ? 1 : 2;
        hPlan = hp;
      }
    }
    if (plan == 0) {
      out
        ..byte(0x1B)
        ..byte(0x5B);
      if (sx > 0) {
        out
          ..decimal(sy + 1)
          ..byte(0x3B)
          ..decimal(sx + 1);
      } else if (sy > 0) {
        out.decimal(sy + 1);
      }
      out.byte(0x48);
    } else {
      if (plan == 2) {
        final dy = y - _cy;
        _csiCount(dy.abs(), dy > 0 ? 0x42 : 0x41); // CUD / CUU
      }
      switch (hPlan) {
        case 1:
          out.byte(0x0D);
        case 2:
          _csiCount(x - _cx, 0x43); // CUF
        case 3:
          _csiCount(_cx - x, 0x44); // CUB
        case 4:
          out.csi(sx + 1, 0x47); // CHA
      }
    }
    _cx = x;
    _cy = y;
  }

  /// Moves the cursor to row [y] of an inline region, keeping its column.
  void _moveToRow(int y) {
    final dy = y - _cy;
    if (dy != 0) {
      _csiCount(dy.abs(), dy > 0 ? 0x42 : 0x41); // CUD / CUU
      _cy = y;
    }
  }

  // ------------------------------------------------------- row shifts --

  /// Whether cell [i] differs between the surface and the front buffer (a
  /// blank compares by how it looks).
  @pragma('vm:prefer-inline')
  bool _differs(Uint32List bc, Uint32List bs, int i, int fcell, int fstyle) {
    final c = bc[i];
    if (c != fcell) {
      return true;
    }
    final s = bs[i];
    if (s == fstyle) {
      return false;
    }
    return c != kBlank || styles.blankStyleOf(s) != styles.blankStyleOf(fstyle);
  }

  /// If the change of row [y] (damaged in [lo, hi)) is cheaper to apply as
  /// "insert k blanks at column a" (ICH) or "delete k cells at a" (DCH) plus
  /// a few writes than as a rewrite of the tail, emits the ICH/DCH, applies
  /// the same shift to the front buffer and returns a (the diff must then
  /// cover [a, width)). Returns -1 otherwise.
  int _tryRowShift(
    Uint32List bc,
    Uint32List bs,
    Uint64List bc64,
    Uint64List bs64,
    int y,
    int lo,
    int hi,
  ) {
    final w = width;
    final row = y * w;
    final fc = _fc;
    final fs = _fs;
    // the changed span [a, e): identical cells are skipped two at a time,
    // then cells that only look the same (blank styles) one by one
    var a = firstDiffU32(bc, bc64, fc, _fc64, row + lo, row + hi);
    a = firstDiffU32(bs, bs64, fs, _fs64, row + lo, a) - row;
    while (a < hi && !_differs(bc, bs, row + a, fc[row + a], fs[row + a])) {
      a++;
    }
    if (a >= hi) {
      return -1;
    }
    var e = lastDiffU32(bc, bc64, fc, _fc64, row + a, row + hi);
    e = lastDiffU32(bs, bs64, fs, _fs64, e, row + hi) - row;
    while (e > a &&
        !_differs(bc, bs, row + e - 1, fc[row + e - 1], fs[row + e - 1])) {
      e--;
    }
    final changed = e - a; // upper bound of the cells a rewrite would send
    if (changed < 6 || w - a < 8) {
      return -1;
    }
    if ((fc[row + a] & kCont) != 0) {
      return -1;
    } // would split a wide glyph
    // nothing on the terminal to the right of a: shifting it can't help
    // (e.g. a row that just scrolled into view)
    var content = false;
    for (var x = a; x < e && !content; x++) {
      if (fc[row + x] != kBlank) {
        content = true;
      }
    }
    if (!content) {
      return -1;
    }
    for (var x = a; x < w; x++) {
      if ((fc[row + x] & (kUncertain | kSkip | kInvalid)) != 0) {
        return -1;
      }
    }
    // style of the blanks ICH/DCH create (current background on BCE
    // terminals); reset first when the current SGR isn't a plain background
    var eraseStyle = 0;
    final cur = _sgr;
    final bce = caps.backgroundColorErase;
    final curOk =
        cur >= 0 &&
        styles.erasable(cur) &&
        _link == 0 &&
        (bce || styles.bgOf(cur).isDefault);
    if (curOk && bce) {
      eraseStyle = styles.blankStyleOf(cur);
    }
    // Konsole's ICH inserts blanks in the default colours and its DCH
    // appends them, in the current SGR, at the end of the line it holds,
    // which may stop short of the margin: there only the default SGR's
    // blanks look the same wherever they land, and as on xterm
    final konsole = caps.konsoleLines;
    final plain = cur == 0 && _link == 0;
    final shiftStyle = konsole ? 0 : eraseStyle;
    final resetCost = konsole ? (plain ? 0 : 3) : (curOk ? 0 : 3);

    var bestK = 0;
    var bestCost = changed;
    const maxK = 8;
    final last = row + e - 1;
    for (var k = 1; k <= maxK && k < w - a; k++) {
      // inserted, then deleted: a loop of ints, as a for-in over a list
      // makes an iterator for each k
      for (var pass = 0; pass < 2; pass++) {
        final insert = pass == 0;
        if (!insert && (fc[row + a + k] & kCont) != 0) {
          continue;
        }
        // a real edit shifts the whole tail: the shift must explain the last
        // changed cell (one comparison rejects nearly every wrong k)
        if (insert) {
          if (e - 1 >= a + k &&
              _differs(bc, bs, last, fc[last - k], fs[last - k])) {
            continue;
          }
        } else if (e - 1 + k < w &&
            _differs(bc, bs, last, fc[last + k], fs[last + k])) {
          continue;
        }
        // the cells of [a, w) that differ from the shifted front, counted
        // until there are more than the best so far: a loop for each part
        // of the row, which then compares with one source
        var cost = 6 + resetCost; // cursor move + ICH/DCH, roughly
        final rowEnd = row + w;
        if (insert) {
          // [a, a + k) blanks inserted, then the front from a
          final head = row + a + k;
          for (var i = row + a; i < head && cost < bestCost; i++) {
            if (_differs(bc, bs, i, kBlank, shiftStyle)) {
              cost++;
            }
          }
          for (var i = head; i < rowEnd && cost < bestCost; i++) {
            if (_differs(bc, bs, i, fc[i - k], fs[i - k])) {
              cost++;
            }
          }
        } else {
          // the front from a + k, then [w - k, w) blanks erased
          final tail = rowEnd - k;
          for (var i = row + a; i < tail && cost < bestCost; i++) {
            if (_differs(bc, bs, i, fc[i + k], fs[i + k])) {
              cost++;
            }
          }
          for (var i = tail; i < rowEnd && cost < bestCost; i++) {
            if (_differs(bc, bs, i, kBlank, shiftStyle)) {
              cost++;
            }
          }
        }
        if (cost < bestCost) {
          bestCost = cost;
          bestK = insert ? k : -k;
        }
      }
    }
    // require a clear win over rewriting the tail
    if (bestK == 0 || bestCost * 5 > changed * 4) {
      return -1;
    }

    if (!curOk || (konsole && !plain)) {
      _resetSgr();
    }
    _moveTo(a, y);
    final k = bestK.abs();
    if (bestK > 0) {
      _csiCount(k, 0x40); // ICH
      for (var x = w - 1; x >= a + k; x--) {
        fc[row + x] = fc[row + x - k];
        fs[row + x] = fs[row + x - k];
      }
      for (var x = a; x < a + k; x++) {
        fc[row + x] = kBlank;
        fs[row + x] = shiftStyle;
      }
      // a wide glyph whose right half was pushed out is not on screen
      if ((fc[row + w - 1] & kWide) != 0) {
        fc[row + w - 1] = kInvalid;
      }
    } else {
      _csiCount(k, 0x50); // DCH
      for (var x = a; x < w - k; x++) {
        fc[row + x] = fc[row + x + k];
        fs[row + x] = fs[row + x + k];
      }
      for (var x = w - k; x < w; x++) {
        fc[row + x] = kBlank;
        fs[row + x] = shiftStyle;
      }
    }
    stats.shiftedRows++;
    return a;
  }

  // ---------------------------------------------------------------- scroll --

  /// Scrolls rows [top, bottom) of the terminal by [by] and shifts the front
  /// buffer the same way. With [forceRows] the region is re-diffed (the
  /// caller's surface did not move by itself); otherwise the surface moved
  /// identically and only its damage needs diffing.
  void _hardwareScroll(int top, int bottom, int by, {bool forceRows = true}) {
    // The scrolled-in lines are erased with the *current* background on BCE
    // terminals, so the attributes must be reset first.
    if (_sgr != 0 || _link != 0) {
      _resetSgr();
    }
    if (inline) {
      _scrollLines(top, bottom, by);
    } else {
      out
        ..byte(0x1B)
        ..byte(0x5B)
        ..decimal(top + _oy + 1)
        ..byte(0x3B)
        ..decimal(bottom + _oy)
        ..byte(0x72); // DECSTBM (homes the cursor)
      _csiCount(by.abs(), by > 0 ? 0x53 : 0x54); // SU / SD
      out.ascii('\x1b[r');
      _cx = _cy = -1;
    }
    _fillFlags(_rowSame, 0, _rowSame.length, 0);

    final w = width;
    final n = by.abs();
    if (by > 0) {
      _fc.setRange(top * w, (bottom - n) * w, _fc, (top + n) * w);
      _fs.setRange(top * w, (bottom - n) * w, _fs, (top + n) * w);
      fillU32(_fc, (bottom - n) * w, bottom * w, kBlank);
      fillU32(_fs, (bottom - n) * w, bottom * w, 0);
    } else {
      for (var y = bottom - 1; y >= top + n; y--) {
        _fc.setRange(y * w, y * w + w, _fc, (y - n) * w);
        _fs.setRange(y * w, y * w + w, _fs, (y - n) * w);
      }
      fillU32(_fc, top * w, (top + n) * w, kBlank);
      fillU32(_fs, top * w, (top + n) * w, 0);
    }
    if (forceRows) {
      _fillFlags(_forceRow, top, bottom, _wholeRow);
    }
    if (_shown.isNotEmpty) {
      _imagesMoved(top, bottom, 0, w);
    }
    stats.scrolledRows += bottom - top;
    stats.scrollOps++;
  }

  /// Inline mode: scrolls rows [top, bottom) of the region by [by] with a
  /// DL at the row the block loses and an IL at the row it gains: the rows
  /// between move, and those below the block end where they were (DL pulls
  /// them up, IL pushes them back down). Kept out of [_hardwareScroll] so
  /// the fullscreen scroll detection it is inlined into stays as small.
  @pragma('vm:never-inline')
  void _scrollLines(int top, int bottom, int by) {
    final n = by.abs();
    _moveToRow(by > 0 ? top : bottom - n);
    _csiCount(n, 0x4D); // DL
    _moveToRow(by > 0 ? bottom - n : top);
    _csiCount(n, 0x4C); // IL
    _cx = -1; // DEC terminals return it to the first column
  }

  /// Whether the front buffer has a wide glyph across the column boundary
  /// x0 or x1 in rows [top, bottom) (a margin through a glyph scrolls
  /// unpredictably on real terminals), or may have: a reserved cell there
  /// is whatever the terminal has.
  bool _cutsWideGlyph(int top, int bottom, int x0, int x1) {
    final w = width;
    bool cut(int c) => (c & kCont) != 0 || c == kSkip;
    for (var y = top; y < bottom; y++) {
      if (x0 > 0 && cut(_fc[y * w + x0])) {
        return true;
      }
      if (x1 < w && cut(_fc[y * w + x1])) {
        return true;
      }
    }
    return false;
  }

  /// Whether a move of the rectangle [x0, x1) x [top, bottom) by [by]
  /// rows, which the terminal cannot replay with margins, is scrolled as
  /// whole rows (DECSTBM, or DL and IL inline) instead, the cells outside
  /// the rectangle re-diffed against the shifted front: where writing
  /// those that differ from [back] costs fewer bytes, as estimated, than
  /// writing the cells inside that differ unmoved, which re-diffing the
  /// rows would (a log's scrollbar column or a border moves onto cells
  /// like it). Not where the rows are not the
  /// screen's whole rows (a fixed viewport short of an edge), an image the
  /// terminal shows is in them (sixel and iTerm2 pixels are not known to
  /// move with the rows) or a wide glyph is cut at the edges.
  @pragma('vm:never-inline')
  bool _widens(Surface back, int top, int bottom, int by, int x0, int x1) {
    final w = width;
    if (bottom - top < 2 ||
        !_wholeRows ||
        _cutsWideGlyph(top, bottom, x0, x1) ||
        (_shown.isNotEmpty && _scrollsImage(top, bottom, 0, w))) {
      return false;
    }
    final bc = back.cells;
    final bs = back.styles;
    final fc = _fc;
    final fs = _fs;
    // An estimate of the bytes each way (see _writeCost). The scroll:
    // DECSTBM, SU and its reset, or inline the moves to two rows, DL and
    // IL, which leave the column unknown; weighed at about three times
    // their bytes, the estimate being rough (random scenes of
    // test/presenter_diff_test.dart write the fewest bytes so). Then the
    // cells outside, shifted: those the move brings in (blanks in the rows
    // it exposes) that differ.
    // Where they are is kept (_besideLo, _besideHi): the damage they
    // are if the move is widened.
    var outside = inline ? 60 : 40;
    final blo = _besideLo;
    final bhi = _besideHi;
    for (var y = top; y < bottom; y++) {
      final from = y + by;
      final exposed = from < top || from >= bottom;
      final row = y * w;
      final src = from * w;
      var first = -1;
      var last = -2;
      var style = -1;
      for (var x = 0; x < w; x++) {
        if (x == x0) {
          x = x1 - 1; // the rectangle's cells
          continue;
        }
        final i = row + x;
        if (exposed
            ? bc[i] != kBlank || bs[i] != 0
            : fc[src + x] != bc[i] || fs[src + x] != bs[i]) {
          outside += _writeCost(bc[i], bs[i], style, last == x - 1);
          if (first < 0) {
            first = x;
          }
          last = x;
          style = bs[i];
        }
      }
      blo[y] = first < 0 ? 0 : first;
      bhi[y] = first < 0 ? 0 : last + 1;
    }
    // against the cells inside unmoved that differ, counted only as far as
    // it decides
    var inside = 0;
    for (var y = top; y < bottom; y++) {
      final row = y * w;
      var last = -2;
      var style = -1;
      for (var i = row + x0; i < row + x1; i++) {
        if (fc[i] != bc[i] || fs[i] != bs[i]) {
          inside += _writeCost(bc[i], bs[i], style, last == i - 1);
          if (inside > outside) {
            return true;
          }
          last = i;
          style = bs[i];
        }
      }
    }
    return false;
  }

  /// About the bytes writing cell [c] in [style] costs, after a cell in
  /// [prev] (-1 none) that was written just before it when [next]: a cursor
  /// move to start a run, an SGR where the style changes, the glyph's
  /// UTF-8, and for a glyph whose width terminals disagree on, the erase
  /// before it and the move after it.
  static int _writeCost(int c, int style, int prev, bool next) =>
      (next ? 0 : 6) +
      (style == prev ? 0 : 12) +
      ((c & kUncertain) != 0
          ? 12
          : (c & 0xFFFFFF) < 0x80
          ? 1
          : 3);

  /// Damages in [back] the cells of rows [top, bottom) outside the
  /// rectangle that [_widens] found different ([_besideLo], [_besideHi]):
  /// the move of the rectangle scrolled as whole rows shifted them on the
  /// terminal, where on the surface they stayed. The rows not forced
  /// already are diffed over their damage then, without a row shift
  /// (ICH/DCH), as forced ones are.
  void _damageBeside(Surface back, int top, int bottom) {
    final f = _forceRow;
    final blo = _besideLo;
    final bhi = _besideHi;
    for (var y = top; y < bottom; y++) {
      if (f[y] == 0) {
        f[y] = _damageRow;
      }
      if (blo[y] < bhi[y]) {
        back.markDirty(y, blo[y], bhi[y]);
      }
    }
  }

  /// A move of rows [top, bottom) after one widened to whole rows: the
  /// cells of rows left to re-diff may move to any row of it, all of which
  /// are re-diffed then.
  void _carryForced(int top, int bottom) {
    final f = _forceRow;
    for (var y = top; y < bottom; y++) {
      if (f[y] != 0) {
        _fillFlags(f, top, bottom, _wholeRow);
        return;
      }
    }
  }

  /// Scrolls the rectangle [x0, x1) x [top, bottom) by [by] rows using
  /// DECSTBM + DECSLRM margins (DEC mode 69), then restores full margins.
  /// The surface moved identically (Surface.scrollRect).
  void _hardwareScrollRect(int top, int bottom, int by, int x0, int x1) {
    // the exposed cells take the current background
    if (_sgr != 0 || _link != 0) {
      _resetSgr();
    }
    out
      ..ascii('\x1b[?69h\x1b[')
      ..decimal(top + _oy + 1)
      ..byte(0x3B)
      ..decimal(bottom + _oy)
      ..ascii('r\x1b[')
      ..decimal(x0 + _ox + 1)
      ..byte(0x3B)
      ..decimal(x1 + _ox)
      ..byte(0x73); // DECSLRM
    _csiCount(by.abs(), by > 0 ? 0x53 : 0x54); // SU / SD
    out.ascii('\x1b[s\x1b[r\x1b[?69l');
    _cx = _cy = -1;
    _fillFlags(_rowSame, 0, _rowSame.length, 0);

    final w = width;
    final n = by.abs();
    if (by > 0) {
      for (var y = top; y < bottom - n; y++) {
        _fc.setRange(y * w + x0, y * w + x1, _fc, (y + n) * w + x0);
        _fs.setRange(y * w + x0, y * w + x1, _fs, (y + n) * w + x0);
      }
      for (var y = bottom - n; y < bottom; y++) {
        fillU32(_fc, y * w + x0, y * w + x1, kBlank);
        fillU32(_fs, y * w + x0, y * w + x1, 0);
      }
    } else {
      for (var y = bottom - 1; y >= top + n; y--) {
        _fc.setRange(y * w + x0, y * w + x1, _fc, (y - n) * w + x0);
        _fs.setRange(y * w + x0, y * w + x1, _fs, (y - n) * w + x0);
      }
      for (var y = top; y < top + n; y++) {
        fillU32(_fc, y * w + x0, y * w + x1, kBlank);
        fillU32(_fs, y * w + x0, y * w + x1, 0);
      }
    }
    if (_shown.isNotEmpty) {
      _imagesMoved(top, bottom, x0, x1);
    }
    stats.scrolledRows += bottom - top;
    stats.scrollOps++;
    stats.rectScrollOps++;
  }

  /// Hash of cells [start, end): content and style of every cell. Rows of
  /// an even-width screen are hashed two cells per multiply, other rows
  /// one cell per multiply; all rows of one screen take the same path, so
  /// equal rows hash equally.
  static int _rowHash(
    Uint32List c,
    Uint32List st,
    Uint64List c64,
    Uint64List st64,
    int start,
    int end,
  ) {
    var h = 0x2F1A3B5C;
    if ((start & 1) == 0 && (end & 1) == 0) {
      // aligned rows (even width): one multiply per two cells
      for (var k = start >> 1; k < end >> 1; k++) {
        final sv = st64[k];
        h = (h ^ c64[k] ^ ((sv << 23) | (sv >>> 41))) * 0x100000001B3;
      }
      return h;
    }
    for (var i = start; i < end; i++) {
      h = (h ^ (c[i] | (st[i] << 32))) * 0x100000001B3;
    }
    return h;
  }

  bool _frontHashesCorrect() {
    for (var y = 0; y < height; y++) {
      if (_hf[y] !=
          _rowHash(_fc, _fs, _fc64, _fs64, y * width, y * width + width)) {
        return false;
      }
    }
    return true;
  }

  /// Finds a block of rows that moved vertically (by up to [maxAutoScroll])
  /// and scrolls it in hardware. Row hashes only steer the decision: the
  /// following diff runs against the shifted front buffer, so a hash
  /// collision can cost bytes but never correctness.
  void _detectScroll(Surface back) {
    final w = width;
    final h = height;
    var dirtyRows = 0;
    for (var y = 0; y < h; y++) {
      if (back.dirtyLo[y] < back.dirtyHi[y]) {
        dirtyRows++;
      }
    }
    if (dirtyRows < 4 || dirtyRows * 4 < h) {
      return;
    }
    // A scroll only pays off when at least 3 rows really changed; checking
    // that is a cheap 64-bit comparison that stops at the third changed row
    // (a repaint-everything frame where little changed skips hashing).
    final bc = back.cells;
    final bs = back.styles;
    final bc64 = back.cells64;
    final bs64 = back.styles64;
    var changed = 0;
    for (var y = 0; y < h && changed < 3; y++) {
      if (back.dirtyLo[y] >= back.dirtyHi[y]) {
        continue;
      }
      final a = y * w;
      final b = a + w;
      if (!equalRangeU32(bc, bc64, _fc, _fc64, a, b) ||
          !equalRangeU32(bs, bs64, _fs, _fs64, a, b)) {
        changed++;
      } else {
        _rowSame[y] = 1;
      }
    }
    if (changed < 3) {
      return;
    }
    if (_hb.length != h) {
      _hb = Int64List(h);
      _hf = Int64List(h);
      _hfValid = false;
    }
    if (!_hfValid) {
      for (var y = 0; y < h; y++) {
        _hf[y] = _rowHash(_fc, _fs, _fc64, _fs64, y * w, y * w + w);
      }
    }
    for (var y = 0; y < h; y++) {
      // a row without damage still equals the front: its hash is known
      // (valid front hashes: see the end of present)
      _hb[y] = _hfValid && back.dirtyLo[y] >= back.dirtyHi[y]
          ? _hf[y]
          : _rowHash(bc, bs, bc64, bs64, y * w, y * w + w);
    }
    _hashedThisFrame = true;
    // Several blocks may have moved by different amounts (stacked panes
    // scrolling independently): take the best block, scroll it, exclude its
    // rows, repeat. Rows of a scrolled region are re-diffed, so a hash
    // collision costs bytes, never correctness.
    if (_usedRows.length < h) {
      _usedRows = Uint8List(h);
    }
    final used = _usedRows;
    _fillFlags(used, 0, h, 0);
    final maxS = maxAutoScroll < h - 1 ? maxAutoScroll : h - 1;
    for (var round = 0; round < maxScrollBlocks; round++) {
      var bestGain = 0;
      var bestTop = 0;
      var bestBottom = 0;
      var bestBy = 0;
      for (var s = 1; s <= maxS; s++) {
        for (final dir in const <int>[1, -1]) {
          // dir 1: back[y] == front[y + s] (content moved up)
          var runStart = -1;
          var gain = 0;
          final yFrom = dir > 0 ? 0 : s;
          final yTo = dir > 0 ? h - s : h;
          for (var y = yFrom; y <= yTo; y++) {
            final src = y + dir * s;
            final match =
                y < yTo && used[y] == 0 && used[src] == 0 && _hb[y] == _hf[src];
            if (match) {
              if (runStart < 0) {
                runStart = y;
                gain = 0;
              }
              if (_hb[y] != _hf[y]) {
                gain++;
              }
            } else if (runStart >= 0) {
              if (gain > bestGain) {
                bestGain = gain;
                bestBy = dir * s;
                if (dir > 0) {
                  bestTop = runStart;
                  bestBottom = y + s;
                } else {
                  bestTop = runStart - s;
                  bestBottom = y;
                }
              }
              runStart = -1;
            }
          }
        }
      }
      if (bestGain < 3) {
        break;
      }
      // the rows of a sixel or iTerm2 image are rewritten instead
      if (_shown.isEmpty || !_scrollsImage(bestTop, bestBottom, 0, w)) {
        _hardwareScroll(bestTop, bestBottom, bestBy);
      }
      _fillFlags(used, bestTop, bestBottom, 1);
    }
  }
}

/// An image as the presenter last drew it: where ([at], a copy of the
/// surface's placement), its kitty [placement] id, and whether it was
/// [drawn] or its cells left blank.
final class _Shown {
  _Shown(this.at, this.placement, {required this.drawn});
  final ImagePlacement at;
  final int placement;
  final bool drawn;

  /// A scroll may have moved it on the terminal, or the screen was
  /// forgotten: it is drawn again.
  var moved = false;

  /// Shown on, or placed again, by this frame.
  var kept = false;
}
