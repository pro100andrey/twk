/// A terminal emulator for programs run inside a twk app: what they write
/// goes in as bytes, their screen comes out as cells the core's Canvas
/// draws, answers to their queries and what keys, the mouse and pasted
/// text send go back to them as bytes, and what they ask of the terminal
/// beyond the screen comes out as [TerminalEvent]s.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:twk_core/twk_core.dart';

import 'buffer.dart';
import 'events.dart';
import 'input.dart';
import 'modes.dart';
import 'parser.dart';

// Examples can assume:
// import 'package:twk_core/twk_core.dart';

part 'dispatch.dart';
part 'paint.dart';

/// Where the cursor and its attributes were saved (DECSC), per screen.
final class _Saved {
  var x = 0;
  var y = 0;
  var pendingWrap = false;
  Color fg = Color.defaultColor;
  Color bg = Color.defaultColor;
  Color ul = Color.defaultColor;
  var attrs = 0;
  String? link;
  final charsets = Uint8List(4);
  var gl = 0;
  var origin = false;
}

/// The primary or the alternate screen.
final class _Screen {
  _Screen(int width, int height, {required this.alternate})
    : lines = [for (var y = 0; y < height; y++) TerminalLine(width)];

  final bool alternate;
  List<TerminalLine> lines;
  var saved = _Saved();

  /// The kitty keyboard protocol's flags, pushed and popped (`CSI > u`,
  /// `CSI < u`): the last are the current ones.
  final keyFlags = <int>[0];
}

/// How many flags of the kitty keyboard protocol a screen's stack keeps;
/// the oldest go beyond.
const _keyFlagsDepth = 16;

// Character sets (G0..G3 designations).
const _ascii = 0;
const _decGraphics = 1;
const _uk = 2;

/// xterm's palette as 0xRRGGBB.
final Int32List _xtermPalette = () {
  const base = [
    0x000000, 0xcd0000, 0x00cd00, 0xcdcd00, 0x0000ee, 0xcd00cd, 0x00cdcd, //
    0xe5e5e5, 0x7f7f7f, 0xff0000, 0x00ff00, 0xffff00, 0x5c5cff, 0xff00ff,
    0x00ffff, 0xffffff,
  ];
  final p = Int32List(256)..setRange(0, 16, base);
  const levels = [0, 95, 135, 175, 215, 255];
  for (var i = 0; i < 216; i++) {
    p[16 + i] =
        (levels[i ~/ 36] << 16) | (levels[(i ~/ 6) % 6] << 8) | levels[i % 6];
  }
  for (var i = 0; i < 24; i++) {
    final v = 8 + 10 * i;
    p[232 + i] = (v << 16) | (v << 8) | v;
  }
  return p;
}();

/// DEC special graphics for 0x5F..0x7E.
const _decGraphicsMap = [
  0x0020, 0x25C6, 0x2592, 0x2409, 0x240C, 0x240D, 0x240A, 0x00B0, //
  0x00B1, 0x2424, 0x240B, 0x2518, 0x2510, 0x250C, 0x2514, 0x253C,
  0x23BA, 0x23BB, 0x2500, 0x23BC, 0x23BD, 0x251C, 0x2524, 0x2534,
  0x252C, 0x2502, 0x2264, 0x2265, 0x03C0, 0x2260, 0x00A3, 0x00B7,
];

/// A permissive VT emulator (xterm's dialect): a primary screen with a
/// scrollback and an alternate one, the cursor and its modes, SGR with 16,
/// 256 and 24-bit colors and underline styles, DEC special graphics,
/// scroll margins, insertion and deletion of lines and characters, tab
/// stops, autowrap with a pending wrap, wide and combining characters as
/// the core's [TextSegmenter] splits them, OSC titles, hyperlinks and
/// clipboard requests, the mouse, focus and paste modes, and the answers
/// to DSR, DA, DECRQM, DECRQSS and XTVERSION. A sequence it doesn't know is
/// ignored (with [strict], an error).
///
/// A resize rewraps the primary screen and its scrollback: lines the
/// program's text wrapped are joined and split again at the new width,
/// the cursor staying on the character it was on, and the screen shows the
/// last lines with the cursor's among them (lines go to the scrollback when
/// the screen gets shorter, come back from it when it gets taller). The
/// alternate screen, which its program redraws, is cut or padded.
///
/// What a program wrote, read back as text:
///
/// ```dart
/// final term = TerminalEmulator(width: 40, height: 10);
/// term.feedText('\x1b[1mbold\x1b[0m and plain\r\n');
/// print(term.lineText(0)); // bold and plain
/// ```
///
/// A program run in a `Pty`, its answers and keys written back to it:
///
/// ```dart
/// final pty = Pty.start('bash', const [], width: 80, height: 24);
/// final term = TerminalEmulator(onOutput: pty.write);
/// pty.output.listen(term.feed);
/// term.sendKey(const KeyEvent(KeyCode.up));
/// ```
///
/// See also:
///
///  * `TerminalView`, the widget that shows a program's emulator and hands
///    it the keys, the mouse and its size.
final class TerminalEmulator {
  /// An emulator of [width] x [height] cells (at least 1 x 1) in its
  /// initial state, keeping [scrollbackLimit] lines of scrollback.
  ///
  /// Its cells' ids are in [styles] and [glyphs], tables of its own where
  /// they are null. Text is split into cells by [textMode] (code points by
  /// default; DEC mode 2027 switches it), characters whose width is
  /// ambiguous taking [ambiguousWidth] columns. [onOutput], [onEvent] and
  /// [strict] are as the fields of those names.
  TerminalEmulator({
    int width = 80,
    int height = 24,
    int scrollbackLimit = 1000,
    StyleTable? styles,
    GlyphTable? glyphs,
    TextMode textMode = TextMode.legacy,
    int ambiguousWidth = 1,
    this.onOutput,
    this.onEvent,
    this.strict = false,
  }) : _width = width < 1 ? 1 : width,
       _height = height < 1 ? 1 : height,
       styles = styles ?? StyleTable(),
       _ownStyles = styles == null,
       glyphs = glyphs ?? GlyphTable(),
       segmenter = TextSegmenter(
         mode: textMode,
         ambiguousWidth: ambiguousWidth,
       ),
       _scrollback = Scrollback(scrollbackLimit),
       _textMode = textMode {
    _modes = _defaultModes;
    _primary = _Screen(_width, _height, alternate: false);
    _alternate = _Screen(_width, _height, alternate: true);
    _screen = _primary;
    _parser = VtParser(_Dispatch(this));
    _resetState();
  }

