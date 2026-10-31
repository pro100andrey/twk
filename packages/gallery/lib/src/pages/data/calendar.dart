// The Calendar page.
part of 'data.dart';

// ------------------------------------------------------------ Calendar

final _today = DateTime(2026, 10, 19);

/// The days of October 2026 with a meeting, which the marked days show.
const _meetings = {6, 13, 22, 27};

/// Whether [date] has a meeting.
bool _meeting(DateTime date) =>
    date.year == 2026 && date.month == 10 && _meetings.contains(date.day);

/// The Calendar page's `firstWeekday` option.
const _calendarFirstWeekday = ChoiceOption<int>(
  'firstWeekday',
  'first day',
  values: [DateTime.monday, DateTime.sunday],
  labels: ['monday', 'sunday'],
);

/// The Calendar page's `weeks` option.
const _calendarWeeks = SwitchOption('weeks', 'week numbers');

/// The Calendar page's `outside` option.
const _calendarOutside = SwitchOption('outside', 'outside days');

/// The Calendar page's `marked` option.
const _calendarMarked = SwitchOption('marked', 'marked days');

final _calendar = GalleryPage(
  group: _group,
  title: 'Calendar',
  options: const [
    _calendarFirstWeekday,
    _calendarWeeks,
    _calendarOutside,
    _calendarMarked,
  ],
  build: (context, o) => _Month(
    firstWeekday: o(_calendarFirstWeekday),
    weeks: o(_calendarWeeks),
    outside: o(_calendarOutside),
    marked: o(_calendarMarked),
  ),
  // the title, the weekdays, six weeks, a gap and the line under it,
  // whatever the month
  heightIn: (o, room) => 10,
  code: (o) => [
    'DateTime? _selected;',
    '',
    if (o(_calendarMarked)) ...[
      '/// The days of October 2026 with a meeting.',
      'static const _meetings = {${_meetings.join(', ')}};',
      '',
      'static bool _meeting(DateTime date) =>',
      codeLine([
        '    date.year == 2026 && date.month == 10 && ',
        '_meetings.contains(date.day);',
      ]),
      '',
    ],
    '@override',
    'Widget build(BuildContext context) => Column(',
    '  mainAxisSize: .min,',
    '  crossAxisAlignment: .start,',
    '  gap: 1,',
    '  children: [',
    '    Calendar(',
    '      today: DateTime(2026, 10, 19),',
    if (o(_calendarFirstWeekday) == DateTime.sunday)
      '      firstWeekday: DateTime.sunday,',
    if (o(_calendarWeeks)) '      showWeekNumbers: true,',
    if (o(_calendarOutside)) '      showOutsideDays: true,',
    if (o(_calendarMarked)) ...[
      '      dayStyle: (date) =>',
      '          _meeting(date) ? Theme.of(context).warning : null,',
    ],
    '      onSelected: (date) => setState(() => _selected = date),',
    '    ),',
    '    Text.rich([',
    "      Span('selected: ', Theme.of(context).muted),",
    '      switch (_selected) {',
    "        null => Span('nothing', Theme.of(context).muted),",
    '        final date => Span(date.toIso8601String().substring(0, 10)),',
    '      },',
    '    ]),',
    '  ],',
    ');',
  ].join('\n'),
);

/// A month to pick a day of, and the day picked.
final class _Month extends StatefulWidget {
  const _Month({
    required this.firstWeekday,
    required this.weeks,
    required this.outside,
    required this.marked,
  });

  final int firstWeekday;
  final bool weeks;
  final bool outside;
  final bool marked;

  @override
  State<_Month> createState() => _MonthState();
}

final class _MonthState extends State<_Month> with KeptState {
  // kept in the page's state while the gallery runs
  late final _controller =
      (kept['calendar'] ??= CalendarController(cursor: _today))
          as CalendarController;
  int get _picked => kept['picked'] as int? ?? 0;

  @override
  Widget build(BuildContext context) {
    final selected = _controller.selected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Calendar(
          controller: _controller,
          today: _today,
          firstWeekday: widget.firstWeekday,
          showWeekNumbers: widget.weeks,
          showOutsideDays: widget.outside,
          dayStyle: widget.marked
              ? (date) => _meeting(date) ? Theme.of(context).warning : null
              : null,
          onSelected: (date) => setState(() => kept['picked'] = _picked + 1),
        ),
        LitLine([
          ('selected: ', true),
          (
            selected?.toIso8601String().substring(0, 10) ?? 'nothing',
            selected == null,
          ),
        ], serial: _picked),
      ],
    );
  }
}
