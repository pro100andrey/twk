/// The prompts of a [Cli], as each of its modes asks them: [Prompter].
///
/// @docImport 'cli.dart';
library;

import 'dart:async';

import 'package:twk/twk.dart';

import 'capabilities.dart';
import 'cli.dart';
import 'lines.dart';
import 'prompt_exception.dart';
import 'prompt_views.dart';

/// How a hidden answer reads once given, whatever its length: the history
/// does not keep how long a secret is.
const hiddenAnswer = '******';

/// How many choices a list shows at once, and above how many a list is
/// filtered by what is typed unless told.
const choicesShown = 7;

/// Asks the questions of a [Cli] the way its mode allows, one at a time:
///
/// * interactive: a widget mounted in the inline session, which goes once
///   it is answered, `✔ question answer` committed in its place; Ctrl+C
///   cancels it (`✗ question`), as Ctrl+D at an empty line does;
/// * plain: a line read as the terminal reads it, the choices numbered,
///   asked again until the answer is one;
/// * non-interactive: nothing is read, the default is the answer, written
///   as `? question answer`; without one, or with one refused,
///   [PromptAnswerRequiredException].
final class Prompter {
  /// The prompts of [cli].
  Prompter(this.cli);

  /// The console the prompts ask through.
  final Cli cli;

  // the prompt asked last, which the next one waits for
  Future<void> _last = Future.value();

  CliMode get _mode => cli.mode;

  /// See [Cli.prompt].
  Future<String> prompt(
    String question, {
    String? defaultValue,
    bool hidden = false,
    String? Function(String answer)? validate,
    FutureOr<List<String>> Function(String typed)? suggest,
    String? placeholder,
  }) => _serial(() async {
    String shown(String value) =>
        hidden && value.isNotEmpty ? hiddenAnswer : value;
    switch (_mode) {
      case CliMode.nonInteractive:
        if (defaultValue == null) {
          throw PromptAnswerRequiredException(question);
        }
        if (validate?.call(defaultValue) case final refused?) {
          throw PromptAnswerRequiredException(
            question,
            invalidDefault: refused,
          );
        }
        _writeLine(_assumed(question, shown(defaultValue)));
        return defaultValue;
      case CliMode.plain:
        while (true) {
          _write(_asking(question, hint: hidden ? null : defaultValue));
          final line = await _readLine(question, hidden: hidden);
          final value = line.isEmpty ? defaultValue ?? '' : line;
          final refused = validate?.call(value);
          if (refused == null) {
            return value;
          }
          _writeLine(_refused(refused));
        }
      case CliMode.interactive:
        return _live<String>(
          question,
          (answer) => TextPromptView(
            answer: answer,
            theme: cli.theme,
            question: question,
            hint: hidden ? null : defaultValue,
            hidden: hidden,
            placeholder: placeholder,
            suggest: hidden ? null : suggest,
            submit: (text) {
              final value = text.isEmpty ? defaultValue ?? '' : text;
              final refused = validate?.call(value);
              if (refused == null) {
                answer.give(value, shown(value));
              }
              return refused;
            },
          ),
        );
    }
  });

