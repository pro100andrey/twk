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

/// A terminal twk knows facts of by its version ([TerminalFeature]).
enum KnownTerminal {
  /// KDE's Konsole: XTVERSION `Konsole 26.08.3`, `KONSOLE_VERSION=260803`.
  konsole,

  /// VTE, the widget of GNOME Terminal, Ptyxis, Tilix and kin: XTVERSION
  /// `VTE(7802)`, `VTE_VERSION=7802` (0.78.2).
  vte,
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

  /// It shows the mouse pointer's shapes OSC 22 names by CSS's names.
  pointerShapesCss,

  /// It shows a program's progress (OSC 9;4) and takes it for nothing else.
  progressReports,

  /// It shows desktop notifications by OSC 777.
  notificationsOsc777,

  /// It draws the block sextants itself.
  sextants,

  /// It reorders right-to-left text in each row itself, and can't be told
  /// not to.
  reordersBidi,

  /// It implements REP (`CSI n b`).
  repeatChar,
}

/// What twk knows each terminal to do, and from which version on: an empty
/// version is every version.
const _known = <KnownTerminal, Map<TerminalFeature, List<int>>>{
  KnownTerminal.konsole: {
    TerminalFeature.synchronizedOutput: [26, 4],
    TerminalFeature.konsoleLines: [],
    TerminalFeature.pointerShapesCss: [26, 4],
    TerminalFeature.progressReports: [26, 4],
    TerminalFeature.notificationsOsc777: [22, 12],
    TerminalFeature.sextants: [22, 4],
    TerminalFeature.reordersBidi: [],
  },
  KnownTerminal.vte: {
    TerminalFeature.notificationsOsc777: [0, 52],
    TerminalFeature.repeatChar: [0, 62],
    TerminalFeature.sextants: [0, 78],
    TerminalFeature.progressReports: [0, 80],
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
  /// known has only what every version has.
  bool has(TerminalFeature feature) {
    final least = _known[terminal]?[feature];
    return least != null && (least.isEmpty || versionAtLeast(version, least));
  }

  @override
  String toString() => terminal == null
      ? 'unknown'
      : '${terminal!.name}${version.isEmpty ? '' : ' ${version.join('.')}'}';
}

/// Which terminal the output reaches, from the name and version it tells
/// ([version], its XTVERSION answer), else its environment.
///
/// A name the terminal tells comes first, but a multiplexer's (tmux,
/// GNU screen), which answers for itself and says nothing of the terminal
/// outside it. Then a `TERM` of a terminal's own
/// ([termNamesItsOwnTerminal]), then a `TERM_PROGRAM` other than tmux's:
/// either names a terminal, and the variables a terminal sets for its
/// programs (`KONSOLE_VERSION`, `VTE_VERSION`) are then those of the
/// terminal it was started from. Then those variables, where `TERM` is
/// one those terminals set, a multiplexer's or not told: under another
/// (`st-256color`) they too are of the terminal it was started from.
TerminalIdentity identifyTerminal(
  Map<String, String> env, {
  String version = '',
}) {
  if (version.isNotEmpty &&
      !version.startsWith('tmux') &&
      !version.startsWith('screen')) {
    if (version.startsWith('Konsole')) {
      return TerminalIdentity(
        KnownTerminal.konsole,
        _dotted(version.substring(7).trimLeft()),
      );
    }
    if (version.startsWith('VTE(')) {
      return TerminalIdentity(
        KnownTerminal.vte,
        _vte(_number(version.substring(4).replaceAll(')', ''))),
      );
    }
    return TerminalIdentity.unknown;
  }
  if (termNamesItsOwnTerminal(env['TERM'] ?? '')) {
    return TerminalIdentity.unknown;
  }
  final program = env['TERM_PROGRAM'] ?? '';
  if (program.isNotEmpty && program != 'tmux') {
    return TerminalIdentity.unknown;
  }
  if (!_termOfKonsoleOrVte(env['TERM'] ?? '')) {
    return TerminalIdentity.unknown;
  }
  final konsole = _number(env['KONSOLE_VERSION']);
  if (env.containsKey('KONSOLE_VERSION')) {
    // 260803: 26.08.3
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
  return TerminalIdentity.unknown;
}

/// Whether [term], a `TERM`, may be one Konsole or VTE sets (`xterm-256color`
/// by default, `konsole-256color` as a profile may name it) or a
/// multiplexer's inside them, or is not told: any other (`st-256color`,
/// `linux`) is a terminal's that was started from them and inherited their
/// variables.
bool _termOfKonsoleOrVte(String term) =>
    term.isEmpty ||
    term.startsWith('xterm') ||
    term.startsWith('konsole') ||
    term.startsWith('vte') ||
    term.startsWith('tmux') ||
    term.startsWith('screen');

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
