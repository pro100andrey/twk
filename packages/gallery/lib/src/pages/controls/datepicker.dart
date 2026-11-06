// The DatePicker page.
part of 'controls.dart';

/// The DatePicker page's `time` option.
const _datepickerTime = SwitchOption('time', 'time of day');

/// The DatePicker page's `week` option.
const _datepickerWeek = ChoiceOption<int>(
  'week',
  'weeks start',
  values: [1, 7],
  labels: ['monday', 'sunday'],
);

final _datepickerPage = GalleryPage(
  group: _group,
  title: 'DatePicker',
  // Tab stays in the open calendar's FocusScope
  modalTab: false,
  options: [
    _datepickerTime,
    _datepickerWeek,
    popupLookOption(),
  ],
  build: (context, o) => _Date(
    time: o(_datepickerTime),
    firstWeekday: o(_datepickerWeek),
    popupLook: popupLookOf(o),
  ),
  code: (o) {
    final time = o(_datepickerTime);
    return [
      'final _calendar = PopupController();',
      'DateTime? _date;',
      '',
      'static const _days = [',
      for (final d in _days) "  '$d',",
      '];',
      '',
      '@override',
      'void dispose() {',
      '  _calendar.dispose();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) => Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  spacing: 1,',
      '  children: [',
      '    Row(',
      '      mainAxisSize: .min,',
      '      spacing: 2,',
      '      children: [',
      '        SizedBox(',
      '          width: 22,',
      '          child: DatePicker(',
      '            value: _date,',
      if (time) '            showTime: true,',
      '            firstDate: DateTime(2026),',
      '            lastDate: DateTime(2026, 12, 31),',
      '            today: DateTime(2026, 10, 19),',
      if (o(_datepickerWeek) == 7) '            firstWeekday: DateTime.sunday,',
      ...popupLookArg(o, '            '),
      '            controller: _calendar,',
      '            onChanged: (date) => setState(() => _date = date),',
      '          ),',
      '        ),',
      '        // opens the calendar, the focus in it',
      "        Button('Calendar', onPressed: _calendar.open),",
      '      ],',
      '    ),',
      '    Text.rich([',
      "      Span('picked: ', Theme.of(context).muted),",
      '      switch (_date) {',
      "        null => Span('nothing', Theme.of(context).muted),",
      '        final date => Span(',
      r"          '${_days[date.weekday - 1]}, ${date.day} '",
      if (time)
        r"          '${Calendar.englishMonthNames[date.month - 1]}, '"
      else
        r"          '${Calendar.englishMonthNames[date.month - 1]}',",
      if (time) ...[
        r"          '${'${date.hour}'.padLeft(2, '0')}:'",
        r"          '${'${date.minute}'.padLeft(2, '0')}',",
      ],
      '        ),',
      '      },',
      '    ]),',
      '  ],',
      ');',
    ].join('\n');
  },
);

const _days = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// A day of 2026 picked, typed or stepped, with its time of day or not.
final class _Date extends StatefulWidget {
  const _Date({
    required this.time,
    required this.firstWeekday,
    required this.popupLook,
  });

  final bool time;
  final int firstWeekday;
  final PanelLook popupLook;

  @override
  State<_Date> createState() => _DateState();
}

final class _DateState extends State<_Date> with KeptState {
  final _calendar = PopupController();

  @override
  void dispose() {
    _calendar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final date = keptOr<DateTime?>('date', null);
    String two(int n) => '$n'.padLeft(2, '0');
    final at = date == null || !widget.time
        ? ''
        : ', ${two(date.hour)}:${two(date.minute)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 1,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            SizedBox(
              width: 22,
              child: DatePicker(
                value: date,
                showTime: widget.time,
                firstDate: DateTime(2026),
                lastDate: DateTime(2026, 12, 31),
                today: DateTime(2026, 10, 19),
                firstWeekday: widget.firstWeekday,
                popupLook: widget.popupLook,
                controller: _calendar,
                onChanged: (date) => keep('date', date),
              ),
            ),
            Button('Calendar', onPressed: _calendar.open),
          ],
        ),
        LitLine([
          ('picked: ', true),
          if (date == null)
            ('nothing', true)
          else
            (
              '${_days[date.weekday - 1]}, ${date.day} '
                  '${Calendar.englishMonthNames[date.month - 1]}$at',
              false,
            ),
        ], serial: serial),
      ],
    );
  }
}
