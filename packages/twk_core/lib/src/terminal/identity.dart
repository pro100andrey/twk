/// Which terminal a program's output reaches, as far as twk can tell, and
/// what twk knows that terminal to do from which version on without
/// answering a query for it.
///
/// One identification ([identifyTerminal]) and one table ([_known]): the
/// rules that decide a capability by a terminal's name ask
/// [TerminalIdentity.has] instead of reading `KONSOLE_VERSION` or
/// XTVERSION themselves, so that a terminal is told the same way for every
/// capability, and a version threshold is written once.
library;

/// A terminal twk knows facts of ([TerminalFeature]).
enum KnownTerminal {
  /// KDE's Konsole: XTVERSION `Konsole 26.08.3`, `KONSOLE_VERSION=260803`.
  konsole,

  /// VTE, the widget of GNOME Terminal, Ptyxis, GNOME Console, Tilix and
  /// kin: XTVERSION `VTE(7802)`, `VTE_VERSION=7802` (0.78.2).
  vte,

  /// kitty: XTVERSION `kitty(0.38.1)`, `TERM=xterm-kitty`,
  /// `KITTY_WINDOW_ID`.
  kitty,

  /// Ghostty: XTVERSION `ghostty 1.0.1`, `TERM=xterm-ghostty`,
  /// `TERM_PROGRAM=ghostty`, `GHOSTTY_RESOURCES_DIR`.
  ghostty,

  /// foot: XTVERSION `foot(1.18.0)`, `TERM=foot`.
  foot,

  /// WezTerm: XTVERSION `WezTerm 20240203-110809-5046fc22`,
  /// `TERM_PROGRAM=WezTerm`, `TERM=wezterm`, `WEZTERM_PANE`.
  wezterm,

  /// iTerm2: XTVERSION `iTerm2 3.5.0`, `TERM_PROGRAM=iTerm.app`,
  /// `LC_TERMINAL=iTerm2` (which ssh passes on), `ITERM_SESSION_ID`.
  iterm2,

  /// xterm: XTVERSION `XTerm(397)`, `XTERM_VERSION=XTerm(397)`.
  xterm,

  /// macOS's Terminal.app: `TERM_PROGRAM=Apple_Terminal`.
  appleTerminal,

  /// mintty, Cygwin's and Git for Windows' terminal: XTVERSION
  /// `mintty 3.7.8`, `TERM_PROGRAM=mintty`.
  mintty,

  /// Rio: XTVERSION `Rio 0.4.6`, `TERM_PROGRAM=rio`.
  rio,

  /// Contour: XTVERSION `contour 0.6.1.7494`, `TERM=contour`,
  /// `TERM_PROGRAM=contour`.
  contour,

  /// Windows Terminal: `WT_SESSION` (it answers no XTVERSION).
  windowsTerminal,

  /// ConEmu: `ConEmuPID`, `ConEmuANSI=ON`.
  conemu,

  /// Alacritty: `TERM=alacritty`.
  alacritty,

  /// rxvt-unicode: `TERM=rxvt-unicode`, `rxvt-unicode-256color`.
  urxvt,

  /// mlterm: XTVERSION `mlterm…`, `TERM=mlterm`, `MLTERM`.
  mlterm,

  /// PuTTY: `TERM=putty`, `putty-256color`.
  putty,
}

/// What a terminal may do without telling it: each a fact of the table of
/// known terminals, from a version on.
enum TerminalFeature {
  /// It honours DEC mode 2026 (synchronized output) though it may answer no
  /// DECRQM for it: Konsole 26.04 on (its commit fae264b561), which has no
  /// DECRQM at all.
  synchronizedOutput,

  /// Its lines are Konsole's (`TerminalCaps.konsoleLines`), and its images
  /// (`TerminalCaps.konsoleImages`).
  konsoleLines,

  /// It shows 24-bit color (`ColorMode.trueColor`) though no `COLORTERM`
  /// says so.
  trueColor,

  /// It shows 256 colors and not 24-bit ones, whatever its `TERM`.
  colors256,

  /// It reads the underline styles of SGR `4:2` to `4:5` otherwise: `4:3`
  /// as `43`, a yellow background (`TerminalCaps.styledUnderlines`).
  misreadsStyledUnderlines,

