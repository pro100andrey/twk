/// What a language is made of: a [Lexer] that splits a line into tokens with
/// a [TokenScanner], states that nest ([LexFrame]), and the [Language] that
/// names it.
library;

import 'token.dart';

/// Splits source of one language into tokens a line at a time.
///
/// [lexLine] gets a line and the state the line before ended in and
/// returns the state this one ends in: inside a block comment, a string
/// that spans lines, a heredoc. A state is a value: null (where the
/// source starts), an int, a string, a record, an enum, a [LexFrame], or
/// an object of a class of the lexer's own with `==` and `hashCode`. Two
/// equal states must lex the next line alike, since a `Highlighter`
/// stops lexing again after an edit at the first line that starts in a
/// state equal to the one it started in before; and a state carries no
/// more than the lines after it need, so that one an edit did not change
/// stays equal.
///
/// A lexer keeps nothing between calls: one instance, a `const` one, lexes
/// any number of sources.
///
/// Adding a language is a file `lang/<name>.dart` that declares its lexer,
/// private, and `const <name>Language`, its [Language], whose doc names
/// what the lexer tells apart; and in `languages.dart` the file's import,
/// its export and an entry in `languages`. What nests across lines goes in
/// [LexFrame]s (as in `lang/dart.dart` and `lang/bash.dart`) or in a value
/// of the lexer's own (`lang/json.dart`), and the docs of [TokenKind] say
/// what each kind is for.
abstract class Lexer {
  /// A lexer, constant, as every lexer of this package is.
  const Lexer();

  /// Lexes the line [s] holds, which starts in [state], from
  /// [TokenScanner.pos] 0 to its end, and returns the state it ends in.
  /// Whatever it leaves unlexed at the end of the line is
  /// [TokenKind.plain].
  Object? lexLine(TokenScanner s, Object? state);
}

/// A line of source being lexed: [line], the position [pos] lexing has
/// reached, and the tokens before it, which [emit] adds.
///
/// A lexer looks at the code units at and around [pos] ([current],
/// [peek], [startsWith], [match]), finds where a token ends ([endWhile],
/// [numberEnd], [indexOf]) and emits it, which moves [pos] to its end.
/// Tokens of one kind that follow each other are one token.
final class TokenScanner {
  /// A scanner of [line] at its start, no token emitted yet.
  TokenScanner(this.line);

  /// The line, without its line break.
  final String line;

  /// Where the next token starts: the end of the last one emitted.
  int get pos => _pos;
  var _pos = 0;

  final _kinds = <TokenKind>[];
  final _ends = <int>[];

  /// Whether the whole line is lexed.
  bool get atEnd => _pos >= line.length;

  /// The code unit at [pos]; -1 at the end of the line.
  int get current => _pos < line.length ? line.codeUnitAt(_pos) : -1;

  /// The code unit [offset] units after [pos], or before it when negative;
  /// -1 outside the line.
  int peek(int offset) {
    final i = _pos + offset;
    return i >= 0 && i < line.length ? line.codeUnitAt(i) : -1;
  }

  /// Whether [text] is at [pos] + [offset].
  bool startsWith(String text, [int offset = 0]) =>
      line.startsWith(text, _pos + offset);

  /// The end of the match of [pattern] at [pos]; -1 when it does not
  /// match there.
  int match(Pattern pattern) => pattern.matchAsPrefix(line, _pos)?.end ?? -1;

  /// Where [text] is next found from [pos]; -1 when it is not.
  int indexOf(String text) => line.indexOf(text, _pos);

  /// The first index from [from] (by default [pos]) whose code unit fails
  /// [test]; the length of the line when none does.
  int endWhile(bool Function(int unit) test, [int? from]) {
    var i = from ?? _pos;
    while (i < line.length && test(line.codeUnitAt(i))) {
      i++;
    }
    return i;
  }

  /// The end of the number at [pos], as C-like languages write one:
  /// decimal with an optional fraction and exponent (`1`, `1.5`, `.5`,
  /// `1e-3`), or hexadecimal, binary or octal with a `0x`, `0b` or `0o`
  /// prefix; `_` may separate digits, and letters and digits right after
  /// it are a suffix it includes (`10u32`, `1n`, `2.0f`). [pos] when no
  /// number is there. A `.` is the number's only when a digit follows it,
  /// so `1.foo` and `1..2` end at the `1`.
  int numberEnd() {
    var i = _pos;
    final first = current;
    if (first == _zero && i + 1 < line.length) {
      final prefix = line.codeUnitAt(i + 1) | 0x20;
      if (prefix == 0x78 || prefix == 0x62 || prefix == 0x6F) {
        // 0x, 0b, 0o and the digits and suffix after them
        return endWhile(isIdentifierPart, i + 2);
      }
    }
    if (isDigit(first)) {
      i = endWhile(_isDigitOrSeparator, i);
    } else if (first != _dot || !isDigit(peek(1))) {
      return _pos;
    }
    if (_unit(i) == _dot && isDigit(_unit(i + 1))) {
      i = endWhile(_isDigitOrSeparator, i + 1);
    }
    if (_unit(i) | 0x20 == 0x65) {
      var j = i + 1;
      if (_unit(j) == 0x2B || _unit(j) == 0x2D) {
        j++;
      }
      if (isDigit(_unit(j))) {
        i = endWhile(_isDigitOrSeparator, j);
      }
    }
    return endWhile(isIdentifierPart, i);
  }

