// A tool that reads its configuration and fails on it: inspect() shows
// what it read, and the error Cli.run catches ends it with a traceback,
// the source it was thrown at highlighted, and exit code 1; at a terminal
// it is committed in the inline session the progress opened, which is
// then closed.
//
//   dart run example/errors.dart              # at a terminal
//   dart run example/errors.dart -v           # with every frame
//   dart run example/errors.dart --no-color   # plain lines
//   dart run example/errors.dart 2>&1 | cat   # a pipe
import 'dart:convert';

import 'package:twk_cli/twk_cli.dart';

const _text = '{"version": 2, "targets": ["api", "web"], "owner": null}';

Future<void> main(List<String> args) => Cli.runWithArgs(args, (
  cli,
  rest,
) async {
  final map = await cli.progress('Reading the config').run(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return jsonDecode(_text) as Map<String, Object?>;
  }, done: (_) => 'Read the config');
  await cli.inspect(map, label: 'config');
  _Config.from(map);
});

final class _Config {
  _Config(this.name);

  factory _Config.from(Map<String, Object?> map) {
    final name = map['name'];
    if (name is! String) {
      throw StateError('the config has no "name"');
    }
    return _Config(name);
  }

  /// The config's name, which this one lacks.
  final String name;
}
