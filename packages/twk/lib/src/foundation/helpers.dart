/// Small helpers the widgets share: lists compared element by element
/// ([sameList]), a ratio kept from 0 to 1 ([unitRatio]) and days counted
/// from 1970-01-01 ([dayOf], [utcOfDay], [dateOfDay], [weekdayOfDay]).
/// Internal: not exported.
library;

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
