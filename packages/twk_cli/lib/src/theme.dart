/// How a [Cli]'s channels look, and the theme its widgets are shown in:
/// [CliTheme].
///
/// @docImport 'cli.dart';
library;

import 'package:meta/meta.dart';
import 'package:twk/twk.dart';

// Examples can assume:
// import 'package:twk/twk.dart';

/// The style of each channel of a [Cli], merged under the styles of the
/// message itself, and the [ThemeData] the widgets it shows are shown in
/// ([data]).
///
/// A channel left out takes its style from [data]: [Cli.detail] its muted
/// text, [Cli.success], [Cli.warn] and [Cli.err] its success, warning and
/// error colors; [Cli.info] is unstyled and [Cli.alert] bold white on red.
/// Without [data], the terminal's own colors ([ThemeData.terminal]), its
/// muted text dim ([lineData]).
///
/// The prompts' lines take [question], [answer] and [hint]: `? Name?
/// (my_app)` as asked, `✔ Name? my_app` once answered, the `✔` in
/// [success] and a refusal's `✗` in [error].
///
/// ```dart
/// final cli = Cli(
///   theme: CliTheme(
///     warning: const Style(fg: Color.yellow, attrs: Attr.bold),
///   ),
/// );
/// ```
@immutable
final class CliTheme {
  /// A theme of [data] with the channels given restyled.
  const CliTheme({
    this.data,
    this._detail,
    this._info,
    this._success,
    this._warning,
    this._error,
    this._alert,
    this._question,
    this._answer,
    this._hint,
  });

  /// What widgets are shown in ([Cli.show], prompts, progress); null for
  /// the terminal's own theme, which the inline session takes from its
  /// brightness.
  final ThemeData? data;

  final Style? _detail;
  final Style? _info;
  final Style? _success;
  final Style? _warning;
  final Style? _error;
  final Style? _alert;
  final Style? _question;
  final Style? _answer;
  final Style? _hint;

  /// What the channels' lines are styled from: [data], or without it the
  /// terminal's own colors with the muted text dim. A [Cli] writes its
  /// lines without asking the terminal what its background is, and dim
  /// reads on a dark one and a light one alike, where a grey of either
  /// theme would not.
  @internal
  ThemeData get lineData => data ?? _terminal;

  static final ThemeData _terminal =
      const ThemeData.terminal(
        Brightness.dark,
      ).copyWith(
        muted: const Style(fg: Color.defaultColor, attrs: Attr.dim),
      );

  ThemeData get _data => lineData;

  /// The style of [Cli.detail]: muted by default.
  Style get detail => _detail ?? _data.muted;

  /// The style of [Cli.info]: unstyled by default.
  Style get info => _info ?? const Style();

  /// The style of [Cli.success]: the theme's success color by default.
  Style get success => _success ?? _data.success;

  /// The style of [Cli.warn]: the theme's warning color by default.
  Style get warning => _warning ?? _data.warning;

  /// The style of [Cli.err]: the theme's error color by default.
  Style get error => _error ?? _data.error;

  /// The style of [Cli.alert]: bold white on red by default.
  Style get alert =>
      _alert ??
      const Style(fg: Color.brightWhite, bg: Color.red, attrs: Attr.bold);

  /// The question a prompt asks: bold by default.
  Style get question => _question ?? const Style(attrs: Attr.bold);

  /// A prompt's answer once given, and the `?` before a question: the
  /// theme's primary color by default.
  Style get answer => _answer ?? _data.primary;

  /// What a prompt says around its question (the default, how to answer):
  /// the theme's muted text by default.
  Style get hint => _hint ?? _data.muted;

  /// This theme with the fields given replaced.
  CliTheme copyWith({
    ThemeData? data,
    Style? detail,
    Style? info,
    Style? success,
    Style? warning,
    Style? error,
    Style? alert,
    Style? question,
    Style? answer,
    Style? hint,
  }) => CliTheme(
    data: data ?? this.data,
    detail: detail ?? _detail,
    info: info ?? _info,
    success: success ?? _success,
    warning: warning ?? _warning,
    error: error ?? _error,
    alert: alert ?? _alert,
    question: question ?? _question,
    answer: answer ?? _answer,
    hint: hint ?? _hint,
  );

  @override
  bool operator ==(Object other) =>
      other is CliTheme &&
      other.data == data &&
      other._detail == _detail &&
      other._info == _info &&
      other._success == _success &&
      other._warning == _warning &&
      other._error == _error &&
      other._alert == _alert &&
      other._question == _question &&
      other._answer == _answer &&
      other._hint == _hint;

  @override
  int get hashCode => Object.hash(
    data,
    _detail,
    _info,
    _success,
    _warning,
    _error,
    _alert,
    _question,
    _answer,
    _hint,
  );
}
