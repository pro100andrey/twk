// DatePicker: the date as yyyy-mm-dd, with the time of day; the calendar
// opened by Alt+Down and by ▾ under the field, a date taken by its keys and
// by a click, closed by Escape and a press outside; text typed taken on
// Enter and as the focus leaves, kept within the bounds or given up when it
// is no date; Up, Down and the wheel stepping the part the caret is in; a
// disabled picker; a picker in a FormField.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show MouseTracking;
import 'package:twk_test/twk_test.dart';

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

/// Presses each key of [keys], pumping after each until the app is idle:
/// a popup that fades in or out has done so.
Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pumpUntilIdle();
  }
}

Future<void> type(TwkTester t, String text) async {
  await t.type(text);
  await t.pumpUntilIdle();
}

/// Clicks the cell ([x], [y]), pumping until the app is idle: a calendar
/// that fades in has done so.
Future<void> click(TwkTester t, int x, int y, {int button = 0}) async {
  await t.click(x, y, button: button);
  await t.pumpUntilIdle();
}

/// Takes the text of the field away.
Future<void> clear(TwkTester t) => press(t, 'ctrl+a ctrl+k');

final today = DateTime(2026, 10, 19);

/// A [DatePicker] whose date [value] holds, [width] cells wide, above a
/// node `next`, in an overlay; [changes] gets each date it gives,
/// [entered] each Enter that goes on to the nodes above.
Widget picker(
  ValueNotifier<DateTime?> value, {
  List<DateTime?>? changes,
  List<String>? entered,
  int width = 16,
  DateTime? firstDate,
  DateTime? lastDate,
  bool showTime = false,
  bool enabled = true,
  bool autofocus = false,
}) {
  final node = FocusNode(debugLabel: 'date');
  addTearDown(node.dispose);
  return Overlay(
    child: KeyBindings(
      {'enter': () => entered?.add('enter')},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: width,
            child: ValueListenableBuilder<DateTime?>(
              valueListenable: value,
              builder: (context, v, _) => DatePicker(
                value: v,
                firstDate: firstDate,
                lastDate: lastDate,
                showTime: showTime,
                today: today,
                onChanged: enabled
                    ? (next) {
                        changes?.add(next);
                        value.value = next;
                      }
                    : null,
                focusNode: node,
                autofocus: autofocus,
              ),
            ),
          ),
          const Focus(debugLabel: 'next', child: Text('next')),
        ],
      ),
    ),
  );
}

/// October 2026 in the popup under a field at the top left.
const october = [
  '',
  '     October 2026',
  ' Mo Tu We Th Fr Sa Su',
  '           1  2  3  4',
  '  5  6  7  8  9 10 11',
  ' 12 13 14 15 16 17 18',
  ' 19 20 21 22 23 24 25',
  ' 26 27 28 29 30 31',
  '',
  '',
];

