/// A real terminal session: the process's own terminal (Linux, macOS,
/// Windows 10+), one a `twk shell` serves over a local socket (see
/// `socket.dart`), or one at the far end of a program's own link
/// ([Terminal.overLink]), the only one on the web; or output that takes
/// plain text only (a pipe, a file, CI: see `plain.dart`).
///
/// Responsibilities: raw input, alternate screen, capability probing,
/// resize notifications, input decoding, writing frames with backpressure,
/// recording what is read and written when asked (`TWK_TRACE_INPUT`,
/// `TWK_TRACE_OUTPUT`), and restoring the terminal on every exit path.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../graphics.dart';
import '../input/coalesce.dart';
import '../input/events.dart';
import '../input/parser.dart';
import '../platform/platform.dart';
import '../presenter.dart';
import '../style.dart';
import '../unicode/unicode.dart';
import 'link.dart';
import 'outbox.dart';
import 'plain.dart';
import 'sequences.dart';
import 'trace.dart';

// Examples can assume:
// import 'dart:convert';

/// What [Terminal] found out about the terminal as it opened it: what it
/// asked the terminal, what the terminal answered, and what its
/// environment tells.
///
/// A program reads it from [TerminalBackend.info] to decide what to show:
///
/// ```dart
/// final terminal = await Terminal.open();
/// final info = terminal.info;
/// final dark = info.brightness != Brightness.light;
/// final images = info.caps.graphics != GraphicsProtocol.none;
/// ```
///
/// A terminal that didn't answer in time ([answeredQueries] false) is
/// taken to have none of what has to be asked.
final class TerminalInfo {
  /// What a terminal was found to be; [kittyKeyboardFlags] is kept only
  /// where [kittyKeyboard], [KittyKeyboardFlags.disambiguate] where null,
  /// and [palette] is copied. The rest default to a terminal on the
  /// alternate screen that has none of what they name, the app ordering
  /// right-to-left text.
  TerminalInfo({
    required this.caps,
    required this.textMode,
    required this.ambiguousWidth,
    required this.colorMode,
    required this.foregroundRgb,
    required this.backgroundRgb,
    required this.inBandResize,
    required this.graphemeMode,
    required this.kittyKeyboard,
    required this.answeredQueries,
    int? kittyKeyboardFlags,
    this.alternateScreen = true,
    this.cursorColumn,
    this.colorSchemeReports = false,
    this.notifications = NotificationProtocol.none,
    this.multiplexer = Multiplexer.none,
    this.plain = false,
    this.pointerNames,
    this.progressReports = false,
    this.bidi = BidiReordering.app,
    this.declaredBrightness,
    Map<int, int> palette = const {},
    Map<String, String> settings = const {},
  }) : palette = Map.unmodifiable(palette),
       settings = Map.unmodifiable(settings),
       kittyKeyboardFlags = kittyKeyboard
           ? kittyKeyboardFlags ?? KittyKeyboardFlags.disambiguate
           : 0;

  /// What the frame writer ([Presenter]) may use: synchronized output,
  /// REP, margins, the image protocol, a cell's size in pixels.
  final TerminalCaps caps;

  /// How the terminal splits text into cells: [TextMode.graphemes] where
  /// it clusters graphemes (mode 2027, or known to), else
  /// [TextMode.legacy], code point by code point.
  final TextMode textMode;

  /// Columns the terminal gives East Asian Ambiguous characters (box
  /// drawing, `…`, `→`, `·`): 2 in some CJK setups. Measured by the probe
  /// when the alternate screen is used, 1 otherwise.
  final int ambiguousWidth;

  /// The colors the terminal shows, by its environment ([colorModeFor]);
  /// [ColorMode.none] for plain output.
  final ColorMode colorMode;

  /// The terminal's default text color (OSC 10), for alpha blending.
  final int? foregroundRgb;

  /// The terminal's default background (OSC 11), for alpha blending.
  final int? backgroundRgb;

  /// The first 16 palette entries the terminal told (OSC 4), RGB by index
  /// (0..15), for alpha blending ([StyleTable.setPaletteRgb]): a palette
  /// color is blended as the terminal shows it, an entry it didn't tell as
  /// xterm shows it.
  final Map<int, int> palette;

  /// The brightness the terminal's environment declares
  /// ([brightnessFor]): a guess for a terminal that doesn't tell its
  /// background, and no more than that, `COLORFGBG` being inherited (from
  /// the terminal a tmux session was started in, from before a profile
  /// changed). Not [brightness].
  final Brightness? declaredBrightness;

  /// Whether the terminal's colors are dark or light, by [backgroundRgb];
  /// null when the terminal didn't tell its background.
  Brightness? get brightness {
    final background = backgroundRgb;
    return background == null ? null : Brightness.ofRgb(background);
  }

  /// Whether the terminal reports its size as input (DEC mode 2048),
  /// which is then turned on: no signal is watched for it.
  final bool inBandResize;

  /// Whether the terminal has grapheme cluster widths (DEC mode 2027),
  /// which are then turned on.
  final bool graphemeMode;

  /// Whether the kitty keyboard protocol is supported (`CSI ? u` was
  /// answered) and enabled: the Escape key arrives as `CSI 27 u`, so a lone
  /// ESC byte starts a sequence; it counts as the Escape key only after a
  /// long pause (500 ms), in case the terminal sends a legacy ESC after
  /// all. Once one did (Konsole answers for the protocol and sends the
  /// Escape key as a lone ESC), a lone ESC waits
  /// [TerminalOptions.escapeTimeout] from then on, as without it.
  final bool kittyKeyboard;

  /// The kitty keyboard protocol's flags pushed where [kittyKeyboard]
  /// ([TerminalOptions.kittyKeyboardFlags], [KittyKeyboardFlags]), 0
  /// otherwise; [KittyKeyboardFlags.disambiguate] where not told. With
  /// [KittyKeyboardFlags.eventTypes] keys come repeated and released too
  /// ([KeyEvent.kind]). These are the flags pushed, not asked back: a
  /// terminal that implements fewer of them reports less.
  final int kittyKeyboardFlags;

  /// Whether the terminal answered the probe (its DA1, the last query) in
  /// time; false for a very old terminal, or something in between
  /// swallowing queries, and what has to be asked is then taken to be
  /// missing.
  final bool answeredQueries;

  /// Whether the app draws on the alternate screen; false in the inline
  /// mode ([TerminalOptions.alternateScreen]), where it draws in a region
  /// of the normal screen.
  final bool alternateScreen;

  /// The column the cursor was in when the terminal was opened (CPR), asked
  /// in the inline mode only: the region starts on the cursor's line when
  /// it is 0, on the next line otherwise. Null when not known.
  final int? cursorColumn;

  /// Whether the terminal reports each change of its color scheme
  /// ([ColorSchemeReport]): DEC mode 2031 is supported and enabled.
  final bool colorSchemeReports;

  /// How the terminal shows desktop notifications ([Terminal.notify]): as
  /// it declares ([TerminalDeclaration.notifications]), else Terminal.app's
  /// bell where it answers the secondary device attributes as Terminal.app
  /// (`1;95;0`, over ssh too), else by its environment
  /// ([notificationProtocolFor]).
  final NotificationProtocol notifications;

  /// The multiplexer the program runs in, by its environment
  /// ([multiplexerFor]).
  final Multiplexer multiplexer;

  /// Whether the output takes plain text only ([TerminalOptions.plain]):
  /// nothing was asked of it, so the rest is what is safe without a
  /// terminal (no capabilities or colors, graphemes, the inline region at
  /// the start of a line). The terminal writes nothing of its own, neither
  /// modes nor a title, the clipboard or notifications, only what it is
  /// given ([TerminalBackend.write]); `TwkApp` gives it no frame as it
  /// comes, only the last one as lines of text when it ends, and in the
  /// inline mode each commit's lines as they are committed.
  final bool plain;

  /// Whether the terminal is known to show the mouse pointer in the shape
  /// OSC 22 sets ([pointerShapeSequence]): where it names the shapes
  /// ([pointerNames]).
  bool get pointerShapes => pointerNames != null;

  /// How the terminal names the pointer's shapes in OSC 22; null where it
  /// isn't known to show them. As it declares
  /// ([TerminalDeclaration.pointerShapes]): by CSS's names where it shows
  /// them; else by its environment and its name and version
  /// ([pointerNamesFor]).
  final PointerNames? pointerNames;

  /// Whether the terminal is known to show a program's progress in its tab
  /// or taskbar (OSC 9;4, [progressSequence]): as it declares
  /// ([TerminalDeclaration.progressReports]), else by its environment and
  /// its version ([progressReportsFor]).
  final bool progressReports;

  /// The app's own settings the terminal sets ([settingNames]), as its
  /// environment has them: `TWK_SCREEN_READER` and `TWK_DEBUG` where the
  /// link's environment ([TerminalLink.environment]) sets them, set empty
  /// too, on a terminal of the process ([Terminal.open], whose link is
  /// its own or the `twk shell`'s it found, and [Terminal.connect]); none
  /// over a link of a program's own ([Terminal.overLink]: an SSH session,
  /// a browser's terminal), whose far end is not to turn the app's debug
  /// aids on. `TwkApp` reads them over the process's environment when it
  /// is given none (`TwkApp.environment`), so that the terminal an app is
  /// on, such as an editor's terminal, switches them for any app.
  final Map<String, String> settings;

  /// The variables of the environment a terminal sets for the app
  /// ([settings]): `TWK_SCREEN_READER` (the screen-reader mode of twk's
  /// `AppBinding`) and `TWK_DEBUG` (the debug aids, `TwkApp.debugNames`).
  /// The rest of twk's own, `TWK_LOG`'s path and the editor's command
  /// (`TWK_EDITOR`) among them, are the process's alone: a file to write
  /// and a command to run are not the terminal's to name.
  static const settingNames = {'TWK_SCREEN_READER', 'TWK_DEBUG'};

  /// The [settingNames] [environment] sets, as it sets them.
  static Map<String, String> _settingsOf(Map<String, String> environment) => {
    for (final name in settingNames)
      if (environment.containsKey(name)) name: ?environment[name],
  };

