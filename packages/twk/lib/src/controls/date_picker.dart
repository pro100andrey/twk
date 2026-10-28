/// A date typed in a field or picked from a calendar: [DatePicker].
library;

import 'package:twk_core/twk_core.dart' show Attr;

import '../data/calendar.dart';
import '../editing/text_editing.dart';
import '../focus/focus.dart';
import '../focus/hinted_keys.dart';
import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../overlay/panel.dart';
import '../overlay/popover.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'number_input.dart' show TypedInputState;
import 'select.dart' show PopupController, PopupHostState;

/// A field for a date, typed, stepped with the keys or picked from a
/// [Calendar] that opens under it.
///
/// With [showTime], the date has its time of day too. The field has `▾`
/// after it, and is typed as `yyyy-mm-dd` (with the time `yyyy-mm-dd
/// hh:mm`, 24 hours). Empty, the field stands for no date, null, and shows
/// the format in [ThemeData.muted].
///
/// A date of this year, held by the app:
///
/// ```dart
/// final due = ValueNotifier<DateTime?>(null);
/// final picker = ValueListenableBuilder(
///   valueListenable: due,
///   builder: (context, value, _) => DatePicker(
///     value: value,
///     firstDate: DateTime(2026),
///     lastDate: DateTime(2026, 12, 31),
///     onChanged: (date) => due.value = date,
///   ),
/// );
/// ```
///
/// The text typed is taken as Enter is pressed, which goes on to the nodes
/// above (a `Form` moves to the next field), and as the focus leaves the
/// field: a date of the calendar, the month and the day of one digit or
/// two, the time left out for midnight; one before [firstDate] or after
/// [lastDate] as that bound's date, at the same time. Text that is no date
/// gives way to the value. Meanwhile the field shows such text in
/// [errorStyle], [ThemeData.error] when null, and Escape puts the value
/// back; taken out of the tree, the field takes nothing. The bounds are of
/// the day: the time of day is any.
///
/// While the field has the focus, Up and Down (and the wheel over it)
/// step the part of the date the caret is in, as a calendar does: a year
/// or a month, to the same day or the last of a shorter month, a day, an
/// hour or a minute, later and earlier; from the date typed, if one is.
/// The caret is put at the end of that part. With no date, they give
/// [today], the caret at its end. Alt+Down opens the calendar (hinted, as
/// are Up and Down), as does a press of the left button on `▾`, which a
/// second one closes; a press on the field focuses it, and closes the
/// calendar.
///
/// The calendar shows the month of the date, or of [today], in a popup
/// under the field, a [Panel] as [popupLook] says: of the theme's surface,
/// a cell of room around the calendar, or a border there. The date is
/// selected, the days outside the bounds muted, the cursor in
/// [cursorStyle], filled with [ThemeData.primary] and bold in
/// [ThemeData.onPrimary] when null; its rows start with [firstWeekday]. It
/// has the focus while it is open, and its keys (see [Calendar]), hinted as
/// a date picker's (`←↑↓→ day   pgup pgdn month   enter pick`): Enter or
/// Space on a date, or a click on one within the bounds, takes that date,
/// at the time the value has, and closes it; the wheel over it shows the
/// month before or after. Escape, the focus leaving it and the field and a
/// press outside both close it; the field gets the focus back where the
/// calendar had it.
///
/// Each calls [onChanged] with the date it is to take, once that is
/// another; the app builds it with that one, and the field shows it. Keys
/// that come before the app builds it again step from the date the last
/// one gave. Disabled with no [onChanged]: then it is muted, and takes
/// neither the focus, which Tab passes by, nor the mouse.
///
/// A row as wide as it may be, the field a `TextField` (the keys that edit
/// it are its), in [style] over the theme's surface and text; where its
/// width is not bounded, as wide as its text. While it has the focus the
/// field is in [focusedStyle], [ThemeData.selection] when null, and then
/// shows its selection a step towards [ThemeData.primary]. `▾` is in
/// [ThemeData.primary] while the field has the focus or the calendar is
/// open (in bold), in [arrowStyle] otherwise ([ThemeData.muted] when
/// null), [ThemeData.muted] while it is disabled. `focusedStyle: const
/// Style()`, `arrowStyle: theme.primary`, `popupLook: PanelLook.bordered`
/// and `cursorStyle: theme.primary.merge(const Style(attrs:
/// Attr.reverse))` give a plain look: the field without a fill, the
/// calendar in a border, its cursor reversed.
///
/// The popup needs an `Overlay` above, as a [Popover] does. With a
/// [controller], the app opens and closes the calendar and hears it open
/// and close.
///
/// See also:
///
///  * [Calendar], the month to pick a day from, without the field.
///  * [PopupController], which opens and closes the calendar.
final class DatePicker extends StatefulWidget {
  /// A field for [value], which [onChanged] changes; disabled when that is
  /// null.
  ///
  /// [firstWeekday] is one of [DateTime.monday] to [DateTime.sunday],
  /// which it asserts.
  const DatePicker({
    required this.value,
    required this.onChanged,
    super.key,
    this.controller,
    this.firstDate,
    this.lastDate,
    this.showTime = false,
    this.today,
    this.firstWeekday = DateTime.monday,
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.focusedStyle,
    this.arrowStyle,
    this.errorStyle,
    this.popupLook = PanelLook.raised,
    this.popupFadeIn = const Duration(milliseconds: 120),
    this.cursorStyle,
  }) : assert(
         firstWeekday >= DateTime.monday && firstWeekday <= DateTime.sunday,
         'firstWeekday from DateTime.monday to DateTime.sunday',
       );

