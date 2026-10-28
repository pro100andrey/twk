/// A month in weeks: [Calendar], the [CalendarController] that holds its
/// cursor and its selected date, and its [RenderCalendar].
library;

import 'package:twk_core/twk_core.dart'
    show
        Attr,
        BoxConstraints,
        Canvas,
        KeyCode,
        KeyEvent,
        KeyKind,
        Mod,
        PaintContext,
        RenderObject;

import '../focus/focus_tree.dart';
import '../focus/hinted_keys.dart';
import '../foundation/change_notifier.dart';
import '../foundation/helpers.dart';
import '../foundation/listenable_builder.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../gestures/mouse.dart';
import '../style/style.dart';
import 'chart_glyphs.dart';

// Examples can assume:
// late CalendarController dates;
// void book(DateTime date) {}

/// Where a [Calendar] is: its [cursor], the date its keys move, whose
/// [month] it shows, and its [selected] date, which Enter and Space set.
/// The cursor stays between [firstDate] and [lastDate]. It notifies its
/// listeners of each change.
///
/// What a date picker drives: it sets the date typed ([selected]), shows
/// another month ([month], [moveCursor]), and listens for the date chosen
/// ([Calendar.onSelected]) and the month shown.
///
/// Its dates are days: of a date it is given it reads the year, the month
/// and the day, whatever its time and zone; the dates it gives are local
/// ones at midnight, `DateTime(year, month, day)`.
///
/// A controller for the dates of this year, a day chosen, showing the
/// month after it:
///
/// ```dart
/// final dates = CalendarController(
///   selected: DateTime(2026, 10, 21),
///   firstDate: DateTime(2026),
///   lastDate: DateTime(2026, 12, 31),
/// );
/// dates.moveCursor(months: 1);
/// ```
final class CalendarController extends ChangeNotifier {
  /// The cursor on [cursor], else on [selected], else on today; moved
  /// within the bounds.
  CalendarController({
    DateTime? selected,
    DateTime? cursor,
    DateTime? firstDate,
    DateTime? lastDate,
  }) : _selected = _dayOrNull(selected),
       _first = _dayOrNull(firstDate),
       _last = _dayOrNull(lastDate),
       _cursor = dayOf(cursor ?? selected ?? DateTime.now()) {
    assert(
      _first == null || _last == null || _first! <= _last!,
      'firstDate after lastDate',
    );
    _cursor = _clamp(_cursor);
  }

  // days since 1970-01-01
  int? _selected;
  int _cursor;
  int? _first;
  int? _last;

  /// The date chosen; null for none. Enter and Space set it to the
  /// cursor's. Set, the cursor moves to it, within the bounds, and its
  /// month shows; the date itself is kept, inside the bounds or not.
  DateTime? get selected => _dateOrNull(_selected);

  set selected(DateTime? date) {
    final day = _dayOrNull(date);
    final cursor = day == null ? _cursor : _clamp(day);
    if (day != _selected || cursor != _cursor) {
      _selected = day;
      _cursor = cursor;
      notifyListeners();
    }
  }

  /// The date the keys move from, marked while the calendar has the focus;
  /// its month is the one shown. Set, it is moved within the bounds.
  DateTime get cursor => dateOfDay(_cursor);

  set cursor(DateTime date) => _moveTo(dayOf(date));

  /// The first day of the month shown: the cursor's. Set to a date of
  /// another month, the cursor moves to that month, as [moveCursor] does.
  DateTime get month {
    final c = utcOfDay(_cursor);
    return DateTime(c.year, c.month);
  }

  set month(DateTime date) {
    final c = utcOfDay(_cursor);
    moveCursor(months: (date.year - c.year) * 12 + date.month - c.month);
  }

  /// Moves the cursor [months] months, to the same day of the month or the
  /// last day of a shorter one, then [days] days; within the bounds.
  void moveCursor({int days = 0, int months = 0}) =>
      _moveTo(_addMonths(_cursor, months) + days);

  /// The earliest date the cursor may be on; null for no bound. The
  /// calendar shows the days before it in [Calendar.outsideStyle].
  DateTime? get firstDate => _dateOrNull(_first);

