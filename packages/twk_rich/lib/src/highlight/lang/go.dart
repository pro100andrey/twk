/// Go.
library;

import '../lexer.dart';
import '../token.dart';

/// Go: keywords, built-in types and the types `type` declares, functions
/// where `func` declares them and where they are called, `true`, `false`,
/// `nil` and `iota`, numbers, comments, strings and runes with escapes,
/// and raw strings in backquotes. Comments in blocks and raw strings go on
/// across lines. A name that starts with a capital is exported, not a type,
/// so it is plain where nothing else tells what it is.
const goLanguage = Language(
  name: 'go',
  aliases: ['golang'],
  lexer: _GoLexer(),
);

/// The state of a line that ends inside a block comment.
const _inComment = 1;

/// The state of a line that ends inside a raw string.
const _inRaw = 2;

const _keywords = {
  'break', 'case', 'chan', 'const', 'continue', 'default', 'defer', 'else', //
  'fallthrough', 'for', 'func', 'go', 'goto', 'if', 'import', 'interface',
  'map', 'package', 'range', 'return', 'select', 'struct', 'switch', 'type',
  'var',
};

const _constants = {'true', 'false', 'nil', 'iota'};

const _types = {
  'any', 'bool', 'byte', 'comparable', 'complex64', 'complex128', 'error', //
  'float32', 'float64', 'int', 'int8', 'int16', 'int32', 'int64', 'rune',
  'string', 'uint', 'uint8', 'uint16', 'uint32', 'uint64', 'uintptr',
};

final class _GoLexer extends Lexer {
  const _GoLexer();

  @override
  Object? lexLine(TokenScanner s, Object? state) {
    if (state == _inComment && !_closeComment(s)) {
      return _inComment;
    }
    if (state == _inRaw && !_closeRaw(s)) {
      return _inRaw;
    }
    // what `type` or `func` declares, if the next token is a name
    TokenKind? declared;
    while (!s.atEnd) {
      final c = s.current;
      final next = s.peek(1);
      if (TokenScanner.isBlank(c)) {
        s.emit(TokenKind.plain, s.endWhile(TokenScanner.isBlank));
        continue;
      }
      final declares = declared;
      declared = null;
      if (c == _slash && next == _slash) {
        s.emitRest(TokenKind.comment);
      } else if (c == _slash && next == _star) {
        s.emitLength(TokenKind.comment, 2);
        if (!_closeComment(s)) {
          return _inComment;
        }
      } else if (c == _backtick) {
        s.emitLength(TokenKind.string, 1);
        if (!_closeRaw(s)) {
          return _inRaw;
        }
      } else if (c == _doubleQuote) {
        _string(s);
      } else if (c == _quote) {
        _rune(s);
      } else if (TokenScanner.isDigit(c) ||
          c == _dot && TokenScanner.isDigit(next)) {
        s.emit(TokenKind.number, s.numberEnd());
      } else if (TokenScanner.isIdentifierStart(c)) {
        declared = _name(s, declares);
      } else if (c == _colon && next == _equals) {
        s.emitLength(TokenKind.operator, 2);
      } else if (_isOperator(c)) {
        s.emitLength(TokenKind.operator, 1);
      } else if (_isPunctuation(c)) {
        s.emitLength(TokenKind.punctuation, 1);
      } else {
        s.emitLength(TokenKind.plain, 1);
      }
    }
    return null;
  }

  /// Emits a name as what it is, as [declares] says when `type` or `func`
  /// is before it, and returns what the name after it declares.
  TokenKind? _name(TokenScanner s, TokenKind? declares) {
    final line = s.line;
    final end = s.endWhile(TokenScanner.isIdentifierPart);
    final name = line.substring(s.pos, end);
    final call = end < line.length && line.codeUnitAt(end) == _openParen;
    final member = s.peek(-1) == _dot;
    s.emit(switch (name) {
      _ when member => call ? TokenKind.function : TokenKind.plain,
      _ when _keywords.contains(name) => TokenKind.keyword,
      _ when declares != null => declares,
      _ when _constants.contains(name) => TokenKind.constant,
      _ when _types.contains(name) => TokenKind.type,
      _ when call => TokenKind.function,
      _ => TokenKind.plain,
    }, end);
    if (member) {
      return null;
    }
    return switch (name) {
      'type' => TokenKind.type,
      'func' => TokenKind.function,
      _ => null,
    };
  }
}

