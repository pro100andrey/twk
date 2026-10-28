/// JavaScript and TypeScript.
library;

import '../lexer.dart';
import '../token.dart';

/// JavaScript: keywords, capitalized types, calls, decorators, numbers,
/// `true`, `false`, `null`, `undefined`, `NaN` and `Infinity`, comments,
/// strings with escapes, regular expressions told from division, and
/// template literals with code interpolated in them (`${code}`), which
/// holds templates of its own. Comments in blocks, templates and the code
/// in them go on across lines, and so does a string whose line ends in a
/// backslash. JSX is not told apart: its tags lex as code.
///
/// A `/` starts a regular expression where a value goes, at the start of
/// its line or after an operator, a keyword or punctuation other than a
/// closing bracket, when a `/` closes it on the line; elsewhere it
/// divides.
const javascriptLanguage = Language(
  name: 'javascript',
  aliases: ['js', 'jsx', 'mjs', 'cjs'],
  lexer: _ScriptLexer(typescript: false),
);

/// TypeScript: JavaScript ([javascriptLanguage]) and the keywords and
/// built-in types TypeScript adds.
const typescriptLanguage = Language(
  name: 'typescript',
  aliases: ['ts', 'tsx', 'mts', 'cts'],
  lexer: _ScriptLexer(typescript: true),
);

// The modes of the frames of the state: a block comment; a string its line
// ended in after a backslash, its quote the frame's depth; a template; or
// code interpolated in a template, with as many braces open in it as its
// depth.
const _comment = 0;
const _string = 1;
const _template = 2;
const _interpolation = 3;

final Set<String> _reserved = _words(
  'break case catch class const continue debugger default delete do else '
  'enum export extends finally for function if import in instanceof new '
  'return super switch this throw try typeof var void while with',
);

/// Keywords that are also names: a keyword unless a call or a member.
final Set<String> _contextual = _words(
  'as async await from get let of set static yield',
);

/// What TypeScript adds to [_contextual].
final Set<String> _typescriptContextual = _words(
  'abstract accessor asserts declare implements infer interface is keyof '
  'module namespace out override private protected public readonly '
  'satisfies type unique',
);

/// The built-in types of TypeScript, `void` among them.
final Set<String> _typescriptTypes = _words(
  'any bigint boolean never number object string symbol unknown void',
);

const _constants = {'true', 'false', 'null', 'undefined', 'NaN', 'Infinity'};

/// The words of [text], apart by blanks.
Set<String> _words(String text) => text.split(' ').toSet();

final class _ScriptLexer extends Lexer {
  const _ScriptLexer({required this.typescript});

  final bool typescript;

