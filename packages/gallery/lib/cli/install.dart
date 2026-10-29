// Resolves, then downloads and compiles at once: a spinner while one thing
// is done, then a task list with bars, rates and the time left, where the
// terminal redraws; lines logged meanwhile land above them.
import 'dart:async';

import 'package:twk/cli.dart';
import 'package:twk/twk.dart';

Future<void> main(List<String> args) => Cli.runWithArgs(args, install);

Future<void> install(Cli cli, List<String> rest) async {
  final resolving = cli.progress('Resolving');
  for (var i = 1; i <= 4; i++) {
    await _wait(150);
    resolving.update('Resolving ($i of 4)');
  }
  resolving.complete('Resolved 4 packages');

  await cli.tasks(
    (tracker) => Future.wait([
      tracker.run(
        'assets.zip',
        (task) => _download(task, 2400000, 30),
        total: 2400000,
        unit: ProgressUnit.bytes,
      ),
      tracker.run(
        'fonts.tar',
        (task) => _download(task, 900000, 15),
        total: 900000,
        unit: ProgressUnit.bytes,
      ),
      tracker.run('Compiling', (task) async {
        await _wait(1200);
        cli.info('compiled 118 libraries');
        await _wait(600);
      }),
    ]),
  );
  cli.success('Installed in build/app.');
}

/// [size] bytes in [steps], one each 60 ms.
Future<void> _download(ProgressTask task, int size, int steps) async {
  for (var i = 0; i < steps; i++) {
    await _wait(60);
    task.advance(size ~/ steps);
  }
}

Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: ms));
