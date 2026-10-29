// A spinner while one thing is done, then three tasks at once with bars,
// rate and time left, lines logged landing above them; as the output
// allows.
//
//   dart run example/cli/progress.dart            # at a terminal: live
//   dart run example/cli/progress.dart --no-color # lines as things start, end
//   dart run example/cli/progress.dart | cat      # how each ended
//   dart run example/cli/progress.dart --fail     # the last task fails
import 'dart:async';

import 'package:twk/cli.dart';
import 'package:twk/twk.dart';

Future<void> main(List<String> args) => Cli.runWithArgs(args, (
  cli,
  rest,
) async {
  final progress = cli.progress('Resolving dependencies');
  for (var i = 1; i <= 4; i++) {
    await _wait(250);
    progress.update('Resolving dependencies ($i of 4)');
  }
  progress.complete('Resolved 4 dependencies');

  await cli
      .progress('Generating code')
      .run(() => _wait(600), done: (_) => 'Generated 12 files');

  final fail = rest.contains('--fail');
  try {
    await cli.tasks(
      (tracker) => Future.wait([
        tracker.run(
          'Downloading assets.zip',
          (task) => _download(task, 2400000, 120000),
          total: 2400000,
          unit: ProgressUnit.bytes,
        ),
        tracker.run(
          'Downloading fonts.tar',
          (task) async {
            await _download(task, 900000, 30000);
            cli.info('fonts unpacked');
          },
          total: 900000,
          unit: ProgressUnit.bytes,
        ),
        tracker.run('Building binary', (task) async {
          await _wait(1500);
          if (fail) {
            throw const FormatException('linker exited with 1');
          }
        }),
      ]),
    );
    cli.success('Done.');
  } on FormatException catch (e) {
    cli.err('Build failed: ${e.message}');
  }
});

Future<void> _download(ProgressTask task, int size, int chunk) async {
  for (var got = 0; got < size; got += chunk) {
    await _wait(50);
    task.advance(chunk);
  }
}

Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: ms));