  /// The date shown; null for none.
  final DateTime? value;

  /// Called with the date the field is to take, null for none; null for a
  /// disabled field.
  final void Function(DateTime? date)? onChanged;

  /// Opens and closes the calendar, and says whether it is open; null for
  /// one of its own. Opened by it, the calendar has the focus, the field
  /// getting it back as it closes.
  final PopupController? controller;

  /// The earliest day it takes; null for no bound.
  final DateTime? firstDate;

  /// The latest day it takes; null for no bound.
  final DateTime? lastDate;

  /// Whether the field shows and takes the time of day, in hours and
  /// minutes.
  final bool showTime;

  /// The date the calendar shows as today, and Up and Down give with no
  /// date; null for the date of the build.
  final DateTime? today;

  /// The weekday the calendar's rows start with, [DateTime.monday] to
  /// [DateTime.sunday].
  final int firstWeekday;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// The field, the theme's surface and text under it.
  final Style? style;

  /// The field while it has the focus, over [style];
  /// [ThemeData.selection] when null.
  final Style? focusedStyle;

  /// `▾` while the field has not the focus and the calendar is closed;
  /// [ThemeData.muted] when null.
  final Style? arrowStyle;

  /// The field while its text is no date, or one beyond the bounds;
  /// [ThemeData.error] when null.
  final Style? errorStyle;

  /// How the calendar's popup stands out of what is under it.
  final PanelLook popupLook;

  /// How long the calendar's popup takes to fade in from what is under it
  /// as it opens, easing out; 120 ms by default, zero for at once.
  final Duration popupFadeIn;

  /// The calendar's cursor; [ThemeData.primary] filled,
  /// [ThemeData.onPrimary] in bold on it, when null.
  final Style? cursorStyle;

  @override
  State<DatePicker> createState() => _DatePickerState();
}

