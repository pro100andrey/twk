// A terminal with color scheme reports (DEC mode 2031), in a
// pseudo-terminal (color_scheme_pty.py) running color_scheme_app.dart.
@TestOn('linux || mac-os')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

void main() {
  late String app;
  setUpAll(
    () async => app = await compiledProgram(
      'test/terminal/color_scheme_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  test('the reports are turned on while the app runs, and after one the '
      'default colors are asked for again', () async {
    final dir = Directory.systemTemp.createTempSync('color_scheme');
    addTearDown(() => dir.deleteSync(recursive: true));
    final out = '${dir.path}/out.bin';
    final res = await runProcess('python3', [
      'test/terminal/color_scheme_pty.py',
      out,
      Platform.resolvedExecutable,
      app,
    ], group: true);
    expect(res.stderr, '''
brightness dark reports true
scheme light
color 10 4c4f69
color 11 eff1f5
''');
    expect(res.exitCode, 0);
    final written = String.fromCharCodes(File(out).readAsBytesSync());
    final on = written.indexOf('\x1b[?2031h');
    expect(written.indexOf('\x1b[?2031\$p'), inInclusiveRange(0, on));
    final asked = written.indexOf('\x1b]10;?\x1b\\\x1b]11;?\x1b\\', on);
    expect(asked, greaterThan(on));
    expect(written.indexOf('\x1b[?2031l', asked), greaterThan(asked));
    expect(written.lastIndexOf('\x1b[?2031h'), on, reason: 'turned on once');
  }, timeout: const Timeout(Duration(minutes: 1)));
}