  /// Who puts right-to-left text in the order it reads: the app where the
  /// terminal does no bidi, or honours BDSM and is in explicit mode while
  /// it is open; the terminal where it reorders rows itself and can't be
  /// told not to ([bidiReorderingFor], or Terminal.app told by its
  /// secondary device attributes over ssh), and on plain output, whose reader
  /// orders each line; or what [TerminalOptions.bidi] says. `TwkApp` draws
  /// text in visual order for the app (`PipelineOwner.textOrder`), in
  /// logical order for the terminal.
  final BidiReordering bidi;

  @override
  String toString() =>
      'sync=${caps.synchronizedOutput} rep=${caps.repeatChar} '
      'margins=${caps.leftRightMargins} konsoleLines=${caps.konsoleLines} '
      'styledUnderlines=${caps.styledUnderlines} '
      'text=${textMode.name} ambiguous=$ambiguousWidth '
      'color=${colorMode.name} fg=${foregroundRgb?.toRadixString(16)} '
      'bg=${backgroundRgb?.toRadixString(16)} '
      'declared=${declaredBrightness?.name} palette=${palette.length} '
      'inBandResize=$inBandResize mode2027=$graphemeMode '
      'kittyKeyboard=$kittyKeyboard flags=$kittyKeyboardFlags '
      'answered=$answeredQueries '
      'alternateScreen=$alternateScreen cursorColumn=$cursorColumn '
      'colorSchemeReports=$colorSchemeReports '
      'notifications=${notifications.name} multiplexer=${multiplexer.name} '
      'pointerNames=${pointerNames?.name} '
      'progressReports=$progressReports '
      'bidi=${bidi.name} '
      'graphics=${caps.graphics.name} konsoleImages=${caps.konsoleImages} '
      'cell=${caps.cellPixelWidth}x${caps.cellPixelHeight}px plain=$plain';
}

/// How [Terminal] opens a terminal: the screen it draws on, the input it
/// asks for, how long it waits for answers.
///
/// The defaults suit a fullscreen app: the alternate screen, mouse reports
/// of presses, drags and the wheel, bracketed paste, focus reports and the
/// kitty keyboard protocol where the terminal has them. An app that draws
/// below the shell's prompt and stays in its history is inline:
///
/// ```dart
/// final terminal = await Terminal.open(
///   const TerminalOptions(alternateScreen: false),
/// );
/// ```
///
/// One that wants key releases too (a game, say) pushes more of the kitty
/// keyboard protocol:
///
/// ```dart
/// final terminal = await Terminal.open(
///   const TerminalOptions(
///     kittyKeyboardFlags:
///         KittyKeyboardFlags.disambiguate | KittyKeyboardFlags.eventTypes,
///   ),
/// );
/// ```
final class TerminalOptions {
  /// Options with every one at its default; asserts that
  /// [kittyKeyboardFlags] are [KittyKeyboardFlags] bits.
  const TerminalOptions({
    this.alternateScreen = true,
    this.mouse = true,
    this.mouseMotion = false,
    this.normalScreenMouse = false,
    this.bracketedPaste = true,
    this.focusEvents = true,
    this.kittyKeyboard = true,
    this.kittyKeyboardFlags = KittyKeyboardFlags.disambiguate,
    this.probeTimeout = const Duration(seconds: 1),
    this.escapeTimeout = const Duration(milliseconds: 30),
    this.pasteTimeout = const Duration(seconds: 2),
    this.graphics,
    this.plain,
    this.bidi,
  }) : assert(
         kittyKeyboardFlags >= 0 && kittyKeyboardFlags < 32,
         'not KittyKeyboardFlags bits: $kittyKeyboardFlags',
       );

  /// Whether the app draws on the alternate screen (fullscreen), the
  /// default. False is the inline mode: the app draws in a region of the
  /// normal screen, from the line the cursor is on down, which grows with
  /// its content and stays in the terminal's history when the app ends (see
  /// `TwkApp`); rows above it are never written.
  final bool alternateScreen;

  /// Whether the mouse is reported (buttons, wheel, drags) from the start,
  /// as [MouseTracking.drags]; [Terminal.mouseTracking] switches them while
  /// the terminal is open. Ignored on the normal screen ([alternateScreen]
  /// false) unless [normalScreenMouse]: in the inline mode the mouse stays
  /// the terminal's (its wheel scrolls the scrollback, its selection
  /// works), and reports would give screen rows, which an inline region
  /// doesn't know.
  final bool mouse;

  /// Whether, with [mouse], motion without a pressed button is reported
  /// too, as [MouseTracking.motion] (mode 1003; chatty). False by default.
  final bool mouseMotion;

  /// Whether the mouse is reported on the normal screen too
  /// ([alternateScreen] false), as [mouse] says and
  /// [Terminal.mouseTracking] switches them: for an app in a fixed viewport
  /// (`TwkApp.viewport`), which gets them relative to its rectangle. Off,
  /// the default, the inline mode leaves the mouse to the terminal (see
  /// [mouse]).
  final bool normalScreenMouse;

  /// Bracketed paste (mode 2004), on by default: a paste comes as one
  /// [PasteEvent] rather than as keys (a very long one as several,
  /// [InputParser.pasteLimit]). Ignored by terminals without it.
  final bool bracketedPaste;

  /// Focus reports (mode 1004), on by default: [FocusEvent]s when the
  /// terminal's window gains or loses the focus. Ignored by terminals
  /// without them.
  final bool focusEvents;

  /// Whether the kitty keyboard protocol is used, the default: asked
  /// whether the terminal has it (`CSI ? u`), [kittyKeyboardFlags] pushed
  /// (`CSI > flags u`) as the modes are entered and popped (`CSI < u`) as
  /// they are left, on the screen they were pushed on; ignored by terminals
  /// without it. False: neither asked nor pushed, whatever
  /// [kittyKeyboardFlags] says.
  final bool kittyKeyboard;

  /// The kitty keyboard protocol's flags pushed with [kittyKeyboard]
  /// ([KittyKeyboardFlags] bits), [KittyKeyboardFlags.disambiguate]
  /// among them whether or not they name it: the Escape key a sequence of
  /// its own, never a lone ESC (see [escapeTimeout]). By default that
  /// alone, and keys come as presses only. With
  /// [KittyKeyboardFlags.eventTypes] they come repeated and released too
  /// ([KeyEvent.kind]): what acts on keys then acts on presses and repeats
  /// and leaves releases alone, or a field types each letter twice.
  /// [TerminalInfo.kittyKeyboardFlags] tells what was pushed.
  final int kittyKeyboardFlags;

  /// How long the probe waits for the terminal's answers (DA1 comes last).
  /// Only a terminal that doesn't answer DA1 at all waits this long; over a
  /// slow link the answers can take a few hundred milliseconds.
  final Duration probeTimeout;

  /// How long a lone ESC (or ESC and an introducer such as `[`) waits for
  /// the rest of a sequence before it counts as the Escape key (or Alt+key).
  /// Only used without the kitty keyboard protocol, or once a terminal
  /// that has it sent the Escape key as a lone ESC all the same (see
  /// [TerminalInfo.kittyKeyboard]); a sequence whose parameters arrived
  /// waits 500 ms.
  final Duration escapeTimeout;

  /// How long a bracketed paste may go without input before it is ended
  /// without its end marker (lost on the way): until then every byte is
  /// pasted text, keys included.
  final Duration pasteTimeout;

  /// How images are shown ([TerminalCaps.graphics]); null for what the
  /// terminal declares ([TerminalDeclaration.graphics]), else what
  /// `TWK_GRAPHICS` names (`kitty`, `sixel`, `iterm2` or `none`), or else
  /// what the probe finds out ([graphicsProtocolFor]).
  final GraphicsProtocol? graphics;

  /// Whether the output takes plain text only ([TerminalInfo.plain]),
  /// where `TWK_PLAIN` says nothing ([plainAsked]: `1` or `true`, `0` or
  /// `false`). True: plain. False: never, and [Terminal.open] throws where
  /// it finds no terminal. Null, the default: plain where the environment
  /// says CI ([runsInCi]), and where [Terminal.open] finds no terminal and
  /// stdout is not one (a pipe, a file); a `twk shell` serving the project
  /// comes first there. Over a link or a shell's socket ([Terminal.overLink],
  /// [Terminal.connect]) only true makes it plain.
  final bool? plain;

  /// Who puts right-to-left text in the order it reads
  /// ([TerminalInfo.bidi]); null, the default, for what the probe finds
  /// out ([bidiReorderingFor]). A terminal that honours BDSM is put in the
  /// mode the choice needs, explicit for [BidiReordering.app] and implicit
  /// for [BidiReordering.terminal], and back in its own when it is closed
  /// or handed over ([bidiModeSequences]).
  final BidiReordering? bidi;
}

/// The colors a terminal supports, from its environment: none where
/// `NO_COLOR` is set to anything but an empty string (see no-color.org)
/// or `TERM` is `dumb`; else by `COLORTERM`, `TERM`, `TERM_PROGRAM` and
/// known terminals, [windows] for a Windows console, which takes 24-bit
/// color.
///
/// It is what [TerminalInfo.colorMode] says as [Terminal] opens, so that
/// output written beside twk, to the same terminal, is in the same colors:
///
/// ```dart
/// final mode = colorModeFor({'TERM': 'xterm', 'TERM_PROGRAM': 'WezTerm'});
/// print(mode); // ColorMode.trueColor
/// ```
ColorMode colorModeFor(Map<String, String> env, {bool windows = false}) {
  final term = env['TERM'] ?? '';
  final program = env['TERM_PROGRAM'] ?? '';
  final colorTerm = env['COLORTERM'] ?? '';
  // TERM=dumb before what a terminal it was started from left behind
  // (COLORTERM, TERM_PROGRAM): a shell in an editor
  if ((env['NO_COLOR'] ?? '').isNotEmpty || term == 'dumb') {
    return ColorMode.none;
  }
  if (colorTerm == 'truecolor' ||
      colorTerm == '24bit' ||
      env.containsKey('WT_SESSION') ||
      program == 'iTerm.app' ||
      program == 'WezTerm' ||
      program == 'ghostty' ||
      term == 'xterm-kitty' ||
      term == 'xterm-ghostty' ||
      windows) {
    return ColorMode.trueColor;
  }
  if (term.contains('256color') || program == 'Apple_Terminal') {
    return ColorMode.ansi256; // Terminal.app has no 24-bit color
  }
  return ColorMode.ansi16;
}

