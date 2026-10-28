/// Bash and the shells like it.
library;

import '../lexer.dart';
import '../token.dart';

/// Bash: the command of each command line as a function, keywords where
/// a command starts, assignments, variables and parameter expansions,
/// comments, strings in single and double quotes and `$'…'`, escapes,
/// command substitution (`$(…)` and backquotes), arithmetic (`$((…))`,
/// `((…))`), operators and redirections, numbers standing alone, case
/// patterns, and heredocs. Strings, substitutions, arithmetic and heredocs
/// go on across lines.
const bashLanguage = Language(
  name: 'bash',
  aliases: ['sh', 'shell', 'zsh'],
  lexer: _BashLexer(),
);

// The modes of the frames of the state: code in `$(…)`, its depth the
// parentheses open in it; code in backquotes; arithmetic, its depth the
// parentheses open in it; strings in double quotes, single quotes and
// `$'…'`; the body of a heredoc, its text the delimiter and its depth the
// flags below.
const _command = 0;
const _backquote = 1;
const _arithmetic = 2;
const _double = 3;
const _single = 4;
const _ansi = 5;
const _heredoc = 6;

/// A heredoc of `<<-`, whose lines lose their leading tabs.
const _stripTabs = 1;

/// A heredoc whose delimiter is quoted, with nothing expanded in it.
const _literal = 2;

const _keywords = {
  'if', 'then', 'else', 'elif', 'fi', 'case', 'esac', 'for', 'select', //
  'while', 'until', 'do', 'done', 'function', 'time', 'coproc',
};

/// Keywords after which a command starts.
const _commandKeywords = {
  'if',
  'then',
  'else',
  'elif',
  'while',
  'until',
  'do',
  'time',
  'coproc',
};

/// What may follow `\$` as a parameter of its own: a digit or a special
/// parameter.
const _special = r'0123456789@*#?$!-_';

/// A case pattern where a command would start: `a|b)`, `*)`, `(x)`.
final _pattern = RegExp(r'\(?[^\s()|;&<>]*(\s*\|\s*[^\s()|;&<>]*)*\)');

final class _BashLexer extends Lexer {
  const _BashLexer();

  @override
  Object? lexLine(TokenScanner s, Object? state) {
    var frame = state as LexFrame?;
    if (frame == null && s.startsWith('#!')) {
      s.emitRest(TokenKind.comment);
      return null;
    }
    if (frame != null && frame.mode == _heredoc) {
      var end = 0;
      if (frame.depth & _stripTabs != 0) {
        end = s.endWhile((unit) => unit == 0x09);
      }
      if (s.line.length - end == frame.text.length &&
          s.line.startsWith(frame.text, end)) {
        s.emitRest(TokenKind.string);
        return frame.outer;
      }
      if (frame.depth & _literal != 0) {
        s.emitRest(TokenKind.string);
        return frame;
      }
    }
    final line = _Line(s);
    while (!s.atEnd) {
      frame = switch (frame?.mode) {
        _double || _heredoc => line.expanding(frame!),
        _single => line.single(frame!),
        _ansi => line.ansi(frame!),
        _arithmetic => line.arithmetic(frame!),
        _ => line.code(frame),
      };
    }
    final heredoc = line.heredoc;
    return heredoc == null
        ? frame
        : LexFrame(
            _heredoc,
            depth: line.heredocFlags,
            text: heredoc,
            outer: frame,
          );
  }
}

/// A line being lexed and what lexing it has found so far.
final class _Line {
  _Line(this.s);

  final TokenScanner s;

  /// Whether a command starts at the next word.
  var commandStarts = true;

  /// How many frames deep an assignment where a command starts is, whose
  /// value ends at the next blank, where a command starts again; -1 for
  /// none.
  var assignedAt = -1;

  /// Whether the next word names a function (after `function`).
  var nameNext = false;

  /// Whether lexing is inside `[[ … ]]`, where `&&` and `||` start no
  /// command.
  var inTest = false;

  /// Whether an `in` is a keyword (after `for`, `select` or `case`).
  var expectIn = false;

  /// The delimiter of the first heredoc the line opens, if any, and its
  /// flags.
  String? heredoc;
  var heredocFlags = 0;