  /// Bytes for the program: answers to its queries and what [sendKey],
  /// [sendMouse], [sendPaste] and the others encode.
  void Function(Uint8List bytes)? onOutput;

  /// What the program asks of the terminal beyond its screen.
  void Function(TerminalEvent event)? onEvent;

  /// Rows `[top, bottom)` of the screen shown moved up by `n` rows (down
  /// when `n` is negative), as a line feed at the bottom margin, IND, RI,
  /// SU, SD, IL and DL move them; the rows they leave are blank. A view
  /// moves what it painted of them with them (a hardware scroll) instead of
  /// painting them again.
  void Function(int top, int bottom, int n)? onScrolled;

  /// An unknown sequence throws a [FormatException] instead of being
  /// ignored (for tests).
  final bool strict;

  /// The styles of the cells; a host that passes its canvas's table can
  /// copy cells as they are.
  ///
  /// A table of the emulator's own is swept ([StyleTable.sweep]) once
  /// twice as many styles are in use as after the last sweep, and at
  /// least [sweepFloor]: a program that writes 24-bit color (a video, an
  /// image viewer) gives each color it sends a style, which would
  /// otherwise be kept as long as the emulator is. What no cell of its
  /// screens and scrollback has is freed; ids kept from before are noted
  /// by [StyleTable.sweeps]. A table the host passed is the host's to
  /// sweep, the emulator's cells among the roots.
  final StyleTable styles;
  final bool _ownStyles;

  /// The fewest styles in use a table of the emulator's own is swept
  /// past (see [styles]); a test's may be fewer.
  static var sweepFloor = 4096;

  // swept once this many styles are in use
  var _sweepAt = 0;

  /// The multi-code-point glyphs of the cells.
  final GlyphTable glyphs;

  /// How printed text is split into cells; DEC mode 2027 switches its
  /// mode between grapheme clusters and code points.
  final TextSegmenter segmenter;
  final TextMode _textMode;
  final _scan = ClusterScan();

  late final VtParser _parser;
  late final _Screen _primary;
  late final _Screen _alternate;
  late _Screen _screen;
  final Scrollback _scrollback;

  int _width;
  int _height;

  /// How many columns the screen has.
  int get width => _width;

  /// How many rows the screen has.
  int get height => _height;

  // cursor
  var _x = 0;
  var _y = 0;
  var _pendingWrap = false;

  /// The cursor's column (where the next character goes; with a wrap
  /// pending, the last column).
  int get cursorX => _x;

  /// The cursor's row on the screen.
  int get cursorY => _y;

  /// The last character was printed in the last column and the next one
  /// goes to the next row.
  bool get wrapPending => _pendingWrap;

  /// Whether the program shows the cursor (DECTCEM).
  bool get cursorVisible => mode(TerminalMode.cursorVisible);

  /// The cursor's shape the program set (DECSCUSR);
  /// [CursorShape.terminalDefault] until it sets one.
  CursorShape get cursorShape => _cursorShape;
  CursorShape _cursorShape = CursorShape.terminalDefault;

  // scroll region: rows [_top, _bottom)
  var _top = 0;
  var _bottom = 0;

  /// The scroll margins (DECSTBM): rows [top, bottom).
  (int, int) get margins => (_top, _bottom);

  late Uint8List _tabs;

  // SGR
  Color _fg = Color.defaultColor;
  Color _bg = Color.defaultColor;
  Color _ul = Color.defaultColor;
  var _attrs = 0;
  String? _link;
  var _style = 0;
  var _eraseStyle = 0;
  var _styleDirty = true;

  // character sets
  final _charsets = Uint8List(4);
  var _gl = 0;
  var _singleShift = -1;

  var _modes = 0;
  final _savedModes = <TerminalMode, bool>{};

  int get _defaultModes =>
      TerminalMode.autowrap.bit |
      TerminalMode.cursorVisible.bit |
      TerminalMode.autorepeat.bit |
      (_textMode == TextMode.graphemes
          ? TerminalMode.graphemeClustering.bit
          : 0);

  /// The glyph REP repeats, -1 before anything was printed.
  var _lastGlyph = -1;
  var _lastWidth = 1;

  /// Window title (OSC 0, 2).
  String get title => _title;
  var _title = '';

  /// Icon name (OSC 0, 1).
  String get iconName => _iconName;
  var _iconName = '';
  final _titleStack = <(String, String)>[];

  /// The working directory the program last told (OSC 7).
  Uri? get workingDirectory => _cwd;
  Uri? _cwd;

  /// The palette as RGB (0xRRGGBB), which OSC 4 sets and asks for; cells
  /// keep palette indices.
  final palette = Int32List(256);

  /// The default text color (0xRRGGBB) the host draws with, which OSC 10
  /// reports until the program sets its own.
  var defaultForeground = 0xE5E5E5;

  /// The default background, for OSC 11.
  var defaultBackground = 0x000000;

