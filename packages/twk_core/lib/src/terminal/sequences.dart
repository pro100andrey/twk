/// The control strings a terminal is sent beside its frames: the title
/// ([titleSequence]), the clipboard ([clipboardSequence]), the mouse's
/// reports and pointer ([mouseTrackingSequence], [pointerShapeSequence]),
/// desktop notifications ([notifySequence]), progress ([progressSequence]),
/// bidi modes; each wrapped for a [Multiplexer] where it has to pass one
/// ([passthroughSequence]). What a terminal is known to show is told by its
/// environment ([pointerNamesFor], [progressReportsFor],
/// [bidiReorderingFor]).
library;

import 'dart:convert';

import '../unicode/unicode.dart';

// Examples can assume:
// import 'dart:convert';

/// Returns OSC 52, which puts [text] on the system clipboard, wrapped for
/// [multiplexer] ([passthroughSequence]).
///
/// Terminals that allow it: kitty, WezTerm, foot, Ghostty, Windows
/// Terminal, iTerm2, xterm with `allowWindowOps`; it works over ssh, unlike
/// a local clipboard tool. Inside tmux it also goes as it is, first: tmux
/// takes that one itself with `set-clipboard on` (keeping it as a paste
/// buffer too) and drops it by default, while the wrapped one needs
/// `allow-passthrough on`. A tmux inside another hands the outer one plain
/// OSC 52, which that takes with `set-clipboard on`.
String clipboardSequence(
  String text, {
  Multiplexer multiplexer = Multiplexer.none,
}) {
  final s = '\x1b]52;c;${base64.encode(utf8.encode(text))}\x1b\\';
  final wrapped = passthroughSequence(s, multiplexer);
  return multiplexer == Multiplexer.tmux ? '$s$wrapped' : wrapped;
}

/// Returns OSC 2, which sets the window's or tab's title to [title].
///
/// Control characters (C0, DEL, C1) are removed, so the title can't end
/// the string early or inject sequences.
///
/// ```dart
/// final bytes = utf8.encode(titleSequence('Editor — notes.md'));
/// ```
///
/// See also:
///
///  * [pushTitleSequence] and [popTitleSequence], which keep the user's
///    title to put back.
String titleSequence(String title) {
  final clean = StringBuffer();
  for (final r in title.runes) {
    if (r >= 0x20 && r != 0x7F && (r < 0x80 || r > 0x9F)) {
      clean.writeCharCode(r);
    }
  }
  return '\x1b]2;$clean\x1b\\';
}

/// XTWINOPS that pushes the window's and icon's titles on the terminal's
/// title stack, for [popTitleSequence] to put back.
const pushTitleSequence = '\x1b[22;0t';

/// XTWINOPS that pops the titles [pushTitleSequence] pushed, putting them
/// back.
const popTitleSequence = '\x1b[23;0t';

/// What the terminal reports of the mouse, each value what the one before
/// it reports and more, at more bytes: a DEC mode each, with SGR
/// coordinates (mode 1006).
enum MouseTracking {
  /// Nothing: the mouse is the terminal's, its selection and its wheel.
  off(0),

  /// Presses, releases and the wheel (mode 1000).
  buttons(1000),

  /// Those, and motion while a button is held (mode 1002).
  drags(1002),

  /// Those, and all motion (mode 1003): a report for each cell the mouse
  /// crosses.
  motion(1003);

  const MouseTracking(this.mode);

  /// The DEC mode that turns it on; 0 for [off].
  final int mode;
}

/// What switches the terminal's mouse reports from [from] to [to]: the
/// mode of [from] off, that of [to] on (terminals keep one of them on at a
/// time, and some turn any of them off with the reset of another), SGR
/// coordinates on with the first and off with the last; empty when they
/// are the same.
String mouseTrackingSequence(MouseTracking from, MouseTracking to) {
  if (from == to) {
    return '';
  }
  const off = MouseTracking.off;
  return switch ((from, to)) {
    (off, _) => '\x1b[?${to.mode}h\x1b[?1006h',
    (_, off) => '\x1b[?${from.mode}l\x1b[?1006l',
    _ => '\x1b[?${from.mode}l\x1b[?${to.mode}h',
  };
}

/// How a terminal shows a desktop notification ([notifySequence]).
enum NotificationProtocol {
  /// None is known to work: nothing is sent.
  none,

