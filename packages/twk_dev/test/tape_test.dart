// The tape language parsed, statement by statement, and the errors it
// gives, by line; the themes; a known screen as a still SVG, to the byte;
// frames made an animation at their times; the screen a Show draws for a
// recording, drawing what the screen showed.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart' show Mod;
import 'package:twk_dev/src/tape.dart';
import 'package:twk_term/twk_term.dart';

/// [step] in a word or a few, to compare.
String _describe(TapeStep step) => switch (step) {
  TypeStep(:final text, :final delay) => 'type "$text"${_at(delay)}',
  KeyStep(:final name, :final key, :final count, :final delay) =>
    'key $name ${key.code.name}"${key.char}"/${key.modifiers}'
        '${count == 1 ? '' : ' x$count'}${_at(delay)}',
  SleepStep(:final duration) => 'sleep ${duration.inMilliseconds}ms',
  WaitStep(:final pattern, :final source, :final scope, :final timeout) =>
    'wait ${scope.name} $source ${pattern.pattern}${_at(timeout)}',
  HideStep(:final hide) => hide ? 'hide' : 'show',
  ScreenshotStep(:final path) => 'screenshot $path',
  DelayStep(:final delay, :final timeout) =>
    delay != null
        ? 'typing ${delay.inMilliseconds}ms'
        : 'timeout ${timeout!.inMilliseconds}ms',
};

String _at(Duration? d) => d == null ? '' : ' @${d.inMilliseconds}ms';

Matcher _error(String message) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', message),
);

