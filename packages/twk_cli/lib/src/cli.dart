/// The console of a command-line tool: [Cli], its channels, levels and
/// flags, and twk widgets shown in its output.
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart' show SyntaxTheme, jsonLines;

import 'capabilities.dart';
import 'lines.dart';
import 'progress.dart';
import 'prompt_exception.dart';
import 'prompts.dart';
import 'session.dart';
import 'terminal.dart';
import 'theme.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// Future<void> build() async {}
// Future<void> download(void Function(int bytes) received) async {}
// const size = 3400000;

/// The level a command line's `--verbose` and `--quiet` ask for: [verbose]
/// shows everything ([LogLevel.debug]), [quiet] only errors
/// ([LogLevel.error]), neither keeps [LogLevel.info]. Given both,
/// [verbose] wins: `-q` tends to sit in an alias or a script, and `-v` is
/// added by hand to see why something went wrong.
LogLevel levelFromFlags({bool verbose = false, bool quiet = false}) => verbose
    ? LogLevel.debug
    : quiet
    ? LogLevel.error
    : LogLevel.info;

/// The console of a command-line tool: messages by channel and level,
/// styled as the terminal takes them, and any twk widget shown in the
/// output ([show]).
///
/// Everything goes through one [terminal], whose [mode] says how:
///
/// * [CliMode.interactive]: somebody answers at a terminal that redraws.
///   The first time something needs it (a widget shown, a prompt, a
///   progress) the console opens one inline twk app on the terminal and
///   keeps it until [close] ([CliSession]): what is live is in its region,
///   finished output, lines logged included, is committed to the
///   terminal's history above it. Until then, lines are written as they
///   are elsewhere.
/// * [CliMode.plain] and [CliMode.nonInteractive]: nothing is opened;
///   output is written as lines, a widget as the lines of its text, with
///   escapes only where the terminal takes them.
///
/// [err], [alert] and [warn] write to the error output, so a pipe carries
/// results only; the rest goes to the output. A message is written when
/// [level] lets its channel through: [detail] at [LogLevel.debug],
/// [info] and [success] at [LogLevel.info], [warn] at
/// [LogLevel.warning], [err] and [alert] at [LogLevel.error], the quiet
/// threshold (`--quiet`): a person who silenced the output still sees
/// the run fail.
///
/// A message is a [String], styled text ([Span], `'x'.bold.fg(Color.red)`)
/// or a list of both: see [messageLines]. Its channel's style
/// ([CliTheme]) is merged under its own.
///
/// [Cli.run] and [Cli.runWithArgs] are the front door of a program: they
/// set the console up from its flags, make it [Cli.current] for the body
/// and [close] it on the way out.
///
/// ```dart
/// Future<void> main(List<String> args) =>
///     Cli.runWithArgs(args, (cli, rest) async {
///       cli.detail('building ${rest.join(' ')}');
///       await build();
///       cli.success('Built.');
///     });
/// ```
final class Cli {
  /// A console on [terminal], the process's stdio unless given one,
  /// showing what [level] lets through in [theme], the source of an error
  /// as [sourceLines] gives it.
  Cli({
    CliTerminal? terminal,
    this.level = LogLevel.info,
    CliTheme? theme,
    this.sourceLines,
  }) : terminal = terminal ?? CliTerminal.system(),
       theme = theme ?? const CliTheme();

  static final _zoneKey = Object();
  static Cli? _default;

  /// The console of the [Cli.run] the caller runs in, else one on the
  /// process's stdio, made the first time it is asked for.
  ///
  /// The default one is never closed by anybody: a program that shows a
  /// widget through it in the interactive mode has to [close] it, as
  /// [Cli.run] does, or its inline session keeps stdin open.
  // ignore: prefer_constructors_over_static_methods, the zone's, made once
  static Cli get current =>
      Zone.current[_zoneKey] as Cli? ?? (_default ??= Cli());

