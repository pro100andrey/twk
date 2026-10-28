/// Dart.
library;

import '../lexer.dart';
import '../token.dart';

/// Dart: keywords, built-in and capitalized types, calls, annotations,
/// numbers, symbols, block comments that nest, and strings, raw or not,
/// one quote or three long, with escapes and interpolation (`$name`,
/// `${code}`). Comments in blocks, strings three quotes long and the code
/// interpolated in them go on across lines.
const dartLanguage = Language(name: 'dart', lexer: _DartLexer());

// The modes of the frames of the state: a block comment as deep as the
// frame's depth, a string with the flags below in its depth, or code
// interpolated in a string, with as many braces open in it as its depth.
const _comment = 0;
const _string = 1;
const _interpolation = 2;

const _double = 1;
const _triple = 2;
const _raw = 4;

final Set<String> _reserved = _words(
  'assert break case catch class const continue default do else enum '
  'extends final finally for if in is new rethrow return super switch this '
  'throw try var while with',
);

/// Keywords that are also names, of a method for one: a keyword unless a
/// call or a member.
final Set<String> _contextual = _words(
  'abstract as async await base covariant deferred export extension external '
  'factory get hide implements import interface late library mixin on '
  'operator part required sealed set show static sync typedef when yield',
);

/// The words of [text], apart by blanks.
Set<String> _words(String text) => text.split(' ').toSet();

const _constants = {'true', 'false', 'null'};

/// Built-in types not written with a capital.
const _types = {'bool', 'double', 'dynamic', 'int', 'num', 'void'};

final class _DartLexer extends Lexer {
  const _DartLexer();

  @override
  Object? lexLine(TokenScanner s, Object? state) {
    var frame = state as LexFrame?;
    if (frame == null && s.startsWith('#!')) {
      s.emitRest(TokenKind.comment);
      return null;
    }
    while (!s.atEnd) {
      frame = switch (frame?.mode) {
        _comment => _blockComment(s, frame!),
        _string => _stringBody(s, frame!),
        _ => _code(s, frame),
      };
    }
    // a string one quote long ends with the line, and what is in it
    var carried = frame;
    for (var f = frame; f != null; f = f.outer) {
      if (f.mode == _string && f.depth & _triple == 0) {
        carried = f.outer;
      }
    }
    return carried;
  }

  /// Lexes code, at the top or interpolated in a string ([frame]), up to
  /// where a comment or a string opens or the interpolation closes, and
  /// returns the frame lexing goes on in.
  LexFrame? _code(TokenScanner s, LexFrame? frame) {
    var interpolation = frame;
    while (!s.atEnd) {
      final c = s.current;
      final next = s.peek(1);
      if (TokenScanner.isBlank(c)) {
        s.emit(TokenKind.plain, s.endWhile(TokenScanner.isBlank));
      } else if (c == _slash && next == _slash) {
        s.emitRest(TokenKind.comment);
      } else if (c == _slash && next == _star) {
        s.emitLength(TokenKind.comment, 2);
        return LexFrame(_comment, depth: 1, outer: interpolation);
      } else if (c == _quote || c == _doubleQuote) {
        return _openString(s, 0, interpolation);
      } else if (c == _r && (next == _quote || next == _doubleQuote)) {
        return _openString(s, 1, interpolation);
      } else if (TokenScanner.isDigit(c) ||
          c == _dot && TokenScanner.isDigit(next)) {
        s.emit(TokenKind.number, s.numberEnd());
      } else if (_isNameStart(c)) {
        _name(s);
      } else if (c == _at) {
        s.emit(TokenKind.annotation, _dottedNameEnd(s, s.pos + 1));
      } else if (c == _hash) {
        final end = _isNameStart(next)
            ? _dottedNameEnd(s, s.pos + 1)
            : s.endWhile(_isOperator, s.pos + 1);
        s.emit(TokenKind.constant, end);
      } else if (c == _openBrace) {
        s.emitLength(TokenKind.punctuation, 1);
        interpolation = interpolation?.withDepth(interpolation.depth + 1);
      } else if (c == _closeBrace) {
        s.emitLength(TokenKind.punctuation, 1);
        if (interpolation != null) {
          if (interpolation.depth == 0) {
            return interpolation.outer;
          }
          interpolation = interpolation.withDepth(interpolation.depth - 1);
        }
      } else if (_isOperator(c)) {
        s.emitLength(TokenKind.operator, 1);
      } else if (_isPunctuation(c)) {
        s.emitLength(TokenKind.punctuation, 1);
      } else {
        s.emitLength(TokenKind.plain, 1);
      }
    }
    return interpolation;
  }

  /// Emits a name as what it is: a keyword, constant, type, call or other.
  void _name(TokenScanner s) {
    final line = s.line;
    final start = s.pos;
    final end = s.endWhile(_isNamePart);
    final name = line.substring(start, end);
    final member = s.peek(-1) == _dot;
    final call = end < line.length && line.codeUnitAt(end) == _openParen;
    final kind = switch (name) {
      _ when member => call ? TokenKind.function : _typeOrPlain(name),
      _ when _reserved.contains(name) => TokenKind.keyword,
      _ when _constants.contains(name) => TokenKind.constant,
      _ when _types.contains(name) => TokenKind.type,
      _ when !call && _contextual.contains(name) => TokenKind.keyword,
      _ when call && !_capitalized(name) => TokenKind.function,
      _ => _typeOrPlain(name),
    };
    s.emit(kind, end);
  }

