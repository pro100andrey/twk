/// Inline content of paragraphs, headings and table cells: [parseInlines].
library;

import 'entities.dart';
import 'nodes.dart';

/// The inline nodes of [text], the content of a paragraph, heading or table
/// cell with no space or tab at either end.
///
/// After CommonMark's algorithm, with GFM's strikethrough and its links of
/// URLs, `www.` addresses and email addresses in the text. Raw HTML is text.
///
/// Brackets around a label that a definition may have are an [MdReference]
/// whether the document defines the label or not, and leave the brackets
/// around them free to be a link, as an undefined one does in CommonMark.
/// Brackets that leave emphasis in them unmatched, which emphasis around
/// them may match, are one only with a label after them.
List<MdInline> parseInlines(String text) {
  parsedUnits += text.length;
  return _InlineParser(text)._parse();
}

/// The code units [parseInlines] has parsed since the program started: what
/// a test reads to see how much of a document a piece cost.
var parsedUnits = 0;

/// The link reference definition that starts at [start] of [text], the
/// content of a paragraph, and the end of its line; null where none does.
({MdDefinition definition, int end})? parseDefinition(String text, int start) =>
    (_InlineParser(text)..pos = start)._definition();

/// [text] with backslash escapes and character references resolved.
String unescape(String text) {
  if (!text.contains(r'\') && !text.contains('&')) {
    return text;
  }
  final out = StringBuffer();
  var k = 0;
  while (k < text.length) {
    final c = text.codeUnitAt(k);
    if (c == _backslash &&
        k + 1 < text.length &&
        _isEscapable(text.codeUnitAt(k + 1))) {
      out.writeCharCode(text.codeUnitAt(k + 1));
      k += 2;
    } else if (c == _amp) {
      final match = _entity.matchAsPrefix(text, k);
      final decoded = match == null ? null : decodeEntity(match[0]!);
      if (decoded == null) {
        out.writeCharCode(c);
        k++;
      } else {
        out.write(decoded);
        k = match!.end;
      }
    } else {
      out.writeCharCode(c);
      k++;
    }
  }
  return out.toString();
}

const _tab = 0x09;
const _lf = 0x0A;
const _space = 0x20;
const _bang = 0x21;
const _amp = 0x26;
const _lparen = 0x28;
const _rparen = 0x29;
const _star = 0x2A;
const _colon = 0x3A;
const _lt = 0x3C;
const _gt = 0x3E;
const _lbracket = 0x5B;
const _backslash = 0x5C;
const _rbracket = 0x5D;
const _underscore = 0x5F;
const _backtick = 0x60;
const _tilde = 0x7E;

final _entity = RegExp(
  '&(?:#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[A-Za-z][A-Za-z0-9]{1,31});',
);
final _emailAutolink = RegExp(
  r"<([a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9]"
  '(?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
  r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)>',
);
final _uriAutolink = RegExp(
  r'<([A-Za-z][A-Za-z0-9.+-]{1,31}:[^<>\x00-\x20]*)>',
);
final _whitespace = RegExp(r'[\p{Zs}\t\n\f\r]', unicode: true);
final _punctuation = RegExp(r'[\p{P}\p{S}]', unicode: true);

bool _isEscapable(int c) =>
    (c >= 0x21 && c <= 0x2F) ||
    (c >= 0x3A && c <= 0x40) ||
    (c >= 0x5B && c <= 0x60) ||
    (c >= 0x7B && c <= 0x7E);

bool _isWhitespace(int c) => _whitespace.hasMatch(String.fromCharCode(c));

bool _isPunctuation(int c) => _punctuation.hasMatch(String.fromCharCode(c));

bool _isAlnum(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A);

/// Whether [c] may be part of a domain name besides `-`, `_` and `.`.
bool _isHostChar(int c) => !_isWhitespace(c) && !_isPunctuation(c);

enum _Kind {
  text,
  code,
  emphasis,
  strong,
  strikethrough,
  link,
  image,
  reference,
  soft,
  hard,
}

/// A node of the tree the parser builds and rearranges before it turns into
/// [MdInline] values.
final class _Node {
  _Node(this.kind, [this.literal = '']);

  final _Kind kind;
  String literal;
  var destination = '';
  String? title;
  var label = '';
  MdReferenceKind referenceKind = MdReferenceKind.full;
  var image = false;
  _Node? parent;
  _Node? prev;
  _Node? next;
  _Node? first;
  _Node? last;