/// Whether the terminal shows the underline styles of SGR `4:2` to `4:5`
/// ([TerminalCaps.styledUnderlines]), by its environment: all but
/// Terminal.app, which reads `4:3` as `43`, a yellow background. A `TERM`
/// of a terminal of its own (kitty, ghostty, Alacritty, foot, WezTerm)
/// comes before a `TERM_PROGRAM` inherited from the Terminal.app it was
/// started in. Over ssh Terminal.app's `TERM_PROGRAM` is not passed on:
/// the probe tells it there by its secondary device attributes.
///
/// ```dart
/// print(styledUnderlinesFor({'TERM_PROGRAM': 'Apple_Terminal'})); // false
/// ```
bool styledUnderlinesFor(Map<String, String> env) => !_isAppleTerminal(env);

/// Whether the environment names Terminal.app: its `TERM_PROGRAM`, not
/// inherited by a terminal whose `TERM` is its own
/// ([termNamesItsOwnTerminal]) started from it.
bool _isAppleTerminal(Map<String, String> env) {
  if (env['TERM_PROGRAM'] != 'Apple_Terminal') {
    return false;
  }
  return !termNamesItsOwnTerminal(env['TERM'] ?? '');
}

/// Whether the terminal's colors are dark or light as its environment
/// declares them: `COLORFGBG`, which rxvt, Konsole and others set to the
/// palette indexes of their default text and background (`15;0`, or
/// `15;default;0`), the background's last. Dark for a background of 0 to
/// 6 or 8, light for 7 or 9 to 15, as vim reads it; null where it is
/// unset or says `default`. [TerminalInfo.declaredBrightness]: a guess,
/// what the terminal tells (OSC 11) coming first.
///
/// ```dart
/// print(brightnessFor({'COLORFGBG': '0;15'})); // Brightness.light
/// ```
Brightness? brightnessFor(Map<String, String> env) {
  final value = env['COLORFGBG'];
  if (value == null) {
    return null;
  }
  return switch (int.tryParse(value.split(';').last)) {
    final bg? when (bg >= 0 && bg <= 6) || bg == 8 => Brightness.dark,
    final bg? when bg >= 7 && bg <= 15 => Brightness.light,
    _ => null,
  };
}

/// How the terminal shows desktop notifications, from its environment: its
/// own `TERM`, then its `TERM_PROGRAM`, then the variables terminals set
/// for their programs (inherited inside tmux or screen too). A
/// `TERM_PROGRAM` of another terminal gives [NotificationProtocol.none]:
/// such variables are then those of the terminal it was started from.
/// Terminal.app (`Apple_Terminal`), which shows none of a program's, has
/// its bell rung ([NotificationProtocol.bell]); not a terminal of a `TERM`
/// of its own started from it ([termNamesItsOwnTerminal]).
NotificationProtocol notificationProtocolFor(Map<String, String> env) {
  const osc777 = NotificationProtocol.osc777;
  final term = env['TERM'] ?? '';
  if (term == 'xterm-kitty') {
    return NotificationProtocol.osc99;
  }
  if (term == 'xterm-ghostty' ||
      term.startsWith('foot') ||
      term.startsWith('rxvt-unicode')) {
    return osc777;
  }
  if (term == 'dumb') {
    return NotificationProtocol.none;
  }
  switch (env['TERM_PROGRAM'] ?? '') {
    case 'iTerm.app':
      return NotificationProtocol.osc9;
    case 'Apple_Terminal':
      return _isAppleTerminal(env)
          ? NotificationProtocol.bell
          : NotificationProtocol.none;
    case 'WezTerm' || 'ghostty':
      return osc777;
    case '' || 'tmux':
      break;
    default:
      return NotificationProtocol.none;
  }
  int version(String name) => int.tryParse(env[name] ?? '') ?? 0;
  if (env.containsKey('KITTY_WINDOW_ID')) {
    return NotificationProtocol.osc99;
  }
  if (env.containsKey('ITERM_SESSION_ID') || env['LC_TERMINAL'] == 'iTerm2') {
    return NotificationProtocol.osc9;
  }
  if (env.containsKey('WEZTERM_PANE') ||
      env.containsKey('GHOSTTY_RESOURCES_DIR') ||
      version('KONSOLE_VERSION') >= 221200 ||
      env.containsKey('WT_SESSION') ||
      version('VTE_VERSION') >= 5200) {
    return osc777;
  }
  return NotificationProtocol.none;
}

/// The multiplexer a program's output goes through, from its environment:
/// `TMUX` or `STY` in one, a `TERM` of `tmux…` or `screen…` reached from
/// one (over ssh).
Multiplexer multiplexerFor(Map<String, String> env) {
  final term = env['TERM'] ?? '';
  if (env.containsKey('TMUX')) {
    return Multiplexer.tmux;
  }
  if (env.containsKey('STY')) {
    return Multiplexer.screen;
  }
  if (term.startsWith('tmux')) {
    return Multiplexer.tmux;
  }
  if (term.startsWith('screen')) {
    return Multiplexer.screen;
  }
  return Multiplexer.none;
}

/// How the terminal shows images, from what `TWK_GRAPHICS` names, else
/// from what it answered and its environment: kitty's protocol where it
/// answered kitty's query ([kittyGraphics]); iTerm2's where its name
/// ([version], XTVERSION) or its environment says iTerm2 or WezTerm; sixel
/// where its device attributes say it has them ([sixel]). Inside tmux,
/// which answers the queries itself, sixel is tmux's own (3.4), and kitty's
/// or iTerm2's go to the terminal outside when the environment names one
/// that has it; inside GNU screen, which can't pass images on, none.
GraphicsProtocol graphicsProtocolFor(
  Map<String, String> env, {
  bool kittyGraphics = false,
  bool sixel = false,
  String version = '',
}) {
  final named = env['TWK_GRAPHICS'] ?? '';
  for (final p in GraphicsProtocol.values) {
    if (p.name == named) {
      return p;
    }
  }
  final multiplexer = multiplexerFor(env);
  if (multiplexer == Multiplexer.screen) {
    return GraphicsProtocol.none;
  }
  final program = env['TERM_PROGRAM'] ?? '';
  final iterm =
      version.startsWith('iTerm2') ||
      version.startsWith('WezTerm') ||
      program == 'iTerm.app' ||
      program == 'WezTerm' ||
      env['LC_TERMINAL'] == 'iTerm2';
  if (multiplexer == Multiplexer.tmux) {
    if (sixel) {
      return GraphicsProtocol.sixel;
    }
    if (env.containsKey('KITTY_WINDOW_ID') ||
        env.containsKey('GHOSTTY_RESOURCES_DIR')) {
      return GraphicsProtocol.kitty;
    }
    return iterm ||
            env.containsKey('ITERM_SESSION_ID') ||
            env.containsKey('WEZTERM_PANE')
        ? GraphicsProtocol.iterm2
        : GraphicsProtocol.none;
  }
  if (kittyGraphics) {
    return GraphicsProtocol.kitty;
  }
  if (iterm) {
    return GraphicsProtocol.iterm2;
  }
  return sixel ? GraphicsProtocol.sixel : GraphicsProtocol.none;
}

/// What [Terminal.open] does with [own], the process's own terminal (null
/// when stdin or stdout isn't one): opens it, or, when there is none or its
/// raw mode can't be entered ([TerminalLink.enterRaw] throws), the terminal
/// of the `twk shell` that `TWK_SHELL` in [env] names, or, where it is not
/// set, the one serving the project [directory] is in (the current one
/// when null; see `SocketLink.toShell`). Without such a shell, throws what
/// [own] threw or a [TerminalException] 'not a terminal'; a `TWK_SHELL`
/// naming no shell that listens throws a [TerminalException] saying so.
Future<Terminal> openOwnOrShell(
  TerminalLink? own,
  TerminalOptions options, [
  String? directory,
  Map<String, String> env = const {},
]) async {
  TerminalException? refused;
  if (own != null) {
    try {
      return await Terminal._open(own, options);
    } on TerminalException catch (e) {
      refused = e;
    }
  }
  final shell = await SocketLink.toShell(directory, env);
  if (shell == null) {
    throw refused ?? const TerminalException('not a terminal');
  }
  return Terminal._open(shell, options);
}

/// What [Terminal.open] does in a process of [env], whose own terminal is
/// [own] (null when stdin or stdout isn't one) and whose plain output is
/// what [plain] makes: plain when `TWK_PLAIN` ([plainAsked]), or else
/// [TerminalOptions.plain], says true, or neither says anything and [env]
/// says CI ([runsInCi]); otherwise [openOwnOrShell] in [directory] with
/// [env] (its `TWK_SHELL`), and
/// when that finds no terminal, [outputIsTerminal] is false (stdout is a
/// pipe or a file) and neither says false, plain after all.
Future<Terminal> openForProcess(
  TerminalLink? own,
  TerminalLink Function() plain,
  TerminalOptions options, {
  required Map<String, String> env,
  required bool outputIsTerminal,
  String? directory,
}) async {
  final asked = plainAsked(env) ?? options.plain;
  if (asked ?? runsInCi(env)) {
    return Terminal._open(plain(), options, plain: true);
  }
  try {
    return await openOwnOrShell(own, options, directory, env);
  } on TerminalException {
    if (asked != null || outputIsTerminal) {
      rethrow;
    }
  }
  return Terminal._open(plain(), options, plain: true);
}

/// What the frame loop (`TwkApp`) needs from a terminal: [Terminal] is the
/// real one; a test can stand in with a fake.
abstract interface class TerminalBackend {
  /// What the terminal was found to be as it opened.
  TerminalInfo get info;

  /// The number of columns, kept up to date from resize events.
  int get width;

  /// The number of rows, kept up to date from resize events.
  int get height;

  /// Decoded input, plus a [ResizeEvent] each time the size changes.
  Stream<InputEvent> get events;

