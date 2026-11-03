import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart' show mayReorder;

/// 'a', [mark] and 'b': the controls are built, not written, so that the
/// source reads as it is.
String withMark(int mark) => String.fromCharCodes([0x61, mark, 0x62]);

void main() {
  test('mayReorder is true for a string with a right-to-left letter, an '
      'Arabic number or a right-to-left embedding, override or isolate', () {
    expect(mayReorder('שלום'), isTrue);
    expect(mayReorder('abc שלום'), isTrue);
    expect(mayReorder('مرحبا'), isTrue);
    expect(mayReorder('a١'), isTrue);
    expect(mayReorder(withMark(0x202B)), isTrue);
    expect(mayReorder(withMark(0x202E)), isTrue);
    expect(mayReorder(withMark(0x2067)), isTrue);
    // a letter outside the BMP, as a surrogate pair
    expect(mayReorder('a\u{10800}'), isTrue);
  });

  test('mayReorder is false for text that has none: Latin, digits, CJK, '
      'emoji, a lone surrogate, the empty string', () {
    expect(mayReorder(''), isFalse);
    expect(mayReorder('hello 123 !?'), isFalse);
    expect(mayReorder('日本語 한국어 ß é'), isFalse);
    expect(mayReorder('a\u{1F600}b'), isFalse);
    expect(mayReorder('a\uD800'), isFalse);
    expect(mayReorder(withMark(0x202A)), isFalse);
  });
}
