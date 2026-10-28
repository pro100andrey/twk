// A syntax theme as a value: copyWith replacing the style of each kind
// alone, tokens made spans in the styles of their kinds, and themes equal
// by their styles hashing alike.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';

/// How copyWith replaces the style of each kind.
final copies = <TokenKind, SyntaxTheme Function(SyntaxTheme, Style)>{
  TokenKind.plain: (t, s) => t.copyWith(plain: s),
  TokenKind.keyword: (t, s) => t.copyWith(keyword: s),
  TokenKind.type: (t, s) => t.copyWith(type: s),
  TokenKind.function: (t, s) => t.copyWith(function: s),
  TokenKind.variable: (t, s) => t.copyWith(variable: s),
  TokenKind.constant: (t, s) => t.copyWith(constant: s),
  TokenKind.string: (t, s) => t.copyWith(string: s),
  TokenKind.escape: (t, s) => t.copyWith(escape: s),
  TokenKind.number: (t, s) => t.copyWith(number: s),
  TokenKind.comment: (t, s) => t.copyWith(comment: s),
  TokenKind.annotation: (t, s) => t.copyWith(annotation: s),
  TokenKind.key: (t, s) => t.copyWith(key: s),
  TokenKind.punctuation: (t, s) => t.copyWith(punctuation: s),
  TokenKind.operator: (t, s) => t.copyWith(operator: s),
  TokenKind.inserted: (t, s) => t.copyWith(inserted: s),
  TokenKind.deleted: (t, s) => t.copyWith(deleted: s),
  TokenKind.heading: (t, s) => t.copyWith(heading: s),
};

void main() {
  final base = SyntaxTheme.from(const ThemeData.terminal(Brightness.dark));
  const red = Style(fg: Color.rgb(200, 0, 0));

  test('copyWith replaces the style of the kind given and keeps every '
      'other', () {
    expect(copies.keys, unorderedEquals(TokenKind.values));
    for (final MapEntry(key: kind, value: copy) in copies.entries) {
      final changed = copy(base, red);
      for (final other in TokenKind.values) {
        expect(
          changed.styleOf(other),
          other == kind ? red : base.styleOf(other),
          reason: '$other after copyWith(${kind.name}:)',
        );
      }
    }
    expect(base.copyWith(), base);
  });

  test('spans are the tokens in the styles of their kinds, in order', () {
    const tokens = [
      Token(TokenKind.keyword, 'final'),
      Token(TokenKind.plain, ' x '),
      Token(TokenKind.operator, '='),
      Token(TokenKind.number, '1'),
    ];
    final spans = base.spans(tokens);
    expect([for (final span in spans) span.text], ['final', ' x ', '=', '1']);
    expect(
      [for (final span in spans) span.style],
      [
        base.keyword,
        base.plain,
        base.operator,
        base.number,
      ],
    );
    expect(base.spans(const []), isEmpty);
  });

  test('themes with equal styles are equal and hash alike', () {
    final again = SyntaxTheme.from(const ThemeData.terminal(Brightness.dark));
    expect(again, base);
    expect(again.hashCode, base.hashCode);
    expect(base.copyWith(comment: red), isNot(base));
    expect(
      base.copyWith(comment: red).hashCode,
      base.copyWith(comment: red).hashCode,
    );
  });
}
