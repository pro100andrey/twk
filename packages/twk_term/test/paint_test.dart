import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_term/twk_term.dart';

/// Row [y] of [canvas]'s surface as text.
String rowText(Canvas canvas, int y) {
  final s = canvas.surface;
  final sb = StringBuffer();
  for (var x = 0; x < s.width; x++) {
    final c = s.cells[y * s.width + x];
    if ((c & kCont) == 0) {
      sb.write(canvas.glyphs.stringOf(c));
    }
  }
  return sb.toString().trimRight();
}

Canvas canvasOf(int w, int h) =>
    Canvas(Surface(w, h), StyleTable(), GlyphTable());

void main() {
  test('cells carry over as they are into the same tables', () {
    final canvas = canvasOf(10, 3);
    final t =
        TerminalEmulator(
            width: 10,
            height: 3,
            styles: canvas.styles,
            glyphs: canvas.glyphs,
          )
          ..feedText('\x1b[31mab\x1b[0me\u0301中\r\n\x1b[44mx\x1b[K')
          ..paint(canvas);
    final s = canvas.surface;
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 10; x++) {
        expect(s.cells[y * 10 + x], t.cellAt(x, y), reason: '$x,$y');
        expect(s.styles[y * 10 + x], t.styleAt(x, y), reason: '$x,$y');
      }
    }
  });

  test('styles and glyphs are carried over to other tables', () {
    final t = TerminalEmulator(width: 10, height: 2)
      ..feedText(
        '\x1b[1;31;48;5;20mab\x1b[0m e\u0301 '
        '\x1b]8;;http://x\x1b\\L\x1b]8;;\x1b\\\x1b[4:3;58:5:2mu',
      );
    final canvas = canvasOf(10, 2);
    t.paint(canvas);
    expect(rowText(canvas, 0), 'ab e\u0301 Lu');
    final st = canvas.styles;
    int style(int x) => canvas.surface.styles[x];
    expect(st.fgOf(style(0)), Color.red);
    expect(st.bgOf(style(1)), const Color.indexed(20));
    expect(st.attrsOf(style(1)), Attr.bold);
    expect(st.attrsOf(style(2)), 0);
    expect(st.linkOf(style(5)), 'http://x');
    expect(st.attrsOf(style(6)), Attr.curlyUnderline);
    expect(st.underlineColorOf(style(6)), Color.green);
    // painted again: the same pens and glyph ids
    final before = List.of(canvas.surface.cells);
    t.paint(canvas);
    expect(canvas.surface.cells, before);
    expect(canvas.glyphs.length, 1);
  });

  test('at an offset, within the canvas translation and clip', () {
    final t = TerminalEmulator(width: 4, height: 2)..feedText('ab中\r\ncdef');
    final canvas = canvasOf(8, 4)
      ..translate(1, 1)
      ..clipRect(0, 0, 4, 2);
    t.paint(canvas, x: 1);
    expect(
      [for (var y = 0; y < 4; y++) rowText(canvas, y)],
      [
        '',
        '  ab',
        '  cde',
        '',
      ],
    );
  });

  test('scrolled back into the scrollback', () {
    final t = TerminalEmulator(width: 4, height: 2)
      ..feedText('1\r\n2\r\n3\r\n4');
    final canvas = canvasOf(4, 2);
    t.paint(canvas, scrollOffset: 1);
    expect([rowText(canvas, 0), rowText(canvas, 1)], ['2', '3']);
    t.paint(canvas, scrollOffset: 9);
    expect([rowText(canvas, 0), rowText(canvas, 1)], ['1', '2']);
    t
      ..feedText('\x1b[?1049h')
      ..paint(canvas, scrollOffset: 1);
    expect(
      [rowText(canvas, 0), rowText(canvas, 1)],
      ['', ''],
      reason: 'the alternate screen has none',
    );
  });

  test('reverse video turns every cell around', () {
    final t = TerminalEmulator(width: 2, height: 1)
      ..feedText('\x1b[7ma\x1b[0mb');
    final canvas = canvasOf(2, 1);
    t.paint(canvas);
    expect(canvas.styles.attrsOf(canvas.surface.styles[0]), Attr.reverse);
    t
      ..feedText('\x1b[?5h')
      ..paint(canvas);
    expect(canvas.styles.attrsOf(canvas.surface.styles[0]), 0);
    expect(canvas.styles.attrsOf(canvas.surface.styles[1]), Attr.reverse);
  });

  test('the default colors in those given, the others as they are', () {
    final t = TerminalEmulator(width: 5, height: 1)
      ..feedText('a\x1b[31mb\x1b[0;7mc\x1b[0;44md\x1b[0;4:3me');
    final canvas = canvasOf(5, 1);
    const fg = Color.rgb(1, 2, 3);
    const bg = Color.rgb(4, 5, 6);
    t.paint(canvas, fg: fg, bg: bg);
    final st = canvas.styles;
    int style(int x) => canvas.surface.styles[x];
    expect([st.fgOf(style(0)), st.bgOf(style(0))], [fg, bg]);
    expect([st.fgOf(style(1)), st.bgOf(style(1))], [Color.red, bg]);
    expect(
      [st.fgOf(style(2)), st.bgOf(style(2)), st.attrsOf(style(2))],
      [fg, bg, Attr.reverse],
      reason: 'reverse video turns them around as it would the defaults',
    );
    expect([st.fgOf(style(3)), st.bgOf(style(3))], [fg, Color.blue]);
    expect(
      st.underlineColorOf(style(4)),
      Color.defaultColor,
      reason: 'an underline of the default color is drawn in the text color',
    );
    // other colors: the pens follow, and the emulator kept none of them
    t.paint(canvas, fg: Color.green);
    expect(
      [st.fgOf(style(0)), st.bgOf(style(0))],
      [
        Color.green,
        Color.defaultColor,
      ],
    );
    expect(t.styles.fgOf(t.styleAt(0, 0)), Color.defaultColor);
    t.paint(canvas);
    expect(style(0), 0, reason: 'by default the defaults stay');
  });

  test('a line painted on its own, also a copy of one', () {
    final t = TerminalEmulator(width: 4, height: 2)
      ..feedText('\x1b[?5hab\r\n中');
    final canvas = canvasOf(6, 2);
    final copy = TerminalLine(4);
    copy.cells.setAll(0, t.line(1).cells);
    t
      ..paintLine(canvas, t.line(0), x: 2)
      ..paintLine(canvas, copy, y: 1);
    expect([rowText(canvas, 0), rowText(canvas, 1)], ['  ab', '中']);
    expect(canvas.styles.attrsOf(canvas.surface.styles[2]), Attr.reverse);
  });

  group('a program writing ever more 24-bit colors', () {
    final floor = TerminalEmulator.sweepFloor;
    final screenFloor = Screen.sweepFloor;
    tearDown(() {
      TerminalEmulator.sweepFloor = floor;
      Screen.sweepFloor = screenFloor;
    });

    /// `X` in each red of [from] to [to], one after another.
    String reds(int from, int to) => [
      for (var i = from; i < to; i++) '\x1b[38;2;$i;0;0mX',
    ].join();

    test('sweeps the table of its own past the floor, the cells keeping '
        'their colors', () {
      TerminalEmulator.sweepFloor = 32;
      final t = TerminalEmulator(width: 10, height: 2, scrollbackLimit: 0);
      // a read at a time, as a program's output comes
      for (var i = 0; i < 200; i += 5) {
        t.feedText(reds(i, i + 5));
      }
      expect(t.styles.sweeps, greaterThan(0));
      expect(t.styles.length, lessThanOrEqualTo(96));
      // the last 20 written are what the screen shows
      for (var k = 0; k < 20; k++) {
        final id = t.styleAt(k % 10, k ~/ 10);
        expect(t.styles.fgOf(id), Color.rgb(180 + k, 0, 0), reason: '$k');
      }
    });

    test("leaves a table the host passed to the host's sweeps", () {
      TerminalEmulator.sweepFloor = 32;
      final canvas = canvasOf(10, 2);
      final t = TerminalEmulator(
        width: 10,
        height: 2,
        scrollbackLimit: 0,
        styles: canvas.styles,
      )..feedText(reds(0, 200));
      expect(t.styles.sweeps, 0);
    });

    test('paints the colors as they are, the screen keeping only those '
        'it shows', () {
      TerminalEmulator.sweepFloor = 32;
      Screen.sweepFloor = 32;
      final screen = Screen(10, 1);
      final t = TerminalEmulator(width: 10, height: 1, scrollbackLimit: 0);
      for (var i = 0; i < 2000; i += 10) {
        t
          ..feedText('\r${reds(i % 250, i % 250 + 10)}')
          ..paint(screen.canvas);
        screen.render();
        for (var x = 0; x < 10; x++) {
          expect(
            screen.styles.fgOf(screen.surface.styles[x]),
            Color.rgb(i % 250 + x, 0, 0),
            reason: 'frame $i, cell $x',
          );
        }
      }
      expect(screen.styles.sweeps, greaterThan(0));
      expect(screen.styles.length, lessThanOrEqualTo(96));
    });
  });
}
