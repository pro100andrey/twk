// The input events as values: their modifiers, equality and hashes, and
// how they print.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

void main() {
  test("a key's ctrl, alt and shift tell the modifiers held", () {
    const key = KeyEvent(
      KeyCode.up,
      modifiers: Mod.ctrl | Mod.shift | Mod.superKey,
    );
    expect((key.ctrl, key.alt, key.shift), (true, false, true));
    const alt = KeyEvent(KeyCode.char, char: 'x', modifiers: Mod.alt);
    expect((alt.ctrl, alt.alt, alt.shift), (false, true, false));
    const plain = KeyEvent(KeyCode.char, char: 'x');
    expect((plain.ctrl, plain.alt, plain.shift), (false, false, false));
  });

  test('equal events are one in a set, events that differ in any field '
      'are not', () {
    // read at run time, so that the second of each is no const, which is
    // canonical: the same object as the first
    final focused = bool.parse('true');
    final three = int.parse('3');
    final groups = <List<InputEvent>>[
      [
        const KeyEvent(KeyCode.char, char: 'a'),
        KeyEvent(KeyCode.char, char: String.fromCharCode(0x61)),
        const KeyEvent(KeyCode.char, char: 'b'),
        const KeyEvent(KeyCode.char, char: 'a', modifiers: Mod.ctrl),
        const KeyEvent(KeyCode.char, char: 'a', kind: KeyKind.release),
      ],
      [
        const MouseEvent(MouseKind.down, 3, 4),
        MouseEvent(MouseKind.down, three, 4),
        const MouseEvent(MouseKind.down, 3, 4, button: 2),
        const MouseEvent(MouseKind.down, 3, 4, modifiers: Mod.shift),
        const MouseEvent(MouseKind.up, 3, 4),
      ],
      [
        const PasteEvent('hi'),
        PasteEvent(String.fromCharCodes([0x68, 0x69])),
        const PasteEvent('ho'),
      ],
      [
        const FocusEvent(true),
        FocusEvent(focused),
        const FocusEvent(false),
      ],
      [
        const ResizeEvent(80, 24),
        ResizeEvent(80 + three - 3, 24),
        const ResizeEvent(24, 80),
      ],
      [
        const ModeReport(2026, 1),
        ModeReport(2026, three - 2),
        const ModeReport(2026, 2),
        const ModeReport(2027, 1),
      ],
      [
        const KeyboardFlagsReport(1),
        KeyboardFlagsReport(three - 2),
        const KeyboardFlagsReport(3),
      ],
      [
        const ColorSchemeReport(Brightness.dark),
        ColorSchemeReport(Brightness.values[three - 3]),
        const ColorSchemeReport(Brightness.light),
      ],
    ];
    for (final [first, equal, ...others] in groups) {
      expect(equal, first);
      expect(equal.hashCode, first.hashCode, reason: '$first');
      expect({first, equal, ...others}, hasLength(1 + others.length));
    }
  });

  test('an unknown sequence prints its bytes, ESC spelled out', () {
    expect(
      UnknownSequence('\x1b[99;1z'.codeUnits).toString(),
      'Unknown(ESC[99;1z)',
    );
  });
}
