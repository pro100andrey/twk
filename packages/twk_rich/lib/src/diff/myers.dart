/// Where two lists differ: [diffLists] and the [DiffChange]s it finds.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// A change from one list to another: the items from [oldStart] up to
/// [oldEnd] of the old list replaced by those from [newStart] up to
/// [newEnd] of the new one. Either range may be empty.
final class DiffChange {
  /// The items from [oldStart] up to [oldEnd] replaced by those from
  /// [newStart] up to [newEnd].
  const DiffChange(this.oldStart, this.oldEnd, this.newStart, this.newEnd);

  /// The index of the first item of the old list the change replaces.
  final int oldStart;

  /// The index after the last item of the old list the change replaces;
  /// [oldStart] where it replaces none, adding items only.
  final int oldEnd;

  /// The index of the first item of the new list the change puts in.
  final int newStart;

  /// The index after the last item of the new list the change puts in;
  /// [newStart] where it puts in none, removing items only.
  final int newEnd;

  @override
  bool operator ==(Object other) =>
      other is DiffChange &&
      other.oldStart == oldStart &&
      other.oldEnd == oldEnd &&
      other.newStart == newStart &&
      other.newEnd == newEnd;

  @override
  int get hashCode => Object.hash(oldStart, oldEnd, newStart, newEnd);

  @override
  String toString() => 'DiffChange($oldStart, $oldEnd, $newStart, $newEnd)';
}

/// The changes that make [a] into [b], in order, apart by at least one
/// item both keep; items are equal by `==` and `hashCode`.
///
/// They are those of a shortest edit script, the fewest items removed and
/// added, found by Myers' algorithm in linear space: O((N+M)·D) time and
/// O(N+M) memory for lists of N and M items that D edits tell apart,
/// after the head and the tail they share, and the items only one of them
/// has, are set aside. The search for where the edits divide gives up
/// after [maxCost] edits, by default the larger of 256 and the square root
/// of N+M, and divides them at the point it got furthest to, as GNU diff
/// and git do: past that bound the changes still make [a] into [b], the
/// items kept equal and in order, but may remove and add more than the
/// fewest, and each such division costs O((N+M)·[maxCost]).
List<DiffChange> diffLists<T>(List<T> a, List<T> b, {int? maxCost}) {
  assert((maxCost ?? 1) > 0, 'a cost of 1 or more');
  final shorter = math.min(a.length, b.length);
  var head = 0;
  while (head < shorter && a[head] == b[head]) {
    head++;
  }
  var tail = 0;
  while (tail < shorter - head &&
      a[a.length - 1 - tail] == b[b.length - 1 - tail]) {
    tail++;
  }
  final n = a.length - head - tail;
  final m = b.length - head - tail;
  if (n == 0 && m == 0) {
    return const [];
  }
  if (n == 0 || m == 0) {
    return [DiffChange(head, head + n, head, head + m)];
  }

  // Each item as a number, the same for equal items; those of [b] that [a]
  // does not have are -1.
  final ids = <T, int>{};
  final idsOfA = Int32List(n);
  for (var i = 0; i < n; i++) {
    idsOfA[i] = ids.putIfAbsent(a[head + i], () => ids.length);
  }
  final idsOfB = Int32List(m);
  final inB = Uint8List(ids.length);
  for (var j = 0; j < m; j++) {
    final id = idsOfB[j] = ids[b[head + j]] ?? -1;
    if (id >= 0) {
      inB[id] = 1;
    }
  }

  // An item only one list has is never kept: the search runs on the rest.
  final whereA = [
    for (var i = 0; i < n; i++)
      if (inB[idsOfA[i]] == 1) i,
  ];
  final whereB = [
    for (var j = 0; j < m; j++)
      if (idsOfB[j] >= 0) j,
  ];
  final keptA = Uint8List(n);
  final keptB = Uint8List(m);
  if (whereA.isNotEmpty && whereB.isNotEmpty) {
    final x = Int32List.fromList([for (final i in whereA) idsOfA[i]]);
    final y = Int32List.fromList([for (final j in whereB) idsOfB[j]]);
    final search = _Myers(
      x,
      y,
      maxCost ?? math.max(256, math.sqrt(x.length + y.length).toInt()),
    )..run();
    for (var k = 0; k < x.length; k++) {
      if (search.changedX[k] == 0) {
        keptA[whereA[k]] = 1;
      }
    }
    for (var k = 0; k < y.length; k++) {
      if (search.changedY[k] == 0) {
        keptB[whereB[k]] = 1;
      }
    }
  }

  // The items kept are the same on both sides, in order: what lies
  // between them is a change.
  final changes = <DiffChange>[];
  var i = 0;
  var j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && keptA[i] == 1 && keptB[j] == 1) {
      i++;
      j++;
      continue;
    }
    final i0 = i;
    final j0 = j;
    while (i < n && keptA[i] == 0) {
      i++;
    }
    while (j < m && keptB[j] == 0) {
      j++;
    }
    changes.add(DiffChange(head + i0, head + i, head + j0, head + j));
  }
  return changes;
}

/// Myers' search for the shortest edit script between [x] and [y] in
/// linear space, as GNU diff's `diffseq.h` has it: the furthest reaching
/// paths from both corners of a region meet in a middle snake that divides
/// it in two, each searched the same way; [changedX] and [changedY] end up
/// 1 for each item removed or added.
final class _Myers {
  _Myers(this.x, this.y, this.maxCost)
    : changedX = Uint8List(x.length),
      changedY = Uint8List(y.length),
      _forward = Int32List(x.length + y.length + 3),
      _backward = Int32List(x.length + y.length + 3),
      _zero = y.length + 1;

  final Int32List x;
  final Int32List y;

