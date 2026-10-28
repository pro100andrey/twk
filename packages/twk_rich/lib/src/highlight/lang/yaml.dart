/// YAML.
library;

import '../lexer.dart';
import '../token.dart';

/// YAML: keys, plain scalars as numbers, constants (`true`, `false`,
/// `null`, `~`, as YAML 1.2 has them) or strings, quoted scalars with
/// their escapes, comments, the indicators of sequences, mappings, flow
/// collections and block scalars, anchors and aliases, tags, directives
/// and document markers. Block scalars (the lines indented more than the
/// key or `-` before their `|` or `>`), quoted scalars and flow
/// collections go on across lines.
const yamlLanguage = Language(
  name: 'yaml',
  aliases: ['yml'],
  lexer: _YamlLexer(),
);

// The modes of the state: a block scalar, its depth the indent of the
// node it belongs to; a flow collection, its depth how deep collections
// nest; a scalar in single or double quotes, its depth that of the flow
// collections it is in.
const _block = 0;
const _flow = 1;
const _single = 2;
const _double = 3;

final _number = RegExp(
  r'^([-+]?(\d[\d_]*(\.\d*)?|\.\d+)([eE][-+]?\d+)?|0x[\da-fA-F_]+|0o[0-7_]+'
  r'|[-+]?\.(inf|Inf|INF)|\.(nan|NaN|NAN))$',
);

const _constants = {
  'true', 'True', 'TRUE', 'false', 'False', 'FALSE', //
  'null', 'Null', 'NULL', '~',
};

final class _YamlLexer extends Lexer {
  const _YamlLexer();

  @override
  Object? lexLine(TokenScanner s, Object? state) {
    final frame = state as LexFrame?;
    final line = s.line;
    var flow = 0;
    switch (frame?.mode) {
      case _block when !_documentMarker(s):
        if (s.endWhile(TokenScanner.isBlank) == line.length ||
            s.endWhile(_isSpace) > frame!.depth) {
          s
            ..emit(TokenKind.plain, s.endWhile(_isSpace))
            ..emitRest(TokenKind.string);
          return frame;
        }
      case _flow:
        flow = frame!.depth;
      case _single || _double:
        flow = frame!.depth;
        final quote = frame.mode == _double ? _doubleQuote : _quote;
        if (!_quoted(
          s,
          quote,
          _closing(line, s.pos, quote),
          TokenKind.string,
        )) {
          return frame;
        }
    }
    if (flow == 0 && s.pos == 0) {
      if (s.current == _percent) {
        s.emit(TokenKind.annotation, _valueEnd(s, s.pos, 0));
      } else if (_documentMarker(s)) {
        s.emitLength(TokenKind.punctuation, 3);
      }
    }
    var keyAllowed = s.pos == 0;
    var blockScalar = false;
    // the indent of the node a block scalar here belongs to: the column of
    // the last key or `-` before it
    var node = -1;
    while (!s.atEnd) {
      final c = s.current;
      final next = s.peek(1);
      if (TokenScanner.isBlank(c)) {
        s.emit(TokenKind.plain, s.endWhile(TokenScanner.isBlank));
      } else if (c == _hash &&
          (s.pos == 0 || TokenScanner.isBlank(s.peek(-1)))) {
        s.emitRest(TokenKind.comment);
      } else if (flow == 0 &&
          (c == _dash || c == _question) &&
          keyAllowed &&
          _endsNode(next)) {
        node = s.pos;
        s.emitLength(TokenKind.punctuation, 1);
      } else if (flow == 0 &&
          (c == _bar || c == _greater) &&
          _blockIndicator(s)) {
        blockScalar = true;
      } else if (c == _openBracket || c == _openBrace) {
        flow++;
        keyAllowed = true;
        s.emitLength(TokenKind.punctuation, 1);
      } else if (flow > 0 && (c == _closeBracket || c == _closeBrace)) {
        flow--;
        keyAllowed = false;
        s.emitLength(TokenKind.punctuation, 1);
      } else if (flow > 0 && c == _comma) {
        keyAllowed = true;
        s.emitLength(TokenKind.punctuation, 1);
      } else if (c == _colon && (flow > 0 || _endsNode(next))) {
        keyAllowed = false;
        s.emitLength(TokenKind.punctuation, 1);
      } else if (c == _ampersand || c == _star) {
        s.emit(
          TokenKind.variable,
          s.endWhile((unit) => _inProperty(unit, flow)),
        );
      } else if (c == _bang) {
        s.emit(TokenKind.type, s.endWhile((unit) => _inProperty(unit, flow)));
      } else if (c == _quote || c == _doubleQuote) {
        final close = _closing(line, s.pos + 1, c);
        final key = keyAllowed && close >= 0 && _colonAt(s, close + 1);
        if (key) {
          node = s.pos;
        }
        s.emitLength(key ? TokenKind.key : TokenKind.string, 1);
        if (!_quoted(s, c, close, key ? TokenKind.key : TokenKind.string)) {
          return LexFrame(c == _doubleQuote ? _double : _single, depth: flow);
        }
      } else {
        final colon = keyAllowed ? _keyColon(s, flow) : -1;
        if (colon >= 0) {
          node = s.pos;
          s.emit(TokenKind.key, _trimmed(s, colon));
        } else {
          final end = _valueEnd(s, s.pos, flow);
          s.emit(_scalarKind(line.substring(s.pos, end)), end);
        }
      }
    }
    if (blockScalar) {
      return LexFrame(_block, depth: node);
    }
    return flow > 0 ? LexFrame(_flow, depth: flow) : null;
  }
}

