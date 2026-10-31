// Key specs: the grammar KeyCombo.parse reads, the typos it names, the key
// events a combo accepts, and the keys a terminal without the kitty
// keyboard protocol does not tell apart.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

KeyEvent char(String c, [int mods = 0]) =>
    KeyEvent(KeyCode.char, char: c, modifiers: mods);

void main() {
  const ctrl = Mod.ctrl;
  const alt = Mod.alt;
  const shift = Mod.shift;

  group('a spec is the combo', () {
    final cases = <String, KeyCombo>{
      'a': KeyCombo.char('a'),
      'я': KeyCombo.char('я'),
      '?': KeyCombo.char('?'),
      '+': KeyCombo.char('+'),
      'A': KeyCombo.char('a', modifiers: shift),
      'shift+a': KeyCombo.char('a', modifiers: shift),
      'shift+A': KeyCombo.char('a', modifiers: shift),
      'Я': KeyCombo.char('я', modifiers: shift),
      'ctrl+s': KeyCombo.char('s', modifiers: ctrl),
      'ctrl+S': KeyCombo.char('s', modifiers: ctrl | shift),
      'shift+ctrl+s': KeyCombo.char('s', modifiers: ctrl | shift),
      'ctrl++': KeyCombo.char('+', modifiers: ctrl),
      'ctrl+alt+x': KeyCombo.char('x', modifiers: ctrl | alt),
      'super+x': KeyCombo.char('x', modifiers: Mod.superKey),
      'space': KeyCombo.char(' '),
      'ctrl+space': KeyCombo.char(' ', modifiers: ctrl),
      'ctrl+shift+1': KeyCombo.char('1', modifiers: ctrl | shift),
      'enter': const KeyCombo(KeyCode.enter),
      'shift+tab': const KeyCombo(KeyCode.tab, modifiers: shift),
      'escape': const KeyCombo(KeyCode.escape),
      // the name the hints show it by
      'esc': const KeyCombo(KeyCode.escape),
      'shift+esc': const KeyCombo(KeyCode.escape, modifiers: shift),
      'backspace': const KeyCombo(KeyCode.backspace),
      'pageup': const KeyCombo(KeyCode.pageUp),
      'ctrl+pagedown': const KeyCombo(KeyCode.pageDown, modifiers: ctrl),
      'shift+alt+end': const KeyCombo(KeyCode.end, modifiers: alt | shift),
      'super+up': const KeyCombo(KeyCode.up, modifiers: Mod.superKey),
      'f12': const KeyCombo(KeyCode.f12),
    };
    for (final MapEntry(key: spec, value: combo) in cases.entries) {
      test('"$spec": $combo', () => expect(KeyCombo.parse(spec), combo));
    }
  });

  test('a combo is written as it is parsed: the modifiers in the order '
      'ctrl, alt, shift, super, Shift and a letter as the capital', () {
    final written = {
      'a': 'a',
      'shift+a': 'A',
      'ctrl+shift+a': 'ctrl+A',
      'shift+alt+ctrl+super+end': 'ctrl+alt+shift+super+end',
      'ctrl++': 'ctrl++',
      'space': 'space',
      'pagedown': 'pagedown',
      'alt+f4': 'alt+f4',
      'esc': 'escape',
    };
    for (final MapEntry(key: spec, value: text) in written.entries) {
      final combo = KeyCombo.parse(spec);
      expect('$combo', text, reason: spec);
      expect(KeyCombo.parse('$combo'), combo, reason: spec);
    }
  });

  test('keys pressed one after another are apart by one space', () {
    expect(KeyCombo.parseSequence('ctrl+x ctrl+s'), [
      KeyCombo.char('x', modifiers: ctrl),
      KeyCombo.char('s', modifiers: ctrl),
    ]);
    expect(KeyCombo.parseSequence('g g'), [
      KeyCombo.char('g'),
      KeyCombo.char('g'),
    ]);
    expect(KeyCombo.parseSequence('+ space'), [
      KeyCombo.char('+'),
      KeyCombo.char(' '),
    ]);
  });

  test('a spec that is not one is a FormatException naming the part that '
      'is wrong, and the name meant where it can tell', () {
    final errors = {
      'cmd+s':
          '"cmd" in "cmd+s" is not a modifier: ctrl, alt, shift or '
          'super; "super" is meant?',
      'Ctrl+s':
          '"Ctrl" in "Ctrl+s" is not a modifier: ctrl, alt, shift or '
          'super; "ctrl" is meant?',
      'ctrl+ctrl+s': '"ctrl" twice in "ctrl+ctrl+s"',
      'ctrl+Enter':
          '"Enter" in "ctrl+Enter" is neither one character nor '
          'a key',
      'Enter': '"enter" is meant?',
      'Esc': '"escape" is meant?',
      'ret':
          '"ret" in "ret" is neither one character nor a key: space, '
          'enter, tab, backspace, escape, up, down, left, right, home, end, '
          'pageup, pagedown, insert, delete, f1 to f12; "enter" is meant?',
      'pgup': '"pageup" is meant?',
      'F5': '"f5" is meant?',
      'ctrl': '"ctrl" in "ctrl" is a modifier: the key comes after it',
      'ctrl+': '"ctrl+" has no key after its last "+"',
      'shift+1':
          '"shift+1": Shift and "1" type another character, which '
          'names the key',
      'shift+space':
          '"shift+space": Shift and space type a space: "space" '
          'names the key',
      'ctrl+\t': 'a control character in "ctrl+\t" is not a key: name it',
      'g  g': 'keys apart by one space each',
      ' g': 'keys apart by one space each',
      '': 'keys apart by one space each',
    };
    for (final MapEntry(key: spec, value: message) in errors.entries) {
      expect(
        () => KeyCombo.parseSequence(spec),
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'message', contains(message))
              .having((e) => e.source, 'source', spec),
        ),
        reason: spec,
      );
    }
  });

  test('leader in a sequence stands for the leader given, alone; without '
      'one it is a FormatException', () {
    final space = KeyCombo.char(' ');
    expect(KeyCombo.parseSequence('leader f g', leader: space), [
      space,
      KeyCombo.char('f'),
      KeyCombo.char('g'),
    ]);
    expect(KeyCombo.parseSequence('g leader', leader: space), [
      KeyCombo.char('g'),
      space,
    ]);
    final errors = {
      'leader f': (
        null,
        '"leader" in "leader f" stands for a leader key, and none is given',
      ),
      'ctrl+leader': (
        space,
        '"leader" in "ctrl+leader" takes no modifiers: it is a key of its own',
      ),
    };
    for (final MapEntry(key: spec, value: (leader, message))
        in errors.entries) {
      expect(
        () => KeyCombo.parseSequence(spec, leader: leader),
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'message', message)
              .having((e) => e.source, 'source', spec),
        ),
        reason: spec,
      );
    }
  });

  test('parse takes one key: a sequence is a FormatException', () {
    expect(
      // the failure is what is tested
      // ignore: twk_lints/key_names
      () => KeyCombo.parse('g g'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          '"g g" is 2 keys; one is meant',
        ),
      ),
    );
  });

  group('a combo accepts the key events a terminal sends for it', () {
    final cases = <String, List<KeyEvent>>{
      // Shift and a letter: the capital as text, or the letter with Shift
      // (kitty with Ctrl or Alt held)
      'A': [char('A'), char('a', shift), char('A', shift)],
      'alt+A': [char('A', alt), char('a', alt | shift)],
      'ctrl+A': [char('a', ctrl | shift)],
      'ctrl+s': [
        char('s', ctrl),
        const KeyEvent(
          KeyCode.char,
          char: 's',
          modifiers: ctrl,
          kind: .repeat,
        ),
      ],
      '!': [char('!')],
      'space': [char(' ')],
      'shift+tab': [const KeyEvent(KeyCode.tab, modifiers: shift)],
      'ctrl+i': [char('i', ctrl)],
      'tab': [const KeyEvent(KeyCode.tab)],
    };
    final all = [for (final events in cases.values) ...events];
    for (final MapEntry(key: spec, value: events) in cases.entries) {
      test('"$spec": $events, no other of these', () {
        final combo = KeyCombo.parse(spec);
        expect([
          for (final e in all)
            if (combo.accepts(e)) e,
        ], events);
      });
    }

    test('not on its release', () {
      expect(
        KeyCombo.parse('ctrl+s').accepts(
          const KeyEvent(
            KeyCode.char,
            char: 's',
            modifiers: ctrl,
            kind: .release,
          ),
        ),
        isFalse,
      );
    });

    test('the combo of an event is the one that accepts it', () {
      for (final e in all) {
        expect(KeyCombo.fromEvent(e).accepts(e), isTrue, reason: '$e');
      }
      expect(KeyCombo.fromEvent(char('A')), KeyCombo.parse('A'));
      expect('${KeyCombo.fromEvent(char('a', ctrl | shift))}', 'ctrl+A');
    });
  });

  // a terminal without the protocol sends a control character for Ctrl and
  // a letter, and some of those are keys of their own
  Widget bound(List<String> seen, List<String> specs) => KeyBindings({
    for (final spec in specs) spec: () => seen.add(spec),
  }, child: const Text('x'));

  const specs = ['ctrl+i', 'tab', 'ctrl+m', 'enter', 'ctrl+[', 'escape'];

  testTwk('with the kitty keyboard protocol, ctrl+i is not tab, ctrl+m not '
      'enter and ctrl+[ not escape', (t) async {
    final seen = <String>[];
    await t.pumpWidget(bound(seen, specs), kittyKeyboard: true);
    await t.press(specs.join(' '));
    expect(seen, specs);
  });

  testTwk('without it, ctrl+i arrives as tab, ctrl+m as enter and ctrl+[ as '
      'escape', (t) async {
    final seen = <String>[];
    await t.pumpWidget(bound(seen, specs));
    await t.press(specs.join(' '));
    expect(seen, ['tab', 'tab', 'enter', 'enter', 'escape', 'escape']);
  });
}