  /// OSC 9, iTerm2's: one message.
  osc9,

  /// OSC 777 `notify`, urxvt's: a title and a body.
  osc777,

  /// OSC 99, kitty's: a title and a body, in base64 when it has line
  /// breaks.
  osc99,
}

/// The terminal multiplexer between a program and the terminal, which keeps
/// sequences it doesn't know from the terminal unless they are wrapped
/// ([passthroughSequence]).
enum Multiplexer {
  /// None: the program writes to the terminal itself.
  none,

  /// tmux.
  tmux,

  /// GNU screen.
  screen,
}

/// Returns a desktop notification of [title] and [body] in [protocol],
/// wrapped for [multiplexer].
///
/// Empty for [NotificationProtocol.none] or with nothing to show. Control
/// characters and the blanks around each text are removed; a line break in
/// the body is kept by OSC 99 and is a space elsewhere, as a tab is. The
/// title is cut to 256 bytes of UTF-8 and the body to 1024, between
/// graphemes, ending with `…`. OSC 9 shows `title: body`; OSC 777 shows a
/// body without a title as the title, and `,` for `;`, which would end its
/// field. OSC 99 sends the title and the body as two sequences under [id]
/// (letters, digits and `_-+.`, the rest dropped): a notification with the
/// same id that is still shown is replaced.
String notifySequence(
  String title,
  String body, {
  required NotificationProtocol protocol,
  Multiplexer multiplexer = Multiplexer.none,
  String id = '1',
}) {
  var t = _cut(_plain(title, lines: false), 256);
  var b = _cut(
    _plain(body, lines: protocol == NotificationProtocol.osc99),
    1024,
  );
  if (t.isEmpty && b.isEmpty) {
    return '';
  }
  final String s;
  switch (protocol) {
    case NotificationProtocol.none:
      return '';
    case NotificationProtocol.osc9:
      s = '\x1b]9;${[t, b].where((p) => p.isNotEmpty).join(': ')}\x1b\\';
    case NotificationProtocol.osc777:
      if (t.isEmpty) {
        (t, b) = (b, '');
      }
      s =
          '\x1b]777;notify;${t.replaceAll(';', ',')};'
          '${b.replaceAll(';', ',')}\x1b\\';
    case NotificationProtocol.osc99:
      final i = 'i=${id.replaceAll(RegExp(r'[^\w+.-]'), '')}';
      final sb = StringBuffer();
      if (t.isNotEmpty) {
        sb.write('\x1b]99;$i${b.isEmpty ? '' : ':d=0'};$t\x1b\\');
      }
      if (b.isNotEmpty) {
        sb.write(
          b.contains('\n')
              ? '\x1b]99;$i:p=body:e=1;${base64.encode(utf8.encode(b))}\x1b\\'
              : '\x1b]99;$i:p=body;$b\x1b\\',
        );
      }
      s = sb.toString();
  }
  return passthroughSequence(s, multiplexer);
}

/// The shapes of the mouse pointer OSC 22 sets ([pointerShapeSequence]),
/// by the names of CSS's `cursor` ([css]), as kitty's protocol names them,
/// or by the X cursor font's ([x11]), as xterm and iTerm2 do.
enum PointerShape {
  /// A shortcut or alias of something is to be made.
  alias('alias'),

  /// A cell or a range of cells can be selected (a thick plus).
  cell('cell', 'tcross'),

  /// Something is to be copied.
  copy('copy'),

  /// A precise point (cross hairs).
  crosshair('crosshair', 'crosshair'),

  /// The platform's own pointer, an arrow mostly (CSS `default`).
  arrow('default', 'left_ptr'),

  /// The right (east) edge is to be moved.
  eResize('e-resize', 'right_side'),

  /// An edge is to be moved left or right.
  ewResize('ew-resize', 'sb_h_double_arrow'),

  /// Something can be grabbed and dragged (an open hand).
  grab('grab', 'fleur'),

  /// Something is being dragged (a closed hand).
  grabbing('grabbing', 'fleur'),

  /// Help is at hand (an arrow with a question mark).
  help('help', 'question_arrow'),

  /// Something is to be moved.
  move('move', 'fleur'),

  /// The top (north) edge is to be moved.
  nResize('n-resize', 'based_arrow_up'),

  /// The top right corner is to be moved.
  neResize('ne-resize', 'top_right_corner'),