  /// Lexes code, at the top, in `$(…)` or in backquotes ([frame]), up to
  /// where another frame opens or this one closes, and returns the frame
  /// lexing goes on in.
  LexFrame? code(LexFrame? frame) {
    var current = frame;
    while (!s.atEnd) {
      final c = s.current;
      final next = s.peek(1);
      if (TokenScanner.isBlank(c)) {
        s.emit(TokenKind.plain, s.endWhile(TokenScanner.isBlank));
        if (assignedAt == _depthOf(current)) {
          commandStarts = true;
          assignedAt = -1;
        }
      } else if (c == _hash && _wordStarts(s.peek(-1))) {
        s.emitRest(TokenKind.comment);
      } else if (c == _backslash) {
        _escape();
        commandStarts = false;
      } else if (c == _quote || c == _doubleQuote) {
        s.emitLength(TokenKind.string, 1);
        commandStarts = false;
        return LexFrame(c == _quote ? _single : _double, outer: current);
      } else if (c == _backtick) {
        s.emitLength(TokenKind.punctuation, 1);
        if (current?.mode == _backquote) {
          commandStarts = false;
          return current!.outer;
        }
        commandStarts = true;
        return LexFrame(_backquote, outer: current);
      } else if (c == _dollar) {
        final opened = _dollarFrame(current);
        if (opened != null) {
          return opened;
        }
        commandStarts = false;
      } else if (c == _openParen) {
        if (commandStarts && next == _openParen) {
          s.emitLength(TokenKind.punctuation, 2);
          return LexFrame(_arithmetic, outer: current);
        }
        s.emitLength(TokenKind.punctuation, 1);
        if (current?.mode == _command) {
          current = current!.withDepth(current.depth + 1);
        }
        commandStarts = true;
      } else if (c == _closeParen) {
        s.emitLength(TokenKind.punctuation, 1);
        commandStarts = false;
        if (current?.mode == _command) {
          if (current!.depth == 0) {
            return current.outer;
          }
          current = current.withDepth(current.depth - 1);
        }
      } else if (c == _less && next == _less && s.peek(2) != _less) {
        _heredocStart();
      } else if (c == _less ||
          c == _greater ||
          c == _ampersand && next == _greater) {
        s.emit(TokenKind.operator, s.endWhile(_isRedirection));
      } else if (c == _semicolon || c == _ampersand || c == _bar) {
        s.emit(TokenKind.operator, s.endWhile(_isControl));
        commandStarts = !inTest;
        assignedAt = -1;
      } else if (commandStarts && current == null && _casePattern()) {
        commandStarts = true;
      } else {
        _word(current);
      }
    }
    return current;
  }

  /// Lexes a word: a number, an assignment, a keyword, a command, or
  /// text.
  void _word(LexFrame? frame) {
    final line = s.line;
    final start = s.pos;
    final c = s.current;
    if (TokenScanner.isDigit(c) && _numberStarts(s.peek(-1))) {
      final end = s.endWhile(TokenScanner.isDigit);
      if (end == line.length || _endsWord(line.codeUnitAt(end))) {
        s.emit(TokenKind.number, end);
        commandStarts = false;
        return;
      }
    }
    final nameEnd = s.endWhile(TokenScanner.isIdentifierPart);
    if (nameEnd > start && !TokenScanner.isDigit(c)) {
      final assigns = line.startsWith('=', nameEnd)
          ? 1
          : line.startsWith('+=', nameEnd)
          ? 2
          : 0;
      if (assigns > 0) {
        s
          ..emit(TokenKind.variable, nameEnd)
          ..emitLength(TokenKind.operator, assigns);
        if (commandStarts) {
          assignedAt = _depthOf(frame);
          commandStarts = false;
        }
        return;
      }
    }
    final end = s.endWhile(_inWord);
    final word = line.substring(start, end);
    final whole = end == line.length || _endsWord(line.codeUnitAt(end));
    if (nameNext) {
      nameNext = false;
      s.emit(TokenKind.function, end);
    } else if (expectIn && word == 'in' && whole) {
      expectIn = false;
      s.emit(TokenKind.keyword, end);
    } else if ((word == '{' || word == '}') && whole) {
      s.emit(TokenKind.punctuation, end);
      commandStarts = word == '{';
    } else if ((word == ']' || word == ']]') && whole) {
      s.emit(TokenKind.punctuation, end);
      inTest = false;
    } else if (word == '!' && whole) {
      s.emit(TokenKind.operator, end);
    } else if (!commandStarts) {
      s.emit(TokenKind.plain, end);
    } else if (_keywords.contains(word) && whole) {
      s.emit(TokenKind.keyword, end);
      commandStarts = _commandKeywords.contains(word);
      nameNext = word == 'function';
      expectIn = word == 'for' || word == 'select' || word == 'case';
    } else if ((word == '[' || word == '[[') && whole) {
      s.emit(TokenKind.punctuation, end);
      commandStarts = false;
      inTest = word == '[[';
    } else {
      s.emit(TokenKind.function, end);
      commandStarts = false;
    }
  }

