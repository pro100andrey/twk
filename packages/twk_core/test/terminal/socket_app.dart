// Opens the terminal without one (stdin and stdout are pipes), writes a
// line and closes it, telling what it got on stdout: for socket_test.dart,
// which serves the project's shell.
import 'dart:io';
import 'dart:typed_data';

import 'package:twk_core/terminal.dart';

Future<void> main() async {
  try {
    final term = await Terminal.open(
      const TerminalOptions(probeTimeout: Duration(milliseconds: 50)),
    );
    term.write(Uint8List.fromList('from the app'.codeUnits));
    await term.flush();
    await term.close();
    stdout.writeln('opened ${term.width}x${term.height}');
  } on TerminalException catch (e) {
    stdout.writeln(e);
  }
}
