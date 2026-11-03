// A reader of fd 0 (PosixInput) listened to and paused at once, then let
// go, and a program that inherits fd 0 after it: what fd 0 had is left to
// the program, as a pause tells the reader before it returns. It ends on
// its own; its report goes to stderr. posix_input_test.dart runs it with a
// line already waiting on fd 0.
//
//   printf 'abc\n' | dart run test/terminal/posix_input_paused_app.dart
import 'dart:io';

import 'package:twk_core/src/terminal/posix_input.dart';

Future<void> main() async {
  final read = <int>[];
  final input = PosixInput.open()!.stream.listen(read.addAll)..pause();
  await input.cancel();
  final child = await Process.start('sh', [
    '-c',
    r'read x; printf "child %s\n" "$x"',
  ], mode: ProcessStartMode.inheritStdio);
  final code = await child.exitCode;
  stderr.writeln('read ${read.length}, child exit $code');
}
