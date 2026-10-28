import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_web/src/link.dart';

import 'fake_xterm.dart';

/// A terminal over a link to [xterm]; DA1 unanswered would take a minute.
Future<Terminal> _open(FakeXterm xterm) => Terminal.overLink(
  XtermLink(xterm),
  const TerminalOptions(probeTimeout: Duration(minutes: 1)),
);

void main() {
  group('the probe', () {
    test('finds what xterm.js 6.0.0 answers', () async {
      final xterm = FakeXterm(columns: 107, rows: 27);
      final terminal = await _open(xterm);
      addTearDown(terminal.close);
      final info = terminal.info;
      expect(info.answeredQueries, isTrue);
      expect(info.caps.synchronizedOutput, isTrue);
      expect(info.graphemeMode, isFalse);
      expect(info.inBandResize, isFalse);
      expect(info.colorSchemeReports, isFalse);
      expect(info.caps.leftRightMargins, isFalse);
      expect(info.kittyKeyboard, isFalse);
      expect(info.foregroundRgb, 0xFFFFFF);
      expect(info.backgroundRgb, 0x000000);
      expect(info.brightness, Brightness.dark);
      expect(info.colorMode, ColorMode.trueColor);
      expect(info.caps.graphics, GraphicsProtocol.none);
      expect(info.ambiguousWidth, 1);
      expect((terminal.width, terminal.height), (107, 27));
    });

    test('is written to the terminal, and DA1 last', () async {
      final xterm = FakeXterm();
      final terminal = await _open(xterm);
      addTearDown(terminal.close);
      final probe = utf8.decode(xterm.writes.first);
      expect(probe, contains('\x1b[?2026\$p'));
      expect(probe, contains('\x1b]11;?\x1b\\'));
      expect(probe, endsWith('\x1b[c'));
    });
  });

  test('tells what the terminal is', () {
    final xterm = FakeXterm(columns: 90, rows: 30);
    final link = XtermLink(xterm);
    expect(link.environment, XtermLink.xtermEnvironment);
    expect(link.environment['COLORTERM'], 'truecolor');
    expect((link.columns, link.lines), (90, 30));
    expect(link.windows, isFalse);
    expect(link.eraseChar, 0x7F);
    final plain = XtermLink(xterm, environment: const {'TERM': 'xterm'});
    expect(plain.environment, {'TERM': 'xterm'});
  });

  group('input', () {
    test('is what the terminal sends, in UTF-8', () async {
      final xterm = FakeXterm();
      final terminal = await _open(xterm);
      addTearDown(terminal.close);
      final events = <InputEvent>[];
      terminal.events.listen(events.add);
      xterm
        ..send('é😀')
        ..send('\x7f')
        ..send('\x1b[I')
        ..send('\x1b[200~a\nb\x1b[201~');
      await pumpEventQueue();
      expect(events, [
        const KeyEvent(KeyCode.char, char: 'é'),
        const KeyEvent(KeyCode.char, char: '😀'),
        const KeyEvent(KeyCode.backspace),
        const FocusEvent(true),
        const PasteEvent('a\nb'),
      ]);
    });

    test('binary input is its bytes', () async {
      final xterm = FakeXterm();
      final link = XtermLink(xterm);
      final bytes = <int>[];
      final sub = link.input.listen(bytes.addAll);
      xterm.sendBinary('\x1b[M é!');
      await pumpEventQueue();
      expect(bytes, [0x1B, 0x5B, 0x4D, 0x20, 0xE9, 0x21]);
      await sub.cancel();
      await link.close();
    });
  });

  group('output', () {
    test('is written to the terminal as it is', () async {
      final xterm = FakeXterm();
      final link = XtermLink(xterm)
        ..add(utf8.encode('héllo'))
        ..add([0x1B, 0x5B, 0x6D]);
      expect(xterm.written, 'héllo\x1b[m');
      await link.close();
    });

    test('a flush waits for the callback of the last write', () async {
      final xterm = FakeXterm()..hold = true;
      final link = XtermLink(xterm)
        ..add([0x61])
        ..add([0x62]);
      var flushed = false;
      unawaited(link.flush().then((_) => flushed = true));
      await pumpEventQueue();
      expect(flushed, isFalse);
      xterm.release();
      await pumpEventQueue();
      expect(flushed, isTrue);
      await link.close();
    });

    test('a flush with nothing on its way completes at once', () async {
      final xterm = FakeXterm();
      final link = XtermLink(xterm)..add([0x61]);
      await pumpEventQueue();
      var flushed = false;
      unawaited(link.flush().then((_) => flushed = true));
      await Future<void>.value();
      expect(flushed, isTrue);
      await link.close();
    });

    test("the terminal's flush waits for its frame to be parsed", () async {
      final xterm = FakeXterm();
      final terminal = await _open(xterm);
      xterm.hold = true;
      terminal.write(utf8.encode('frame'));
      var flushed = false;
      unawaited(terminal.flush().then((_) => flushed = true));
      await pumpEventQueue();
      expect(flushed, isFalse);
      expect(xterm.written, endsWith('frame'));
      xterm
        ..hold = false
        ..release();
      await pumpEventQueue();
      expect(flushed, isTrue);
      await terminal.close();
    });

    test(
      'closing completes a pending flush and drops what comes after',
      () async {
        final xterm = FakeXterm()..hold = true;
        final link = XtermLink(xterm)..add([0x61]);
        final flushed = link.flush();
        await link.close();
        await flushed;
        link.add([0x62]);
        expect(xterm.written, 'a');
        await link.flush();
      },
    );
  });

  test("the terminal's resizes are reported", () async {
    final xterm = FakeXterm();
    final terminal = await _open(xterm);
    addTearDown(terminal.close);
    final events = <InputEvent>[];
    terminal.events.listen(events.add);
    xterm.resize(100, 30);
    await pumpEventQueue();
    expect(events, [const ResizeEvent(100, 30)]);
    expect((terminal.width, terminal.height), (100, 30));
  });

  test('closing the terminal removes its listeners', () async {
    final xterm = FakeXterm();
    final terminal = await _open(xterm);
    expect(xterm.listeners, 3);
    await terminal.close();
    expect(xterm.listeners, 0);
    expect(xterm.written, endsWith('\x1b[?1049l'));
  });
}
