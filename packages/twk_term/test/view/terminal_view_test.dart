// The view over a link of the test's own: what the "program" writes goes in
// when the test says, what the view sends it is read back.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show MouseTracking;
import 'package:twk_term/twk_term.dart';
import 'package:twk_test/twk_test.dart';

/// A session over a link: [write] is the program writing, [takeSent] what
/// it was sent, [sizes] the sizes it was told.
final class Link {
  Link(TwkTester t, {int width = 80, int height = 24}) {
    // in the app's zone: what it writes is fed as the clock runs
    session = t.clock.run(
      () => TerminalSession(
        output: _output.stream,
        input: _sent.addAll,
        onResize: (w, h) => sizes.add((w, h)),
        width: width,
        height: height,
      ),
    );
  }

  late final TerminalSession session;
  final _output = StreamController<List<int>>();
  final _sent = <int>[];
  final sizes = <(int, int)>[];

  /// [s] as the program writes it, `\e` standing for ESC.
  void write(String s) => _output.add(utf8.encode(s.replaceAll(r'\e', '\x1b')));

  /// What the program was sent so far, ESC as `\e`; cleared.
  String takeSent() {
    final s = utf8.decode(_sent).replaceAll('\x1b', r'\e');
    _sent.clear();
    return s;
  }

  Future<void> end() => _output.close();
}

/// The rows the last paint of the view painted, as its render object tells.
int rowsPainted(TwkTester t) {
  final description = t
      .renderObject<RenderObject>(find.byType(TerminalView))
      .describe()
      .toStringDeep();
  return int.parse(
    RegExp(r'rows painted: (\d+)').firstMatch(description)!.group(1)!,
  );
}

/// [child] three render objects deeper: a frame paints it after the
/// repaint boundaries above that depth.
Widget deeper(Widget child) => Padding(
  padding: EdgeInsets.zero,
  child: Padding(
    padding: EdgeInsets.zero,
    child: Padding(padding: EdgeInsets.zero, child: child),
  ),
);

/// What frame [frame] wrote, ESC as `\e`.
String bytesOf(RecordedFrame frame) =>
    utf8.decode(frame.bytes, allowMalformed: true).replaceAll('\x1b', r'\e');

