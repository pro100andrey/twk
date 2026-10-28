/// Rust.
library;

import '../lexer.dart';
import '../token.dart';

/// Rust: keywords, primitive and capitalized types, functions where `fn`
/// declares them and where they are called, macros (`println!`),
/// attributes (`#[derive`), lifetimes and labels as types (`'a`), macro
/// variables (`$x`), numbers with their suffixes, `true` and `false`,
/// comments, block comments that nest, characters and byte characters,
/// and strings (`"…"`, `b"…"`, `c"…"`) with escapes, and raw ones
/// (`r#"…"#`) without. Block comments and strings go on across lines.
const rustLanguage = Language(
  name: 'rust',
  aliases: ['rs'],
  lexer: _RustLexer(),
);

// The modes of the frames of the state: a block comment as deep as the
// frame's depth, a string, or a raw string with as many hashes around it
// as the frame's depth.
const _comment = 0;
const _string = 1;
const _raw = 2;

final Set<String> _keywords = _words(
  'as async await break const continue crate dyn else enum extern fn for '
  'if impl in let loop match mod move mut pub ref return self static '
  'struct super trait type unsafe use where while abstract become box do '
  'final gen macro override priv try typeof unsized virtual yield',
);

final Set<String> _types = _words(
  'bool char str i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 '
  'f64',
);

/// The words of [text], apart by blanks.
Set<String> _words(String text) => text.split(' ').toSet();

final class _RustLexer extends Lexer {
  const _RustLexer();

  @override
  Object? lexLine(TokenScanner s, Object? state) {
    var frame = state as LexFrame?;
    if (frame == null && s.startsWith('#!') && !s.startsWith('#![')) {
      s.emitRest(TokenKind.comment);
      return null;
    }
    final line = _Line(s);
    while (!s.atEnd) {
      frame = switch (frame?.mode) {
        _comment => line.blockComment(frame!),
        _string => line.string(frame!),
        _raw => line.raw(frame!),
        _ => line.code(),
      };
    }
    return frame;
  }
}

/// A line being lexed and what lexing it has found so far.
final class _Line {
  _Line(this.s);

  final TokenScanner s;

  /// What `fn`, `struct` and the like declare, if the next token is a
  /// name.
  TokenKind? declared;

