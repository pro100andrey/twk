// Terminal.notify and Terminal.copyToClipboard over a link in memory, in
// the environment of one terminal or another.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'fake_link.dart';
import 'on_clock.dart';

/// What a terminal in an environment with [env] is given when it opens,
/// sends one notification, copies a text to the clipboard and closes.
Future<String> written(Map<String, String> env) async {
  final clock = FakeClock();
  final link = FakeLink(environment: env);
  final term = await clock.open(
    link,
    const TerminalOptions(probeTimeout: Duration(seconds: 5)),
  );
  term
    ..notify('Build', 'done; 3 tests')
    ..copyToClipboard('copied 🧪');
  await clock.runUntil(term.close);
  return link.text;
}

/// The OSC 52 that the copy of [written] is.
final _copied = '\x1b]52;c;${base64.encode(utf8.encode('copied 🧪'))}';

void main() {
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
  );

  test('foot: OSC 777', () async {
    final s = await written({'TERM': 'foot'});
    expect(s, contains('\x1b]777;notify;Build;done, 3 tests\x1b\\'));
  });

  test('a terminal not known to show notifications: nothing', () async {
    final s = await written({'TERM': 'xterm-256color'});
    expect(s, isNot(contains('Build')));
    expect(s, contains('\x1b[?1049l'), reason: 'the app ran');
  });

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
  });

  test(
    'the clipboard inside GNU screen: OSC 52 in DCS, ended by BEL',
    () async {
      final s = await written({'TERM': 'screen', 'STY': '4242.pts-0.host'});
      expect(s, contains('\x1bP$_copied\x07\x1b\\'));
    },
  );

  test('the clipboard outside a multiplexer: OSC 52 as it is', () async {
    final s = await written({'TERM': 'xterm-256color'});
    expect(s, contains('$_copied\x1b\\'));
    expect(s, isNot(contains('\x1bP')));
  });
}
