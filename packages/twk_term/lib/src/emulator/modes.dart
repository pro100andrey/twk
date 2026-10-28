/// The modes a program turns on and off, and what the host does about the
/// ones that change how input is to be sent.
library;

/// A mode set with `CSI h` / `CSI ? h` and reset with `l`. The emulator
/// answers DECRQM for each; what isn't listed is reported as unknown.
enum TerminalMode {
  /// IRM: printed text pushes the rest of the row right.
  insert(4, ansi: true),

  /// LNM: LF, VT and FF return to the first column; Enter sends CR LF.
  newLine(20, ansi: true),

  /// DECCKM: arrow keys, Home and End are sent as `SS3 A` rather than
  /// `CSI A`.
  cursorKeys(1),

  /// DECSCNM: the whole screen in reverse video.
  reverseVideo(5),

  /// DECOM: row positions count from the top margin and stay within the
  /// margins.
  origin(6),

  /// DECAWM: text reaching the last column wraps to the next row.
  autowrap(7),

  /// DECARM: keys repeat (kept, not acted on).
  autorepeat(8),

  /// X10 mouse: presses only, no modifiers.
  mouseX10(9),

  /// The cursor blinks (att610).
  cursorBlink(12),

  /// DECTCEM: the cursor is shown.
  cursorVisible(25),

  /// DECNKM: the keypad sends application sequences (DECKPAM sets it too).
  keypad(66),

  /// Presses, releases and the wheel.
  mouseButtons(1000),

  /// Those, and motion with a button held.
  mouseDrags(1002),

  /// Those, and all motion.
  mouseMotion(1003),

  /// Focus in and out are sent (`CSI I`, `CSI O`).
  focus(1004),

  /// Mouse coordinates as UTF-8 characters.
  mouseUtf8(1005),

  /// Mouse reports in SGR form (`CSI < b ; x ; y M`).
  mouseSgr(1006),

  /// The wheel on the alternate screen, the mouse not tracked, is sent as
  /// arrow keys.
  alternateScroll(1007),

  /// Mouse reports in urxvt form (`CSI b ; x ; y M`).
  mouseUrxvt(1015),

  /// The alternate screen (also switched by modes 47 and 1047, which
  /// report the same).
  alternateScreen(1049),

  /// Pasted text is bracketed by `CSI 200 ~` and `CSI 201 ~`.
  bracketedPaste(2004),

  /// The program is drawing a frame: what the screen shows is not to be
  /// presented until it resets the mode.
  synchronizedOutput(2026),

  /// Text is split into cells by grapheme clusters (UAX #29) rather than
  /// code point by code point (wcwidth).
  graphemeClustering(2027);

  const TerminalMode(this.code, {this.ansi = false});

  /// The mode's number.
  final int code;

  /// Set with `CSI h` rather than `CSI ? h`.
  final bool ansi;

  /// The bit of this mode in a set of modes.
  int get bit => 1 << index;

  static final Map<int, TerminalMode> _private = {
    for (final m in values)
      if (!m.ansi) m.code: m,
  };
  static final Map<int, TerminalMode> _ansi = {
    for (final m in values)
      if (m.ansi) m.code: m,
  };

  /// The mode [code] (private: `CSI ?`), or null when it isn't known.
  static TerminalMode? of(int code, {required bool private}) =>
      private ? _private[code] : _ansi[code];
}

/// What the program wants to hear of the mouse.
enum MouseProtocol {
  /// Nothing: the mouse is the host's (selection, scrolling back).
  off,

  /// Presses only, no modifiers (mode 9).
  x10,

  /// Presses, releases and the wheel (mode 1000).
  buttons,

  /// Those, and motion with a button held (mode 1002).
  drags,

  /// Those, and all motion (mode 1003).
  motion,
}

/// How mouse reports are encoded.
enum MouseEncoding {
  /// `CSI M` and three bytes, coordinates up to 223.
  x10,

  /// `CSI M` and three UTF-8 characters, coordinates up to 2015.
  utf8,

  /// `CSI < b ; x ; y M` (`m` for a release).
  sgr,

  /// `CSI b ; x ; y M`.
  urxvt,
}