  /// The cursor color, for OSC 12 (the text color when null).
  int? defaultCursorColor;

  int? _fgSet;
  int? _bgSet;
  int? _cursorSet;

  /// The default text color: the program's (OSC 10) or the host's.
  int get foregroundColor => _fgSet ?? defaultForeground;

  /// The default background: the program's (OSC 11) or the host's.
  int get backgroundColor => _bgSet ?? defaultBackground;

  /// The cursor color: the program's (OSC 12), the host's or the text
  /// color.
  int get cursorColor => _cursorSet ?? defaultCursorColor ?? foregroundColor;

  /// The width of a cell in pixels, for XTWINOPS 14 and 16; unknown (0)
  /// leaves those unanswered.
  var cellPixelWidth = 0;

  /// The height of a cell in pixels, for XTWINOPS 14 and 16; unknown (0)
  /// leaves those unanswered.
  var cellPixelHeight = 0;

  /// Whether [mode] is set.
  bool mode(TerminalMode mode) => _modes & mode.bit != 0;

  /// The alternate screen is shown.
  bool get alternateScreen => identical(_screen, _alternate);

  /// What the program wants to hear of the mouse.
  MouseProtocol get mouseProtocol => mode(TerminalMode.mouseMotion)
      ? MouseProtocol.motion
      : mode(TerminalMode.mouseDrags)
      ? MouseProtocol.drags
      : mode(TerminalMode.mouseButtons)
      ? MouseProtocol.buttons
      : mode(TerminalMode.mouseX10)
      ? MouseProtocol.x10
      : MouseProtocol.off;

  /// How mouse reports are encoded.
  MouseEncoding get mouseEncoding => mode(TerminalMode.mouseSgr)
      ? MouseEncoding.sgr
      : mode(TerminalMode.mouseUrxvt)
      ? MouseEncoding.urxvt
      : mode(TerminalMode.mouseUtf8)
      ? MouseEncoding.utf8
      : MouseEncoding.x10;

  // ------------------------------------------------------------ reading --

  /// Row [y] of the screen shown.
  TerminalLine line(int y) => _screen.lines[y];

  /// Lines scrolled off the top of the primary screen.
  int get scrollbackLength => _scrollback.length;

  /// Scrollback line [i], 0 the oldest.
  TerminalLine scrollbackLine(int i) => _scrollback[i];

  /// How many lines the scrollback keeps; lines beyond go, oldest first.
  int get scrollbackLimit => _scrollback.limit;
  set scrollbackLimit(int value) => _scrollback.limit = value;

  /// How many lines have gone into the scrollback since the emulator was
  /// made; a view scrolled back keeps its lines in place by it.
  int get scrollbackAdded => _scrollbackAdded;
  var _scrollbackAdded = 0;

  /// The kitty keyboard protocol's flags the program set on the screen
  /// shown (`CSI = u`, `CSI > u`), 0 for the legacy keys: 1 disambiguate,
  /// 2 report event types, 4 alternate keys, 8 all keys as escape codes, 16
  /// associated text. [sendKey] encodes the keys by them.
  int get keyboardFlags => _screen.keyFlags.last;

  /// Row [y] of the screen as text, the blanks at its end left out.
  String lineText(int y) => line(y).text(glyphs);

  /// The screen as text, a line per row.
  String get text => [for (var y = 0; y < _height; y++) lineText(y)].join('\n');

  /// The glyph word of the cell at ([x], [y]): glyph id and flags (`kWide`,
  /// `kCont`, `kUncertain`).
  int cellAt(int x, int y) => line(y).cells[x];

  /// The text of the cell at ([x], [y]); empty for the trailing half of a
  /// two-column glyph.
  String cellText(int x, int y) {
    final c = cellAt(x, y);
    return (c & kCont) != 0 ? '' : glyphs.stringOf(c);
  }

  /// The style id (in [styles]) of the cell at ([x], [y]).
  int styleAt(int x, int y) => line(y).styles[x];

  final _painter = _Painter();

  /// Draws the screen with [canvas], its top left cell at ([x], [y]) (the
  /// canvas's translation and clip apply), shown [scrollOffset] lines back
  /// in the scrollback (on the primary screen); the screen's reverse video
  /// (DECSCNM) applied, the cursor not drawn. The cells' styles and glyphs
  /// are carried over to the canvas's tables, once each.
  ///
  /// The program's default text color is painted in [fg] and its default
  /// background in [bg] (underlines in the default color follow [fg]);
  /// [Color.defaultColor], as by default, leaves them the host terminal's.
  /// The emulator's state is not changed: what the program is told of its
  /// colors ([defaultForeground], [defaultBackground]) is set apart.
  void paint(
    Canvas canvas, {
    int x = 0,
    int y = 0,
    int scrollOffset = 0,
    Color fg = Color.defaultColor,
    Color bg = Color.defaultColor,
  }) => _painter.paint(this, canvas, x, y, scrollOffset, fg, bg);

  /// Draws [line] — a row of the screen or of the scrollback, or a copy of
  /// one, its ids in [styles] and [glyphs] — as [paint] draws each row,
  /// its first cell at ([x], [y]), the default colors in [fg] and [bg]; as
  /// many cells as the narrower of the line and the screen.
  void paintLine(
    Canvas canvas,
    TerminalLine line, {
    int x = 0,
    int y = 0,
    Color fg = Color.defaultColor,
    Color bg = Color.defaultColor,
  }) => _painter.paintLine(this, canvas, line, x, y, fg, bg);

  // ------------------------------------------------------------ writing --

  /// Takes what the program wrote; a sequence may be split across calls.
  void feed(List<int> bytes) {
    _parser.feed(bytes);
    _sweepIfDue();
  }

  /// [text] as the program would write it (UTF-8).
  void feedText(String text) => feed(utf8.encode(text));