  set firstDate(DateTime? date) {
    final day = _dayOrNull(date);
    if (day != _first) {
      assert(day == null || _last == null || day <= _last!, 'after lastDate');
      _first = day;
      _cursor = _clamp(_cursor);
      notifyListeners();
    }
  }

  /// The latest date the cursor may be on; null for no bound. The calendar
  /// shows the days after it in [Calendar.outsideStyle].
  DateTime? get lastDate => _dateOrNull(_last);

  set lastDate(DateTime? date) {
    final day = _dayOrNull(date);
    if (day != _last) {
      assert(
        day == null || _first == null || day >= _first!,
        'before firstDate',
      );
      _last = day;
      _cursor = _clamp(_cursor);
      notifyListeners();
    }
  }

  void _moveTo(int day) {
    final d = _clamp(day);
    if (d != _cursor) {
      _cursor = d;
      notifyListeners();
    }
  }

  /// Whether [day] is within the bounds.
  bool _within(int day) => _clamp(day) == day;

  int _clamp(int day) {
    if (_first case final first? when day < first) {
      return first;
    }
    if (_last case final last? when day > last) {
      return last;
    }
    return day;
  }
}

/// The days of a month in weeks, a row each from [firstWeekday] — six
/// rows, so that every month is as tall — under a row of the weekdays'
/// names and, with [showHeader], the month's name and year, centered: the
/// month of the [controller]'s cursor ([CalendarController.month]). A day
/// is two columns wide, its number at their right, a blank column between
/// two days; with [showWeekNumbers], each row starts with its ISO 8601
/// week number: that of the week most of its days are in, its fourth
/// day's. 20 columns wide, 23 with the week numbers; 8 rows tall, 7
/// without the header; within the constraints, the rest of them blank.
///
/// While it has the focus, the arrows move the cursor a day or a week,
/// Page Up and Page Down a month, a year with Shift, Home and End to the
/// first and the last day of the month; Enter and Space select the
/// cursor's date ([CalendarController.selected]) and call [onSelected]
/// with it. Other keys go up to the nodes above its [Focus], Escape too.
/// A click of the left button on a day, within the controller's bounds,
/// focuses the calendar and selects the day as Enter does, a day of the
/// months around too ([showOutsideDays]), whose month then shows. One
/// that only shows a month takes no focus, nor clicks: [canRequestFocus]
/// false.
///
/// The styles, each merged over those before it: [style] for every cell,
/// over the theme's background and text; [headerStyle], [weekdayStyle] for
/// the names and the week numbers, [outsideStyle] for the days of the
/// months around ([showOutsideDays]) and those outside the controller's
/// bounds; then for a day [todayStyle], its [dayStyle], [selectedStyle]
/// and, while the calendar has the focus, [cursorStyle]. One left null is
/// the theme's: bold text, [ThemeData.muted], [ThemeData.muted],
/// [ThemeData.accent] in bold, [ThemeData.selection] and
/// [ThemeData.primary] reversed.
///
/// A repaint boundary: moving the cursor repaints nothing else. The month
/// is laid out as util-linux `cal` lays it out.
///
/// A calendar of the dates of a [CalendarController], with week numbers,
/// that books the date Enter, Space or a click picks:
///
/// ```dart
/// Calendar(controller: dates, showWeekNumbers: true, onSelected: book)
/// ```
///
/// See also:
///
///  * [CalendarController], what moves its cursor and holds the date
///    chosen.
final class Calendar extends StatefulWidget {
  /// Shows the month of [controller]'s cursor; asserts that
  /// [firstWeekday] is a weekday, and that there are 12 [monthNames] and 7
  /// [weekdayNames].
  const Calendar({
    super.key,
    this.controller,
    this.onSelected,
    this.today,
    this.firstWeekday = DateTime.monday,
    this.showHeader = true,
    this.showWeekNumbers = false,
    this.showOutsideDays = false,
    this.dayStyle,
    this.monthNames = englishMonthNames,
    this.weekdayNames = englishWeekdayNames,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus,
    this.keyHints = true,
    this.style,
    this.headerStyle,
    this.weekdayStyle,
    this.outsideStyle,
    this.todayStyle,
    this.selectedStyle,
    this.cursorStyle,
  }) : assert(
         firstWeekday >= DateTime.monday && firstWeekday <= DateTime.sunday,
         'firstWeekday from DateTime.monday to DateTime.sunday',
       ),
       assert(monthNames.length == 12, 'a name for each month'),
       assert(weekdayNames.length == 7, 'a name for each weekday');

