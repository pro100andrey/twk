/// Python.
library;

import '../lexer.dart';
import '../token.dart';

/// Python: keywords, `match`, `case` and `type` where they start a
/// statement, built-in and capitalized types, functions where `def`
/// declares them and where they are called, decorators, numbers, `True`,
/// `False` and `None`, comments, and strings with their prefixes (`r`,
/// `b`, `u`, `f`, `t` and their pairs), one quote or three long, with
/// escapes unless raw, and in f-strings and t-strings fields of code
/// (`{code!r:>{width}}`) with format specs. Strings three quotes long and
/// the fields in them go on across lines, and so does a string whose line
/// ends in a backslash.
const pythonLanguage = Language(
  name: 'python',
  aliases: ['py', 'py3', 'python3'],
  lexer: _PythonLexer(),
);

// The modes of the frames of the state: a string with the flags below in
// its depth; the code of a field of an f-string, with as many brackets
// open in it as its depth; or the format spec of a field.
const _string = 0;
const _field = 1;
const _spec = 2;

const _double = 1;
const _triple = 2;
const _raw = 4;
const _format = 8;

final Set<String> _reserved = _words(
  'and as assert async await break class continue def del elif else except '
  'finally for from global if import in is lambda nonlocal not or pass '
  'raise return try while with yield',
);

/// The prefixes of strings, in lower case, and their flags.
const Map<String, int> _prefixes = {
  'r': _raw, 'u': 0, 'b': 0, 'f': _format, 't': _format, 'br': _raw, //
  'rb': _raw, 'fr': _raw | _format, 'rf': _raw | _format,
  'tr': _raw | _format, 'rt': _raw | _format,
};

/// Keywords only where they start a statement: `match x:`, `type X = …`.
const _soft = {'match', 'case', 'type'};

/// Keywords after which `match`, `case` and `type` are names.
const _notAfterSoft = {'and', 'else', 'if', 'in', 'is', 'or'};

const _constants = {'True', 'False', 'None'};

final Set<String> _types = _words(
  'bool bytearray bytes complex dict float frozenset int list memoryview '
  'object range set slice str tuple type',
);

/// The words of [text], apart by blanks.
Set<String> _words(String text) => text.split(' ').toSet();

final class _PythonLexer extends Lexer {
  const _PythonLexer();

  @override
  Object? lexLine(TokenScanner s, Object? state) {
    var frame = state as LexFrame?;
    final line = _Line(s);
    while (!s.atEnd) {
      frame = switch (frame?.mode) {
        _string => line.string(frame!),
        _spec => line.spec(frame!),
        _ => line.code(frame),
      };
    }
    // a string one quote long ends with its line, and what is in it,
    // unless a backslash in it ends the line
    var carried = frame;
    for (var f = frame; f != null; f = f.outer) {
      if (f.mode == _string &&
          f.depth & _triple == 0 &&
          !(identical(f, frame) && _continues(s.line))) {
        carried = f.outer;
      }
    }
    return carried;
  }
}

/// Whether [line] ends in a backslash that escapes its line break.
bool _continues(String line) {
  var i = line.length;
  while (i > 0 && line.codeUnitAt(i - 1) == _backslash) {
    i--;
  }
  return (line.length - i).isOdd;
}

/// A line being lexed and what lexing it has found so far.
final class _Line {
  _Line(this.s);

  final TokenScanner s;

  /// What `def` or `class` declares, if the next token is a name.
  TokenKind? declared;

  /// Lexes code, at the top or in a field of an f-string ([frame]), up to
  /// where a string or a format spec opens or the field closes, and
  /// returns the frame lexing goes on in.
  LexFrame? code(LexFrame? frame) {
    var field = frame;
    while (!s.atEnd) {
      final c = s.current;
      final next = s.peek(1);
      if (TokenScanner.isBlank(c)) {
        s.emit(TokenKind.plain, s.endWhile(TokenScanner.isBlank));
        continue;
      }
      final declares = declared;
      declared = null;
      if (c == _hash) {
        s.emitRest(TokenKind.comment);
      } else if (c == _quote || c == _doubleQuote) {
        return _openString(0, 0, field);
      } else if (TokenScanner.isDigit(c) ||
          c == _dot && TokenScanner.isDigit(next)) {
        s.emit(TokenKind.number, s.numberEnd());
      } else if (TokenScanner.isIdentifierStart(c)) {
        final opened = _name(field, declares);
        if (opened != null) {
          return opened;
        }
      } else if (c == _at &&
          field == null &&
          s.endWhile(TokenScanner.isBlank, 0) == s.pos &&
          TokenScanner.isIdentifierStart(next)) {
        s.emit(TokenKind.annotation, _dottedNameEnd(s.pos + 1));
      } else if (c == _colon && next == _equals) {
        s.emitLength(TokenKind.operator, 2);
      } else if (c == _colon && field != null && field.depth == 0) {
        s.emitLength(TokenKind.punctuation, 1);
        return LexFrame(_spec, outer: field.outer);
      } else if (c == _openParen || c == _openBracket || c == _openBrace) {
        s.emitLength(TokenKind.punctuation, 1);
        field = field?.withDepth(field.depth + 1);
      } else if (c == _closeParen || c == _closeBracket || c == _closeBrace) {
        s.emitLength(TokenKind.punctuation, 1);
        if (field != null) {
          if (field.depth == 0 && c == _closeBrace) {
            return field.outer;
          }
          field = field.withDepth(field.depth > 0 ? field.depth - 1 : 0);
        }
      } else if (_isOperator(c)) {
        s.emitLength(TokenKind.operator, 1);
      } else if (_isPunctuation(c)) {
        s.emitLength(TokenKind.punctuation, 1);
      } else {
        s.emitLength(TokenKind.plain, 1);
      }
    }
    return field;
  }