void main() {
  testTwk('shows the date as yyyy-mm-dd before ▾, muted at rest and in '
      'the primary color while it has the focus, the field then on the '
      'selection color; with showTime, the time too; empty, the format '
      'muted', (t) async {
    final value = ValueNotifier<DateTime?>(DateTime(2026, 3, 7, 9, 5));
    addTearDown(value.dispose);
    const dark = ThemeData.dark;
    await t.pumpWidget(
      Theme(data: dark, child: picker(value)),
      size: (30, 3),
    );
    expect(t.lines, ['2026-03-07     ▾', 'next', '']);
    expect(t.cell(15, 0).fg, dark.muted.fg);
    expect(t.cell(0, 0).bg, dark.well.bg);
    await press(t, 'tab');
    expect(t.cell(15, 0).fg, dark.primary.fg);
    expect(t.cell(0, 0).bg, dark.selection.bg);
    await press(t, 'home shift+right');
    // the selection a step towards the primary color
    expect(t.cell(0, 0).bg, const Color.rgb(0x40, 0x6d, 0xa3));
    expect(t.cell(1, 0).bg, dark.selection.bg);
    await press(t, 'tab');
    await t.pumpWidget(
      Theme(
        data: ThemeData.dark,
        child: picker(value, showTime: true, width: 22),
      ),
    );
    expect(t.lines.first, '2026-03-07 09:05     ▾');
    value.value = null;
    await t.pump();
    expect(t.lines.first, 'yyyy-mm-dd hh:mm     ▾');
    expect(t.cell(0, 0).fg, ThemeData.dark.muted.fg);
  });

  testTwk('focusedStyle, arrowStyle, popupLook and cursorStyle give a '
      'plain look: the calendar in a border, its cursor reversed', (
    t,
  ) async {
    const dark = ThemeData.dark;
    await t.pumpWidget(
      Theme(
        data: dark,
        child: Overlay(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 22,
              child: DatePicker(
                value: DateTime(2026, 10, 19),
                today: today,
                onChanged: (_) {},
                focusedStyle: const Style(),
                arrowStyle: dark.primary,
                popupLook: PanelLook.bordered,
                cursorStyle: dark.primary.merge(
                  const Style(attrs: Attr.reverse),
                ),
              ),
            ),
          ),
        ),
      ),
      size: (30, 12),
    );
    expect(t.cell(21, 0).fg, dark.primary.fg);
    await press(t, 'tab');
    expect(t.cell(0, 0).bg, dark.well.bg);
    await press(t, 'alt+down');
    expect(t.lines[1], '┌────────────────────┐');
    expect(t.lines[2], '│    October 2026    │');
    expect(t, styleAt(1, 7, hasAttr(Attr.reverse)));
  });

  group('the calendar', () {
    testTwk('Alt+Down opens it under the field on the month of the date, '
        'focused; Enter takes the date the cursor is on, closes it and '
        'focuses the field; hinted', (t) async {
      final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 19));
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark,
          child: picker(value, changes: changes, width: 22),
        ),
        size: (30, 12),
      );
      await press(t, 'tab');
      expect(focused(t), 'date');
      expect(hints(t), ['up later', 'down earlier', 'alt+down calendar']);
      await press(t, 'alt+down');
      expect(t.lines.take(11), ['2026-10-19           ▾', ...october]);
      expect(focused(t), isNot('date'));
      expect(hints(t), [
        'left day',
        'up day',
        'down day',
        'right day',
        'pageup month',
        'pagedown month',
        'enter pick',
        'escape close',
      ]);
      // the cursor filled with the primary color; no border, a cell of
      // room around the calendar
      expect(t, styleAt(1, 7, hasBg(ThemeData.dark.primary.fg!)));
      expect(t, styleAt(1, 7, hasFg(ThemeData.dark.onPrimary.fg!)));
      expect(t, styleAt(1, 7, hasAttr(Attr.bold)));
      expect(t.cell(10, 6).bg, ThemeData.dark.surface.bg);
      expect(t.cell(0, 1).bg, ThemeData.dark.surface.bg);
      // ▾ bold while it is open
      expect(t, styleAt(21, 0, hasAttr(Attr.bold)));
      await press(t, 'right down');
      expect(t, styleAt(5, 8, hasBg(ThemeData.dark.primary.fg!)));
      // the date selected
      expect(t.cell(1, 7).bg, ThemeData.dark.selection.bg);
      await press(t, 'enter');
      expect(changes, [DateTime(2026, 10, 27)]);
      expect(focused(t), 'date');
      expect(t.lines, [
        '2026-10-27           ▾',
        'next',
        ...List.filled(10, ''),
      ]);
    });

    testTwk('Escape closes it, taking nothing, and focuses the field', (
      t,
    ) async {
      final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 19));
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      await t.pumpWidget(
        picker(value, changes: changes, autofocus: true),
        size: (30, 12),
      );
      await press(t, 'alt+down pagedown');
      expect(t.lines[2], '    November 2026');
      await press(t, 'escape');
      expect(t.lines[1], 'next');
      expect(focused(t), 'date');
      expect(changes, isEmpty);
      await press(t, 'alt+down');
      expect(t.lines[2], '     October 2026');
    });

    testTwk('opens on the month of today with no date, nothing selected; '
        'its keys take the date at midnight', (t) async {
      final value = ValueNotifier<DateTime?>(null);
      addTearDown(value.dispose);
      await t.pumpWidget(picker(value, autofocus: true), size: (30, 12));
      await press(t, 'alt+down');
      expect(t.lines.skip(1).take(10), october);
      // the cursor on today
      expect(t, styleAt(1, 7, hasAttr(Attr.bold)));
      expect(t, styleAt(1, 7, isNot(hasAttr(Attr.reverse))));
      await press(t, 'left space');
      expect(value.value, DateTime(2026, 10, 18));
    });

    testTwk('a press of ▾ focuses the field and opens it, a second closes '
        'it; a click on a day takes it; the wheel shows the month before '
        'and after', (t) async {
      final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 19));
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      await t.pumpWidget(picker(value, changes: changes), size: (30, 12));
      await click(t, 15, 0);
      expect(t.lines.skip(1).take(10), october);
      await click(t, 15, 0);
      expect(t.lines[1], 'next');
      expect(focused(t), 'date');
      await press(t, 'tab');
      expect(focused(t), 'next');
      await click(t, 15, 0);
      await press(t, 'escape');
      expect(focused(t), 'date');
      await click(t, 15, 0, button: 2);
      expect(t.lines[1], 'next');
      await click(t, 15, 0);
      // the 20th
      await click(t, 5, 7);
      expect(changes, [DateTime(2026, 10, 20)]);
      expect(t.lines.first, '2026-10-20     ▾');
      expect(focused(t), 'date');
      await click(t, 15, 0);
      await t.mouse(MouseKind.wheelDown, 10, 6);
      await t.pump();
      expect(t.lines[2], '    November 2026');
      await t.mouse(MouseKind.wheelUp, 10, 6);
      await t.mouse(MouseKind.wheelUp, 10, 6);
      await t.pump();
      expect(t.lines[2], '    September 2026');
      // a gap and the name of a day take nothing
      await click(t, 3, 7);
      await click(t, 4, 3);
      expect(changes, [DateTime(2026, 10, 20)]);
      expect(t.lines[2], '    September 2026');
    });

    testTwk('a press outside it and the field closes it, as does a press on '
        'the field, which focuses the field', (t) async {
      final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 19));
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      await t.pumpWidget(picker(value, changes: changes), size: (30, 12));
      await click(t, 15, 0);
      await click(t, 26, 11);
      expect(t.lines[1], 'next');
      expect(focused(t), 'date');
      await click(t, 15, 0);
      await click(t, 3, 0);
      expect(t.lines[1], 'next');
      expect(focused(t), 'date');
      expect(changes, isEmpty);
    });

    testTwk('shows the days outside the bounds muted, and takes no click on '
        'them; its cursor stays within them', (t) async {
      final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 12));
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark,
          child: picker(
            value,
            changes: changes,
            firstDate: DateTime(2026, 10, 10),
            lastDate: DateTime(2026, 10, 25),
            autofocus: true,
          ),
        ),
        size: (30, 12),
      );
      await press(t, 'alt+down');
      final muted = ThemeData.dark.muted.fg;
      // the 9th and the 26th, the 10th
      expect(t.cell(14, 5).fg, muted);
      expect(t.cell(2, 8).fg, muted);
      expect(t.cell(17, 5).fg, isNot(muted));
      await click(t, 14, 5);
      await click(t, 2, 8);
      expect(changes, isEmpty);
      await press(t, 'up up pagedown enter');
      expect(changes, [DateTime(2026, 10, 25)]);
    });

    testTwk('opens on the month of the date typed, which it takes first', (
      t,
    ) async {
      final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 19));
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      await t.pumpWidget(
        picker(value, changes: changes, autofocus: true),
        size: (30, 12),
      );
      await clear(t);
      await type(t, '2026-12-5');
      await press(t, 'alt+down');
      expect(changes, [DateTime(2026, 12, 5)]);
      expect(t.lines[2], '    December 2026');
    });

    testTwk('opens within the bounds the picker has then', (t) async {
      final value = ValueNotifier<DateTime?>(null);
      addTearDown(value.dispose);
      await t.pumpWidget(
        picker(
          value,
          firstDate: DateTime(2026, 10, 10),
          lastDate: DateTime(2026, 10, 25),
          autofocus: true,
        ),
        size: (30, 12),
      );
      await press(t, 'alt+down escape');
      await t.pumpWidget(
        picker(
          value,
          firstDate: DateTime(2026, 8, 3),
          lastDate: DateTime(2026, 9, 30),
          autofocus: true,
        ),
      );
      await press(t, 'alt+down');
      expect(t.lines[2], '    September 2026');
      await press(t, 'enter');
      expect(value.value, DateTime(2026, 9, 30));
    });

    testTwk('closes when the app moves the focus elsewhere, which keeps it', (
      t,
    ) async {
      final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 19));
      final other = FocusNode(debugLabel: 'other');
      addTearDown(value.dispose);
      addTearDown(other.dispose);
      await t.pumpWidget(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: picker(value, autofocus: true)),
            Focus(focusNode: other, child: const Text('other')),
          ],
        ),
        size: (30, 14),
      );
      await press(t, 'alt+down');
      expect(t.lines[1], isNot('next'));
      other.requestFocus();
      await t.pump();
      expect(t.lines[1], 'next');
      expect(focused(t), 'other');
    });

    testTwk('with showTime, a date taken keeps the time of the value', (
      t,
    ) async {
      final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 19, 8, 30));
      addTearDown(value.dispose);
      await t.pumpWidget(
        picker(value, showTime: true, width: 22, autofocus: true),
        size: (30, 12),
      );
      await press(t, 'alt+down right enter');
      expect(value.value, DateTime(2026, 10, 20, 8, 30));
      expect(t.lines.first, '2026-10-20 08:30     ▾');
    });
  });

  group('the text typed', () {
    testTwk('is taken on Enter, which goes on to the nodes above, as the '
        'date it is: the month and the day of one digit or two', (t) async {
      final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 19));
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      final entered = <String>[];
      await t.pumpWidget(
        picker(value, changes: changes, entered: entered, autofocus: true),
        size: (30, 3),
      );
      await clear(t);
      await type(t, ' 2027-1-5 ');
      expect(changes, isEmpty);
      await press(t, 'enter');
      expect(changes, [DateTime(2027, 1, 5)]);
      expect(entered, ['enter']);
      expect(t.lines.first, '2027-01-05     ▾');
    });

    testTwk('is taken as the focus leaves the field; empty, as no date', (
      t,
    ) async {
      final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 19));
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      await t.pumpWidget(
        picker(value, changes: changes, autofocus: true),
        size: (30, 3),
      );
      await press(t, 'backspace');
      await type(t, '8');
      await press(t, 'tab');
      expect(focused(t), 'next');
      expect(changes, [DateTime(2026, 10, 18)]);
      await press(t, 'shift+tab');
      await clear(t);
      await press(t, 'enter');
      expect(changes, [DateTime(2026, 10, 18), null]);
      expect(t.lines.first, 'yyyy-mm-dd     ▾');
    });

    testTwk('before or after the bounds is taken as the bound, and shown in '
        'the error style until then', (t) async {
      final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 19));
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark,
          child: picker(
            value,
            changes: changes,
            firstDate: DateTime(2026),
            lastDate: DateTime(2026, 12, 31),
            autofocus: true,
          ),
        ),
        size: (30, 3),
      );
      final error = ThemeData.dark.error.fg;
      await clear(t);
      await type(t, '2027-03-01');
      expect(t.cell(0, 0).fg, error);
      await press(t, 'enter');
      expect(t.cell(0, 0).fg, isNot(error));
      await clear(t);
      await type(t, '1999-12-31');
      expect(t.cell(0, 0).fg, error);
      await press(t, 'enter');
      expect(changes, [DateTime(2026, 12, 31), DateTime(2026)]);
      expect(t.lines.first, '2026-01-01     ▾');
    });

    testTwk('that is no date gives way to the value, in the error style '
        'until then; Escape puts the value back, then goes on', (t) async {
      final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 19));
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      final escaped = <String>[];
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark,
          child: KeyBindings(
            {'escape': () => escaped.add('escape')},
            child: picker(
              value,
              changes: changes,
              width: 22,
              autofocus: true,
            ),
          ),
        ),
        size: (30, 3),
      );
      final error = ThemeData.dark.error.fg;
      for (final wrong in [
        '2026-02-29',
        '2026-13-01',
        '2026-00-10',
        '2026-10-32',
        '26-10-19',
        '2026/10/19',
        '2026-10-19 10:00',
        'today',
      ]) {
        await clear(t);
        await type(t, wrong);
        expect(t.cell(0, 0).fg, error, reason: wrong);
        await press(t, 'up');
        expect(t.lines.first, startsWith(wrong), reason: wrong);
        await press(t, 'enter');
        expect(t.lines.first, '2026-10-19           ▾', reason: wrong);
      }
      await type(t, '1');
      await press(t, 'escape');
      expect(t.lines.first, '2026-10-19           ▾');
      expect(escaped, isEmpty);
      await press(t, 'escape');
      expect(escaped, ['escape']);
      expect(changes, isEmpty);
    });

    testTwk('with showTime, takes the time of day, 24 hours, midnight when '
        'left out', (t) async {
      final value = ValueNotifier<DateTime?>(null);
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark,
          child: picker(
            value,
            changes: changes,
            showTime: true,
            width: 22,
            autofocus: true,
          ),
        ),
        size: (30, 3),
      );
      await type(t, '2026-10-19 7:05');
      await press(t, 'enter');
      await clear(t);
      await type(t, '2026-10-20');
      await press(t, 'enter');
      expect(changes, [DateTime(2026, 10, 19, 7, 5), DateTime(2026, 10, 20)]);
      expect(t.lines.first, '2026-10-20 00:00     ▾');
      for (final wrong in [
        '2026-10-19 24:00',
        '2026-10-19 12:60',
        '2026-10-19 1:5',
      ]) {
        await clear(t);
        await type(t, wrong);
        expect(t.cell(0, 0).fg, ThemeData.dark.error.fg, reason: wrong);
        await press(t, 'enter');
      }
      expect(changes, hasLength(2));
    });
  });

  testTwk('with showTime, a date beyond the bounds is taken as the bound at '
      'its time', (t) async {
    final value = ValueNotifier<DateTime?>(null);
    addTearDown(value.dispose);
    await t.pumpWidget(
      picker(
        value,
        showTime: true,
        lastDate: DateTime(2026, 12, 31),
        width: 22,
        autofocus: true,
      ),
      size: (30, 3),
    );
    await type(t, '2027-03-01 10:30');
    await press(t, 'enter');
    expect(value.value, DateTime(2026, 12, 31, 10, 30));
  });

  testTwk('today is the one given, and the rows start with the first '
      'weekday given', (t) async {
    final value = ValueNotifier<DateTime?>(null);
    addTearDown(value.dispose);
    await t.pumpWidget(
      Overlay(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 16,
              child: ValueListenableBuilder<DateTime?>(
                valueListenable: value,
                builder: (context, v, _) => DatePicker(
                  value: v,
                  onChanged: (date) => value.value = date,
                  today: DateTime(2031, 5, 6, 13),
                  firstWeekday: DateTime.sunday,
                  autofocus: true,
                ),
              ),
            ),
          ],
        ),
      ),
      size: (30, 12),
    );
    await press(t, 'up');
    expect(value.value, DateTime(2031, 5, 6));
    await press(t, 'alt+down');
    expect(t.lines.skip(2).take(3), [
      '       May 2031',
      ' Su Mo Tu We Th Fr Sa',
      '              1  2  3',
    ]);
  });

  testTwk('keys typed right after Tab, in one read, are its', (t) async {
    final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 19));
    addTearDown(value.dispose);
    final changes = <DateTime?>[];
    await t.pumpWidget(picker(value, changes: changes), size: (30, 12));
    await t.input('\t\x1b[A\x1b[1;3B'.codeUnits);
    await t.pumpUntilIdle();
    expect(changes, [DateTime(2026, 10, 20)]);
    expect(t.lines.skip(1).take(10), october);
  });

  group('Up and Down', () {
    testTwk('step the day the caret is after, a day later and earlier; the '
        'month and the year where it is in those, to the last day of a '
        'shorter month; the caret put at the end of the part', (t) async {
      final value = ValueNotifier<DateTime?>(DateTime(2024, 1, 31));
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      await t.pumpWidget(
        picker(value, changes: changes, autofocus: true),
        size: (30, 3),
      );
      await press(t, 'up down down');
      expect(changes, [
        DateTime(2024, 2),
        DateTime(2024, 1, 31),
        DateTime(2024, 1, 30),
      ]);
      await press(t, 'up home right right right right right up');
      expect(changes.skip(3), [DateTime(2024, 1, 31), DateTime(2024, 2, 29)]);
      // the caret at the end of the month: a typed digit goes there
      await press(t, 'home right up');
      expect(changes.skip(5), [DateTime(2025, 2, 28)]);
      await press(t, 'down');
      expect(changes.skip(6), [DateTime(2024, 2, 28)]);
      await type(t, '9');
      expect(t.lines.first, '20249-02-28    ▾');
    });

    testTwk('with showTime, step the hour and the minute the caret is in, '
        'across the day', (t) async {
      final value = ValueNotifier<DateTime?>(DateTime(2026, 12, 31, 23, 59));
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      await t.pumpWidget(
        picker(
          value,
          changes: changes,
          showTime: true,
          width: 22,
          autofocus: true,
        ),
        size: (30, 3),
      );
      expect(t.lines.first, '2026-12-31 23:59     ▾');
      await press(t, 'up');
      expect(changes, [DateTime(2027)]);
      await press(t, 'left left left left down');
      expect(changes.skip(1), [DateTime(2026, 12, 31, 23)]);
      await press(t, 'left left left left left down');
      expect(changes.skip(2), [DateTime(2026, 12, 30, 23)]);
    });

    testTwk('with no date give today, within the bounds', (t) async {
      final value = ValueNotifier<DateTime?>(null);
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      await t.pumpWidget(
        picker(
          value,
          changes: changes,
          firstDate: DateTime(2026, 11, 2),
          autofocus: true,
        ),
        size: (30, 3),
      );
      await press(t, 'down');
      expect(changes, [DateTime(2026, 11, 2)]);
      await press(t, 'down up');
      expect(changes.skip(1), [DateTime(2026, 11, 3)]);
    });

    testTwk('step from the date typed, and do nothing while it is no date; '
        'keys that come before the app builds it again step from the date '
        'the last one gave', (t) async {
      final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 19));
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      await t.pumpWidget(
        picker(value, changes: changes, autofocus: true),
        size: (30, 3),
      );
      await press(t, 'backspace');
      await type(t, '0');
      await press(t, 'up');
      expect(changes, [DateTime(2026, 10, 11)]);
      await press(t, 'backspace backspace');
      await press(t, 'up');
      expect(changes, hasLength(1));
      await press(t, 'escape');
      // three keys in one read
      await t.input('\x1b[A\x1b[A\x1b[A'.codeUnits);
      await t.pump();
      expect(changes.skip(1), [
        DateTime(2026, 10, 12),
        DateTime(2026, 10, 13),
        DateTime(2026, 10, 14),
      ]);
    });

    testTwk('the wheel steps as they do while the field has the focus, and '
        'goes to the views around while it has not', (t) async {
      final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 19));
      addTearDown(value.dispose);
      final changes = <DateTime?>[];
      final wheel = <int>[];
      await t.pumpWidget(
        Listener(
          onScroll: (e) => wheel.add(e.scrollY),
          child: picker(value, changes: changes),
        ),
        size: (30, 3),
      );
      await t.mouse(MouseKind.wheelUp, 3, 0);
      await t.pump();
      expect(wheel, [-1]);
      await press(t, 'tab');
      await t.mouse(MouseKind.wheelUp, 3, 0);
      await t.pump();
      await t.mouse(MouseKind.wheelDown, 3, 0);
      await t.pump();
      expect(changes, [DateTime(2026, 10, 20), DateTime(2026, 10, 19)]);
      expect(wheel, [-1]);
    });
  });

  testTwk('disabled, with no onChanged, it is muted and takes neither the '
      'focus, which Tab passes by, nor the mouse', (t) async {
    final value = ValueNotifier<DateTime?>(DateTime(2026, 10, 19));
    addTearDown(value.dispose);
    await t.pumpWidget(
      Theme(data: ThemeData.dark, child: picker(value, enabled: false)),
      size: (30, 12),
    );
    final muted = ThemeData.dark.muted.fg;
    expect([t.cell(0, 0).fg, t.cell(15, 0).fg], [muted, muted]);
    await press(t, 'tab');
    expect(focused(t), 'next');
    await press(t, 'alt+down');
    await click(t, 15, 0);
    expect(t.lines[1], 'next');
    await click(t, 3, 0);
    expect(focused(t), 'next');
    expect(t.terminal.mouseTracking, MouseTracking.off);
  });

  testTwk('in a FormField: validated, a date picked takes the error away, '
      'Enter moves to the next field, saved and reset', (t) async {
    final form = GlobalKey<FormState>();
    final saved = <DateTime?>[];
    final node = FocusNode(debugLabel: 'date');
    final name = FocusNode(debugLabel: 'name');
    addTearDown(node.dispose);
    addTearDown(name.dispose);
    await t.pumpWidget(
      Overlay(
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FormField<DateTime>(
                validator: (v) => v == null ? 'when?' : null,
                onSaved: saved.add,
                builder: (field) => SizedBox(
                  width: 16,
                  child: DatePicker(
                    value: field.value,
                    onChanged: field.didChange,
                    today: today,
                    focusNode: node,
                  ),
                ),
              ),
              TextFormField(focusNode: name),
            ],
          ),
        ),
      ),
      size: (30, 14),
    );
    expect(form.currentState!.submit(), isFalse);
    await t.pump();
    expect(focused(t), 'date');
    expect(t.lines.take(2), ['yyyy-mm-dd     ▾', 'when?']);
    await press(t, 'alt+down enter');
    expect(t.lines.take(2), ['2026-10-19     ▾', '']);
    await press(t, 'enter');
    expect(focused(t), 'name');
    expect(form.currentState!.submit(), isTrue);
    expect(saved, [DateTime(2026, 10, 19)]);
    form.currentState!.reset();
    await t.pump();
    expect(t.lines.first, 'yyyy-mm-dd     ▾');
  });
}