  /// Its DCH shifts a line only up to where the cursor last jumped, and
  /// drops the background an EL gave the rest of it
  /// (`TerminalCaps.insertDelete` off).
  misshiftsLines,

  /// It shows the mouse pointer's shapes OSC 22 names by CSS's names.
  pointerShapesCss,

  /// It shows the mouse pointer's shapes OSC 22 names by the X cursor
  /// font's names.
  pointerShapesX11,

  /// It shows a program's progress (OSC 9;4) and takes it for nothing else.
  progressReports,

  /// It shows desktop notifications by OSC 99, kitty's protocol, and
  /// answers its query (`p=?`).
  notificationsOsc99,

  /// It shows desktop notifications by OSC 777.
  notificationsOsc777,

  /// It shows desktop notifications by OSC 9.
  notificationsOsc9,

  /// It shows no desktop notification of a program's, but marks its bell.
  notificationsBell,

  /// It shows images by kitty's protocol, through tmux too.
  kittyGraphics,

  /// It plays the frames of an image of kitty's protocol; others show the
  /// first.
  kittyAnimation,

  /// It shows images by iTerm2's protocol (OSC 1337).
  iterm2Graphics,

  /// It clusters graphemes though it may not answer DECRQM 2027.
  graphemes,

  /// It draws the block sextants itself.
  sextants,

  /// It reorders right-to-left text in each row itself, and can't be told
  /// not to.
  reordersBidi,

  /// It implements REP (`CSI n b`).
  repeatChar,
}

/// A fact of the table: from [version] on (empty: every version); a
/// terminal whose version is not known has it where [unversioned], as one
/// whose versions without it are long out of use.
final class _Since {
  const _Since(this.version, {this.unversioned = false});

  final List<int> version;
  final bool unversioned;
}

/// Every version.
const _every = _Since([]);

