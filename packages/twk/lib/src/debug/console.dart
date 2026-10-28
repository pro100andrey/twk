/// The log console: a [ConsoleController] over an app's [LogSink], and
/// the [Console] that shows an app with the console listing its records
/// over it.
library;

import 'dart:convert';

import 'package:twk_core/twk_core.dart'
    show
        Attr,
        BoxConstraints,
        Canvas,
        DiagnosticPropertiesBuilder,
        LogLevel,
        LogRecord,
        LogSink,
        PaintContext,
        PipelineOwner,
        RenderObject,
        StyleTable,
        TerminalBackend,
        clipboardSequence;

import '../binding/app_binding.dart';
import '../data/chart_glyphs.dart' show opaque;
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../layout/flex.dart';
import '../layout/stack.dart';
import '../platform/platform.dart' show writeFile;
import '../style/style.dart';
import 'console_record.dart';

export 'console_record.dart'
    show RecordFrame, RecordLine, RecordLineKind, recordLines;

/// What a log console shows of [sink] and what is done to it: whether it
/// is open, the records listed — those at [level] and above, of the ones
/// the sink keeps, which it takes as they are logged — the window onto
/// them, the selected record, copying it, saving the list and clearing it.
/// It notifies its listeners of each change, each record taken too.
///
/// It keeps as many records as the sink does, and takes each in constant
/// time; a [Console] paints only the rows it shows, so a burst of records
/// costs a frame no more than one record does. [dispose] stops taking
/// them.
///
/// An app runs with a console of its own over the log it writes to:
///
/// ```dart
/// final logs = LogSink();
/// final console = ConsoleController(logs, level: LogLevel.info);
///
/// Future<void> main() => runApp(
///   KeyBindings(
///     {'f2': console.toggle},
///     child: Console(controller: console, child: const Text('app')),
///   ),
///   logs: logs,
/// );
/// ```
///
/// The binding has one of its own, which the debug keys open
/// (`DebugAids.console`).
final class ConsoleController extends ChangeNotifier {
  /// A console of [sink]'s records at [level] and above, at first those it
  /// keeps; [openOnError] as the field says.
  ConsoleController(
    this.sink, {
    this._level = LogLevel.debug,
    this.openOnError = false,
  }) : _ring = List.filled(sink.capacity, null),
       _listed = List.filled(sink.capacity, 0) {
    sink.records.forEach(_take);
    sink.addListener(_add);
  }

  /// Where the records come from.
  final LogSink sink;

  /// Whether a record at [LogLevel.error] opens the console when it is
  /// closed, following the newest record so that the error shows.
  bool openOnError;

  // the records kept, by number: record n at n % capacity
  final List<LogRecord?> _ring;

  // records taken so far: the number of the next one
  var _count = 0;

  // the number of the first record taken since the last [clear]: those
  // before it are not listed
  var _clearedBefore = 0;

  // the numbers of the listed records, oldest first, in a ring from _first
  final List<int> _listed;
  var _first = 0;
  var _length = 0;

  // listed records below the window: 0 follows the newest
  var _below = 0;

  // the number of the selected record; -1 for none
  var _selected = -1;

  // records the panel lists at once, and the columns of its lines, as of
  // its last layout; 0 before it
  var _rows = 0;
  var _columns = 0;

  var _open = false;

  /// Whether the console is shown.
  bool get isOpen => _open;

  /// Shows the console; nothing when it is open.
  void open() {
    if (!_open) {
      _open = true;
      notifyListeners();
    }
  }

  /// Hides the console; nothing when it is closed.
  void close() {
    if (_open) {
      _open = false;
      notifyListeners();
    }
  }

  /// Opens the console when it is closed, closes it when it is open.
  void toggle() => _open ? close() : open();

  LogLevel _level;

  /// The least level of the records listed. Set, it follows the newest
  /// record again, the selected one kept in view, or deselected when
  /// the new level hides it.
  LogLevel get level => _level;

  set level(LogLevel level) {
    if (level == _level) {
      return;
    }
    _level = level;
    _first = 0;
    _length = 0;
    final from = _count - kept;
    for (
      var n = from > _clearedBefore ? from : _clearedBefore;
      n < _count;
      n++
    ) {
      if (_record(n).level.index >= level.index) {
        _listed[_length++] = n;
      }
    }
    _below = 0;
    final at = _indexOf(_selected);
    if (at < 0) {
      _selected = -1;
    } else {
      _reveal(at);
    }
    notifyListeners();
  }