  /// The top right or bottom left corner is to be moved.
  neswResize('nesw-resize'),

  /// What is dragged can't be dropped here.
  noDrop('no-drop', 'X_cursor'),

  /// What was asked won't be done.
  notAllowed('not-allowed', 'X_cursor'),

  /// An edge is to be moved up or down.
  nsResize('ns-resize', 'sb_v_double_arrow'),

  /// The top left corner is to be moved.
  nwResize('nw-resize', 'top_left_corner'),

  /// The top left or bottom right corner is to be moved.
  nwseResize('nwse-resize'),

  /// A link (a pointing hand).
  pointer('pointer', 'hand2'),

  /// The program is busy, but takes input meanwhile.
  progress('progress', 'watch'),

  /// The bottom (south) edge is to be moved.
  sResize('s-resize', 'based_arrow_down'),

  /// The bottom right corner is to be moved.
  seResize('se-resize', 'bottom_right_corner'),

  /// The bottom left corner is to be moved.
  swResize('sw-resize', 'bottom_left_corner'),

  /// Text that can be selected (an I-beam).
  text('text', 'xterm'),

  /// Vertical text that can be selected.
  verticalText('vertical-text'),

  /// The left (west) edge is to be moved.
  wResize('w-resize', 'left_side'),

  /// The program is busy and takes no input.
  wait('wait', 'watch'),

  /// Something can be zoomed in.
  zoomIn('zoom-in', 'plus'),

  /// Something can be zoomed out.
  zoomOut('zoom-out', 'minus');

  const PointerShape(this.css, [this.x11]);

  /// Its name in OSC 22 and in CSS.
  final String css;

  /// The name of the X cursor font's shape nearest it, which xterm takes
  /// and iTerm2 shows as its macOS counterpart; iTerm2 knows `minus` for
  /// [zoomOut] as well, which the font hasn't. Null where there is none
  /// ([alias], [copy], the diagonal resizes, [verticalText]): the terminal
  /// shows its own pointer. A grabbing hand is an open one there.
  final String? x11;
}

/// How a terminal names the shapes of the mouse pointer in OSC 22
/// ([pointerShapeSequence]).
enum PointerNames {
  /// By CSS's names ([PointerShape.css]).
  css,

  /// By the X cursor font's ([PointerShape.x11]): a name the terminal
  /// doesn't know shows its own pointer.
  x11,
}

/// Returns OSC 22, which shows the mouse pointer in [shape] over the
/// terminal, by the names it knows ([names]), or as the terminal shows it
/// by itself for null.
///
/// Only some terminals show it ([pointerNamesFor]); an app sets it
/// through `TerminalStateBackend.setTerminalState`, so that it is put
/// back on the way out.
String pointerShapeSequence(
  PointerShape? shape, [
  PointerNames names = PointerNames.css,
]) {
  final name = switch (names) {
    PointerNames.css => shape?.css,
    PointerNames.x11 => shape?.x11,
  };
  return '\x1b]22;${name ?? ''}\x1b\\';
}

/// How the terminal is known to name the shapes of the mouse pointer it
/// shows by OSC 22 ([pointerShapeSequence]), from its environment and its
/// name and version as it tells them ([version], XTVERSION); null where it
/// isn't known to show them. By CSS's names kitty (0.31 on), foot (1.12
/// on), Ghostty, Rio and Konsole (26.04 on); by the X cursor font's xterm
/// (patch 367 on) and iTerm2 (3.7 on: from 3.5 it takes them, but shows
/// its own pointer while the mouse is reported, as it is to an app with
/// a [PointerShape] to show). mintty names them by Windows'
/// names, Contour knows three of them, and VTE, WezTerm, Windows Terminal,
/// Alacritty and Terminal.app show none. Not inside tmux, which drops it,
/// or GNU screen: the shape would stay over the other panes as well. A
/// name the terminal tells, then its own `TERM` and `TERM_PROGRAM`, come
/// before variables a terminal it was started from left in its
/// environment.
PointerNames? pointerNamesFor(
  Map<String, String> env, {
  String version = '',
}) {
  const css = PointerNames.css;
  const x11 = PointerNames.x11;
  final term = env['TERM'] ?? '';
  if (env.containsKey('TMUX') ||
      env.containsKey('STY') ||
      term.startsWith('tmux') ||
      term.startsWith('screen')) {
    return null;
  }
  if (version.startsWith('iTerm2 ')) {
    return _atLeast(version.substring(7), const [3, 7]) ? x11 : null;
  }
  if (version.startsWith('XTerm(')) {
    return _atLeast(version.substring(6), const [367]) ? x11 : null;
  }
  if (term == 'xterm-kitty' ||
      term == 'xterm-ghostty' ||
      term.startsWith('foot')) {
    return css;
  }
  switch (env['TERM_PROGRAM'] ?? '') {
    case 'ghostty' || 'rio':
      return css;
    case 'iTerm.app':
      final programVersion = env['TERM_PROGRAM_VERSION'] ?? '';
      return _atLeast(programVersion, const [3, 7]) ? x11 : null;
    case '':
      break;
    default:
      return null;
  }
  return env.containsKey('KITTY_WINDOW_ID') ||
          env.containsKey('GHOSTTY_RESOURCES_DIR') ||
          _number(env['KONSOLE_VERSION']) >= 260400
      ? css
      : null;
}

