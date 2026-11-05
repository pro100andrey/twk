// Says whether the process catches SIGTSTP (SigCgt of /proc/self/status) with
// its terminal open, handed over and closed, and whether stdout, the shell's
// too, was ever made non-blocking: what pty_test.dart reads.
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

/// O_NONBLOCK in the flags of stdout, as /proc shows them.
bool get stdoutBlocks {
  final line = File(
    '/proc/self/fdinfo/1',
  ).readAsLinesSync().firstWhere((l) => l.startsWith('flags:'));
  return int.parse(line.split('\t').last, radix: 8) & 0x800 == 0;
}

Future<void> main() async {
  final before = catchesStop;
  final term = await Terminal.open(
    const TerminalOptions(probeTimeout: Duration(milliseconds: 200)),
  );
  term.write(ascii.encode('written'));
  await term.flush();
  final open = catchesStop;
  final blocks = stdoutBlocks;
  await term.suspend();
  final handed = catchesStop;
  await term.resume();
  final back = catchesStop;
  await term.close();
  stdout.writeln(
    jsonEncode([before, open, handed, back, catchesStop, blocks]),
  );
}
