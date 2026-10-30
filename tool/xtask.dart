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
  exitCode = await runXtask(args, verbs: verbs());
}
