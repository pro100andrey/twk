// Key specs and mouse reports as bytes, checked by what the core's parser
// makes of them.
import 'package:test/test.dart';
import 'package:twk/twk.dart' show KeyCombo;
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/src/keys.dart';

/// What the parser makes of the bytes of [spec], resolving a lone ESC as a
/// terminal does after a pause.
List<InputEvent> parse(String spec, {bool kitty = false}) {
  final parser = InputParser();
  return [
    for (final bytes in keyBytes(spec, kitty: kitty)) ...[
      ...parser.feed(bytes),
      ...parser.flush(),
    ],
  ];
}

KeyEvent char(String c, [int mods = 0]) =>
    KeyEvent(KeyCode.char, char: c, modifiers: mods);

KeyEvent key(KeyCode code, [int mods = 0]) => KeyEvent(code, modifiers: mods);

void main() {
  const ctrl = Mod.ctrl;
  const alt = Mod.alt;
  const shift = Mod.shift;

  group('without the kitty protocol, a key is', () {
    final cases = <String, List<InputEvent>>{
      'a': [char('a')],
      'я': [char('я')],
      'A': [char('A')],
      'shift+a': [char('A')],
      '+': [char('+')],
      'space': [char(' ')],
      'ctrl+s': [char('s', ctrl)],
      'ctrl+space': [char(' ', ctrl)],
      'ctrl+]': [char(']', ctrl)],
      'ctrl+i': [key(KeyCode.tab)],
      'alt+x': [char('x', alt)],
      'alt+X': [char('X', alt)],
      'ctrl+alt+x': [char('x', ctrl | alt)],
      'alt+[': [char('[', alt)],
      'enter': [key(KeyCode.enter)],
      'alt+enter': [key(KeyCode.enter, alt)],
      'tab': [key(KeyCode.tab)],
      'shift+tab': [key(KeyCode.tab, shift)],
      'alt+shift+tab': [key(KeyCode.tab, alt | shift)],
      'backspace': [key(KeyCode.backspace)],
      'ctrl+backspace': [key(KeyCode.backspace, ctrl)],
      'alt+backspace': [key(KeyCode.backspace, alt)],
      'escape': [key(KeyCode.escape)],
      'esc': [key(KeyCode.escape)],
      'alt+escape': [key(KeyCode.escape, alt)],
      'up': [key(KeyCode.up)],
      'ctrl+left': [key(KeyCode.left, ctrl)],
      'shift+alt+end': [key(KeyCode.end, shift | alt)],
      'home': [key(KeyCode.home)],
      'pageup': [key(KeyCode.pageUp)],
      'ctrl+pagedown': [key(KeyCode.pageDown, ctrl)],
      'insert': [key(KeyCode.insert)],
      'shift+delete': [key(KeyCode.delete, shift)],
      'f1': [key(KeyCode.f1)],
      'ctrl+f4': [key(KeyCode.f4, ctrl)],
      'f5': [key(KeyCode.f5)],
      'shift+f12': [key(KeyCode.f12, shift)],
      'g g': [char('g'), char('g')],
      'ctrl+x ctrl+s': [char('x', ctrl), char('s', ctrl)],
    };
    for (final MapEntry(key: spec, value: events) in cases.entries) {
      test('"$spec": $events', () => expect(parse(spec), events));
    }
  });

  group('with the kitty protocol, a key is', () {
    final cases = <String, List<InputEvent>>{
      'a': [char('a')],
      'shift+a': [char('A')],
      'ctrl+s': [char('s', ctrl)],
      'ctrl+shift+s': [char('s', ctrl | shift)],
      'ctrl+S': [char('s', ctrl | shift)],
      'ctrl+i': [char('i', ctrl)],
      'ctrl++': [char('+', ctrl)],
      'ctrl+1': [char('1', ctrl)],
      'alt+x': [char('x', alt)],
      'super+x': [char('x', Mod.superKey)],
      'ctrl+space': [char(' ', ctrl)],
      'escape': [key(KeyCode.escape)],
      'shift+escape': [key(KeyCode.escape, shift)],
      'enter': [key(KeyCode.enter)],
      'ctrl+enter': [key(KeyCode.enter, ctrl)],
      'shift+tab': [key(KeyCode.tab, shift)],
      'ctrl+backspace': [key(KeyCode.backspace, ctrl)],
      'super+up': [key(KeyCode.up, Mod.superKey)],
      'f2': [key(KeyCode.f2)],
    };
    for (final MapEntry(key: spec, value: events) in cases.entries) {
      test(
        '"$spec": $events',
        () => expect(parse(spec, kitty: true), events),
      );
    }
  });

  test('Escape is a lone ESC without the protocol, which the parser holds '
      'until a pause; with it, a sequence of its own', () {
    expect(keyBytes('escape', kitty: false), [
      [0x1B],
    ]);
    final parser = InputParser()..feed(keyBytes('escape', kitty: false)[0]);
    expect(parser.hasPending, isTrue);
    expect(keyBytes('escape', kitty: true), [
      '\x1b[27u'.codeUnits,
    ]);
  });

  test('a key xterm sends no bytes of its own for is an ArgumentError '
      'naming it as it is parsed', () {
    for (final spec in [
      'ctrl+S',
      'ctrl+shift+s',
      'alt+shift+1',
      'ctrl+enter',
      'shift+enter',
      'ctrl+escape',
      'super+x',
      'super+up',
      'ctrl+1',
      'ctrl++',
    ]) {
      expect(
        () => keyBytes(spec, kitty: false),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('"${KeyCombo.parse(spec)}" has no bytes'),
          ),
        ),
        reason: spec,
      );
    }
  });

  test('a spec that is not one is a FormatException saying why', () {
    final errors = {
      'cmd+s': '"cmd" in "cmd+s" is not a modifier',
      'Ctrl+s': '"Ctrl" in "Ctrl+s" is not a modifier',
      'ctrl+ctrl+s': '"ctrl" twice',
      'ctrl+Enter': '"Enter" in "ctrl+Enter" is neither one character',
      'ret': '"ret" in "ret" is neither one character nor a key',
      'g  g': 'keys apart by one space each',
      '': 'keys apart by one space each',
      'shift+1': 'Shift and "1" type another character',
    };
    for (final MapEntry(key: spec, value: message) in errors.entries) {
      expect(
        () => keyBytes(spec, kitty: false),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
        reason: spec,
      );
    }
  });

  group('a mouse report is', () {
    List<InputEvent> parse(List<int> bytes) => InputParser().feed(bytes);

    final cases = <MouseEvent>[
      const MouseEvent(MouseKind.down, 0, 0),
      const MouseEvent(MouseKind.down, 79, 23, button: 2),
      const MouseEvent(MouseKind.up, 5, 3, button: 1),
      const MouseEvent(MouseKind.drag, 6, 3),
      const MouseEvent(MouseKind.move, 7, 4),
      const MouseEvent(MouseKind.wheelUp, 1, 2),
      const MouseEvent(MouseKind.wheelDown, 1, 2, modifiers: Mod.ctrl),
      const MouseEvent(MouseKind.wheelLeft, 1, 2),
      const MouseEvent(MouseKind.wheelRight, 1, 2),
      const MouseEvent(MouseKind.down, 3, 3, button: 8),
      const MouseEvent(MouseKind.up, 3, 3, button: 11),
      const MouseEvent(
        MouseKind.down,
        2,
        2,
        modifiers: Mod.shift | Mod.alt | Mod.ctrl,
      ),
    ];
    for (final e in cases) {
      test(
        '$e',
        () => expect(
          parse(mouseBytes(e.kind, e.x, e.y, e.button, e.modifiers)),
          [e],
        ),
      );
    }

    test('an ArgumentError for a button or modifier it cannot have', () {
      expect(
        () => mouseBytes(MouseKind.down, 0, 0, 3, 0),
        throwsArgumentError,
      );
      expect(
        () => mouseBytes(MouseKind.down, 0, 0, 0, Mod.superKey),
        throwsArgumentError,
      );
    });
  });
}
