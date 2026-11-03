// A reader of fd 0 (PosixInput) paused and let go while fd 0 has much more
// (a file of 128 MiB): the reader reads what is there without waiting, so
// only the stop flag it looks at before each read stops it, and what is
// left of the file is a program's after it (`wc -c` says how much, on
// stdout). It ends on its own; posix_input_test.dart runs it.
//
//   dart run test/terminal/posix_input_flood_app.dart < a-big-file
import 'dart:async';
import 'dart:io';

import 'package:twk_core/src/terminal/isolate_input.dart';
import 'package:twk_core/src/terminal/posix_input.dart';

Future<void> main() async {
  final reading = Completer<void>();
  late final StreamSubscription<List<int>> input;
  input = IsolateInput(PosixInput.open()!).stream.listen((_) {
    if (!reading.isCompleted) {
      input.pause();
      reading.complete();
    }
  });
  await reading.future;
  // completes once the reader stopped
  await input.cancel();
  final left = await Process.start('wc', [
    '-c',
  ], mode: ProcessStartMode.inheritStdio);
  exitCode = await left.exitCode;
}