/// What a program's progress in the terminal's tab or taskbar shows
/// ([progressSequence]), by the number OSC 9;4 gives it ([code]).
enum ProgressState {
  /// No progress: the bar is taken away.
  none(0),

  /// A bar filled as far as the percent says.
  normal(1),

  /// The bar in the color of an error.
  error(2),

  /// Work going on that has no percent: a bar moving to and fro.
  indeterminate(3),

  /// The bar in the color of a warning, paused.
  paused(4);

  const ProgressState(this.code);

  /// Its number in OSC 9;4.
  final int code;
}

/// Returns OSC 9;4, ConEmu's, which shows the program's progress in
/// [state], with [percent] done (cut to 0…100) where given.
///
/// [ProgressState.none] and [ProgressState.indeterminate] take no percent.
String progressSequence(ProgressState state, {int? percent}) {
  final p =
      percent == null ||
          state == ProgressState.none ||
          state == ProgressState.indeterminate
      ? ''
      : ';${percent.clamp(0, 100)}';
  return '\x1b]9;4;${state.code}$p\x1b\\';
}

/// Whether the terminal is known to show a program's progress in its tab
/// or taskbar (OSC 9;4, [progressSequence]) and to take it for nothing
/// else, from its environment and its name and version as it tells them
/// ([version], XTVERSION): Windows Terminal, ConEmu, Ghostty, VTE 0.80 on
/// (GNOME Terminal, Ptyxis), Konsole 26.04 on, and by their versions
/// kitty 0.38 on, iTerm2 3.6.6 on, mintty 3.4.2 on, Rio 0.3.1 on, Contour
/// 0.7 on; tmux 3.7 on, which shows it in the terminal outside it where
/// that has it. Earlier kitty, iTerm2 and foot show an OSC 9 as a desktop
/// notification, so a terminal whose version is not known is not; foot
/// and WezTerm (but in nightly builds, and only to its Lua) show none.
bool progressReportsFor(Map<String, String> env, {String version = ''}) {
  final term = env['TERM'] ?? '';
  final programVersion = env['TERM_PROGRAM_VERSION'] ?? '';
  if (term == 'xterm-ghostty') {
    return true;
  }
  if (term == 'xterm-kitty') {
    return _kitty38(version);
  }
  if (term.startsWith('foot') || term == 'dumb') {
    return false;
  }
  switch (env['TERM_PROGRAM'] ?? '') {
    case 'ghostty':
      return true;
    case 'iTerm.app':
      return _atLeast(programVersion, const [3, 6, 6]);
    case 'tmux':
      return _atLeast(programVersion, const [3, 7]);
    case 'mintty':
      return _atLeast(programVersion, const [3, 4, 2]);
    case 'rio':
      return _atLeast(programVersion, const [0, 3, 1]);
    case 'contour':
      return _atLeast(programVersion, const [0, 7]);
    case '':
      break;
    default:
      return false;
  }
  if (env.containsKey('TMUX') ||
      env.containsKey('STY') ||
      term.startsWith('tmux') ||
      term.startsWith('screen')) {
    // a tmux of no known version, or GNU screen, which drops it
    return false;
  }
  if (env.containsKey('KITTY_WINDOW_ID')) {
    return _kitty38(version);
  }
  return env.containsKey('WT_SESSION') ||
      env.containsKey('ConEmuPID') ||
      env['ConEmuANSI'] == 'ON' ||
      env.containsKey('GHOSTTY_RESOURCES_DIR') ||
      _number(env['VTE_VERSION']) >= 8000 ||
      _number(env['KONSOLE_VERSION']) >= 260400;
}