  /// January to December.
  static const englishMonthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Monday to Sunday, two letters each.
  static const englishWeekdayNames = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  /// Where it is; null for one of its own, its cursor on [today].
  final CalendarController? controller;

  /// Called with the date Enter or Space selected.
  final void Function(DateTime date)? onSelected;

  /// The date shown in [todayStyle]; null for the date of the build.
  final DateTime? today;

  /// The weekday each row starts with, [DateTime.monday] to
  /// [DateTime.sunday].
  final int firstWeekday;

  /// Whether the month's name and year go above the weekdays' names.
  final bool showHeader;

  /// Whether each row starts with its ISO 8601 week number.
  final bool showWeekNumbers;

  /// Whether the days of the months before and after fill the rows around
  /// the month's days, in [outsideStyle]; blanks otherwise.
  final bool showOutsideDays;

  /// The style of a date's day, for its events; null for none. Called with
  /// each date shown on each paint; a new function repaints the calendar.
  final Style? Function(DateTime date)? dayStyle;

  /// The months' names, January first, which the header puts before the
  /// year.
  final List<String> monthNames;

  /// The weekdays' names, Monday first: each at the right of a day's two
  /// columns, cut off at them.
  final List<String> weekdayNames;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// See [FocusNode.canRequestFocus].
  final bool? canRequestFocus;

  /// Whether the keys it takes carry their hints, for a `KeyHintsBar`:
  /// `←↑↓→ move   pgup pgdn month   enter select` while it has the focus;
  /// false leaves them out, the keys doing what they do still.
  final bool keyHints;

  /// Every cell, the theme's background and text under it.
  final Style? style;

  /// The month's name and year; bold when null.
  final Style? headerStyle;

  /// The weekdays' names and the week numbers; [ThemeData.muted] when null.
  final Style? weekdayStyle;

  /// The days of the months around and those outside the bounds;
  /// [ThemeData.muted] when null.
  final Style? outsideStyle;

  /// [today]; [ThemeData.accent] in bold when null.
  final Style? todayStyle;

  /// The selected date; [ThemeData.selection] when null.
  final Style? selectedStyle;

  /// The cursor, while the calendar has the focus; [ThemeData.primary]
  /// reversed when null.
  final Style? cursorStyle;

  @override
  State<Calendar> createState() => _CalendarState();
}

final class _CalendarState extends State<Calendar> {
  CalendarController? _own;
  FocusNode? _ownNode;

  // what paints the month, which tells the date of a cell
  RenderCalendar? _month;

  CalendarController get _controller =>
      widget.controller ?? (_own ??= CalendarController(cursor: widget.today));

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void dispose() {
    _own?.dispose();
    _ownNode?.dispose();
    super.dispose();
  }