/// What twk knows each terminal to do, and from which version on.
const _known = <KnownTerminal, Map<TerminalFeature, _Since>>{
  KnownTerminal.konsole: {
    TerminalFeature.synchronizedOutput: _Since([26, 4]),
    TerminalFeature.konsoleLines: _every,
    TerminalFeature.pointerShapesCss: _Since([26, 4]),
    TerminalFeature.progressReports: _Since([26, 4]),
    // commit 6ba3cbb1d, first in 23.04; OSC 99 cf94769bb, first in 24.12
    TerminalFeature.notificationsOsc777: _Since([23, 4]),
    TerminalFeature.notificationsOsc99: _Since([24, 12]),
    TerminalFeature.sextants: _Since([22, 4]),
    TerminalFeature.reordersBidi: _every,
  },
  KnownTerminal.vte: {
    TerminalFeature.notificationsOsc777: _Since([0, 52]),
    TerminalFeature.repeatChar: _Since([0, 62]),
    TerminalFeature.sextants: _Since([0, 78]),
    TerminalFeature.progressReports: _Since([0, 80]),
  },
  KnownTerminal.kitty: {
    TerminalFeature.trueColor: _every,
    TerminalFeature.pointerShapesCss: _Since([0, 31], unversioned: true),
    TerminalFeature.progressReports: _Since([0, 38]),
    TerminalFeature.notificationsOsc99: _every,
    TerminalFeature.kittyGraphics: _every,
    TerminalFeature.kittyAnimation: _every,
    TerminalFeature.graphemes: _every,
    // where its sextants were mended
    TerminalFeature.sextants: _Since([0, 19, 3], unversioned: true),
    TerminalFeature.repeatChar: _every,
  },
  KnownTerminal.ghostty: {
    TerminalFeature.trueColor: _every,
    TerminalFeature.pointerShapesCss: _every,
    TerminalFeature.progressReports: _every,
    TerminalFeature.notificationsOsc777: _every,
    TerminalFeature.kittyGraphics: _every,
    TerminalFeature.sextants: _Since([1], unversioned: true),
    TerminalFeature.repeatChar: _every,
  },
  KnownTerminal.foot: {
    TerminalFeature.pointerShapesCss: _Since([1, 12], unversioned: true),
    TerminalFeature.notificationsOsc99: _Since([1, 18]),
    TerminalFeature.notificationsOsc777: _every,
    TerminalFeature.sextants: _every,
    TerminalFeature.repeatChar: _every,
  },
  KnownTerminal.wezterm: {
    TerminalFeature.trueColor: _every,
    TerminalFeature.notificationsOsc777: _every,
    TerminalFeature.iterm2Graphics: _every,
    TerminalFeature.graphemes: _every,
    // with custom_block_glyphs on, the default
    TerminalFeature.sextants: _Since([20210814]),
    TerminalFeature.repeatChar: _every,
  },
  KnownTerminal.iterm2: {
    TerminalFeature.trueColor: _every,
    // from 3.5 it takes them, but shows its own pointer while the mouse is
    // reported, as it is to an app with a pointer shape to show
    TerminalFeature.pointerShapesX11: _Since([3, 7]),
    TerminalFeature.progressReports: _Since([3, 6, 6]),
    TerminalFeature.notificationsOsc9: _every,
    TerminalFeature.iterm2Graphics: _every,
  },
  KnownTerminal.xterm: {
    TerminalFeature.pointerShapesX11: _Since([367]),
    TerminalFeature.repeatChar: _every,
  },
  KnownTerminal.appleTerminal: {
    TerminalFeature.colors256: _every,
    TerminalFeature.misreadsStyledUnderlines: _every,
    TerminalFeature.misshiftsLines: _every,
    TerminalFeature.notificationsBell: _every,
    TerminalFeature.reordersBidi: _every,
  },
  KnownTerminal.mintty: {
    TerminalFeature.progressReports: _Since([3, 4, 2]),
  },
  KnownTerminal.rio: {
    TerminalFeature.pointerShapesCss: _every,
    TerminalFeature.progressReports: _Since([0, 3, 1]),
    TerminalFeature.sextants: _Since([0, 4, 6]),
  },
  KnownTerminal.contour: {
    TerminalFeature.progressReports: _Since([0, 7]),
    TerminalFeature.sextants: _Since([0, 3, 1]),
  },
  KnownTerminal.windowsTerminal: {
    TerminalFeature.trueColor: _every,
    TerminalFeature.progressReports: _every,
    TerminalFeature.notificationsOsc777: _every,
    TerminalFeature.graphemes: _every,
    TerminalFeature.repeatChar: _every,
  },
  KnownTerminal.conemu: {
    TerminalFeature.progressReports: _every,
  },
  KnownTerminal.alacritty: {
    TerminalFeature.repeatChar: _every,
  },
  KnownTerminal.urxvt: {
    TerminalFeature.notificationsOsc777: _every,
  },
  KnownTerminal.mlterm: {
    TerminalFeature.reordersBidi: _every,
  },
  KnownTerminal.putty: {
    TerminalFeature.reordersBidi: _every,
  },
};

/// The terminal a program's output reaches, as [identifyTerminal] tells it:
/// one twk knows ([terminal]) and its [version], or none it knows.
final class TerminalIdentity {
  /// [terminal] at [version] (empty where it is not known).
  const TerminalIdentity(this.terminal, [this.version = const []]);

  /// None twk knows.
  static const unknown = TerminalIdentity(null);

  /// The terminal, null for one twk knows no facts of.
  final KnownTerminal? terminal;

  /// Its version, major first; empty where it did not say.
  final List<int> version;

  /// Whether the terminal is known to do [feature]: it is one the table
  /// has it for, at the version from which it does or later. A version not
  /// known has what every version has, and what the table takes such a
  /// version to have.
  bool has(TerminalFeature feature) {
    final since = _known[terminal]?[feature];
    if (since == null) {
      return false;
    }
    if (since.version.isEmpty) {
      return true;
    }
    return version.isEmpty
        ? since.unversioned
        : versionAtLeast(version, since.version);
  }

  @override
  String toString() => terminal == null
      ? 'unknown'
      : '${terminal!.name}${version.isEmpty ? '' : ' ${version.join('.')}'}';
}

/// The terminals whose XTVERSION answers start so, and where the version
/// starts in it: `kitty(0.38.1)`, `WezTerm 20240203-…`.
const _versionNames = <String, KnownTerminal>{
  'Konsole': KnownTerminal.konsole,
  'VTE(': KnownTerminal.vte,
  'kitty(': KnownTerminal.kitty,
  'foot(': KnownTerminal.foot,
  'ghostty': KnownTerminal.ghostty,
  'WezTerm': KnownTerminal.wezterm,
  'iTerm2': KnownTerminal.iterm2,
  'XTerm(': KnownTerminal.xterm,
  'mlterm': KnownTerminal.mlterm,
  'mintty': KnownTerminal.mintty,
  'Rio': KnownTerminal.rio,
  'contour': KnownTerminal.contour,
};

