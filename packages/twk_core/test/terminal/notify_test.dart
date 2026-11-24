// Terminal.notify and Terminal.copyToClipboard over a link in memory, in
// the environment of one terminal or another.
import 'dart:convert';
import 'dart:io' show pid;

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
    ..notify(const DesktopNotification('Build', body: 'done; 3 tests'))
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
      final id = RegExp(r'\]99;i=(\d+\.auto-1):').firstMatch(s)?[1];
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

  group('a notification of its own', () {
    /// A terminal of [env] that answers OSC 99's query with [keys] (none
    /// where empty), opened on a clock.
    Future<(Terminal, FakeLink, FakeClock)> opened(
      Map<String, String> env, {
      String keys = '',
    }) async {
      final clock = FakeClock();
      final link = FakeLink(environment: env)
        ..type(
          '${keys.isEmpty ? '' : '\x1b]99;i=twk:p=?;$keys\x1b\\'}'
          '\x1b[?1004;1\$y\x1b[?62;22c',
        );
      final term = await clock.open(
        link,
        const TerminalOptions(probeTimeout: Duration(seconds: 5)),
      );
      return (term, link, clock);
    }

    test("its id after the process's on the wire, returned as the app's; "
        'one of its own where it has none', () async {
      final (term, link, _) = await opened({'TERM': 'xterm-kitty'});
      final before = link.text.length;
      expect(term.notify(const DesktopNotification('a', id: 'build')), 'build');
      expect(term.notify(const DesktopNotification('b')), 'auto-1');
      expect(
        term.notify(const DesktopNotification('c', id: 'x:y z')),
        'xyz',
        reason: "only OSC 99's identifier characters",
      );
      term.closeNotification('build');
      expect(
        link.text.substring(before),
        '\x1b]99;i=$pid.build;a\x1b\\'
        '\x1b]99;i=$pid.auto-1;b\x1b\\'
        '\x1b]99;i=$pid.xyz;c\x1b\\'
        '\x1b]99;i=$pid.build:p=close;\x1b\\',
      );
    });

    test("the app's ids and twk's own apart: twk's are auto-1, auto-2...; "
        'an id of which nothing is left is one of its own', () async {
      final (term, _, _) = await opened({'TERM': 'xterm-kitty'});
      expect(term.notify(const DesktopNotification('a', id: '1')), '1');
      expect(term.notify(const DesktopNotification('b')), 'auto-1');
      expect(term.notify(const DesktopNotification('c', id: 'ü')), 'auto-2');
    });

    test('null where nothing was shown: held back for the focus, no text, '
        'the bell only', () async {
      final (kitty, _, _) = await opened({'TERM': 'xterm-kitty'});
      expect(kitty.notify(const DesktopNotification(' ')), isNull);
      final (foot, _, _) = await opened({'TERM': 'foot'});
      expect(
        foot.notify(const DesktopNotification('a', whenUnfocused: true)),
        isNull,
      );
      final (none, link, clock) = await opened({'TERM': 'xterm-256color'});
      link.type('\x1b[O');
      await clock.flushMicrotasks();
      expect(none.notify(const DesktopNotification('a')), isNull);
      expect(link.text, endsWith('\x07'));
    });

    test("a click asked for comes back under the app's id; one on "
        "another process's is dropped", () async {
      final (term, link, clock) = await opened({'TERM': 'xterm-kitty'});
      final events = <InputEvent>[];
      final sub = term.events.listen(events.add);
      final before = link.text.length;
      term.notify(
        const DesktopNotification('Build', id: 'b'),
        reportActivation: true,
      );
      expect(
        link.text.substring(before),
        '\x1b]99;i=$pid.b:a=focus,report;Build\x1b\\',
      );
      link
        ..type('\x1b]99;i=$pid.b;\x1b\\')
        ..type('\x1b]99;i=1.b;\x1b\\');
      await clock.flushMicrotasks();
      expect(events.whereType<NotificationActivated>(), [
        const NotificationActivated('b'),
      ]);
      await sub.cancel();
    });

    test('where none is known to be shown the bell, only while the window '
        'has lost the focus, and not for a notification of no text', () async {
      final (term, link, clock) = await opened({'TERM': 'xterm-256color'});
      final before = link.text.length;
      term.notify(const DesktopNotification('Build'));
      expect(link.text.substring(before), isEmpty);
      link.type('\x1b[O');
      await clock.flushMicrotasks();
      term
        ..notify(const DesktopNotification('Build'))
        ..notify(const DesktopNotification(' '));
      expect(link.text.substring(before), '\x07');
    });

    test('shown only without the focus: o=unfocused where the terminal '
        'takes it, else held back while the window has the focus', () async {
      const note = DesktopNotification('Build', whenUnfocused: true);
      final (kitty, kittyLink, _) = await opened(
        {'TERM': 'xterm-256color'},
        keys: 'p=title,body:o=always,unfocused',
      );
      final k = kittyLink.text.length;
      kitty.notify(note);
      expect(kittyLink.text.substring(k), contains(':o=unfocused;Build'));

      final (foot, footLink, clock) = await opened({'TERM': 'foot'});
      final f = footLink.text.length;
      foot.notify(note);
      expect(footLink.text.substring(f), isEmpty);
      footLink.type('\x1b[O');
      await clock.flushMicrotasks();
      foot.notify(note);
      expect(
        footLink.text.substring(f),
        '\x1b]777;notify;Build;\x1b\\',
      );
    });
  });
}