void main() {
  group('Tape.parse', () {
    test('reads each statement: the outputs, the settings, the program '
        'and the steps in order; comments left out', () {
      final tape = Tape.parse(r'''
# a tape
Output out/demo.cast
Output out/demo.svg   # a comment after a statement

Set Width 40
Set Height 10
Set Theme LIGHT
Set FontSize 14
Set Padding 8
Set FontFamily "Fira Code"
Set Framerate 30
Set TypingSpeed 80ms
Env GREETING 'hello world'
Run dart "example/my app.dart" --flag
Type "ls -l # no comment"
Type@10ms 'a' "b"
Enter
Down@200ms 3
Ctrl+C
Alt+Shift+Tab
Ctrl+Left
Space 2
Shift+a
Sleep 1.5s
Sleep 250ms
Sleep 2
Wait /q quit/
Wait+Line@5s /^\$ #$/
Wait+Screen "a.b"
Hide
Show
Screenshot /tmp/still.svg
Set WaitTimeout 3s
''', name: 'demo.tape');

      expect(tape.name, 'demo.tape');
      expect(tape.outputs, ['out/demo.cast', 'out/demo.svg']);
      final s = tape.settings;
      expect((s.width, s.height), (40, 10));
      expect(s.theme, same(TapeTheme.light));
      expect((s.fontSize, s.padding, s.fontFamily), (14, 8, 'Fira Code'));
      expect(s.framerate, 30);
      expect(tape.environment, {'GREETING': 'hello world'});
      expect(tape.command, ['dart', 'example/my app.dart', '--flag']);
      expect(tape.steps.map(_describe), [
        'typing 80ms',
        'type "ls -l # no comment"',
        'type "ab" @10ms',
        'key Enter enter""/0',
        'key Down down""/0 x3 @200ms',
        'key Ctrl+C char"c"/${Mod.ctrl}',
        'key Alt+Shift+Tab tab""/${Mod.alt | Mod.shift}',
        'key Ctrl+Left left""/${Mod.ctrl}',
        'key Space char" "/0 x2',
        'key Shift+a char"a"/${Mod.shift}',
        'sleep 1500ms',
        'sleep 250ms',
        'sleep 2000ms',
        'wait screen /q quit/ q quit',
        r'wait line /^\$ #$/ ^\$ #$ @5000ms',
        r'wait screen "a.b" a\.b',
        'hide',
        'show',
        'screenshot /tmp/still.svg',
        'timeout 3000ms',
      ]);
      expect(tape.steps.map((s) => s.line).take(3), [12, 15, 16]);
      final waits = tape.steps.whereType<WaitStep>().toList();
      expect(waits[1].pattern.hasMatch('one\n\$ #\nthree'), isTrue);
      expect(waits[2].pattern.hasMatch('axb'), isFalse);
    });

    test('a tape of nothing is sh at 80 by 24, dark, and writes nothing', () {
      final tape = Tape.parse('\n# nothing\n');

      expect(tape.command, isNull);
      expect(tape.outputs, isEmpty);
      expect(tape.steps, isEmpty);
      expect((tape.settings.width, tape.settings.height), (80, 24));
      expect(tape.settings.theme, same(TapeTheme.dark));
      expect(tape.settings.padding, isNull);
    });

    test('says on which line what is wrong', () {
      final cases = {
        'Tipe "x"': '1: no statement "Tipe"',
        'Type hi': '1: Type takes quoted text: Type "text"',
        'Type "hi': '1: a string with no closing "',
        'Type "a"b': '1: no space after "a"',
        'Sleep soon': '1: "soon" is no duration: 500ms, 1.5s, 2, 1m',
        'Sleep': '1: Sleep takes a duration',
        'Sleep@1s 2': '1: Sleep takes no @<duration>',
        'Tipe@1s "x"': '1: no statement "Tipe"',
        'Type@soon "x"': '1: "soon" after @ is no duration',
        'Enter 0': '1: "0" is no count of presses',
        'Enter "2"': '1: Enter takes how many times, if anything',
        'Output demo.gif':
            '1: Output writes a .cast or an .svg file, not '
            'demo.gif',
        'Screenshot a.png': '1: Screenshot writes an .svg file, not a.png',
        'Wait': '1: Wait takes a /regular expression/ or "text"',
        'Wait /abc': '1: a regular expression with no closing /',
        'Hide now': '1: Hide takes nothing',
        'Env A': '1: Env takes a name and a value',
        'Run': '1: Run takes a program and its arguments',
        'Run a\nRun b': '2: a tape runs one program',
        'Set Width 0': '1: Set Width takes a number of cells from 1 to 1000',
        'Set Height': '1: Set Height takes a value',
        'Set FontSize 0': '1: Set FontSize takes a number of pixels',
        'Set TypingSpeed fast': '1: "fast" is no duration: 50ms, 0.1s',
        'Set Theme nope':
            '1: no theme "nope"; there are dark, light, xterm and a JSON '
            'object of colours',
        'Set Theme {"red": "red"}': "1: the theme's red is no #rrggbb: red",
        'Set Theme {"bg": "#000000"}': '1: a theme has no colour "bg"',
        'Set Colour red':
            '1: no setting "Colour"; there are Width, Height, Theme, '
            'FontSize, FontFamily, Padding, Framerate, TypingSpeed and '
            'WaitTimeout',
        'Type "x"\n\nSet Width 10':
            '3: Set Width comes before the first Type, key, Sleep, Wait, '
            'Hide, Show or Screenshot',
        'Sleep 1\nRun sh':
            '2: Run comes before the first Type, key, Sleep, '
            'Wait, Hide, Show or Screenshot',
      };
      for (final MapEntry(key: source, value: message) in cases.entries) {
        expect(
          () => Tape.parse(source, name: 't.tape'),
          _error('t.tape:$message'),
          reason: source,
        );
      }
      expect(
        () => Tape.parse('Wait /(/', name: 't.tape'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            startsWith('t.tape:1: /(/ is no regular expression: '),
          ),
        ),
      );
    });

    test('takes the typing speed and the timeout anywhere', () {
      final tape = Tape.parse(
        'Type "a"\nSet TypingSpeed 1s\nSet WaitTimeout 2m\nType "b"',
      );

      expect(tape.steps.map(_describe), [
        'type "a"',
        'typing 1000ms',
        'timeout 120000ms',
        'type "b"',
      ]);
    });
  });

  test('parseDuration reads seconds, ms, s and m', () {
    expect(parseDuration('500ms'), const Duration(milliseconds: 500));
    expect(parseDuration('1.5s'), const Duration(milliseconds: 1500));
    expect(parseDuration('2'), const Duration(seconds: 2));
    expect(parseDuration('.25'), const Duration(milliseconds: 250));
    expect(parseDuration('1m'), const Duration(minutes: 1));
    for (final bad in ['', 'x', '-1', '1h', '1 s', 's']) {
      expect(parseDuration(bad), isNull, reason: bad);
    }
  });

  group('TapeTheme', () {
    test('names the themes there are, case aside', () {
      expect(TapeTheme.parse('Dark'), same(TapeTheme.dark));
      expect(TapeTheme.parse('xterm'), same(TapeTheme.xterm));
      expect(TapeTheme.xterm.ansi, hasLength(16));
      expect(TapeTheme.light.ansi, hasLength(16));
      expect(TapeTheme.dark.ansi, hasLength(16));
    });

    test("takes a JSON object of colours, purple for magenta, dark's for "
        'those left out', () {
      final theme = TapeTheme.parse(
        '{"name": "mine", "background": "#101010", "purple": "#aa00aa", '
        '"brightPurple": "#FF00ff", "red": "#ff0000"}',
      );

      expect(theme.name, 'mine');
      expect(theme.background, 0x101010);
      expect(theme.foreground, TapeTheme.dark.foreground);
      expect(theme.cursor, TapeTheme.dark.foreground);
      expect(theme.ansi[1], 0xff0000);
      expect(theme.ansi[5], 0xaa00aa);
      expect(theme.ansi[13], 0xff00ff);
      expect(theme.ansi[2], TapeTheme.dark.ansi[2]);
      expect(() => TapeTheme.parse('{"red": 1}'), throwsFormatException);
      expect(() => TapeTheme.parse('[]'), throwsFormatException);
      expect(() => TapeTheme.parse('{'), throwsFormatException);
    });
  });

  group('screenSvg', () {
    test('draws a known screen: text in runs of a style as long as their '
        'cells, backgrounds as rects, box lines as paths, a wide character '
        'on its own, escaped', () {
      final screen = TerminalEmulator(width: 12, height: 2)
        ..feedText('\x1b[1;31mhi\x1b[0m \x1b[44m<&>\x1b[0m\r\n╭─╮ 世\x1b[?25l');

      expect(
        screenSvg(screen, const SvgLook()),
        [
          '<svg xmlns="http://www.w3.org/2000/svg" width="147.2" ',
          'height="70.4" viewBox="0 0 184 88"><style>text{white-space:pre}',
          '.c{fill:#aeafad;fill-opacity:.6}',
          '.t0{fill:#cd3131;font-weight:bold}',
          '.b0{fill:#2472c8}',
          'path{fill:none;stroke-linecap:square}',
          '.s0{stroke:#cccccc;stroke-width:2}</style>',
          '<rect width="184" height="88" rx="8" fill="#1e1e1e"/>',
          '<svg x="20" y="20" width="144" height="48" ',
          'font-family="${SvgLook.defaultFontFamily}" font-size="20" ',
          'fill="#cccccc">',
          '<defs>',
          '<g id="a"><rect x="36" width="36" height="24" class="b0"/>',
          '<text y="18" class="t0" textLength="24">hi</text>',
          '<text x="36" y="18" textLength="36">&lt;&amp;&gt;</text></g>',
          '<g id="b"><path d="M12 12A6 6 0 0 0 6 18V24',
          'M24 12A6 6 0 0 1 30 18V24M12 12H24" class="s0"/>',
          '<text x="48" y="18">世</text></g>',
          '</defs>',
          '<g><use href="#a"/><use href="#b" y="24"/></g>',
          '</svg></svg>\n',
        ].join(),
      );
    });

    test("takes the theme's colours, the palette's past 15, a reversed "
        'cell, dim text and the cursor', () {
      final screen = TerminalEmulator(width: 8, height: 1)
        ..feedText(
          [
            '\x1b[7mr\x1b[0m\x1b[2md\x1b[0m\x1b[38;5;196mx\x1b[0m ',
            '\x1b[38;2;1;2;3m█▌\x1b[0m',
          ].join(),
        );
      final svg = screenSvg(
        screen,
        const SvgLook(theme: TapeTheme.light, fontSize: 20, padding: 0),
      );

      expect(svg, contains('width="96" height="24" viewBox="0 0 96 24"'));
      expect(svg, contains('fill="#ffffff"/>'));
      // reversed: the default text colour behind, the background's in front
      expect(svg, contains('.t0{fill:#ffffff}'));
      expect(svg, contains('<rect width="12" height="24" class="b0"/>'));
      expect(svg, contains('.b0{fill:#333333}'));
      // dim: halfway to the background
      expect(svg, contains('.t1{fill:#999999}'));
      // palette colour 196, xterm's
      expect(svg, contains('.t2{fill:#ff0000}'));
      // blocks: a full one and a half, of their colour, as rects
      expect(svg, contains('.b1{fill:#010203}'));
      expect(
        svg,
        contains(
          [
            '<rect x="48" y="0" width="12" height="24" class="b1"/>',
            '<rect x="60" y="0" width="6" height="24" class="b1"/>',
          ].join(),
        ),
      );
      expect(
        svg,
        contains('<rect x="72" y="0" width="12" height="24" class="c"/>'),
      );
    });
  });

  test('the right half, the upper eighth and the right eighth of a cell, '
      'and a shade, are rects of their parts, the shade at its opacity', () {
    final screen = TerminalEmulator(width: 4, height: 1)
      ..feedText('▐▔▕▒\x1b[?25l');
    final rects = [
      for (final m in RegExp(
        '<rect x[^>]*>',
      ).allMatches(screenSvg(screen, const SvgLook(padding: 0))))
        m[0],
    ];

    const shade =
        '<rect x="36" y="0" width="12" height="24" class="b0" '
        'fill-opacity="0.5"/>';
    expect(rects, [
      '<rect x="6" y="0" width="6" height="24" class="b0"/>',
      '<rect x="12" y="0" width="12" height="3" class="b0"/>',
      '<rect x="34.5" y="0" width="1.5" height="24" class="b0"/>',
      shade,
    ]);
  });

  group('SvgFilm', () {
    test('counts its frames; one of none cannot be drawn', () {
      final film = SvgFilm(const SvgLook());
      expect(film.length, 0);
      expect(() => film.render(Duration.zero), throwsStateError);
      film.add(Duration.zero, TerminalEmulator(width: 2, height: 1));
      expect(film.length, 1);
    });

    test('plays the frames at their times, over and over, a row drawn once '
        'for every frame that shows it; a frame sooner than the gap after '
        'the last takes its place, one that shows the same is none', () {
      final screen = TerminalEmulator(width: 6, height: 2)
        ..feedText('\r\nzz\x1b[H');
      final film = SvgFilm(
        const SvgLook(),
        minGap: const Duration(milliseconds: 20),
      )..add(Duration.zero, screen);
      screen.feedText('a');
      film
        ..add(const Duration(milliseconds: 500), screen)
        ..add(const Duration(milliseconds: 510), screen)
        ..add(const Duration(milliseconds: 700), screen);
      screen.feedText('b');
      film.add(const Duration(milliseconds: 1000), screen);
      screen.feedText('c');
      film.add(const Duration(milliseconds: 1010), screen);

      expect(film.times, const [
        Duration.zero,
        Duration(milliseconds: 500),
        Duration(milliseconds: 1000),
      ]);
      final svg = film.render(const Duration(seconds: 2));
      expect(
        svg,
        contains(
          [
            '.f{animation:f 2s steps(1,end) infinite}\n',
            '@keyframes f{0%{transform:translateX(0px)}',
            '25%{transform:translateX(-72px)}',
            '50%{transform:translateX(-144px)}',
            '100%{transform:translateX(-144px)}}',
          ].join(),
        ),
      );
      expect(
        svg,
        contains(
          [
            '<defs><g id="a"><text y="18" textLength="24">zz</text></g>',
            '<g id="b"><text y="18">a</text></g>',
            '<g id="c"><text y="18" textLength="36">abc</text></g></defs>',
          ].join(),
        ),
      );
      expect(
        svg,
        contains(
          [
            '<g class="f">',
            '<g><use href="#a" y="24"/>',
            '<rect x="0" y="0" width="12" height="24" class="c"/></g>',
            '<g transform="translate(72)"><use href="#b"/>',
            '<use href="#a" y="24"/>',
            '<rect x="12" y="0" width="12" height="24" class="c"/></g>',
            '<g transform="translate(144)"><use href="#c"/>',
            '<use href="#a" y="24"/>',
            '<rect x="36" y="0" width="12" height="24" class="c"/></g>',
            '</g>',
          ].join(),
        ),
      );
      // what lies past the end is left out
      expect(
        film.render(const Duration(milliseconds: 800)),
        allOf(
          contains(
            [
              '@keyframes f{0%{transform:translateX(0px)}',
              '62.5%{transform:translateX(-72px)}',
              '100%{transform:translateX(-72px)}}',
            ].join(),
          ),
          isNot(contains('abc')),
        ),
      );
    });

    test('is still, with no animation, with one frame', () {
      final screen = TerminalEmulator(width: 4, height: 1)..feedText('hi');
      final svg =
          (SvgFilm(const SvgLook())..add(const Duration(seconds: 1), screen))
              .render(const Duration(seconds: 3));

      expect(svg, isNot(contains('animation')));
      expect(svg, isNot(contains('class="f"')));
      expect(svg, contains('<text y="18" textLength="24">hi</text>'));
    });
  });

  test('redraw draws the screen as it is, in its styles, the cursor where '
      'it is and hidden, on the alternate screen', () {
    final shown = TerminalEmulator(width: 20, height: 4)
      ..feedText(
        '\x1b[?1049h\x1b[2;3H\x1b[1;4:3;38;5;200;48;2;1;2;3mstyled'
        '\x1b[0m wide 世界\r\n\x1b[7;9;53;3;2;95;104mx\x1b[0m   '
        '\x1b[41m  \x1b[0m\x1b[1;5H\x1b[?25l',
      );
    final drawn = TerminalEmulator(width: 20, height: 4)
      ..feedText(redraw(shown));

    expect(drawn.alternateScreen, isTrue);
    expect(drawn.text, shown.text);
    expect((drawn.cursorX, drawn.cursorY), (4, 0));
    expect(drawn.cursorVisible, isFalse);
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 20; x++) {
        final (a, b) = (shown.styleAt(x, y), drawn.styleAt(x, y));
        expect(
          (
            drawn.styles.fgOf(b),
            drawn.styles.bgOf(b),
            drawn.styles.attrsOf(b),
            drawn.cellAt(x, y),
          ),
          (
            shown.styles.fgOf(a),
            shown.styles.bgOf(a),
            shown.styles.attrsOf(a),
            shown.cellAt(x, y),
          ),
          reason: 'cell ($x, $y)',
        );
      }
    }
  });
}
