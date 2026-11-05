// Says whether the process catches SIGTSTP (SigCgt of /proc/self/status) with
// its terminal open, handed over and closed: what pty_test.dart reads.
import 'dart:convert';
import 'dart:io';

import 'package:twk_core/terminal.dart';

bool get catchesStop {
  final line = File(
    '/proc/self/status',
  ).readAsLinesSync().firstWhere((l) => l.startsWith('SigCgt:'));
  final mask = int.parse(line.split('\t').last, radix: 16);
  return mask & (1 << 19) != 0;
}

Future<void> main() async {
  final before = catchesStop;
  final term = await Terminal.open(
    const TerminalOptions(probeTimeout: Duration(milliseconds: 200)),
  );
  final open = catchesStop;
  await term.suspend();
  final handed = catchesStop;
  await term.resume();
  final back = catchesStop;
  await term.close();
  stdout.writeln(
    jsonEncode([before, open, handed, back, catchesStop]),
  );
}