  /// The edits after which a search that need not be the shortest gives up.
  final int maxCost;

  final Uint8List changedX;
  final Uint8List changedY;

  /// The furthest x each search reached on each diagonal x − y, at
  /// [_zero] + the diagonal.
  final Int32List _forward;
  final Int32List _backward;
  final int _zero;

  static const _far = 0x7fffffff;

  // where the last search divided its region, and whether each half has
  // to be the shortest
  var _midX = 0;
  var _midY = 0;
  var _lowShortest = false;
  var _highShortest = false;

  void run() {
    // regions still to search: x from, x to, y from, y to, shortest
    final regions = <int>[0, x.length, 0, y.length, 0];
    while (regions.isNotEmpty) {
      final shortest = regions.removeLast() == 1;
      var yTo = regions.removeLast();
      var yFrom = regions.removeLast();
      var xTo = regions.removeLast();
      var xFrom = regions.removeLast();
      while (xFrom < xTo && yFrom < yTo && x[xFrom] == y[yFrom]) {
        xFrom++;
        yFrom++;
      }
      while (xTo > xFrom && yTo > yFrom && x[xTo - 1] == y[yTo - 1]) {
        xTo--;
        yTo--;
      }
      if (xFrom == xTo || yFrom == yTo) {
        changedX.fillRange(xFrom, xTo, 1);
        changedY.fillRange(yFrom, yTo, 1);
        continue;
      }
      _divide(xFrom, xTo, yFrom, yTo, shortest);
      if ((_midX == xFrom && _midY == yFrom) ||
          (_midX == xTo && _midY == yTo)) {
        // no way on found: the region is a change as a whole
        changedX.fillRange(xFrom, xTo, 1);
        changedY.fillRange(yFrom, yTo, 1);
        continue;
      }
      regions
        ..addAll([xFrom, _midX, yFrom, _midY, if (_lowShortest) 1 else 0])
        ..addAll([_midX, xTo, _midY, yTo, if (_highShortest) 1 else 0]);
    }
  }

  /// Finds where the region [xFrom]..[xTo] × [yFrom]..[yTo] divides, whose
  /// first and last items differ on the two sides: the middle snake, or,
  /// unless [shortest], the furthest point a search got to by [maxCost]
  /// edits.
  void _divide(int xFrom, int xTo, int yFrom, int yTo, bool shortest) {
    final fd = _forward;
    final bd = _backward;
    final z = _zero;
    final lowest = xFrom - yTo;
    final highest = xTo - yFrom;
    final forwardMid = xFrom - yFrom;
    final backwardMid = xTo - yTo;
    var fMin = forwardMid;
    var fMax = forwardMid;
    var bMin = backwardMid;
    var bMax = backwardMid;
    final odd = (forwardMid - backwardMid).isOdd;
    fd[z + forwardMid] = xFrom;
    bd[z + backwardMid] = xTo;
    for (var cost = 1; ; cost++) {
      // the forward search, an edit further on each diagonal
      if (fMin > lowest) {
        fd[z + --fMin - 1] = -1;
      } else {
        fMin++;
      }
      if (fMax < highest) {
        fd[z + ++fMax + 1] = -1;
      } else {
        fMax--;
      }
      for (var d = fMax; d >= fMin; d -= 2) {
        final low = fd[z + d - 1];
        final high = fd[z + d + 1];
        var i = low < high ? high : low + 1;
        var j = i - d;
        while (i < xTo && j < yTo && x[i] == y[j]) {
          i++;
          j++;
        }
        fd[z + d] = i;
        if (odd && bMin <= d && d <= bMax && bd[z + d] <= i) {
          _divideAt(i, j, true, true);
          return;
        }
      }
      // the backward search
      if (bMin > lowest) {
        bd[z + --bMin - 1] = _far;
      } else {
        bMin++;
      }
      if (bMax < highest) {
        bd[z + ++bMax + 1] = _far;
      } else {
        bMax--;
      }
      for (var d = bMax; d >= bMin; d -= 2) {
        final low = bd[z + d - 1];
        final high = bd[z + d + 1];
        var i = low < high ? low : high - 1;
        var j = i - d;
        while (i > xFrom && j > yFrom && x[i - 1] == y[j - 1]) {
          i--;
          j--;
        }
        bd[z + d] = i;
        if (!odd && fMin <= d && d <= fMax && i <= fd[z + d]) {
          _divideAt(i, j, true, true);
          return;
        }
      }
      if (shortest || cost < maxCost) {
        continue;
      }
      // too costly: divide at the furthest point either search got to
      var forwardBest = -1;
      var forwardX = 0;
      for (var d = fMax; d >= fMin; d -= 2) {
        var i = math.min(fd[z + d], xTo);
        var j = i - d;
        if (yTo < j) {
          i = yTo + d;
          j = yTo;
        }
        if (forwardBest < i + j) {
          forwardBest = i + j;
          forwardX = i;
        }
      }
      var backwardBest = _far;
      var backwardX = 0;
      for (var d = bMax; d >= bMin; d -= 2) {
        var i = math.max(xFrom, bd[z + d]);
        var j = i - d;
        if (j < yFrom) {
          i = yFrom + d;
          j = yFrom;
        }
        if (i + j < backwardBest) {
          backwardBest = i + j;
          backwardX = i;
        }
      }
      if (xTo + yTo - backwardBest < forwardBest - (xFrom + yFrom)) {
        _divideAt(forwardX, forwardBest - forwardX, true, false);
      } else {
        _divideAt(backwardX, backwardBest - backwardX, false, true);
      }
      return;
    }
  }

  void _divideAt(int i, int j, bool lowShortest, bool highShortest) {
    _midX = i;
    _midY = j;
    _lowShortest = lowShortest;
    _highShortest = highShortest;
  }
}