  /// See [Cli.promptAny].
  Future<List<String>> promptAny(
    String question, {
    String separator = ',',
    List<String>? defaultValues,
    String? Function(List<String> answer)? validate,
    String? placeholder,
  }) => _serial(() async {
    if (separator.isEmpty) {
      throw ArgumentError.value(separator, 'separator', 'must not be empty');
    }
    List<String> split(String line) => line.trim().isEmpty
        ? [...?defaultValues]
        : [
            for (final part in line.split(separator))
              if (part.trim().isNotEmpty) part.trim(),
          ];
    final joiner = separator.trim().isEmpty ? separator : '$separator ';
    final hint = defaultValues?.join(joiner);
    String shown(List<String> values) => values.join(', ');
    switch (_mode) {
      case CliMode.nonInteractive:
        if (defaultValues == null) {
          throw PromptAnswerRequiredException(question);
        }
        if (validate?.call(defaultValues) case final refused?) {
          throw PromptAnswerRequiredException(
            question,
            invalidDefault: refused,
          );
        }
        _writeLine(_assumed(question, shown(defaultValues)));
        return [...defaultValues];
      case CliMode.plain:
        while (true) {
          _write(_asking(question, hint: hint));
          final values = split(await _readLine(question));
          final refused = validate?.call(values);
          if (refused == null) {
            return values;
          }
          _writeLine(_refused(refused));
        }
      case CliMode.interactive:
        return _live<List<String>>(
          question,
          (answer) => TextPromptView(
            answer: answer,
            theme: cli.theme,
            question: question,
            hint: hint,
            placeholder: placeholder,
            submit: (text) {
              final values = split(text);
              final refused = validate?.call(values);
              if (refused == null) {
                answer.give(values, shown(values));
              }
              return refused;
            },
          ),
        );
    }
  });

  /// See [Cli.confirm].
  Future<bool> confirm(String question, {bool? defaultValue}) =>
      _serial(() async {
        String shown(bool value) => value ? 'yes' : 'no';
        switch (_mode) {
          case CliMode.nonInteractive:
            if (defaultValue == null) {
              throw PromptAnswerRequiredException(question);
            }
            _writeLine(_assumed(question, shown(defaultValue)));
            return defaultValue;
          case CliMode.plain:
            final hint = switch (defaultValue) {
              true => 'Y/n',
              false => 'y/N',
              null => 'y/n',
            };
            while (true) {
              _write(_asking(question, hint: hint, brackets: '[]'));
              switch ((await _readLine(question)).trim().toLowerCase()) {
                case '' when defaultValue != null:
                  return defaultValue;
                case 'y' || 'yes':
                  return true;
                case 'n' || 'no':
                  return false;
              }
              _writeLine(_refused('answer y or n'));
            }
          case CliMode.interactive:
            return _live<bool>(
              question,
              (answer) => ConfirmPromptView(
                answer: answer,
                theme: cli.theme,
                question: question,
                defaultValue: defaultValue,
                submit: (value) => answer.give(value, shown(value)),
              ),
            );
        }
      });

  /// See [Cli.chooseOne].
  Future<T> chooseOne<T>(
    String question, {
    required List<T> choices,
    T? defaultValue,
    String Function(T choice)? display,
    bool? filter,
  }) => _serial(() async {
    _requireChoices(choices);
    final labels = _labels(choices, display);
    final initial = defaultValue == null ? -1 : choices.indexOf(defaultValue);
    switch (_mode) {
      case CliMode.nonInteractive:
        if (initial < 0) {
          throw PromptAnswerRequiredException(question);
        }
        _writeLine(_assumed(question, labels[initial]));
        return choices[initial];
      case CliMode.plain:
        _numbered(question, labels);
        final fallback = initial < 0 ? 0 : initial;
        while (true) {
          _write([
            Span('Enter a number', cli.theme.hint),
            Span(' (${fallback + 1})', cli.theme.hint),
            const Span(': '),
          ]);
          final line = (await _readLine(question)).trim();
          if (line.isEmpty) {
            return choices[fallback];
          }
          final picked = _pick(line, labels);
          if (picked != null) {
            return choices[picked];
          }
          _writeLine(_refused('answer a number from 1 to ${labels.length}'));
        }
      case CliMode.interactive:
        return _live<T>(
          question,
          (answer) => ChoicePromptView(
            answer: answer,
            theme: cli.theme,
            question: question,
            labels: labels,
            multiple: false,
            selected: {if (initial >= 0) initial},
            filter: filter ?? choices.length > choicesShown,
            submit: (picked) {
              final i = picked.single;
              answer.give(choices[i], labels[i]);
              return null;
            },
          ),
        );
    }
  });

