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
/// 40 % of those they have. Null too for lines of more than 20000 words
/// between them (some 40000 characters of code): two such lines with
/// little in common take a diff of their words far longer than a frame
/// (two random lines of 3.7 million characters, a minute), and the line is
/// shown changed whole instead.
(List<(int, int)>, List<(int, int)>)? changedWords(
  String before,
  String after,
) {
  final wordsBefore = _words(before, _maxWords);
  final wordsAfter = wordsBefore == null
      ? null
      : _words(after, _maxWords - wordsBefore.length);
  if (wordsBefore == null || wordsAfter == null) {
    return null;
  }
  final changes = diffLists(wordsBefore, wordsAfter);
  final startsBefore = _starts(wordsBefore);
  final startsAfter = _starts(wordsAfter);
  final rangesBefore = <(int, int)>[];
  final rangesAfter = <(int, int)>[];
  // the characters other than blanks each line has, and those of them it
  // changes
  var changed = 0;
  for (final c in changes) {
    if (c.oldEnd > c.oldStart) {
      final range = (startsBefore[c.oldStart], startsBefore[c.oldEnd]);
      rangesBefore.add(range);
      changed += _filled(before, range);
    }
    if (c.newEnd > c.newStart) {
      final range = (startsAfter[c.newStart], startsAfter[c.newEnd]);
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

/// The most words two lines have between them for a diff of their words.
const _maxWords = 20000;

/// The words of [line], in order: runs of letters, digits and `_`, runs
/// of blanks, and the other characters one by one; null once there are
/// more than [most].
List<String>? _words(String line, int most) {
  final words = <String>[];
  var i = 0;
  while (i < line.length) {
    if (words.length == most) {
      return null;
    }
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

/// Where each of [words], the words of a line, starts in it, and then
/// where the line ends.
List<int> _starts(List<String> words) {
  final starts = List.filled(words.length + 1, 0);
  for (var k = 0; k < words.length; k++) {
    starts[k + 1] = starts[k] + words[k].length;
  }
  return starts;
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
