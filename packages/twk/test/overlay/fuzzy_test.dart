// Fuzzy matching: the characters of a query found in order, ignoring case;
// the score, word starts and characters found side by side counting more;
// the best of the ways to find them; characters as grapheme clusters; a
// fixed list ranked the same way each time.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

/// [texts] that [query] matches, the best first, those that match alike in
/// their order.
List<String> ranked(String query, List<String> texts) {
  final matched = [
    for (final text in texts)
      if (fuzzyMatch(query, text) case final match?) (text, match.score),
  ];
  sortStable(matched, compare: (a, b) => b.$2.compareTo(a.$2));
  return [for (final (text, _) in matched) text];
}

/// Sorts [list] as [compare] says, keeping the order of those alike.
void sortStable<T>(List<T> list, {required int Function(T, T) compare}) {
  final indexed = [for (final (i, e) in list.indexed) (i, e)]
    ..sort((a, b) {
      final c = compare(a.$2, b.$2);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  list.setAll(0, [for (final (_, e) in indexed) e]);
}

void main() {
  test('the characters of the query are found in order, ignoring case, '
      'with gaps; none missing or out of order', () {
    expect(fuzzyMatch('SAVE', 'save'), const FuzzyMatch(24, [0, 1, 2, 3]));
    expect(fuzzyMatch('sv', 'Save'), const FuzzyMatch(9 + 1, [0, 2]));
    expect(fuzzyMatch('x', 'Save'), isNull);
    expect(fuzzyMatch('vs', 'Save'), isNull);
    expect(fuzzyMatch('saves', 'Save'), isNull);
    expect(fuzzyMatch('', 'Save'), const FuzzyMatch(0, []));
    expect(fuzzyMatch('', ''), const FuzzyMatch(0, []));
    expect(fuzzyMatch('s', ''), isNull);
  });

  test('a character scores 1, 8 more at the start of a word and 4 more '
      'right after the one found before it', () {
    // O and f start words
    expect(fuzzyMatch('of', 'Open file'), const FuzzyMatch(18, [0, 5]));
    // o and f side by side
    expect(fuzzyMatch('of', 'Profile'), const FuzzyMatch(6, [2, 3]));
    // after a blank, punctuation, or a small letter for a capital
    expect(fuzzyMatch('f', 'x-file')?.score, 9);
    expect(fuzzyMatch('f', 'x.file')?.score, 9);
    expect(fuzzyMatch('f', 'x/file')?.score, 9);
    expect(fuzzyMatch('f', 'openFile')?.score, 9);
    expect(fuzzyMatch('f', 'OPENFILE')?.score, 1);
    expect(fuzzyMatch('f', 'x2file')?.score, 1);
    // a character beyond ASCII is a letter
    expect(fuzzyMatch('f', 'éfile')?.score, 1);
  });

  test('of the ways the query can be found, the best scores', () {
    // b at the start of a word, not in "cab"
    expect(fuzzyMatch('ab', 'a cab b'), const FuzzyMatch(18, [0, 6]));
    // side by side rather than apart, and apart at a word start rather
    // than side by side
    expect(fuzzyMatch('il', 'mail xl'), const FuzzyMatch(1 + 1 + 4, [2, 3]));
    expect(fuzzyMatch('il', 'mail list'), const FuzzyMatch(1 + 9, [2, 5]));
    // a at a word start and b right after it, not the first a
    expect(fuzzyMatch('ab', 'xa-ab'), const FuzzyMatch(9 + 1 + 4, [3, 4]));
  });

  test('a character is a grapheme cluster, found by its first code point', () {
    // e and a combining acute accent
    expect(fuzzyMatch('e', 'café x'), const FuzzyMatch(1, [3]));
    expect(fuzzyMatch('fx', 'café x'), const FuzzyMatch(1 + 9, [2, 6]));
    // a family of four, one cluster of seven code points (11 code units)
    const family = '\u{1F468}‍\u{1F469}‍\u{1F467}‍\u{1F466}';
    expect(fuzzyMatch('ab', 'a${family}b'), const FuzzyMatch(9 + 1, [0, 12]));
    expect(fuzzyMatch('\u{1F468}', family), const FuzzyMatch(9, [0]));
    // a query of one cluster finds one, of two finds two
    expect(fuzzyMatch('e\u0301', 'cafe\u0301'), const FuzzyMatch(1, [3]));
    expect(fuzzyMatch('\u{1F468}\u{1F469}', family), isNull);
  });

  test('a fixed list ranks the same way each time', () {
    const commands = [
      'Close folder',
      'Search files',
      'Settings',
      'Show diff',
      'Save file',
      'Save all files',
      'saveFile',
    ];
    final first = ranked('sf', commands);
    // 18 each: the initials; 10 each: s inside a word
    expect(first, [
      'Search files',
      'Save file',
      'Save all files',
      'saveFile',
      'Close folder',
      'Show diff',
    ]);
    for (var i = 0; i < 3; i++) {
      expect(ranked('sf', commands), first);
    }
    // the initials (18) before s and a side by side (14), before a apart
    // inside a word (10)
    expect(ranked('sa', commands), [
      'Save all files',
      'Save file',
      'saveFile',
      'Search files',
    ]);
  });

  test('two matches of the same score at the same places are equal, with '
      'equal hashes, and say what they are', () {
    final a = fuzzyMatch('of', 'Open file')!;
    final b = fuzzyMatch('of', 'Open file')!;
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(fuzzyMatch('of', 'Profile')));
    expect(a, isNot(const FuzzyMatch(18, [0])));
    expect('$a', 'FuzzyMatch(18, [0, 5])');
  });
}