  /// See [Cli.chooseAny].
  Future<List<T>> chooseAny<T>(
    String question, {
    required List<T> choices,
    List<T>? defaultValues,
    String Function(T choice)? display,
    bool? filter,
    int min = 0,
    int? max,
  }) => _serial(() async {
    _requireChoices(choices);
    if (min < 0 || min > choices.length) {
      throw RangeError.range(min, 0, choices.length, 'min');
    }
    if (max != null && (max < min || max < 1)) {
      throw RangeError.range(max, min < 1 ? 1 : min, null, 'max');
    }
    final labels = _labels(choices, display);
    final initial = {
      for (final value in defaultValues ?? <T>[])
        if (choices.indexOf(value) case final i when i >= 0) i,
    };
    List<T> inOrder(Set<int> picked) => [
      for (var i = 0; i < choices.length; i++)
        if (picked.contains(i)) choices[i],
    ];
    String shown(Set<int> picked) => picked.isEmpty
        ? 'none'
        : [
            for (var i = 0; i < choices.length; i++)
              if (picked.contains(i)) labels[i],
          ].join(', ');
    String? refuse(Set<int> picked) => picked.length < min
        ? 'choose at least $min'
        : max != null && picked.length > max
        ? 'choose at most $max'
        : null;
    switch (_mode) {
      case CliMode.nonInteractive:
        if (defaultValues == null) {
          throw PromptAnswerRequiredException(question);
        }
        if (refuse(initial) case final refused?) {
          throw PromptAnswerRequiredException(
            question,
            invalidDefault: refused,
          );
        }
        _writeLine(_assumed(question, shown(initial)));
        return inOrder(initial);
      case CliMode.plain:
        _numbered(question, labels);
        final hint = initial.isEmpty
            ? null
            : ([...initial]..sort()).map((i) => i + 1).join(',');
        while (true) {
          _write([
            Span('Enter numbers separated by commas', cli.theme.hint),
            if (hint != null) Span(' ($hint)', cli.theme.hint),
            const Span(': '),
          ]);
          final line = (await _readLine(question)).trim();
          final picked = line.isEmpty ? {...initial} : _pickAll(line, labels);
          final refused = picked == null
              ? 'answer numbers from 1 to ${labels.length}'
              : refuse(picked);
          if (refused == null) {
            return inOrder(picked!);
          }
          _writeLine(_refused(refused));
        }
      case CliMode.interactive:
        return _live<List<T>>(
          question,
          (answer) => ChoicePromptView(
            answer: answer,
            theme: cli.theme,
            question: question,
            labels: labels,
            multiple: true,
            selected: initial,
            filter: filter ?? choices.length > choicesShown,
            submit: (picked) {
              if (refuse(picked) case final refused?) {
                return refused;
              }
              answer.give(inOrder(picked), shown(picked));
              return null;
            },
          ),
        );
    }
  });

  /// Runs [body] once the prompt asked before it is done.
  Future<T> _serial<T>(Future<T> Function() body) {
    final asked = _last.then((_) => body());
    _last = asked.then<void>((_) {}, onError: (Object _) {});
    return asked;
  }

  /// Mounts what [build] builds in the inline session until it is
  /// answered or cancelled, and commits the line it leaves in its place.
  Future<T> _live<T>(
    String question,
    Widget Function(PromptAnswer<T> answer) build,
  ) async {
    if (cli.sessionEnded) {
      // stdin went with it
      throw PromptCancelledException(question, PromptCancelReason.endOfInput);
    }
    final session = await cli.session();
    final answer = PromptAnswer<T>(question);
    final live = session.mount(build(answer));
    unawaited(
      session.done.then(
        (_) => answer.cancel(PromptCancelReason.interrupt),
        onError: answer.fail,
      ),
    );
    List<Span> line;
    try {
      final (value, shown) = await answer.future;
      line = _answered(question, shown);
      final written = session.commit(lineWidget(line));
      live.remove();
      await written;
      return value;
    } on PromptCancelledException {
      line = _cancelled(question);
      final written = session.commit(lineWidget(line));
      live.remove();
      await written;
      rethrow;
    }
  }