  /// How many records it keeps, listed or not: those of the sink.
  int get kept => _count < _ring.length ? _count : _ring.length;

  /// How many records are listed.
  int get length => _length;

  /// How many of the records it keeps were taken before the last [clear],
  /// and are listed no more; 0 before a clear.
  int get cleared {
    final from = _count - kept;
    return _clearedBefore > from ? _clearedBefore - from : 0;
  }

  /// Lists none of the records taken so far, only those taken after, as
  /// [level] lets them through; the window follows the newest, none
  /// selected. The sink keeps them: `TWK_LOG`, `twk logs` and the sink's
  /// own records are not the console's.
  void clear() {
    _clearedBefore = _count;
    _first = 0;
    _length = 0;
    _below = 0;
    _selected = -1;
    notifyListeners();
  }

  /// The listed record at [index], the oldest at 0.
  LogRecord recordAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', _length);
    return _record(_numberAt(index));
  }

  /// How many listed records are below the window; 0 while it follows the
  /// newest record, which a record taken then scrolls into view. Otherwise
  /// the window stays on the records it shows as more are taken.
  int get below => _below < _maxBelow ? _below : _maxBelow;

  /// Scrolls the window [rows] records towards the newest (towards the
  /// oldest when negative), as far as there are records.
  void scrollBy(int rows) {
    final below = (this.below - rows).clamp(0, _maxBelow);
    if (below != _below) {
      _below = below;
      notifyListeners();
    }
  }

  /// Follows the newest record again.
  void scrollToEnd() {
    if (_below != 0) {
      _below = 0;
      notifyListeners();
    }
  }

  /// The selected record; null for none, or once it dropped out of the
  /// sink or the [level] hid it.
  LogRecord? get selected => _selected < 0 ? null : _record(_selected);

  /// Selects the record listed before the selected one, the bottom row of
  /// the window when none is selected, and scrolls it into view; the
  /// oldest stays selected.
  void selectPrevious() => _select(-1);

  /// Selects the record listed after the selected one, the top row of the
  /// window when none is selected, and scrolls it into view; the newest
  /// stays selected.
  void selectNext() => _select(1);

  /// Selects no record; nothing when none is.
  void deselect() {
    if (_selected >= 0) {
      _selected = -1;
      notifyListeners();
    }
  }

  /// Puts the selected record on the system clipboard as the log writes it
  /// ([LogRecord.toString], error and stack included): writes OSC 52
  /// ([clipboardSequence]) to [terminal], wrapped for the multiplexer it
  /// runs in (`TerminalInfo.multiplexer`). Returns false, writing nothing,
  /// when none is selected.
  bool copy(TerminalBackend terminal) {
    final record = selected;
    if (record == null) {
      return false;
    }
    terminal.write(
      utf8.encode(
        clipboardSequence(
          '$record',
          multiplexer: terminal.info.multiplexer,
        ),
      ),
    );
    return true;
  }

  /// Writes the records listed, oldest first, to the file at [path] in
  /// place of what it held, as `TWK_LOG` keeps them: each as
  /// [LogRecord.toString] writes it, ending in a line feed. On the web,
  /// which has no files, it fails with [UnsupportedError].
  Future<void> save(String path) async {
    final text = StringBuffer();
    for (var i = 0; i < _length; i++) {
      text
        ..write(_record(_numberAt(i)))
        ..write('\n');
    }
    await writeFile(path, '$text');
  }

  // the record shown whole, its lines as last laid out and the width they
  // were laid out at, the first line in the window and the line selected
  LogRecord? _shown;
  List<RecordLine> _lines = const [];
  var _linesWidth = -1;
  var _top = 0;
  var _cursor = 0;

  /// The record shown whole in place of the list ([showSelected]); null
  /// while the list shows.
  LogRecord? get shownRecord => _shown;

  /// Shows the selected record whole in place of the list: its message and
  /// error line by line, then its stack, frame by frame ([recordLines]),
  /// the first line selected. Nothing when none is selected.
  void showSelected() {
    final record = selected;
    if (record == null) {
      return;
    }
    _shown = record;
    _linesWidth = -1;
    _top = 0;
    _cursor = 0;
    notifyListeners();
  }

  /// Shows the list again; nothing while it shows.
  void hideRecord() {
    if (_shown != null) {
      _shown = null;
      _lines = const [];
      notifyListeners();
    }
  }

  /// The lines of the shown record at [width] columns, laid out once a
  /// width; none while the list shows.
  List<RecordLine> linesAt(int width) {
    final record = _shown;
    if (record == null) {
      return const [];
    }
    if (width != _linesWidth) {
      _lines = recordLines(record, width);
      _linesWidth = width;
      _clampCursor();
    }
    return _lines;
  }

  /// The selected line of the shown record, as last laid out; null while
  /// the list shows.
  RecordLine? get selectedLine =>
      _shown == null || _lines.isEmpty ? null : _lines[_cursor];

  /// The index of [selectedLine] in the shown record's lines.
  int get lineIndex => _cursor;

  /// The first of the shown record's lines in the window.
  int get firstLine => _top;

  /// Selects what row [row] of the window shows (from 0, the window's top
  /// row): a record of the list, or a line of the record shown whole;
  /// nothing where the row shows none.
  void selectRow(int row) {
    if (row < 0 || row >= _window) {
      return;
    }
    if (_shown != null) {
      moveLine(_top + row - _cursor);
      return;
    }
    final end = _length - below;
    final start = end - _window > 0 ? end - _window : 0;
    final index = start + row;
    if (index >= end) {
      return;
    }
    _selected = _numberAt(index);
    notifyListeners();
  }

  /// Moves the selected line of the shown record [by] lines (back when
  /// negative), as far as there are lines, and keeps it in the window.
  void moveLine(int by) {
    if (_shown == null) {
      return;
    }
    // keys that come before the record is painted move through its lines
    // as the last layout lays them out
    if (_linesWidth < 0 && _columns > 0) {
      linesAt(_columns);
    }
    if (_lines.isEmpty) {
      return;
    }
    final to = (_cursor + by).clamp(0, _lines.length - 1);
    if (to != _cursor) {
      _cursor = to;
      _clampCursor();
      notifyListeners();
    }
  }

  void _clampCursor() {
    if (_lines.isEmpty) {
      _cursor = 0;
      _top = 0;
      return;
    }
    if (_cursor >= _lines.length) {
      _cursor = _lines.length - 1;
    }
    final window = _window;
    if (_cursor < _top) {
      _top = _cursor;
    } else if (_cursor >= _top + window) {
      _top = _cursor - window + 1;
    }
    final most = _lines.length > window ? _lines.length - window : 0;
    if (_top > most) {
      _top = most;
    }
  }

  /// Stops taking the sink's records, and drops the listeners.
  @override
  void dispose() {
    sink.removeListener(_add);
    super.dispose();
  }

  void _add(LogRecord record) {
    _take(record);
    if (openOnError && !_open && record.level == LogLevel.error) {
      _open = true;
      _below = 0;
    }
    notifyListeners();
  }

  /// Keeps [record], dropping the oldest when the ring is full, and lists
  /// it when [level] lets it through.
  void _take(LogRecord record) {
    final capacity = _ring.length;
    if (_count >= capacity) {
      final dropped = _count - capacity;
      if (_length > 0 && _listed[_first] == dropped) {
        _first = (_first + 1) % capacity;
        _length--;
      }
      if (_selected == dropped) {
        _selected = -1;
      }
    }
    _ring[_count % capacity] = record;
    if (record.level.index >= _level.index) {
      _listed[(_first + _length) % capacity] = _count;
      _length++;
      if (_below > 0) {
        _below++;
      }
    }
    _count++;
  }

  LogRecord _record(int number) => _ring[number % _ring.length]!;

  int _numberAt(int index) => _listed[(_first + index) % _listed.length];

  /// The index of the listed record numbered [number]; -1 when it is not
  /// listed.
  int _indexOf(int number) {
    if (number < 0) {
      return -1;
    }
    var lo = 0;
    var hi = _length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final n = _numberAt(mid);
      if (n == number) {
        return mid;
      }
      if (n < number) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }

  // records the window shows at once
  int get _window => _rows > 0 ? _rows : 1;

  int get _maxBelow => _length > _window ? _length - _window : 0;

  void _select(int step) {
    if (_length == 0) {
      return;
    }
    final at = _indexOf(_selected);
    final int index;
    if (at >= 0) {
      index = (at + step).clamp(0, _length - 1);
    } else {
      final bottom = _length - 1 - below;
      final top = bottom - _window + 1;
      index = step < 0 ? bottom : (top < 0 ? 0 : top);
    }
    _selected = _numberAt(index);
    _reveal(index);
    notifyListeners();
  }

  /// Scrolls the listed record at [index] into the window: to its bottom
  /// row from below it, to its top row from above.
  void _reveal(int index) {
    final bottom = _length - 1 - below;
    if (index > bottom) {
      _below = _length - 1 - index;
    } else if (index < bottom - _window + 1) {
      _below = _length - index - _window;
    }
  }
}

