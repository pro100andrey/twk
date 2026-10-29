/// Why a prompt of a [Cli] returned no answer: [PromptException], and the
/// two ways it happens.
///
/// @docImport 'cli.dart';
library;

/// Why a prompt returned no answer.
///
/// Sealed so that a caller tells the two apart exhaustively: a person who
/// walked away ([PromptCancelledException]) is not a run that nobody could
/// be asked in ([PromptAnswerRequiredException]). A command line ends the
/// first quietly and turns the second into "pass `--flag`".
///
/// ```dart
/// Future<void> run(Cli cli) async {
///   try {
///     await cli.confirm('Overwrite?');
///   } on PromptException catch (e) {
///     switch (e) {
///       case PromptCancelledException():
///         cli.info('Cancelled.');
///       case PromptAnswerRequiredException(:final question):
///         cli.err('"$question" needs --yes where nobody can answer');
///     }
///   }
/// }
/// ```
sealed class PromptException implements Exception {
  /// [question] went unanswered.
  const PromptException(this.question);

  /// The question that went unanswered, as the prompt was given it.
  final String question;
}

/// How a person left a prompt without answering.
enum PromptCancelReason {
  /// Ctrl+C.
  interrupt,

  /// Ctrl+D at an empty line, or the end of input.
  endOfInput,
}

/// The person left the prompt without answering ([reason]): Ctrl+C,
/// Ctrl+D, or input ended. What the prompt showed is gone by the time it
/// is thrown, and in the interactive mode `✗ question` is committed in its
/// place.
final class PromptCancelledException extends PromptException {
  /// [question] was left for [reason].
  const PromptCancelledException(super.question, this.reason);

  /// What ended the prompt.
  final PromptCancelReason reason;

  @override
  String toString() =>
      'PromptCancelledException: "$question" was cancelled (${reason.name})';
}

/// Nobody can answer (the [Cli]'s mode is non-interactive: a pipe, `CI`,
/// `--no-input`) and the prompt has no default to take instead, or one its
/// validation refuses ([invalidDefault] says why).
///
/// Nothing is read before it is thrown, so a command line can catch it
/// and name the flag that answers [question].
final class PromptAnswerRequiredException extends PromptException {
  /// [question] has nobody to answer it, and no default, or one that
  /// failed validation with [invalidDefault].
  const PromptAnswerRequiredException(super.question, {this.invalidDefault});

  /// The message the default failed validation with; null when there was
  /// no default at all.
  final String? invalidDefault;

  @override
  String toString() => switch (invalidDefault) {
    null =>
      'PromptAnswerRequiredException: "$question" needs an answer, '
          'and nobody can answer',
    final reason =>
      'PromptAnswerRequiredException: "$question" needs an answer, '
          'nobody can answer and the default is refused: $reason',
  };
}