/// Whether [version], an XTVERSION answer, is kitty's, 0.38 or later.
bool _kitty38(String version) =>
    version.startsWith('kitty(') &&
    _atLeast(version.substring(6), const [0, 38]);

/// Whether the version at the start of [version] (numbers separated by
/// dots) is [least] or later; false when it starts with no number.
bool _atLeast(String version, List<int> least) {
  final parts = RegExp(r'^\d+(\.\d+)*').stringMatch(version);
  if (parts == null) {
    return false;
  }
  final numbers = parts.split('.').map(int.parse).toList();
  for (var i = 0; i < least.length; i++) {
    final n = i < numbers.length ? numbers[i] : 0;
    if (n != least[i]) {
      return n > least[i];
    }
  }
  return true;
}

/// [value] as a number, 0 when it is none.
int _number(String? value) => int.tryParse(value ?? '') ?? 0;

/// Who puts right-to-left text in the order it reads on a terminal
/// (`TerminalInfo.bidi`).
enum BidiReordering {
  /// The app, by the Unicode Bidirectional Algorithm (UAX #9), drawing text
  /// in visual order (`TextOrder.visual`): for a terminal that shows each
  /// character in the cell it is written to, doing no bidi or told not to
  /// (explicit mode, [explicitBidiSequence]).
  app,

  /// The terminal, which reorders each row itself (implicit mode): the app
  /// draws text in logical order, as stored (`TextOrder.logical`).
  terminal,
}

/// DECRQM for BDSM, ECMA-48's bidirectional support mode (8): answered
/// `CSI 8 ; Ps $ y` ([bidiReorderingFor]).
const bidiModeQuery = '\x1b[8\$p';

/// BDSM set: implicit mode, the terminal reorders the right-to-left text
/// of each row itself, as for programs that know nothing of bidi.
const implicitBidiSequence = '\x1b[8h';

/// BDSM reset: explicit mode, the terminal shows each character in the
/// cell it is written to, for an app that orders text itself.
const explicitBidiSequence = '\x1b[8l';

/// Whether [term], a `TERM`, is a terminal's own name, set by that
/// terminal (kitty, Ghostty, foot, Alacritty, Contour, WezTerm): it comes
/// before a `TERM_PROGRAM` or other variables a terminal it was started
/// from left in its environment, as Terminal.app's `Apple_Terminal`.
bool termNamesItsOwnTerminal(String term) =>
    term == 'xterm-kitty' ||
    term == 'xterm-ghostty' ||
    term.startsWith('foot') ||
    term == 'alacritty' ||
    term == 'contour' ||
    term == 'wezterm';

/// Who puts right-to-left text in the order it reads on a terminal, by its
/// answer to [bidiModeQuery], [mode] (the Ps of `CSI 8 ; Ps $ y`, null
/// without one), and else by its environment and its name and version as
/// it tells them ([version], XTVERSION).
///
/// 1 (set) or 2 (reset): it honours BDSM, and explicit mode leaves the
/// order to the app ([bidiModeSequences]): VTE (GNOME Terminal, Ptyxis),
/// WezTerm, iTerm2 3.7.5 on, mintty. 3 (set for good): the terminal. 0
/// (not known), 4 (reset for good, iTerm2's while its right-to-left
/// support is off) or no answer: the terminal where it is known to reorder
/// rows itself with no way to stop it, Konsole (XTVERSION `Konsole`,
/// `KONSOLE_VERSION`), mlterm (XTVERSION `mlterm`, `MLTERM`), Terminal.app
/// (`TERM_PROGRAM` `Apple_Terminal`) and PuTTY (a `TERM` of `putty…`); the
/// app elsewhere: in terminals that do no bidi (xterm, kitty, foot,
/// Alacritty, Ghostty, Contour, Windows Terminal, the Linux console), and
/// inside tmux or GNU screen, which do none and pass BDSM on to no
/// terminal. A name the terminal tells, then its own `TERM` and
/// `TERM_PROGRAM`, come before variables a terminal it was started from
/// left in its environment.
BidiReordering bidiReorderingFor(
  Map<String, String> env, {
  int? mode,
  String version = '',
}) {
  const app = BidiReordering.app;
  const terminal = BidiReordering.terminal;
  switch (mode) {
    case 1 || 2:
      return app;
    case 3:
      return terminal;
  }
  final term = env['TERM'] ?? '';
  if (env.containsKey('TMUX') ||
      env.containsKey('STY') ||
      term.startsWith('tmux') ||
      term.startsWith('screen')) {
    return app;
  }
  if (version.isNotEmpty) {
    return version.startsWith('Konsole') || version.startsWith('mlterm')
        ? terminal
        : app;
  }
  if (term.startsWith('putty') || term.startsWith('mlterm')) {
    return terminal;
  }
  if (termNamesItsOwnTerminal(term)) {
    return app;
  }
  switch (env['TERM_PROGRAM'] ?? '') {
    case 'Apple_Terminal':
      return terminal;
    case '':
      break;
    default:
      return app;
  }
  return env.containsKey('KONSOLE_VERSION') || env.containsKey('MLTERM')
      ? terminal
      : app;
}