/// Shows [child] and, while [controller] is open, its log console over
/// the bottom [rows] rows of [child], or over all of it when it is
/// shorter. In the inline mode, whose region is as tall as the app asks,
/// the console goes below the child instead, and the region grows by it.
/// Opening and closing rebuild nothing: the child keeps its state.
///
/// The console is a header naming the [ConsoleController.level], how many
/// records are listed of those kept since the last clear, how many it
/// cleared and how many are below the window,
/// then a row for each record in the window: its time in
/// [ThemeData.muted], its level in the level's color ([ThemeData.muted]
/// for debug, [ThemeData.info], [ThemeData.warning], [ThemeData.error])
/// and the first line of its message and error in [ThemeData.text], on
/// [ThemeData.surface]; the selected record in [ThemeData.selection]. It
/// is a repaint boundary: a record taken repaints it alone, and only the
/// rows it shows.
///
/// See [ConsoleController] for an example.
final class Console extends StatelessWidget {
  /// Shows [child], and [controller]'s console over it while it is open,
  /// [rows] rows tall, 10 by default.
  const Console({
    required this.controller,
    required this.child,
    super.key,
    this.rows = 10,
  });

  /// What the console shows, and whether it is open.
  final ConsoleController controller;

  /// The app the console is over.
  final Widget child;