/// Emits the block comment at [s]'s position up to its end or the end of
/// the line; whether it ended.
bool _closeComment(TokenScanner s) {
  final close = s.indexOf('*/');
  s.emit(TokenKind.comment, close < 0 ? s.line.length : close + 2);
  return close >= 0;
}

/// Emits the raw string at [s]'s position up to its closing backquote or
/// the end of the line; whether it ended.
bool _closeRaw(TokenScanner s) {
  final close = s.indexOf('`');
  s.emit(TokenKind.string, close < 0 ? s.line.length : close + 1);
  return close >= 0;
}

/// Emits the string at [s]'s position, which ends with its line.
void _string(TokenScanner s) {
  s.emitLength(TokenKind.string, 1);
  while (!s.atEnd) {
    s.emit(
      TokenKind.string,
      s.endWhile((unit) => unit != _doubleQuote && unit != _backslash),
    );
    if (s.current == _doubleQuote) {
      s.emitLength(TokenKind.string, 1);
      return;
    }
    if (!s.atEnd) {
      s.emit(TokenKind.escape, _escapeEnd(s));
    }
  }
}

/// Emits the rune at [s]'s position: a character or an escape in quotes,
/// or the quote alone when no rune is there.
void _rune(TokenScanner s) {
  final line = s.line;
  final start = s.pos;
  int end;
  if (s.peek(1) == _backslash) {
    s.emitLength(TokenKind.string, 1);
    end = _escapeEnd(s);
  } else {
    end = start + 1 + _characterLength(line, start + 1);
  }
  if (end < line.length && line.codeUnitAt(end) == _quote) {
    if (s.pos > start) {
      s
        ..emit(TokenKind.escape, end)
        ..emitLength(TokenKind.string, 1);
    } else {
      s.emit(TokenKind.string, end + 1);
    }
  } else if (s.pos == start) {
    s.emitLength(TokenKind.plain, 1);
  }
}

/// The length of the character at [i] of [line]: 2 for a surrogate pair,
/// 0 at the end of the line or at a quote.
int _characterLength(String line, int i) {
  if (i >= line.length || line.codeUnitAt(i) == _quote) {
    return 0;
  }
  final unit = line.codeUnitAt(i);
  return unit >= 0xD800 && unit < 0xDC00 && i + 1 < line.length ? 2 : 1;
}

/// The end of the escape at [s]'s position: `\xHH`, `\uHHHH`,
/// `\UHHHHHHHH`, three octal digits, or a backslash and the character after
/// it.
int _escapeEnd(TokenScanner s) {
  final start = s.pos + 1;
  return switch (s.peek(1)) {
    -1 => start,
    0x78 => _digitsEnd(s, start + 1, 2, TokenScanner.isHexDigit), // x
    0x75 => _digitsEnd(s, start + 1, 4, TokenScanner.isHexDigit), // u
    0x55 => _digitsEnd(s, start + 1, 8, TokenScanner.isHexDigit), // U
    >= 0x30 && <= 0x37 => _digitsEnd(s, start, 3, _isOctalDigit),
    _ => start + 1,
  };
}

/// The end of up to [count] digits that pass [test] from [from].
int _digitsEnd(
  TokenScanner s,
  int from,
  int count,
  bool Function(int unit) test,
) {
  final end = s.endWhile(test, from);
  return end - from > count ? from + count : end;
}

bool _isOctalDigit(int unit) => unit >= 0x30 && unit <= 0x37;

bool _isOperator(int unit) => switch (unit) {
  0x21 || 0x25 || 0x26 || 0x2A || 0x2B || 0x2D || 0x2F => true, // ! % & * + - /
  0x3C || 0x3D || 0x3E || 0x5E || 0x7C || 0x7E => true, // < = > ^ | ~
  _ => false,
};

bool _isPunctuation(int unit) => switch (unit) {
  0x28 || 0x29 || 0x2C || 0x2E || 0x3A || 0x3B => true, // ( ) , . : ;
  0x5B || 0x5D || 0x7B || 0x7D => true, // [ ] { }
  _ => false,
};

const _slash = 0x2F;
const _star = 0x2A;
const _quote = 0x27;
const _doubleQuote = 0x22;
const _backtick = 0x60;
const _backslash = 0x5C;
const _dot = 0x2E;
const _colon = 0x3A;
const _equals = 0x3D;
const _openParen = 0x28;