  /// Emits a name as what it is, as [declares] says when `def` or `class`
  /// is before it; or, when it prefixes a string, opens the string and
  /// returns its frame, above [field].
  LexFrame? _name(LexFrame? field, TokenKind? declares) {
    final line = s.line;
    final start = s.pos;
    final end = s.endWhile(TokenScanner.isIdentifierPart);
    final name = line.substring(start, end);
    final after = end < line.length ? line.codeUnitAt(end) : -1;
    if (after == _quote || after == _doubleQuote) {
      final flags = _prefixes[name.toLowerCase()];
      if (flags != null) {
        return _openString(name.length, flags, field);
      }
    }
    final member = s.peek(-1) == _dot;
    final call = after == _openParen;
    s.emit(switch (name) {
      _ when member => call ? TokenKind.function : _typeOrPlain(name),
      _ when _reserved.contains(name) => TokenKind.keyword,
      _ when declares != null => declares,
      _ when _constants.contains(name) => TokenKind.constant,
      _ when _soft.contains(name) && _startsStatement(field, start, end) =>
        TokenKind.keyword,
      _ when _types.contains(name) => TokenKind.type,
      _ when call && !_capitalized(name) => TokenKind.function,
      _ => _typeOrPlain(name),
    }, end);
    if (!member) {
      declared = switch (name) {
        'def' => TokenKind.function,
        'class' => TokenKind.type,
        _ => null,
      };
    }
    return null;
  }

  /// Whether the soft keyword from [start] to [end] starts a statement: it
  /// is the first word of its line, at the top, and a blank and an operand
  /// follow it.
  bool _startsStatement(LexFrame? field, int start, int end) {
    if (field != null || s.endWhile(TokenScanner.isBlank, 0) != start) {
      return false;
    }
    final line = s.line;
    final operand = s.endWhile(TokenScanner.isBlank, end);
    if (operand == end || operand >= line.length) {
      return false;
    }
    final c = line.codeUnitAt(operand);
    if (TokenScanner.isIdentifierStart(c)) {
      final word = line.substring(
        operand,
        s.endWhile(TokenScanner.isIdentifierPart, operand),
      );
      return !_notAfterSoft.contains(word);
    }
    return TokenScanner.isDigit(c) ||
        c == _quote ||
        c == _doubleQuote ||
        c == _openParen ||
        c == _openBracket ||
        c == _openBrace ||
        c == _minus;
  }

  /// Emits the opening of a string with [prefix] code units of prefix
  /// before its quotes and returns its frame, with [flags] and above
  /// [outer].
  LexFrame _openString(int prefix, int flags, LexFrame? outer) {
    final quote = s.peek(prefix);
    final triple = s.peek(prefix + 1) == quote && s.peek(prefix + 2) == quote;
    s.emitLength(TokenKind.string, prefix + (triple ? 3 : 1));
    return LexFrame(
      _string,
      depth:
          flags |
          (quote == _doubleQuote ? _double : 0) |
          (triple ? _triple : 0),
      outer: outer,
    );
  }