  /// Writes one frame. The bytes are copied: the caller may reuse its
  /// buffer as soon as this returns.
  void write(Uint8List bytes);

  /// Completes when everything written so far reached the OS.
  Future<void> flush();

  /// Restores the terminal. Safe to call more than once.
  Future<void> close();
}

/// A [TerminalBackend] that can hand the terminal to another program and
/// take it back ([Terminal]); `TwkApp.suspend` does both around the other
/// program.
abstract interface class SuspendableBackend implements TerminalBackend {
  /// Hands the terminal back as it was before it was taken, keeping input
  /// for [resume]: what the other program reads is its own.
  Future<void> suspend();

  /// Takes the terminal back after [suspend]; what the screen shows is then
  /// unknown. In the inline mode the cursor is left at the start of a line
  /// below whatever was printed meanwhile, where the region starts again.
  Future<void> resume();
}

/// A [TerminalBackend] that keeps state an app set on the terminal beyond
/// its screen (the pointer's shape, the progress in its tab) and puts it
/// back as it was on every way out, as it does the modes it opened with:
/// [Terminal], `HeadlessTerminal`.
abstract interface class TerminalStateBackend implements TerminalBackend {
  /// Writes [sequence], which sets the state [key] names, and keeps
  /// [restore], which puts it back as it was: written when the terminal is
  /// closed, by whatever closes it, or handed to another program, and
  /// [sequence] again when it is taken back. While handed over, [sequence]
  /// waits for that. With [refresh], [sequence] is written again each time
  /// that long has passed since, for a terminal that takes a state away
  /// when it isn't told again (Ghostty drops a progress after 15 s). Both
  /// are ASCII. Ignored once closed, and for plain output
  /// ([TerminalInfo.plain]).
  void setTerminalState(
    Object key,
    String sequence,
    String restore, {
    Duration? refresh,
  });

  /// Writes what puts the state [key] names back as it was
  /// ([setTerminalState]), and forgets it; nothing when it isn't set.
  void restoreTerminalState(Object key);
}

/// A [TerminalBackend] whose mouse reports can be switched while it is
/// open ([Terminal], `HeadlessTerminal`), so that an app has on only what
/// it uses: while it uses none, the terminal's own selection and wheel
/// work.
abstract interface class MouseTrackingBackend implements TerminalBackend {
  /// What the terminal reports of the mouse; [MouseTracking.off] on the
  /// normal screen, unless [TerminalOptions.normalScreenMouse].
  MouseTracking get mouseTracking;

  /// Switches the reports to [tracking], writing the modes that do it
  /// ([mouseTrackingSequence]). Ignored on the normal screen unless
  /// [TerminalOptions.normalScreenMouse] (see [TerminalOptions.mouse]),
  /// and once closed.
  set mouseTracking(MouseTracking tracking);
}

/// A [TerminalBackend] that sets the title of the terminal's window or tab
/// and shows desktop notifications ([Terminal], `HeadlessTerminal`). A
/// backend that wraps a terminal implements it to pass both on; twk's
/// `WindowTitle` and `AppBinding.notify` do nothing on a backend without
/// it.
abstract interface class WindowBackend implements TerminalBackend {
  /// Sets the title of the terminal's window or tab to [title]. Ignored
  /// once closed.
  void setTitle(String title);

  /// Shows a desktop notification of [title] and [body] where the terminal
  /// is known to show one ([TerminalInfo.notifications]); nothing
  /// elsewhere, and once closed.
  void notify(String title, String body);
}