  /// How tall the console is: the header and a record less than this; 10
  /// by default.
  final int rows;

  @override
  Widget build(BuildContext context) {
    final panel = _Panel(controller: controller, rows: rows);
    return AppBinding.maybeOf(context)?.mode == ScreenMode.inline
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: child),
              panel,
            ],
          )
        : Stack(
            fit: StackFit.passthrough,
            children: [
              child,
              Positioned(left: 0, right: 0, bottom: 0, child: panel),
            ],
          );
  }
}

/// The console of a [Console]: while the controller is open [rows] rows
/// tall, or as tall as it may be when less, and as wide as it may be;
/// closed, it takes no room.
final class _Panel extends LeafRenderObjectWidget {
  const _Panel({required this.controller, required this.rows});

  final ConsoleController controller;
  final int rows;

  @override
  RenderConsolePanel createRenderObject(BuildContext context) =>
      RenderConsolePanel(
        controller: controller,
        theme: Theme.of(context),
        rows: rows,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderConsolePanel renderObject,
  ) {
    renderObject
      ..controller = controller
      ..theme = Theme.of(context)
      ..rows = rows;
  }
}

/// What a [_Panel] lays out and paints, and what the binding shows its
/// console with (`DebugAids.console`); not exported.
final class RenderConsolePanel extends RenderObject {
  /// The panel of [_controller]'s console in [_theme], [_rows] rows tall
  /// while it is open.
  RenderConsolePanel({
    required this._controller,
    required this._theme,
    required this._rows,
  });

  ConsoleController _controller;

  /// What the panel shows; set, the panel listens to the new one in place
  /// of the old, and is laid out again.
  ConsoleController get controller => _controller;
  set controller(ConsoleController c) {
    if (identical(c, _controller)) {
      return;
    }
    if (owner != null) {
      _controller.removeListener(_changed);
      c.addListener(_changed);
    }
    _controller = c;
    markNeedsLayout();
  }

  ThemeData _theme;

  /// What the panel is painted in: its [ThemeData.surface], text and level
  /// colors.
  ThemeData get theme => _theme;
  set theme(ThemeData t) {
    if (t != _theme) {
      _theme = t;
      markNeedsPaint();
    }
  }

  int _rows;

  /// How tall the panel is while the console is open, within its
  /// constraints.
  int get rows => _rows;
  set rows(int r) {
    if (r != _rows) {
      _rows = r;
      markNeedsLayout();
    }
  }

  // whether the controller was open, and showed a record whole, at the
  // last layout
  var _laidOutOpen = false;
  var _laidOutRecord = false;

  @override
  bool get isRepaintBoundary => true;

