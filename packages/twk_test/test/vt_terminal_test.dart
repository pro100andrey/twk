// The inline terminal backend: an app's frames written into the emulator's
// normal screen, below the lines printed before it, which are guarded.
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/vt_terminal.dart';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('the screen shows the history, and the app writes on the line after '
      'it', () {
    final term = VtTerminal(width: 20, height: 4, history: [r'$ app', 'ok']);
    expect((term.width, term.height), (20, 4));
    expect(term.info.cursorColumn, 0);
    term.write(bytes('hello'));
    expect(term.lines, [r'$ app', 'ok', 'hello', '']);
    expect(term.frames, [bytes('hello')]);
  });

  test('a history whose last line has no line break leaves the cursor after '
      'its text, on a line the app must leave', () {
    VtTerminal start() => VtTerminal(
      width: 20,
      height: 3,
      history: [r'$ app', 'name? '],
      atLineStart: false,
    );
    final term = start();
    expect(term.info.cursorColumn, 6);
    term.write(bytes('\r\nAda'));
    expect(term.lines, [r'$ app', 'name?', 'Ada']);
    expect(() => start().write(bytes('Ada')), throwsStateError);
  });

  test('writing over the history is an error', () {
    final term = VtTerminal(width: 20, height: 4, history: [r'$ app']);
    expect(() => term.write(bytes('\x1b[Ax')), throwsStateError);
    expect(term.vt.errors, ['a guarded row was changed']);
  });

  test('lines scrolled off the top of the screen are kept before it', () {
    final term = VtTerminal(width: 10, height: 2, history: ['one', 'two']);
    expect(term.lines, ['one', 'two', '']);
    term.write(bytes('three'));
    expect(term.lines, ['one', 'two', 'three']);
    expect(term.vt.history, hasLength(1));
  });

  test('what is typed arrives as key events', () async {
    final term = VtTerminal();
    final events = <InputEvent>[];
    final sub = term.events.listen(events.add);
    term.type('hi');
    await pumpEventQueue();
    expect([for (final e in events) (e as KeyEvent).char], ['h', 'i']);
    await sub.cancel();
    await term.close();
  });

  test('a resize keeps what the screen shows and is delivered as an '
      'event', () async {
    final term = VtTerminal(width: 10, height: 3, history: ['one']);
    final events = <InputEvent>[];
    final sub = term.events.listen(events.add);
    term
      ..write(bytes('abcdefgh'))
      ..resize(4, 3);
    await pumpEventQueue();
    expect((term.width, term.height), (4, 3));
    expect(term.lines, ['one', 'abcd', '']);
    expect(events, [const ResizeEvent(4, 3)]);
    await sub.cancel();
    await term.close();
  });

  test('once closed, it takes no more frames', () async {
    final term = VtTerminal(width: 10, height: 2);
    expect(term.closed, isFalse);
    term.write(bytes('a'));
    await term.flush();
    await term.close();
    term.write(bytes('b'));
    expect(term.closed, isTrue);
    expect(term.frames, hasLength(1));
    expect(term.lines.first, 'a');
  });

  test('the title is written to the frames, not shown; a notification is '
      'not written', () {
    final term = VtTerminal(width: 10, height: 2)
      ..setTitle('Editor')
      ..notify('Build', 'done');
    expect(term.frames, [bytes(titleSequence('Editor'))]);
    expect(term.lines, ['', '']);
  });
}
