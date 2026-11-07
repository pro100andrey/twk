// Opens the process's terminal twice at once and writes to the file its
// argument names what became of each. double_open_test.dart runs it in a
// pseudo-terminal.
import 'dart:io';

import 'package:twk_core/twk_core.dart';

Future<void> main(List<String> args) async {
  final results = await Future.wait([
    for (var i = 0; i < 2; i++)
      Terminal.open().then<Object>((t) => t, onError: (Object e) => e),
  ]);
  final said = [
    for (final r in results)
      if (r is Terminal) 'opened' else '${r.runtimeType}',
  ];
  for (final t in results.whereType<Terminal>()) {
    await t.close();
  }
  File(args.single).writeAsStringSync(said.join(' '));
  exit(0);
}