  Future<String> _readLine(String question, {bool hidden = false}) async {
    final terminal = cli.terminal;
    final line = await terminal.readLine(hidden: hidden);
    if (line != null) {
      return line;
    }
    if (terminal.capabilities.outputIsTerminal) {
      // Ctrl+D ends no line at the terminal: what comes next starts one
      terminal.out.writeln();
    }
    throw PromptCancelledException(question, PromptCancelReason.endOfInput);
  }

  /// `? question (hint) `, as a plain prompt asks.
  List<Span> _asking(String question, {String? hint, String brackets = '()'}) {
    final theme = cli.theme;
    return [
      Span('? ', theme.answer),
      Span(question, theme.question),
      if (hint != null && hint.isNotEmpty)
        Span(' ${brackets[0]}$hint${brackets[1]}', theme.hint),
      const Span(' '),
    ];
  }

  /// `? question answer`: what was assumed where nobody can answer.
  List<Span> _assumed(String question, String answer) {
    final theme = cli.theme;
    return [
      Span('? ', theme.answer),
      Span(question, theme.question),
      if (answer.isNotEmpty) Span(' $answer', theme.answer),
    ];
  }

  /// `✔ question answer`: what an answered prompt leaves.
  List<Span> _answered(String question, String answer) {
    final theme = cli.theme;
    return [
      Span('✔ ', theme.success),
      Span(question, theme.question),
      if (answer.isNotEmpty) Span(' $answer', theme.answer),
    ];
  }

  /// `✗ question`: what a cancelled prompt leaves.
  List<Span> _cancelled(String question) {
    final theme = cli.theme;
    return [Span('✗ ', theme.error), Span(question, theme.question)];
  }

  /// `✗ message`: why an answer was refused.
  List<Span> _refused(String message) {
    final error = cli.theme.error;
    return [Span('✗ ', error), Span(message, error)];
  }

  /// The question, then the choices numbered from 1.
  void _numbered(String question, List<String> labels) {
    _writeLine(_asking(question)..removeLast());
    for (var i = 0; i < labels.length; i++) {
      _writeLine([
        const Span('  '),
        Span('${i + 1}', cli.theme.hint),
        Span(') ${labels[i]}'),
      ]);
    }
  }

  /// The indices [answer] names, separated by commas or blanks; null
  /// where one of them names none.
  static Set<int>? _pickAll(String answer, List<String> labels) {
    final picked = <int>{};
    for (final token in answer.split(RegExp(r'[,\s]+'))) {
      if (token.isEmpty) {
        continue;
      }
      final i = _pick(token, labels);
      if (i == null) {
        return null;
      }
      picked.add(i);
    }
    return picked;
  }

  /// The index [answer] names: its number from 1, or its label, in any
  /// case; null for none.
  static int? _pick(String answer, List<String> labels) {
    final n = int.tryParse(answer);
    if (n != null) {
      return n >= 1 && n <= labels.length ? n - 1 : null;
    }
    final lower = answer.toLowerCase();
    final i = labels.indexWhere((label) => label.toLowerCase() == lower);
    return i < 0 ? null : i;
  }

  void _write(List<Span> line) => cli.terminal.out.write(_encode(line));

  void _writeLine(List<Span> line) => cli.terminal.out.writeln(_encode(line));

  String _encode(List<Span> line) {
    final caps = cli.terminal.capabilities;
    return encodeLine(
      line,
      ansi: caps.ansi,
      hyperlinks: caps.hyperlinks,
      colorMode: caps.colorMode,
      styledUnderlines: caps.styledUnderlines,
    );
  }

  static List<String> _labels<T>(
    List<T> choices,
    String Function(T choice)? display,
  ) => [for (final choice in choices) display?.call(choice) ?? '$choice'];

  static void _requireChoices(List<Object?> choices) {
    if (choices.isEmpty) {
      throw ArgumentError.value(choices, 'choices', 'must not be empty');
    }
  }
}

/// [line] as a widget, for the session to commit.
Widget lineWidget(List<Span> line) =>
    line.isEmpty ? const Text(' ') : Text.rich(line);