  void append(_Node child) {
    child
      ..unlink()
      ..parent = this
      ..prev = last;
    if (last == null) {
      first = child;
    } else {
      last!.next = child;
    }
    last = child;
  }

  void insertAfter(_Node sibling) {
    sibling
      ..unlink()
      ..parent = parent
      ..prev = this
      ..next = next;
    if (next == null) {
      parent?.last = sibling;
    } else {
      next!.prev = sibling;
    }
    next = sibling;
  }

  void unlink() {
    if (prev == null) {
      parent?.first = next;
    } else {
      prev!.next = next;
    }
    if (next == null) {
      parent?.last = prev;
    } else {
      next!.prev = prev;
    }
    parent = null;
    prev = null;
    next = null;
  }
}

/// A run of `*`, `_` or `~` that may open or close emphasis.
final class _Delimiter {
  _Delimiter(
    this.char,
    this.count,
    this.node,
    this.prev,
    this.open,
    this.close, [
    int? original,
  ]) : original = original ?? count;

  final int char;
  int count;
  final int original;
  final _Node node;
  _Delimiter? prev;
  _Delimiter? next;
  final bool open;
  final bool close;
}

/// A `[` or `![` that a `]` may close into a link or image.
final class _Bracket {
  _Bracket(
    this.node,
    this.index,
    this.prev,
    this.delimiter, {
    required this.image,
  });

  final _Node node;

  /// Where the `[` is.
  final int index;
  final _Bracket? prev;
  final _Delimiter? delimiter;
  final bool image;
  var active = true;
}

final class _InlineParser {
  _InlineParser(this.s);

  final String s;
  var pos = 0;
  final _root = _Node(_Kind.text);
  _Delimiter? _delimiters;
  _Bracket? _brackets;

  List<MdInline> _parse() {
    while (pos < s.length) {
      switch (s.codeUnitAt(pos)) {
        case _lf:
          _newline();
        case _backslash:
          _escape();
        case _backtick:
          _codeSpan();
        case _star || _underscore || _tilde:
          _delimiterRun();
        case _lbracket:
          pos++;
          _openBracket('[', image: false);
        case _bang:
          pos++;
          if (pos < s.length && s.codeUnitAt(pos) == _lbracket) {
            pos++;
            _openBracket('![', image: true);
          } else {
            _text('!');
          }
        case _rbracket:
          _closeBracket();
        case _lt:
          _autolink();
        case _amp:
          _reference();
        default:
          _plainText();
      }
    }
    _processEmphasis(null);
    return _convert(_root, inLink: false);
  }

  void _text(String text) => _root.append(_Node(_Kind.text, text));

  int _peek(int at) => at < s.length ? s.codeUnitAt(at) : -1;

  void _newline() {
    pos++;
    final last = _root.last;
    if (last != null && last.kind == _Kind.text && last.literal.endsWith(' ')) {
      final hard = last.literal.endsWith('  ');
      var end = last.literal.length;
      while (end > 0 && last.literal.codeUnitAt(end - 1) == _space) {
        end--;
      }
      last.literal = last.literal.substring(0, end);
      _root.append(_Node(hard ? _Kind.hard : _Kind.soft));
    } else {
      _root.append(_Node(_Kind.soft));
    }
    while (_peek(pos) == _space) {
      pos++;
    }
  }

