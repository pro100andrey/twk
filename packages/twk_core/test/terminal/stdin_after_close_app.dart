// The process's own terminal opened, a key read through it and closed, then
// a program that inherits fd 0 reading a line, and a second terminal opened
// after it reading a key: what is left of fd 0 once a terminal let it go.
// It ends on its own; its report goes to stderr. stdin_after_close_test.dart
// runs it in a pseudo-terminal.
//
//   python3 tool/pty_run.py --input none \
//       --when 'press a key' --when 'child> ' --when 'again a key' \
//       --input '#1:a,#2:hello\r,#3:b' -- \
//       dart run test/terminal/stdin_after_close_app.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:twk_core/twk_core.dart';

/// Opens the terminal, writes [prompt], and returns the first key typed,
/// the terminal closed.
Future<String> keyThrough(String prompt) async {
  final terminal = await Terminal.open();
  terminal.write(Uint8List.fromList('$prompt\r\n'.codeUnits));
  await terminal.flush();
  final key =
      await terminal.events.firstWhere((e) => e is KeyEvent) as KeyEvent;
  await terminal.close();
  return key.char.isEmpty ? key.code.name : key.char;
}

Future<void> main() async {
  final first = await keyThrough('press a key');
  final child = await Process.start('sh', [
    '-c',
    // fails where fd 0 is closed (3) or gave something else (4)
    r'printf "child> "; read x || exit 3; [ "$x" = hello ] || exit 4',
  ], mode: ProcessStartMode.inheritStdio);
  final code = await child.exitCode;
  final second = await keyThrough('again a key');
  stderr.writeln('first $first, child exit $code, second $second');
}
