// A command that wraps twk's, written when it was runTui (before 6d4f947).
import 'dart:io';

import 'package:twk_dev/twk_dev.dart';

Future<void> main(List<String> arguments) async {
  final code = await runTui(arguments);
  exitCode = code == usageExitCode ? 2 : code;
}

Future<int> Function(List<String>) entry = runTui;

Future<int> create(String name) => runTui(['create', name]);