  /// Emits the text from [pos] to [end] as a token of [kind] and moves
  /// [pos] to [end]; nothing when [end] is [pos].
  void emit(TokenKind kind, int end) {
    assert(end >= _pos && end <= line.length, 'emit to $end from $_pos');
    if (end <= _pos) {
      return;
    }
    if (_kinds.isNotEmpty && _kinds.last == kind) {
      _ends.last = end;
    } else {
      _kinds.add(kind);
      _ends.add(end);
    }
    _pos = end;
  }

  /// Emits the next [length] code units as a token of [kind].
  void emitLength(TokenKind kind, int length) => emit(kind, _pos + length);

  /// Emits the rest of the line as a token of [kind].
  void emitRest(TokenKind kind) => emit(kind, line.length);

  /// The tokens of the line, the rest of it [TokenKind.plain] when it is
  /// not lexed to its end.
  List<Token> tokens() {
    emitRest(TokenKind.plain);
    if (_kinds.isEmpty) {
      return const [];
    }
    return List.unmodifiable([
      for (var k = 0; k < _kinds.length; k++)
        Token(_kinds[k], line.substring(k == 0 ? 0 : _ends[k - 1], _ends[k])),
    ]);
  }

  int _unit(int i) => i < line.length ? line.codeUnitAt(i) : -1;

  /// Whether [unit] is an ASCII digit.
  static bool isDigit(int unit) => unit >= _zero && unit <= _zero + 9;

  /// Whether [unit] is an ASCII hexadecimal digit.
  static bool isHexDigit(int unit) =>
      isDigit(unit) || (unit | 0x20) >= 0x61 && (unit | 0x20) <= 0x66;

  /// Whether [unit] starts a name in most languages: an ASCII letter, `_`,
  /// or a code unit beyond ASCII.
  static bool isIdentifierStart(int unit) =>
      (unit | 0x20) >= 0x61 && (unit | 0x20) <= 0x7A ||
      unit == 0x5F ||
      unit >= 0x80;

  /// Whether [unit] goes on a name in most languages: what starts one, or
  /// an ASCII digit.
  static bool isIdentifierPart(int unit) =>
      isIdentifierStart(unit) || isDigit(unit);

  /// Whether [unit] is a space or a tab.
  static bool isBlank(int unit) => unit == 0x20 || unit == 0x09;

  static bool _isDigitOrSeparator(int unit) => isDigit(unit) || unit == 0x5F;
}

const _zero = 0x30;
const _dot = 0x2E;

/// A state of a lexer whose constructs nest across lines: the [mode] it is
/// in, such as a string, a block comment or code interpolated in a string,
/// above the frames it returns to ([outer]), which are null at the bottom.
/// What a mode needs is in [depth] (how deep comments or brackets nest, the
/// flags of a string) and [text] (the word that ends a heredoc). Frames
/// are values: equal when their stacks hold equal fields.
final class LexFrame {
  /// A frame in [mode], with [depth] 0 and [text] empty unless given,
  /// above [outer], none by default.
  const LexFrame(this.mode, {this.depth = 0, this.text = '', this.outer});

  /// What lexing is inside of, as the lexer numbers its modes.
  final int mode;

  /// What the mode needs as a number: how deep comments or brackets nest,
  /// or the flags of a string.
  final int depth;

  /// What the mode needs as text, such as the word that ends a heredoc.
  final String text;

  /// The frame lexing returns to when this one ends; null at the bottom.
  final LexFrame? outer;

  /// This frame with [depth] set.
  LexFrame withDepth(int depth) =>
      LexFrame(mode, depth: depth, text: text, outer: outer);

  @override
  bool operator ==(Object other) =>
      other is LexFrame &&
      other.mode == mode &&
      other.depth == depth &&
      other.text == text &&
      other.outer == outer;

  @override
  int get hashCode => Object.hash(mode, depth, text, outer);

  @override
  String toString() =>
      'LexFrame($mode, depth: $depth, text: $text, outer: $outer)';
}

/// A language that can be highlighted: its [name], the [aliases] it also
/// goes by, such as the names of Markdown code fences, and its [lexer].
final class Language {
  /// A language called [name] and [aliases], none by default, all in lower
  /// case, lexed by [lexer].
  const Language({
    required this.name,
    required this.lexer,
    this.aliases = const [],
  });

  /// Text without highlighting: each line a single plain token. What a
  /// name no language goes by falls back to.
  static const plain = Language(
    name: 'text',
    lexer: _PlainLexer(),
    aliases: ['plain', 'plaintext', 'txt'],
  );

  /// The name, in lower case.
  final String name;

  /// Other names, in lower case.
  final List<String> aliases;

  /// What splits the language's lines into tokens.
  final Lexer lexer;

  /// Whether this language is [name] or goes by it, in any case.
  bool isNamed(String name) {
    final lower = name.toLowerCase();
    return lower == this.name || aliases.contains(lower);
  }

  @override
  String toString() => 'Language($name)';
}

/// The lexer of [Language.plain].
final class _PlainLexer extends Lexer {
  const _PlainLexer();

  @override
  Object? lexLine(TokenScanner s, Object? state) => null;
}