/// A terminal a program draws on and reads input from, opened in raw mode,
/// asked what it can do, and put back as it was however the program ends.
///
/// [open] opens the process's own terminal (or a `twk shell`'s, or plain
/// output where there is none); [connect], the terminal a `twk shell`
/// serves; [overLink], one at the far end of a [TerminalLink] (an SSH
/// channel, a terminal in a browser). Opening one enters raw mode, probes
/// the terminal ([info]) and turns its modes on ([options]). [events]
/// then delivers what is typed and the size's changes, [write] and
/// [flush] take frames, and [close] restores the terminal; opened with
/// [open] or [connect], it is restored also when SIGTERM ends the process.
///
/// `TwkApp` runs the frame loop on one; a program can use it alone too:
///
/// ```dart
/// Future<void> main() async {
///   final terminal = await Terminal.open();
///   try {
///     terminal.write(utf8.encode('Press a key'));
///     await terminal.flush();
///     await terminal.events.firstWhere((e) => e is KeyEvent);
///   } finally {
///     await terminal.close();
///   }
/// }
/// ```
///
/// See also:
///
///  * `HeadlessTerminal`, a terminal in memory for tests.
///  * [TerminalOptions], what opening one turns on.
final class Terminal
    implements
        SuspendableBackend,
        MouseTrackingBackend,
        TerminalStateBackend,
        WindowBackend {
  Terminal._(
    this.options,
    this.info,
    this._parser,
    this._link,
    this._input,
    this._signals,
    this._ofProcess, [
    this._inputTrace,
    this._outputTrace,
  ]) : _out = _outbox(_link, _outputTrace);

  /// How long a sequence that has surely started (or, with the kitty
  /// protocol, any ESC) may wait for the rest of its bytes.
  static const _longEscapeTimeout = Duration(milliseconds: 500);

  /// What the terminal was opened with.
  final TerminalOptions options;

  @override
  final TerminalInfo info;
  final InputParser _parser;
  final TerminalLink _link;
  final StreamSubscription<List<int>> _input;
  final List<StreamSubscription<void>> _signals;

  /// Opened with [open] or [connect]: the process's signals are watched
  /// and [suspend] hands the terminal to another program of the process.
  final bool _ofProcess;

  /// Whether the shell the process was started from has the terminal,
  /// with job control, while the process is stopped ([stopForShell]): the
  /// process's own terminal (stdin and stdout, [open]) on a POSIX system,
  /// not plain output, nor a terminal over a link or a socket ([connect]),
  /// whose shell, where there is one, doesn't run this process.
  bool get stopsForShell =>
      _ofProcess && !isWindows && !info.plain && isOwnTerminal(_link);

  /// Where what is read and what is written are recorded
  /// (`TWK_TRACE_INPUT`, `TWK_TRACE_OUTPUT`); null when not asked for.
  final TraceWriter? _inputTrace;
  final TraceWriter? _outputTrace;

  final _events = StreamController<InputEvent>();
  Timer? _escTimer;
  Timer? _pasteTimer;
  StreamSubscription<void>? _resizes;
  var _closed = false;

  @override
  var width = 80;
  @override
  var height = 24;

  /// Decoded input, plus [ResizeEvent]s from any resize source.
  @override
  Stream<InputEvent> get events => _events.stream;

  /// Opens the terminal: raw mode, probe, modes on. Throws
  /// [TerminalException] when stdin/stdout are not a terminal and the
  /// output is not plain text either (see below). If anything
  /// fails after raw mode was entered (e.g. stdout is gone), the console
  /// modes are restored before the error is rethrown.
  ///
  /// When stdin or stdout is not a terminal (the app was started from an
  /// IDE, or with stdin from /dev/null, whose raw mode can't be entered)
  /// and a `twk shell` serves the project the current directory is in (its
  /// address file `.dart_tool/twk/shell`, see [LocalAddress]), the terminal
  /// is that shell's, as with [connect]. The environment variable
  /// `TWK_SHELL` ([LocalAddress.shellVariable]), when set, names the shell
  /// instead (`unix:<path>#<token>` or `tcp:<host>:<port>#<token>`, what
  /// [LocalAddress.toVariable] writes): the one an editor started the app
  /// for, the project's address file then not read. A `TWK_SHELL` where
  /// nobody listens is a [TerminalException], which plain output (below)
  /// takes the place of as of a missing shell.
  ///
  /// Where the output takes plain text only ([TerminalOptions.plain]: in
  /// CI, or stdout a pipe or a file with no shell to give way to) nothing
  /// of that is done: the terminal writes plain text to stdout, at a fixed
  /// size (`COLUMNS` x `LINES`, else 80 x 24), and reads stdin only where
  /// it is a terminal, as that hands it on (see [TerminalInfo.plain]).
  /// SIGINT is Ctrl+C and SIGTERM ends the process, as on a terminal.
  ///
  /// With `TWK_TRACE_INPUT` or `TWK_TRACE_OUTPUT` set to a path, every read
  /// or every write from the probe on is recorded in that file, with when
  /// it happened (see [TraceWriter]); a path that can't be written fails
  /// here, before raw mode.
  ///
  /// On the web, which has neither, throws [UnsupportedError]: a terminal
  /// there is one over a link ([overLink]).
  ///
  /// ```dart
  /// final terminal = await Terminal.open();
  /// try {
  ///   final app = TwkApp(terminal);
  ///   // ... app.run(root, onEvent)
  /// } finally {
  ///   await terminal.close();
  /// }
  /// ```
  static Future<Terminal> open([
    TerminalOptions options = const TerminalOptions(),
  ]) => openForProcess(
    ownTerminalLink(),
    plainStdio,
    options,
    env: environment,
    outputIsTerminal: outputIsTerminal,
  );

  /// Opens the terminal the `twk shell` at [address] serves (see
  /// `TerminalShell`): everything [open] does, over the socket. The shell
  /// is told what puts the terminal back, and writes it if this process
  /// goes away without restoring it. When the shell goes away, [events]
  /// get a [TerminalException]. Throws `SocketException` when nobody
  /// listens at [address], [TerminalException] when the shell refuses,
  /// [UnsupportedError] on the web. Plain only when
  /// [TerminalOptions.plain] is true.
  static Future<Terminal> connect(
    LocalAddress address, [
    TerminalOptions options = const TerminalOptions(),
  ]) async => _open(
    await SocketLink.connect(address),
    options,
    plain: options.plain ?? false,
  );

  /// Opens the terminal at the far end of [link] (an SSH channel, a
  /// terminal in a browser): everything [open] does, over the link, but
  /// none of what belongs to this process, which may serve many such
  /// terminals. No signals are watched (Ctrl+C comes as a key over the
  /// link), [suspend] throws [UnsupportedError], and nothing is recorded
  /// for `TWK_TRACE_INPUT` or `TWK_TRACE_OUTPUT`. When the link's input
  /// ends with an error (the far end went away), [events] get it. If
  /// opening fails, the link is restored and closed before the error is
  /// rethrown. Plain (an SSH channel without a pseudo-terminal) only when
  /// [TerminalOptions.plain] is true.
  ///
  /// A server that serves an app to each terminal that connects opens one
  /// per link, and closes it when the app is done:
  ///
  /// ```dart
  /// Future<void> serve(TerminalLink link) async {
  ///   final terminal = await Terminal.overLink(link);
  ///   try {
  ///     await terminal.events.firstWhere((e) => e is KeyEvent);
  ///   } finally {
  ///     await terminal.close();
  ///   }
  /// }
  /// ```
  static Future<Terminal> overLink(
    TerminalLink link, [
    TerminalOptions options = const TerminalOptions(),
  ]) => _open(
    link,
    options,
    ofProcess: false,
    plain: options.plain ?? false,
  );

  /// Opens the terminal over [link]; [plain], as plain output
  /// ([TerminalInfo.plain]): no raw mode, no probe, no modes.
  static Future<Terminal> _open(
    TerminalLink link,
    TerminalOptions options, {
    bool ofProcess = true,
    bool plain = false,
  }) async {
    // The process's signals are watched before raw mode is entered, but
    // not over a program's own link. Until the terminal exists, Ctrl+C
    // goes to the probe's early input and SIGTERM only restores the
    // console.
    Terminal? t;
    var raw = false;
    final early = <InputEvent>[];
    final signals = ofProcess
        ? _watchSignals(
            (e) {
              final term = t;
              if (term == null) {
                early.add(e);
              } else if (!term._suspended) {
                // while suspended Ctrl+C is the other program's
                term._events.add(e);
              }
            },
            () async {
              final term = t;
              if (term != null) {
                await term.close();
              } else if (raw) {
                link.restore();
              }
            },
          )
        : const <StreamSubscription<void>>[];
    StreamSubscription<List<int>>? sub;
    TraceWriter? inputTrace;
    TraceWriter? outputTrace;
    try {
      // the traces' paths are the process's: one file for all terminals
      final env = ofProcess ? environment : const <String, String>{};
      // one clock: reads and writes on one time line
      final clock = Stopwatch()..start();
      TraceWriter? trace(String name, TraceDirection direction) {
        final path = env[name] ?? '';
        return path.isEmpty
            ? null
            : TraceWriter.open(
                path,
                direction,
                link.columns,
                link.lines,
                clock: clock,
              );
      }

      inputTrace = trace('TWK_TRACE_INPUT', TraceDirection.input);
      outputTrace = trace('TWK_TRACE_OUTPUT', TraceDirection.output);
      if (!plain) {
        link.enterRaw();
        raw = true;
      }
      // one subscription for the probe and the session: input that arrives
      // while switching from one to the other can't be lost
      sub = link.input.listen(null);
      final parser = InputParser()
        ..backspaceSendsCtrlH = link.eraseChar == 0x08;
      // a link of the program's own sets none of the app's settings
      final settings = ofProcess
          ? TerminalInfo._settingsOf(link.environment)
          : const <String, String>{};
      final (info, bidiMode) = plain
          ? (_plainInfo(options, settings), null)
          : await _probe(
              link,
              parser,
              sub,
              options,
              early,
              inputTrace,
              outputTrace,
              settings,
            );
      final term = t = Terminal._(
        options,
        info,
        parser,
        link,
        sub,
        signals,
        ofProcess,
        inputTrace,
        outputTrace,
      );
      if (plain) {
        return term
          .._adoptInput(early)
          .._watchResize();
      }
      // BDSM goes with the states: put back on every way out, and set
      // again on resume
      if (bidiModeSequences(bidiMode, info.bidi) case final bdsm?) {
        term._states[_bidiMode] = bdsm;
      }
      return term
        .._adoptInput(early)
        .._enterModes()
        .._watchResize();
    } on Object {
      final term = t;
      if (term != null) {
        try {
          await term.close();
        } on Object {
          // the original error is the one worth reporting
        }
      } else {
        for (final s in signals) {
          await s.cancel();
        }
        if (raw) {
          link.restore();
        }
        await sub?.cancel();
        await _closeTraces(inputTrace, outputTrace);
        await link.close();
      }
      rethrow;
    }
  }

  /// Ctrl+C typed while terminal-generated signals are on, or SIGINT sent
  /// from outside (a CTRL_C_EVENT on Windows), becomes a key, so the app
  /// decides what it means. SIGTERM, or on Windows the console being closed
  /// (SIGHUP), restores the terminal and exits. Windows' Ctrl+Break can't
  /// be watched from Dart: it ends the process without the restore.
  static List<StreamSubscription<void>> _watchSignals(
    void Function(InputEvent e) interrupt,
    Future<void> Function() terminate,
  ) => watchSignals(
    () => interrupt(
      const KeyEvent(KeyCode.char, char: 'c', modifiers: Mod.ctrl),
    ),
    terminate,
  );

  // ------------------------------------------------------------- probing --

  /// What plain output is taken for, asked nothing (see
  /// [TerminalInfo.plain]).
  static TerminalInfo _plainInfo(
    TerminalOptions o,
    Map<String, String> settings,
  ) => TerminalInfo(
    caps: const TerminalCaps(synchronizedOutput: false),
    textMode: TextMode.graphemes,
    ambiguousWidth: 1,
    colorMode: ColorMode.none,
    foregroundRgb: null,
    backgroundRgb: null,
    inBandResize: false,
    graphemeMode: false,
    kittyKeyboard: false,
    answeredQueries: false,
    alternateScreen: o.alternateScreen,
    cursorColumn: o.alternateScreen ? null : 0,
    plain: true,
    bidi: o.bidi ?? BidiReordering.terminal,
    settings: settings,
  );

  /// The probe's [queries] on the alternate screen, inside a synchronized
  /// update, then U+2500 drawn at the home position and the cursor asked
  /// where it went: what the terminal shows of a query it doesn't know is
  /// left on a screen that is let go.
  static String _onAlternateScreen(String queries) =>
      '\x1b[?2026h\x1b[?1049h$queries'
      '\x1b[H\u2500\x1b[6n\x1b[?1049l\x1b[?2026l';

  /// The probe's [queries] inline: where the cursor is asked (the region's
  /// column), it is kept (DECSC), and the queries go to the alternate
  /// screen, inside a synchronized update, before it is asked again where
  /// it is: where the terminal has no alternate screen and showed some of
  /// them, it moved ([_putBack]).
  static String _inPlace(String queries) =>
      '\x1b[6n\x1b7\x1b[?2026h\x1b[?1049h$queries'
      '\x1b[?1049l\x1b[?2026l\x1b[6n';

  /// The cursor put back where [_inPlace] kept it (DECRC), and what the
  /// terminal [shown] of its queries erased to the end of the line (EL):
  /// nothing erased where it showed nothing, a fixed viewport writing
  /// nothing outside it.
  static String _putBack({required bool shown}) =>
      '\x1b8${shown ? '\x1b[K' : ''}';

  /// Queries the terminal; what the user types meanwhile goes to [early].
  /// Returns what it found and its answer about BDSM ([bidiModeQuery]),
  /// null without one.
  static Future<(TerminalInfo, int?)> _probe(
    TerminalLink link,
    InputParser parser,
    StreamSubscription<List<int>> input,
    TerminalOptions o,
    List<InputEvent> early,
    TraceWriter? inputTrace,
    TraceWriter? outputTrace,
    Map<String, String> settings,
  ) async {
    final modes = <int, ModeReport>{};
    int? fg;
    int? bg;
    final palette = <int, int>{};
    var kitty = false;
    var ambiguous = 1;
    int? column;
    int? shownTo;
    var attributes = const <int>[];
    var kittyGraphics = false;
    var version = '';
    var cellWidth = 0;
    var cellHeight = 0;
    int? bidiMode;
    var secondary = const <int>[];
    // the queries, all in one write, which the device attributes end
    final round = Completer<bool>()..future.ignore();
    void fail(Object e, StackTrace st) {
      if (!round.isCompleted) {
        round.completeError(e, st);
      }
    }

    input
      ..onData((bytes) {
        inputTrace?.add(bytes);
        final List<InputEvent> events;
        try {
          events = parser.feed(bytes);
        } on Object catch (e, st) {
          // a stream callback: an error here would escape open()'s try and
          // kill the process with the console still raw
          fail(e, st);
          return;
        }
        for (final e in events) {
          switch (e) {
            case ModeReport(:final mode):
              modes[mode] = e;
            case ColorReport(:final which, :final rgb) when which == 10:
              fg = rgb;
            case ColorReport(:final which, :final rgb) when which == 11:
              bg = rgb;
            case ColorReport(:final which, :final rgb, :final index)
                when which == 4:
              if (index < 16) {
                palette[index] = rgb;
              }
            case KeyboardFlagsReport():
              kitty = true;
            case CursorReport(:final x):
              if (o.alternateScreen) {
                ambiguous = x >= 2 ? 2 : 1;
              } else if (column == null) {
                column = x;
              } else {
                shownTo = x; // after the queries asked in place
              }
            case UnknownSequence(:final bytes) when _isProbeReply(bytes):
              final s = String.fromCharCodes(bytes);
              if (s.startsWith('\x1b_G')) {
                kittyGraphics = s.contains(';OK');
              } else if (s.startsWith('\x1bP>|')) {
                version = s.substring(4).replaceFirst(_stringEnd, '');
              } else if (_bidiModeReply.firstMatch(s) case final m?) {
                bidiMode = int.parse(m[1]!);
              } else if (_secondaryReply.firstMatch(s) case final m?) {
                secondary = [
                  for (final p in m[1]!.split(';')) int.tryParse(p) ?? 0,
                ];
              } else {
                final m = _cellSizeReply.firstMatch(s)!;
                cellHeight = int.parse(m[1]!);
                cellWidth = int.parse(m[2]!);
              }
            case DeviceAttributes(:final params):
              attributes = params;
              if (!round.isCompleted) {
                round.complete(true);
              }
            default:
              early.add(e); // the user typed during the probe
          }
        }
      })
      ..onError(fail); // the shell went away
    // The queries are asked where they leave no trace (a terminal that
    // doesn't know one may print it: Terminal.app prints the last byte of
    // a DECRQM and the body of kitty's graphics query, GNU screen the
    // DECRQM's): on the alternate screen, inside a synchronized update (no
    // flash where that is supported), all in one write, answered in one
    // round trip, as fish asks its own. Full screen, the ambiguous width
    // is then measured by drawing U+2500 at the home position and asking
    // where the cursor went (CSI 6 n). Inline, where the cursor is is
    // asked first, on the normal screen (the region starts on a line of
    // its own), and again once the alternate screen is let go: a terminal
    // without one (GNU screen without `altscreen on`, the Linux console)
    // moved it showing a query, whose cells on its line are then erased.
    // GNU screen, whose alternate screen may be off, is asked no DECRQM,
    // which it prints. Among the queries
    // are a cell's size in pixels, the secondary device attributes (DA2,
    // by which Terminal.app is told over ssh too: `1;95;0`) and, unless the
    // protocol images are shown with is given, the graphics query and the
    // terminal's name and version (XTVERSION), not in a multiplexer, which
    // answers them itself; sixel comes with the device attributes (DA1,
    // last).
    final env = link.environment;
    // what the terminal declares comes before the guess by its name
    final declared = link is DeclaringLink
        ? link.declaration
        : const TerminalDeclaration();
    final detect =
        o.graphics == null &&
        declared.graphics == null &&
        !GraphicsProtocol.values.any((p) => p.name == env['TWK_GRAPHICS']);
    final askName = detect && multiplexerFor(env) == Multiplexer.none;
    final term = env['TERM'] ?? '';
    final screenLike = term.startsWith('screen') || env.containsKey('STY');
    // what Terminal.app prints of them stays on the alternate screen:
    // asked of it too, as of a terminal started from it, which keeps its
    // TERM_PROGRAM
    final asked =
        '${screenLike ? '' : _modeQueries}'
        '\x1b]10;?\x1b\\\x1b]11;?\x1b\\$_paletteQuery'
        '${o.kittyKeyboard ? '\x1b[?u' : ''}'
        '\x1b[16t${askName ? _kittyGraphicsQuery : ''}'
        '${askName ? '\x1b[>0q' : ''}'
        // the Linux console may take it for DA1
        '${term == 'linux' ? '' : '\x1b[>c'}';
    // inline, where the cursor is before the queries and after them
    parser.cursorReportsExpected = o.alternateScreen ? 1 : 2;
    final bytes = utf8.encode(
      '${o.alternateScreen ? _onAlternateScreen(asked) : _inPlace(asked)}'
      '\x1b[c',
    );
    link.add(bytes);
    outputTrace?.add(bytes);
    await link.flush();
    final answered = await round.future.timeout(
      o.probeTimeout,
      onTimeout: () => false,
    );
    if (!o.alternateScreen) {
      final back = utf8.encode(
        _putBack(shown: shownTo != null && shownTo != column),
      );
      link.add(back);
      outputTrace?.add(back);
      await link.flush();
    }
    if (answered) {
      // a terminal that ignores CSI 6 n: Shift+F3 must stay a key
      parser.expectCursorReport = false;
    }

    bool supported(int mode) => modes[mode]?.supported ?? false;
    final program = env['TERM_PROGRAM'] ?? '';

    final color = colorModeFor(env, windows: link.windows);

    // Grapheme clustering: announced via mode 2027, or known terminals that
    // cluster without it.
    final graphemes =
        supported(2027) ||
        term == 'xterm-kitty' ||
        env.containsKey('WT_SESSION') ||
        program == 'WezTerm';

    // REP (CSI n b) has no capability query; enable it only for terminals
    // that declare it, or are known to implement it.
    final vte = int.tryParse(env['VTE_VERSION'] ?? '') ?? 0;
    final repeatChar =
        declared.repeatChar ??
        (!screenLike &&
            !env.containsKey('TMUX') &&
            (term == 'xterm-kitty' ||
                term == 'xterm-ghostty' ||
                term.startsWith('foot') ||
                term == 'alacritty' ||
                program == 'WezTerm' ||
                program == 'ghostty' ||
                env.containsKey('WT_SESSION') ||
                env.containsKey('XTERM_VERSION') ||
                vte >= 6200));
    // the first attribute is the conformance level; 4 is sixel
    final sixel = attributes.skip(1).contains(4);
    final multiplexer = multiplexerFor(env);
    // Konsole's lines and its images come with Konsole itself
    final konsole = konsoleLinesFor(env, version: version);
    // The environment as the terminal tells it by its secondary device
    // attributes (as vim tells Terminal.app, `1;95;0`): Terminal.app's
    // TERM_PROGRAM where it answers so, also over ssh, which doesn't pass
    // it on; none where another answers, a terminal started from
    // Terminal.app that keeps it (xterm, `41;…`). Not through a
    // multiplexer, which answers them itself.
    final told = _toldEnvironment(
      env,
      multiplexer == Multiplexer.none ? secondary : const [],
    );
    final apple = _isAppleTerminal(told);
    // a terminal that declares it shows the shapes is twk's, which names
    // them by CSS's names
    final pointerNames = switch (declared.pointerShapes) {
      true => PointerNames.css,
      false => null,
      null => pointerNamesFor(told, version: version),
    };
    final graphics =
        o.graphics ??
        declared.graphics ??
        graphicsProtocolFor(
          env,
          kittyGraphics: kittyGraphics,
          sixel: sixel,
          version: version,
        );
    final info = TerminalInfo(
      caps: TerminalCaps(
        synchronizedOutput: supported(2026),
        // GNU screen without `defbce on` erases with the default background
        backgroundColorErase: !screenLike,
        repeatChar: repeatChar,
        // Terminal.app misreads 4:3: a plain underline it shows
        styledUnderlines:
            declared.styledUnderlines ?? styledUnderlinesFor(told),
        // Terminal.app's DCH shifts a line only up to where the cursor
        // last jumped and drops the background an EL gave the rest of it:
        // its cells are written again instead, which costs bytes, never
        // cells
        insertDelete: !(apple && multiplexer == Multiplexer.none),
        konsoleLines: konsole,
        konsoleImages: konsole,
        leftRightMargins: supported(69) && !screenLike,
        graphics: graphics,
        // tmux 3.4 shows sixel itself
        graphicsMultiplexer:
            graphics == GraphicsProtocol.sixel &&
                multiplexer == Multiplexer.tmux &&
                sixel
            ? Multiplexer.none
            : multiplexer,
        cellPixelWidth: cellWidth,
        cellPixelHeight: cellHeight,
      ),
      textMode: graphemes ? TextMode.graphemes : TextMode.legacy,
      ambiguousWidth: ambiguous,
      colorMode: color,
      foregroundRgb: fg,
      backgroundRgb: bg,
      palette: palette,
      inBandResize: supported(2048),
      graphemeMode: supported(2027),
      kittyKeyboard: kitty,
      kittyKeyboardFlags: _kittyFlags(o),
      answeredQueries: answered,
      alternateScreen: o.alternateScreen,
      cursorColumn: column,
      colorSchemeReports: supported(2031),
      declaredBrightness: brightnessFor(env),
      notifications: declared.notifications ?? notificationProtocolFor(told),
      multiplexer: multiplexer,
      pointerNames: pointerNames,
      progressReports:
          declared.progressReports ??
          progressReportsFor(told, version: version),
      bidi: o.bidi ?? bidiReorderingFor(told, mode: bidiMode, version: version),
      settings: settings,
    );
    return (info, bidiMode);
  }

  /// OSC 4 for the 16 colors a palette color (`Color.blue` and kin) is
  /// shown in, in one sequence (xterm's form): each entry is answered on
  /// its own, before DA1, an entry the terminal doesn't know not at all.
  static const _paletteQuery =
      '\x1b]4;0;?;1;?;2;?;3;?;4;?;5;?;6;?;7;?;'
      '8;?;9;?;10;?;11;?;12;?;13;?;14;?;15;?\x1b\\';

  /// DECRQM for the modes the probe asks about: synchronized output, the
  /// grapheme mode, in-band resizes, left and right margins, color scheme
  /// reports, and BDSM.
  static const _modeQueries =
      '\x1b[?2026\$p\x1b[?2027\$p\x1b[?2048\$p\x1b[?69\$p'
      '\x1b[?2031\$p$bidiModeQuery';

  /// kitty's graphics query: a 1x1 image it would show, answered with
  /// `APC G i=31 ; OK ST` where the protocol is there.
  static const _kittyGraphicsQuery =
      '\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\';

  /// What ends a string sequence: ST or BEL.
  static final _stringEnd = RegExp(r'(\x1b\\|\x07)$');

  /// `CSI 6 ; height ; width t`: a cell's size in pixels.
  static final _cellSizeReply = RegExp(r'^\x1b\[6;(\d+);(\d+)t$');

  /// `CSI 8 ; Ps $ y`: the answer about BDSM ([bidiModeQuery]).
  static final _bidiModeReply = RegExp(r'^\x1b\[8;(\d+)\$y$');

  /// `CSI > Pp ; Pv ; Pc c`: the secondary device attributes (DA2), the
  /// terminal's kind, version and keyboard.
  static final _secondaryReply = RegExp(r'^\x1b\[>([\d;]*)c$');

  /// What [_states] keeps BDSM under.
  static final _bidiMode = Object();

  /// A reply to one of the probe's queries the input parser doesn't know:
  /// kitty's graphics query, XTVERSION (`DCS > | name ST`), the cell size,
  /// BDSM.
  /// [env] as the terminal's secondary device attributes, [secondary]
  /// (none for no answer), tell it: Terminal.app's `TERM_PROGRAM` where
  /// they are Terminal.app's, without it where they are another's.
  static Map<String, String> _toldEnvironment(
    Map<String, String> env,
    List<int> secondary,
  ) {
    if (secondary.isEmpty) {
      return env;
    }
    final apple =
        secondary.length == 3 &&
        secondary[0] == 1 &&
        secondary[1] == 95 &&
        secondary[2] == 0;
    final named = env['TERM_PROGRAM'] == 'Apple_Terminal';
    if (apple == named) {
      return env;
    }
    return apple
        ? {...env, 'TERM_PROGRAM': 'Apple_Terminal'}
        : ({...env}
            ..remove('TERM_PROGRAM')
            ..remove('TERM_PROGRAM_VERSION'));
  }

  static bool _isProbeReply(List<int> bytes) {
    final s = String.fromCharCodes(bytes);
    return s.startsWith('\x1b_G') ||
        s.startsWith('\x1bP>|') ||
        _cellSizeReply.hasMatch(s) ||
        _bidiModeReply.hasMatch(s) ||
        _secondaryReply.hasMatch(s);
  }

  // --------------------------------------------------------------- modes --

  /// The kitty keyboard flags pushed ([TerminalOptions.kittyKeyboardFlags]):
  /// those asked for, always with disambiguation.
  static int _kittyFlags(TerminalOptions o) =>
      o.kittyKeyboardFlags | KittyKeyboardFlags.disambiguate;

  /// The mouse may be reported on this screen (see
  /// [TerminalOptions.normalScreenMouse]).
  bool get _mouseScreen => options.alternateScreen || options.normalScreenMouse;

  late MouseTracking _mouseTracking =
      options.mouse && _mouseScreen && !info.plain
      ? (options.mouseMotion ? MouseTracking.motion : MouseTracking.drags)
      : MouseTracking.off;

  /// Starts as [TerminalOptions.mouse] and [TerminalOptions.mouseMotion]
  /// say; [MouseTracking.off] for plain output, and stays so. While
  /// suspended ([suspend]) a switch is written by [resume].
  @override
  MouseTracking get mouseTracking => _mouseTracking;

  @override
  set mouseTracking(MouseTracking tracking) {
    final from = _mouseTracking;
    if (_closed || !_mouseScreen || info.plain || tracking == from) {
      return;
    }
    _mouseTracking = tracking;
    if (!_suspended) {
      _writeString(mouseTrackingSequence(from, tracking));
      _tellLost();
    }
  }

  void _enterModes() {
    final o = options;
    final sb = StringBuffer();
    if (o.alternateScreen) {
      sb.write('\x1b[?1049h');
    }
    sb.write('\x1b[?25l\x1b]8;;\x1b\\'); // no hyperlink open
    if (o.alternateScreen) {
      sb.write('\x1b[2J'); // the inline region erases only its own rows
    }
    sb.write(mouseTrackingSequence(MouseTracking.off, _mouseTracking));
    if (o.bracketedPaste) {
      sb.write('\x1b[?2004h');
    }
    if (o.focusEvents) {
      sb.write('\x1b[?1004h');
    }
    if (o.kittyKeyboard) {
      sb.write('\x1b[>${_kittyFlags(o)}u');
    }
    if (info.inBandResize) {
      sb.write('\x1b[?2048h');
    }
    if (info.graphemeMode) {
      sb.write('\x1b[?2027h');
    }
    if (info.colorSchemeReports) {
      sb.write('\x1b[?2031h');
    }
    for (final (set, _) in _states.values) {
      sb.write(set);
    }
    _writeString(sb.toString());
    _tellLost();
  }

  /// The states set on the terminal ([setTerminalState]), and BDSM where
  /// opening it switched that, in the order they were first set: what sets
  /// each and what puts it back.
  final _states = <Object, (String, String)>{};

  /// What writes a state again ([setTerminalState]'s refresh), by its key.
  final _refreshes = <Object, Timer>{};

  @override
  void setTerminalState(
    Object key,
    String sequence,
    String restore, {
    Duration? refresh,
  }) {
    assert(
      '$sequence$restore'.codeUnits.every((c) => c < 0x80),
      'a terminal state is set and put back in ASCII',
    );
    if (_closed || info.plain) {
      return;
    }
    _states[key] = (sequence, restore);
    _refreshes.remove(key)?.cancel();
    if (refresh != null) {
      _refreshes[key] = Timer.periodic(refresh, (_) {
        if (!_suspended) {
          _writeString(sequence);
        }
      });
    }
    if (!_suspended) {
      _writeString(sequence);
      _tellLost();
    }
  }

  @override
  void restoreTerminalState(Object key) {
    _refreshes.remove(key)?.cancel();
    final state = _states.remove(key);
    if (state == null || _closed) {
      return;
    }
    if (!_suspended) {
      _writeString(state.$2);
      _tellLost();
    }
  }

  /// Tells the link what puts the terminal back as it was: the states set
  /// on it, the modes off, the user's title; nothing for plain output.
  void _tellLost() {
    if (!info.plain) {
      _link.restoreWith(
        Uint8List.fromList(
          '${_exitSequence()}${_titlePushed ? popTitleSequence : ''}'.codeUnits,
        ),
      );
    }
  }

  String _exitSequence() {
    final o = options;
    final sb = StringBuffer();
    for (final (_, restore) in _states.values.toList().reversed) {
      sb.write(restore);
    }
    sb.write('\x1b[0m\x1b]8;;\x1b\\'); // + close any hyperlink
    if (info.colorSchemeReports) {
      sb.write('\x1b[?2031l');
    }
    if (info.graphemeMode) {
      sb.write('\x1b[?2027l');
    }
    if (info.inBandResize) {
      sb.write('\x1b[?2048l');
    }
    if (o.kittyKeyboard) {
      sb.write('\x1b[<u');
    }
    if (o.focusEvents) {
      sb.write('\x1b[?1004l');
    }
    if (o.bracketedPaste) {
      sb.write('\x1b[?2004l');
    }
    sb
      ..write(mouseTrackingSequence(_mouseTracking, MouseTracking.off))
      // autowrap (the presenter turns it off), cursor visible with the
      // user's own cursor shape
      ..write('\x1b[?7h\x1b[0 q\x1b[?25h');
    if (o.alternateScreen) {
      sb.write('\x1b[?1049l');
    }
    return sb.toString();
  }

  /// Writes the terminal's own [s] (Latin-1); nothing for plain output.
  void _writeString(String s) {
    if (!info.plain) {
      _out.add(Uint8List.fromList(s.codeUnits));
    }
  }

  final Outbox _out;

  /// The outbox to [link], recording what it hands over in [trace].
  static Outbox _outbox(TerminalLink link, TraceWriter? trace) => Outbox(
    trace == null
        ? link.add
        : (bytes) {
            link.add(bytes);
            trace.add(bytes);
          },
    link.flush,
  );

  /// Closes the traces; what closing the first failed with is thrown once
  /// the second is closed too.
  static Future<void> _closeTraces(
    TraceWriter? input,
    TraceWriter? output,
  ) async {
    try {
      await input?.close();
    } finally {
      await output?.close();
    }
  }

  // ---------------------------------------------------------------- input --

  void _adoptInput(List<InputEvent> early) {
    if (!info.answeredQueries && !info.plain) {
      _lateProbeReplies = true;
      // a terminal that never answers: Shift+F3 (CSI 1;2R, a cursor report
      // while one is expected) must become a key again
      _lateProbeTimer = Timer(const Duration(seconds: 5), _endLateProbe);
    }
    early.forEach(_events.add);
    _input
      ..onData(_onBytes)
      // the shell went away
      ..onError(_events.addError);
  }

  void _onBytes(List<int> bytes) {
    _inputTrace?.add(bytes);
    _escTimer?.cancel();
    _pasteTimer?.cancel();
    _parse(() => _parser.feed(bytes));
    if (_parser.inPaste) {
      _pasteTimer = Timer(options.pasteTimeout, () => _parse(_parser.endPaste));
    }
    if (_parser.hasPending) {
      // A sequence split across reads (a slow link) must not be cut: only a
      // lone ESC, or ESC and an introducer, may be a key typed by the user.
      // With the kitty protocol even a lone ESC isn't the Escape key; it is
      // resolved only after a long pause, in case the terminal sends a
      // legacy ESC after all, until it has
      final wait =
          (info.kittyKeyboard && !_legacyEscape) || _parser.sequenceStarted
          ? _longEscapeTimeout
          : options.escapeTimeout;
      _escTimer = Timer(wait, () => _parse(_flushEscape));
    }
  }

  /// Whether the terminal answered for the kitty keyboard protocol but
  /// sent the Escape key as a lone ESC all the same (Konsole does): from
  /// then on a lone ESC waits [TerminalOptions.escapeTimeout], as without
  /// the protocol.
  var _legacyEscape = false;

  /// What the parser held once the wait for the rest of it ran out; the
  /// Escape key it made of a lone ESC under the kitty protocol tells that
  /// the terminal sends it so.
  List<InputEvent> _flushEscape() {
    final events = _parser.flush();
    if (events case [KeyEvent(code: KeyCode.escape, modifiers: 0)]
        when info.kittyKeyboard) {
      _legacyEscape = true;
    }
    return events;
  }

  /// Delivers what one parser step produced. Input is read outside the
  /// app's zone, so a parser error goes to whoever listens to [events]
  /// instead of crashing past the terminal restore.
  ///
  /// Of a run of motions with no button held and the same modifiers in
  /// one read only the last is delivered ([deliverCoalesced]).
  void _parse(List<InputEvent> Function() step) {
    final List<InputEvent> events;
    try {
      events = step();
    } on Object catch (e, s) {
      _events.addError(e, s);
      return;
    }
    deliverCoalesced(events, _deliver);
  }

  /// The probe gave up before DA1, but its answers may still come: they are
  /// not input, so they are dropped until DA1 (the last one) arrives, or
  /// for a few seconds.
  var _lateProbeReplies = false;
  Timer? _lateProbeTimer;

  void _endLateProbe() {
    _lateProbeTimer?.cancel();
    _lateProbeReplies = false;
    _parser.expectCursorReport = false;
  }

  /// Running while the answer to a resume's cursor query that came too
  /// late may still come: it is dropped.
  Timer? _lateCursorTimer;

  void _deliver(InputEvent e) {
    if (e is CursorReport) {
      final asked = _cursorAsked;
      if (asked != null && !asked.isCompleted) {
        asked.complete(e.x);
        return;
      }
      if (_lateCursorTimer?.isActive ?? false) {
        _lateCursorTimer!.cancel();
        return;
      }
    }
    if (_lateProbeReplies) {
      switch (e) {
        case DeviceAttributes():
          _endLateProbe();
          return;
        case ModeReport() ||
            ColorReport() ||
            KeyboardFlagsReport() ||
            CursorReport():
          return;
        case UnknownSequence(:final bytes) when _isProbeReply(bytes):
          return;
        default:
      }
    }
    if (e is ResizeEvent) {
      width = e.width;
      height = e.height;
    } else if (e is FocusEvent) {
      _focused = e.focused;
    }
    _events.add(e);
    if (e is ColorSchemeReport) {
      _askColors();
    }
  }

  /// Asks for the default colors and the palette entries the probe was
  /// told again, after the color scheme changed: the answers are
  /// [ColorReport]s.
  void _askColors() {
    final fg = info.foregroundRgb == null ? '' : '\x1b]10;?\x1b\\';
    final bg = info.backgroundRgb == null ? '' : '\x1b]11;?\x1b\\';
    final entries = [for (final i in info.palette.keys) '$i;?'];
    final palette = entries.isEmpty ? '' : '\x1b]4;${entries.join(';')}\x1b\\';
    _writeString('$fg$bg$palette');
  }

  // --------------------------------------------------------------- resize --

  void _watchResize() {
    width = _link.columns;
    height = _link.lines;
    if (info.inBandResize) {
      return;
    } // arrives in the input stream
    _resizes = _link.resizes.listen((_) => _checkSize());
  }

  /// Reports a size other than the last one.
  void _checkSize() {
    final w = _link.columns;
    final h = _link.lines;
    if (w != width || h != height) {
      width = w;
      height = h;
      _events.add(ResizeEvent(w, h));
    }
  }

  // ------------------------------------------------------------ suspend --

  var _suspended = false;

  /// Asked where the cursor is ([resume]); completed by its report.
  Completer<int>? _cursorAsked;

  /// Hands the terminal back as [open] found it, for another program (an
  /// editor, a pager, a shell): the modes off (the alternate screen left,
  /// mouse, paste and focus reports, the kitty keyboard flags popped, the
  /// cursor shown in the user's shape) and raw mode off, with input paused
  /// rather than cancelled (cancelling it would close stdin, see [close]).
  /// Until [resume] Ctrl+C is the other program's: it isn't delivered.
  /// Throws [UnsupportedError] on a terminal opened with [overLink]: no
  /// program of this process can have it.
  @override
  Future<void> suspend() async {
    if (!_ofProcess) {
      throw UnsupportedError(
        'no other program can have a terminal over a link',
      );
    }
    if (_closed || _suspended) {
      return;
    }
    _suspended = true;
    _input.pause();
    // what was read before is the app's: resolved now, not by a timer
    // while the other program has the terminal, nor joined to what comes
    // after
    _escTimer?.cancel();
    _pasteTimer?.cancel();
    if (_parser.inPaste) {
      _parse(_parser.endPaste);
    } else if (_parser.hasPending) {
      _parse(_parser.flush);
    }
    try {
      _writeString(_exitSequence());
      _link.restoreWith(const []);
      await flush();
    } finally {
      if (!info.plain) {
        _link.restore();
      }
    }
  }

  /// Takes the terminal back after [suspend], as [open] took it: raw mode
  /// and the modes again, then input (what was typed before [suspend] and
  /// not read yet comes first). A size changed meanwhile is reported. In
  /// the inline mode the cursor is left at the start of a line of its own
  /// below what was printed meanwhile: the line it is on if it is at the
  /// start of one, the next one otherwise.
  @override
  Future<void> resume() async {
    if (_closed || !_suspended) {
      return;
    }
    if (!info.plain) {
      _link.enterRaw();
    }
    _suspended = false;
    _enterModes();
    // Where the cursor is (CSI 6 n) matters to the inline region, and the
    // answer is input: dart:io notes how much input is waiting also while
    // paused, and once resumed it waits for that much, in a blocking read,
    // even when the other program read it meanwhile. The answer ends that
    // wait (a terminal that doesn't answer leaves it to the next key).
    Completer<int>? asked;
    if (info.answeredQueries) {
      asked = _cursorAsked = Completer<int>();
      _parser.expectCursorReport = true;
      _writeString('\x1b[6n');
    }
    await flush();
    _input.resume();
    _checkSize();
    var column = -1;
    if (asked != null) {
      column = await asked.future.timeout(
        options.probeTimeout,
        onTimeout: () => -1,
      );
      _cursorAsked = null;
      if (column < 0) {
        // the answer may still come, and is no key (CSI 1;2R is Shift+F3)
        _lateCursorTimer?.cancel();
        _lateCursorTimer = Timer(
          const Duration(seconds: 5),
          () => _parser.expectCursorReport = false,
        );
      } else {
        _parser.expectCursorReport = false;
      }
    }
    if (!options.alternateScreen && column != 0 && !_closed) {
      _writeString('\r\n');
      await flush();
    }
  }

  /// Stops the process as Ctrl+Z does with terminal-generated signals on
  /// (here Ctrl+Z is a key): SIGTSTP to its process group, so the shell it
  /// was started from takes the terminal, until the shell continues it
  /// (`fg`). Without a shell doing job control nothing stops. Call it
  /// between [suspend] and [resume] (`TwkApp.suspendToShell` does). POSIX
  /// only: throws [UnsupportedError] on Windows and on the web.
  static Future<void> stopForShell() async {
    if (isWindows) {
      throw UnsupportedError('no job control on Windows');
    }
    stopProcessGroup();
    // SIGCONT can't be watched from Dart. The stop comes at once, before
    // this thread runs on if the signal went to it; the pause makes sure
    // the process stopped before the terminal is taken back.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  // ---------------------------------------------------------------- output --

  var _titlePushed = false;

  /// Sets the window/tab title; the user's title is restored on [close].
  @override
  void setTitle(String title) {
    if (_closed) {
      return;
    }
    if (!_titlePushed) {
      _writeString(pushTitleSequence);
      _titlePushed = true;
      if (!_suspended) {
        _tellLost();
      }
    }
    _writeUtf8(titleSequence(title));
  }

  /// Copies [text] to the system clipboard (OSC 52), through tmux or
  /// screen ([TerminalInfo.multiplexer]). See [clipboardSequence].
  void copyToClipboard(String text) {
    if (_closed) {
      return;
    }
    _writeString(clipboardSequence(text, multiplexer: info.multiplexer));
  }

  var _notifications = 0;

  // whether the terminal's window has the focus, as its last focus report
  // said; with none, it is taken to have it
  var _focused = true;

  /// Shows a desktop notification of [title] and [body] where the terminal
  /// is known to show one ([TerminalInfo.notifications]), through tmux or
  /// screen ([TerminalInfo.multiplexer]); does nothing elsewhere. See
  /// [notifySequence] for what is sent. Terminal.app's bell
  /// ([NotificationProtocol.bell]) is rung only while its window doesn't
  /// have the focus ([FocusEvent], [TerminalOptions.focusEvents]).
  @override
  void notify(String title, String body) {
    if (_closed ||
        (info.notifications == NotificationProtocol.bell && _focused)) {
      return;
    }
    final s = notifySequence(
      title,
      body,
      protocol: info.notifications,
      multiplexer: info.multiplexer,
      id: '$processId.${++_notifications}',
    );
    if (s.isNotEmpty) {
      _writeUtf8(s);
    }
  }

  /// Writes the terminal's own [s], UTF-8 encoded; nothing for plain
  /// output.
  void _writeUtf8(String s) {
    if (!info.plain) {
      _out.add(utf8.encode(s));
    }
  }

  /// Writes one frame. The bytes are copied into a buffer reused from frame
  /// to frame (no garbage per frame), so the caller may reuse its own
  /// buffer as soon as this returns. See [Outbox] for what happens to
  /// writes made while a flush is pending.
  @override
  void write(Uint8List bytes) {
    if (!_closed) {
      _out.frame(bytes);
    }
  }

  /// Completes when everything written so far reached the OS: awaiting it
  /// between frames keeps frames from queueing up on slow connections.
  @override
  Future<void> flush() => _out.flush();

  /// Restores the terminal. Safe to call more than once. The console modes
  /// are restored even when writing the exit sequence fails (stdout gone);
  /// that error is rethrown afterwards.
  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _escTimer?.cancel();
    _pasteTimer?.cancel();
    _lateProbeTimer?.cancel();
    _lateCursorTimer?.cancel();
    for (final timer in _refreshes.values) {
      timer.cancel();
    }
    await _resizes?.cancel();
    for (final s in _signals) {
      await s.cancel();
    }
    try {
      if (!_suspended) {
        // suspended, the modes are off and the screen is another's
        _writeString(_exitSequence());
      }
      if (_titlePushed) {
        _writeString(popTitleSequence);
      }
      _link.restoreWith(const []);
      await flush();
    } finally {
      if (!info.plain) {
        _link.restore();
      }
      await _input.cancel();
      // the done event is only delivered to a listener: without one the
      // future never completes
      final closed = _events.close();
      if (_events.hasListener) {
        await closed;
      }
      try {
        await _closeTraces(_inputTrace, _outputTrace);
      } finally {
        await _link.close();
      }
    }
  }
}

/// Whether the screen's lines are Konsole's ([TerminalCaps.konsoleLines]),
/// from the terminal's name and version as it tells them ([version],
/// XTVERSION) or else its environment (`KONSOLE_VERSION`): each as long as
/// what was written on it, which ICH pads with blanks in the default colours
/// and DCH ends with blanks at that length rather than at the right margin.
/// Inside a multiplexer ([multiplexerFor]) the lines are the multiplexer's,
/// which does as xterm does. The same terminal's images are Konsole's
/// ([TerminalCaps.konsoleImages]).
bool konsoleLinesFor(Map<String, String> env, {String version = ''}) {
  if (multiplexerFor(env) != Multiplexer.none) {
    return false;
  }
  if (version.isNotEmpty) {
    return version.startsWith('Konsole');
  }
  return env.containsKey('KONSOLE_VERSION');
}
