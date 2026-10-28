/// Fuzzy matching: [fuzzyMatch] finds the characters of a query in a text
/// in order, with gaps, and scores how well they fall.
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show ClusterScan, TextSegmenter;

/// How the characters of a query fall in a text ([fuzzyMatch]): its
/// [score], the higher the better, and the [positions] they are at.
@immutable
final class FuzzyMatch {
  /// A match of [score] at [positions].
  const FuzzyMatch(this.score, this.positions);

  /// How well the characters fall: the sum of what each scores, the higher
  /// the better; 0 for an empty query.
  final int score;

  /// Where in the text each character of the query is: the offset its
  /// grapheme cluster starts at, in order.
  final List<int> positions;

  @override
  bool operator ==(Object other) {
    if (other is! FuzzyMatch ||
        other.score != score ||
        other.positions.length != positions.length) {
      return false;
    }
    for (var i = 0; i < positions.length; i++) {
      if (other.positions[i] != positions[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(score, Object.hashAll(positions));

  @override
  String toString() => 'FuzzyMatch($score, $positions)';
}

/// How [query] matches [text]: each character of [query] found in [text],
/// in order and with any gaps, ignoring case; null when they are not all
/// there. An empty query matches any text, with a score of 0.
///
/// A character is a grapheme cluster, and two are alike when their first
/// code points are in lower case: `e` finds `é` written as `e` and a
/// combining accent. Of the ways the characters can be found, the match is
/// the one with the highest score, the sum of what each character found
/// scores:
///
/// * 1 for the character;
/// * 8 more where it starts a word: the first character of the text, one
///   after a blank or an ASCII punctuation mark, or a capital after a small
///   letter (`openFile`);
/// * 4 more where it comes right after the character found before it.
///
/// So `of` scores 1 + 8 + 1 + 8 = 18 in `Open file` and 1 + 1 + 4 = 6 in
/// `Profile`, and the first wins. Ways that score alike are told apart the
/// same way each time: the match is the same for the same query and text.
///
/// The commands that match what is typed, the best first:
///
/// ```dart
/// final commands = ['Open file', 'Profile', 'Close'];
/// final matches = [
///   for (final c in commands)
///     if (fuzzyMatch('of', c) case final m?) (c, m),
/// ]..sort((a, b) => b.$2.score - a.$2.score);
/// // matches: Open file (18), Profile (6)
/// ```
FuzzyMatch? fuzzyMatch(String query, String text) {
  if (query.isEmpty) {
    return const FuzzyMatch(0, []);
  }
  final q = _Clusters(query);
  final t = _Clusters(text);
  final m = q.length;
  final n = t.length;
  if (m > n) {
    return null;
  }
  // best[j]: the best score with the characters of the query so far found,
  // the last at character j of the text; from[i * n + j]: where the one
  // before it is then
  const none = -1;
  var best = List.filled(n, none);
  var next = List.filled(n, none);
  final from = List.filled(m * n, none);
  for (var j = 0; j < n; j++) {
    if (t.keys[j] == q.keys[0]) {
      best[j] = 1 + _bonus(t, j);
    }
  }
  for (var i = 1; i < m; i++) {
    // the best of best[0 .. j - 2], and where it is
    var most = none;
    var mostAt = none;
    next.fillRange(0, n, none);
    for (var j = 1; j < n; j++) {
      if (j >= 2 && best[j - 2] > most) {
        most = best[j - 2];
        mostAt = j - 2;
      }
      if (t.keys[j] != q.keys[i]) {
        continue;
      }
      final apart = most;
      final right = best[j - 1] == none ? none : best[j - 1] + _adjacent;
      if (apart == none && right == none) {
        continue;
      }
      final before = right >= apart ? j - 1 : mostAt;
      next[j] = 1 + _bonus(t, j) + (right >= apart ? right : apart);
      from[i * n + j] = before;
    }
    final swap = best;
    best = next;
    next = swap;
  }
  var end = none;
  for (var j = 0; j < n; j++) {
    if (best[j] != none && (end == none || best[j] > best[end])) {
      end = j;
    }
  }
  if (end == none) {
    return null;
  }
  final positions = List.filled(m, 0);
  for (var i = m - 1, j = end; i >= 0; i--) {
    positions[i] = t.starts[j];
    j = from[i * n + j];
  }
  return FuzzyMatch(best[end], List.unmodifiable(positions));
}

// what a character of the query scores more where it starts a word of the
// text, and where it comes right after the one found before it
const _wordStart = 8;
const _adjacent = 4;

int _bonus(_Clusters t, int j) {
  if (j == 0) {
    return _wordStart;
  }
  final before = t.firsts[j - 1];
  final at = t.firsts[j];
  final separated = before < 0x80 && !_isAsciiAlnum(before);
  final camel = _isLower(before) && _isUpper(at);
  return separated || camel ? _wordStart : 0;
}

bool _isAsciiAlnum(int c) =>
    c >= 0x30 && c <= 0x39 || _isUpper(c) || _isLower(c);

bool _isUpper(int c) => c >= 0x41 && c <= 0x5A;

bool _isLower(int c) => c >= 0x61 && c <= 0x7A;

/// The grapheme clusters of a text: where each starts, its first code
/// point, and that in lower case, by which clusters are alike.
final class _Clusters {
  _Clusters(String text) {
    final scan = ClusterScan();
    for (var i = 0; i < text.length; i = scan.end) {
      _segmenter.scan(text, i, scan);
      starts.add(i);
      firsts.add(scan.first);
      keys.add(_lower(scan.first));
    }
  }

  static final _segmenter = TextSegmenter();

  final starts = <int>[];
  final firsts = <int>[];
  final keys = <int>[];

  int get length => starts.length;

  static int _lower(int c) {
    if (c < 0x80) {
      return _isUpper(c) ? c + 0x20 : c;
    }
    return String.fromCharCode(c).toLowerCase().runes.first;
  }
}
