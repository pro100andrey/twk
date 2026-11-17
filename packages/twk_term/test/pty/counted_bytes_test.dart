// What a Terminal counts as written ([CountingBackend.bytesWritten]) is
// what a pseudo-terminal's master receives, less the LFs the line
// discipline turned into CR LF (OPOST and ONLCR stay on in raw mode, and
// the presenter writes bare LFs inline and in plain output): the count a
// driver compares the output it received with, in each screen mode.
@Tags(['process'])
@TestOn('linux || mac-os')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_term/twk_term.dart';
import 'package:twk_test/twk_test.dart'
    show compiledProgram, waitFor, waitUntil;

void main() {
  late String app;
  setUpAll(
    () async => app = await compiledProgram(
      'test/pty/counted_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  for (final mode in ['fullscreen', 'inline', 'plain']) {
    test('$mode: the bytes counted are those received, less the LFs '
        'the tty added a CR to', () async {
      final dir = Directory.systemTemp.createTempSync('counted');
      addTearDown(() => dir.deleteSync(recursive: true));
      final report = File('${dir.path}/written');
      final screen = TerminalEmulator(width: 40, height: 10);
      final pty = Pty.start(
        Platform.resolvedExecutable,
        [
          app,
          mode,
          report.path,
        ],
        width: 40,
        height: 10,
      );
      screen.onOutput = pty.write;
      var received = 0;
      var lineFeeds = 0;
      var outputDone = false;
      final reading = pty.output.listen((bytes) {
        received += bytes.length;
        lineFeeds += bytes.where((b) => b == 0x0A).length;
        screen.feed(bytes);
      }, onDone: () => outputDone = true);
      addTearDown(() async {
        pty
          ..kill(ProcessSignal.sigkill)
          ..close();
        await reading.cancel();
      });
      await waitFor(pty.exitCode, 'the app to end');
      await waitUntil(() => outputDone, 'the end of its output');
      final counted = int.parse(report.readAsStringSync());
      expect(counted, greaterThan(0));
      if (mode != 'fullscreen') {
        expect(lineFeeds, greaterThan(0), reason: 'a bare LF is written');
      }
      expect(received - lineFeeds, counted);
    });
  }
}
