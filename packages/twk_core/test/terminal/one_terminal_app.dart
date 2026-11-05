// The process's own terminal opened twice: the second is refused while the
// first has it, the first still reads its keys; suspended, the first gives
// way to a second, and has it again once that is closed. Its report goes to
// stderr. one_terminal_test.dart runs it in a pseudo-terminal.
//
//   python3 tool/pty_run.py --input none \
//       --when 'first ready' --when 'second ready' --when 'first again' \
//       --input '#1:a,#2:b,#3:c' -- \
//       dart run test/terminal/one_terminal_app.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:twk_core/twk_core.dart';

/// Writes [prompt] and returns the first key [events] gives.
Future<String> key(
  Terminal terminal,
  StreamIterator<InputEvent> events,
  String prompt,
) async {
  terminal.write(Uint8List.fromList('$prompt\r\n'.codeUnits));
  await terminal.flush();
  while (await events.moveNext()) {
    if (events.current case KeyEvent(:final char)) {
      return char;
    }
  }
  return 'ended';
}

Future<void> main() async {
  final first = await Terminal.open();
  final firstEvents = StreamIterator(first.events);
  var refused = 'not refused';
  try {
    final other = await Terminal.open();
    await other.close();
  } on TerminalException catch (e) {
    refused = 'refused';
    stderr.writeln('message: ${e.message}');
  }
  final a = await key(first, firstEvents, 'first ready');
  await first.suspend();
  final second = await Terminal.open();
  final secondEvents = StreamIterator(second.events);
  final b = await key(second, secondEvents, 'second ready');
  // an iterator holds its subscription paused, which a close waits for
  await secondEvents.cancel();
  await second.close();
  await first.resume();
  final c = await key(first, firstEvents, 'first again');
  await firstEvents.cancel();
  await first.close();
  stderr.writeln('$refused, first $a, second $b, first $c');
}
