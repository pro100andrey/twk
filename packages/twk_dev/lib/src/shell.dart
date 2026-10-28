/// `twk shell`: [ShellCommand].
library;

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:twk_core/twk_core.dart';

import 'project.dart';

/// `twk shell`: serves this terminal to the apps of the project, started
/// elsewhere ([TerminalShell]), until Ctrl+C while no app has it, SIGTERM
/// or the terminal being closed.
final class ShellCommand extends Command<int> {
  /// Sets up `twk shell`'s option: `--directory`.
  ShellCommand() {
    argParser.addOption(
      'directory',
      abbr: 'C',
      valueHelp: 'path',
      help:
          'A directory of the project whose apps to serve (default: the '
          'current one).',
    );
  }

  @override
  String get name => 'shell';

  @override
  String get invocation => 'twk shell [--directory=<path>]';

  @override
  String get description =>
      'Serve this terminal to an app started elsewhere.\n\n'
      'Owns this terminal and serves it over a local socket to an app of '
      'the project started without a terminal (from the IDE, under the '
      'debugger), so that breakpoints leave the screen alone: the app '
      "finds the shell by the address file in the project's "
      '.dart_tool/twk. One app at a time, the newest; when it goes away '
      'the terminal is put back. Ctrl+C while no app has the terminal '
      'stops the shell.';

  @override
  Future<int> run() async {
    final project = projectOf(argResults!.option('directory'));
    final TerminalShell shell;
    try {
      shell = await TerminalShell.start(
        directory: project,
        onEvent: (event) => _say(switch (event) {
          ShellEvent.connected => 'an app connected',
          ShellEvent.disconnected => 'the app went away; waiting for the next',
        }),
      );
    } on TerminalException catch (e) {
      stderr.writeln('twk shell: ${e.message}');
      return 1;
    }
    _shell = shell;
    var code = 0;
    void stopWith(int exitCode) {
      code = exitCode;
      unawaited(shell.stop());
    }

    final signals = [
      // Ctrl+C reaches the shell only while no app has the terminal
      ProcessSignal.sigint.watch().listen((_) => stopWith(0)),
      if (Platform.isWindows)
        ProcessSignal.sighup.watch().listen((_) => stopWith(129))
      else ...[
        ProcessSignal.sigterm.watch().listen((_) => stopWith(143)),
        ProcessSignal.sighup.watch().listen((_) => stopWith(129)),
      ],
    ];
    // said once the signals are watched: one sent on the word ends the
    // shell as it says, not this process before it watches them
    _say('serving this terminal to the apps of $project; Ctrl+C stops it');
    _say('waiting for an app');
    try {
      await shell.done;
    } finally {
      for (final s in signals) {
        await s.cancel();
      }
    }
    return code;
  }

  TerminalShell? _shell;

  void _say(String line) => _shell?.say('twk shell: $line\n');
}