/// The terminals that set a `TERM_PROGRAM` of their own, by it: its
/// `TERM_PROGRAM_VERSION` is their version, but GNOME Console's (VTE), whose
/// VTE's is `VTE_VERSION`.
const _programs = <String, KnownTerminal>{
  'iTerm.app': KnownTerminal.iterm2,
  'WezTerm': KnownTerminal.wezterm,
  'ghostty': KnownTerminal.ghostty,
  'Apple_Terminal': KnownTerminal.appleTerminal,
  'mintty': KnownTerminal.mintty,
  'rio': KnownTerminal.rio,
  'contour': KnownTerminal.contour,
  'kgx': KnownTerminal.vte,
};

/// Which terminal the output reaches, from the name and version it tells
/// ([version], its XTVERSION answer), else its environment.
///
/// A name the terminal tells comes first, but a multiplexer's (tmux,
/// GNU screen), which answers for itself and says nothing of the terminal
/// outside it. Then a `TERM` of a terminal's own ([_termOf]: kitty's
/// `xterm-kitty`, foot's, Alacritty's...; `dumb`, an editor's, of none),
/// then a `TERM_PROGRAM` other than tmux's: either names a terminal, and
/// the variables a terminal sets for its programs (`KONSOLE_VERSION`,
/// `KITTY_WINDOW_ID`, `WT_SESSION`...) are then those of the terminal it was
/// started from. Then those variables, where `TERM` is one those terminals
/// set, a multiplexer's or not told: under another (`st-256color`) they too
/// are of the terminal it was started from. kitty's, Ghostty's, WezTerm's
/// and iTerm2's before Konsole's and VTE's, as a kitty under a `TERM` of
/// its own choosing started from GNOME Terminal keeps `VTE_VERSION`.
TerminalIdentity identifyTerminal(
  Map<String, String> env, {
  String version = '',
}) {
  if (version.isNotEmpty &&
      !version.startsWith('tmux') &&
      !version.startsWith('screen')) {
    for (final MapEntry(key: name, value: terminal) in _versionNames.entries) {
      if (version.startsWith(name)) {
        final rest = version.substring(name.length).trimLeft();
        return TerminalIdentity(
          terminal,
          terminal == KnownTerminal.vte
              ? _vte(_number(rest.replaceAll(')', '')))
              : _dotted(rest.startsWith('(') ? rest.substring(1) : rest),
        );
      }
    }
    return TerminalIdentity.unknown;
  }
  final term = env['TERM'] ?? '';
  final program = env['TERM_PROGRAM'] ?? '';
  final programVersion = _dotted(env['TERM_PROGRAM_VERSION'] ?? '');
  if (_termNamesItsOwnTerminal(term)) {
    final own = _termOf(term);
    return own == null
        ? TerminalIdentity.unknown
        : TerminalIdentity(
            own,
            _programs[program] == own ? programVersion : const [],
          );
  }
  if (program.isNotEmpty && program != 'tmux') {
    return switch (_programs[program]) {
      null => TerminalIdentity.unknown,
      KnownTerminal.vte => TerminalIdentity(
        KnownTerminal.vte,
        _vte(_number(env['VTE_VERSION'])),
      ),
      final known => TerminalIdentity(known, programVersion),
    };
  }
  if (!_termOfInheritingTerminal(term)) {
    return TerminalIdentity.unknown;
  }
  if (env.containsKey('KITTY_WINDOW_ID')) {
    return const TerminalIdentity(KnownTerminal.kitty);
  }
  if (env.containsKey('GHOSTTY_RESOURCES_DIR')) {
    return const TerminalIdentity(KnownTerminal.ghostty);
  }
  if (env.containsKey('WEZTERM_PANE')) {
    return const TerminalIdentity(KnownTerminal.wezterm);
  }
  if (env['LC_TERMINAL'] == 'iTerm2') {
    return TerminalIdentity(
      KnownTerminal.iterm2,
      _dotted(env['LC_TERMINAL_VERSION'] ?? ''),
    );
  }
  if (env.containsKey('ITERM_SESSION_ID')) {
    return const TerminalIdentity(KnownTerminal.iterm2);
  }
  if (env.containsKey('KONSOLE_VERSION')) {
    // 260803: 26.08.3
    final konsole = _number(env['KONSOLE_VERSION']);
    return TerminalIdentity(KnownTerminal.konsole, [
      konsole ~/ 10000,
      konsole ~/ 100 % 100,
      konsole % 100,
    ]);
  }
  if (env.containsKey('VTE_VERSION')) {
    return TerminalIdentity(
      KnownTerminal.vte,
      _vte(_number(env['VTE_VERSION'])),
    );
  }
  if (env.containsKey('WT_SESSION')) {
    return const TerminalIdentity(KnownTerminal.windowsTerminal);
  }
  if (env.containsKey('ConEmuPID') || env['ConEmuANSI'] == 'ON') {
    return const TerminalIdentity(KnownTerminal.conemu);
  }
  if (env.containsKey('MLTERM')) {
    return const TerminalIdentity(KnownTerminal.mlterm);
  }
  final xterm = env['XTERM_VERSION'] ?? '';
  if (xterm.startsWith('XTerm(')) {
    return TerminalIdentity(KnownTerminal.xterm, _dotted(xterm.substring(6)));
  }
  return TerminalIdentity.unknown;
}

