// diffLists: the changes between two lists, the fewest (as the longest
// common subsequence counts them, on random lists), the items only one
// list has set aside, still right past the bound of its search, and on
// long lists; and the changes as values.
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

/// How many items [changes] remove and add, once it is checked that they
/// make [a] into [b]: in order, each changing something, apart by items
/// both keep, equal and as many on both sides.
int edits<T>(List<T> a, List<T> b, List<DiffChange> changes) {
  var i = 0;
  var j = 0;
  var count = 0;
  for (final (k, c) in changes.indexed) {
    expect(c.oldStart - i, c.newStart - j, reason: 'kept before change $k');
    expect(c.oldStart > i || k == 0, isTrue, reason: 'change $k apart');
    expect(c.oldEnd > c.oldStart || c.newEnd > c.newStart, isTrue);
    expect(a.sublist(i, c.oldStart), b.sublist(j, c.newStart));
    count += c.oldEnd - c.oldStart + c.newEnd - c.newStart;
    i = c.oldEnd;
    j = c.newEnd;
  }
  expect(a.sublist(i), b.sublist(j), reason: 'kept after the last change');
  return count;
}

/// The fewest items removed and added that make [a] into [b]: those not
/// in a longest common subsequence.
int fewest<T>(List<T> a, List<T> b) {
  var row = List.filled(b.length + 1, 0);
  for (final x in a) {
    final next = List.filled(b.length + 1, 0);
    for (var j = 0; j < b.length; j++) {
      next[j + 1] = x == b[j] ? row[j] + 1 : max(next[j], row[j + 1]);
    }
    row = next;
  }
  return a.length + b.length - 2 * row[b.length];
}

List<int> randomList(Random random, int length, int kinds) => [
  for (var i = 0; i < length; i++) random.nextInt(kinds),
];

void main() {
  test('finds nothing between lists that are equal', () {
    expect(diffLists(<int>[], <int>[]), isEmpty);
    expect(diffLists([1, 2, 3], [1, 2, 3]), isEmpty);
  });

  test('finds what one list removes, adds and replaces', () {
    expect(diffLists([1, 2, 3], [1, 3]), [const DiffChange(1, 2, 1, 1)]);
    expect(diffLists([1, 3], [1, 2, 3]), [const DiffChange(1, 1, 1, 2)]);
    expect(diffLists(<int>[], [1, 2]), [const DiffChange(0, 0, 0, 2)]);
    expect(diffLists([1, 2], <int>[]), [const DiffChange(0, 2, 0, 0)]);
    expect(diffLists([1, 2, 3], [4, 2, 5]), [
      const DiffChange(0, 1, 0, 1),
      const DiffChange(2, 3, 2, 3),
    ]);
    expect(diffLists('abc'.split(''), 'xyz'.split('')), [
      const DiffChange(0, 3, 0, 3),
    ]);
  });

  test("finds the fewest edits of Myers' example", () {
    final a = 'abcabba'.split('');
    final b = 'cbabac'.split('');
    expect(edits(a, b, diffLists(a, b)), 5);
  });

  test('finds the fewest edits between random lists', () {
    final random = Random(1);
    for (var round = 0; round < 3000; round++) {
      final kinds = 2 + round % 5;
      final a = randomList(random, random.nextInt(40), kinds);
      final b = random.nextBool()
          ? randomList(random, random.nextInt(40), kinds)
          : [
              for (final x in a)
                if (random.nextInt(4) > 0)
                  x
                else if (random.nextBool())
                  random.nextInt(kinds),
            ];
      final reason = '$a → $b';
      expect(
        edits(a, b, diffLists(a, b)),
        fewest(a, b),
        reason: reason,
      );
    }
  });

  test('finds the fewest edits where items only one list has stand '
      'between those both have', () {
    final a = ['x', 'a', 'y', 'b', 'c', 'z', 'a'];
    final b = ['a', 'p', 'b', 'q', 'a', 'c'];
    expect(edits(a, b, diffLists(a, b)), fewest(a, b));
    expect(diffLists(['x', 'y'], ['p', 'q', 'r']), [
      const DiffChange(0, 2, 0, 3),
    ]);
  });

  test('past maxCost still makes one list into the other, with more '
      'edits than the fewest', () {
    final random = Random(2);
    var more = 0;
    for (var round = 0; round < 500; round++) {
      final a = randomList(random, random.nextInt(200), 3);
      final b = randomList(random, random.nextInt(200), 3);
      final found = edits(a, b, diffLists(a, b, maxCost: 1));
      expect(found, greaterThanOrEqualTo(fewest(a, b)));
      if (found > fewest(a, b)) {
        more++;
      }
    }
    expect(more, greaterThan(0));
  });

  test('makes long lists into each other', () {
    final random = Random(3);
    final a = [for (var i = 0; i < 50000; i++) 'line ${random.nextInt(500)}'];
    // a line in 50 replaced, one in 50 of the rest removed
    var made = 0;
    final b = <String>[];
    for (final line in a) {
      if (random.nextInt(50) == 0) {
        b.add('line ${random.nextInt(500)}');
        made += 2;
      } else if (random.nextInt(50) == 0) {
        made++;
      } else {
        b.add(line);
      }
    }
    expect(edits(a, b, diffLists(a, b)), lessThanOrEqualTo(made));

    final other = [for (var i = 0; i < 50000; i++) 'other $i'];
    expect(diffLists(a, other), [const DiffChange(0, 50000, 0, 50000)]);
  });

  test('changes are equal by their ranges, hash alike and show them', () {
    DiffChange change(int at) => DiffChange(at, at + 1, at, at + 2);
    expect(change(2), change(2));
    expect(change(2).hashCode, change(2).hashCode);
    expect(change(2), isNot(change(3)));
    expect(change(2), isNot(const DiffChange(2, 3, 2, 3)));
    expect('${change(2)}', 'DiffChange(2, 3, 2, 4)');
  });
}
