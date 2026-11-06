// A backslash before a character beyond U+FFFF: every language's escape
// takes the whole character, never half of its surrogate pair.
import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

void main() {
  for (final language in languages) {
    test('${language.name}: no token holds half a surrogate pair', () {
      final tokens = Highlighter(language, r'"\😀" x').tokens(0);
      expect(tokens.map((t) => t.text).join(), r'"\😀" x');
      for (final token in tokens) {
        final text = token.text;
        expect(
          text.runes.any((r) => r >= 0xD800 && r <= 0xDFFF),
          isFalse,
          reason: '$token holds a lone surrogate',
        );
        if (token.kind == TokenKind.escape) {
          expect(text, r'\😀');
        }
      }
    });
  }
}