  /// Emits a case pattern where a command would start and returns whether
  /// there is one.
  bool _casePattern() {
    final end = s.match(_pattern);
    if (end < 0) {
      return false;
    }
    while (s.pos < end - 1) {
      final c = s.current;
      if (c == _bar || c == _openParen) {
        s.emitLength(c == _bar ? TokenKind.operator : TokenKind.punctuation, 1);
      } else {
        s.emit(
          TokenKind.plain,
          s.endWhile((unit) => unit != _bar).clamp(s.pos, end - 1),
        );
      }
    }
    s.emitLength(TokenKind.punctuation, 1);
    return true;
  }

  /// Lexes `<<` or `<<-` and the delimiter of the heredoc it opens.
  void _heredocStart() {
    final strip = s.peek(2) == _dash;
    s.emitLength(TokenKind.operator, strip ? 3 : 2);
    s.emit(TokenKind.plain, s.endWhile(TokenScanner.isBlank));
    final start = s.pos;
    final end = s.endWhile(
      (unit) =>
          !TokenScanner.isBlank(unit) &&
          !_isControl(unit) &&
          unit != _less &&
          unit != _greater &&
          unit != _openParen &&
          unit != _closeParen,
    );
    if (end == start) {
      return;
    }
    final word = s.line.substring(start, end);
    final delimiter = word.replaceAll(RegExp(r'''['"\\]'''), '');
    s.emit(TokenKind.string, end);
    if (heredoc == null && delimiter.isNotEmpty) {
      heredoc = delimiter;
      heredocFlags =
          (strip ? _stripTabs : 0) | (word != delimiter ? _literal : 0);
    }
  }

  /// Lexes what starts with `$` at the position: a substitution or
  /// arithmetic that opens a frame above [outer], which it returns, or a
  /// variable, an ANSI-C string or a `$` alone, for which it returns null.
  LexFrame? _dollarFrame(LexFrame? outer) {
    final next = s.peek(1);
    if (next == _openParen && s.peek(2) == _openParen) {
      s.emitLength(TokenKind.punctuation, 3);
      return LexFrame(_arithmetic, outer: outer);
    }
    if (next == _openParen) {
      s.emitLength(TokenKind.punctuation, 2);
      commandStarts = true;
      return LexFrame(_command, outer: outer);
    }
    if (next == _quote && outer?.mode != _double && outer?.mode != _heredoc) {
      s.emitLength(TokenKind.string, 2);
      return LexFrame(_ansi, outer: outer);
    }
    _variable();
    return null;
  }

  /// Emits the variable or parameter expansion at the position, or a `$`
  /// alone as plain.
  void _variable() {
    final line = s.line;
    final next = s.peek(1);
    if (next == _openBrace) {
      var depth = 0;
      var i = s.pos + 1;
      for (; i < line.length; i++) {
        final unit = line.codeUnitAt(i);
        if (unit == _openBrace) {
          depth++;
        } else if (unit == _closeBrace && --depth == 0) {
          break;
        }
      }
      s.emit(TokenKind.variable, i < line.length ? i + 1 : line.length);
    } else if (TokenScanner.isIdentifierStart(next)) {
      s.emit(
        TokenKind.variable,
        s.endWhile(TokenScanner.isIdentifierPart, s.pos + 1),
      );
    } else if (next >= 0 && _special.contains(String.fromCharCode(next))) {
      s.emitLength(TokenKind.variable, 2);
    } else {
      s.emitLength(TokenKind.plain, 1);
    }
  }

  /// Emits a backslash and the character it escapes, or the backslash
  /// alone at the end of the line.
  void _escape() => s.emitLength(TokenKind.escape, s.peek(1) < 0 ? 1 : 2);

  /// Lexes a string in double quotes or the body of a heredoc ([frame]),
  /// with what expands in it, up to where it ends or a substitution opens,
  /// and returns the frame lexing goes on in.
  LexFrame? expanding(LexFrame frame) {
    final quoted = frame.mode == _double;
    while (!s.atEnd) {
      s.emit(
        TokenKind.string,
        s.endWhile(
          (unit) =>
              unit != _backslash &&
              unit != _dollar &&
              unit != _backtick &&
              (!quoted || unit != _doubleQuote),
        ),
      );
      final c = s.current;
      if (c == _doubleQuote) {
        s.emitLength(TokenKind.string, 1);
        return frame.outer;
      } else if (c == _backslash) {
        final next = s.peek(1);
        if (next < 0 ||
            next == _dollar ||
            next == _backtick ||
            next == _backslash ||
            quoted && next == _doubleQuote) {
          _escape();
        } else {
          s.emitLength(TokenKind.string, 2);
        }
      } else if (c == _backtick) {
        s.emitLength(TokenKind.punctuation, 1);
        commandStarts = true;
        return LexFrame(_backquote, outer: frame);
      } else if (c == _dollar) {
        final opened = _dollarFrame(frame);
        if (opened != null) {
          return opened;
        }
      }
    }
    return frame;
  }