  /// The rows it is tall while open, and whether it is.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('rows', _rows);
    if (_controller.isOpen) {
      properties.addTag('open');
    }
  }

  @override
  void attach(PipelineOwner o) {
    super.attach(o);
    // once, also when attached again without a detach
    _controller
      ..removeListener(_changed)
      ..addListener(_changed);
  }

  @override
  void detach() {
    _controller.removeListener(_changed);
    super.detach();
  }

  // opening and closing change its size; what else changes, what it shows
  void _changed() {
    if (_controller.isOpen != _laidOutOpen ||
        (_controller._shown != null) != _laidOutRecord) {
      markNeedsLayout();
    } else if (_laidOutOpen) {
      markNeedsPaint();
    }
  }

  // the rows while a record shows whole: twice the list's
  int get _recordRows => 2 * _rows;

  int get _openRows => _controller._shown != null ? _recordRows : _rows;

  @override
  int computeMinIntrinsicHeight(int width) =>
      _controller.isOpen ? _openRows : 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _controller.isOpen ? _openRows : 0;

  @override
  void performLayout(BoxConstraints c) {
    _laidOutOpen = _controller.isOpen;
    _laidOutRecord = _controller._shown != null;
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.constrainH(_laidOutOpen ? _openRows : 0);
    if (_laidOutOpen) {
      _controller
        .._rows = height > 1 ? height - 1 : 0
        .._columns = width - 2;
    }
  }

  @override
  void paint(PaintContext ctx) {
    if (width == 0 || height == 0) {
      return;
    }
    final canvas = ctx.canvas;
    final base = opaque(_theme.surface.merge(_theme.text));
    canvas.fill(0, 0, width, height, base.penIn(canvas.styles));
    if (!_laidOutOpen) {
      return;
    }
    canvas
      ..save()
      ..clipRect(0, 0, width, height);
    if (_controller._shown case final record?) {
      _paintRecordHeader(canvas, base, record);
      _paintLines(canvas, base);
    } else {
      _paintHeader(canvas, base);
      _paintRecords(canvas, base);
    }
    canvas.restore();
  }

  void _paintHeader(Canvas canvas, Style base) {
    final styles = canvas.styles;
    final header = base.merge(const Style(attrs: Attr.underline));
    canvas.fill(0, 0, width, 1, header.penIn(styles));
    final title = header
        .merge(_theme.primary)
        .merge(const Style(attrs: Attr.bold));
    final x = 1 + canvas.text(1, 0, 'console', title.penIn(styles));
    final c = _controller;
    final below = c.below;
    final cleared = c.cleared;
    canvas.text(
      x + 2,
      0,
      '${c.level.name}+  ${c.length} of ${c.kept - cleared}'
      '${cleared > 0 ? '  $cleared cleared' : ''}'
      '${below > 0 ? '  $below below' : ''}',
      header.merge(_theme.muted).penIn(styles),
    );
  }

  void _paintRecords(Canvas canvas, Style base) {
    final c = _controller;
    final end = c.length - c.below;
    final start = end - (height - 1) > 0 ? end - (height - 1) : 0;
    if (start >= end) {
      return;
    }
    final pens = [
      _RowPens(base, _theme, canvas.styles),
      _RowPens(base.merge(_theme.selection), _theme, canvas.styles),
    ];
    // the code units of a message it looks at: more than the columns left
    final limit = 4 * (width - _messageX) + 4;
    for (var i = start; i < end; i++) {
      final number = c._numberAt(i);
      final record = c._record(number);
      final p = pens[number == c._selected ? 1 : 0];
      final y = 1 + i - start;
      final level = record.level.index;
      if (number == c._selected) {
        canvas.fill(0, y, width, 1, p.plain);
      }
      // the error formatted once; what the row leaves out of the record
      // (more lines, a stack) at its end
      final error = record.error == null ? null : '${record.error}';
      final more = _more(record, error);
      final text = _firstLine(record, error, limit);
      canvas
        ..text(1, y, LogRecord.formatTime(record.time), p.time)
        ..text(_levelX, y, _tags[level], p.levels[level]);
      if (more.isEmpty) {
        canvas.text(_messageX, y, text, p.plain);
        continue;
      }
      final markX = width - 1 - more.length;
      if (markX > _messageX + 1) {
        canvas
          ..save()
          ..clipRect(0, y, markX - 1, 1)
          ..text(_messageX, y, text, p.plain)
          ..restore();
      }
      canvas.text(markX, y, more, p.time);
    }
  }

  void _paintRecordHeader(Canvas canvas, Style base, LogRecord record) {
    final styles = canvas.styles;
    final header = base.merge(const Style(attrs: Attr.underline));
    canvas.fill(0, 0, width, 1, header.penIn(styles));
    final level = record.level.index;
    final pens = _RowPens(header, _theme, styles);
    var x = 1;
    x += canvas.text(x, 0, LogRecord.formatTime(record.time), pens.time) + 1;
    x += canvas.text(x, 0, _tags[level], pens.levels[level]);
    final lines = _controller.linesAt(width - 2);
    final c = _controller;
    final where = lines.isEmpty
        ? ''
        : 'line ${c._cursor + 1} of ${lines.length}';
    canvas.text(
      x + 2,
      0,
      '$where  esc back',
      header.merge(_theme.muted).penIn(styles),
    );
  }

  void _paintLines(Canvas canvas, Style base) {
    final c = _controller;
    final lines = c.linesAt(width - 2);
    final styles = canvas.styles;
    final selected = base.merge(_theme.selection);
    for (var i = c._top; i < lines.length && i - c._top < height - 1; i++) {
      final line = lines[i];
      final y = 1 + i - c._top;
      final row = i == c._cursor ? selected : base;
      if (i == c._cursor) {
        canvas.fill(0, y, width, 1, row.penIn(styles));
      }
      switch (line.kind) {
        case RecordLineKind.message:
          canvas.text(1, y, line.text, row.penIn(styles));
        case RecordLineKind.error:
          canvas.text(1, y, line.text, row.merge(_theme.error).penIn(styles));
        case RecordLineKind.folded:
          canvas.text(
            3,
            y,
            line.text,
            row.merge(_theme.muted).penIn(styles),
          );
        case RecordLineKind.frame:
          final frame = line.frame;
          if (frame == null) {
            canvas.text(3, y, line.text, row.merge(_theme.muted).penIn(styles));
            break;
          }
          // the place a link to the file where there is one
          final path = frame.path;
          final at = row
              .merge(_theme.primary)
              .merge(
                Style(link: path == null ? null : Uri.file(path).toString()),
              );
          // a place too long for the row is cut from the left, so that its
          // file, line and column, and the member after it, show
          final most = (width - 4) * 2 ~/ 3;
          var place = frame.location;
          if (place.length > most && most > 8) {
            place = '…${place.substring(place.length - most + 1)}';
          }
          final x = 3 + canvas.text(3, y, place, at.penIn(styles));
          canvas.text(
            x + 2,
            y,
            frame.member,
            row.merge(_theme.muted).penIn(styles),
          );
      }
    }
  }
}