  @override
  Object? lexLine(TokenScanner s, Object? state) {
    var frame = state as LexFrame?;
    if (frame == null && s.startsWith('#!')) {
      s.emitRest(TokenKind.comment);
      return null;
    }
    final line = _Line(s, typescript);
    while (!s.atEnd) {
      frame = switch (frame?.mode) {
        _comment => line.blockComment(frame!),
        _string => line.string(frame!),
        _template => line.template(frame!),
        _ => line.code(frame),
      };
    }
    // a string in quotes ends with its line, unless a backslash ends it
    if (frame?.mode == _string && !_continues(s.line)) {
      return frame!.outer;
    }
    return frame;
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
  _Line(this.s, this.typescript);

  final TokenScanner s;
  final bool typescript;

  /// Whether a `/` here starts a regular expression.
  var regex = true;

  /// Lexes code, at the top or interpolated in a template ([frame]), up to
  /// where a comment, a string or a template opens or the interpolation
  /// closes, and returns the frame lexing goes on in.
  LexFrame? code(LexFrame? frame) {
    var interpolation = frame;
    while (!s.atEnd) {
      final c = s.current;
      final next = s.peek(1);
      if (TokenScanner.isBlank(c)) {
        s.emit(TokenKind.plain, s.endWhile(TokenScanner.isBlank));
        continue;
      }
      var value = false;
      if (c == _slash && next == _slash) {
        s.emitRest(TokenKind.comment);
        return interpolation;
      } else if (c == _slash && next == _star) {
        s.emitLength(TokenKind.comment, 2);
        return LexFrame(_comment, outer: interpolation);
      } else if (c == _slash && regex && _regexEnd() > 0) {
        s.emit(TokenKind.string, _regexEnd());
        value = true;
      } else if (c == _quote || c == _doubleQuote) {
        s.emitLength(TokenKind.string, 1);
        regex = false;
        return LexFrame(_string, depth: c, outer: interpolation);
      } else if (c == _backtick) {
        s.emitLength(TokenKind.string, 1);
        return LexFrame(_template, outer: interpolation);
      } else if (TokenScanner.isDigit(c) ||
          c == _dot && TokenScanner.isDigit(next)) {
        s.emit(TokenKind.number, s.numberEnd());
        value = true;
      } else if (_isNameStart(c)) {
        value = _name();
      } else if (c == _hash && _isNameStart(next)) {
        s.emit(TokenKind.plain, s.endWhile(_isNamePart, s.pos + 1));
        value = true;
      } else if (c == _at && _isNameStart(next)) {
        s.emit(TokenKind.annotation, _dottedNameEnd(s.pos + 1));
      } else if (c == _openBrace) {
        s.emitLength(TokenKind.punctuation, 1);
        interpolation = interpolation?.withDepth(interpolation.depth + 1);
      } else if (c == _closeBrace) {
        s.emitLength(TokenKind.punctuation, 1);
        value = true;
        if (interpolation != null) {
          if (interpolation.depth == 0) {
            regex = false;
            return interpolation.outer;
          }
          interpolation = interpolation.withDepth(interpolation.depth - 1);
        }
      } else if ((c == _plus || c == _minus) && next == c) {
        // after a value, `++` and `--` end it
        s.emitLength(TokenKind.operator, 2);
        value = !regex;
      } else if (_isOperator(c)) {
        s.emitLength(TokenKind.operator, 1);
      } else if (_isPunctuation(c)) {
        s.emitLength(TokenKind.punctuation, 1);
        value = c == _closeParen || c == _closeBracket;
      } else {
        s.emitLength(TokenKind.plain, 1);
      }
      regex = !value;
    }
    return interpolation;
  }

  /// Emits a name as what it is: a keyword, constant, type, call or other;
  /// whether a value ends with it.
  bool _name() {
    final line = s.line;
    final start = s.pos;
    final end = s.endWhile(_isNamePart);
    final name = line.substring(start, end);
    final member = s.peek(-1) == _dot && s.peek(-2) != _dot;
    final call = end < line.length && line.codeUnitAt(end) == _openParen;
    final kind = switch (name) {
      _ when member => call ? TokenKind.function : _typeOrPlain(name),
      _ when typescript && _typescriptTypes.contains(name) => TokenKind.type,
      _ when _reserved.contains(name) => TokenKind.keyword,
      _ when _constants.contains(name) => TokenKind.constant,
      _ when !call && _contextual.contains(name) => TokenKind.keyword,
      _ when !call && typescript && _typescriptContextual.contains(name) =>
        TokenKind.keyword,
      _ when call && !_capitalized(name) => TokenKind.function,
      _ => _typeOrPlain(name),
    };
    s.emit(kind, end);
    return kind != TokenKind.keyword;
  }

  /// The end of the regular expression at [s]'s position, its flags
  /// included; -1 when no `/` closes it on the line.
  int _regexEnd() {
    final line = s.line;
    var inClass = false;
    for (var i = s.pos + 1; i < line.length; i++) {
      switch (line.codeUnitAt(i)) {
        case _backslash:
          i++;
        case _openBracket:
          inClass = true;
        case _closeBracket:
          inClass = false;
        case _slash when !inClass:
          return s.endWhile(TokenScanner.isIdentifierPart, i + 1);
      }
    }
    return -1;
  }

  /// Lexes the string of [frame] up to its closing quote or the end of the
  /// line, and returns the frame lexing goes on in.
  LexFrame? string(LexFrame frame) {
    final quote = frame.depth;
    while (!s.atEnd) {
      s.emit(
        TokenKind.string,
        s.endWhile((unit) => unit != quote && unit != _backslash),
      );
      if (s.current == quote) {
        s.emitLength(TokenKind.string, 1);
        regex = false;
        return frame.outer;
      }
      if (!s.atEnd) {
        s.emit(TokenKind.escape, _escapeEnd(s));
      }
    }
    return frame;
  }

  /// Lexes the template of [frame] up to where it ends or an interpolation
  /// opens, and returns the frame lexing goes on in.
  LexFrame? template(LexFrame frame) {
    while (!s.atEnd) {
      s.emit(
        TokenKind.string,
        s.endWhile(
          (unit) => unit != _backtick && unit != _backslash && unit != _dollar,
        ),
      );
      final c = s.current;
      if (c == _backtick) {
        s.emitLength(TokenKind.string, 1);
        regex = false;
        return frame.outer;
      } else if (c == _backslash) {
        s.emit(TokenKind.escape, _escapeEnd(s));
      } else if (c == _dollar && s.peek(1) == _openBrace) {
        s.emitLength(TokenKind.punctuation, 2);
        regex = true;
        return LexFrame(_interpolation, outer: frame);
      } else if (c == _dollar) {
        s.emitLength(TokenKind.string, 1);
      }
    }
    return frame;
  }

  /// Lexes the block comment of [frame] up to its end or the end of the
  /// line, and returns the frame lexing goes on in.
  LexFrame? blockComment(LexFrame frame) {
    final close = s.indexOf('*/');
    s.emit(TokenKind.comment, close < 0 ? s.line.length : close + 2);
    return close < 0 ? frame : frame.outer;
  }

  /// The end of a name and the names after it, a dot before each, from
  /// [from]: `a.b.c`.
  int _dottedNameEnd(int from) {
    final line = s.line;
    var end = s.endWhile(_isNamePart, from);
    while (end + 1 < line.length &&
        line.codeUnitAt(end) == _dot &&
        _isNameStart(line.codeUnitAt(end + 1))) {
      end = s.endWhile(_isNamePart, end + 1);
    }
    return end;
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
const _plus = 0x2B;
const _minus = 0x2D;
const _star = 0x2A;
const _quote = 0x27;
const _doubleQuote = 0x22;
const _backtick = 0x60;
const _backslash = 0x5C;
const _dollar = 0x24;
const _dot = 0x2E;
const _at = 0x40;
const _hash = 0x23;
const _openParen = 0x28;
const _closeParen = 0x29;
const _openBracket = 0x5B;
const _closeBracket = 0x5D;
const _openBrace = 0x7B;
const _closeBrace = 0x7D;
const _underscore = 0x5F;
const _u = 0x75;
const _x = 0x78;