  /// Lexes code up to where a comment or a string opens, and returns the
  /// frame lexing goes on in.
  LexFrame? code() {
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
        return const LexFrame(_comment, depth: 1);
      } else if (c == _doubleQuote) {
        s.emitLength(TokenKind.string, 1);
        return const LexFrame(_string);
      } else if (c == _quote) {
        _character(0);
      } else if (TokenScanner.isDigit(c)) {
        s.emit(TokenKind.number, s.numberEnd());
      } else if (TokenScanner.isIdentifierStart(c)) {
        final opened = _name(declares);
        if (opened != null) {
          return opened;
        }
      } else if (c == _hash &&
          (next == _openBracket ||
              next == _bang && s.peek(2) == _openBracket)) {
        s.emit(
          TokenKind.annotation,
          s.endWhile(
            (unit) => TokenScanner.isIdentifierPart(unit) || unit == _colon,
            s.pos + (next == _bang ? 3 : 2),
          ),
        );
      } else if (c == _dollar && TokenScanner.isIdentifierStart(next)) {
        s.emit(
          TokenKind.variable,
          s.endWhile(TokenScanner.isIdentifierPart, s.pos + 1),
        );
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

  /// Emits a name as what it is, as [declares] says when `fn` or the like
  /// is before it; or, when it prefixes a string, opens the string and
  /// returns its frame.
  LexFrame? _name(TokenKind? declares) {
    final line = s.line;
    final start = s.pos;
    final end = s.endWhile(TokenScanner.isIdentifierPart);
    final name = line.substring(start, end);
    final after = end < line.length ? line.codeUnitAt(end) : -1;
    if (name == 'r' || name == 'br' || name == 'cr') {
      final hashes = s.endWhile((unit) => unit == _hash, end) - end;
      if (s.peek(end - start + hashes) == _doubleQuote) {
        s.emitLength(TokenKind.string, end - start + hashes + 1);
        return LexFrame(_raw, depth: hashes);
      }
      if (name == 'r' &&
          hashes == 1 &&
          TokenScanner.isIdentifierStart(s.peek(2))) {
        // a raw identifier: r#type
        s.emit(
          TokenKind.plain,
          s.endWhile(TokenScanner.isIdentifierPart, end + 1),
        );
        return null;
      }
    }
    if ((name == 'b' || name == 'c') && after == _doubleQuote) {
      s.emitLength(TokenKind.string, 2);
      return const LexFrame(_string);
    }
    if (name == 'b' && after == _quote) {
      _character(1);
      return null;
    }
    if (after == _bang && s.peek(end - start + 1) != _equals) {
      s.emit(TokenKind.function, end + 1);
      return null;
    }
    final member = s.peek(-1) == _dot && s.peek(-2) != _dot;
    final call = after == _openParen;
    s.emit(switch (name) {
      _ when member => call ? TokenKind.function : _typeOrPlain(name),
      _ when _keywords.contains(name) => TokenKind.keyword,
      _ when declares != null => declares,
      'true' || 'false' => TokenKind.constant,
      _ when _types.contains(name) => TokenKind.type,
      _ when call && !_capitalized(name) => TokenKind.function,
      _ => _typeOrPlain(name),
    }, end);
    if (!member) {
      declared = switch (name) {
        'fn' => TokenKind.function,
        'enum' || 'struct' || 'trait' || 'type' || 'union' => TokenKind.type,
        _ => null,
      };
    }
    return null;
  }

  /// Emits what a quote [prefix] code units on starts: a character, its
  /// prefix (`b`) included, a lifetime or a label, or the quote alone.
  void _character(int prefix) {
    final line = s.line;
    final open = s.pos + prefix;
    if (s.peek(prefix + 1) == _backslash) {
      s.emitLength(TokenKind.string, prefix + 1);
      final end = _escapeEnd(s);
      if (end < line.length && line.codeUnitAt(end) == _quote) {
        s
          ..emit(TokenKind.escape, end)
          ..emitLength(TokenKind.string, 1);
      }
      return;
    }
    final length = _characterLength(line, open + 1);
    final close = open + 1 + length;
    if (length > 0 && close < line.length && line.codeUnitAt(close) == _quote) {
      s.emit(TokenKind.string, close + 1);
    } else if (prefix == 0 && TokenScanner.isIdentifierStart(s.peek(1))) {
      s.emit(
        TokenKind.type,
        s.endWhile(TokenScanner.isIdentifierPart, open + 1),
      );
    } else {
      s.emitLength(TokenKind.plain, prefix + 1);
    }
  }

  /// Lexes the inside of the string of [frame] up to where it ends, and
  /// returns the frame lexing goes on in.
  LexFrame? string(LexFrame frame) {
    while (!s.atEnd) {
      s.emit(
        TokenKind.string,
        s.endWhile((unit) => unit != _doubleQuote && unit != _backslash),
      );
      if (s.current == _doubleQuote) {
        s.emitLength(TokenKind.string, 1);
        return null;
      }
      if (!s.atEnd) {
        s.emit(TokenKind.escape, _escapeEnd(s));
      }
    }
    return frame;
  }

  /// Lexes the inside of the raw string of [frame] up to a quote and as
  /// many hashes as opened it, and returns the frame lexing goes on in.
  LexFrame? raw(LexFrame frame) {
    final line = s.line;
    for (var i = s.indexOf('"'); i >= 0; i = line.indexOf('"', i + 1)) {
      final end = i + 1 + frame.depth;
      if (s.endWhile((unit) => unit == _hash, i + 1) >= end) {
        s.emit(TokenKind.string, end);
        return null;
      }
    }
    s.emitRest(TokenKind.string);
    return frame;
  }

  /// Lexes the block comment of [frame], counting the comments nested in
  /// it, and returns the frame lexing goes on in.
  LexFrame? blockComment(LexFrame frame) {
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
          return null;
        }
      } else {
        i++;
      }
    }
    s.emit(TokenKind.comment, i);
    return frame.withDepth(depth);
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

/// The end of the escape sequence at [s]'s position: `\xHH`, `\u{H…}`, or
/// a backslash and the character after it.
int _escapeEnd(TokenScanner s) {
  final start = s.pos + 1;
  switch (s.peek(1)) {
    case -1:
      return start;
    case 0x78: // x
      final end = s.endWhile(TokenScanner.isHexDigit, start + 1);
      return end - start - 1 > 2 ? start + 3 : end;
    case 0x75 when s.peek(2) == _openBrace: // u{
      final close = s.line.indexOf('}', start);
      return close < 0 ? s.line.length : close + 1;
  }
  return start + 1;
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
  0x3C || 0x3D || 0x3E || 0x3F || 0x40 || 0x5E || 0x7C => true, // < = > ? @ ^ |
  0x7E => true, // ~
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
const _backslash = 0x5C;
const _dollar = 0x24;
const _dot = 0x2E;
const _hash = 0x23;
const _bang = 0x21;
const _colon = 0x3A;
const _equals = 0x3D;
const _openParen = 0x28;
const _openBracket = 0x5B;
const _openBrace = 0x7B;