  /// A click on a day: within the controller's bounds, it picks the day as
  /// Enter does, and focuses the calendar.
  void _tapped(PointerEvent event) {
    final month = _month;
    final node = _node;
    if (month == null || month.owner == null || !node.canRequestFocus) {
      return;
    }
    final date = month.dateAt(event.x, event.y);
    final c = _controller;
    if (date == null || !c._within(dayOf(date))) {
      return;
    }
    node.requestFocus();
    c.cursor = date;
    _select(c);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // only while it has the focus, whichever keys reach its node
    if (event.kind == KeyKind.release || !node.hasFocus) {
      return KeyEventResult.ignored;
    }
    final c = _controller;
    switch ((event.code, event.modifiers)) {
      case (KeyCode.left, 0):
        c.moveCursor(days: -1);
      case (KeyCode.right, 0):
        c.moveCursor(days: 1);
      case (KeyCode.up, 0):
        c.moveCursor(days: -7);
      case (KeyCode.down, 0):
        c.moveCursor(days: 7);
      case (KeyCode.pageUp, 0):
        c.moveCursor(months: -1);
      case (KeyCode.pageDown, 0):
        c.moveCursor(months: 1);
      case (KeyCode.pageUp, Mod.shift):
        c.moveCursor(months: -12);
      case (KeyCode.pageDown, Mod.shift):
        c.moveCursor(months: 12);
      case (KeyCode.home, 0):
        c.cursor = c.month;
      case (KeyCode.end, 0):
        final month = c.month;
        c.cursor = DateTime(month.year, month.month + 1, 0);
      case (KeyCode.enter, 0):
        _select(c);
      case (KeyCode.char, 0) when event.char == ' ':
        _select(c);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// The keys [_onKey] takes, those a `KeyHintsBar` names; the arrows
  /// in the order their signs read, `←↑↓→`.
  static const _hints = {
    'left': 'move',
    'up': 'move',
    'down': 'move',
    'right': 'move',
    'pageup': 'month',
    'pagedown': 'month',
    'enter': 'select',
  };

  // _onKey takes each of them whenever its node has the focus, at the
  // bounds too
  static bool _takes(String key) => true;

  void _select(CalendarController c) {
    final date = c.cursor;
    c.selected = date;
    widget.onSelected?.call(date);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final node = _node;
    return HintedKeys(
      node: node,
      hints: widget.keyHints ? _hints : const {},
      takes: _takes,
      child: Focus(
        focusNode: node,
        autofocus: widget.autofocus,
        // its own node as Focus keeps its own: focusable unless told not
        canRequestFocus:
            widget.canRequestFocus ?? (widget.focusNode == null ? true : null),
        onKeyEvent: _onKey,
        child: GestureDetector(
          // one that takes no focus has the terminal report no mouse
          onTap: widget.canRequestFocus ?? node.canRequestFocus
              ? _tapped
              : null,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) =>
                _Month(this, controller, widget.today ?? DateTime.now()),
          ),
        ),
      ),
    );
  }
}

/// The month of a [Calendar] as its controller has it, with its theme's
/// styles where the calendar has none, and its cursor while the [Focus]
/// above it has the focus.
final class _Month extends LeafRenderObjectWidget {
  const _Month(this.state, this.controller, this.today);

  final _CalendarState state;
  final CalendarController controller;
  final DateTime today;

  @override
  RenderCalendar createRenderObject(BuildContext context) {
    final calendar = RenderCalendar(cursor: controller.cursor);
    updateRenderObject(context, calendar);
    return calendar;
  }

  @override
  void updateRenderObject(BuildContext context, RenderCalendar renderObject) {
    final c = state.widget;
    final theme = Theme.of(context);
    state._month = renderObject
      ..cursor = controller.cursor
      ..selected = controller.selected
      ..firstDate = controller.firstDate
      ..lastDate = controller.lastDate
      ..today = today
      ..firstWeekday = c.firstWeekday
      ..showHeader = c.showHeader
      ..showWeekNumbers = c.showWeekNumbers
      ..showOutsideDays = c.showOutsideDays
      ..showCursor = Focus.of(context).hasFocus
      ..dayStyle = c.dayStyle
      ..monthNames = c.monthNames
      ..weekdayNames = c.weekdayNames
      ..style = theme.background.merge(theme.text).merge(c.style ?? _plain)
      ..headerStyle = c.headerStyle ?? _bold
      ..weekdayStyle = c.weekdayStyle ?? theme.muted
      ..outsideStyle = c.outsideStyle ?? theme.muted
      ..todayStyle = c.todayStyle ?? theme.accent.merge(_bold)
      ..selectedStyle = c.selectedStyle ?? theme.selection
      ..cursorStyle = c.cursorStyle ?? theme.fill(theme.primary.fg);
  }
}

const _plain = Style();
const _bold = Style(attrs: Attr.bold);