/// Whether [s] is at the start of a line that is `---` or `...`, alone or
/// before a blank.
bool _documentMarker(TokenScanner s) =>
    s.pos == 0 &&
    (s.startsWith('---') || s.startsWith('...')) &&
    (s.line.length == 3 || TokenScanner.isBlank(s.line.codeUnitAt(3)));

/// Emits the indicator of a block scalar at [s]'s position, `|` or `>`
/// with its indentation and chomping indicators, and returns whether there
/// is one there.
bool _blockIndicator(TokenScanner s) {
  final end = s.endWhile(
    (unit) => unit == _plus || unit == _dash || TokenScanner.isDigit(unit),
    s.pos + 1,
  );
  if (end < s.line.length && !TokenScanner.isBlank(s.line.codeUnitAt(end))) {
    return false;
  }
  s.emit(TokenKind.punctuation, end);
  return true;
}

/// Emits the rest of a quoted scalar from [s]'s position to its closing
/// quote at [close], or to the end of the line when [close] is -1, as
/// [kind], its escapes apart, and returns whether it closed.
bool _quoted(TokenScanner s, int quote, int close, TokenKind kind) {
  final end = close < 0 ? s.line.length : close + 1;
  while (s.pos < end) {
    final c = s.current;
    if (quote == _doubleQuote && c == _backslash) {
      final length = switch (s.peek(1)) {
        0x78 => 4, // \xHH
        0x75 => 6, // \uHHHH
        0x55 => 10, // \UHHHHHHHH
        _ => 2,
      };
      s.emit(TokenKind.escape, s.pos + length > end ? end : s.pos + length);
    } else if (quote == _quote && c == _quote && s.pos + 1 < end) {
      s.emitLength(TokenKind.escape, 2);
    } else {
      // up to the next quote or escape
      var i = s.pos + 1;
      while (i < end &&
          s.line.codeUnitAt(i) != quote &&
          (quote != _doubleQuote || s.line.codeUnitAt(i) != _backslash)) {
        i++;
      }
      s.emit(kind, i);
    }
  }
  return close >= 0;
}