/// What puts a terminal that honours BDSM, [mode] being its answer to
/// [bidiModeQuery] (1 set, 2 reset), in the mode [bidi] needs, explicit
/// for the app and implicit for the terminal, and what puts it back; null
/// where it is in that mode already or doesn't honour BDSM.
(String, String)? bidiModeSequences(int? mode, BidiReordering bidi) =>
    switch ((mode, bidi)) {
      (1, BidiReordering.app) => (explicitBidiSequence, implicitBidiSequence),
      (2, BidiReordering.terminal) => (
        implicitBidiSequence,
        explicitBidiSequence,
      ),
      _ => null,
    };

/// Returns [sequence] wrapped so that [multiplexer] passes it on to the
/// terminal outside; [sequence] itself for [Multiplexer.none].
///
/// tmux (with `allow-passthrough on`, 3.3 and later) takes it in `DCS tmux;
/// … ST` with every ESC doubled; GNU screen in `DCS … ST` pieces of at most
/// 252 bytes of UTF-8 (older versions keep no more than 256), whole
/// characters, where ST would end the piece, so the OSCs in it end with
/// BEL. One level only: inside a multiplexer inside another the sequence is
/// lost.
String passthroughSequence(String sequence, Multiplexer multiplexer) {
  switch (multiplexer) {
    case Multiplexer.none:
      return sequence;
    case Multiplexer.tmux:
      return '\x1bPtmux;${sequence.replaceAll('\x1b', '\x1b\x1b')}\x1b\\';
    case Multiplexer.screen:
      final sb = StringBuffer();
      final piece = StringBuffer();
      var bytes = 0;
      for (final r in sequence.replaceAll('\x1b\\', '\x07').runes) {
        final n = r < 0x80
            ? 1
            : r < 0x800
            ? 2
            : r < 0x10000
            ? 3
            : 4;
        if (bytes + n > 252) {
          sb.write('\x1bP$piece\x1b\\');
          piece.clear();
          bytes = 0;
        }
        piece.writeCharCode(r);
        bytes += n;
      }
      if (piece.isNotEmpty) {
        sb.write('\x1bP$piece\x1b\\');
      }
      return sb.toString();
  }
}

/// [text] without control characters (C0, DEL, C1) and the blanks around
/// it: a line break (LF, CR LF or CR) is kept where [lines], a space
/// otherwise, as a tab is.
String _plain(String text, {required bool lines}) {
  final sb = StringBuffer();
  for (final r in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').runes) {
    if (r == 0x0A) {
      sb.write(lines ? '\n' : ' ');
    } else if (r == 0x09) {
      sb.write(' ');
    } else if (r >= 0x20 && r != 0x7F && (r < 0x80 || r > 0x9F)) {
      sb.writeCharCode(r);
    }
  }
  return sb.toString().trim();
}

/// [text] cut to at most [max] bytes of UTF-8 between graphemes, ending
/// with `…` when cut.
String _cut(String text, int max) {
  if (utf8.encode(text).length <= max) {
    return text;
  }
  var bytes = 3; // the ellipsis
  var end = 0;
  for (final (start, stop) in graphemeBoundaries(text)) {
    bytes += utf8.encode(text.substring(start, stop)).length;
    if (bytes > max) {
      break;
    }
    end = stop;
  }
  return '${text.substring(0, end)}…';
}