/// What a [Calendar] lays out and paints: the month of [cursor], as
/// [Calendar] shows it, in the styles given, none of them the theme's. Its
/// dates are days, as a [CalendarController]'s are.
final class RenderCalendar extends RenderObject {
  /// Lays out and paints the month of [cursor], with the settings a
  /// [Calendar] has; the styles left out are plain.
  RenderCalendar({
    required DateTime cursor,
    DateTime? selected,
    DateTime? firstDate,
    DateTime? lastDate,
    DateTime? today,
    this._firstWeekday = DateTime.monday,
    this._showHeader = true,
    this._showWeekNumbers = false,
    this._showOutsideDays = false,
    this._showCursor = false,
    this._dayStyle,
    this._monthNames = Calendar.englishMonthNames,
    this._weekdayNames = Calendar.englishWeekdayNames,
    this._style = const Style(),
    this._headerStyle = const Style(),
    this._weekdayStyle = const Style(),
    this._outsideStyle = const Style(),
    this._todayStyle = const Style(),
    this._selectedStyle = const Style(),
    this._cursorStyle = const Style(),
  }) : _cursor = dayOf(cursor),
       _selected = _dayOrNull(selected),
       _first = _dayOrNull(firstDate),
       _last = _dayOrNull(lastDate),
       _today = _dayOrNull(today);

  // days since 1970-01-01
  int _cursor;
  int? _selected;
  int? _first;
  int? _last;
  int? _today;

  /// The date in [cursorStyle] while [showCursor]; its month is the one
  /// shown.
  DateTime get cursor => dateOfDay(_cursor);
  set cursor(DateTime date) {
    final day = dayOf(date);
    if (day != _cursor) {
      _cursor = day;
      markNeedsPaint();
    }
  }

  /// The date in [selectedStyle]; null for none.
  DateTime? get selected => _dateOrNull(_selected);
  set selected(DateTime? date) {
    final day = _dayOrNull(date);
    if (day != _selected) {
      _selected = day;
      markNeedsPaint();
    }
  }

  /// The first date not in [outsideStyle]; null for no bound.
  DateTime? get firstDate => _dateOrNull(_first);
  set firstDate(DateTime? date) {
    final day = _dayOrNull(date);
    if (day != _first) {
      _first = day;
      markNeedsPaint();
    }
  }

  /// The last date not in [outsideStyle]; null for no bound.
  DateTime? get lastDate => _dateOrNull(_last);
  set lastDate(DateTime? date) {
    final day = _dayOrNull(date);
    if (day != _last) {
      _last = day;
      markNeedsPaint();
    }
  }

  /// The date in [todayStyle]; null for none.
  DateTime? get today => _dateOrNull(_today);
  set today(DateTime? date) {
    final day = _dayOrNull(date);
    if (day != _today) {
      _today = day;
      markNeedsPaint();
    }
  }

  int _firstWeekday;

  /// The weekday each row starts with, as [Calendar.firstWeekday].
  int get firstWeekday => _firstWeekday;
  set firstWeekday(int d) {
    if (d != _firstWeekday) {
      _firstWeekday = d;
      markNeedsPaint();
    }
  }

  bool _showHeader;

  /// Whether the month's name and year go above the weekdays' names, as
  /// [Calendar.showHeader]; set, the calendar is laid out again.
  bool get showHeader => _showHeader;
  set showHeader(bool s) {
    if (s != _showHeader) {
      _showHeader = s;
      markNeedsLayout();
    }
  }

  bool _showWeekNumbers;

  /// Whether each row starts with its ISO 8601 week number, as
  /// [Calendar.showWeekNumbers]; set, the calendar is laid out again.
  bool get showWeekNumbers => _showWeekNumbers;
  set showWeekNumbers(bool s) {
    if (s != _showWeekNumbers) {
      _showWeekNumbers = s;
      markNeedsLayout();
    }
  }

  bool _showOutsideDays;

  /// Whether the days of the months around fill the rows, as
  /// [Calendar.showOutsideDays].
  bool get showOutsideDays => _showOutsideDays;
  set showOutsideDays(bool s) {
    if (s != _showOutsideDays) {
      _showOutsideDays = s;
      markNeedsPaint();
    }
  }

  bool _showCursor;

