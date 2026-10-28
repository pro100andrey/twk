// The small helpers the widgets share: lists compared element by
// element, a ratio kept from 0 to 1, and days counted from 1970-01-01 as
// the calendar, the heatmap and the date picker count them.
import 'package:test/test.dart';
import 'package:twk/src/foundation/helpers.dart';

void main() {
  test('sameList: equal elements in the same order', () {
    final list = [1, 2, 3];
    expect(sameList(list, list), isTrue);
    expect(sameList([1, 2, 3], [1, 2, 3]), isTrue);
    expect(sameList(<int>[], <int>[]), isTrue);
    expect(sameList([1, 2, 3], [1, 3, 2]), isFalse);
    expect(sameList([1, 2], [1, 2, 3]), isFalse);
    expect(sameList(['a'], ['b']), isFalse);
  });

  test('unitRatio keeps a ratio from 0 to 1, NaN at 0', () {
    expect(unitRatio(0.25), 0.25);
    expect(unitRatio(-1), 0.0);
    expect(unitRatio(1.5), 1.0);
    expect(unitRatio(double.nan), 0.0);
    expect(unitRatio(double.infinity), 1.0);
  });

  group('days', () {
    test('dayOf counts the date, whatever its time and zone', () {
      expect(dayOf(DateTime.utc(1970)), 0);
      expect(dayOf(DateTime(1970, 1, 2, 23, 59)), 1);
      expect(dayOf(DateTime.utc(1969, 12, 31)), -1);
      expect(dayOf(DateTime(2026, 10, 23)), 20749);
    });

    test('utcOfDay and dateOfDay give the day back, at midnight', () {
      expect(utcOfDay(20749), DateTime.utc(2026, 10, 23));
      expect(dateOfDay(20749), DateTime(2026, 10, 23));
      expect(dateOfDay(-1), DateTime(1969, 12, 31));
    });

    test('weekdayOfDay is DateTime.weekday, before 1970 too', () {
      for (final day in [-800, -8, -1, 0, 1, 6, 7, 20749]) {
        expect(weekdayOfDay(day), utcOfDay(day).weekday, reason: '$day');
      }
      expect(weekdayOfDay(0), DateTime.thursday);
    });
  });
}
