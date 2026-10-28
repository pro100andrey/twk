// Months in weeks from either first weekday, across the ends of years,
// with ISO 8601 week numbers and the days of the months around; names of
// other languages; today, a day's own style, the selection and the cursor
// merged in order, the theme's where none is given; the controller's
// cursor, bounds and selection; the keys that move the cursor and select
// while the calendar has the focus, the others going up; and repainting
// nothing but the calendar.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show MouseTracking;
import 'package:twk_test/twk_test.dart';

import 'shot.dart';

const red = Color.rgb(255, 0, 0);
const green = Color.rgb(0, 255, 0);
const grey = Color.rgb(1, 2, 3);
const Color none = Color.defaultColor;

/// [calendar] shown on [width] × [height] cells.
Shot show(RenderCalendar calendar, {int width = 20, int height = 8}) {
  final shot = Shot.render(calendar, width, height);
  expect(shot.vt.errors, isEmpty);
  return shot;
}

/// The cells of row [y] of [shot] from column [from] to [to] that show a
/// glyph: the text color of a blank does not show, and the terminal gets
/// whichever is at hand.
List<(String, Color, Color)> glyphs(Shot shot, int y, int from, int to) => [
  for (final cell in shot.colors(y).sublist(from, to))
    if (cell.$1 != ' ') cell,
];

/// A calendar whose cursor is on [year]-[month]-[day].
RenderCalendar on(
  int year,
  int month,
  int day, {
  int firstWeekday = DateTime.monday,
  bool showWeekNumbers = false,
  bool showOutsideDays = false,
  Style outsideStyle = const Style(),
}) => RenderCalendar(
  cursor: DateTime(year, month, day),
  firstWeekday: firstWeekday,
  showWeekNumbers: showWeekNumbers,
  showOutsideDays: showOutsideDays,
  outsideStyle: outsideStyle,
);