  /// Sweeps a table of the emulator's own when it is due (see [styles]).
  void _sweepIfDue() {
    final live = styles.live;
    if (!_ownStyles || live <= sweepFloor || live <= _sweepAt) {
      return;
    }
    void lines(void Function(int id) mark, TerminalLine line) {
      final ids = line.styles;
      for (var x = 0; x < ids.length; x++) {
        mark(ids[x]);
      }
    }

    styles.sweep((mark) {
      for (final line in _primary.lines) {
        lines(mark, line);
      }
      for (final line in _alternate.lines) {
        lines(mark, line);
      }
      for (var i = 0; i < _scrollback.length; i++) {
        lines(mark, _scrollback[i]);
      }
    });
    // the pen's own ids may be gone: made again as text comes
    _styleDirty = true;
    _sweepAt = 2 * styles.live;
  }

  /// A new size; see the class comment for what happens to the screen.
  void resize(int width, int height) {
    final w = width < 1 ? 1 : width;
    final h = height < 1 ? 1 : height;
    if (w == _width && h == _height) {
      return;
    }
    final onPrimary = !alternateScreen;
    var x = _x + (_pendingWrap ? 1 : 0);
    var y = _y;
    // the primary screen: rewrapped with its scrollback
    final saved = _primary.saved;
    final lines = [..._scrollback.toList(), ..._primary.lines];
    final base = _scrollback.length;
    // the blank rows below the cursor (and below the saved cursor) go
    var last = lines.length - 1;
    final keepTo = base + (onPrimary ? y : saved.y);
    while (last > keepTo && _isBlank(lines[last])) {
      last--;
    }
    final (wrapped, cl, cc) = reflow(
      lines.sublist(0, last + 1),
      w,
      base + (onPrimary ? y : saved.y),
      onPrimary ? x : saved.x,
    );
    var start = wrapped.length - h;
    if (start > cl) {
      start = cl; // the cursor's line stays on the screen
    }
    if (start < 0) {
      start = 0;
    }
    _scrollback.replace(wrapped.sublist(0, start));
    final shown = wrapped.sublist(
      start,
      start + h < wrapped.length ? start + h : wrapped.length,
    );
    while (shown.length < h) {
      shown.add(TerminalLine(w));
    }
    _primary.lines = shown;
    var pending = false;
    if (onPrimary) {
      pending = cc >= w;
      x = pending ? w - 1 : cc;
      y = cl - start;
    } else {
      saved
        ..x = cc >= w ? w - 1 : cc
        ..y = cl - start
        ..pendingWrap = cc >= w;
    }
    // the alternate screen: cut or padded, the cursor's row kept
    final alt = _alternate.lines;
    for (final line in alt) {
      line.resize(w, 0);
    }
    if (!onPrimary && y >= h) {
      alt.removeRange(0, y - h + 1);
      y = h - 1;
    }
    if (alt.length > h) {
      alt.removeRange(h, alt.length);
    }
    while (alt.length < h) {
      alt.add(TerminalLine(w));
    }
    for (final s in [_primary.saved, _alternate.saved]) {
      s
        ..x = s.x.clamp(0, w - 1)
        ..y = s.y.clamp(0, h - 1);
    }
    _width = w;
    _height = h;
    _x = x.clamp(0, w - 1);
    _y = y.clamp(0, h - 1);
    _pendingWrap = pending && _autowrap;
    _top = 0;
    _bottom = h;
    final tabs = Uint8List(w);
    for (var i = 8; i < w; i += 8) {
      tabs[i] = 1;
    }
    tabs.setRange(0, w < _tabs.length ? w : _tabs.length, _tabs);
    _tabs = tabs;
  }

  static bool _isBlank(TerminalLine line) =>
      !line.wrapped && line.contentWidth == 0;

  /// Back to the state of a new terminal (RIS); the scrollback stays.
  void reset() {
    _parser.reset();
    _switchScreen(alternate: false);
    for (final s in [_primary, _alternate]) {
      for (final line in s.lines) {
        line.clear(0);
      }
      s.saved = _Saved();
      s.keyFlags
        ..clear()
        ..add(0);
    }
    _resetState();
  }

  void _resetState() {
    _x = 0;
    _y = 0;
    _pendingWrap = false;
    _top = 0;
    _bottom = _height;
    _tabs = Uint8List(_width);
    for (var i = 8; i < _width; i += 8) {
      _tabs[i] = 1;
    }
    _sgrReset();
    _link = null;
    _charsets.fillRange(0, 4, _ascii);
    _gl = 0;
    _singleShift = -1;
    final modes = _defaultModes;
    for (final m in TerminalMode.values) {
      _setMode(m, on: modes & m.bit != 0);
    }
    segmenter.mode = _textMode;
    _savedModes.clear();
    if (_cursorShape != CursorShape.terminalDefault) {
      _cursorShape = CursorShape.terminalDefault;
      _event(const CursorShapeChanged(CursorShape.terminalDefault));
    }
    _resetPalette();
    _fgSet = null;
    _bgSet = null;
    _cursorSet = null;
    _lastGlyph = -1;
  }

  void _resetPalette() => palette.setAll(0, _xtermPalette);

  // -------------------------------------------------------------- input --

  /// Sends [key] as the program's modes want it: in its kitty keyboard
  /// protocol flags ([keyboardFlags], [kittyKeySequence]) where it set
  /// any that change the keys, else as xterm does ([keySequence]); false
  /// when it sends nothing (a release the program doesn't hear of).
  bool sendKey(KeyEvent key) {
    final flags = keyboardFlags;
    final s = flags & _kittyKeys != 0
        ? kittyKeySequence(key, flags)
        : keySequence(
            key,
            cursorKeys: mode(TerminalMode.cursorKeys),
            newLine: mode(TerminalMode.newLine),
          );
    if (s == null) {
      return false;
    }
    _send(utf8.encode(s));
    return true;
  }