  /// Runs [body] with a console set up from a command line's flags, which
  /// is [Cli.current] for the whole of it, its asynchronous continuations
  /// included, and is [close]d when it ends, by an error too.
  ///
  /// [verbose] and [quiet] pick the level ([levelFromFlags]). `false` for
  /// [color] is `--no-color`: no escapes whatever the terminal takes.
  /// `false` for [input] is `--no-input`: nothing is asked. Left `true`,
  /// both are detected (`NO_COLOR`, `CI`, whether stdio is a terminal).
  ///
  /// With [handleErrors], what [body] throws, and what is thrown in it
  /// that nothing catches (a future nobody awaits), ends the run as a
  /// command line ends: the [traceback] on the error output ([error]),
  /// every frame under `--verbose`; the terminal restored; the
  /// [CliTerminal.exitCode] [errorExitCode]. A [PromptException] ends it
  /// quietly, with its question and no traceback: a prompt cancelled with
  /// `✗ question` (the interactive prompt shows it itself), and 130, the
  /// code of an interrupt, for Ctrl+C; one nobody can answer with what it
  /// needs, and [errorExitCode]. The run then completes with null where
  /// its result may be null (a `void` body's), and with the error
  /// otherwise: a value it has none of. An error left uncaught once the
  /// run has ended is shown, and sets the code, all the same. Without
  /// [handleErrors] what the body throws is the run's, as it is.
  ///
  /// [sourceLines] is the console's [Cli.sourceLines].
  ///
  /// [open] makes the terminal from what the flags leave to detection
  /// (null) and what they decide: [CliTerminal.system] unless a test of
  /// the program passes one that makes a fake terminal.
  static Future<T> run<T>(
    FutureOr<T> Function(Cli cli) body, {
    bool verbose = false,
    bool quiet = false,
    bool color = true,
    bool input = true,
    CliTheme? theme,
    SourceLines? sourceLines,
    bool handleErrors = true,
    int errorExitCode = 1,
    CliTerminal Function({bool? ansi, bool? interactive})? open,
  }) async {
    final terminal = (open ?? CliTerminal.system)(
      ansi: color ? null : false,
      interactive: input ? null : false,
    );
    final cli = Cli(
      terminal: terminal,
      level: levelFromFlags(verbose: verbose, quiet: quiet),
      theme: theme,
      sourceLines: sourceLines,
    );
    if (!handleErrors) {
      try {
        return await runZoned(
          () => Future<T>.sync(() => body(cli)),
          zoneValues: {_zoneKey: cli},
        );
      } finally {
        await cli.close();
      }
    }
    // made outside the zone, so that its error reaches the await below
    final done = Completer<T>();
    void failed(Object error, StackTrace stack) {
      if (done.isCompleted) {
        unawaited(cli._failed(error, stack, errorExitCode));
      } else {
        done.completeError(error, stack);
      }
    }

    runZonedGuarded(
      () {
        unawaited(
          Future<T>.sync(() => body(cli)).then((value) {
            if (!done.isCompleted) {
              done.complete(value);
            }
          }, onError: failed),
        );
      },
      failed,
      zoneValues: {_zoneKey: cli},
    );
    try {
      return await done.future;
    } on Object catch (error, stack) {
      await cli._failed(error, stack, errorExitCode);
      if (null is T) {
        return null as T;
      }
      rethrow;
    } finally {
      await cli.close();
    }
  }

