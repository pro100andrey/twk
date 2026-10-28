// Writes a trace to the file args[0] until a write fails, for
// trace_test.dart, which runs it with the size of the files it may write
// limited: says on stdout what close threw.
import 'dart:io';
import 'dart:typed_data';

import 'package:twk_core/src/terminal/trace.dart'
    show TraceDirection, TraceWriter;

Future<void> main(List<String> args) async {
  final writer = TraceWriter.open(args[0], TraceDirection.output, 80, 24);
  for (var i = 0; i < 8; i++) {
    writer.add(Uint8List(512));
    // the writes start on their own, not in close: a write that fails is
    // one on its way
    await Future<void>.delayed(Duration.zero);
  }
  try {
    await writer.close();
    stdout.writeln('close threw nothing');
  } on FileSystemException catch (e) {
    stdout.writeln(
      'close threw ${e.runtimeType}, errno ${e.osError?.errorCode}',
    );
  }
}
