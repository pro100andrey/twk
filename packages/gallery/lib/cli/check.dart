// Reads a config and fails on it: what was read as a JsonView shows it
// (twk_rich's jsonLines), and the error Cli.run catches ends the run with
// its traceback, the line it was thrown at highlighted as Dart (twk_rich's
// dartSourceLines), and exit code 1.
import 'dart:convert';

import 'package:twk/cli.dart';
import 'package:twk_rich/twk_rich.dart' show dartSourceLines, jsonLines;

Future<void> main(List<String> args) =>
    Cli.runWithArgs(args, check, sourceLines: dartSourceLines);

const _text = '{"version": 2, "target": "web"}';

Future<void> check(Cli cli, List<String> rest) async {
  final map = await cli.progress('Reading twk.yaml').run(() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return jsonDecode(_text) as Map<String, Object?>;
  }, done: (_) => 'Read twk.yaml');
  cli.info('config:');
  jsonLines(map).forEach(cli.info);
  cli.success('Deploying ${_name(map)}.');
}

String _name(Map<String, Object?> map) {
  if (map['name'] case final String name) {
    return name;
  }
  throw StateError('no "name" set');
}