  /// Lexes a string in single quotes ([frame]) up to where it ends.
  LexFrame? single(LexFrame frame) {
    final close = s.indexOf("'");
    s.emit(TokenKind.string, close < 0 ? s.line.length : close + 1);
    return close < 0 ? frame : frame.outer;
  }

  /// Lexes a string of `$'…'` ([frame]), with its escapes, up to where it
  /// ends.
  LexFrame? ansi(LexFrame frame) {
    while (!s.atEnd) {
      s.emit(
        TokenKind.string,
        s.endWhile((unit) => unit != _quote && unit != _backslash),
      );
      if (s.current == _quote) {
        s.emitLength(TokenKind.string, 1);
        return frame.outer;
      }
      if (s.current == _backslash) {
        _escape();
      }
    }
    return frame;
  }

  /// Lexes arithmetic ([frame]) up to where it closes or a frame opens in
  /// it, and returns the frame lexing goes on in.
  LexFrame? arithmetic(LexFrame frame) {
    var current = frame;
    while (!s.atEnd) {
      final c = s.current;
      if (TokenScanner.isBlank(c)) {
        s.emit(TokenKind.plain, s.endWhile(TokenScanner.isBlank));
      } else if (TokenScanner.isDigit(c)) {
        s.emit(TokenKind.number, s.numberEnd());
      } else if (TokenScanner.isIdentifierStart(c)) {
        s.emit(TokenKind.variable, s.endWhile(TokenScanner.isIdentifierPart));
      } else if (c == _dollar) {
        final opened = _dollarFrame(current);
        if (opened != null) {
          return opened;
        }
      } else if (c == _openParen) {
        s.emitLength(TokenKind.punctuation, 1);
        current = current.withDepth(current.depth + 1);
      } else if (c == _closeParen) {
        if (current.depth == 0 && s.peek(1) == _closeParen) {
          s.emitLength(TokenKind.punctuation, 2);
          commandStarts = false;
          return current.outer;
        }
        s.emitLength(TokenKind.punctuation, 1);
        if (current.depth > 0) {
          current = current.withDepth(current.depth - 1);
        }
      } else if ('+-*/%<>=!&|^~?:,'.contains(String.fromCharCode(c))) {
        s.emitLength(TokenKind.operator, 1);
      } else {
        s.emitLength(TokenKind.plain, 1);
      }
    }
    return current;
  }
}

/// How many frames [frame] is: 0 for none.
int _depthOf(LexFrame? frame) {
  var depth = 0;
  for (var f = frame; f != null; f = f.outer) {
    depth++;
  }
  return depth;
}

/// Whether a word starts after [unit], for a `#` to start a comment.
bool _wordStarts(int unit) =>
    unit < 0 ||
    TokenScanner.isBlank(unit) ||
    _isControl(unit) ||
    unit == _openParen ||
    unit == _closeParen ||
    unit == _backtick;

/// Whether a number may start after [unit].
bool _numberStarts(int unit) =>
    _wordStarts(unit) || unit == _less || unit == _greater || unit == 0x3D;

/// Whether [unit] ends a word.
bool _endsWord(int unit) =>
    TokenScanner.isBlank(unit) ||
    _isControl(unit) ||
    unit == _less ||
    unit == _greater ||
    unit == _openParen ||
    unit == _closeParen ||
    unit == _backtick;

/// Whether [unit] goes on a word lexed as one token.
bool _inWord(int unit) =>
    !_endsWord(unit) &&
    unit != _quote &&
    unit != _doubleQuote &&
    unit != _backslash &&
    unit != _dollar;

bool _isControl(int unit) =>
    unit == _semicolon || unit == _ampersand || unit == _bar;

bool _isRedirection(int unit) =>
    unit == _less || unit == _greater || unit == _ampersand;

const _hash = 0x23;
const _backslash = 0x5C;
const _quote = 0x27;
const _doubleQuote = 0x22;
const _backtick = 0x60;
const _dollar = 0x24;
const _openParen = 0x28;
const _closeParen = 0x29;
const _openBrace = 0x7B;
const _closeBrace = 0x7D;
const _less = 0x3C;
const _greater = 0x3E;
const _ampersand = 0x26;
const _semicolon = 0x3B;
const _bar = 0x7C;
const _dash = 0x2D;
