/// What a terminal can do, and the [CliMode] that follows from it:
/// [CliCapabilities], detected from stdio and the environment.
library;

import 'package:twk/twk.dart' show ColorMode;
import 'package:twk_core/twk_core.dart'
    show colorModeFor, plainAsked, runsInCi, styledUnderlinesFor;

/// How a program may talk to the person at a terminal, derived from
/// [CliCapabilities] ([CliCapabilities.mode]).
enum CliMode {
  /// Somebody can answer and output takes ANSI on a terminal: prompts and
  /// progress are widgets live in an inline twk app, finished output is
  /// committed above them.
  interactive,

  /// Somebody can answer, but output takes no ANSI or is not a terminal
  /// (`NO_COLOR`, `TERM=dumb`, `TWK_PLAIN=1`, `--no-color`, a pipe):
  /// output is written as lines, prompts are asked as plain lines.
  plain,

  /// Nobody can answer: input is not a terminal, the environment says CI
  /// (`CI`, `BUILD_NUMBER` and the rest twk_core's [runsInCi] reads), or
  /// input was refused (`--no-input`). Output is written as lines, and
  /// nothing is read.
  nonInteractive,
}

/// What a terminal can do, fixed when it is detected.
///
/// The process's terminal (`CliTerminal.system`) detects these from stdio
/// and the environment through [CliCapabilities.detect]; a fake terminal
/// states them outright.
///
/// ```dart
/// final caps = CliCapabilities.detect(
///   environment: {'NO_COLOR': '1'},
///   inputIsTerminal: true,
///   outputIsTerminal: true,
///   outputSupportsAnsi: true,
/// );
/// print(caps.mode); // CliMode.plain
/// ```
final class CliCapabilities {
  /// Capabilities as given; [hyperlinks] defaults to styled output on a
  /// terminal, [errorIsTerminal] to [outputIsTerminal].
  const CliCapabilities({
    required this.ansi,
    required this.interactiveInput,
    required this.outputIsTerminal,
    bool? errorIsTerminal,
    bool? hyperlinks,
    this.colorMode = ColorMode.trueColor,
    this.styledUnderlines = true,
  }) : errorIsTerminal = errorIsTerminal ?? outputIsTerminal,
       hyperlinks = hyperlinks ?? (ansi && outputIsTerminal);

  /// Detects the capabilities from what stdio reports and from
  /// [environment], as twk_core reads it where it opens a terminal, with
  /// `FORCE_COLOR`, `--no-color` and `--no-input` on top.
  ///
  /// Styling: `TWK_PLAIN=1` (twk_core's [plainAsked]) switches it off, then
  /// `FORCE_COLOR` wins over the rest (`0` or `false` switch styling off,
  /// any other non-empty value on); then where the environment takes no
  /// colors (twk_core's [colorModeFor]: a non-empty `NO_COLOR`,
  /// `TERM=dumb`) it is off; otherwise output must be a terminal that
  /// supports ANSI escapes.
  ///
  /// Input is interactive only on a terminal, and there only where the
  /// environment does not say CI (twk_core's [runsInCi]: `CI`,
  /// `CONTINUOUS_INTEGRATION`, `BUILD_NUMBER` or `RUN_ID`); [interactive]
  /// replaces the CI rule, so `false` is `--no-input`, and `true` asks
  /// under CI: still only on a terminal, since a pipe has nobody behind
  /// it.
  ///
  /// [ansi] replaces the styling rules (`--no-color`) and [hyperlinks] the
  /// default of styled output on a terminal. The colors are twk_core's
  /// ([colorModeFor], [windows] for a Windows console): 24-bit, 256 or 16
  /// by `COLORTERM`, `TERM` and `TERM_PROGRAM`, and 16 where styling is
  /// forced on an environment that takes none; the underline styles are
  /// shown as twk_core's [styledUnderlinesFor] has it: on all terminals
  /// but Terminal.app.
  factory CliCapabilities.detect({
    required Map<String, String> environment,
    required bool inputIsTerminal,
    required bool outputIsTerminal,
    required bool outputSupportsAnsi,
    bool? errorIsTerminal,
    bool? ansi,
    bool? interactive,
    bool? hyperlinks,
    bool windows = false,
  }) {
    final colors = colorModeFor(environment, windows: windows);
    return CliCapabilities(
      ansi:
          ansi ??
          _detectAnsi(
            environment,
            colors,
            outputIsTerminal: outputIsTerminal,
            outputSupportsAnsi: outputSupportsAnsi,
          ),
      interactiveInput:
          inputIsTerminal && (interactive ?? !runsInCi(environment)),
      outputIsTerminal: outputIsTerminal,
      errorIsTerminal: errorIsTerminal,
      hyperlinks: hyperlinks,
      colorMode: colors == ColorMode.none ? ColorMode.ansi16 : colors,
      styledUnderlines: styledUnderlinesFor(environment),
    );
  }

  /// Whether ANSI escapes (colors, styles, cursor moves) are written.
  final bool ansi;

  /// Whether somebody can answer a prompt: input is a terminal and asking
  /// was not refused.
  final bool interactiveInput;

  /// Whether output goes to a terminal rather than a pipe or a file.
  final bool outputIsTerminal;

  /// Whether the error output goes to a terminal: the same screen as the
  /// output, where that is one too.
  final bool errorIsTerminal;

  /// Whether links are written as OSC 8 hyperlinks rather than bare
  /// labels.
  final bool hyperlinks;

  /// The colors styled output is written in, where it is ([ansi]).
  final ColorMode colorMode;

  /// Whether the terminal shows the underline styles (double, curly,
  /// dotted, dashed); without them each is written as a plain underline.
  final bool styledUnderlines;

  /// Whether output can be redrawn in place: cursor moves and line clears
  /// reach a terminal that understands them.
  bool get redraws => ansi && outputIsTerminal;

  /// The mode these capabilities allow: [CliMode.nonInteractive] where
  /// nobody can answer, [CliMode.interactive] where output redraws,
  /// [CliMode.plain] otherwise.
  CliMode get mode => !interactiveInput
      ? CliMode.nonInteractive
      : redraws
      ? CliMode.interactive
      : CliMode.plain;

  static bool _detectAnsi(
    Map<String, String> environment,
    ColorMode colors, {
    required bool outputIsTerminal,
    required bool outputSupportsAnsi,
  }) {
    if (plainAsked(environment) ?? false) {
      return false;
    }
    if (environment['FORCE_COLOR'] case final force? when force.isNotEmpty) {
      return force != '0' && force.toLowerCase() != 'false';
    }
    if (colors == ColorMode.none) {
      return false;
    }
    return outputIsTerminal && outputSupportsAnsi;
  }

  @override
  String toString() =>
      'CliCapabilities(ansi: $ansi, interactiveInput: $interactiveInput, '
      'outputIsTerminal: $outputIsTerminal, '
      'errorIsTerminal: $errorIsTerminal, hyperlinks: $hyperlinks, '
      'colorMode: ${colorMode.name}, styledUnderlines: $styledUnderlines)';
}
