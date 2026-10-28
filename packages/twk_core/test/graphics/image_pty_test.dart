// An image in a pseudo-terminal (tool/pty_run.py) in each protocol, as
// image_app.dart shows it: the terminal is handed back intact and the test
// emulator takes every byte written (tool/replay.dart).
@TestOn('linux || mac-os')
// what a loaded machine may take: the app's run, up to pty_run's own
// timeout, and the replay
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

/// image_app.dart and tool/replay.dart, compiled once.
late String _app;
late String _replay;

/// What image_app.dart wrote with TWK_GRAPHICS set to [protocol], after
/// the emulator took it all.
Future<String> written(String protocol) async {
  final dir = Directory.systemTemp.createTempSync('image');
  addTearDown(() => dir.deleteSync(recursive: true));
  final out = '${dir.path}/out.bin';
  final res = await runProcess(
    'python3',
    [
      '../../tool/pty_run.py',
      '--input',
      'none',
      '--out',
      out,
      '--',
      Platform.resolvedExecutable,
      _app,
    ],
    environment: {'TWK_GRAPHICS': protocol},
    group: true,
  );
  expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
  final replay = await runProcess(Platform.resolvedExecutable, [
    _replay,
    '--fullscreen',
    out,
    '100',
    '30',
  ]);
  expect(replay.exitCode, 0, reason: '${replay.stdout}');
  return latin1.decode(File(out).readAsBytesSync());
}

void main() {
  setUpAll(() async {
    final packages = (await Isolate.packageConfig)!.toFilePath();
    const cache = '.dart_tool/twk_test/programs';
    _app = await compiledProgram(
      'test/graphics/image_app.dart',
      packages: packages,
      cache: cache,
    );
    _replay = await compiledProgram(
      '../../tool/replay.dart',
      packages: packages,
      cache: cache,
    );
  });

  test('kitty: sent once, placed again after the scroll, deleted', () async {
    final out = await written('kitty');
    expect('a=T,'.allMatches(out), hasLength(1));
    expect(out, contains('a=p,i=1,p=1,c=4,r=2,C=1,q=2'));
    expect(out, contains('\x1b_Ga=d,d=I,i=1,q=2\x1b\\'));
  });

  test('sixel: sent where it is, before and after the scroll', () async {
    final out = await written('sixel');
    expect('\x1bP0;1;0q'.allMatches(out), hasLength(2));
    expect(out, contains('\x1b[?8452l\x1b8'));
  });

  test('iTerm2: sent where it is, before and after the scroll', () async {
    final out = await written('iterm2');
    expect('\x1b]1337;File='.allMatches(out), hasLength(2));
  });
}
