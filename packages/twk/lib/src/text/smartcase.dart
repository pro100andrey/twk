/// [Smartcase]: text searched for as vim's smartcase searches, ignoring
/// the case while what is searched for is all in lower case.
library;

import 'dart:typed_data' show Uint16List;

/// A search for [pattern] as vim's smartcase searches: ignoring the case
/// while [pattern] is all in lower case ([ignoresCase]), heeding it
/// otherwise. Made once for a pattern and used for every text searched,
/// it makes no lower-cased copy of a text: each code unit of the text is
/// compared in lower case as it is reached, and what it finds is an
/// offset in the text as it is.
///
/// A letter whose lower case is not one letter of as many code units (on
/// the web, `İ`, whose lower case is `i` and a combining dot) is compared
/// as it is, which keeps the offsets of the text's: the rest of such a
/// text still ignores the case.
///
/// ```dart
/// final search = Smartcase('readme');
/// assert(search.isIn('README.md') && search.indexIn('a Readme') == 2);
/// assert(!Smartcase('README').isIn('readme.md'));
/// ```
final class Smartcase {
  /// A search for [pattern], ignoring the case if it is all in lower case.
  Smartcase(this.pattern) : ignoresCase = pattern == pattern.toLowerCase();

  /// What is searched for.
  final String pattern;

  /// Whether the case of the text is ignored: while [pattern] is all in
  /// lower case.
  final bool ignoresCase;

  /// Where [pattern] is in [text] from [start] on, an offset in [text]; -1
  /// when it is not there. An empty [pattern] is at [start].
  int indexIn(String text, [int start = 0]) {
    if (!ignoresCase) {
      return text.indexOf(pattern, start);
    }
    RangeError.checkValueInInterval(start, 0, text.length, 'start');
    final p = pattern;
    final m = p.length;
    if (m == 0) {
      return start;
    }
    final first = p.codeUnitAt(0);
    final end = text.length - m;
    outer:
    for (var i = start; i <= end; i++) {
      if (_lowerAt(text, i) != first) {
        continue;
      }
      for (var j = 1; j < m; j++) {
        if (_lowerAt(text, i + j) != p.codeUnitAt(j)) {
          continue outer;
        }
      }
      return i;
    }
    return -1;
  }

  /// Whether [pattern] is in [text].
  bool isIn(String text) => indexIn(text) >= 0;

  /// `Smartcase(pattern)`.
  @override
  String toString() => 'Smartcase($pattern)';

  /// The code unit at [k] of [text] in lower case: of the letter it is,
  /// or, a half of a surrogate pair, the same half of the pair's.
  static int _lowerAt(String text, int k) {
    final u = text.codeUnitAt(k);
    if (u < 0x80) {
      return u >= 0x41 && u <= 0x5A ? u | 0x20 : u;
    }
    if (u & 0xF800 != 0xD800) {
      return _lowerUnit(u);
    }
    if (u < 0xDC00) {
      if (k + 1 < text.length) {
        final low = text.codeUnitAt(k + 1);
        if (low & 0xFC00 == 0xDC00) {
          return 0xD7C0 + (_lowerAstral(_codePoint(u, low)) >> 10);
        }
      }
      return u;
    }
    if (k > 0) {
      final high = text.codeUnitAt(k - 1);
      if (high & 0xFC00 == 0xD800) {
        return 0xDC00 | (_lowerAstral(_codePoint(high, u)) & 0x3FF);
      }
    }
    return u;
  }

  static int _codePoint(int high, int low) =>
      0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);

  // the lower case of each code unit from 0x80 on that is no surrogate,
  // found as first asked for: 0 not yet
  static Uint16List? _units;

  static int _lowerUnit(int u) {
    final units = _units ??= Uint16List(0x10000);
    final known = units[u];
    if (known != 0) {
      return known;
    }
    final lower = String.fromCharCode(u).toLowerCase();
    return units[u] = lower.length == 1 ? lower.codeUnitAt(0) : u;
  }

  // the lower case of each code point past 0xFFFF asked for
  static final _astral = <int, int>{};

  static int _lowerAstral(int c) {
    if (_astral[c] case final known?) {
      return known;
    }
    final lower = String.fromCharCode(c).toLowerCase();
    final one = lower.length == 2 && lower.runes.length == 1;
    return _astral[c] = one ? lower.runes.first : c;
  }
}
