// Serves its terminal to the apps of the project it runs in with
// TerminalShell.start, as `twk shell` does, and is such an app itself
// (Terminal.connect): for socket_test.dart, which runs it in a
// pseudo-terminal. Says on stderr what a second shell for the project is
// told, the size the app got and what the shell heard of it.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:twk_core/twk_core.dart';

Future<void> main() async {
  final events = <ShellEvent>[];
  final gone = Completer<void>();
  final shell = await TerminalShell.start(
    onEvent: (e) {
      events.add(e);
      if (e == ShellEvent.disconnected) {
        gone.complete();
      }
    },
  );
  try {
    await TerminalShell.start();
    stderr.writeln('a second shell started');
  } on TerminalException catch (e) {
    stderr.writeln('a second shell: ${e.message}');
  }
  final address = LocalAddress.read(LocalAddress.fileOf('shell'))!;
  final term = await Terminal.connect(address);
  term.write(Uint8List.fromList('from the app'.codeUnits));
  await term.flush();
  stderr.writeln('the app got ${term.width}x${term.height}');
  await term.close();
  await gone.future;
  await shell.stop();
  stderr.writeln('the shell heard: ${events.map((e) => e.name).join(', ')}');
}