  /// The kitty flags that change what keys send: disambiguate, event
  /// types, all keys as escape codes.
  static const int _kittyKeys = 1 | 2 | 8;

  /// Sends [text] as typed.
  void sendText(String text) => _send(utf8.encode(text));

  /// Sends [text] as pasted (bracketed when the program asked).
  void sendPaste(String text) => _send(
    utf8.encode(
      pasteSequence(text, bracketed: mode(TerminalMode.bracketedPaste)),
    ),
  );

  /// Sends a focus change when the program asked for them; false when it
  /// didn't.
  bool sendFocus({required bool focused}) {
    if (!mode(TerminalMode.focus)) {
      return false;
    }
    _send(utf8.encode(focused ? '\x1b[I' : '\x1b[O'));
    return true;
  }

  /// Sends [event] (cell coordinates on this screen) as the program's mouse
  /// modes want it; false when the program doesn't hear of it, and the
  /// mouse is the host's. On the alternate screen with mode 1007 the wheel
  /// of an untracked mouse goes as arrow keys.
  bool sendMouse(MouseEvent event) {
    final protocol = mouseProtocol;
    if (protocol == MouseProtocol.off) {
      if (alternateScreen &&
          mode(TerminalMode.alternateScroll) &&
          (event.kind == MouseKind.wheelUp ||
              event.kind == MouseKind.wheelDown)) {
        return sendKey(
          KeyEvent(
            event.kind == MouseKind.wheelUp ? KeyCode.up : KeyCode.down,
          ),
        );
      }
      return false;
    }
    final bytes = mouseSequence(event, protocol, mouseEncoding);
    if (bytes == null) {
      return false;
    }
    _send(Uint8List.fromList(bytes));
    return true;
  }

  /// Answers a [ClipboardRead] with [text] from [selection].
  void answerClipboard(String selection, String text) => _reply(
    '\x1b]52;$selection;${base64.encode(utf8.encode(text))}\x1b\\',
  );