void main() {
  group('RenderCalendar', () {
    test("shows a month in weeks from Monday under its name and the weekdays' "
        'names', () {
      expect(show(on(2026, 10, 19)).rows, [
        '    October 2026',
        'Mo Tu We Th Fr Sa Su',
        '          1  2  3  4',
        ' 5  6  7  8  9 10 11',
        '12 13 14 15 16 17 18',
        '19 20 21 22 23 24 25',
        '26 27 28 29 30 31',
        '',
      ]);
    });

    test('starts its weeks on Sunday, or another weekday', () {
      expect(show(on(2026, 10, 19, firstWeekday: DateTime.sunday)).rows, [
        '    October 2026',
        'Su Mo Tu We Th Fr Sa',
        '             1  2  3',
        ' 4  5  6  7  8  9 10',
        '11 12 13 14 15 16 17',
        '18 19 20 21 22 23 24',
        '25 26 27 28 29 30 31',
        '',
      ]);
      expect(show(on(2026, 10, 19, firstWeekday: DateTime.saturday)).rows, [
        '    October 2026',
        'Sa Su Mo Tu We Th Fr',
        '                1  2',
        ' 3  4  5  6  7  8  9',
        '10 11 12 13 14 15 16',
        '17 18 19 20 21 22 23',
        '24 25 26 27 28 29 30',
        '31',
      ]);
    });

    test('turns the year with the cursor, the weeks numbered as ISO 8601 '
        'numbers them', () {
      final calendar = on(2026, 12, 31, showWeekNumbers: true);
      final shot = show(calendar, width: 23);
      expect(shot.rows, [
        '      December 2026',
        '   Mo Tu We Th Fr Sa Su',
        '49     1  2  3  4  5  6',
        '50  7  8  9 10 11 12 13',
        '51 14 15 16 17 18 19 20',
        '52 21 22 23 24 25 26 27',
        '53 28 29 30 31',
        '',
      ]);
      calendar.cursor = DateTime(2027);
      shot.frame();
      expect(shot.rows, [
        '       January 2027',
        '   Mo Tu We Th Fr Sa Su',
        '53              1  2  3',
        ' 1  4  5  6  7  8  9 10',
        ' 2 11 12 13 14 15 16 17',
        ' 3 18 19 20 21 22 23 24',
        ' 4 25 26 27 28 29 30 31',
        '',
      ]);
    });

    test('numbers a week from Sunday as the ISO week most of its days are '
        'in', () {
      final calendar = on(
        2024,
        12,
        1,
        firstWeekday: DateTime.sunday,
        showWeekNumbers: true,
      );
      // Sunday the 29th is in week 52, the rest of its row in week 1
      expect(show(calendar, width: 23).rows, [
        '      December 2024',
        '   Su Mo Tu We Th Fr Sa',
        '49  1  2  3  4  5  6  7',
        '50  8  9 10 11 12 13 14',
        '51 15 16 17 18 19 20 21',
        '52 22 23 24 25 26 27 28',
        ' 1 29 30 31',
        '',
      ]);
    });

    test('fills the rows around the month with the days of the months '
        'around, in their style', () {
      final shot = show(
        on(
          2026,
          2,
          14,
          showOutsideDays: true,
          outsideStyle: const Style(fg: grey),
        ),
      );
      expect(shot.rows, [
        '   February 2026',
        'Mo Tu We Th Fr Sa Su',
        '26 27 28 29 30 31  1',
        ' 2  3  4  5  6  7  8',
        ' 9 10 11 12 13 14 15',
        '16 17 18 19 20 21 22',
        '23 24 25 26 27 28  1',
        ' 2  3  4  5  6  7  8',
      ]);
      expect(glyphs(shot, 2, 15, 20), [
        ('3', grey, none),
        ('1', grey, none),
        ('1', none, none),
      ]);
      expect(glyphs(shot, 6, 15, 20), [
        ('2', none, none),
        ('8', none, none),
        ('1', grey, none),
      ]);
    });

    test("puts a weekday's name at the right of a day's two columns, cut off "
        "at them; the header is the month's name and the year", () {
      String names(List<String> weekdayNames) => show(
        RenderCalendar(
          cursor: DateTime(2026, 10),
          weekdayNames: weekdayNames,
        ),
      ).rows[1];
      expect(
        names(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']),
        'Mo Tu We Th Fr Sa Su',
      );
      expect(
        names(['M', 'T', 'W', 'T', 'F', 'S', 'S']),
        ' M  T  W  T  F  S  S',
      );
      expect(
        names(['月曜', '火', '水', '木', '金', '土', '日']),
        '月 火 水 木 金 土 日',
      );
      final german = show(
        RenderCalendar(
          cursor: DateTime(2026, 10),
          monthNames: const [
            'Januar',
            'Februar',
            'März',
            'April',
            'Mai',
            'Juni',
            'Juli',
            'August',
            'September',
            'Oktober',
            'November',
            'Dezember',
          ],
          weekdayNames: const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'],
        ),
      );
      expect(german.rows.take(2), [
        '    Oktober 2026',
        'Mo Di Mi Do Fr Sa So',
      ]);
    });

    test("today, a day's own style, the selection and the cursor, merged in "
        'that order; the cursor only while shown', () {
      final calendar = RenderCalendar(
        cursor: DateTime(2026, 10, 19),
        selected: DateTime(2026, 10, 22),
        today: DateTime(2026, 10, 20),
        showCursor: true,
        dayStyle: (date) => date.day.isEven ? const Style(fg: green) : null,
        todayStyle: const Style(fg: red, attrs: Attr.bold),
        selectedStyle: const Style(fg: red, bg: grey),
        cursorStyle: const Style(attrs: Attr.reverse),
      );
      final shot = show(calendar);
      // 19 20 21 22
      expect(glyphs(shot, 5, 0, 12), [
        ('1', none, none),
        ('9', none, none),
        ('2', green, none),
        ('0', green, none),
        ('2', none, none),
        ('1', none, none),
        ('2', red, grey),
        ('2', red, grey),
      ]);
      // the gap after the selection
      expect(shot.colors(5)[11].$3, none);
      // the digits of the 19th to the 22nd
      const digits = [0, 1, 3, 4, 6, 7, 9, 10];
      List<int> attrs() => [for (final x in digits) shot.attrs(5)[x]];
      expect(attrs(), [
        Attr.reverse,
        Attr.reverse,
        Attr.bold,
        Attr.bold,
        0,
        0,
        0,
        0,
      ]);
      calendar.cursor = DateTime(2026, 10, 22);
      shot.frame();
      expect(attrs(), [
        0,
        0,
        Attr.bold,
        Attr.bold,
        0,
        0,
        Attr.reverse,
        Attr.reverse,
      ]);
      expect(shot.colors(5)[9], ('2', red, grey));
      calendar.showCursor = false;
      shot.frame();
      expect(shot.attrs(5)[9], 0);
    });

    test('shows the days outside its bounds in the style of the days '
        'around', () {
      final shot = show(
        RenderCalendar(
          cursor: DateTime(2026, 10, 19),
          firstDate: DateTime(2026, 10, 5),
          lastDate: DateTime(2026, 10, 30),
          outsideStyle: const Style(fg: grey),
        ),
      );
      // the 4th and the 5th, the 30th and the 31st
      expect(shot.colors(2)[19], ('4', grey, none));
      expect(shot.colors(3)[1], ('5', none, none));
      expect(shot.colors(6)[13], ('0', none, none));
      expect(shot.colors(6)[16], ('1', grey, none));
    });

    test('gives the date shown at a cell', () {
      final calendar = on(2026, 10, 19);
      show(calendar);
      expect(calendar.dateAt(0, 5), DateTime(2026, 10, 19));
      expect(calendar.dateAt(1, 5), DateTime(2026, 10, 19));
      expect(calendar.dateAt(16, 6), DateTime(2026, 10, 31));
      expect(calendar.dateAt(9, 2), DateTime(2026, 10));
      // between two days, the names, the header, below the weeks, beyond
      // the right edge, and the hidden days of the months around
      for (final (x, y) in [
        (2, 5),
        (0, 1),
        (4, 0),
        (0, 8),
        (20, 5),
        (6, 2),
        (18, 6),
      ]) {
        expect(calendar.dateAt(x, y), isNull, reason: '$x, $y');
      }
      calendar.showOutsideDays = true;
      expect(calendar.dateAt(6, 2), DateTime(2026, 9, 30));
      expect(calendar.dateAt(19, 7), DateTime(2026, 11, 8));
      final numbered = on(2026, 10, 19, showWeekNumbers: true);
      show(numbered, width: 23);
      expect(numbered.dateAt(1, 5), isNull);
      expect(numbered.dateAt(3, 5), DateTime(2026, 10, 19));
    });
  });

  group('CalendarController', () {
    test('reads the year, the month and the day of a date, and gives local '
        'dates at midnight', () {
      // the ends of the local day are another day in UTC, east or west of
      // it
      for (final date in [
        DateTime(2026, 10, 19, 0, 30),
        DateTime(2026, 10, 19, 23, 30),
        DateTime.utc(2026, 10, 19),
        DateTime.utc(2026, 10, 19, 23, 59),
      ]) {
        final c = CalendarController(selected: date);
        expect(c.selected, DateTime(2026, 10, 19), reason: '$date');
        expect(c.cursor, DateTime(2026, 10, 19), reason: '$date');
        expect(c.month, DateTime(2026, 10), reason: '$date');
      }
      expect(
        CalendarController(cursor: DateTime(1969, 12, 31, 23, 30)).cursor,
        DateTime(1969, 12, 31),
      );
    });

    test('moves the cursor a number of months, to the same day or the last '
        'day of a shorter month, then a number of days', () {
      DateTime moved(DateTime from, {int days = 0, int months = 0}) =>
          (CalendarController(
            cursor: from,
          )..moveCursor(days: days, months: months)).cursor;
      expect(moved(DateTime(2026, 1, 31), months: 1), DateTime(2026, 2, 28));
      expect(moved(DateTime(2028, 1, 31), months: 1), DateTime(2028, 2, 29));
      expect(moved(DateTime(2026, 3, 31), months: -1), DateTime(2026, 2, 28));
      expect(
        moved(DateTime(2026, 1, 31), months: 1, days: 1),
        DateTime(2026, 3),
      );
      expect(moved(DateTime(2026, 12, 15), months: 1), DateTime(2027, 1, 15));
      expect(moved(DateTime(2026, 1, 15), months: -13), DateTime(2024, 12, 15));
      expect(moved(DateTime(1969, 12, 31), days: 1), DateTime(1970));
      expect(moved(DateTime(2026, 12, 31), days: 1), DateTime(2027));
      expect(moved(DateTime(2026, 3, 28), days: 2), DateTime(2026, 3, 30));
      expect(moved(DateTime(2026, 10, 24), days: 2), DateTime(2026, 10, 26));
    });

    test('shows another month by moving the cursor to it', () {
      final c = CalendarController(cursor: DateTime(2026, 1, 31))
        ..month = DateTime(2026, 4, 15);
      expect(c.cursor, DateTime(2026, 4, 30));
      expect(c.month, DateTime(2026, 4));
      c.month = DateTime(2025, 2);
      expect(c.cursor, DateTime(2025, 2, 28));
    });

    test('keeps the cursor within its bounds, the selected date as it is '
        'given', () {
      final c = CalendarController(
        cursor: DateTime(2020),
        firstDate: DateTime(2026, 9, 28),
        lastDate: DateTime(2026, 11, 3),
      );
      expect(c.cursor, DateTime(2026, 9, 28));
      c.moveCursor(months: 2);
      expect(c.cursor, DateTime(2026, 11, 3));
      c.month = DateTime(2026);
      expect(c.cursor, DateTime(2026, 9, 28));
      c.cursor = DateTime(2030);
      expect(c.cursor, DateTime(2026, 11, 3));
      c.selected = DateTime(2026, 12, 25);
      expect(c.selected, DateTime(2026, 12, 25));
      expect(c.cursor, DateTime(2026, 11, 3));
      c.selected = DateTime(2026, 10, 2);
      expect(c.cursor, DateTime(2026, 10, 2));
      c.firstDate = DateTime(2026, 10, 10);
      expect(c.cursor, DateTime(2026, 10, 10));
      c
        ..lastDate = null
        ..cursor = DateTime(2030);
      expect(c.cursor, DateTime(2030));
      expect(c.firstDate, DateTime(2026, 10, 10));
      expect(c.lastDate, isNull);
    });

    test('notifies its listeners of each change, and of nothing else', () {
      var told = 0;
      final c = CalendarController(cursor: DateTime(2026, 10, 19))
        ..addListener(() => told++)
        ..cursor = DateTime(2026, 10, 19, 8)
        ..moveCursor()
        ..month = DateTime(2026, 10, 3)
        ..selected = null
        ..firstDate = null
        ..lastDate = null;
      expect(told, 0);
      c
        ..cursor = DateTime(2026, 10, 20)
        ..moveCursor(days: 1)
        ..month = DateTime(2026, 11)
        ..selected = DateTime(2026, 11, 21)
        ..selected = DateTime(2026, 12)
        ..firstDate = DateTime(2026)
        ..lastDate = DateTime(2027);
      expect(told, 7);
    });
  });

  group('Calendar', () {
    testTwk('is 20 columns wide and 8 rows tall, 23 columns with the week '
        'numbers and a row less without the header', (t) async {
      Widget beside(Calendar calendar) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [calendar, const Text('|')],
          ),
          const Text('below'),
        ],
      );
      final today = DateTime(2026, 10, 19);
      await t.pumpWidget(
        Theme.terminal(child: beside(Calendar(today: today))),
        size: (30, 10),
      );
      expect(t, hasTextAt(20, 0, '|'));
      expect(t.lines[8], 'below');
      await t.pumpWidget(
        Theme.terminal(
          child: beside(
            Calendar(today: today, showWeekNumbers: true, showHeader: false),
          ),
        ),
      );
      expect(t, hasTextAt(23, 0, '|'));
      expect(t.lines[0], startsWith('   Mo Tu'));
      expect(t.lines[7], 'below');
    });

    testTwk('the arrows move the cursor a day or a week while it has the '
        'focus, into the months around, which it shows', (t) async {
      final c = CalendarController(cursor: DateTime(2026, 10));
      await t.pumpWidget(
        Theme.terminal(
          child: Calendar(controller: c, today: DateTime(2026, 10, 19)),
        ),
        size: (20, 8),
      );
      await t.press('right');
      await t.pump();
      expect(c.cursor, DateTime(2026, 10));
      expect(t, styleAt(10, 2, isNot(hasBg(Color.blue))));
      await t.press('tab');
      await t.pump();
      expect(
        t,
        styleAt(10, 2, hasBg(Color.blue)),
      );
      final cursors = <DateTime>[];
      for (final key in ['left', 'right', 'down', 'up', 'up']) {
        await t.press(key);
        await t.pump();
        cursors.add(c.cursor);
        if (key == 'left') {
          expect(t.lines[0], '   September 2026');
          expect(t, styleAt(7, 6, hasBg(Color.blue)));
        }
      }
      expect(cursors, [
        DateTime(2026, 9, 30),
        DateTime(2026, 10),
        DateTime(2026, 10, 8),
        DateTime(2026, 10),
        DateTime(2026, 9, 24),
      ]);
    });

    testTwk('Page Up and Page Down move the cursor a month, to the last day '
        'of a shorter one, Shift a year; Home and End to the ends of the '
        'month', (t) async {
      final c = CalendarController(cursor: DateTime(2028, 1, 31));
      await t.pumpWidget(
        Theme.terminal(child: Calendar(controller: c, autofocus: true)),
        size: (20, 8),
      );
      final cursors = <DateTime>[];
      for (final key in [
        'pagedown',
        'pagedown',
        'shift+pageup',
        'home',
        'end',
        'pageup',
        'shift+pagedown',
      ]) {
        await t.press(key);
        cursors.add(c.cursor);
      }
      expect(cursors, [
        DateTime(2028, 2, 29),
        DateTime(2028, 3, 29),
        DateTime(2027, 3, 29),
        DateTime(2027, 3),
        DateTime(2027, 3, 31),
        DateTime(2027, 2, 28),
        DateTime(2028, 2, 28),
      ]);
    });

    testTwk('moves across the end of a year and shows the next year from '
        'Sunday', (t) async {
      final c = CalendarController(cursor: DateTime(2026, 12, 31));
      await t.pumpWidget(
        Theme.terminal(
          child: Calendar(
            controller: c,
            firstWeekday: DateTime.sunday,
            autofocus: true,
          ),
        ),
        size: (20, 8),
      );
      await t.press('right');
      await t.pump();
      expect(c.cursor, DateTime(2027));
      expect(t.lines, [
        '    January 2027',
        'Su Mo Tu We Th Fr Sa',
        '                1  2',
        ' 3  4  5  6  7  8  9',
        '10 11 12 13 14 15 16',
        '17 18 19 20 21 22 23',
        '24 25 26 27 28 29 30',
        '31',
      ]);
      expect(t, styleAt(16, 2, hasBg(Color.blue)));
    });

    testTwk("Enter and Space select the cursor's date and call onSelected "
        'with it', (t) async {
      final c = CalendarController(cursor: DateTime(2026, 10, 19));
      final selected = <DateTime>[];
      await t.pumpWidget(
        Theme.terminal(
          child: Calendar(
            controller: c,
            onSelected: selected.add,
            today: DateTime(2026),
            autofocus: true,
          ),
        ),
        size: (20, 8),
      );
      await t.press('enter');
      expect(selected, [DateTime(2026, 10, 19)]);
      expect(c.selected, DateTime(2026, 10, 19));
      await t.press('right space right');
      await t.pump();
      expect(selected, [DateTime(2026, 10, 19), DateTime(2026, 10, 20)]);
      expect(c.selected, DateTime(2026, 10, 20));
      // the selection on the terminal theme's grey, under the cursor
      // filled with blue
      expect(
        t,
        styleAt(4, 5, allOf(hasBg(const Color.indexed(237)), hasFg(none))),
      );
      expect(t, styleAt(7, 5, hasBg(Color.blue)));
    });

    testTwk('the keys it does not take go up to the nodes above it', (
      t,
    ) async {
      final c = CalendarController(cursor: DateTime(2026, 10, 19));
      final above = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: Focus(
            onKeyEvent: (node, event) {
              above.add('$event');
              return KeyEventResult.handled;
            },
            child: Calendar(controller: c, autofocus: true),
          ),
        ),
        size: (20, 8),
      );
      await t.press('escape x ctrl+left shift+right left');
      expect(above, [
        'Key(escape)',
        'Key("x")',
        'Key(left mod=4)',
        'Key(right mod=1)',
      ]);
      expect(c.cursor, DateTime(2026, 10, 18));
    });

    testTwk('a click on a day, on either of its columns, picks it as Enter '
        'does and focuses the calendar; on no day, or one outside the '
        'bounds, nothing', (t) async {
      final c = CalendarController(
        cursor: DateTime(2026, 10, 19),
        firstDate: DateTime(2026, 10, 2),
      );
      final selected = <DateTime>[];
      await t.pumpWidget(
        Theme.terminal(
          child: Calendar(controller: c, onSelected: selected.add),
        ),
        size: (20, 8),
      );
      // ' 5  6  7  8  9 10 11': the 9th on columns 12 and 13
      await t.click(13, 3);
      await t.pump();
      expect(selected, [DateTime(2026, 10, 9)]);
      expect(c.selected, DateTime(2026, 10, 9));
      expect(c.cursor, DateTime(2026, 10, 9));
      expect(
        t,
        styleAt(13, 3, hasBg(Color.blue)),
      );
      await t.click(15, 4);
      expect(selected.last, DateTime(2026, 10, 17));
      // the blank between two days, the header, a blank before the 1st,
      // the 1st before firstDate
      for (final (x, y) in [(14, 4), (5, 0), (1, 1), (0, 2), (10, 2)]) {
        await t.click(x, y);
      }
      expect(selected, [DateTime(2026, 10, 9), DateTime(2026, 10, 17)]);
      expect(c.cursor, DateTime(2026, 10, 17));
    });

    testTwk('with the days of the months around, a click on one picks it and '
        'shows its month; one that takes no focus takes no click', (t) async {
      final c = CalendarController(cursor: DateTime(2026, 10, 19));
      await t.pumpWidget(
        Theme.terminal(child: Calendar(controller: c, showOutsideDays: true)),
        size: (20, 8),
      );
      await t.click(0, 2);
      await t.pump();
      expect(c.selected, DateTime(2026, 9, 28));
      expect(t.lines[0], '   September 2026');
      await t.pumpWidget(
        Theme.terminal(
          child: Calendar(
            controller: c,
            showOutsideDays: true,
            canRequestFocus: false,
          ),
        ),
      );
      expect(t.terminal.mouseTracking, MouseTracking.off);
      await t.click(4, 4);
      expect(c.selected, DateTime(2026, 9, 28));
    });

    testTwk('one that takes no focus shows its month without a cursor', (
      t,
    ) async {
      final c = CalendarController(cursor: DateTime(2026, 10, 19));
      await t.pumpWidget(
        Theme.terminal(
          child: Calendar(
            controller: c,
            canRequestFocus: false,
            autofocus: true,
          ),
        ),
        size: (20, 8),
      );
      await t.press('tab right');
      await t.pump();
      expect(c.cursor, DateTime(2026, 10, 19));
      expect(t, styleAt(0, 5, isNot(hasBg(Color.blue))));
    });

    testTwk('without a controller, one of its own with the cursor on today', (
      t,
    ) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Calendar(today: DateTime(2027, 2, 14), autofocus: true),
        ),
        size: (20, 8),
      );
      expect(t.lines[0], '   February 2027');
      expect(t, styleAt(19, 3, hasBg(Color.blue)));
      await t.press('right');
      await t.pump();
      expect(t, styleAt(1, 4, hasBg(Color.blue)));
      // today, in the accent of the terminal's theme
      expect(
        t,
        styleAt(19, 3, allOf(hasFg(Color.magenta), hasAttr(Attr.bold))),
      );
    });

    testTwk("without styles of its own, the theme's", (t) async {
      const theme = ThemeData.dark;
      await t.pumpWidget(
        Theme.terminal(
          child: Theme(
            data: theme,
            child: Calendar(
              controller: CalendarController(
                cursor: DateTime(2026, 10, 19),
                selected: DateTime(2026, 10, 21),
              ),
              today: DateTime(2026, 10, 20),
              showOutsideDays: true,
              autofocus: true,
            ),
          ),
        ),
        size: (20, 8),
      );
      final text = theme.text.fg!;
      final background = theme.background.bg!;
      final muted = theme.muted.fg!;
      expect(
        t,
        styleAt(
          4,
          0,
          allOf(hasFg(text), hasBg(background), hasAttr(Attr.bold)),
        ),
      );
      expect(t, styleAt(0, 1, allOf(hasFg(muted), hasBg(background))));
      // the 28th of September, the 19th to the 22nd of October
      expect(t, styleAt(0, 2, hasFg(muted)));
      expect(
        t,
        styleAt(
          0,
          5,
          hasBg(theme.primary.fg!),
        ),
      );
      expect(
        t,
        styleAt(3, 5, allOf(hasFg(theme.accent.fg!), hasAttr(Attr.bold))),
      );
      expect(t, styleAt(6, 5, hasBg(theme.selection.bg!)));
      expect(t, styleAt(9, 5, allOf(hasFg(text), hasBg(background))));
      expect(t, styleAt(19, 7, hasBg(background)));
    });

    testTwk('gives the hints of its keys to a KeyHintsBar while it has the '
        'focus; none with keyHints false', (t) async {
      Widget app({bool keyHints = true}) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Calendar(today: DateTime(2026, 10, 19), keyHints: keyHints),
          const KeyHintsBar(),
        ],
      );
      await t.pumpWidget(Theme.terminal(child: app()), size: (50, 9));
      expect(t.lines[8], '');
      await t.press('tab');
      await t.pump();
      expect(t.lines[8], '←↑↓→ move   pgup pgdn month   enter select');
      await t.press('right');
      await t.pump();
      expect(t, styleAt(3, 5, hasBg(Color.blue)));
      await t.pumpWidget(Theme.terminal(child: app(keyHints: false)));
      expect(t.lines[8], '');
      await t.press('right');
      await t.pump();
      expect(t, styleAt(6, 5, hasBg(Color.blue)));
    });

    testTwk('rebuilt with other names and settings, shows them in the same '
        'month', (t) async {
      final c = CalendarController(cursor: DateTime(2026, 10, 19));
      await t.pumpWidget(
        Theme.terminal(
          child: Calendar(controller: c, today: DateTime(2026, 10, 20)),
        ),
        size: (23, 8),
      );
      RenderCalendar month() => find
          .byWidgetPredicate((w) => true)
          .evaluate()
          .map((e) => e.renderObject)
          .whereType<RenderCalendar>()
          .toSet()
          .single;
      final first = month();
      expect(t.lines.take(2), ['    October 2026', 'Mo Tu We Th Fr Sa Su']);
      Style? weekend(DateTime date) =>
          date.weekday >= DateTime.saturday ? const Style(fg: red) : null;
      await t.pumpWidget(
        Theme.terminal(
          child: Calendar(
            controller: c,
            today: DateTime(2026, 10, 20),
            firstWeekday: DateTime.sunday,
            showWeekNumbers: true,
            showOutsideDays: true,
            dayStyle: weekend,
            monthNames: const [
              'Januar',
              'Februar',
              'März',
              'April',
              'Mai',
              'Juni',
              'Juli',
              'August',
              'September',
              'Oktober',
              'November',
              'Dezember',
            ],
            weekdayNames: const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'],
            style: const Style(bg: grey),
            headerStyle: const Style(fg: green),
            weekdayStyle: const Style(fg: red),
            outsideStyle: const Style(attrs: Attr.dim),
            todayStyle: const Style(attrs: Attr.underline),
            selectedStyle: const Style(fg: grey),
            cursorStyle: const Style(attrs: Attr.italic),
          ),
        ),
      );
      expect(t.lines.take(2), [
        '       Oktober 2026',
        '   So Mo Di Mi Do Fr Sa',
      ]);
      final m = month();
      expect(m, same(first));
      expect(m.firstWeekday, DateTime.sunday);
      // without the focus, no cursor
      expect(m.showCursor, isFalse);
      expect(
        (m.showHeader, m.showWeekNumbers, m.showOutsideDays),
        (
          true,
          true,
          true,
        ),
      );
      expect(m.dayStyle, same(weekend));
      expect(m.monthNames[9], 'Oktober');
      expect(m.weekdayNames.last, 'So');
      expect(m.style.bg, grey);
      expect(m.headerStyle, const Style(fg: green));
      expect(m.weekdayStyle, const Style(fg: red));
      expect(m.outsideStyle, const Style(attrs: Attr.dim));
      expect(m.todayStyle, const Style(attrs: Attr.underline));
      expect(m.selectedStyle, const Style(fg: grey));
      expect(m.cursorStyle, const Style(attrs: Attr.italic));
      expect(
        (m.cursor, m.today),
        (DateTime(2026, 10, 19), DateTime(2026, 10, 20)),
      );
      expect((m.selected, m.firstDate, m.lastDate), (null, null, null));
    });

    testTwk('moving the cursor repaints nothing else', (t) async {
      final count = PaintCount();
      final c = CalendarController(cursor: DateTime(2026, 10, 19));
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            children: [
              Counted(count),
              Calendar(controller: c, autofocus: true),
            ],
          ),
        ),
        size: (20, 9),
      );
      final paints = count.paints;
      await t.press('right down');
      await t.pump();
      expect(c.cursor, DateTime(2026, 10, 27));
      expect(t, styleAt(3, 7, hasBg(Color.blue)));
      expect(count.paints, paints);
    });
  });
}
