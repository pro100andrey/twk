// `twk shell` in a terminal of the test's (see terminal.dart): the
// terminal served to an app of the project that connects to the shell,
// the shell saying when one comes and goes, Ctrl+C while no app has the
// terminal and SIGTERM stopping it, the terminal put back. The app is
// this test, on `Terminal.connect`.
@TestOn('linux || mac-os')
@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart' as core show Terminal;
import 'package:twk_core/twk_core.dart' show LocalAddress;

import 'terminal.dart';
import 'twk.dart';

void main() {
  setUpAll(compileTwk);

  late String project;
  setUp(() async {
    project = (await Directory.systemTemp.createTemp('twk_shell_')).path;
    addTearDown(() => Directory(project).delete(recursive: true));
    File(p.join(project, 'pubspec.yaml')).writeAsStringSync('name: app\n');
  });

  /// `twk shell` of [project], once it waits for an app.
  Future<Terminal> shell() async {
    final t = await Terminal.twk(['shell', '-C', project]);
    await t.until(
      () => t.text.contains('twk shell: waiting for an app'),
      'the shell',
    );
    return t;
  }

  test('serves its terminal to an app of the project, saying when one '
      'connects and when it went away, and stops on Ctrl+C while no app '
      'has the terminal, with 0, the terminal put back', () async {
    final t = await shell();
    final before = t.modes;
    expect(
      t.text,
      contains(
        'twk shell: serving this terminal to the apps of $project; '
        'Ctrl+C stops it',
      ),
    );

    final address = LocalAddress.read(LocalAddress.fileOf('shell', project));
    final app = await core.Terminal.connect(address!);
    await t.until(
      () => t.text.contains('twk shell: an app connected'),
      'the app to connect',
    );
    // the keys go to the app as they are typed, not echoed
    expect(t.modes.lflag & (icanon | echo), 0, reason: '${t.modes}');
    app.write(utf8.encode('from the app'));
    await app.flush();
    await t.until(() => t.text.contains('from the app'), "the app's text");
    await app.close();
    await t.until(
      () =>
          t.text.contains('twk shell: the app went away; waiting for the next'),
      'the app to go',
    );

    t.type('\x03');
    expect(await t.ended(), exits(0));
    expect(t.modes.same(before), isTrue, reason: '${t.modes}');
    expect(
      File(LocalAddress.fileOf('shell', project)).existsSync(),
      isFalse,
    );
  });

  test('stopped by SIGTERM ends with 143', () async {
    final t = await shell();
    t.pty.kill();
    expect(await t.ended(), exits(143));
  });
}