/// Whether [term], a `TERM`, may be one the terminals that set variables
/// for their programs set (`xterm-256color` by default, Konsole's
/// `konsole-256color` as a profile may name it) or a multiplexer's inside
/// them, or is not told: any other (`st-256color`, `linux`) is a terminal's
/// that was started from them and inherited their variables.
bool _termOfInheritingTerminal(String term) =>
    term.isEmpty ||
    term.startsWith('xterm') ||
    term.startsWith('konsole') ||
    term.startsWith('vte') ||
    term.startsWith('tmux') ||
    term.startsWith('screen');

/// The terminal whose own name [term], a `TERM`, is; null for `dumb`, of
/// no terminal, and one not of [_termNamesItsOwnTerminal].
KnownTerminal? _termOf(String term) => switch (term) {
  'xterm-kitty' => KnownTerminal.kitty,
  'xterm-ghostty' => KnownTerminal.ghostty,
  'alacritty' => KnownTerminal.alacritty,
  'contour' => KnownTerminal.contour,
  'wezterm' => KnownTerminal.wezterm,
  _ when term.startsWith('foot') => KnownTerminal.foot,
  _ when term.startsWith('rxvt-unicode') => KnownTerminal.urxvt,
  _ when term.startsWith('mlterm') => KnownTerminal.mlterm,
  _ when term.startsWith('putty') => KnownTerminal.putty,
  _ => null,
};

/// Whether [term], a `TERM`, is a terminal's own name, set by that
/// terminal (kitty, Ghostty, foot, Alacritty, Contour, WezTerm,
/// rxvt-unicode, mlterm, PuTTY), or `dumb`, an editor's: it comes before a
/// `TERM_PROGRAM` or other variables a terminal it was started from left in
/// its environment, as Terminal.app's `Apple_Terminal`.
bool _termNamesItsOwnTerminal(String term) =>
    term == 'dumb' || _termOf(term) != null;

/// Whether [version] is [least] or later, both major first; a missing
/// part is 0.
bool versionAtLeast(List<int> version, List<int> least) {
  for (var i = 0; i < least.length; i++) {
    final n = i < version.length ? version[i] : 0;
    if (n != least[i]) {
      return n > least[i];
    }
  }
  return true;
}

/// Whether the version at the start of [version] (numbers separated by
/// dots) is [least] or later; false when it starts with no number.
bool dottedAtLeast(String version, List<int> least) {
  final parts = _dotted(version);
  return parts.isNotEmpty && versionAtLeast(parts, least);
}

/// The numbers separated by dots at the start of [version]; none where it
/// starts with no number.
List<int> _dotted(String version) {
  final parts = RegExp(r'^\d+(\.\d+)*').stringMatch(version);
  return parts == null ? const [] : parts.split('.').map(int.parse).toList();
}

/// VTE's version number (7802) as its version (0.78.2).
List<int> _vte(int n) => [0, n ~/ 100, n % 100];

/// [value] as a number, 0 when it is none.
int _number(String? value) => int.tryParse(value ?? '') ?? 0;