/// What a row of [record], whose error reads [error], leaves out, as its
/// end says: `+2` lines of the message and the error past the first,
/// `stack` where it has one; empty where it shows all.
String _more(LogRecord record, String? error) {
  var lines = '\n'.allMatches(record.message).length;
  if (error != null) {
    lines += '\n'.allMatches(error).length;
  }
  return [
    if (lines > 0) '+$lines',
    if (record.stack != null) 'stack',
  ].join(' ');
}

// the columns a row's level and message start at
const _levelX = 14;
const _messageX = 20;

const _tags = ['DEBUG', 'INFO', 'WARN', 'ERROR'];

/// The pens of the rows of one style: blanks and the message, the time,
/// and each level's tag by its index.
final class _RowPens {
  _RowPens(Style row, ThemeData theme, StyleTable styles)
    : plain = row.penIn(styles),
      time = row.merge(theme.muted).penIn(styles),
      levels = [
        for (final level in LogLevel.values)
          row
              .merge(switch (level) {
                LogLevel.debug => theme.muted,
                LogLevel.info => theme.info,
                LogLevel.warning => theme.warning,
                LogLevel.error => theme.error,
              })
              .penIn(styles),
      ];

  final int plain;
  final int time;
  final List<int> levels;
}

/// The first line of [record]'s message, then that of its error, which
/// reads [error], at most [limit] code units of them.
String _firstLine(LogRecord record, String? error, int limit) {
  final message = _cut(record.message, limit);
  if (error == null ||
      message.length < record.message.length ||
      message.length + 2 >= limit) {
    return message;
  }
  return '$message: ${_cut(error, limit - message.length - 2)}';
}

/// [s] up to its first line break, at most [limit] code units of it.
String _cut(String s, int limit) {
  final end = s.length < limit ? s.length : limit;
  for (var i = 0; i < end; i++) {
    final unit = s.codeUnitAt(i);
    if (unit == 0x0A || unit == 0x0D) {
      return s.substring(0, i);
    }
  }
  return end == s.length ? s : s.substring(0, end);
}
