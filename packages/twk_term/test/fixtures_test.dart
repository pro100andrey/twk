// Output of real programs in an 80x24 pseudo-terminal, captured with
// tool/pty_run.py (`--out`, the input typed as given) under
// `env -i HOME=… TERM=xterm-256color LANG=C.UTF-8`:
//
//   bash       bash --rcfile rc -i 2>&1, rc setting a coloured PS1 and a
//                title; typed: echo hello world, ls, a printf of bold
//                red, an echo wrapping twice, a printf of tabs, CJK and a
//                combining accent, exit
//   nano       nano -I notes.txt (vim isn't installed here): two lines
//                typed in, Up and Home, `>> `, Ctrl+X, n
//   less       less -R pager.txt (60 lines, every tenth bold green):
//                Space, /green, q
//   htop       htop -d 5 -p $$ (its own process only): a few frames, q
//   git_log    git --no-pager -c color.ui=always log --graph
//                --decorate=short --format='%C(auto)%h%d %s
//                %C(blue)(%an)%C(reset)' -n 12 a69eb9e
//   chat_demo  dart run packages/twk_core/example/chat_demo.dart
//                --seconds=2 (twk_core's demo; the probe answered by
//                pty_run as a modern terminal)
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_term/twk_term.dart';

import 'support.dart';

Uint8List fixture(String name) =>
    File('test/fixtures/$name.bin').readAsBytesSync();

/// An 80x24 emulator fed [bytes], strict: every sequence the programs
/// wrote is one it knows.
(TerminalEmulator, List<TerminalEvent>) run(List<int> bytes) {
  final events = <TerminalEvent>[];
  final t = TerminalEmulator(strict: true, onEvent: events.add)..feed(bytes);
  return (t, events);
}

List<String> rows(TerminalEmulator t) => [
  for (var y = 0; y < t.height; y++) t.lineText(y),
];

Color fg(TerminalEmulator t, int x, int y) => t.styles.fgOf(t.styleAt(x, y));
Color bg(TerminalEmulator t, int x, int y) => t.styles.bgOf(t.styleAt(x, y));
int attrs(TerminalEmulator t, int x, int y) =>
    t.styles.attrsOf(t.styleAt(x, y));

