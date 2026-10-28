// A terminal over an in-memory link, opened by Terminal.overLink (or, with
// `own`, as Terminal.open opens the process's own one) in an environment
// that asks for a trace, that this process sends SIGINT and then SIGTERM:
// prints what the terminal got, up to a key typed after the SIGINT, for
// link_test.dart.
import 'dart:async';
import 'dart:io';

import 'package:twk_core/src/terminal/terminal.dart' show openOwnOrShell;
import 'package:twk_core/terminal.dart';

import 'fake_link.dart';

Future<void> main(List<String> args) async {
  final link = FakeLink()..type('\x1b[?62;22c');
  const options = TerminalOptions(probeTimeout: Duration(seconds: 5));
  final term = args.contains('own')
      ? await openOwnOrShell(link, options)
      : await Terminal.overLink(link, options);
  // the key typed after the SIGINT: what the terminal made of the signal,
  // if anything, came before it
  final typed = Completer<void>();
  term.events.listen((e) {
    if (e case KeyEvent(char: 'z')) {
      typed.complete();
    } else {
      stdout.writeln('event $e');
    }
  });
  // a watcher of its own: SIGINT ends the process neither way, nor stays
  // ignored if it was ignored when the process started
  final interrupted = Completer<void>();
  final sigint = ProcessSignal.sigint.watch().listen(
    (_) => interrupted.complete(),
  );
  Process.killPid(pid, ProcessSignal.sigint);
  await interrupted.future;
  link.type('z');
  // less than the test waits for the process to end, to be told
  await typed.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () => stdout.writeln('the key typed never came'),
  );
  await sigint.cancel();
  stdout.writeln('sigterm');
  await stdout.flush();
  Process.killPid(pid); // SIGTERM
  await Future<void>.delayed(const Duration(seconds: 5));
  stdout.writeln('survived');
}
