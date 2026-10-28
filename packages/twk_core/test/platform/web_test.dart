// What stands in on the web for the process (platform/web.dart), loaded
// on the VM: it imports nothing of dart:io or dart:js_interop. There is
// nothing to read; what would watch does nothing, and what would open,
// read, write or serve throws UnsupportedError; an error is printed to
// the console (web_print.dart, in a process of its own).
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_core/src/platform/web.dart' as web;
import 'package:twk_test/twk_test.dart' show runProcess;

void main() {
  test('there is no environment, Windows, process id or terminal of its '
      'own', () {
    expect(web.environment, isEmpty);
    expect(web.isWindows, isFalse);
    expect(web.processId, 0);
    expect(web.ownTerminalLink(), isNull);
    expect(web.outputIsTerminal, isFalse);
  });

  test('watching the signals watches none', () {
    expect(web.watchSignals(() {}, () async {}), isEmpty);
  });

  test('plain output, files, job control and local sockets are '
      'unsupported', () async {
    expect(web.plainStdio, throwsUnsupportedError);
    expect(() => web.appendFile('log', 'x'), throwsUnsupportedError);
    expect(() => web.readFile('trace'), throwsUnsupportedError);
    expect(() => web.createFile('trace', const []), throwsUnsupportedError);
    expect(web.stopProcessGroup, throwsUnsupportedError);
    await expectLater(web.SocketLink.toShell(), throwsUnsupportedError);
    await expectLater(web.TerminalShell.start(), throwsUnsupportedError);
    await expectLater(
      web.LogServer.start(null, () => const []),
      throwsUnsupportedError,
    );
  });

  test('an error is printed to the console, past any zone that catches '
      'prints', () async {
    final res = await runProcess(Platform.resolvedExecutable, [
      File('test/platform/web_print.dart').absolute.path,
    ]);
    expect(res.stdout, 'to the console\nthe zone caught 0\n');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