  void _send(List<int> bytes) =>
      onOutput?.call(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));

  void _reply(String s) => _send(utf8.encode(s));

  void _event(TerminalEvent e) => onEvent?.call(e);

  void _unknown(String what) {
    if (strict) {
      throw FormatException('unsupported sequence: $what');
    }
  }

  // -------------------------------------------------------------- modes --

  void _setMode(TerminalMode m, {required bool on}) {
    if (mode(m) == on) {
      return;
    }
    _modes = on ? _modes | m.bit : _modes & ~m.bit;
    _event(ModeChanged(m, enabled: on));
  }

  static const List<TerminalMode> _mouseModes = [
    TerminalMode.mouseX10,
    TerminalMode.mouseButtons,
    TerminalMode.mouseDrags,
    TerminalMode.mouseMotion,
  ];
  static const List<TerminalMode> _mouseEncodings = [
    TerminalMode.mouseUtf8,
    TerminalMode.mouseSgr,
    TerminalMode.mouseUrxvt,
  ];

  /// DECSET / DECRST of private mode [code].
  void _privateMode(int code, {required bool on}) {
    switch (code) {
      case 47:
        _switchScreen(alternate: on);
        return;
      case 1047:
        if (on) {
          _switchScreen(alternate: true);
        } else if (alternateScreen) {
          _clearScreen(_alternate);
          _switchScreen(alternate: false);
        }
        return;
      case 1048:
        on ? _saveCursor() : _restoreCursor();
        return;
      case 1049:
        if (on) {
          if (!alternateScreen) {
            _saveCursor();
            _switchScreen(alternate: true);
            _clearScreen(_alternate);
          }
        } else if (alternateScreen) {
          _switchScreen(alternate: false);
          _restoreCursor();
        }
        return;
    }
    final m = TerminalMode.of(code, private: true);
    if (m == null) {
      if (!_ignoredModes.contains(code)) {
        _unknown('CSI ? $code ${on ? 'h' : 'l'}');
      }
      return;
    }
    _applyMode(m, on: on);
  }

  /// Private modes known and left reset: 132 columns and what allows them,
  /// smooth scrolling, reverse wraparound, highlight tracking, the meta and
  /// keypad variants of xterm.
  static const _ignoredModes = {
    3, 4, 40, 45, 1001, 1034, 1035, 1036, 1037, 1039, 1042, 1043, 1070, //
  };

  void _applyMode(TerminalMode m, {required bool on}) {
    if (_mouseModes.contains(m)) {
      // one of them at a time; any of them reset turns tracking off
      for (final other in _mouseModes) {
        _setMode(other, on: on && other == m);
      }
    } else if (_mouseEncodings.contains(m)) {
      for (final other in _mouseEncodings) {
        _setMode(other, on: on && other == m);
      }
    } else if (m == TerminalMode.alternateScreen) {
      _privateMode(1049, on: on);
    } else {
      if (m == TerminalMode.graphemeClustering) {
        segmenter.mode = on ? TextMode.graphemes : TextMode.legacy;
      }
      _setMode(m, on: on);
      if (m == TerminalMode.origin) {
        _moveTo(0, 0);
      }
    }
  }

  /// The DECRQM value of private mode [code].
  int _privateModeValue(int code) {
    if (code == 47 || code == 1047) {
      return alternateScreen ? 1 : 2;
    }
    final m = TerminalMode.of(code, private: true);
    if (m == null) {
      return _ignoredModes.contains(code) ? 4 : 0;
    }
    return mode(m) ? 1 : 2;
  }

  void _switchScreen({required bool alternate}) {
    if (alternateScreen == alternate) {
      return;
    }
    _screen = alternate ? _alternate : _primary;
    _pendingWrap = false;
    _setMode(TerminalMode.alternateScreen, on: alternate);
  }

  void _clearScreen(_Screen s) {
    for (final line in s.lines) {
      line.clear(_eraseStyleNow);
    }
  }

  // ---------------------------------------------------------------- SGR --

  void _sgrReset() {
    _fg = Color.defaultColor;
    _bg = Color.defaultColor;
    _ul = Color.defaultColor;
    _attrs = 0;
    _styleDirty = true;
  }

  @pragma('vm:prefer-inline')
  int get _styleNow {
    if (_styleDirty) {
      _updateStyle();
    }
    return _style;
  }

  @pragma('vm:prefer-inline')
  int get _eraseStyleNow {
    if (_styleDirty) {
      _updateStyle();
    }
    return _eraseStyle;
  }

  void _updateStyle() {
    _style = styles.style(
      fg: _fg,
      bg: _bg,
      attrs: _attrs,
      underlineColor: _ul,
      link: _link,
    );
    // erased cells take the background alone (BCE)
    _eraseStyle = _bg.isDefault ? 0 : styles.style(bg: _bg);
    _styleDirty = false;
  }

  // ----------------------------------------------------------- printing --

  @pragma('vm:prefer-inline')
  bool get _autowrap => _modes & _autowrapBit != 0;
  static final int _autowrapBit = TerminalMode.autowrap.bit;
  static final int _insertBit = TerminalMode.insert.bit;

  void _printAscii(Uint8List data, int start, int end) {
    if (_charsets[_gl] != _ascii ||
        _singleShift >= 0 ||
        _modes & _insertBit != 0) {
      for (var i = start; i < end; i++) {
        _putGlyph(_mapCharset(data[i]), 1);
      }
      return;
    }
    final style = _styleNow;
    final w = _width;
    var i = start;
    while (i < end) {
      if (_pendingWrap) {
        if (_autowrap) {
          _wrap();
        } else {
          _pendingWrap = false;
        }
      }
      final line = _screen.lines[_y];
      final cells = line.cells;
      final x0 = _x;
      var n = end - i;
      if (n > w - x0) {
        n = w - x0;
      }
      final x1 = x0 + n;
      if (x0 > 0 && (cells[x0] & kCont) != 0) {
        cells[x0 - 1] = kBlank;
      }
      if (x1 < w && (cells[x1] & kCont) != 0) {
        cells[x1] = kBlank;
      }
      final styles = line.styles;
      for (var k = 0; k < n; k++) {
        cells[x0 + k] = data[i + k];
        styles[x0 + k] = style;
      }
      i += n;
      if (x1 >= w) {
        _x = w - 1;
        if (_autowrap) {
          _pendingWrap = true;
        } else if (i < end) {
          cells[w - 1] = data[end - 1]; // the rest overwrite the last column
          i = end;
        }
      } else {
        _x = x1;
      }
    }
    _lastGlyph = data[end - 1];
    _lastWidth = 1;
  }

  int _mapCharset(int c) {
    var set = _charsets[_gl];
    if (_singleShift >= 0) {
      set = _charsets[_singleShift];
      _singleShift = -1;
    }
    if (set == _decGraphics && c >= 0x5F && c <= 0x7E) {
      return _decGraphicsMap[c - 0x5F];
    }
    if (set == _uk && c == 0x23) {
      return 0xA3;
    }
    return c;
  }

  void _printText(String text) {
    var s = text;
    if (_charsets[_gl] != _ascii || _singleShift >= 0) {
      final sb = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        final c = s.codeUnitAt(i);
        sb.writeCharCode(c >= 0x20 && c < 0x7F ? _mapCharset(c) : c);
      }
      s = sb.toString();
    }
    var i = s.codeUnitAt(0) >= 0x300 ? _joinLeft(s) : 0;
    final scan = _scan;
    while (i < s.length) {
      final start = i;
      segmenter.scan(s, i, scan);
      i = scan.end;
      final w = scan.width;
      if (w == 0) {
        continue; // a control, a mark without a base, a zero-width char
      }
      var glyph = scan.length == 1 ? scan.first : glyphs.intern(s, start, i);
      if (scan.uncertain || scan.joinsNext) {
        glyph |= kUncertain;
      }
      _putGlyph(glyph, w);
    }
  }

  /// Joins the start of [s] to the cell left of the cursor where it
  /// continues that cell's cluster (a combining mark, a variation
  /// selector, an emoji ZWJ sequence arriving in pieces); returns the code
  /// units of [s] taken.
  int _joinLeft(String s) {
    var px = _pendingWrap ? _x : _x - 1;
    if (px < 0) {
      return 0;
    }
    final line = _screen.lines[_y];
    final cells = line.cells;
    var cell = cells[px];
    if ((cell & kCont) != 0) {
      if (px == 0) {
        return 0;
      }
      px--;
      cell = cells[px];
    }
    final prev = glyphs.stringOf(cell);
    final joined = prev + (s.length > 32 ? s.substring(0, 32) : s);
    final scan = _scan;
    segmenter.scan(joined, 0, scan);
    if (scan.end <= prev.length) {
      return 0;
    }
    var glyph = glyphs.intern(joined, 0, scan.end);
    if (scan.uncertain || scan.joinsNext) {
      glyph |= kUncertain;
    }
    final wide = (cell & kWide) != 0;
    if (scan.width == 2 && !wide && px + 1 < _width) {
      // wider now (a VS16): takes the column after it
      if ((cells[px + 1] & kWide) != 0) {
        line.breakWide(px + 1);
      }
      cells[px] = glyph | kWide;
      cells[px + 1] = kCont;
      line.styles[px + 1] = line.styles[px];
      if (!_pendingWrap && _x == px + 1) {
        _x = px + 2;
        if (_x >= _width) {
          _x = _width - 1;
          _pendingWrap = _autowrap;
        }
      }
      _lastWidth = 2;
    } else {
      cells[px] = wide ? glyph | kWide : glyph;
      _lastWidth = wide ? 2 : 1;
    }
    _lastGlyph = glyph;
    return scan.end - prev.length;
  }

  /// Prints one glyph of width [w] (1 or 2) at the cursor.
  void _putGlyph(int glyph, int w) {
    if (_pendingWrap) {
      if (_autowrap) {
        _wrap();
      } else {
        _pendingWrap = false;
      }
    }
    if (w == 2) {
      if (_width < 2) {
        return;
      }
      if (_x == _width - 1) {
        if (_autowrap) {
          // doesn't fit: the last column stays blank, the glyph goes on
          _screen.lines[_y].erase(_x, _x + 1, _styleNow);
          _wrap();
        } else {
          _x = _width - 2;
        }
      }
    }
    final line = _screen.lines[_y];
    if (_modes & _insertBit != 0) {
      _insertCells(line, _x, w, _eraseStyleNow);
    }
    final cells = line.cells;
    final styles = line.styles;
    final x = _x;
    final style = _styleNow;
    if (x > 0 && (cells[x] & kCont) != 0) {
      cells[x - 1] = kBlank;
    }
    final end = x + w;
    if (end < _width && (cells[end] & kCont) != 0) {
      cells[end] = kBlank;
    }
    if (w == 2) {
      cells[x] = glyph | kWide;
      cells[x + 1] = kCont;
      styles[x] = style;
      styles[x + 1] = style;
    } else {
      cells[x] = glyph;
      styles[x] = style;
    }
    if (end >= _width) {
      _x = _width - 1;
      _pendingWrap = _autowrap;
    } else {
      _x = end;
    }
    _lastGlyph = glyph;
    _lastWidth = w;
  }

  /// REP: the last glyph printed, [n] times more.
  void _repeat(int n) {
    if (_lastGlyph < 0) {
      return;
    }
    final glyph = _lastGlyph & ~kWide;
    final w = _lastWidth;
    final count = n > _width * _height ? _width * _height : n;
    for (var i = 0; i < count; i++) {
      _putGlyph(glyph, w);
    }
  }

  /// To the start of the next row, the row ending wrapped.
  void _wrap() {
    _screen.lines[_y].wrapped = true;
    _x = 0;
    _pendingWrap = false;
    _index();
  }

  // ----------------------------------------------------- cursor and rows --

  /// IND / LF: down a row, scrolling at the bottom margin.
  void _index() {
    if (_y == _bottom - 1) {
      _scrollUp(1);
    } else if (_y < _height - 1) {
      _y++;
    }
  }

  /// RI: up a row, scrolling at the top margin.
  void _reverseIndex() {
    if (_y == _top) {
      _scrollDown(1);
    } else if (_y > 0) {
      _y--;
    }
  }

  /// Scrolls the margins up [n] rows; off the top of the primary screen
  /// (margin at its top row) into the scrollback.
  void _scrollUp(int n) {
    final top = _top;
    final bottom = _bottom;
    final k = n > bottom - top ? bottom - top : n;
    final lines = _screen.lines;
    final keep = top == 0 && !alternateScreen;
    final style = _eraseStyleNow;
    for (var i = 0; i < k; i++) {
      final gone = lines[top];
      for (var y = top; y < bottom - 1; y++) {
        lines[y] = lines[y + 1];
      }
      var fresh = keep ? _scrollback.push(gone) : gone;
      if (fresh == null || fresh.width != _width) {
        fresh = TerminalLine(_width, style);
      } else {
        fresh.clear(style);
      }
      lines[bottom - 1] = fresh;
    }
    if (keep && _scrollback.limit > 0) {
      _scrollbackAdded += k;
    }
    onScrolled?.call(top, bottom, k);
  }

  /// Scrolls the margins down [n] rows.
  void _scrollDown(int n) {
    final top = _top;
    final bottom = _bottom;
    final k = n > bottom - top ? bottom - top : n;
    final lines = _screen.lines;
    final style = _eraseStyleNow;
    for (var i = 0; i < k; i++) {
      final line = lines.removeAt(bottom - 1)..clear(style);
      lines.insert(top, line);
    }
    onScrolled?.call(top, bottom, -k);
  }

  /// To column [x], row [y] (counted from the top margin in origin mode),
  /// within the screen (the margins in origin mode).
  void _moveTo(int x, int y) {
    final origin = mode(TerminalMode.origin);
    final lo = origin ? _top : 0;
    final hi = origin ? _bottom - 1 : _height - 1;
    final row = y + lo;
    _y = row < lo ? lo : (row > hi ? hi : row);
    _x = x < 0 ? 0 : (x >= _width ? _width - 1 : x);
    _pendingWrap = false;
  }

  void _setColumn(int x) {
    _x = x < 0 ? 0 : (x >= _width ? _width - 1 : x);
    _pendingWrap = false;
  }

  /// Up [n] rows, stopping at the top margin when below it.
  void _cursorUp(int n) {
    final stop = _y >= _top ? _top : 0;
    _y = _y - n < stop ? stop : _y - n;
    _pendingWrap = false;
  }

  /// Down [n] rows, stopping at the bottom margin when above it.
  void _cursorDown(int n) {
    final stop = _y < _bottom ? _bottom - 1 : _height - 1;
    _y = _y + n > stop ? stop : _y + n;
    _pendingWrap = false;
  }

  void _tab(int n) {
    var x = _x;
    for (var i = 0; i < n && x < _width - 1; i++) {
      x++;
      while (x < _width - 1 && _tabs[x] == 0) {
        x++;
      }
    }
    _x = x;
    _pendingWrap = false;
  }

  void _backTab(int n) {
    var x = _x;
    for (var i = 0; i < n && x > 0; i++) {
      x--;
      while (x > 0 && _tabs[x] == 0) {
        x--;
      }
    }
    _x = x;
    _pendingWrap = false;
  }

  void _saveCursor() {
    final s = _screen.saved
      ..x = _x
      ..y = _y
      ..pendingWrap = _pendingWrap
      ..fg = _fg
      ..bg = _bg
      ..ul = _ul
      ..attrs = _attrs
      ..link = _link
      ..gl = _gl
      ..origin = mode(TerminalMode.origin);
    s.charsets.setAll(0, _charsets);
  }

  void _restoreCursor() {
    final s = _screen.saved;
    _x = s.x.clamp(0, _width - 1);
    _y = s.y.clamp(0, _height - 1);
    _pendingWrap = s.pendingWrap && _x == _width - 1;
    _fg = s.fg;
    _bg = s.bg;
    _ul = s.ul;
    _attrs = s.attrs;
    _link = s.link;
    _styleDirty = true;
    _gl = s.gl;
    _charsets.setAll(0, s.charsets);
    _setMode(TerminalMode.origin, on: s.origin);
  }

  // ---------------------------------------------------------- editing --

  /// Shifts cells [x, width) of [line] right by [n], blanks in [style]
  /// coming in.
  void _insertCells(TerminalLine line, int x, int n, int style) {
    final w = _width;
    final k = n > w - x ? w - x : n;
    final cells = line.cells;
    if (x > 0 && (cells[x] & kCont) != 0) {
      line.breakWide(x);
    }
    if (k < w - x) {
      // a two-column glyph pushed off the edge in halves goes whole
      if ((cells[w - k - 1] & kWide) != 0) {
        line.breakWide(w - k - 1);
      }
      cells.setRange(x + k, w, cells, x);
      line.styles.setRange(x + k, w, line.styles, x);
    }
    cells.fillRange(x, x + k, kBlank);
    line.styles.fillRange(x, x + k, style);
  }

  /// ICH.
  void _insertChars(int n) {
    _insertCells(_screen.lines[_y], _x, n, _eraseStyleNow);
    _pendingWrap = false;
  }

  /// DCH.
  void _deleteChars(int n) {
    final line = _screen.lines[_y];
    final w = _width;
    final x = _x;
    final k = n > w - x ? w - x : n;
    final cells = line.cells;
    if ((cells[x] & kCont) != 0) {
      line.breakWide(x);
    }
    if (x + k < w && (cells[x + k] & kCont) != 0) {
      line.breakWide(x + k);
    }
    cells.setRange(x, w - k, cells, x + k);
    line.styles.setRange(x, w - k, line.styles, x + k);
    cells.fillRange(w - k, w, kBlank);
    line.styles.fillRange(w - k, w, _eraseStyleNow);
    _pendingWrap = false;
  }

  /// IL / DL: lines at the cursor's row, inside the margins only.
  void _insertLines(int n, {required bool delete}) {
    if (_y < _top || _y >= _bottom) {
      return;
    }
    final top = _top;
    _top = _y;
    if (delete) {
      // lines deleted are not kept: no scrollback from here
      final lines = _screen.lines;
      final k = n > _bottom - _y ? _bottom - _y : n;
      final style = _eraseStyleNow;
      for (var i = 0; i < k; i++) {
        final line = lines.removeAt(_y)..clear(style);
        lines.insert(_bottom - 1, line);
      }
      onScrolled?.call(_y, _bottom, k);
    } else {
      _scrollDown(n);
    }
    _top = top;
    _x = 0;
    _pendingWrap = false;
  }

  /// ED.
  void _eraseDisplay(int how) {
    final lines = _screen.lines;
    final style = _eraseStyleNow;
    switch (how) {
      case 0:
        lines[_y]
          ..erase(_x, _width, style)
          ..wrapped = false;
        for (var y = _y + 1; y < _height; y++) {
          lines[y].clear(style);
        }
      case 1:
        for (var y = 0; y < _y; y++) {
          lines[y].clear(style);
        }
        lines[_y].erase(0, _x + 1, style);
      case 2:
        for (final line in lines) {
          line.clear(style);
        }
      case 3:
        _scrollback.clear();
    }
    _pendingWrap = false;
  }

  /// EL.
  void _eraseLine(int how) {
    final line = _screen.lines[_y];
    final style = _eraseStyleNow;
    switch (how) {
      case 0:
        line
          ..erase(_x, _width, style)
          ..wrapped = false;
      case 1:
        line.erase(0, _x + 1, style);
      case 2:
        line.clear(style);
    }
    _pendingWrap = false;
  }

  /// DECALN: the screen full of `E`, margins reset, the cursor home.
  void _alignmentTest() {
    for (final line in _screen.lines) {
      line
        ..clear(0)
        ..cells.fillRange(0, _width, 0x45);
    }
    _top = 0;
    _bottom = _height;
    _setMode(TerminalMode.origin, on: false);
    _moveTo(0, 0);
  }

  /// DECSTR.
  void _softReset() {
    _setMode(TerminalMode.cursorVisible, on: true);
    _setMode(TerminalMode.insert, on: false);
    _setMode(TerminalMode.origin, on: false);
    _setMode(TerminalMode.autowrap, on: true);
    _setMode(TerminalMode.cursorKeys, on: false);
    _setMode(TerminalMode.keypad, on: false);
    _top = 0;
    _bottom = _height;
    _sgrReset();
    _link = null;
    _charsets.fillRange(0, 4, _ascii);
    _gl = 0;
    _singleShift = -1;
    _screen.saved = _Saved();
  }
}
