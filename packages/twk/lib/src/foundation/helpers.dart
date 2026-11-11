/// Small helpers the widgets share: lists compared element by element
/// ([sameList]), a ratio kept from 0 to 1 ([unitRatio]) and days counted
/// from 1970-01-01 ([dayOf], [utcOfDay], [dateOfDay], [weekdayOfDay]).
/// Internal: not exported.
library;

/// How many keys [debugDistinct] reads at most.
const debugDistinctLimit = 1000;

/// For an assert: that the [count] keys [at] gives are all different, else
/// the assertion fails with [message] of the key twice and the index of its
/// second place. With [full] every key is read, once, as an initState
/// does. Else O(min(count, [debugDistinctLimit])): only the first
/// [debugDistinctLimit] keys are read, so a virtualized list of a million
/// items rebuilt costs what a small one does, and a duplicate further on
/// goes unseen; the common mistake, a small list with one, is caught.
/// Always true.
bool debugDistinct<K>(
  int count,
  K Function(int index) at,
  String Function(K key, int index) message, {
  bool full = false,
}) {
  final seen = <K>{};
  final n = full || count < debugDistinctLimit ? count : debugDistinctLimit;
  for (var i = 0; i < n; i++) {
    final key = at(i);
    assert(seen.add(key), message(key, i));
  }
  return true;
}

/// Whether [a] and [b] hold equal elements in the same order.
bool sameList<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// The index of the first item for which [enabled] holds, stepping [step]
/// places at a time from [from] round a list of [count] items, wrapping at
/// both ends; [from] itself comes last, and may lie outside the list (-1 or
/// [count]) for starting at an end. -1 where none is enabled.
int nextEnabled(int count, int from, int step, bool Function(int i) enabled) {
  for (var k = 1; k <= count; k++) {
    final i = ((from + step * k) % count + count) % count;
    if (enabled(i)) {
      return i;
    }
  }
  return -1;
}

/// [ratio] kept from 0 to 1; 0 for NaN.
double unitRatio(double ratio) => ratio >= 1 ? 1.0 : (ratio > 0 ? ratio : 0.0);

/// The day of [date] (its year, month and day, whatever its time and
/// zone) as days since 1970-01-01.
int dayOf(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

/// [day], days since 1970-01-01, at midnight UTC.
DateTime utcOfDay(int day) => DateTime.fromMillisecondsSinceEpoch(
  day * Duration.millisecondsPerDay,
  isUtc: true,
);

/// [day], days since 1970-01-01, as a local date at midnight.
DateTime dateOfDay(int day) {
  final d = utcOfDay(day);
  return DateTime(d.year, d.month, d.day);
}

/// The weekday of [day], days since 1970-01-01, [DateTime.monday] to
/// [DateTime.sunday]; 1970-01-01 was a Thursday.
int weekdayOfDay(int day) => (day + 3) % 7 + 1;
