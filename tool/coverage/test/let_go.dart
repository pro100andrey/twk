// What children_test.dart runs in a process of its own: a ChildCoverage
// over the package in args[0], a process of it started (args[1] the
// script) and still running when the watch stops, after [childGrace]
// given as args[2] milliseconds. Prints the process's id, then ends
// before it, as the coverage tool does.
import 'dart:io';

import 'package:twk_coverage/children.dart';
import 'package:twk_doc_snippets/packages.dart';

Future<void> main(List<String> args) async {
  final [dir, script, grace] = args;
  final temp = Directory.systemTemp.createTempSync('let_go_');
  final children = ChildCoverage.start(
    RepoPackage(dir, '.', 'probe'),
    temp,
    Directory('${temp.path}/out'),
  )!;
  // the one process started as its dart: the first the watch takes
  final taken = children.taken.first;
  final child = await Process.start(
    children.dart,
    ['--packages=$dir/.dart_tool/package_config.json', script, 'sleep'],
    // in this process's group, which the test made for it: the test's
    // tear-down ends it with this one, should this end without letting
    // it go
    workingDirectory: dir,
  );
  // its line printed, and being measured: the watch took it
  await child.stdout.first;
  // within the 30 s the test is given
  final pid = await taken.timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      stderr.writeln('the watch did not take ${child.pid} in 10 s');
      exit(1);
    },
  );
  if (pid != child.pid) {
    stderr.writeln('the watch took $pid, not ${child.pid}');
    exit(1);
  }
  await children.stop(grace: Duration(milliseconds: int.parse(grace)));
  stdout.writeln('${child.pid} ${children.lost}');
  exit(0);
}
