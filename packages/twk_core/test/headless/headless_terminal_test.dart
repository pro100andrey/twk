// The in-memory terminal: input decoded by the real parser, the pauses a
// real terminal waits out left to the caller, frames kept as written,
// notifications in the protocol chosen, the terminal handed over and taken
// back.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

void main() {
  late HeadlessTerminal term;
  late List<InputEvent> got;

  void open({
    bool kittyKeyboard = false,
    TerminalOptions options = const TerminalOptions(),
  }) {
    term = HeadlessTerminal(
      width: 20,
      height: 4,
      kittyKeyboard: kittyKeyboard,
      options: options,
    );
    got = [];
    term.events.listen(got.add);
  }

  /// What the input so far was decoded into.
  Future<List<InputEvent>> events() async {
    await pumpEventQueue();
    final out = [...got];
    got.clear();
    return out;
  }

  test('describes the terminal the caller chose', () {
    final t = HeadlessTerminal(
      width: 30,
      height: 5,
      caps: const TerminalCaps(synchronizedOutput: false),
      textMode: TextMode.legacy,
      ambiguousWidth: 2,
      colorMode: ColorMode.ansi256,
      foregroundRgb: 0xEEEEEE,
      backgroundRgb: 0x111111,
      kittyKeyboard: true,
    );
    final info = t.info;
    expect((t.width, t.height), (30, 5));
    expect(info.caps.synchronizedOutput, isFalse);
    expect(info.textMode, TextMode.legacy);
    expect(info.ambiguousWidth, 2);
    expect(info.colorMode, ColorMode.ansi256);
    expect((info.foregroundRgb, info.backgroundRgb), (0xEEEEEE, 0x111111));
    expect(info.kittyKeyboard, isTrue);
    expect(info.alternateScreen, isTrue);
    expect(info.cursorColumn, isNull, reason: 'asked inline only');
  });

  test('in the inline mode describes where the cursor starts', () {
    const inline = TerminalOptions(alternateScreen: false);
    final info = HeadlessTerminal(options: inline).info;
    expect(info.alternateScreen, isFalse);
    expect(info.cursorColumn, 0);
    expect(
      HeadlessTerminal(options: inline, cursorColumn: 7).info.cursorColumn,
      7,
    );
  });

  test('input is decoded by the parser, split anywhere', () async {
    open();
    term
      ..input([0x1B, 0x5B])
      ..input([0x41, 0xD0])
      ..input([0xBF])
      ..type('ok\r');
    expect(await events(), [
      const KeyEvent(KeyCode.up),
      const KeyEvent(KeyCode.char, char: 'п'),
      const KeyEvent(KeyCode.char, char: 'o'),
      const KeyEvent(KeyCode.char, char: 'k'),
      const KeyEvent(KeyCode.enter),
    ]);
  });

  test('a lone ESC is the Escape key once its pause is timed out', () async {
    open();
    expect(term.inputTimeout, isNull);
    term.type('\x1b');
    expect(await events(), isEmpty);
    expect(term.inputTimeout, const Duration(milliseconds: 30));
    term.timeOutInput();
    expect(await events(), [const KeyEvent(KeyCode.escape)]);
    expect(term.inputTimeout, isNull);
    term.timeOutInput();
    expect(await events(), isEmpty, reason: 'nothing was waiting');
  });

  test('the escape pause is the one the options give', () {
    open(
      options: const TerminalOptions(escapeTimeout: Duration(milliseconds: 5)),
    );
    term.type('\x1b[');
    expect(term.inputTimeout, const Duration(milliseconds: 5));
  });

  test('a sequence whose parameters came waits the long pause', () async {
    open();
    term.type('\x1b[1;');
    expect(term.inputTimeout, const Duration(milliseconds: 500));
    term.type('5A');
    expect(await events(), [const KeyEvent(KeyCode.up, modifiers: Mod.ctrl)]);
    expect(term.inputTimeout, isNull);
  });

  test('with the kitty protocol even a lone ESC waits long', () {
    open(kittyKeyboard: true);
    term.type('\x1b');
    expect(term.inputTimeout, const Duration(milliseconds: 500));
  });

  test('a paste whose end marker was lost ends when timed out', () async {
    open();
    term.type('\x1b[200~one\x1b');
    expect(await events(), isEmpty);
    expect(term.inputTimeout, const Duration(seconds: 2));
    term.timeOutInput();
    expect(await events(), [const PasteEvent('one\x1b')]);
    expect(term.inputTimeout, isNull);
  });

  test('a resize changes the size and is reported once', () async {
    open();
    term
      ..resize(30, 5)
      ..resize(30, 5);
    expect((term.width, term.height), (30, 5));
    expect(await events(), [const ResizeEvent(30, 5)]);
  });

  test('an in-band resize report changes the size', () async {
    open();
    term.type('\x1b[48;6;40;0;0t');
    expect(await events(), [const ResizeEvent(40, 6)]);
    expect((term.width, term.height), (40, 6));
  });

  test('frames are kept as written', () {
    open();
    final buf = Uint8List.fromList([1, 2, 3]);
    term.write(buf);
    buf[0] = 9;
    term.write(Uint8List.fromList([4]));
    expect(term.frames, [
      [1, 2, 3],
      [4],
    ]);
  });

  test('a notification is written in the protocol chosen, through the '
      'multiplexer, each under an id of its own', () {
    String sent(HeadlessTerminal t) =>
        utf8.decode([for (final f in t.frames) ...f]);

    final kitty = HeadlessTerminal(
      notifications: NotificationProtocol.osc99,
      multiplexer: Multiplexer.tmux,
    );
    expect(kitty.info.notifications, NotificationProtocol.osc99);
    kitty
      ..notify('Build', 'done')
      ..notify('Build', 'failed');
    expect(
      sent(kitty),
      '\x1bPtmux;\x1b\x1b]99;i=1:d=0;Build\x1b\x1b\\'
      '\x1b\x1b]99;i=1:p=body;done\x1b\x1b\\\x1b\\'
      '\x1bPtmux;\x1b\x1b]99;i=2:d=0;Build\x1b\x1b\\'
      '\x1b\x1b]99;i=2:p=body;failed\x1b\x1b\\\x1b\\',
    );

    final foot = HeadlessTerminal(notifications: NotificationProtocol.osc777)
      ..notify('Build', 'done; 3 tests');
    expect(sent(foot), '\x1b]777;notify;Build;done, 3 tests\x1b\\');
  });

  test('the bell is rung only while a focus report typed last said the '
      'window lost the focus', () {
    String sent(HeadlessTerminal t) =>
        utf8.decode([for (final f in t.frames) ...f]);
    final t = HeadlessTerminal(notifications: NotificationProtocol.bell)
      ..notify('Build', 'done');
    expect(t.frames, isEmpty);
    t
      ..type('\x1b[O')
      ..notify('Build', 'done');
    expect(sent(t), '\x07');
    t
      ..type('\x1b[I')
      ..notify('Build', 'done');
    expect(sent(t), '\x07');
  });

  test('a notification is not written where none is known to show, nor '
      'once closed', () async {
    open();
    expect(term.info.notifications, NotificationProtocol.none);
    term.notify('Build', 'done');
    expect(term.frames, isEmpty);

    final t = HeadlessTerminal(notifications: NotificationProtocol.osc9);
    await t.close();
    t.notify('Build', 'done');
    expect(t.frames, isEmpty);
  });

  test('a flush waits for a held connection', () async {
    open();
    final hold = Completer<void>();
    term.holdFlush = hold.future;
    var flushed = false;
    unawaited(term.flush().then((_) => flushed = true));
    await pumpEventQueue();
    expect(flushed, isFalse);
    hold.complete();
    await pumpEventQueue();
    expect(flushed, isTrue);
    expect(term.flushes, 1);
  });

  test("handed over, input is the other program's: it is dropped until "
      'the terminal is taken back', () async {
    open();
    expect(term, isA<SuspendableBackend>());
    expect((term.suspended, term.suspends), (false, 0));
    await term.suspend();
    expect((term.suspended, term.suspends), (true, 1));
    term
      ..type('x')
      ..resize(30, 5);
    expect(await events(), [const ResizeEvent(30, 5)]);
    await term.resume();
    expect((term.suspended, term.suspends), (false, 1));
    term.type('y');
    expect(await events(), [const KeyEvent(KeyCode.char, char: 'y')]);
    expect(term.frames, isEmpty);
  });

  test('handing over twice, taking back what was not handed over, or '
      'handing over once closed does nothing', () async {
    open(options: const TerminalOptions(alternateScreen: false));
    term.resumeColumn = 5;
    await term.resume();
    expect(term.suspended, isFalse);
    expect(term.frames, isEmpty);
    await term.suspend();
    await term.suspend();
    expect(term.suspends, 1);
    await term.resume();
    await term.close();
    await term.suspend();
    expect((term.suspended, term.suspends), (false, 1));
  });

  test('taken back in the inline mode, the cursor goes to the start of the '
      'next line unless the other program left it at the start of '
      'one', () async {
    open(options: const TerminalOptions(alternateScreen: false));
    await term.suspend();
    await term.resume();
    expect(term.frames, isEmpty);
    term.resumeColumn = 5;
    await term.suspend();
    await term.resume();
    expect(term.frames, [
      [0x0D, 0x0A],
    ]);
  });

  test('taken back on the alternate screen, nothing is written wherever '
      'the cursor is', () async {
    open();
    term.resumeColumn = 5;
    await term.suspend();
    await term.resume();
    expect(term.frames, isEmpty);
  });

  test('close ends the events and drops later frames', () async {
    var ended = false;
    final t = HeadlessTerminal();
    t.events.listen(null, onDone: () => ended = true);
    await t.close();
    await t.close();
    expect(t.closed, isTrue);
    expect(ended, isTrue);
    t.write(Uint8List.fromList([1]));
    expect(t.frames, isEmpty);
  });

  test('input and a resize once closed are dropped', () async {
    final t = HeadlessTerminal();
    await t.close();
    t
      ..type('x')
      ..resize(100, 30);
    expect(t.width, 80);
  });

  test('close completes with nobody listening', () async {
    await HeadlessTerminal().close();
  });

  test('a title is written as the sequence that sets it, pushing none; '
      'nothing once closed', () async {
    final t = HeadlessTerminal()..setTitle('Editor');
    expect(t.frames, [utf8.encode(titleSequence('Editor'))]);
    await t.close();
    t.setTitle('Other');
    expect(t.frames, hasLength(1));
  });
}