  void _escape() {
    pos++;
    final c = _peek(pos);
    if (c == _lf) {
      pos++;
      _root.append(_Node(_Kind.hard));
    } else if (c >= 0 && _isEscapable(c)) {
      pos++;
      _text(String.fromCharCode(c));
    } else {
      _text(r'\');
    }
  }

  void _codeSpan() {
    final start = pos;
    while (_peek(pos) == _backtick) {
      pos++;
    }
    final ticks = pos - start;
    var k = pos;
    while (k < s.length) {
      if (s.codeUnitAt(k) != _backtick) {
        k++;
        continue;
      }
      final run = k;
      while (k < s.length && s.codeUnitAt(k) == _backtick) {
        k++;
      }
      if (k - run == ticks) {
        var code = s.substring(pos, run).replaceAll('\n', ' ');
        if (code.length > 1 &&
            code.startsWith(' ') &&
            code.endsWith(' ') &&
            code.trim().isNotEmpty) {
          code = code.substring(1, code.length - 1);
        }
        pos = k;
        _root.append(_Node(_Kind.code, code));
        return;
      }
    }
    _text(s.substring(start, pos));
  }

  /// The code point that ends just before [at]; a line feed at the start.
  int _codePointBefore(int at) {
    if (at == 0) {
      return _lf;
    }
    final low = s.codeUnitAt(at - 1);
    if (low >= 0xDC00 && low <= 0xDFFF && at >= 2) {
      final high = s.codeUnitAt(at - 2);
      if (high >= 0xD800 && high <= 0xDBFF) {
        return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
      }
    }
    return low;
  }

  /// The code point that starts at [at]; a line feed at the end.
  int _codePointAt(int at) {
    if (at >= s.length) {
      return _lf;
    }
    final high = s.codeUnitAt(at);
    if (high >= 0xD800 && high <= 0xDBFF && at + 1 < s.length) {
      final low = s.codeUnitAt(at + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) {
        return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
      }
    }
    return high;
  }

  void _delimiterRun() {
    final c = s.codeUnitAt(pos);
    final start = pos;
    while (_peek(pos) == c) {
      pos++;
    }
    final count = pos - start;
    final before = _codePointBefore(start);
    final after = _codePointAt(pos);
    final beforeSpace = _isWhitespace(before);
    final beforePunctuation = _isPunctuation(before);
    final afterSpace = _isWhitespace(after);
    final afterPunctuation = _isPunctuation(after);
    final left =
        !afterSpace && (!afterPunctuation || beforeSpace || beforePunctuation);
    final right =
        !beforeSpace && (!beforePunctuation || afterSpace || afterPunctuation);
    final node = _Node(_Kind.text, s.substring(start, pos));
    _root.append(node);
    if (c == _tilde && count > 2) {
      return;
    }
    final open = c == _underscore
        ? left && (!right || beforePunctuation)
        : left;
    final close = c == _underscore
        ? right && (!left || afterPunctuation)
        : right;
    final delimiter = _Delimiter(c, count, node, _delimiters, open, close);
    _delimiters?.next = delimiter;
    _delimiters = delimiter;
  }

  void _openBracket(String text, {required bool image}) {
    final node = _Node(_Kind.text, text);
    _root.append(node);
    _brackets = _Bracket(node, pos - 1, _brackets, _delimiters, image: image);
  }

  void _closeBracket() {
    pos++;
    final after = pos;
    final opener = _brackets;
    if (opener == null) {
      _text(']');
      return;
    }
    if (!opener.active) {
      _brackets = opener.prev;
      _text(']');
      return;
    }
    var node = _inlineLink(opener);
    if (node == null) {
      pos = after;
      node = _referenceLink(opener);
    }
    _brackets = opener.prev;
    if (node == null) {
      _text(']');
      return;
    }
    var child = opener.node.next;
    while (child != null) {
      final next = child.next;
      node.append(child);
      child = next;
    }
    _root.append(node);
    _processEmphasis(opener.delimiter);
    opener.node.unlink();
    if (node.kind == _Kind.link) {
      for (var b = _brackets; b != null; b = b.prev) {
        if (!b.image) {
          b.active = false;
        }
      }
    }
  }

  /// The link or image of `(destination "title")` at [pos], after the `]`
  /// that closes [opener]; null where none is.
  _Node? _inlineLink(_Bracket opener) {
    if (_peek(pos) != _lparen) {
      return null;
    }
    pos++;
    _skipSpaceAndNewline();
    final destination = _destination();
    if (destination == null) {
      return null;
    }
    final end = pos;
    String? title;
    _skipSpaceAndNewline();
    if (pos > end) {
      title = _title();
      _skipSpaceAndNewline();
    }
    if (_peek(pos) != _rparen) {
      return null;
    }
    pos++;
    return _Node(opener.image ? _Kind.image : _Kind.link)
      ..destination = destination
      ..title = title;
  }

  /// The reference link or image that the `]` before [pos] closes with
  /// [opener]: by a label at [pos], `[]` or nothing that may be one; null
  /// where the label is not one a definition may have, and where nothing
  /// follows brackets that leave emphasis in them unmatched, which emphasis
  /// around them may match when no definition has the label.
  _Node? _referenceLink(_Bracket opener) {
    final length = _labelLength(pos);
    final String label;
    final MdReferenceKind kind;
    if (length > 2) {
      label = s.substring(pos + 1, pos + length - 1);
      kind = MdReferenceKind.full;
    } else if (_labelLength(opener.index) == pos - opener.index) {
      label = s.substring(opener.index + 1, pos - 1);
      kind = length == 2 ? MdReferenceKind.collapsed : MdReferenceKind.shortcut;
    } else {
      return null;
    }
    if (label.trim().isEmpty ||
        (kind == MdReferenceKind.shortcut &&
            _leavesEmphasis(opener.delimiter))) {
      return null;
    }
    pos += length;
    return _Node(_Kind.reference)
      ..label = label
      ..referenceKind = kind
      ..image = opener.image;
  }

  /// The length of the link label at [at], brackets included: at most 999
  /// characters with no bracket a backslash does not escape. 0 where none
  /// is.
  int _labelLength(int at) {
    if (_peek(at) != _lbracket) {
      return 0;
    }
    var k = at + 1;
    while (k < s.length && k - at <= 1000) {
      final c = s.codeUnitAt(k);
      if (c == _backslash && k + 1 < s.length) {
        k += 2;
      } else if (c == _lbracket) {
        return 0;
      } else if (c == _rbracket) {
        return k + 1 - at;
      } else {
        k++;
      }
    }
    return 0;
  }

  /// The link reference definition at [pos] and the end of its line.
  ({MdDefinition definition, int end})? _definition() {
    final start = pos;
    final length = _labelLength(start);
    if (length == 0 || _peek(start + length) != _colon) {
      return null;
    }
    final label = s.substring(start + 1, start + length - 1);
    if (label.trim().isEmpty) {
      return null;
    }
    pos = start + length + 1;
    _skipSpaceAndNewline();
    final destination = _destination();
    if (destination == null) {
      return null;
    }
    final end = pos;
    _skipSpaceAndNewline();
    var title = pos > end ? _title() : null;
    if (title == null || !_lineEnds()) {
      title = null;
      pos = end;
      if (!_lineEnds()) {
        return null;
      }
    }
    return (
      definition: MdDefinition(label, destination, title: title),
      end: pos,
    );
  }

  /// Whether nothing but spaces and tabs follow [pos] on its line; if so,
  /// moves past them and the line ending.
  bool _lineEnds() {
    var k = pos;
    while (_peek(k) == _space || _peek(k) == _tab) {
      k++;
    }
    if (k < s.length && s.codeUnitAt(k) != _lf) {
      return false;
    }
    pos = k < s.length ? k + 1 : k;
    return true;
  }

  void _skipSpaceAndNewline() {
    while (_peek(pos) == _space || _peek(pos) == _tab) {
      pos++;
    }
    if (_peek(pos) == _lf) {
      pos++;
      while (_peek(pos) == _space || _peek(pos) == _tab) {
        pos++;
      }
    }
  }

  String? _destination() {
    if (_peek(pos) == _lt) {
      var k = pos + 1;
      while (k < s.length) {
        final c = s.codeUnitAt(k);
        if (c == _backslash) {
          if (k + 1 < s.length && s.codeUnitAt(k + 1) != _lf) {
            k += 2;
            continue;
          }
          return null;
        }
        if (c == _gt) {
          final destination = unescape(s.substring(pos + 1, k));
          pos = k + 1;
          return destination;
        }
        if (c == _lt || c == _lf) {
          return null;
        }
        k++;
      }
      return null;
    }
    final start = pos;
    var depth = 0;
    var k = pos;
    while (k < s.length) {
      final c = s.codeUnitAt(k);
      if (c == _backslash &&
          k + 1 < s.length &&
          _isEscapable(s.codeUnitAt(k + 1))) {
        k += 2;
      } else if (c == _lparen) {
        depth++;
        k++;
      } else if (c == _rparen) {
        if (depth == 0) {
          break;
        }
        depth--;
        k++;
      } else if (c <= _space || c == 0x7F) {
        break;
      } else {
        k++;
      }
    }
    if ((k == start && _peek(k) != _rparen) || depth != 0) {
      return null;
    }
    pos = k;
    return unescape(s.substring(start, k));
  }

  String? _title() {
    final open = _peek(pos);
    final close = switch (open) {
      0x22 || 0x27 => open,
      _lparen => _rparen,
      _ => -1,
    };
    if (close < 0) {
      return null;
    }
    var k = pos + 1;
    while (k < s.length) {
      final c = s.codeUnitAt(k);
      if (c == _backslash && k + 1 < s.length) {
        k += 2;
      } else if (c == close) {
        final title = unescape(s.substring(pos + 1, k));
        pos = k + 1;
        return title;
      } else if (open == _lparen && c == _lparen) {
        return null;
      } else {
        k++;
      }
    }
    return null;
  }

  void _autolink() {
    final email = _emailAutolink.matchAsPrefix(s, pos);
    final uri = email == null ? _uriAutolink.matchAsPrefix(s, pos) : null;
    final match = email ?? uri;
    if (match == null) {
      pos++;
      _text('<');
      return;
    }
    pos = match.end;
    final text = match[1]!;
    _root.append(
      _Node(_Kind.link)
        ..destination = email == null ? text : 'mailto:$text'
        ..append(_Node(_Kind.text, text)),
    );
  }

  void _reference() {
    final match = _entity.matchAsPrefix(s, pos);
    final decoded = match == null ? null : decodeEntity(match[0]!);
    if (decoded == null) {
      pos++;
      _text('&');
    } else {
      pos = match!.end;
      _text(decoded);
    }
  }

  /// Text up to the next character that may start something else.
  void _plainText() {
    if (_extendedAutolink()) {
      return;
    }
    final start = pos++;
    while (pos < s.length) {
      final c = s.codeUnitAt(pos);
      if (c == _lf ||
          c == _backslash ||
          c == _backtick ||
          c == _star ||
          c == _underscore ||
          c == _tilde ||
          c == _lbracket ||
          c == _bang ||
          c == _rbracket ||
          c == _lt ||
          c == _amp ||
          ((c == 0x77 || c == 0x68 || c == 0x66) && _mayLinkAt(pos))) {
        break;
      }
      pos++;
    }
    _text(s.substring(start, pos));
  }

  /// Whether an extended autolink may start at [at]: at the start of a
  /// line, after whitespace or after `*`, `_`, `~` or `(`.
  bool _mayLinkAt(int at) {
    if (at == 0) {
      return true;
    }
    final c = s.codeUnitAt(at - 1);
    return c == _star ||
        c == _underscore ||
        c == _tilde ||
        c == _lparen ||
        _isWhitespace(c);
  }

  /// Links a `www.` address or an `http://`, `https://` or `ftp://` URL at
  /// [pos], as GFM does; false when none starts there.
  bool _extendedAutolink() {
    if (!_mayLinkAt(pos)) {
      return false;
    }
    final www = s.startsWith('www.', pos);
    var domain = pos;
    if (!www) {
      for (final scheme in const ['http://', 'https://', 'ftp://']) {
        if (s.startsWith(scheme, pos)) {
          domain = pos + scheme.length;
        }
      }
      if (domain == pos) {
        return false;
      }
    }
    final domainEnd = _domain(domain, period: www);
    if (domainEnd < 0) {
      return false;
    }
    var end = domainEnd;
    while (end < s.length &&
        !_isWhitespace(s.codeUnitAt(end)) &&
        s.codeUnitAt(end) != _lt) {
      end++;
    }
    end = _trimAutolink(pos, end);
    if (end <= domain) {
      return false;
    }
    final text = s.substring(pos, end);
    pos = end;
    _root.append(
      _Node(_Kind.link)
        ..destination = www ? 'http://$text' : text
        ..append(_Node(_Kind.text, text)),
    );
    return true;
  }

  /// The end of the domain name that starts at [start]; -1 for none, or for
  /// one with an underscore in its last two labels or, when [period], one
  /// without a period.
  int _domain(int start, {required bool period}) {
    var periods = 0;
    var underscores = 0;
    var lastUnderscores = 0;
    var k = start;
    while (k < s.length) {
      final c = s.codeUnitAt(k);
      if (c == _underscore) {
        lastUnderscores++;
      } else if (c == 0x2E) {
        final next = _peek(k + 1);
        if (next < 0 ||
            !(next == 0x2D || next == _underscore) && !_isHostChar(next)) {
          break;
        }
        periods++;
        underscores = lastUnderscores;
        lastUnderscores = 0;
      } else if (c != 0x2D && !_isHostChar(c)) {
        break;
      }
      k++;
    }
    if (k == start ||
        underscores > 0 ||
        lastUnderscores > 0 ||
        (period && periods == 0)) {
      return -1;
    }
    return k;
  }

  /// The end of an extended autolink from [start] to [until] once trailing
  /// punctuation, unbalanced closing parentheses and what looks like a
  /// character reference are left out.
  int _trimAutolink(int start, int until) {
    var end = until;
    var opening = 0;
    var closing = 0;
    for (var k = start; k < end; k++) {
      final c = s.codeUnitAt(k);
      if (c == _lparen) {
        opening++;
      } else if (c == _rparen) {
        closing++;
      }
    }
    while (end > start) {
      final c = s.codeUnitAt(end - 1);
      if (c == _rparen) {
        if (closing <= opening) {
          return end;
        }
        closing--;
        end--;
      } else if ('''?!.,:*_~'"'''.codeUnits.contains(c)) {
        end--;
      } else if (c == 0x3B) {
        var k = end - 2;
        while (k > start && _isAlnum(s.codeUnitAt(k))) {
          k--;
        }
        end = k < end - 2 && s.codeUnitAt(k) == _amp ? k : end - 1;
      } else {
        return end;
      }
    }
    return end;
  }

  /// Whether emphasis within the brackets that [bottom] is the last
  /// delimiter before leaves a delimiter unmatched that one around them may
  /// match: a closer and an opener before them, or an opener and its
  /// character after [pos].
  bool _leavesEmphasis(_Delimiter? bottom) {
    final top = _delimiters;
    final inside = [
      for (var d = top; d != null && d != bottom; d = d.prev) d,
    ];
    if (!inside.any((d) => d.open || d.close)) {
      return false;
    }
    _Delimiter? copy;
    for (final d in inside.reversed) {
      final next = _Delimiter(
        d.char,
        d.count,
        d.node,
        copy,
        d.open,
        d.close,
        d.original,
      );
      copy?.next = next;
      copy = next;
    }
    final unmatched = <_Delimiter>[];
    _delimiters = copy;
    _processEmphasis(null, unmatched: unmatched);
    _delimiters = top;
    bool opensBefore(int c) {
      for (var d = bottom; d != null; d = d.prev) {
        if (d.char == c && d.open) {
          return true;
        }
      }
      return false;
    }

    return unmatched.any(
      (d) =>
          (d.close && opensBefore(d.char)) ||
          (d.open && s.indexOf(String.fromCharCode(d.char), pos) >= 0),
    );
  }

  /// Matches the delimiters above [bottom] into emphasis, strong emphasis
  /// and strikethrough and removes them. Where [unmatched] is given, the
  /// nodes stay as they are, and the delimiters that may open or close and
  /// are left unmatched are added to it.
  void _processEmphasis(
    _Delimiter? bottom, {
    List<_Delimiter>? unmatched,
  }) {
    final dry = unmatched != null;
    final openersBottom = <int, _Delimiter?>{};
    var closer = _delimiters;
    while (closer != null && closer.prev != bottom) {
      closer = closer.prev;
    }
    while (closer != null) {
      if (!closer.close) {
        closer = closer.next;
        continue;
      }
      final c = closer.char;
      final key = c == _tilde
          ? c * 8 + closer.count
          : c * 8 + (closer.open ? 3 : 0) + closer.original % 3;
      final limit = openersBottom.containsKey(key)
          ? openersBottom[key]
          : bottom;
      var opener = closer.prev;
      var found = false;
      while (opener != null && opener != bottom && opener != limit) {
        final odd =
            c != _tilde &&
            (closer.open || opener.close) &&
            closer.original % 3 != 0 &&
            (opener.original + closer.original) % 3 == 0;
        if (opener.char == c &&
            opener.open &&
            !odd &&
            (c != _tilde || opener.count == closer.count)) {
          found = true;
          break;
        }
        opener = opener.prev;
      }
      final old = closer;
      if (found) {
        closer = _wrap(opener!, closer, dry: dry);
      } else {
        unmatched?.add(closer);
        closer = closer.next;
        openersBottom[key] = old.prev;
        if (!old.open) {
          _remove(old);
        }
      }
    }
    while (_delimiters != null && _delimiters != bottom) {
      if (_delimiters!.open) {
        unmatched?.add(_delimiters!);
      }
      _remove(_delimiters!);
    }
  }

  /// Wraps what lies between [opener] and [closer] into emphasis, strong
  /// emphasis or strikethrough, unless [dry]; the delimiter to go on from.
  _Delimiter? _wrap(
    _Delimiter opener,
    _Delimiter closer, {
    required bool dry,
  }) {
    final c = closer.char;
    final use = c == _tilde
        ? closer.count
        : closer.count >= 2 && opener.count >= 2
        ? 2
        : 1;
    opener.count -= use;
    closer.count -= use;
    final from = opener.node;
    final to = closer.node;
    if (!dry) {
      from.literal = from.literal.substring(0, from.literal.length - use);
      to.literal = to.literal.substring(0, to.literal.length - use);
      final wrapper = _Node(
        c == _tilde
            ? _Kind.strikethrough
            : use == 1
            ? _Kind.emphasis
            : _Kind.strong,
      );
      var child = from.next;
      while (child != null && child != to) {
        final next = child.next;
        wrapper.append(child);
        child = next;
      }
      from.insertAfter(wrapper);
    }
    opener.next = closer;
    closer.prev = opener;
    if (opener.count == 0) {
      if (!dry) {
        from.unlink();
      }
      _remove(opener);
    }
    if (closer.count == 0) {
      if (!dry) {
        to.unlink();
      }
      final next = closer.next;
      _remove(closer);
      return next;
    }
    return closer;
  }

  void _remove(_Delimiter delimiter) {
    delimiter.prev?.next = delimiter.next;
    if (delimiter.next == null) {
      _delimiters = delimiter.prev;
    } else {
      delimiter.next!.prev = delimiter.prev;
    }
  }

  List<MdInline> _convert(_Node parent, {required bool inLink}) {
    final out = <MdInline>[];
    final text = StringBuffer();
    void flush() {
      if (text.isNotEmpty) {
        final string = text.toString();
        text.clear();
        if (inLink) {
          out.add(MdText(string));
        } else {
          out.addAll(linkEmails(string));
        }
      }
    }

    for (var node = parent.first; node != null; node = node.next) {
      if (node.kind == _Kind.text) {
        text.write(node.literal);
        continue;
      }
      flush();
      final link =
          inLink ||
          node.kind == _Kind.link ||
          node.kind == _Kind.image ||
          node.kind == _Kind.reference;
      final children = _convert(node, inLink: link);
      out.add(switch (node.kind) {
        _Kind.code => MdCode(node.literal),
        _Kind.emphasis => MdEmphasis(children),
        _Kind.strong => MdStrong(children),
        _Kind.strikethrough => MdStrikethrough(children),
        _Kind.link => MdLink(node.destination, children, title: node.title),
        _Kind.image => MdImage(node.destination, children, title: node.title),
        _Kind.reference => MdReference(
          node.label,
          children,
          kind: node.referenceKind,
          image: node.image,
        ),
        _Kind.soft => const MdSoftBreak(),
        _Kind.hard => const MdHardBreak(),
        _Kind.text => throw StateError('text is merged'),
      });
    }
    flush();
    return out;
  }
}

/// [text] as text and links of the email addresses in it, as GFM finds
/// them.
List<MdInline> linkEmails(String text) {
  if (!text.contains('@')) {
    return [MdText(text)];
  }
  final out = <MdInline>[];
  var done = 0;
  var at = text.indexOf('@');
  while (at >= 0) {
    var start = at;
    while (start > done) {
      final c = text.codeUnitAt(start - 1);
      if (!_isAlnum(c) && !'.+-_'.codeUnits.contains(c)) {
        break;
      }
      start--;
    }
    var end = at + 1;
    var periods = 0;
    while (end < text.length) {
      final c = text.codeUnitAt(end);
      if (c == 0x2E &&
          end + 1 < text.length &&
          _isAlnum(text.codeUnitAt(end + 1))) {
        periods++;
      } else if (!_isAlnum(c) && c != 0x2D && c != _underscore) {
        break;
      }
      end++;
    }
    // a period is taken only before a letter or digit, so the address
    // never ends in one
    final lastOk = end > at + 1 && _isAlpha(text.codeUnitAt(end - 1));
    if (start < at && periods > 0 && lastOk) {
      if (start > done) {
        out.add(MdText(text.substring(done, start)));
      }
      final address = text.substring(start, end);
      out.add(MdLink('mailto:$address', [MdText(address)]));
      done = end;
    }
    at = text.indexOf('@', at + 1 > done ? at + 1 : done);
  }
  if (done < text.length) {
    out.add(MdText(text.substring(done)));
  }
  return out;
}

bool _isAlpha(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