  /// Whether the cursor is in [cursorStyle].
  bool get showCursor => _showCursor;
  set showCursor(bool s) {
    if (s != _showCursor) {
      _showCursor = s;
      markNeedsPaint();
    }
  }

  Style? Function(DateTime date)? _dayStyle;

  /// The style of a date's day, as [Calendar.dayStyle]; another function
  /// repaints.
  Style? Function(DateTime date)? get dayStyle => _dayStyle;
  set dayStyle(Style? Function(DateTime date)? f) {
    if (!identical(f, _dayStyle)) {
      _dayStyle = f;
      markNeedsPaint();
    }
  }

  List<String> _monthNames;

  /// The months' names, January first, as [Calendar.monthNames].
  List<String> get monthNames => _monthNames;
  set monthNames(List<String> names) {
    if (!sameList(names, _monthNames)) {
      _monthNames = names;
      markNeedsPaint();
    }
  }

  List<String> _weekdayNames;

  /// The weekdays' names, Monday first, as [Calendar.weekdayNames].
  List<String> get weekdayNames => _weekdayNames;
  set weekdayNames(List<String> names) {
    if (!sameList(names, _weekdayNames)) {
      _weekdayNames = names;
      markNeedsPaint();
    }
  }

  Style _style;

  /// Every cell, the others merged over it.
  Style get style => _style;
  set style(Style s) {
    if (s != _style) {
      _style = s;
      markNeedsPaint();
    }
  }

  Style _headerStyle;

  /// The month's name and year.
  Style get headerStyle => _headerStyle;
  set headerStyle(Style s) {
    if (s != _headerStyle) {
      _headerStyle = s;
      markNeedsPaint();
    }
  }

  Style _weekdayStyle;

  /// The weekdays' names and the week numbers.
  Style get weekdayStyle => _weekdayStyle;
  set weekdayStyle(Style s) {
    if (s != _weekdayStyle) {
      _weekdayStyle = s;
      markNeedsPaint();
    }
  }

  Style _outsideStyle;

  /// The days of the months around and those outside [firstDate] and
  /// [lastDate].
  Style get outsideStyle => _outsideStyle;
  set outsideStyle(Style s) {
    if (s != _outsideStyle) {
      _outsideStyle = s;
      markNeedsPaint();
    }
  }

  Style _todayStyle;

  /// [today], merged under its [dayStyle].
  Style get todayStyle => _todayStyle;
  set todayStyle(Style s) {
    if (s != _todayStyle) {
      _todayStyle = s;
      markNeedsPaint();
    }
  }

  Style _selectedStyle;

  /// [selected], merged over its [dayStyle].
  Style get selectedStyle => _selectedStyle;
  set selectedStyle(Style s) {
    if (s != _selectedStyle) {
      _selectedStyle = s;
      markNeedsPaint();
    }
  }

  Style _cursorStyle;

  /// [cursor] while [showCursor], merged over the others.
  Style get cursorStyle => _cursorStyle;
  set cursorStyle(Style s) {
    if (s != _cursorStyle) {
      _cursorStyle = s;
      markNeedsPaint();
    }
  }

  @override
  bool get isRepaintBoundary => true;

  // the column the days start at and the row of the first week
  int get _left => _showWeekNumbers ? 3 : 0;
  int get _top => _showHeader ? 2 : 1;

  @override
  int computeMinIntrinsicWidth(int height) => _left + 20;

  @override
  int computeMaxIntrinsicWidth(int height) => _left + 20;

  @override
  int computeMinIntrinsicHeight(int width) => _top + 6;