void main() {
  group('the screen', () {
    testTwk('shows what the program writes, in its styles', (t) async {
      final link = Link(t);
      await t.pumpWidget(TerminalView(session: link.session), size: (20, 4));
      link.write(
        r'hello \e[1;31mred\e[0m'
        '\r\n'
        r'\e[4mx',
      );
      await t.pump();
      expect(t, matchesScreen('hello red\nx'));
      expect(t, styleAt(6, 0, hasFg(Color.red)));
      expect(t, styleAt(6, 0, hasAttr(Attr.bold)));
      expect(t, styleAt(0, 1, hasAttr(Attr.underline)));
    });

    testTwk("the terminal is the view's size, told to the program", (t) async {
      final link = Link(t);
      await t.pumpWidget(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 5, child: Text('side')),
            Expanded(child: TerminalView(session: link.session)),
          ],
        ),
        size: (25, 6),
      );
      expect(link.sizes, [(20, 6)]);
      expect(
        (link.session.emulator.width, link.session.emulator.height),
        (20, 6),
      );
      link.write('${'x' * 21}y');
      await t.pump();
      expect(t.lines.take(2), ['side ${'x' * 20}', '     xy']);
      await t.resize(30, 4);
      await t.pump();
      expect(link.sizes.last, (25, 4));
    });

    testTwk('repaints the rows that changed alone', (t) async {
      final link = Link(t);
      await t.pumpWidget(
        TerminalView(session: link.session, autofocus: true),
        size: (10, 5),
      );
      link.write('a\r\nb\r\nc\r\nd');
      await t.pump();
      expect(rowsPainted(t), 4, reason: 'the last row is still blank');
      link.write(r'\e[2;1Hx');
      await t.pump();
      expect(t, matchesScreen('a\nx\nc\nd'));
      expect(rowsPainted(t), 1);
      // the cursor moved alone: a paint, no row
      link.write(r'\e[5;5H');
      await t.pump();
      expect(rowsPainted(t), 0);
      expect(t, cursorAt(4, 4));
    });

    testTwk('rows the program scrolls move in hardware, the new one painted', (
      t,
    ) async {
      final link = Link(t);
      await t.pumpWidget(TerminalView(session: link.session), size: (10, 4));
      link.write('1\r\n2\r\n3\r\n4');
      await t.pump();
      link.write('\r\n5');
      await t.pump();
      expect(t, matchesScreen('2\n3\n4\n5'));
      expect(rowsPainted(t), 1);
      expect(bytesOf(t.frames.last), contains(r'\e[1;4r\e[S'));
      // a status line kept below the margins
      link.write(
        r'\e[4;1Hstatus\e[1;3r\e[3;1H'
        '\nsix',
      );
      await t.pump();
      expect(t, matchesScreen('3\n4\nsix\nstatus'));
      expect(bytesOf(t.frames.last), contains(r'\e[1;3r\e[S'));
      expect(rowsPainted(t), 2);
    });

    testTwk('while the program draws a frame, the one before shows', (
      t,
    ) async {
      final link = Link(t);
      await t.pumpWidget(TerminalView(session: link.session), size: (10, 2));
      link.write('old');
      await t.pump();
      link.write(r'\e[?2026h\e[2J\e[Hnew');
      await t.pump();
      expect(t, matchesScreen('old'));
      link.write(r'\e[?2026l');
      await t.pump();
      expect(t, matchesScreen('new'));
      // a frame that isn't ended shows after a while
      link.write(r'\e[?2026h\e[Hnow');
      await t.pump(const Duration(milliseconds: 100));
      expect(t, matchesScreen('new'));
      await t.pump(const Duration(milliseconds: 100));
      expect(t, matchesScreen('now'));
    });
  });

  group('the scrollback', () {
    Future<Link> filled(TwkTester t) async {
      final link = Link(t);
      await t.pumpWidget(
        TerminalView(session: link.session, autofocus: true),
        size: (10, 4),
      );
      link.write([for (var i = 1; i <= 12; i++) 'line $i'].join('\r\n'));
      await t.pump();
      return link;
    }

    testTwk('the wheel scrolls through it, a key brings the screen back', (
      t,
    ) async {
      final link = await filled(t);
      expect(t.lines.first, 'line 9');
      await t.mouse(MouseKind.wheelUp, 0, 0);
      await t.pump();
      expect(t.lines, ['line 6', 'line 7', 'line 8', 'line 9']);
      expect(bytesOf(t.frames.last), contains(r'\e[1;4r\e[3T'));
      expect(rowsPainted(t), 3);
      expect(t.cursorVisible, isFalse, reason: 'the cursor is off the view');
      await t.mouse(MouseKind.wheelUp, 0, 0);
      await t.mouse(MouseKind.wheelUp, 0, 0);
      await t.mouse(MouseKind.wheelUp, 0, 0);
      await t.pump();
      expect(t.lines.first, 'line 1', reason: 'as far as it goes');
      await t.mouse(MouseKind.wheelDown, 0, 0);
      await t.pump();
      expect(t.lines.first, 'line 4');
      // output while scrolled back leaves the lines in place
      link.write('\r\nline 13\r\nline 14');
      await t.pump();
      expect(t.lines.first, 'line 4');
      await t.type('x');
      await t.pump();
      expect(t.lines, ['line 11', 'line 12', 'line 13', 'line 14']);
      expect(link.takeSent(), 'x');
    });

    testTwk('on the alternate screen the wheel sends Up and Down', (t) async {
      final link = await filled(t);
      link.write(r'\e[?1049h');
      await t.pump();
      await t.mouse(MouseKind.wheelDown, 0, 0);
      await t.mouse(MouseKind.wheelUp, 0, 0);
      expect(link.takeSent(), r'\e[B\e[B\e[B\e[A\e[A\e[A');
      link.write(r'\e[?1h');
      await t.pump();
      await t.mouse(MouseKind.wheelUp, 0, 0);
      expect(link.takeSent(), r'\eOA\eOA\eOA');
    });
  });

  group('input', () {
    testTwk("keys go in the program's modes, Tab and Ctrl+C among them", (
      t,
    ) async {
      final link = Link(t);
      await t.pumpWidget(
        Column(
          children: [
            Expanded(
              child: TerminalView(session: link.session, autofocus: true),
            ),
            Button('other', onPressed: () {}),
          ],
        ),
        size: (10, 4),
      );
      await t.press('up tab ctrl+c');
      await t.type('é');
      expect(link.takeSent(), '\\e[A\t\x03é');
      expect(t.isRunning, isTrue);
      link.write(r'\e[?1h');
      await t.pump();
      await t.press('up home');
      expect(link.takeSent(), r'\eOA\eOH');
      // the kitty keyboard protocol, once the program pushed its flags
      link.write(r'\e[>1u');
      await t.pump();
      await t.press('escape ctrl+a enter');
      expect(link.takeSent(), '\\e[27u\\e[97;5u\r');
      link.write(r'\e[<u');
      await t.pump();
      await t.press('escape');
      expect(link.takeSent(), r'\e');
    });

    testTwk('ignored keys go up to the nodes above', (t) async {
      final link = Link(t);
      var quits = 0;
      await t.pumpWidget(
        KeyBindings(
          {'ctrl+q': () => quits++},
          child: TerminalView(
            session: link.session,
            autofocus: true,
            ignoredKeys: const ['ctrl+q'],
          ),
        ),
        size: (10, 2),
      );
      await t.press('ctrl+q ctrl+w');
      expect(quits, 1);
      expect(link.takeSent(), '\x17');
    });

    testTwk('a paste goes as typed, bracketed when the program asked', (
      t,
    ) async {
      final link = Link(t);
      await t.pumpWidget(
        TerminalView(session: link.session, autofocus: true),
        size: (10, 2),
      );
      await t.paste('a\nb');
      expect(link.takeSent(), 'a\rb');
      link.write(r'\e[?2004h');
      await t.pump();
      await t.paste('a\nb');
      expect(
        link.takeSent(),
        r'\e[200~a'
        '\r'
        r'b\e[201~',
      );
    });

    testTwk("the mouse is the program's while it tracks it", (t) async {
      final link = Link(t);
      await t.pumpWidget(
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 1),
          child: TerminalView(session: link.session),
        ),
        size: (12, 5),
      );
      await t.click(4, 2);
      expect(link.takeSent(), '', reason: 'untracked');
      link.write(r'\e[?1000h\e[?1006h');
      await t.pump();
      await t.click(4, 2);
      await t.mouse(MouseKind.wheelDown, 3, 1);
      expect(link.takeSent(), r'\e[<0;3;2M\e[<0;3;2m\e[<65;2;1M');
      // motion only once the program asks for it, from the app's terminal
      // too
      expect(t.terminal.mouseTracking, MouseTracking.buttons);
      await t.mouse(MouseKind.move, 5, 3);
      expect(link.takeSent(), '');
      link.write(r'\e[?1002h');
      await t.pump();
      expect(t.terminal.mouseTracking, MouseTracking.drags);
      link.write(r'\e[?1003h');
      await t.pump();
      expect(t.terminal.mouseTracking, MouseTracking.motion);
      await t.mouse(MouseKind.move, 5, 3);
      expect(link.takeSent(), r'\e[<35;4;3M');
      link.write(r'\e[?1003l');
      await t.pump();
      expect(t.terminal.mouseTracking, MouseTracking.buttons);
      await t.mouse(MouseKind.wheelUp, 3, 1);
      expect(link.takeSent(), '', reason: 'the scrollback again');
    });

    testTwk('the program hears of the focus when it asked', (t) async {
      final left = Link(t);
      final right = Link(t);
      await t.pumpWidget(
        Row(
          children: [
            Expanded(
              child: TerminalView(session: left.session, autofocus: true),
            ),
            Expanded(child: TerminalView(session: right.session)),
          ],
        ),
        size: (20, 3),
      );
      left.write(r'\e[?1004h');
      right.write(r'\e[?1004h');
      await t.pump();
      await t.click(15, 1);
      await t.pump();
      expect(left.takeSent(), r'\e[O');
      expect(right.takeSent(), r'\e[I');
      // the app's terminal lost the focus, and got it back
      await t.input('\x1b[O'.codeUnits);
      await t.input('\x1b[I'.codeUnits);
      expect(right.takeSent(), r'\e[O\e[I');
      expect(left.takeSent(), '');
      await t.type('k');
      expect(right.takeSent(), 'k');
    });
  });

  group('the cursor', () {
    testTwk("shows the program's while the view has the focus", (t) async {
      final link = Link(t);
      final node = FocusNode();
      addTearDown(node.dispose);
      await t.pumpWidget(
        Column(
          children: [
            const Text('top'),
            Expanded(
              child: TerminalView(session: link.session, focusNode: node),
            ),
          ],
        ),
        size: (10, 4),
      );
      link.write('ab');
      await t.pump();
      expect(t.cursorVisible, isFalse);
      node.requestFocus();
      await t.pump();
      expect(t, cursorAt(2, 1));
      link.write(r'\e[?25l');
      await t.pump();
      expect(t.cursorVisible, isFalse);
      link.write(r'\e[?25h\e[3;2H');
      await t.pump();
      expect(t, cursorAt(1, 3));
      node.unfocus();
      await t.pump();
      expect(t.cursorVisible, isFalse);
    });

    for (final fieldLast in [true, false]) {
      final last = fieldLast ? 'the field' : 'the view';
      testTwk('the focus moving from a field to the view and back within a '
          'frame leaves it at the focused one, in its shape, $last painting '
          'last', (t) async {
        final link = Link(t);
        final fieldNode = FocusNode();
        final viewNode = FocusNode();
        addTearDown(fieldNode.dispose);
        addTearDown(viewNode.dispose);
        final c = TextEditingController(text: 'abc');
        addTearDown(c.dispose);
        final field = SizedBox(
          width: 10,
          child: TextField(controller: c, focusNode: fieldNode),
        );
        final view = TerminalView(session: link.session, focusNode: viewNode);
        // later in the column and deeper: painted after the other
        await t.pumpWidget(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: fieldLast
                ? [Expanded(child: view), deeper(field)]
                : [field, Expanded(child: deeper(view))],
          ),
          size: (10, 4),
        );
        final fieldRow = fieldLast ? 3 : 0;
        final viewRow = fieldLast ? 0 : 1;
        // a steady block
        link.write(r'xy\e[2 q');
        fieldNode.requestFocus();
        await t.pump();
        expect(t, cursorAt(3, fieldRow));
        expect(t.vt.cursorShape, CursorShape.bar.code);

        var frames = t.frames.length;
        viewNode.requestFocus();
        await t.pump();
        expect(t.frames, hasLength(frames + 1));
        expect(t, cursorAt(2, viewRow));
        expect(t.vt.cursorShape, CursorShape.block.code);

        frames = t.frames.length;
        fieldNode.requestFocus();
        await t.pump();
        expect(t.frames, hasLength(frames + 1));
        expect(t, cursorAt(3, fieldRow));
        expect(t.vt.cursorShape, CursorShape.bar.code);

        fieldNode.unfocus();
        await t.pump();
        expect(t.cursorVisible, isFalse);
      });
    }

    testTwk("the program's default shape is the host terminal's own", (
      t,
    ) async {
      final link = Link(t);
      await t.pumpWidget(
        TerminalView(session: link.session, autofocus: true),
        size: (10, 2),
      );
      link.write(r'\e[6 q');
      await t.pump();
      expect(t.vt.cursorShape, CursorShape.bar.code);
      // DECSCUSR 0: the host is asked for its own, whatever its user set,
      // not for a block
      link.write(r'\e[0 q');
      await t.pump();
      expect(t.vt.cursorShape, CursorShape.terminalDefault.code);
      expect(t.cursorVisible, isTrue);
    });
  });

  group('the default colors', () {
    const dark = ThemeData.dark;
    final text = dark.text.fg!;
    final back = dark.background.bg!;

    testTwk("are the theme's text on its background", (t) async {
      final link = Link(t);
      await t.pumpWidget(
        Theme(
          data: dark,
          child: TerminalView(session: link.session),
        ),
        size: (6, 2),
      );
      link.write(r'a\e[31mb\e[44mc\e[0;7md');
      await t.pump();
      expect(t, styleAt(0, 0, allOf(hasFg(text), hasBg(back))));
      expect(t, styleAt(1, 0, allOf(hasFg(Color.red), hasBg(back))));
      expect(t, styleAt(2, 0, allOf(hasFg(Color.red), hasBg(Color.blue))));
      expect(
        t,
        styleAt(3, 0, allOf(hasFg(text), hasBg(back), hasAttr(Attr.reverse))),
      );
      expect(t, styleAt(5, 1, hasBg(back)), reason: 'a blank cell');
    });

    testTwk('are those of defaultStyle, the theme where it sets none', (
      t,
    ) async {
      final link = Link(t);
      Widget view(Style? style) => Theme(
        data: dark,
        child: TerminalView(session: link.session, defaultStyle: style),
      );
      await t.pumpWidget(view(null), size: (6, 2));
      link.write('a');
      await t.pump();
      const other = Color.rgb(9, 9, 9);
      await t.pumpWidget(view(const Style(bg: other)), size: (6, 2));
      expect(rowsPainted(t), 2, reason: 'every row painted again');
      expect(t, styleAt(0, 0, allOf(hasFg(text), hasBg(other))));
      expect(t, styleAt(5, 1, hasBg(other)));
      await t.pumpWidget(
        view(const Style(fg: Color.defaultColor, bg: Color.defaultColor)),
        size: (6, 2),
      );
      expect(
        t,
        styleAt(
          0,
          0,
          allOf(hasFg(Color.defaultColor), hasBg(Color.defaultColor)),
        ),
        reason: "the host terminal's own",
      );
    });

    testTwk('are what the program is told when it asks for them', (t) async {
      final link = Link(t);
      String spec(int rgb) => [
        for (final shift in [16, 8, 0])
          ((rgb >> shift & 0xFF) * 257).toRadixString(16).padLeft(4, '0'),
      ].join('/');
      int rgbOf(Color c) => c.value & 0xFFFFFF;
      const light = ThemeData.light;
      Widget view(Style? style) => Theme(
        data: light,
        child: TerminalView(session: link.session, defaultStyle: style),
      );
      const ask = r'\e]10;?\e\\e]11;?\e\\e[?996n';
      await t.pumpWidget(view(null), size: (6, 2));
      link.write(ask);
      await t.pump();
      expect(
        link.takeSent(),
        '\\e]10;rgb:${spec(rgbOf(light.text.fg!))}\\e\\'
        '\\e]11;rgb:${spec(rgbOf(light.background.bg!))}\\e\\'
        r'\e[?997;2n',
        reason: 'light',
      );
      // a palette color as the palette has it
      await t.pumpWidget(
        view(const Style(fg: Color.red, bg: Color.rgb(0, 0, 0x20))),
        size: (6, 2),
      );
      link.write(ask);
      await t.pump();
      expect(
        link.takeSent(),
        r'\e]10;rgb:cdcd/0000/0000\e\'
        r'\e]11;rgb:0000/0000/2020\e\'
        r'\e[?997;1n',
      );
    });
  });

  group('the program asks', () {
    testTwk('for a title, the bell and the clipboard: the callbacks are told', (
      t,
    ) async {
      final link = Link(t);
      final told = <String>[];
      await t.pumpWidget(
        TerminalView(
          session: link.session,
          onTitleChanged: (title) => told.add('title $title'),
          onBell: () => told.add('bell'),
          onClipboardWrite: (selection, text) =>
              told.add('copy $selection $text'),
          onClipboardRead: (selection) => Future.value('from $selection'),
          onEvent: (event) => told.add('$event'),
        ),
        size: (10, 2),
      );
      link.write(
        r'\e]2;hello'
        '\x07\x07'
        r'\e]52;c;aGk='
        '\x07'
        r'\e]52;p;?\e\',
      );
      await t.pump();
      expect(told, [
        'TitleChanged(hello)',
        'title hello',
        'BellRang()',
        'bell',
        'ClipboardWrite(c, 2 chars)',
        'copy c hi',
        'ClipboardRead(p)',
      ]);
      expect(
        link.takeSent(),
        '\\e]52;p;${base64.encode(utf8.encode('from p'))}\\e\\',
      );
      expect(link.session.title, 'hello');
    });

    testTwk('the end of the output ends the session', (t) async {
      final link = Link(t);
      await t.pumpWidget(TerminalView(session: link.session), size: (10, 2));
      expect(link.session.ended, isFalse);
      await link.end();
      await t.pump();
      expect(link.session.ended, isTrue);
      int? code = -1;
      unawaited(link.session.exitCode.then((c) => code = c));
      await t.pump();
      expect(code, isNull);
    });

    testTwk("a program started late starts at the view's size", (t) async {
      final session = t.clock.run(
        () => TerminalSession.start('no-such-program-here', const []),
      );
      addTearDown(session.dispose);
      expect(session.pty, isNull);
      await t.pumpWidget(TerminalView(session: session), size: (30, 5));
      expect(
        (session.emulator.width, session.emulator.height),
        (30, 5),
      );
      expect(session.error, isA<ProcessException>());
      expect(session.ended, isTrue);
      expect(
        t.logs.records.last.message,
        'the terminal could not start its program',
      );
    });
  });
}
