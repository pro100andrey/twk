/// The words a changed line changed: [changedWords].
library;

import 'myers.dart';

/// Where two versions of a line differ, word by word: the ranges of code
/// units, (start, end) in order, of [before] and of [after] that the
/// fewest words removed and added ([diffLists]) take out of one and put
/// into the other. A word is a run of letters, digits and `_` (any
/// character outside ASCII counting as a letter), a run of blanks, or any
/// other character alone.
///
/// Null when the lines have too little in common for the ranges to help:
/// when the characters other than blanks the two keep are fewer than
/// 40 % of those they have.
(List<(int, int)>, List<(int, int)>)? changedWords(
  String before,
  String after,
) {
  final wordsBefore = _words(before);
  final wordsAfter = _words(after);
  final changes = diffLists(wordsBefore, wordsAfter);
  final rangesBefore = <(int, int)>[];
  final rangesAfter = <(int, int)>[];
  // the characters other than blanks each line has, and those of them it
  // changes
  var changed = 0;
  for (final c in changes) {
    if (c.oldEnd > c.oldStart) {
      final range = _range(before, wordsBefore, c.oldStart, c.oldEnd);
      rangesBefore.add(range);
      changed += _filled(before, range);
    }
    if (c.newEnd > c.newStart) {
      final range = _range(after, wordsAfter, c.newStart, c.newEnd);
      rangesAfter.add(range);
      changed += _filled(after, range);
    }
  }
  final filled =
      _filled(before, (0, before.length)) + _filled(after, (0, after.length));
  // kept / filled < 40 %
  if (filled > 0 && (filled - changed) * 5 < filled * 2) {
    return null;
  }
  return (rangesBefore, rangesAfter);
}

/// The words of [line], in order: runs of letters, digits and `_`, runs
/// of blanks, and the other characters one by one.
List<String> _words(String line) {
  final words = <String>[];
  var i = 0;
  while (i < line.length) {
    final start = i;
    final kind = _kindOf(line.codeUnitAt(i++));
    if (kind != _other) {
      while (i < line.length && _kindOf(line.codeUnitAt(i)) == kind) {
        i++;
      }
    }
    words.add(line.substring(start, i));
  }
  return words;
}

/// The code units of [line] that the words from [from] up to [to] of
/// [words], its words, take.
(int, int) _range(String line, List<String> words, int from, int to) {
  var start = 0;
  for (var k = 0; k < from; k++) {
    start += words[k].length;
  }
  var end = start;
  for (var k = from; k < to; k++) {
    end += words[k].length;
  }
  return (start, end);
}

/// How many code units of [range] of [line] are not blanks.
int _filled(String line, (int, int) range) {
  var count = 0;
  for (var i = range.$1; i < range.$2; i++) {
    if (_kindOf(line.codeUnitAt(i)) != _blank) {
      count++;
    }
  }
  return count;
}

const _letter = 0;
const _blank = 1;
const _other = 2;

/// Whether [unit] is part of a word of letters, of blanks, or neither.
int _kindOf(int unit) {
  if (unit == 0x20 || unit == 0x09) {
    return _blank;
  }
  if (unit >= 0x80 ||
      unit == 0x5F ||
      (unit >= 0x30 && unit <= 0x39) ||
      ((unit | 0x20) >= 0x61 && (unit | 0x20) <= 0x7A)) {
    return _letter;
  }
  return _other;
}
