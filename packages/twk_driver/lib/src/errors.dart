/// What a driver reports instead of a result: [DriverError].
library;

/// Something a driver could not do, saying why: a program that does not
/// compile, a wait that ended because the app did, a finder that matched
/// more than one node, a tap that would not reach its target.
///
/// A front end turns it into its own failure (twk_test's `TestFailure`, a
/// tool result of `twk mcp`); the driver itself depends on none of them.
class DriverError implements Exception {
  /// An error saying [message].
  const DriverError(this.message);

  /// What went wrong, for a person to read.
  final String message;

  @override
  String toString() => message;
}

/// A wait on an app that is quiet, so that nothing will change what is
/// waited for: no timer, no frame asked for, nothing held in its input
/// parser. The message advises the `io` option of the wait; a front end
/// that names it otherwise says so with [messageUsing].
final class QuietApp extends DriverError {
  /// The message made of [before] (up to the advice), the advice (to pass
  /// `io`, or to give more where [ioGiven]) and [after].
  QuietApp({
    required String before,
    required this.ioGiven,
    required String after,
  }) : _before = before,
       _after = after,
       super(_text(before, ioGiven, 'io', after));

  /// Whether the wait had an `io` time already.
  final bool ioGiven;

  final String _before;
  final String _after;

  /// The message with the advice naming the argument [option] instead of
  /// `io`.
  String messageUsing(String option) => _text(_before, ioGiven, option, _after);

  static String _text(
    String before,
    bool ioGiven,
    String option,
    String after,
  ) =>
      '$before'
      "${ioGiven ? 'give $option: more' : 'pass $option: to wait for it'}"
      '$after';
}

/// How an app ended, and what was last seen of it.
final class ExitResult {
  /// An end: the process's [code] (null where it is not known), the last
  /// [screen] as text, the last log records ([log]), whether it was
  /// [expected] (the app said it was quitting, or the driver closed it) and
  /// how it [reason] came to be known.
  const ExitResult({
    required this.code,
    required this.screen,
    required this.log,
    required this.expected,
    required this.reason,
  });

  /// The exit code of the process, null where it is not known.
  final int? code;

  /// The screen as the frames showed it last, as text.
  final String screen;

  /// The last log records the app wrote, as text lines.
  final List<String> log;

  /// Whether the app quit as it said it would (`quitting` in its last
  /// acknowledgement) or the driver closed it, and did not fail.
  final bool expected;

  /// What ended: `the app exited`, `the app's terminal ended`, `the app's
  /// VM service closed`.
  final String reason;

  /// `the app exited (0)`, or `the app exited unexpectedly (1)` where the
  /// app did not say it was quitting.
  String get message =>
      '${expected ? reason : '$reason unexpectedly'}'
      '${code == null ? '' : ' ($code)'}';

  @override
  String toString() => message;
}

/// A wait that ended because the app did: its process exited, its
/// terminal ended, or its VM service closed. Not a timeout. Thrown where
/// the app ended without saying it was quitting ([expected] false) and by
/// calls that have no step to return it in.
final class AppEnded extends DriverError {
  /// The end [result] of an app, with the screen and log it left.
  AppEnded(this.result)
    : super(
        '${result.message}\n'
        'screen at the end:\n${result.screen}${_logOf(result.log)}',
      );

  static String _logOf(List<String> log) =>
      log.isEmpty ? '' : '\nlast log records:\n${log.join('\n')}';

  /// How it ended.
  final ExitResult result;

  /// The exit code of the process, null while it is not known.
  int? get exitCode => result.code;

  /// The screen as the frames showed it last, as text.
  String get screen => result.screen;

  /// The last log records the app wrote, as text lines.
  List<String> get log => result.log;

  /// Whether the app said it was quitting.
  bool get expected => result.expected;
}
