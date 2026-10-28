// The repository's checks: `dart run tool/xtask.dart <gate or task>`. What
// they are is xtask.yaml at the root; the verbs it names are in tool/xtask/.
// Here rather than in bin/ (xtask's `dart run :xtask`): the root's package
// is the pub workspace, its tools in tool/ beside this, and xtask one of its
// dev dependencies.
//
//   dart run tool/xtask.dart quick       # pub get, analyze, format
//   dart run tool/xtask.dart handover    # what CONTRIBUTING.md asks
//   dart run tool/xtask.dart --list      # every task, by gate
import 'dart:io';

import 'package:xtask/xtask.dart';

import 'xtask/verbs.dart';

Future<void> main(List<String> args) async {
  // TWK_PACKAGES narrowed the per-package steps until xtask 0.4.0 brought
  // --only. Refused rather than ignored for a while, so a run that still
  // sets it doesn't check every package when it meant two.
  final old = Platform.environment['TWK_PACKAGES'] ?? '';
  if (old.trim().isNotEmpty) {
    stderr.writeln(
      'TWK_PACKAGES is gone: narrow a run with '
      "--only 'packages=packages/twk/*,packages/twk_rich/*' (the members are "
      "the packages' pubspec.yaml files); unset it",
    );
    exitCode = ExitCode.invalidFile;
    return;
  }
  exitCode = await runXtask(args, verbs: verbs());
}
