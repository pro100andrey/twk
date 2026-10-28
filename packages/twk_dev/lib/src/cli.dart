/// The `twk` command: [runTwk] runs it on a command line.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import 'create.dart';
import 'inspect.dart';
import 'logs.dart';
import 'play.dart';
import 'record.dart';
import 'run.dart';
import 'shell.dart';
import 'tape.dart';

// Examples can assume:
// import 'dart:io';

/// The exit code of a command line that names no known subcommand or option.
const usageExitCode = 64;

/// Runs the `twk` command on [arguments] and returns its exit code.
///
/// `--help`, `help` and no arguments at all print the usage and give 0; an
/// unknown subcommand or option prints the error with the usage to stderr
/// and gives [usageExitCode].
///
/// The `twk` executable is this:
///
/// ```dart
/// Future<void> main(List<String> arguments) async {
///   exitCode = await runTwk(arguments);
/// }
/// ```
Future<int> runTwk(List<String> arguments) async {
  final runner =
      CommandRunner<int>('twk', 'Developer tools for apps built on twk.')
        ..addCommand(CreateCommand())
        ..addCommand(RunCommand())
        ..addCommand(InspectCommand())
        ..addCommand(LogsCommand())
        ..addCommand(ShellCommand())
        ..addCommand(RecordCommand())
        ..addCommand(PlayCommand())
        ..addCommand(TapeCommand());
  try {
    return await runner.run(arguments) ?? 0;
  } on UsageException catch (error) {
    stderr.writeln(error);
    return usageExitCode;
  }
}
