/// JSON.
library;

import '../lexer.dart';
import '../token.dart';

/// JSON: keys apart from other strings, escapes, numbers, `true`, `false`
/// and `null`, and the comments of JSON with comments (`//`, and `/* */`
/// across lines). A string ends with its line; a key is a string a `:`
/// follows on its line.
const jsonLanguage = Language(
  name: 'json',
  aliases: ['jsonc'],
  lexer: _JsonLexer(),
);

/// The state of a line that ends inside a block comment.
const _inComment = 1;

final _number = RegExp(r'-?\d+(\.\d+)?([eE][+-]?\d+)?');

final class _JsonLexer extends Lexer {
  const _JsonLexer();

  @override
  Object? lexLine(TokenScanner s, Object? state) {
    var inComment = state == _inComment;
    while (!s.atEnd) {
      final c = s.current;
      if (inComment) {
        final close = s.indexOf('*/');
        s.emit(TokenKind.comment, close < 0 ? s.line.length : close + 2);
        inComment = close < 0;
      } else if (TokenScanner.isBlank(c)) {
        s.emit(TokenKind.plain, s.endWhile(TokenScanner.isBlank));
      } else if (c == _quote) {
        _string(s);
      } else if (c == _minus || TokenScanner.isDigit(c)) {
        final end = s.match(_number);
        s.emit(TokenKind.number, end < 0 ? s.pos : end);
        s.emitLength(TokenKind.plain, end < 0 ? 1 : 0);
      } else if (TokenScanner.isIdentifierStart(c)) {
        final end = s.endWhile(TokenScanner.isIdentifierPart);
        final word = s.line.substring(s.pos, end);
        s.emit(
          word == 'true' || word == 'false' || word == 'null'
              ? TokenKind.constant
              : TokenKind.plain,
          end,
        );
      } else if (c == _slash && s.peek(1) == _slash) {
        s.emitRest(TokenKind.comment);
      } else if (c == _slash && s.peek(1) == _star) {
        s.emitLength(TokenKind.comment, 2);
        inComment = true;
      } else if ('{}[],:'.contains(String.fromCharCode(c))) {
        s.emitLength(TokenKind.punctuation, 1);
      } else {
        s.emitLength(TokenKind.plain, 1);
      }
    }
    return inComment ? _inComment : null;
  }

  /// Emits the string at [s]'s position, as a key when a `:` follows it.
  void _string(TokenScanner s) {
    final line = s.line;
    var end = s.pos + 1;
    while (end < line.length && line.codeUnitAt(end) != _quote) {
      end += line.codeUnitAt(end) == _backslash ? 2 : 1;
    }
    end = end < line.length ? end + 1 : line.length;
    final after = s.endWhile(TokenScanner.isBlank, end);
    final kind = after < line.length && line.codeUnitAt(after) == _colon
        ? TokenKind.key
        : TokenKind.string;
    while (s.pos < end) {
      final escape = line.indexOf(r'\', s.pos);
      if (escape < 0 || escape >= end) {
        s.emit(kind, end);
      } else {
        s.emit(kind, escape);
        final length = s.peek(1) == _u ? 6 : 2;
        s.emit(TokenKind.escape, escape + length > end ? end : escape + length);
      }
    }
  }
}

const _quote = 0x22;
const _backslash = 0x5C;
const _slash = 0x2F;
const _star = 0x2A;
const _minus = 0x2D;
const _colon = 0x3A;
const _u = 0x75;