/// The index of the quote that closes a scalar in [quote]s whose text goes
/// on from [from] in [line]; -1 when it does not close on the line.
int _closing(String line, int from, int quote) {
  var i = from;
  while (i < line.length) {
    final c = line.codeUnitAt(i);
    if (quote == _doubleQuote && c == _backslash) {
      i += 2;
    } else if (c == quote) {
      if (quote == _quote &&
          i + 1 < line.length &&
          line.codeUnitAt(i + 1) == _quote) {
        i += 2;
      } else {
        return i;
      }
    } else {
      i++;
    }
  }
  return -1;
}

/// Whether a `:` that makes what ends at [from] a key follows [from],
/// after blanks.
bool _colonAt(TokenScanner s, int from) {
  final i = s.endWhile(TokenScanner.isBlank, from);
  return i < s.line.length && s.line.codeUnitAt(i) == _colon;
}

/// Where the `:` after the plain key at [s]'s position is; -1 when the
/// plain scalar there is not a key.
int _keyColon(TokenScanner s, int flow) {
  final line = s.line;
  for (var i = s.pos; i < line.length; i++) {
    final c = line.codeUnitAt(i);
    if (c == _hash &&
        i > s.pos &&
        TokenScanner.isBlank(line.codeUnitAt(i - 1))) {
      return -1;
    }
    if (c == _colon) {
      final next = i + 1 < line.length ? line.codeUnitAt(i + 1) : -1;
      if (_endsNode(next) || flow > 0 && _isFlowIndicator(next)) {
        return i;
      }
    }
    if (flow > 0 && _isFlowIndicator(c)) {
      return -1;
    }
  }
  return -1;
}

/// The end of the plain scalar from [from], its trailing blanks left out:
/// it ends before a comment, and in a flow collection at a flow
/// indicator.
int _valueEnd(TokenScanner s, int from, int flow) {
  final line = s.line;
  var i = from;
  while (i < line.length) {
    final c = line.codeUnitAt(i);
    if (c == _hash &&
        i > from &&
        TokenScanner.isBlank(line.codeUnitAt(i - 1))) {
      break;
    }
    if (flow > 0 &&
        (_isFlowIndicator(c) ||
            c == _colon &&
                i + 1 < line.length &&
                TokenScanner.isBlank(line.codeUnitAt(i + 1)))) {
      break;
    }
    i++;
  }
  return _trimmed(s, i);
}

/// [end] moved back over the blanks before it, down to [s]'s position.
int _trimmed(TokenScanner s, int end) {
  var i = end;
  while (i > s.pos && TokenScanner.isBlank(s.line.codeUnitAt(i - 1))) {
    i--;
  }
  return i;
}

TokenKind _scalarKind(String text) => _constants.contains(text)
    ? TokenKind.constant
    : _number.hasMatch(text)
    ? TokenKind.number
    : TokenKind.string;

bool _endsNode(int unit) => unit == -1 || TokenScanner.isBlank(unit);

bool _isSpace(int unit) => unit == 0x20;

bool _isFlowIndicator(int unit) =>
    unit == _comma ||
    unit == _openBracket ||
    unit == _closeBracket ||
    unit == _openBrace ||
    unit == _closeBrace;

/// Whether [unit] goes on an anchor, alias or tag.
bool _inProperty(int unit, int flow) =>
    !TokenScanner.isBlank(unit) && !(flow > 0 && _isFlowIndicator(unit));

const _quote = 0x27;
const _doubleQuote = 0x22;
const _backslash = 0x5C;
const _hash = 0x23;
const _percent = 0x25;
const _dash = 0x2D;
const _plus = 0x2B;
const _question = 0x3F;
const _colon = 0x3A;
const _comma = 0x2C;
const _bar = 0x7C;
const _greater = 0x3E;
const _ampersand = 0x26;
const _star = 0x2A;
const _bang = 0x21;
const _openBracket = 0x5B;
const _closeBracket = 0x5D;
const _openBrace = 0x7B;
const _closeBrace = 0x7D;