  /// [run] with its flags taken off [args]: `-v`/`--verbose`,
  /// `-q`/`--quiet`, `--no-color` and `--no-input`, wherever they are
  /// before a `--`; the rest, in order and with what follows `--` as it
  /// is, goes to [body]. Errors are handled as [run] handles them.
  ///
  /// ```dart
  /// Future<void> main(List<String> args) => Cli.runWithArgs(
  ///   args,
  ///   (cli, rest) => cli.info('files: ${rest.join(', ')}'),
  /// );
  /// ```
  static Future<T> runWithArgs<T>(
    List<String> args,
    FutureOr<T> Function(Cli cli, List<String> rest) body, {
    CliTheme? theme,
    SourceLines? sourceLines,
    bool handleErrors = true,
    int errorExitCode = 1,
    CliTerminal Function({bool? ansi, bool? interactive})? open,
  }) {
    var verbose = false;
    var quiet = false;
    var color = true;
    var input = true;
    final rest = <String>[];
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '-v' || '--verbose':
          verbose = true;
        case '-q' || '--quiet':
          quiet = true;
        case '--no-color':
          color = false;
        case '--no-input':
          input = false;
        case '--':
          rest.addAll(args.skip(i));
          i = args.length;
        default:
          rest.add(args[i]);
      }
    }
    return run(
      (cli) => body(cli, rest),
      verbose: verbose,
      quiet: quiet,
      color: color,
      input: input,
      theme: theme,
      sourceLines: sourceLines,
      handleErrors: handleErrors,
      errorExitCode: errorExitCode,
      open: open,
    );
  }

  /// The terminal output goes to and input comes from.
  final CliTerminal terminal;

  /// How the console talks to the terminal ([CliTerminal.mode]).
  CliMode get mode => terminal.mode;

  /// The threshold a channel is written at or above; mutable, for a
  /// `--verbose` that comes late.
  LogLevel level;

  /// The style of each channel, and what widgets are shown in.
  CliTheme theme;

  /// The lines of code an error's [traceback] shows of the source it was
  /// thrown in, as [Cli.error] and [Cli.run] show it: their text without,
  /// highlighted as Dart with twk_rich's `dartSourceLines`.
  final SourceLines? sourceLines;

  CliCapabilities get _caps => terminal.capabilities;

  final _delayed = <Object?>[];

  // what write() took that no line break ended yet, while a session holds
  // the screen
  final _partial = StringBuffer();

  Future<CliSession>? _opening;
  CliSession? _session;

  // what the inline session's probe found of the underline styles, kept
  // once it ended: the same terminal
  bool? _probedUnderlines;

  /// Whether the lines written show the underline styles: as the inline
  /// session's probe found once one was opened, the environment's guess
  /// ([CliCapabilities.styledUnderlines]) before.
  @internal
  bool get styledUnderlines => _probedUnderlines ?? _caps.styledUnderlines;

  // the session ended: stdin is closed, so none opens again
  var _sessionEnded = false;
  var _closed = false;

  /// Logs [message] at [LogLevel.debug], to the output, in the theme's
  /// [CliTheme.detail] (muted).
  void detail(Object? message) =>
      _log(message, LogLevel.debug, theme.detail, toErr: false);

  /// Logs [message] at [LogLevel.info], to the output, unstyled.
  void info(Object? message) =>
      _log(message, LogLevel.info, theme.info, toErr: false);

  /// Logs [message] at [LogLevel.info], to the output, in the theme's
  /// [CliTheme.success].
  void success(Object? message) =>
      _log(message, LogLevel.info, theme.success, toErr: false);

  /// Logs [message] at [LogLevel.warning], to the error output, in the
  /// theme's [CliTheme.warning]: a warning is a diagnostic, not a result.
  void warn(Object? message) =>
      _log(message, LogLevel.warning, theme.warning, toErr: true);

  /// Logs [message] at [LogLevel.error], to the error output, in the
  /// theme's [CliTheme.error].
  void err(Object? message) =>
      _log(message, LogLevel.error, theme.error, toErr: true);

  /// Logs [message] as an alert, to the error output, in the theme's
  /// [CliTheme.alert] (bold white on red): critical, shown wherever [err]
  /// is.
  void alert(Object? message) =>
      _log(message, LogLevel.error, theme.alert, toErr: true);

  /// Writes [text] to the output as it is: no level, no style, no line
  /// break. While an inline session holds the screen, text goes above
  /// what is live line by line, as each line break ends one; what is left
  /// goes when the console is [close]d.
  void write(String text) {
    final session = _liveSession;
    if (session == null) {
      terminal.out.write(text);
      return;
    }
    _partial.write(text);
    final all = _partial.toString();
    final end = all.lastIndexOf('\n');
    if (end < 0) {
      return;
    }
    _partial
      ..clear()
      ..write(all.substring(end + 1));
    unawaited(
      session.commit(
        _linesWidget(messageLines(all.substring(0, end), const Style())),
      ),
    );
  }

  /// Keeps [message] until [flush]: for what should come after the rest
  /// of the output, such as a summary of warnings.
  void delayed(Object? message) => _delayed.add(message);

  /// Writes the messages [delayed] kept, in order, through [info], and
  /// forgets them.
  void flush() {
    final messages = [..._delayed];
    _delayed.clear();
    messages.forEach(info);
  }

  /// [text], or [uri] itself, as a hyperlink to [uri] (OSC 8) where the
  /// terminal takes them, else the label alone; a message reads it back as
  /// a span with that link.
  String link(Uri uri, [String? text]) {
    final label = text ?? '$uri';
    return _caps.hyperlinks ? '\x1B]8;;$uri\x1B\\$label\x1B]8;;\x1B\\' : label;
  }

  /// Shows [widget] once, laid out at the terminal's width, or [width]
  /// columns, as tall as it is there; completes once it is written.
  ///
  /// In the interactive mode it is committed to the terminal's history
  /// above what is live (the inline session is opened for it the first
  /// time). Elsewhere it is built and painted once, outside an app, and
  /// its rows written as lines: as text, with the styles' escapes where
  /// the terminal takes them; 80 columns wide where the output is no
  /// terminal and `COLUMNS` says nothing. Either way it is shown under
  /// the [theme]'s [CliTheme.data].
  ///
  /// ```dart
  /// await Cli.current.show(
  ///   const Column(
  ///     children: [
  ///       Text('Deployed', style: Style(attrs: Attr.bold)),
  ///       Text('3 services'),
  ///     ],
  ///   ),
  /// );
  /// ```
  Future<void> show(Widget widget, {int? width}) async {
    if (mode == CliMode.interactive && !_sessionEnded && !_closed) {
      final session = await this.session();
      final shown = width == null
          ? widget
          // a Row asks its child for its height at its own width
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [SizedBox(width: width, child: widget)],
            );
      await session.commit(shown);
      return;
    }
    final lines = widgetLines(
      widget,
      width ?? terminal.columns ?? 80,
      theme: theme.data,
      // the core's warnings about it are the console's, at their level
      onLog: (record) => switch (record.level) {
        LogLevel.error => err(record.message),
        LogLevel.warning => warn(record.message),
        LogLevel.info => info(record.message),
        LogLevel.debug => detail(record.message),
      },
      ansi: _caps.ansi,
      hyperlinks: _caps.hyperlinks,
      colorMode: _caps.colorMode,
      styledUnderlines: styledUnderlines,
    );
    final out = terminal.out;
    lines.forEach(out.writeln);
  }

  late final _prompter = Prompter(this);

  /// Asks [question] and answers the line typed, [defaultValue] for an
  /// empty one (the empty string without one).
  ///
  /// [validate] refuses an answer with a message, which is shown, and the
  /// question is asked again. With [hidden] the answer is not shown as it
  /// is typed: masked with one `*` per character in the interactive mode,
  /// not echoed in the plain one; written back, it reads `******`
  /// whatever its length.
  ///
  /// How it asks follows the [mode]:
  ///
  /// * [CliMode.interactive]: a `TextField` in the inline session, after
  ///   the question and the default, [placeholder] in it while it is
  ///   empty; a refusal under it until the text changes. [suggest] gives
  ///   what to choose from for the text before the caret, shown under it
  ///   (`Autocomplete`: Up and Down choose, Enter or Tab put it in). Once
  ///   answered the field goes and `✔ question answer` is committed in its
  ///   place. Ctrl+C throws [PromptCancelledException] with
  ///   [PromptCancelReason.interrupt], Ctrl+D at an empty field with
  ///   [PromptCancelReason.endOfInput], `✗ question` committed.
  /// * [CliMode.plain]: `? question (default) `, then the line read as the
  ///   terminal reads it; the end of input throws
  ///   [PromptCancelledException] with [PromptCancelReason.endOfInput],
  ///   and Ctrl+C is the terminal's: SIGINT.
  /// * [CliMode.nonInteractive]: nothing is read, [defaultValue] is the
  ///   answer, written to the output as `? question answer` so a log shows
  ///   what was assumed. Without one, or with one [validate] refuses,
  ///   [PromptAnswerRequiredException].
  ///
  /// Prompts are asked one at a time: one asked while another is waits
  /// for it.
  ///
  /// ```dart
  /// final name = await Cli.current.prompt(
  ///   'Project name?',
  ///   defaultValue: 'my_app',
  ///   validate: (name) => RegExp(r'^[a-z_]+$').hasMatch(name)
  ///       ? null
  ///       : 'lowercase letters and _ only',
  /// );
  /// ```
  Future<String> prompt(
    String question, {
    String? defaultValue,
    bool hidden = false,
    String? Function(String answer)? validate,
    FutureOr<List<String>> Function(String typed)? suggest,
    String? placeholder,
  }) => _prompter.prompt(
    question,
    defaultValue: defaultValue,
    hidden: hidden,
    validate: validate,
    suggest: suggest,
    placeholder: placeholder,
  );

  /// Asks [question] for many values on one line, split on [separator]
  /// and trimmed, the blank ones dropped; an empty line answers
  /// [defaultValues], or none without them.
  ///
  /// [validate] refuses the values with a message, and the question is
  /// asked again. It asks as [prompt] does, the values shown joined by
  /// commas once answered; where nobody can answer, without
  /// [defaultValues], or with values [validate] refuses,
  /// [PromptAnswerRequiredException].
  ///
  /// ```dart
  /// final tags = await Cli.current.promptAny(
  ///   'Tags?',
  ///   defaultValues: ['cli', 'dart'],
  /// );
  /// ```
  Future<List<String>> promptAny(
    String question, {
    String separator = ',',
    List<String>? defaultValues,
    String? Function(List<String> answer)? validate,
    String? placeholder,
  }) => _prompter.promptAny(
    question,
    separator: separator,
    defaultValues: defaultValues,
    validate: validate,
    placeholder: placeholder,
  );

  /// Asks [question], answered yes (true) or no (false); [defaultValue] is
  /// what Enter, or an empty line, answers.
  ///
  /// Without a default nothing is agreed to on anybody's behalf: Enter
  /// answers nothing until yes or no is chosen, and where nobody can
  /// answer it throws [PromptAnswerRequiredException], so a question that
  /// changes something wants a `--yes` flag for unattended runs.
  ///
  /// * [CliMode.interactive]: the question and the answers of a
  ///   `ConfirmInput`; `y` and `n` answer, Left and Right move the
  ///   highlight, Enter answers it. `✔ question yes` is committed.
  /// * [CliMode.plain]: `? question [Y/n] `, asked again until the answer
  ///   is `y`, `yes`, `n` or `no` in any case, or empty with a default.
  /// * [CliMode.nonInteractive]: [defaultValue], written as `? question
  ///   yes`.
  ///
  /// Ctrl+C, Ctrl+D and the end of input leave it as they leave [prompt].
  ///
  /// ```dart
  /// if (await Cli.current.confirm('Proceed?', defaultValue: true)) {
  ///   Cli.current.info('Proceeding.');
  /// }
  /// ```
  Future<bool> confirm(String question, {bool? defaultValue}) =>
      _prompter.confirm(question, defaultValue: defaultValue);

  /// Asks [question] for one of [choices], which must not be empty, each
  /// shown as [display] makes it (its `toString` without).
  ///
  /// * [CliMode.interactive]: a `SelectionList` of them under the
  ///   question, seven rows at most: Up and Down move, Enter picks the one
  ///   the cursor is on, which starts on [defaultValue], or the first.
  ///   With [filter] what is typed narrows the list to the choices it
  ///   matches (fuzzy, as a command palette does), Backspace takes it back;
  ///   null filters a list of more than seven.
  /// * [CliMode.plain]: the choices numbered (`1) dev`), then a number
  ///   read, or a choice as it reads; empty, [defaultValue], or the first.
  ///   Any other answer is asked again.
  /// * [CliMode.nonInteractive]: [defaultValue], written as `? question
  ///   choice`; a [defaultValue] that is not one of [choices], or none,
  ///   throws [PromptAnswerRequiredException].
  ///
  /// Ctrl+C, Ctrl+D (with nothing typed to filter) and the end of input
  /// leave it as they leave [prompt].
  ///
  /// ```dart
  /// final env = await Cli.current.chooseOne(
  ///   'Target environment?',
  ///   choices: ['dev', 'stage', 'prod'],
  ///   defaultValue: 'dev',
  /// );
  /// ```
  Future<T> chooseOne<T>(
    String question, {
    required List<T> choices,
    T? defaultValue,
    String Function(T choice)? display,
    bool? filter,
  }) => _prompter.chooseOne(
    question,
    choices: choices,
    defaultValue: defaultValue,
    display: display,
    filter: filter,
  );

  /// Asks [question] for any of [choices], which must not be empty,
  /// answered in the order of [choices]: at least [min] of them, at most
  /// [max] (no limit when null); a choice of fewer or more is refused
  /// with a message and asked again.
  ///
  /// It asks as [chooseOne] does, Space toggling the choice the cursor is
  /// on, those of [defaultValues] toggled at first; in the plain mode the
  /// numbers are separated by commas or blanks (`1,3`), and an empty
  /// answer is [defaultValues]. Once answered they are shown joined by
  /// commas. Where nobody can answer, a prompt without [defaultValues],
  /// or with fewer or more of them than [min] and [max] allow, throws
  /// [PromptAnswerRequiredException].
  ///
  /// ```dart
  /// final features = await Cli.current.chooseAny(
  ///   'Features?',
  ///   choices: ['Linter', 'Docker', 'Tests'],
  ///   defaultValues: ['Linter'],
  /// );
  /// ```
  Future<List<T>> chooseAny<T>(
    String question, {
    required List<T> choices,
    List<T>? defaultValues,
    String Function(T choice)? display,
    bool? filter,
    int min = 0,
    int? max,
  }) => _prompter.chooseAny(
    question,
    choices: choices,
    defaultValues: defaultValues,
    display: display,
    filter: filter,
    min: min,
    max: max,
  );

  /// Shows [error], thrown at [stack], as [Cli.run] shows what its body
  /// throws, for an error the program caught: its [traceback] on the error
  /// output at [LogLevel.error], committed above what is live while an
  /// inline session holds the screen; every frame at [LogLevel.debug]
  /// (`--verbose`), those of the app's own code alone otherwise.
  ///
  /// ```dart
  /// try {
  ///   await build();
  /// } on Object catch (error, stack) {
  ///   Cli.current.error(error, stack);
  /// }
  /// ```
  void error(Object error, StackTrace stack) => unawaited(_error(error, stack));

  Future<void> _error(Object error, StackTrace stack) => _logLines(
    traceback(
      error,
      stack,
      allFrames: level.index <= LogLevel.debug.index,
      theme: theme.lineData,
      errorStyle: theme.error,
      hintStyle: theme.hint,
      sourceLines: sourceLines,
    ),
    LogLevel.error,
    toErr: true,
  );

  /// Shows [value] as a `JsonView` shows it, every object and array
  /// expanded, or those less than [expandedDepth] levels below the top
  /// ([jsonLines]): at [LogLevel.info], to the output, committed above
  /// what is live while an inline session holds the screen; completes
  /// once it is written.
  ///
  /// Its first line starts with the value's runtime type, after [label]
  /// where there is one: `config: _Map<String, Object?> {`. Objects other
  /// than JSON's are shown through their `toJson()` where they have one,
  /// else their `toString()`; a value inside itself as `<cycle>`.
  ///
  /// ```dart
  /// await Cli.current.inspect({
  ///   'name': 'twk',
  ///   'tags': ['tui', 'cli'],
  /// }, label: 'config');
  /// ```
  Future<void> inspect(Object? value, {String? label, int? expandedDepth}) {
    final lines = jsonLines(
      value,
      theme: _syntax,
      expandedDepth: expandedDepth,
    );
    lines[0] = [
      if (label != null) ...[Span(label, theme.question), const Span(': ')],
      Span('${value.runtimeType}', theme.hint),
      const Span(' '),
      ...lines[0],
    ];
    return _logLines(lines, LogLevel.info, toErr: false);
  }

  SyntaxTheme get _syntax => SyntaxTheme.from(
    theme.lineData,
  );

  /// Ends a run of [Cli.run] that [error] ended: shows it, as a
  /// [PromptException] ends one or as a traceback, and sets the exit code.
  Future<void> _failed(
    Object error,
    StackTrace stack,
    int errorExitCode,
  ) async {
    switch (error) {
      case PromptCancelledException(:final question, :final reason):
        // the interactive prompt shows `✗ question` itself
        if (mode != CliMode.interactive) {
          await _logLines(
            [
              [Span('✗ ', theme.error), Span(question, theme.question)],
            ],
            LogLevel.error,
            toErr: true,
          );
        }
        terminal.exitCode = reason == PromptCancelReason.interrupt
            ? 130
            : errorExitCode;
      case PromptAnswerRequiredException(
        :final question,
        :final invalidDefault,
      ):
        await _logLines(
          [
            [
              Span('✗ ', theme.error),
              Span(question, theme.question),
              Span(
                invalidDefault == null
                    ? '  nobody can answer, and it has no default'
                    : '  nobody can answer, and its default is refused: '
                          '$invalidDefault',
                theme.hint,
              ),
            ],
          ],
          LogLevel.error,
          toErr: true,
        );
        terminal.exitCode = errorExitCode;
      default:
        await _error(error, stack);
        terminal.exitCode = errorExitCode;
    }
  }

  /// Shows [message] while an operation goes on, until the progress is
  /// closed ([CliProgress.complete], [CliProgress.fail],
  /// [CliProgress.cancel]), [CliProgress.run] closing it on the outcome of
  /// a body.
  ///
  /// What it shows follows what the output can do:
  ///
  /// * [CliMode.interactive]: a spinner, the message and the time so far,
  ///   live in the inline session, below the prompts asked meanwhile, with
  ///   the lines logged meanwhile above it; the closing line committed in
  ///   its place with the time it took, `✓ Built in 3.1 s`.
  /// * A terminal that does not redraw, or where nobody answers: the
  ///   message as it starts, each changed message, the closing line,
  ///   `✓ Built`.
  /// * Output that is no terminal: the closing line alone.
  ///
  /// ```dart
  /// await Cli.current
  ///     .progress('Building')
  ///     .run(build, done: (_) => 'Built');
  /// ```
  CliProgress progress(String message) => CliProgress(this, message);

  /// Runs [body] with a [ProgressTracker] whose tasks are shown as the
  /// output allows, and completes with what the body does, its error
  /// thrown again; the tracker is disposed once it has ended.
  ///
  /// * [CliMode.interactive]: a [ProgressList] of [columns]
  ///   ([ProgressList.defaultColumns] without: the mark, the label, the
  ///   bar, the percent, the rate and the time left), its bars in
  ///   [barShape] (a thin line by default) and [maxBarWidth] cells at most
  ///   (null for all the room the row leaves), live in the inline
  ///   session, below the prompts asked meanwhile, with the lines logged
  ///   meanwhile above it; the terminal's tab shows how much of all of it
  ///   is done (OSC 9;4, where the terminal takes it). Once the body ends,
  ///   the list as it stands is committed in its place. With
  ///   [hideFinished] a task done or skipped leaves the list, its
  ///   [ProgressTask.summary] committed above it.
  /// * A terminal that does not redraw, or where nobody answers: each
  ///   task's label as it is set going (and as it changes while it runs),
  ///   and its summary once it ends:
  ///   `✓ Downloading assets.zip • 3.4/3.4 MB • 2.1 s`.
  /// * Output that is no terminal: each task's summary as it ends.
  ///
  /// The times, rates and times left are read on the [terminal]'s clock.
  ///
  /// ```dart
  /// await Cli.current.tasks(
  ///   (tracker) => Future.wait([
  ///     tracker.run(
  ///       'Downloading assets.zip',
  ///       (task) => download(task.advance),
  ///       total: size,
  ///       unit: ProgressUnit.bytes,
  ///     ),
  ///     tracker.run('Building binary', (_) => build()),
  ///   ]),
  /// );
  /// ```
  Future<T> tasks<T>(
    FutureOr<T> Function(ProgressTracker tracker) body, {
    List<ProgressColumn>? columns,
    bool hideFinished = false,
    ProgressBarShape barShape = ProgressBarShape.line,
    int? maxBarWidth = 30,
  }) => runTasks(
    this,
    body,
    columns: columns,
    hideFinished: hideFinished,
    barShape: barShape,
    maxBarWidth: maxBarWidth,
  );

  /// Writes [line] to the output, with escapes where the terminal takes
  /// them, whatever the [level]: what prompts and progress write outside
  /// the inline session.
  @internal
  void writeLine(List<Span> line) => terminal.out.writeln(
    encodeLine(
      line,
      ansi: _caps.ansi,
      hyperlinks: _caps.hyperlinks,
      colorMode: _caps.colorMode,
      styledUnderlines: styledUnderlines,
    ),
  );

  /// The inline session of the interactive mode, opened the first time it
  /// is asked for and kept until [close]: what the prompts and progress
  /// of this package mount their widgets in. A [StateError] in another
  /// mode, or once the session has ended.
  @internal
  Future<CliSession> session() {
    if (mode != CliMode.interactive) {
      throw StateError('no inline session in the ${mode.name} mode');
    }
    if (_sessionEnded || _closed) {
      throw StateError('the inline session has ended');
    }
    return _opening ??=
        CliSession.open(
          terminal,
          theme: theme.data,
          onInterrupt: _interrupted,
        ).then((session) {
          _probedUnderlines = session.styledUnderlines;
          return _session = session;
        });
  }

  /// Whether the inline session has ended, or the console is closed: no
  /// session opens again.
  @internal
  bool get sessionEnded => _sessionEnded || _closed;

  /// The session while it holds the screen.
  CliSession? get _liveSession => switch (_session) {
    final session? when session.isOpen => session,
    _ => null,
  };

  void _interrupted() {
    _sessionEnded = true;
    _session = null;
    terminal.interrupt();
  }

  /// Ends the inline session where one is open, what [write] left without
  /// a line break written first, so the terminal is restored with the
  /// cursor below the output; then flushes the terminal and closes it
  /// ([CliTerminal.close]): stdin is let go of where a plain prompt read
  /// it, so the process can end. Calling it again does nothing more.
  /// [Cli.run] calls it.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    final opening = _opening;
    if (opening != null) {
      final session = await opening;
      if (_partial.isNotEmpty && session.isOpen) {
        unawaited(
          session.commit(
            _linesWidget(messageLines(_partial.toString(), const Style())),
          ),
        );
        _partial.clear();
      }
      _sessionEnded = true;
      _session = null;
      await session.close();
    }
    if (_partial.isNotEmpty) {
      terminal.out.write(_partial.toString());
      _partial.clear();
    }
    await terminal.flush();
    await terminal.close();
  }

  void _log(
    Object? message,
    LogLevel channel,
    Style style, {
    required bool toErr,
  }) {
    if (channel.index < level.index) {
      return;
    }
    unawaited(_logLines(messageLines(message, style), channel, toErr: toErr));
  }

  /// Writes [lines] where [_log] writes a message of [channel], once its
  /// [level] lets it through; completes once they are written.
  Future<void> _logLines(
    List<List<Span>> lines,
    LogLevel channel, {
    required bool toErr,
  }) async {
    if (channel.index < level.index) {
      return;
    }
    final session = _liveSession;
    if (session != null && (!toErr || _caps.errorIsTerminal)) {
      await session.commit(_linesWidget(lines));
      return;
    }
    final sink = toErr ? terminal.err : terminal.out;
    for (final line in lines) {
      sink.writeln(
        encodeLine(
          line,
          ansi: _caps.ansi,
          hyperlinks: _caps.hyperlinks,
          colorMode: _caps.colorMode,
          styledUnderlines: styledUnderlines,
        ),
      );
    }
  }

  static Widget _linesWidget(List<List<Span>> lines) => lines.length == 1
      ? _line(lines.single)
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final line in lines) _line(line)],
        );

  static Widget _line(List<Span> line) =>
      line.isEmpty ? const Text(' ') : Text.rich(line);
}
