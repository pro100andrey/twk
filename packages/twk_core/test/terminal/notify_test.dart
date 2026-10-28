// Terminal.notify and Terminal.copyToClipboard in a pseudo-terminal
// (tool/pty_run.py) running notify_app.dart in the environment of one
// terminal or another.
@TestOn('linux || mac-os')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

/// Variables that name a terminal: the test's own are left out.
const _terminalVariables = {
  'TERM_PROGRAM',
  'TMUX',
  'STY',
  'KITTY_WINDOW_ID',
  'WEZTERM_PANE',
  'GHOSTTY_RESOURCES_DIR',
  'ITERM_SESSION_ID',
  'LC_TERMINAL',
  'KONSOLE_VERSION',
  'WT_SESSION',
  'VTE_VERSION',
};

/// notify_app.dart, compiled once.
late String _app;

/// What notify_app.dart wrote to the terminal in an environment with [env].
Future<String> written(Map<String, String> env) async {
  final dir = Directory.systemTemp.createTempSync('notify');
  addTearDown(() => dir.deleteSync(recursive: true));
  final out = '${dir.path}/out.bin';
  final environment = {...Platform.environment}
    ..removeWhere((name, _) => _terminalVariables.contains(name))
    ..addAll(env);
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
    environment: environment,
    includeParentEnvironment: false,
    group: true,
  );
  expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
  return utf8.decode(File(out).readAsBytesSync());
}

/// The OSC 52 that notify_app.dart's copy is.
final _copied = '\x1b]52;c;${base64.encode(utf8.encode('copied 🧪'))}';

void main() {
  setUpAll(
    () async => _app = await compiledProgram(
      'test/terminal/notify_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  test(
    'kitty inside tmux: OSC 99 in DCS passthrough, with an id of its own',
    () async {
      final s = await written({
        'TERM': 'tmux-256color',
        'TERM_PROGRAM': 'tmux',
        'TMUX': '/tmp/tmux-1000/default,4242,0',
        'KITTY_WINDOW_ID': '1',
      });
      final id = RegExp(r'\]99;i=(\d+\.1):').firstMatch(s)?[1];
      expect(id, isNotNull, reason: s);
      expect(
        s,
        contains(
          '\x1bPtmux;\x1b\x1b]99;i=$id:d=0;Build\x1b\x1b\\'
          '\x1b\x1b]99;i=$id:p=body;done; 3 tests\x1b\x1b\\\x1b\\',
        ),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('foot: OSC 777', () async {
    final s = await written({'TERM': 'foot'});
    expect(s, contains('\x1b]777;notify;Build;done, 3 tests\x1b\\'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a terminal not known to show notifications: nothing', () async {
    final s = await written({'TERM': 'xterm-256color'});
    expect(s, isNot(contains('Build')));
    expect(s, contains('\x1b[?1049l'), reason: 'the app ran');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the clipboard inside tmux: OSC 52 as it is, then in DCS '
      'passthrough', () async {
    final s = await written({
      'TERM': 'tmux-256color',
      'TMUX': '/tmp/tmux-1000/default,4242,0',
    });
    expect(
      s,
      contains(
        '$_copied\x1b\\'
        '\x1bPtmux;${_copied.replaceAll('\x1b', '\x1b\x1b')}'
        '\x1b\x1b\\\x1b\\',
      ),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'the clipboard inside GNU screen: OSC 52 in DCS, ended by BEL',
    () async {
      final s = await written({'TERM': 'screen', 'STY': '4242.pts-0.host'});
      expect(s, contains('\x1bP$_copied\x07\x1b\\'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('the clipboard outside a multiplexer: OSC 52 as it is', () async {
    final s = await written({'TERM': 'xterm-256color'});
    expect(s, contains('$_copied\x1b\\'));
    expect(s, isNot(contains('\x1bP')));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