void main() {
  test('bash: prompts, output, a wrapped line, tabs and wide text', () {
    final (t, events) = run(fixture('bash'));
    const prompt = r'user@host:~/work$';
    const digits = '0123456789';
    const letters = 'abcdefghijklmnopqrstuvwxyz';
    const echoed = '$digits$letters$digits$letters$digits';
    expect(rows(t), [
      '$prompt echo hello world',
      'hello world',
      '$prompt ls',
      'notes.txt',
      '$prompt printf "\\033[1;31mred\\033[0m plain\\n"',
      'red plain',
      '$prompt echo ${echoed.substring(0, 57)}',
      echoed.substring(57),
      echoed.substring(0, 80),
      echoed.substring(80),
      '$prompt printf "a\\tb\\t\\xe4\\xb8\\xad\\xe6\\x96\\x87 e\\xcc\\x81\\n"',
      'a       b       中文 e\u0301',
      '$prompt exit',
      'exit',
      for (var i = 0; i < 10; i++) '',
    ]);
    expect(t.line(6).wrapped, isTrue);
    expect(t.line(8).wrapped, isTrue);
    expect(t.line(9).wrapped, isFalse);
    expect(t.cellText(16, 11), '中');
    expect(t.cellText(21, 11), 'e\u0301');
    expect((t.cursorX, t.cursorY), (0, 14));
    // the prompt's colours, and the bold red the printf asked for
    expect(fg(t, 0, 0), Color.green);
    expect(fg(t, 9, 0), Color.defaultColor);
    expect(fg(t, 10, 0), Color.blue);
    expect((fg(t, 0, 5), attrs(t, 0, 5)), (Color.red, Attr.bold));
    expect((fg(t, 4, 5), attrs(t, 4, 5)), (Color.defaultColor, 0));
    expect(t.title, 'bash: work');
    expect(t.mode(TerminalMode.bracketedPaste), isFalse);
    expect(
      events.whereType<ModeChanged>().where((e) => e.enabled),
      hasLength(6),
      reason: 'bracketed paste on for each prompt',
    );
  });

  group('nano', () {
    test('editing: the title bar, the text and the shortcuts', () {
      final (t, _) = run(before(fixture('nano'), 'Save modified'));
      expect(t.alternateScreen, isTrue);
      expect(t.mode(TerminalMode.cursorKeys), isTrue);
      expect(t.mode(TerminalMode.keypad), isTrue);
      const title =
          '  GNU nano 9.2                       notes.txt '
          '                       Modified';
      const keys1 =
          '^G Help      ^O Write Out ^F Where Is  '
          '^K Cut       ^T Execute   ^C Location';
      const keys2 =
          r'^X Exit      ^R Read File ^\ Replace   '
          '^U Paste     ^J Justify   ^/ Go To Line';
      expect(rows(t), [
        title,
        '>> Hello from nano',
        'second linefirst line',
        '^[[33myellow^[[0m line',
        for (var i = 0; i < 18; i++) '',
        keys1,
        keys2,
      ]);
      // the title bar in reverse video across the screen
      for (final x in [0, 40, 79]) {
        expect(attrs(t, x, 0), Attr.reverse);
      }
      expect(attrs(t, 0, 22), Attr.reverse);
      expect(attrs(t, 1, 22), Attr.reverse);
      expect(attrs(t, 2, 22), 0);
      // the escape in the file is shown, its colours not applied
      expect(fg(t, 8, 3), Color.defaultColor);
    });

    test('quitting: the primary screen and the modes back', () {
      final (t, events) = run(fixture('nano'));
      expect(t.alternateScreen, isFalse);
      expect(t.mode(TerminalMode.cursorKeys), isFalse);
      expect(t.mode(TerminalMode.keypad), isFalse);
      expect(t.mode(TerminalMode.bracketedPaste), isFalse);
      expect(t.cursorVisible, isTrue);
      expect(rows(t).every((r) => r.isEmpty), isTrue);
      expect(events.whereType<TitleChanged>(), isEmpty);
    });
  });

  test('less: a page after the search, the match standing out', () {
    final (t, _) = run(before(fixture('less'), r'\e[?1049l'));
    expect(rows(t), [
      for (var n = 30; n <= 52; n++)
        if (n % 10 == 0) 'line $n is green and bold' else 'line $n of the file',
      '',
    ]);
    // lines 30, 40 and 50 bold green, each match in reverse video too
    for (final y in [0, 10, 20]) {
      expect((fg(t, 0, y), attrs(t, 0, y)), (Color.green, Attr.bold));
      expect(attrs(t, 11, y), Attr.bold | Attr.reverse);
      expect(attrs(t, 15, y), Attr.bold | Attr.reverse);
      expect(attrs(t, 16, y), Attr.bold);
    }
    expect((fg(t, 0, 1), attrs(t, 0, 1)), (Color.defaultColor, 0));
    final (after, _) = run(fixture('less'));
    expect(after.alternateScreen, isFalse);
    expect(after.mode(TerminalMode.keypad), isFalse);
  });

  test('htop: meters, the header, its process and the function keys', () {
    final (t, _) = run(before(fixture('htop'), r'\r\e[J\e[?12l'));
    final screen = rows(t);
    for (var y = 1; y <= 3; y++) {
      expect(screen[y], matches(RegExp(r'^(\s+\d+\[\s*[\d.]+\]){8}$')));
    }
    expect(screen[4], startsWith('  Mem['));
    expect(screen[5], startsWith('  Swp['));
    expect(screen[5], contains('Load average:'));
    expect(screen[6].trim(), startsWith('Uptime:'));
    expect(screen[8], '  [Main] [I/O]');
    expect(
      screen[9],
      '    PID USER       PRI  NI  VIRT   RES  '
      'PRIV S  CPU%▽MEM%   TIME+  Command',
    );
    expect(screen[10], endsWith('htop -d 5 -p'));
    expect(screen.sublist(11, 23).every((r) => r.isEmpty), isTrue);
    expect(
      screen[23],
      'F1Help  F2Setup F3SearchF4FilterF5Tree  '
      'F6SortByF7Nice -F8Nice +F9Kill  F10Quit',
    );
    // black on green header and selected process, black on cyan keys
    expect((fg(t, 4, 9), bg(t, 4, 9)), (Color.black, Color.green));
    expect(bg(t, 79, 9), Color.green);
    expect(bg(t, 0, 10), Color.cyan);
    expect(
      (fg(t, 0, 23), bg(t, 0, 23)),
      (Color.defaultColor, Color.defaultColor),
    );
    expect((fg(t, 2, 23), bg(t, 2, 23)), (Color.black, Color.cyan));
    expect(t.mouseProtocol, MouseProtocol.buttons);
    expect(t.mouseEncoding, MouseEncoding.sgr);
    expect(t.cursorVisible, isFalse);
    final (after, _) = run(fixture('htop'));
    expect(after.mouseProtocol, MouseProtocol.off);
    expect(after.alternateScreen, isFalse);
  });

  test('git log: wrapped lines, the scrollback and the colours', () {
    final bytes = fixture('git_log');
    final (t, _) = run(bytes);
    final plain =
        utf8
            .decode(bytes)
            .replaceAll(RegExp('\x1b\\[[0-9;]*m'), '')
            .split('\r\n')
          ..removeLast();
    expect(plain, hasLength(12));
    expect(logicalLines(t), plain);
    expect(t.scrollbackLength, greaterThan(0));
    final first = t.scrollbackLine(0);
    expect(first.text(t.glyphs), startsWith('* a69eb9e Pick files'));
    expect(t.styles.fgOf(first.styles[2]), Color.yellow);
    expect(t.styles.fgOf(first.styles[10]), Color.defaultColor);
    final last = t.line(t.cursorY - 1);
    final name = last.text(t.glyphs).indexOf('(Andrii');
    expect(t.styles.fgOf(last.styles[name]), Color.blue);
  });

  group('chat_demo, a twk_core app', () {
    test('answers its probe', () {
      final out = <int>[];
      TerminalEmulator(onOutput: out.addAll).feed(fixture('chat_demo'));
      expect(
        utf8.decode(out).replaceAll('\x1b', r'\e'),
        r'\e[?2026;2$y\e[?2027;2$y\e[?2048;0$y\e[?69;0$y\e[?2031;0$y'
        r'\e]10;rgb:e5e5/e5e5/e5e5\e\\e]11;rgb:0000/0000/0000\e\'
        r'\e[?0u\e[1;2R\e[?62;22;52c',
      );
    });

    test('its last frame', () {
      final (t, events) = run(
        before(fixture('chat_demo'), r'\e[0m\e]8;;\e\\e[<u'),
      );
      final screen = rows(t);
      expect(screen[0], startsWith(' twk_core · chat demo · Ctrl+E: editor'));
      expect(
        screen[2],
        ' tool: grapheme clusters 👨\u200D👩\u200D👧 and '
        'flags 🇺🇦 are one cell each',
      );
      expect(screen[5], ' user: проверь прокрутку и ширину эмодзи 🧪');
      expect(screen[6], ' tool: compiled 87 files · 你好 · 0 warnings');
      expect(screen[22], '> pasted text');
      expect(screen[23], startsWith(' frame '));
      expect(screen[23].length, 80, reason: 'cut at the edge, autowrap off');
      expect(t.mode(TerminalMode.autowrap), isFalse);
      expect(t.mode(TerminalMode.mouseDrags), isTrue);
      expect(t.mode(TerminalMode.focus), isTrue);
      expect(t.cursorShape, CursorShape.bar);
      expect(t.title, 'twk_core · chat demo');
      expect(
        (attrs(t, 1, 0), fg(t, 1, 0), bg(t, 1, 0)),
        (
          Attr.bold,
          const Color.rgb(255, 255, 255),
          const Color.rgb(0, 90, 180),
        ),
      );
      expect(
        t.styles.linkOf(t.styleAt(1, 6)),
        'file:///tmp/twk_core_build.log',
      );
      expect(t.styles.linkOf(t.styleAt(1, 4)), isNull);
      expect(
        events.whereType<ModeChanged>().where(
          (e) => e.mode == TerminalMode.synchronizedOutput,
        ),
        hasLength(greaterThan(40)),
      );
    });

    test('the terminal handed back', () {
      final (t, _) = run(fixture('chat_demo'));
      expect(t.alternateScreen, isFalse);
      expect(t.mode(TerminalMode.autowrap), isTrue);
      expect(t.mouseProtocol, MouseProtocol.off);
      expect(t.cursorShape, CursorShape.terminalDefault);
      expect(t.cursorVisible, isTrue);
    });
  });
}