  /// Lexes the inside of the string of [frame] up to where it ends or a
  /// field opens, and returns the frame lexing goes on in.
  LexFrame? string(LexFrame frame) {
    final quote = frame.depth & _double != 0 ? _doubleQuote : _quote;
    final triple = frame.depth & _triple != 0;
    final raw = frame.depth & _raw != 0;
    final format = frame.depth & _format != 0;
    while (!s.atEnd) {
      s.emit(
        TokenKind.string,
        s.endWhile(
          (unit) =>
              unit != quote &&
              unit != _backslash &&
              (!format || unit != _openBrace && unit != _closeBrace),
        ),
      );
      final c = s.current;
      final next = s.peek(1);
      if (c == quote) {
        if (!triple || next == quote && s.peek(2) == quote) {
          s.emitLength(TokenKind.string, triple ? 3 : 1);
          return frame.outer;
        }
        s.emitLength(TokenKind.string, 1);
      } else if (c == _backslash) {
        if (raw) {
          // a backslash keeps a quote from ending a raw string
          s.emitLength(TokenKind.string, next < 0 ? 1 : 2);
        } else {
          s.emit(TokenKind.escape, _escapeEnd());
        }
      } else if (c == _openBrace && next == _openBrace ||
          c == _closeBrace && next == _closeBrace) {
        s.emitLength(TokenKind.escape, 2);
      } else if (c == _openBrace) {
        s.emitLength(TokenKind.punctuation, 1);
        return LexFrame(_field, outer: frame);
      } else if (c == _closeBrace) {
        s.emitLength(TokenKind.string, 1);
      }
    }
    return frame;
  }

  /// Lexes the format spec of [frame] up to where it ends or a field opens
  /// in it, and returns the frame lexing goes on in.
  LexFrame? spec(LexFrame frame) {
    s.emit(
      TokenKind.string,
      s.endWhile((unit) => unit != _openBrace && unit != _closeBrace),
    );
    if (s.atEnd) {
      return frame;
    }
    s.emitLength(TokenKind.punctuation, 1);
    return s.peek(-1) == _openBrace
        ? LexFrame(_field, outer: frame)
        : frame.outer;
  }

  /// The end of the escape sequence at [s]'s position: `\xHH`, `\uHHHH`,
  /// `\UHHHHHHHH`, `\N{name}`, up to three octal digits, or a backslash
  /// and the character after it.
  int _escapeEnd() {
    final start = s.pos + 1;
    switch (s.peek(1)) {
      case -1:
        return start;
      case 0x78: // x
        return _digitsEnd(start + 1, 2, TokenScanner.isHexDigit);
      case 0x75: // u
        return _digitsEnd(start + 1, 4, TokenScanner.isHexDigit);
      case 0x55: // U
        return _digitsEnd(start + 1, 8, TokenScanner.isHexDigit);
      case 0x4E when s.peek(2) == _openBrace: // N{
        final close = s.line.indexOf('}', start);
        return close < 0 ? s.line.length : close + 1;
      case >= 0x30 && <= 0x37:
        return _digitsEnd(start, 3, (unit) => unit >= 0x30 && unit <= 0x37);
    }
    return start + 1;
  }

  /// The end of up to [count] digits that pass [test] from [from].
  int _digitsEnd(int from, int count, bool Function(int unit) test) {
    final end = s.endWhile(test, from);
    return end - from > count ? from + count : end;
  }

  /// The end of a name and the names after it, a dot before each, from
  /// [from]: `a.b.c`.
  int _dottedNameEnd(int from) {
    final line = s.line;
    var end = s.endWhile(TokenScanner.isIdentifierPart, from);
    while (end + 1 < line.length &&
        line.codeUnitAt(end) == _dot &&
        TokenScanner.isIdentifierStart(line.codeUnitAt(end + 1))) {
      end = s.endWhile(TokenScanner.isIdentifierPart, end + 1);
    }
    return end;
  }
}

TokenKind _typeOrPlain(String name) =>
    _capitalized(name) ? TokenKind.type : TokenKind.plain;

/// Whether [name] starts with a capital after its `_`s.
bool _capitalized(String name) {
  for (var i = 0; i < name.length; i++) {
    final unit = name.codeUnitAt(i);
    if (unit != 0x5F) {
      return unit >= 0x41 && unit <= 0x5A;
    }
  }
  return false;
}

bool _isOperator(int unit) => switch (unit) {
  0x21 || 0x25 || 0x26 || 0x2A || 0x2B || 0x2D || 0x2F => true, // ! % & * + - /
  0x3C || 0x3D || 0x3E || 0x40 || 0x5E || 0x7C || 0x7E => true, // < = > @ ^ | ~
  _ => false,
};

bool _isPunctuation(int unit) => switch (unit) {
  0x2C || 0x2E || 0x3A || 0x3B => true, // , . : ;
  _ => false,
};

const _quote = 0x27;
const _doubleQuote = 0x22;
const _backslash = 0x5C;
const _hash = 0x23;
const _dot = 0x2E;
const _at = 0x40;
const _colon = 0x3A;
const _equals = 0x3D;
const _minus = 0x2D;
const _openParen = 0x28;
const _closeParen = 0x29;
const _openBracket = 0x5B;
const _closeBracket = 0x5D;
const _openBrace = 0x7B;
const _closeBrace = 0x7D;
