// The testing guide's recipe (doc/guides/testing.md): an app run in a
// pseudo-terminal, its keys typed and its screen read, as a terminal does.
@TestOn('linux || mac-os')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_term/twk_term.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  late String counter;

  setUpAll(() async {
    // compiled once, and again only when its sources change
    counter = await compiledProgram(
      '../twk/example/counter.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    );
  });

  test('the counter counts on Up and quits on q', () async {
    final screen = TerminalEmulator(width: 40, height: 6);
    final pty = Pty.start(
      Platform.resolvedExecutable,
      [counter],
      width: 40,
      height: 6,
    );
    final output = pty.output.listen(screen.feed);
    // ends this process and no other, whatever the test does
    addTearDown(() async {
      pty
        ..kill(ProcessSignal.sigkill)
        ..close();
      await output.cancel();
    });

    await waitUntil(() => screen.text.contains('Count: 0'), 'the first frame');
    pty.write(utf8.encode('\x1b[A'));
    await waitUntil(() => screen.text.contains('Count: 1'), 'the count');
    pty.write(utf8.encode('q'));
    expect(await waitFor(pty.exitCode, 'the exit'), 0);
  });
}