  @override
  int computeMaxIntrinsicHeight(int width) => _top + 6;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(_left + 20);
    height = c.constrainH(_top + 6);
  }

  /// The first day of the month shown, its length, and the first day of
  /// its first row.
  (int, int, int) get _grid {
    final c = utcOfDay(_cursor);
    final first = dayOf(DateTime.utc(c.year, c.month));
    final length = DateTime.utc(c.year, c.month + 1, 0).day;
    return (first, length, first - (weekdayOfDay(first) - _firstWeekday) % 7);
  }

  /// The date whose day is at ([x], [y]), on either of its two columns;
  /// null where no day is shown.
  DateTime? dateAt(int x, int y) {
    final col = x - _left;
    final row = y - _top;
    if (x >= width ||
        y >= height ||
        col < 0 ||
        col >= 20 ||
        col % 3 == 2 ||
        row < 0 ||
        row >= 6) {
      return null;
    }
    final (first, length, start) = _grid;
    final day = start + row * 7 + col ~/ 3;
    final outside = day < first || day >= first + length;
    return outside && !_showOutsideDays ? null : dateOfDay(day);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    final base = opaque(_style);
    canvas.fill(0, 0, width, height, base.penIn(styles));
    final left = _left;
    final (first, length, start) = _grid;
    if (_showHeader) {
      final month = utcOfDay(first);
      final title = '${_monthNames[month.month - 1]} ${month.year}';
      final w = canvas.segmenter.width(title);
      canvas.text(
        left + (w < 20 ? (20 - w) ~/ 2 : 0),
        0,
        title,
        base.merge(_headerStyle).penIn(styles),
      );
    }
    final names = base.merge(_weekdayStyle).penIn(styles);
    final top = _top;
    for (var col = 0; col < 7; col++) {
      final name = _weekdayNames[(_firstWeekday - 1 + col) % 7];
      _cell(canvas, left + 3 * col, top - 1, name, names);
    }
    for (var row = 0; row < 6; row++) {
      final y = top + row;
      final from = start + row * 7;
      final inMonth = from < first + length && from + 6 >= first;
      if (!inMonth && !_showOutsideDays) {
        continue;
      }
      if (_showWeekNumbers) {
        _cell(canvas, 0, y, '${_isoWeek(from + 3)}', names);
      }
      for (var col = 0; col < 7; col++) {
        final day = from + col;
        final outside = day < first || day >= first + length;
        if (outside && !_showOutsideDays) {
          continue;
        }
        var s = base;
        if (outside ||
            (_first != null && day < _first!) ||
            (_last != null && day > _last!)) {
          s = s.merge(_outsideStyle);
        }
        if (day == _today) {
          s = s.merge(_todayStyle);
        }
        if (_dayStyle?.call(dateOfDay(day)) case final own?) {
          s = s.merge(own);
        }
        if (day == _selected) {
          s = s.merge(_selectedStyle);
        }
        if (_showCursor && day == _cursor) {
          s = s.merge(_cursorStyle);
        }
        _cell(
          canvas,
          left + 3 * col,
          y,
          '${utcOfDay(day).day}',
          s.penIn(styles),
        );
      }
    }
  }

  /// Fills the two columns from ([x], [y]) in [pen] and draws [text] at
  /// their right, cut off at them.
  static void _cell(Canvas canvas, int x, int y, String text, int pen) {
    final w = canvas.segmenter.width(text);
    canvas
      ..fill(x, y, 2, 1, pen)
      ..save()
      ..clipRect(x, y, 2, 1)
      ..text(w < 2 ? x + 2 - w : x, y, text, pen)
      ..restore();
  }
}

/// [dayOf] of [date]; null for none.
int? _dayOrNull(DateTime? date) => date == null ? null : dayOf(date);

/// [dateOfDay] of [day]; null for none.
DateTime? _dateOrNull(int? day) => day == null ? null : dateOfDay(day);

/// The ISO 8601 week of [day]: weeks from Monday, numbered in the year
/// their Thursday is in.
int _isoWeek(int day) {
  final thursday = day + DateTime.thursday - weekdayOfDay(day);
  final january = dayOf(DateTime.utc(utcOfDay(thursday).year));
  return (thursday - january) ~/ 7 + 1;
}

/// The day [months] months after [day]: the same day of the month, or the
/// last day of a shorter month.
int _addMonths(int day, int months) {
  if (months == 0) {
    return day;
  }
  final d = utcOfDay(day);
  final month = DateTime.utc(d.year, d.month + months);
  final length = DateTime.utc(month.year, month.month + 1, 0).day;
  return dayOf(
    DateTime.utc(month.year, month.month, d.day < length ? d.day : length),
  );
}
