// The reader of fd 0 (PosixInput), in programs of their own: paused as
// soon as it is listened to with a line already waiting on fd 0
// (posix_input_paused_app.dart), it reads nothing, and a program started
// after it gets the line; paused while fd 0 has much more
// (posix_input_flood_app.dart), it stops, leaving the rest.
@Tags(['process'])
@TestOn('linux || mac-os')
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

import '../support/environment.dart';

void main() {
  late String app;
  late String flood;
  setUpAll(() async {
    final packages = (await Isolate.packageConfig)!.toFilePath();
    app = await compiledProgram(
      'test/terminal/posix_input_paused_app.dart',
      packages: packages,
      cache: '.dart_tool/twk_test/programs',
    );
    flood = await compiledProgram(
      'test/terminal/posix_input_flood_app.dart',
      packages: packages,
      cache: '.dart_tool/twk_test/programs',
    );
  });

  test('a reader paused as it is listened to reads nothing, and leaves '
      'what fd 0 has to a program started after', () async {
    final res = await runProcess(
      'sh',
      ['-c', r'printf "abc\n" | "$0" "$1"', Platform.resolvedExecutable, app],
      environment: childEnvironment(),
      includeParentEnvironment: false,
      group: true,
      // what a loaded machine may take to start the app
      timeout: const Duration(minutes: 2),
    );
    final said = '${res.stdout}${res.stderr}';
    expect(res.exitCode, 0, reason: said);
    expect(res.stdout, contains('child abc'), reason: said);
    expect(res.stderr, contains('read 0, child exit 0'), reason: said);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a reader paused while fd 0 has much more stops reading, though '
      'it reads what is there without waiting', () async {
    final dir = await Directory.systemTemp.createTemp('posix_input');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/flood');
    await file.writeAsBytes(Uint8List(_flood)..fillRange(0, _flood, 0x61));
    final res = await runProcess(
      'sh',
      [
        '-c',
        r'"$0" "$1" < "$2"',
        Platform.resolvedExecutable,
        flood,
        file.path,
      ],
      environment: childEnvironment(),
      includeParentEnvironment: false,
      group: true,
      timeout: const Duration(minutes: 1),
    );
    final said = '${res.stdout}${res.stderr}';
    expect(res.exitCode, 0, reason: said);
    // a reader that never looks at the stop flag reads the whole file
    // before it waits, and leaves nothing; one that does stops a few MB
    // in, so only a listener kept from pausing it for as long as the
    // whole file takes to read leaves nothing too
    final left = int.parse('${res.stdout}'.trim());
    expect(left, greaterThan(0), reason: said);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

// the file fd 0 is for the flood: what a reader reads before it is paused
// many times over (a few MB, measured), in more time than a pause takes
const int _flood = 128 << 20;
