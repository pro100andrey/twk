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

/// A wait that ended because the app did: its process exited, its
/// terminal ended, or its VM service closed. Not a timeout.
final class AppEnded extends DriverError {
  /// The end of an app: [reason] says which, [exitCode] is the code when
  /// the process exited, [screen] and [log] what was last seen.
  AppEnded(
    String reason, {
    required this.exitCode,
    required this.screen,
    required this.log,
  }) : super(
         '$reason${exitCode == null ? '' : ' ($exitCode)'}\n'
         'screen at the end:\n$screen'
         '${log.isEmpty ? '' : '\nlast log records:\n${log.join('\n')}'}',
       );

  /// The exit code of the process, null while it is not known.
  final int? exitCode;

  /// The screen as the frames showed it last, as text.
  final String screen;

  /// The last log records the app wrote, as text lines.
  final List<String> log;
}