  /// Emits the opening of a string with [prefix] code units before its
  /// quotes (`r`) and returns its frame, above [outer].
  LexFrame _openString(TokenScanner s, int prefix, LexFrame? outer) {
    final quote = s.peek(prefix);
    final triple = s.peek(prefix + 1) == quote && s.peek(prefix + 2) == quote;
    s.emitLength(TokenKind.string, prefix + (triple ? 3 : 1));
    return LexFrame(
      _string,
      depth:
          (quote == _doubleQuote ? _double : 0) |
          (triple ? _triple : 0) |
          (prefix > 0 ? _raw : 0),
      outer: outer,
    );
  }

  /// Lexes the inside of the string of [frame] up to where it ends or an
  /// interpolation opens, and returns the frame lexing goes on in.
  LexFrame? _stringBody(TokenScanner s, LexFrame frame) {
    final quote = frame.depth & _double != 0 ? _doubleQuote : _quote;
    final triple = frame.depth & _triple != 0;
    final raw = frame.depth & _raw != 0;
    while (!s.atEnd) {
      s.emit(
        TokenKind.string,
        s.endWhile(
          (unit) =>
              unit != quote && (raw || unit != _backslash && unit != _dollar),
        ),
      );
      final c = s.current;
      if (c == quote) {
        if (!triple || s.peek(1) == quote && s.peek(2) == quote) {
          s.emitLength(TokenKind.string, triple ? 3 : 1);
          return frame.outer;
        }
        s.emitLength(TokenKind.string, 1);
      } else if (c == _backslash) {
        s.emit(TokenKind.escape, _escapeEnd(s));
      } else if (c == _dollar) {
        final next = s.peek(1);
        if (next == _openBrace) {
          s.emitLength(TokenKind.punctuation, 2);
          return LexFrame(_interpolation, outer: frame);
        }
        if (TokenScanner.isIdentifierStart(next)) {
          s.emit(
            TokenKind.variable,
            s.endWhile(TokenScanner.isIdentifierPart, s.pos + 1),
          );
        } else {
          s.emitLength(TokenKind.string, 1);
        }
      }
    }
    return frame;
  }

  /// Lexes the block comment of [frame], counting the comments nested in
  /// it, and returns the frame lexing goes on in.
  LexFrame? _blockComment(TokenScanner s, LexFrame frame) {
    final line = s.line;
    var depth = frame.depth;
    var i = s.pos;
    while (i < line.length) {
      if (line.startsWith('/*', i)) {
        depth++;
        i += 2;
      } else if (line.startsWith('*/', i)) {
        depth--;
        i += 2;
        if (depth == 0) {
          s.emit(TokenKind.comment, i);
          return frame.outer;
        }
      } else {
        i++;
      }
    }
    s.emit(TokenKind.comment, i);
    return frame.withDepth(depth);
  }
}

/// The end of the escape sequence at [s]'s position: `\xHH`, `\uHHHH`,
/// `\u{H…}`, or a backslash and the character after it.
int _escapeEnd(TokenScanner s) {
  final start = s.pos + 1;
  switch (s.peek(1)) {
    case -1:
      return start;
    case _x:
      return _hexEnd(s, start + 1, 2);
    case _u when s.peek(2) == _openBrace:
      final close = s.line.indexOf('}', start);
      return close < 0 ? s.line.length : close + 1;
    case _u:
      return _hexEnd(s, start + 1, 4);
  }
  return start + 1;
}

/// The end of up to [count] hexadecimal digits from [from].
int _hexEnd(TokenScanner s, int from, int count) {
  final end = s.endWhile(TokenScanner.isHexDigit, from);
  return end - from > count ? from + count : end;
}

/// The end of a name and the names after it, a dot before each, from
/// [from]: `a.b.C`.
int _dottedNameEnd(TokenScanner s, int from) {
  var end = s.endWhile(_isNamePart, from);
  while (end > from &&
      end + 1 < s.line.length &&
      s.line.codeUnitAt(end) == _dot &&
      _isNameStart(s.line.codeUnitAt(end + 1))) {
    end = s.endWhile(_isNamePart, end + 1);
  }
  return end;
}

TokenKind _typeOrPlain(String name) =>
    _capitalized(name) ? TokenKind.type : TokenKind.plain;

/// Whether [name] starts with a capital after its `_`s and `$`s.
bool _capitalized(String name) {
  for (var i = 0; i < name.length; i++) {
    final unit = name.codeUnitAt(i);
    if (unit != _underscore && unit != _dollar) {
      return unit >= 0x41 && unit <= 0x5A;
    }
  }
  return false;
}

bool _isNameStart(int unit) =>
    TokenScanner.isIdentifierStart(unit) || unit == _dollar;

bool _isNamePart(int unit) =>
    TokenScanner.isIdentifierPart(unit) || unit == _dollar;

bool _isOperator(int unit) => switch (unit) {
  0x21 || 0x25 || 0x26 || 0x2A || 0x2B || 0x2D || 0x2F => true, // ! % & * + - /
  0x3C || 0x3D || 0x3E || 0x3F || 0x5E || 0x7C || 0x7E => true, // < = > ? ^ | ~
  _ => false,
};

bool _isPunctuation(int unit) => switch (unit) {
  0x28 || 0x29 || 0x2C || 0x2E || 0x3A || 0x3B || 0x5B || 0x5D => true,
  _ => false,
};

const _slash = 0x2F;
const _star = 0x2A;
const _quote = 0x27;
const _doubleQuote = 0x22;
const _backslash = 0x5C;
const _dollar = 0x24;
const _dot = 0x2E;
const _at = 0x40;
const _hash = 0x23;
const _openParen = 0x28;
const _openBrace = 0x7B;
const _closeBrace = 0x7D;
const _underscore = 0x5F;
const _r = 0x72;
const _u = 0x75;
const _x = 0x78;