final class _DatePickerState extends State<DatePicker>
    with TypedInputState<DatePicker, DateTime?>, PopupHostState<DatePicker> {
  // whether the calendar is open, as the controller said last
  var _open = false;
  final _calendar = CalendarController();
  final _calendarNode = FocusNode();

  PopupController? _ownPopup;

  PopupController get _popup =>
      widget.controller ?? (_ownPopup ??= PopupController());

  @override
  DateTime? get widgetValue => widget.value;

  @override
  void Function(DateTime? date)? get onChanged => widget.onChanged;

  @override
  FocusNode? get focusNode => widget.focusNode;

  @override
  void initState() {
    super.initState();
    _popup.addListener(_popupChanged);
    attachPopup(widget.controller);
    if (_popup.isOpen && enabled) {
      _showMonth();
      _open = true;
    }
    _settle();
  }

  @override
  void didUpdateWidget(DatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      (oldWidget.controller ?? _ownPopup)?.removeListener(_popupChanged);
      detachPopup(oldWidget.controller);
      _popup.addListener(_popupChanged);
      attachPopup(widget.controller);
      // as the new one says, built now
      final open = _popup.isOpen && enabled;
      if (open && !_open) {
        _showMonth();
      }
      _open = open;
    } else if (_open && !enabled) {
      _open = false;
    }
    _settle();
  }

  /// The controller closed after the build while the field is disabled.
  void _settle() {
    if (_popup.isOpen && !enabled) {
      closePopupAfterBuild(_popup);
    }
  }

  @override
  void dispose() {
    _popup.removeListener(_popupChanged);
    detachPopup(widget.controller);
    _ownPopup?.dispose();
    _calendar.dispose();
    _calendarNode.dispose();
    super.dispose();
  }

  DateTime get _today {
    final today = widget.today ?? DateTime.now();
    return DateTime(today.year, today.month, today.day);
  }

  @override
  String format(DateTime? value) {
    if (value == null) {
      return '';
    }
    final date =
        '${_digits(value.year, 4)}-${_digits(value.month, 2)}-'
        '${_digits(value.day, 2)}';
    return widget.showTime
        ? '$date ${_digits(value.hour, 2)}:${_digits(value.minute, 2)}'
        : date;
  }

  static String _digits(int n, int count) => '$n'.padLeft(count, '0');

  static final _date = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?: (\d{1,2}):(\d{2}))?$',
  );

  @override
  ({DateTime? value})? parse(String text) {
    final t = text.trim();
    if (t.isEmpty) {
      return (value: null);
    }
    final m = _date.firstMatch(t);
    if (m == null || (m[4] != null && !widget.showTime)) {
      return null;
    }
    final [year, month, day, hour, minute] = [
      for (var i = 1; i <= 5; i++) int.parse(m[i] ?? '0'),
    ];
    final date = DateTime(year, month, day, hour, minute);
    // an hour beyond 23 is another day
    if (date.year != year ||
        date.month != month ||
        date.day != day ||
        minute > 59) {
      return null;
    }
    return (value: date);
  }

  @override
  bool fits(DateTime? value) {
    if (value == null) {
      return true;
    }
    final DatePicker(:firstDate, :lastDate) = widget;
    final day = dayOf(value);
    return (firstDate == null || day >= dayOf(firstDate)) &&
        (lastDate == null || day <= dayOf(lastDate));
  }

  @override
  DateTime? clamp(DateTime? value) {
    if (value == null) {
      return null;
    }
    final DatePicker(:firstDate, :lastDate) = widget;
    final day = dayOf(value);
    final bound = firstDate != null && day < dayOf(firstDate)
        ? firstDate
        : lastDate != null && day > dayOf(lastDate)
        ? lastDate
        : null;
    return bound == null
        ? value
        : DateTime(
            bound.year,
            bound.month,
            bound.day,
            value.hour,
            value.minute,
          );
  }

  /// The part of the text the caret is in: 0 the year, 1 the month, 2 the
  /// day, 3 the hour, 4 the minute.
  int get _part {
    final text = controller.text;
    final at = controller.selection.extentOffset;
    final before = text.substring(0, at < text.length ? at : text.length);
    final date = before.trimLeft();
    if (widget.showTime && date.contains(' ')) {
      return date.contains(':') ? 4 : 3;
    }
    final dashes = '-'.allMatches(date).length;
    return dashes < 2 ? dashes : 2;
  }

  @override
  DateTime? stepped(DateTime? from, int count) {
    if (from == null) {
      return _today;
    }
    final DateTime(:year, :month, :day, :hour, :minute) = from;
    return switch (_part) {
      0 => _addMonths(from, 12 * count),
      1 => _addMonths(from, count),
      2 => DateTime(year, month, day + count, hour, minute),
      3 => DateTime(year, month, day, hour + count, minute),
      _ => DateTime(year, month, day, hour, minute + count),
    };
  }

  /// [date] [months] months on: the same day of the month, or the last day
  /// of a shorter month.
  static DateTime _addMonths(DateTime date, int months) {
    final first = DateTime(date.year, date.month + months);
    final length = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(
      first.year,
      first.month,
      date.day < length ? date.day : length,
      date.hour,
      date.minute,
    );
  }

  void _step(int count) {
    // with no date, the caret at the end of today's
    final part = controller.text.trim().isEmpty ? null : _part;
    if (stepBy(count) && part != null) {
      final end = const [4, 7, 10, 13, 16][part];
      final length = controller.text.length;
      controller.selection = TextSelection.collapsed(
        offset: end < length ? end : length,
      );
    }
  }

  void _openCalendar() => _popup.open();

  /// Closes the calendar: where it had the focus, the field focused
  /// before it gets it back.
  void _close() {
    if (servesPopup(widget.controller)) {
      _popup.close();
    }
  }

  /// Opens or closes the calendar as the controller says: a disabled field
  /// keeps it closed. Opened, it shows the month of the date typed, which
  /// is taken first, the field focused so that it gets the focus back.
  void _popupChanged() {
    if (!servesPopup(widget.controller)) {
      return;
    }
    final open = _popup.isOpen;
    if (open && !enabled) {
      _popup.close();
      return;
    }
    if (open == _open) {
      return;
    }
    if (open) {
      node.requestFocus();
      commit();
      _showMonth();
    }
    setState(() => _open = open);
  }

  /// Puts the calendar on the date, or on today.
  void _showMonth() {
    final date = value;
    _calendar
      ..firstDate = null
      ..lastDate = widget.lastDate
      ..firstDate = widget.firstDate
      ..selected = date
      ..cursor = date ?? _today;
  }

  /// The calendar's keys as a date picker names them, in place of
  /// [Calendar]'s own hints.
  static const _calendarHints = {
    'left': 'day',
    'up': 'day',
    'down': 'day',
    'right': 'day',
    'pageup': 'month',
    'pagedown': 'month',
    'enter': 'pick',
  };

  // the calendar takes each of them whenever it has the focus
  static bool _takes(String key) => true;

  void _choose(DateTime date) {
    final v = value;
    _close();
    change(
      clamp(
        widget.showTime && v != null
            ? DateTime(date.year, date.month, date.day, v.hour, v.minute)
            : date,
      ),
    );
  }

  void _toggle(PointerEvent event) {
    if (event.button != 0) {
      return;
    }
    node.requestFocus();
    if (_open) {
      _close();
    } else {
      _openCalendar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Popover(
      open: _open,
      onDismiss: _close,
      fadeIn: widget.popupFadeIn,
      popover: FocusScope(
        child: Panel(
          look: widget.popupLook,
          shadow: false,
          child: Listener(
            onScroll: (event) =>
                _calendar.moveCursor(months: event.scrollY + event.scrollX),
            child: HintedKeys(
              node: _calendarNode,
              hints: _calendarHints,
              takes: _takes,
              child: Calendar(
                controller: _calendar,
                focusNode: _calendarNode,
                keyHints: false,
                onSelected: _choose,
                today: _today,
                firstWeekday: widget.firstWeekday,
                autofocus: true,
                style: theme.surface,
                cursorStyle:
                    widget.cursorStyle ??
                    Style(
                      fg: theme.onPrimary.fg,
                      bg: theme.primary.fg,
                      attrs: Attr.bold,
                    ),
              ),
            ),
          ),
        ),
      ),
      child: buildField(
        context,
        keys: {
          'up': () => _step(1),
          'down': () => _step(-1),
          'alt+down': _openCalendar,
        },
        hints: const {'up': 'later', 'down': 'earlier', 'alt+down': 'calendar'},
        onWheel: (event) => _step(event.scrollX - event.scrollY),
        onPressed: _close,
        placeholder: widget.showTime ? 'yyyy-mm-dd hh:mm' : 'yyyy-mm-dd',
        autofocus: widget.autofocus,
        style: widget.style,
        focusedStyle: widget.focusedStyle,
        errorStyle: widget.errorStyle,
        trailing: Listener(
          onDown: enabled ? _toggle : null,
          child: Text(
            '▾',
            style: theme.text.merge(
              !enabled
                  ? theme.muted
                  : _open
                  ? theme.primary.merge(const Style(attrs: Attr.bold))
                  : node.hasFocus
                  ? theme.primary
                  : widget.arrowStyle ?? theme.muted,
            ),
          ),
        ),
      ),
    );
  }
}
