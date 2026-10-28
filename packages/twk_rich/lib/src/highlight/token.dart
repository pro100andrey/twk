/// What a lexer splits a line of source into: [Token]s of a [TokenKind].
library;

import 'dart:convert';

/// What a piece of source is, which picks its style in a `SyntaxTheme`. Each
/// language uses the kinds it has; what Pygments calls a token of a kind is
/// the guide for what a lexer gives it.
enum TokenKind {
  /// Text of no other kind: names, blanks, and what a lexer does not know.
  plain,

  /// A reserved word or one that acts as a keyword where it stands: `if`,
  /// `class`, `return`.
  keyword,

  /// The name of a type: a built-in one, and by convention one that starts
  /// with a capital, a YAML tag, or a Rust lifetime.
  type,

  /// The name of a function or method where it is declared or called, a
  /// Rust macro, or the command of a shell command line.
  function,

  /// A variable a language marks as one: `$x` in a shell, a string
  /// interpolation or a Rust macro, the name an assignment of a shell sets,
  /// a YAML anchor or alias.
  variable,

  /// A literal constant other than a number: `true`, `false`, `null`.
  constant,

  /// A string or character literal, its quotes included, or text a
  /// language takes as a string: a heredoc, a YAML scalar, a regular
  /// expression literal, the format spec of a Python f-string.
  string,

  /// An escape sequence in a string: `\n`, `\u{1F600}`, `''` in YAML,
  /// `{{` in a Python f-string.
  escape,

  /// A number literal, its prefix and suffix included: `0xFF`, `1.5e3`,
  /// `10u32`.
  number,

  /// A comment, its markers included.
  comment,

  /// An annotation, decorator, attribute or directive: `@override`,
  /// `#[derive(Debug)]`, `%YAML 1.2`.
  annotation,

  /// The key of a mapping in data: of a JSON object, a YAML mapping.
  key,

  /// Brackets, separators and delimiters: `( ) { } , ;`, and those that
  /// open and close an interpolation.
  punctuation,

  /// An operator: `+`, `=`, `=>`, `&&`, a shell's `|` and redirections.
  operator,

  /// A line a diff adds.
  inserted,

  /// A line a diff removes.
  deleted,

  /// A header of a diff: of a file, of a hunk.
  heading,
}

/// A piece of a line of source and what it is: [text] of [kind].
final class Token {
  /// [text] of [kind].
  const Token(this.kind, this.text);

  /// What the text is, which picks its style.
  final TokenKind kind;

  /// The text, without the line break that ends a line.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is Token && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => '${kind.name}${jsonEncode(text)}';
}
