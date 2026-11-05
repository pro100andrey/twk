// Writes more than a terminal holds when a key comes, then ends on Ctrl+C
// (SIGINT): what pty_test.dart runs on a terminal that stops reading.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:twk_core/terminal.dart';

Future<void> main() async {
  final term = await Terminal.open(
    const TerminalOptions(probeTimeout: Duration(milliseconds: 200)),
  );
  term.write(ascii.encode('opened'));
  await term.flush();
  final events = StreamIterator(term.events);
  await events.moveNext();
  term.write(Uint8List(1 << 20)..fillRange(0, 1 << 20, 0x78));
  unawaited(term.flush());
  await events.moveNext();
  await events.cancel();
  await term.close();
}
