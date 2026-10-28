import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

void main() {
  group('clipboard', () {
    test('OSC 52 with base64 UTF-8', () {
      final s = clipboardSequence('привет 🧪');
      expect(s, startsWith('\x1b]52;c;'));
      expect(s, endsWith('\x1b\\'));
      final b64 = s.substring(7, s.length - 2);
      expect(utf8.decode(base64.decode(b64)), 'привет 🧪');
    });

    test('tmux: as it is, for set-clipboard, then in DCS passthrough, '
        'every ESC doubled', () {
      final b64 = base64.encode(utf8.encode('привет 🧪'));
      expect(
        clipboardSequence('привет 🧪', multiplexer: Multiplexer.tmux),
        '\x1b]52;c;$b64\x1b\\'
        '\x1bPtmux;\x1b\x1b]52;c;$b64\x1b\x1b\\\x1b\\',
      );
    });

    test('screen: in DCS pieces of at most 252 bytes, ended by BEL', () {
      final text = 'x' * 600;
      final s = clipboardSequence(text, multiplexer: Multiplexer.screen);
      final pieces = RegExp(
        '\x1bP(.*?)\x1b\\\\',
        dotAll: true,
      ).allMatches(s).map((m) => m[1]!).toList();
      expect(pieces.map((p) => '\x1bP$p\x1b\\').join(), s);
      // 7 bytes before the 800 of base64, BEL after them
      expect(pieces.map((p) => p.length), [252, 252, 252, 52]);
      expect(
        pieces.join(),
        '\x1b]52;c;${base64.encode(utf8.encode(text))}\x07',
      );
    });
  });

  test('title: controls cannot escape the string', () {
    final s = titleSequence('chat\x1b]0;evil\x07\nok \u{9B}x 🧪');
    expect(s, '\x1b]2;chat]0;evilok x 🧪\x1b\\');
  });

  group('notification', () {
    String notify(
      NotificationProtocol protocol,
      String title,
      String body, {
      Multiplexer multiplexer = Multiplexer.none,
    }) => notifySequence(
      title,
      body,
      protocol: protocol,
      multiplexer: multiplexer,
      id: '7',
    );

    test('OSC 9 (iTerm2): one message', () {
      const p = NotificationProtocol.osc9;
      expect(notify(p, 'Build', 'done'), '\x1b]9;Build: done\x1b\\');
      expect(notify(p, '', 'done'), '\x1b]9;done\x1b\\');
      expect(notify(p, 'Build', ''), '\x1b]9;Build\x1b\\');
      expect(notify(p, 'Тесты', '3; ok 🧪'), '\x1b]9;Тесты: 3; ok 🧪\x1b\\');
    });

    test('OSC 777 (urxvt notify): a title and a body, `;` ending neither, '
        'a body without a title shown as the title', () {
      const p = NotificationProtocol.osc777;
      expect(notify(p, 'Build', 'done'), '\x1b]777;notify;Build;done\x1b\\');
      expect(notify(p, 'Build', ''), '\x1b]777;notify;Build;\x1b\\');
      expect(notify(p, '', 'done'), '\x1b]777;notify;done;\x1b\\');
      expect(
        notify(p, 'a;b', '3 passed; 1 failed 🧪'),
        '\x1b]777;notify;a,b;3 passed, 1 failed 🧪\x1b\\',
      );
    });

    test('OSC 99 (kitty): the title, then the body under the same id; a '
        'body with line breaks in base64', () {
      const p = NotificationProtocol.osc99;
      expect(
        notify(p, 'Build', 'done; 3 tests 🧪'),
        '\x1b]99;i=7:d=0;Build\x1b\\'
        '\x1b]99;i=7:p=body;done; 3 tests 🧪\x1b\\',
      );
      expect(notify(p, 'Build', ''), '\x1b]99;i=7;Build\x1b\\');
      expect(notify(p, '', 'done'), '\x1b]99;i=7:p=body;done\x1b\\');
      const title = '\x1b]99;i=7:d=0;Build log\x1b\\';
      final lines = base64.encode(utf8.encode('line 1\nline 2\n\nok'));
      expect(
        notify(p, 'Build\nlog', 'line 1\r\nline 2\r\n\rok'),
        '$title\x1b]99;i=7:p=body:e=1;$lines\x1b\\',
      );
      expect(
        notifySequence('t', '', protocol: p, id: 'a:b;c=d 1\x1b\\'),
        '\x1b]99;i=abcd1;t\x1b\\',
        reason: "only kitty's identifier characters",
      );
    });

    test('nothing where no protocol is known, or nothing to show', () {
      for (final p in NotificationProtocol.values) {
        expect(notify(p, '', ''), '', reason: p.name);
        expect(notify(p, '\x07', '\x1b\n'), '', reason: p.name);
      }
      expect(notify(NotificationProtocol.none, 'Build', 'done'), '');
      expect(
        notify(
          NotificationProtocol.none,
          'Build',
          'done',
          multiplexer: Multiplexer.tmux,
        ),
        '',
      );
    });

    test('control characters cannot end the string or start another', () {
      const evil = 'a\x1b]2;x\x07b\x1b\\c\u{9C}d\u{9D}e\x00f\x7Fg\th\ni';
      const clean = r'a]2;xb\cdefg h i';
      expect(
        notify(NotificationProtocol.osc9, evil, ''),
        '\x1b]9;$clean\x1b\\',
      );
      expect(
        notify(NotificationProtocol.osc777, evil, evil),
        '\x1b]777;notify;${clean.replaceAll(';', ',')};'
        '${clean.replaceAll(';', ',')}\x1b\\',
      );
      final kitty = notify(NotificationProtocol.osc99, evil, evil);
      final body = base64.encode(
        utf8.encode(
          r'a]2;xb\cdefg h'
          '\ni',
        ),
      );
      expect(
        kitty,
        '\x1b]99;i=7:d=0;$clean\x1b\\\x1b]99;i=7:p=body:e=1;$body\x1b\\',
      );
    });

    test('the title is cut to 256 bytes of UTF-8 and the body to 1024, '
        'between graphemes, ending with …', () {
      const thumb = '👍🏽'; // 8 bytes, one grapheme
      final long = thumb * 300;
      final s = notify(NotificationProtocol.osc777, long, long);
      final [_, _, title, body] = s.substring(2, s.length - 2).split(';');
      expect(title, '${thumb * 31}…');
      expect(body, '${thumb * 127}…');
      final fits = notify(NotificationProtocol.osc777, 't' * 256, 'b' * 1024);
      expect(fits, '\x1b]777;notify;${'t' * 256};${'b' * 1024}\x1b\\');
    });

    test('tmux: in DCS passthrough, every ESC doubled', () {
      expect(
        notify(
          NotificationProtocol.osc777,
          'Build',
          'done',
          multiplexer: Multiplexer.tmux,
        ),
        '\x1bPtmux;\x1b\x1b]777;notify;Build;done\x1b\x1b\\\x1b\\',
      );
      expect(
        notify(
          NotificationProtocol.osc99,
          'Build',
          'done',
          multiplexer: Multiplexer.tmux,
        ),
        '\x1bPtmux;\x1b\x1b]99;i=7:d=0;Build\x1b\x1b\\'
        '\x1b\x1b]99;i=7:p=body;done\x1b\x1b\\\x1b\\',
      );
    });

    test('screen: in DCS pieces of at most 252 bytes, whole characters, '
        'the OSCs ended by BEL', () {
      expect(
        notify(
          NotificationProtocol.osc99,
          'Build',
          'done',
          multiplexer: Multiplexer.screen,
        ),
        '\x1bP\x1b]99;i=7:d=0;Build\x07\x1b]99;i=7:p=body;done\x07\x1b\\',
      );
      final title = 'x${'é' * 127}'; // 255 bytes
      final body = 'y' * 600;
      final s = notify(
        NotificationProtocol.osc9,
        title,
        body,
        multiplexer: Multiplexer.screen,
      );
      final pieces = RegExp(
        '\x1bP(.*?)\x1b\\\\',
        dotAll: true,
      ).allMatches(s).map((m) => m[1]!).toList();
      expect(pieces.map((p) => '\x1bP$p\x1b\\').join(), s);
      expect(pieces.map((p) => utf8.encode(p).length), [251, 252, 252, 107]);
      expect(pieces.join(), '\x1b]9;$title: $body\x07');
    });
  });
}
