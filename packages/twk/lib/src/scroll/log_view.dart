/// [LogView]: `tail -f` for an app — the lines a [LogController] is given,
/// following the newest, filtered by level and text, searched with `n`
/// and `N`.
library;

import 'dart:async' show Completer, Stream, StreamSubscription, unawaited;
import 'dart:math' show max, min;

import 'package:meta/meta.dart' show visibleForTesting;

import 'package:twk_core/twk_core.dart'
    show
        Attr,
        BoxConstraints,
        DiagnosticPropertiesBuilder,
        HitTestBehavior,
        ListParentData,
        PaintContext,
        Pen,
        RenderList,
        RenderObject,
        RenderObjectWithChildMixin,
        RenderParagraph,
        stringWidth;

import '../../log.dart';
import '../ansi/stream.dart' show AnsiStream;
import '../editing/caret.dart' show clearRestCursor, restCursor;
import '../focus/focus_tree.dart' show FocusNode;
import '../focus/shortcuts.dart' show KeyBindings;
import '../foundation/change_notifier.dart';
import '../foundation/controller_host.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart' show GestureDetector;
import '../gestures/mouse.dart' show Listener, PointerEvent;
import '../gestures/selection.dart' show Selectable, SelectionArea;
import '../layout/one_child.dart';
import '../layout/stack.dart';
import '../platform/platform.dart'
    show FileBytes, FileReset, TailEvent, tailFile;
import '../style/style.dart';
import '../text/smartcase.dart';
import '../text/widgets.dart';
import 'list_view.dart';
import 'scrollbar.dart';

// Examples can assume:
// import 'dart:convert';
// import 'dart:io';

/// One line of a [LogController]: its [text], [level] and [time], its
/// [spans] where it is in colors of its own, and its [number], the lines
/// added before it since the controller was made.
final class LogLine {
  const LogLine._(this.number, this.text, this.level, this.time, this.spans);

  /// The lines added before this one since the controller was made, those
  /// dropped and cleared too: it tells the line apart for good.
  final int number;

  /// What was logged, as it was given; of a line of [spans], their text.
  final String text;

  /// The pieces of [text] in the styles they were given, each merged over
  /// the style of the line's [level] where a [LogView] shows it (the
  /// colors of a program's output, [LogController.addOutput]); null for a
  /// line all in that style.
  final List<Span>? spans;

  /// How much it matters: what [LogController.level] filters by, and what
  /// a [LogView] colors its level by.
  final LogLevel level;

  /// When it was logged; null shows no time.
  final DateTime? time;

  @override
  String toString() => 'LogLine($number, ${level.name}, $text)';
}

/// The lines a [LogView] shows, and what is done to them: kept, filtered,
/// searched and followed.
///
/// It holds the lines kept, at most [maxLines] of them, the oldest dropped
/// as new ones come; those shown of them, at [level] and above,
/// containing [filter] and kept by [where]; the [query] searched for and
/// the line of the current [match]; and whether the view is [following]
/// the newest line, or else how many [newLines] came since it stopped. It
/// notifies its listeners of each change.
///
/// A line added costs the time it takes to test it against the filter,
/// whatever the lines kept. A [filter] that contains the one before, or a
/// [level] above it, tests only the lines shown; any other change of
/// them tests every line kept. [filter] and [query] ignore the case while
/// they are all in lower case, and heed it otherwise (as vim's smartcase:
/// [Smartcase]).
///
/// Given to one [LogView] at a time; given to one built in place of its
/// view (a key changed), it goes over to that one.
///
/// A log that keeps the last thousand lines, warnings and errors shown:
///
/// ```dart
/// final log = LogController(maxLines: 1000, level: LogLevel.warning)
///   ..add('listening on :8080')
///   ..add('disk 91 % full', level: LogLevel.warning);
/// final view = LogView(controller: log);
/// ```
final class LogController extends ChangeNotifier {
  /// Keeps [maxLines] lines at most (10000 by default; fewer than 1
  /// asserts), and shows those at [level] and above (every level by
  /// default) that contain [filter] and that [where] keeps, with [query]
  /// searched for (both empty by default, for every line and for none;
  /// [where] null for every line).
  LogController({
    int maxLines = 10000,
    this._level = LogLevel.debug,
    this._filter = '',
    this._where,
    this._query = '',
  }) : assert(maxLines > 0, 'a cap of 1 line or more'),
       _maxLines = maxLines;

  // the sources of addOutput and followFile, cancelled with the controller
  final _sources = <LogSource>{};

  // the lines kept, from _head on, their numbers one after another
  final _lines = <LogLine>[];
  var _head = 0;

  // the number of the next line
  var _next = 0;

  // the numbers of the lines shown, from _shownHead on, in order
  var _shown = <int>[];
  var _shownHead = 0;

  // the widest text kept since the last clear, in columns
  var _widest = 0;

  // bumped when the lines shown change other than by lines added: lines
  // dropped from the start, the filter, the level, a clear
  var _reshaped = 0;

  // the number of the current match
  int? _match;

  // whether the view follows the newest line; the first line added since
  // it stopped
  var _following = true;
  var _unseenFrom = 0;

  // the searches for the filter and for the query, made as they are set
  late var _filterCase = Smartcase(_filter);
  late var _queryCase = Smartcase(_query);

  // a move the view is asked for, and how many were asked for
  _Move? _move;
  var _moves = 0;

  // the view it is given to, whose window a search starts from
  final _hosts = ControllerHost<_LogViewState>();

  /// The most lines it keeps; the oldest are dropped past it.
  int get maxLines => _maxLines;
  int _maxLines;
  set maxLines(int n) {
    assert(n > 0, 'a cap of 1 line or more');
    if (n == _maxLines) {
      return;
    }
    _maxLines = n;
    if (_trim()) {
      notifyListeners();
    }
  }

  /// The lines kept.
  int get length => _lines.length - _head;

  /// The line kept at [index], the oldest at 0.
  LogLine operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    return _lines[_head + index];
  }

  /// The lines shown: those kept at [level] and above that contain
  /// [filter] and that [where] keeps.
  int get shownLength => _shown.length - _shownHead;

  /// The line shown at [index], the oldest at 0.
  LogLine shownAt(int index) {
    RangeError.checkValidIndex(index, null, 'index', shownLength);
    return _line(_shown[_shownHead + index]);
  }

  /// Adds a line of [text] at [level], logged at [time] (none shown when
  /// null).
  void add(String text, {LogLevel level = LogLevel.info, DateTime? time}) {
    _add(text, level, time, null);
    _trim();
    notifyListeners();
  }

  /// Adds a line of [spans], in their styles over that of [level], logged
  /// at [time] (none shown when null): filtered and searched by their text.
  void addSpans(
    List<Span> spans, {
    LogLevel level = LogLevel.info,
    DateTime? time,
  }) {
    _add(_textOf(spans), level, time, List.unmodifiable(spans));
    _trim();
    notifyListeners();
  }

  /// Adds the lines of [output], a program's output that comes in pieces
  /// (its stdout, decoded), each line once it ends, at [level], in the
  /// colors its ANSI escape sequences give it: read as an [AnsiStream]
  /// reads it, so a carriage return writes the line over (a progress bar
  /// leaves its last state), a tab moves to the next multiple of
  /// [tabWidth] columns, and no sequence reaches the terminal. The line not
  /// ended when [output] is done is added then. Each line is added as
  /// [map] gives it back, when it is given: the spans to add in its place
  /// (shortened, restyled), or null to leave it out. Returns the
  /// [LogSource]: cancel it once the lines are not wanted; an error of
  /// [output] ends it, and its [LogSource.done] completes with that error.
  ///
  /// ```dart
  /// final log = LogController();
  /// final process = await Process.start('dart', ['test']);
  /// final source = log.addOutput(process.stdout.transform(utf8.decoder));
  /// await source.done;
  /// ```
  LogSource addOutput(
    Stream<String> output, {
    LogLevel level = LogLevel.info,
    int tabWidth = 8,
    List<Span>? Function(List<Span> spans)? map,
  }) => _follow<String>(
    output,
    (reader, text) => reader.add(text),
    level,
    tabWidth,
    map,
  );

  /// [addOutput] of [output], each event of it read into the stream by
  /// [feed], which may [AnsiStream.reset] it, as a file cut short does: the
  /// line not ended is dropped.
  LogSource _follow<T>(
    Stream<T> output,
    void Function(AnsiStream, T) feed,
    LogLevel level,
    int tabWidth,
    List<Span>? Function(List<Span> spans)? map,
  ) {
    final reader = AnsiStream(tabWidth: tabWidth);
    void addEnded() {
      final ended = reader.takeSettled();
      var added = false;
      for (final line in ended) {
        final spans = map == null ? line : map(line);
        if (spans != null) {
          final kept = identical(spans, line)
              ? line
              : List<Span>.unmodifiable(spans);
          _add(_textOf(kept), level, null, kept);
          added = true;
        }
      }
      if (!added) {
        return;
      }
      _trim();
      notifyListeners();
    }

    final source = LogSource._();
    _sources.add(source);
    void finish([Object? error, StackTrace? stack]) {
      _sources.remove(source);
      source._finish(error, stack);
    }

    source._subscription = output.listen(
      (event) {
        feed(reader, event);
        addEnded();
      },
      onError: (Object error, StackTrace stack) {
        finish(error, stack);
        unawaited(source.cancel());
      },
      onDone: () {
        reader.close();
        addEnded();
        finish();
      },
    );
    source._onCancel = () => _sources.remove(source);
    return source;
  }

  /// Cancels the sources of [addOutput] and [followFile] still live, so no
  /// line reaches a disposed controller; the ones returned stay valid to
  /// cancel again.
  @override
  void dispose() {
    for (final source in _sources.toList()) {
      unawaited(source.cancel());
    }
    _sources.clear();
    super.dispose();
  }

  /// Follows the file at [path], adding the lines written to it as [addOutput]
  /// adds those of a program's output (in its colors, a carriage return
  /// writing a line over, each through [map] when it is given), each line
  /// once it ends: those written from the call on, and before them the whole
  /// lines among the last [backlog] bytes the file had (none by default, the
  /// file's from its start for null); a line the backlog begins within is
  /// left out. A write
  /// is told by a watch of the file's directory where the system has one, and
  /// found by a look at the file's size each [poll] all the same; a file cut
  /// short (truncated after a clean, written anew) is read again from its
  /// start, and so is one replaced at the path (another renamed over it, as a
  /// log rotation does) where the system's watch tells it; with the poll
  /// alone, a replacement is told only by being shorter than what was read.
  /// One not there yet is waited for. Malformed UTF-8 is U+FFFD. Tabs go to
  /// the next multiple of [tabWidth] columns. Cancel the returned source to
  /// stop following it. Not on the web, which has no files: the source's
  /// [LogSource.done] completes with an [UnsupportedError].
  ///
  /// The poll goes on while no [LogView] shows the controller, as the lines
  /// do: the controller is the log, a view one way of reading it. Measured,
  /// it is one `stat` of the file each [poll], about a system call a second
  /// per follower, and 10 followers took 12 ms of system time over 30
  /// seconds; cancel the source to stop it. Unlike the library's other
  /// timers (`AppBinding.startTimer`), the poll is a real one, not the app's
  /// clock: what it waits for is a real file, so a test awaits its lines with
  /// `waitUntil` rather than a pump.
  ///
  /// ```dart
  /// final log = LogController();
  /// final source = log.followFile('build.log', tabWidth: 4);
  /// await source.cancel();
  /// ```
  ///
  /// A server's log, the lines of its last 64 KiB at the start, without
  /// the lines of the health checks:
  ///
  /// ```dart
  /// final log = LogController();
  /// log.followFile(
  ///   'server.log',
  ///   backlog: 64 * 1024,
  ///   map: (spans) =>
  ///       spans.any((s) => s.text.contains('GET /health')) ? null : spans,
  /// );
  /// ```
  LogSource followFile(
    String path, {
    int? backlog = 0,
    Duration poll = const Duration(seconds: 1),
    LogLevel level = LogLevel.info,
    int tabWidth = 8,
    List<Span>? Function(List<Span> spans)? map,
  }) => _follow<TailEvent>(
    tailFile(path, backlog: backlog, poll: poll),
    (reader, event) => switch (event) {
      FileBytes(:final bytes) => reader.addBytes(bytes),
      // the old file's unended line, and a character cut, are not the start
      // of the next one
      FileReset() => reader.reset(),
    },
    level,
    tabWidth,
    map,
  );

  static String _textOf(List<Span> spans) => switch (spans) {
    [] => '',
    [final one] => one.text,
    _ => spans.map((s) => s.text).join(),
  };

  /// Adds a line of each of [texts], as [add] does, telling the listeners
  /// once.
  void addAll(
    Iterable<String> texts, {
    LogLevel level = LogLevel.info,
    DateTime? time,
  }) {
    for (final text in texts) {
      _add(text, level, time, null);
    }
    _trim();
    notifyListeners();
  }

  /// Drops every line; the view follows the lines added next.
  void clear() {
    _lines.clear();
    _head = 0;
    _shown = [];
    _shownHead = 0;
    _widest = 0;
    _match = null;
    _following = true;
    _reshaped++;
    notifyListeners();
  }

  /// The least level of the lines shown.
  LogLevel get level => _level;
  LogLevel _level;
  set level(LogLevel level) {
    if (level == _level) {
      return;
    }
    final narrower = level.index > _level.index;
    _level = level;
    _refilter(narrower: narrower);
  }

  /// What the lines shown contain; empty for every line.
  String get filter => _filter;
  String _filter;
  set filter(String filter) {
    if (filter == _filter) {
      return;
    }
    final narrower = filter.contains(_filter);
    _filter = filter;
    _filterCase = Smartcase(filter);
    _refilter(narrower: narrower);
  }

  /// Which lines are shown, of those at [level] and above that contain
  /// [filter]: those it returns true for; null for every one. Set, it
  /// tests every line kept, and the view stays on the lines it shows, as
  /// it does for [filter]; set again to another function (a new closure)
  /// to test them again when what it tests by changed. It is called for
  /// each line added too, so it should be quick, and give a line the same
  /// answer until it is set again.
  ///
  /// The lines of some kinds only, told by their text:
  ///
  /// ```dart
  /// final log = LogController();
  /// final kinds = {'GET', 'POST'};
  /// log.where = (line) => kinds.any(line.text.startsWith);
  /// ```
  bool Function(LogLine line)? get where => _where;
  bool Function(LogLine line)? _where;
  set where(bool Function(LogLine line)? where) {
    if (identical(where, _where)) {
      return;
    }
    // a narrower test is not known: every line kept is tested
    _where = where;
    _refilter(narrower: false);
  }

  /// What [nextMatch] and [previousMatch] look for, highlighted in the
  /// lines shown; empty for nothing. Set, there is no current [match].
  String get query => _query;
  String _query;
  set query(String query) {
    if (query == _query) {
      return;
    }
    _query = query;
    _queryCase = Smartcase(query);
    _match = null;
    notifyListeners();
  }

  /// The line of the current match, if it is still kept; null when there
  /// is none.
  LogLine? get match {
    final m = _match;
    return m == null || !_kept(m) ? null : _line(m);
  }

  /// Makes the next line shown that contains [query] the current [match],
  /// after the current one, round to the oldest past the newest; with no
  /// current match, the first at or below the top of the window. The view
  /// scrolls to show it. Returns whether there is a match.
  bool nextMatch() => _seek(forward: true);

  /// Makes the line shown before the current [match] that contains [query]
  /// the current one, round to the newest past the oldest; with no current
  /// match, the last at or above the bottom of the window. The view
  /// scrolls to show it. Returns whether there is a match.
  bool previousMatch() => _seek(forward: false);

  /// Whether the view shows the newest line and keeps showing it as lines
  /// are added: until it is scrolled away from the end, and again once it
  /// is back there.
  bool get following => _following;

  /// The lines shown that were added since the view stopped [following]:
  /// 0 while it follows.
  int get newLines => _following ? 0 : shownLength - _shownIndexOf(_unseenFrom);

  /// Scrolls the view to the end, where it follows the lines added.
  void follow() {
    _following = true;
    _ask(const _ToEnd());
  }

  void _add(String text, LogLevel level, DateTime? time, List<Span>? spans) {
    final line = LogLine._(_next++, text, level, time, spans);
    _lines.add(line);
    final w = stringWidth(text);
    if (w > _widest) {
      _widest = w;
    }
    if (_passes(line)) {
      _shown.add(line.number);
    }
  }

  /// Drops the oldest lines past [maxLines]; returns whether it dropped
  /// any.
  bool _trim() {
    final over = length - _maxLines;
    if (over <= 0) {
      return false;
    }
    final end = _head + over;
    final last = _lines[end - 1].number;
    while (_shownHead < _shown.length && _shown[_shownHead] <= last) {
      _shownHead++;
    }
    _head = end;
    // the room of what is dropped, once it is half of the lists
    if (_head > 64 && _head * 2 > _lines.length) {
      _lines.removeRange(0, _head);
      _head = 0;
    }
    if (_shownHead > 64 && _shownHead * 2 > _shown.length) {
      _shown.removeRange(0, _shownHead);
      _shownHead = 0;
    }
    _reshaped++;
    return true;
  }

  void _refilter({required bool narrower}) {
    final from = narrower
        ? [for (var i = _shownHead; i < _shown.length; i++) _line(_shown[i])]
        : _lines.skip(_head);
    _shown = [
      for (final line in from)
        if (_passes(line)) line.number,
    ];
    _shownHead = 0;
    _reshaped++;
    notifyListeners();
  }

  bool _passes(LogLine line) =>
      line.level.index >= _level.index &&
      (_filter.isEmpty || _filterCase.isIn(line.text)) &&
      (_where?.call(line) ?? true);

  bool _kept(int number) =>
      length > 0 && number >= _lines[_head].number && number < _next;

  LogLine _line(int number) => _lines[_head + number - _lines[_head].number];

  /// The index among the lines shown of the first whose number is
  /// [number] or more: [shownLength] when there is none.
  int _shownIndexOf(int number) {
    var lo = _shownHead;
    var hi = _shown.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_shown[mid] < number) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo - _shownHead;
  }

  bool _seek({required bool forward}) {
    final n = shownLength;
    if (_query.isEmpty || n == 0) {
      return false;
    }
    // the index the search starts at, which it tests last when it is the
    // current match's
    int start;
    var current = false;
    final m = _match;
    // the first line in the window going forward, the last going back
    final edge = _hosts.host?._windowEdge(top: forward);
    if (m != null) {
      start = _shownIndexOf(m);
      current = start < n && _shown[_shownHead + start] == m;
      if (!current && !forward) {
        start--;
      }
    } else if (edge != null) {
      start = _shownIndexOf(edge);
      if (!forward && (start >= n || _shown[_shownHead + start] > edge)) {
        start--;
      }
    } else {
      start = forward ? 0 : n - 1;
    }
    final step = forward ? 1 : -1;
    for (var k = current ? 1 : 0; k <= n; k++) {
      final i = ((start + step * k) % n + n) % n;
      final line = _line(_shown[_shownHead + i]);
      if (_queryCase.isIn(line.text)) {
        _match = line.number;
        _ask(_ToLine(line.number));
        return true;
      }
    }
    return false;
  }

  void _ask(_Move move) {
    _move = move;
    _moves++;
    notifyListeners();
  }

  /// What the view tells it of its window: whether it shows the end.
  void _shownEnd({required bool atEnd}) {
    if (atEnd == _following) {
      return;
    }
    _following = atEnd;
    if (!atEnd) {
      _unseenFrom = _next;
    }
    notifyListeners();
  }
}

/// A move a [LogController] asks its view for.
sealed class _Move {
  const _Move();
}

/// To the end, following it.
final class _ToEnd extends _Move {
  const _ToEnd();
}

/// To show the line of [number].
final class _ToLine extends _Move {
  const _ToLine(this.number);

  final int number;
}

/// The lines of a [LogController] in a window that scrolls, the newest at
/// the bottom: `tail -f` for an app.
///
/// While it shows the end it follows
/// the lines added ([LogController.following]); scrolled away from it, it
/// stays on the lines it shows, as lines are added, dropped past the cap
/// or filtered, and an indicator at its bottom right counts the lines
/// shown that came since ([LogController.newLines]); End, or a click on
/// the indicator, goes back to the end and follows it.
///
/// A line is its time (`09:05:07.042`, when it has one and [showTime]) in
/// [ThemeData.muted], its level (when [showLevel]) in the level's color
/// ([ThemeData.muted] for debug, [ThemeData.info], [ThemeData.warning],
/// [ThemeData.error]), and its text in [ThemeData.text], a debug line's in
/// [ThemeData.muted]. What the controller's [LogController.query] finds
/// is drawn in [matchStyle] (reverse video) merged onto it; on the line of
/// the current match, in [currentMatchStyle] ([ThemeData.accent] in
/// reverse video and bold). `n` and `N` go to the next and the previous
/// match while there is a query.
///
/// With [wrap] a line too long for the window goes on on the rows below;
/// without, each line is a row, and Left and Right scroll the lines
/// across, a few columns at a time, as far as the widest line kept; going
/// to a match scrolls across to show it. A [Scrollbar] at its right shows
/// where the window is among the lines shown, as [scrollbar] says.
///
/// With [selectable] the lines can be selected with the mouse and copied
/// ([SelectionArea]), each as it reads, its time and level too, and the
/// lines a selection covers stay selected scrolled out of view, as lines
/// are added, dropped past the cap or filtered: what is copied is what was
/// selected. A drag past the top or bottom of the window scrolls it on,
/// selecting the lines it scrolls through, down as far as the end and up
/// as far as [selectReach] lines above the window it was pressed in.
///
/// It is a [ListView] of the lines shown, built as they come into view: a
/// million lines cost what the window does, and a press to select what
/// the window and [selectReach] lines around it do. A line added while it
/// follows moves the rows on the screen up by one and paints the new one
/// (a hardware scroll: with the scrollbar beside the rows, on a terminal
/// with left and right margins, DECSLRM, and else by rewriting the cells
/// that changed); one added while it does not paints nothing. It takes all
/// the room it is given, which must be bounded.
///
/// A log under a field that filters it, the view taking the rest of the
/// room:
///
/// ```dart
/// final log = LogController();
/// final screen = Column(
///   children: [
///     TextField(onChanged: (text) => log.filter = text),
///     Expanded(child: LogView(controller: log, wrap: true)),
///   ],
/// );
/// ```
///
/// See also:
///
///  * [ListView], what it shows its lines in, for a list of one's own.
final class LogView extends StatefulWidget {
  /// Shows the lines of [controller], each with its time and level, cut
  /// off at the window's edge unless [wrap], selectable with the mouse,
  /// with a scrollbar always shown.
  const LogView({
    required this.controller,
    super.key,
    this.wrap = false,
    this.showTime = true,
    this.showLevel = true,
    this.selectable = true,
    this.style,
    this.matchStyle,
    this.currentMatchStyle,
    this.focusNode,
    this.autofocus = false,
    this.scrollbar = ScrollbarVisibility.always,
  });

  /// The lines, and what is done to them.
  final LogController controller;

  /// Whether a line too long for the window goes on below; without, Left
  /// and Right scroll the lines across.
  final bool wrap;

  /// Whether a line shows its time, when it has one.
  final bool showTime;

  /// Whether a line shows its level.
  final bool showLevel;

  /// Whether the lines can be selected with the mouse and copied.
  final bool selectable;

  /// What fills the window under the lines; see [ListView.style].
  final Style? style;

  /// Merged onto what the query finds; reverse video when null.
  final Style? matchStyle;

  /// Merged onto what the query finds on the line of the current match;
  /// [ThemeData.accent] in reverse video and bold when null.
  final Style? currentMatchStyle;

  /// See [ListView.focusNode].
  final FocusNode? focusNode;

  /// See [ListView.autofocus].
  final bool autofocus;

  /// When the [Scrollbar] at its right shows its thumb;
  /// [ScrollbarVisibility.never] for none, the lines taking its column.
  final ScrollbarVisibility scrollbar;

  /// The columns Left and Right scroll the lines across.
  static const sideStep = 4;

  /// The most lines above the window a press was in that a drag from it
  /// selects, scrolling up.
  static const selectReach = 5000;

  /// How many render objects the [LogView]s looked at to find their list
  /// and the lines in their windows.
  @visibleForTesting
  static var renderVisits = 0;

  @override
  State<LogView> createState() => _LogViewState();
}

/// What a line of a [LogView] is drawn with: when it changes, every line
/// is built anew.
typedef _Look = ({
  Style time,
  List<Style> levels,
  Style text,
  Style debug,
  Style match,
  Style current,
  Smartcase query,
  int shift,
  bool wrap,
  bool showTime,
  bool showLevel,
});

final class _LogViewState extends State<LogView> {
  final _list = ListController();

  // what the controller had changed as of the last notification taken
  var _reshaped = 0;
  var _moves = 0;

  // the columns the lines are scrolled across
  var _shift = 0;

  // the lines built, by number, as of _look; and the current match then
  final _built = <int, Widget>{};
  _Look? _look;
  int? _builtMatch;

  // what a selection selects in: the lines shown from one on, each as it
  // reads, joined by line breaks; the number of each and where it starts
  // in it. Made anew around the window on the first ask after a press, and
  // only made longer otherwise: what the selection area holds of it, the
  // place of its anchor and what is selected, stays where it was
  var _text = '';
  var _numbers = <int>[];
  var _starts = <int>[];
  var _pressed = true;

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
    _list.addListener(_scrolled);
  }

  @override
  void didUpdateWidget(LogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _detach(oldWidget.controller);
      _attach(widget.controller);
      _built.clear();
      _text = '';
      _numbers = [];
      _starts = [];
      _pressed = true;
    }
  }

  @override
  void dispose() {
    _detach(widget.controller);
    _list
      ..removeListener(_scrolled)
      ..dispose();
    super.dispose();
  }

  void _attach(LogController c) {
    c
      ..addListener(_changed)
      .._hosts.attach(this);
    _reshaped = c._reshaped;
    _moves = c._moves;
  }

  void _detach(LogController c) {
    c
      ..removeListener(_changed)
      .._hosts.detach(this);
  }

  /// The controller changed: lines added, dropped, filtered, a move asked
  /// for.
  void _changed() {
    final c = widget.controller;
    if (c._reshaped != _reshaped) {
      _reshaped = c._reshaped;
      // scrolled away from the end, it stays on the line at its top, or on
      // the first shown after it when that one is not shown now
      final top = c._following ? null : _windowEdge(top: true);
      if (top != null) {
        _list.jumpToIndex(c._shownIndexOf(top));
      }
    }
    if (c._moves != _moves) {
      _moves = c._moves;
      switch (c._move) {
        case _ToEnd():
          if (_list.hasClients) {
            _list.jumpTo(_list.position.maxScrollExtent);
          }
        case _ToLine(:final number):
          _list.ensureIndexVisible(c._shownIndexOf(number));
          _showAcross(number);
        case null:
      }
    }
    setState(() {});
  }

  /// The position moved, or the list settled: whether it shows the end is
  /// whether it follows.
  void _scrolled() {
    if (!_list.hasClients) {
      return;
    }
    final p = _list.position;
    if (p.hasExtents) {
      widget.controller._shownEnd(atEnd: p.pixels >= p.maxScrollExtent);
    }
  }

  // the list, as last found: kept while it is in the tree
  RenderList? _listFound;

  /// The list, as it was last laid out: found in the tree below the view
  /// once, and again only once it is out of it (built anew).
  RenderList? get _render {
    final kept = _listFound;
    if (kept != null && kept.owner != null && kept.parent != null) {
      return kept;
    }
    return _listFound = _findList();
  }

  // apart from _render: the context of what its search captures is made
  // as the function is entered, the kept list's way out too
  RenderList? _findList() {
    RenderList? found;
    void visit(RenderObject o) {
      if (found != null) {
        return;
      }
      LogView.renderVisits++;
      if (o is RenderList) {
        found = o;
        return;
      }
      o.visitChildren(visit);
    }

    final root = context.findRenderObject();
    if (root != null) {
      visit(root);
    }
    return found;
  }

  /// The numbers of the first and the last line in the window, as it was
  /// last laid out; null with none.
  (int, int)? _window() {
    final top = _windowEdge(top: true);
    return top == null ? null : (top, _windowEdge(top: false)!);
  }

  /// The number of the first line in the window, as it was last laid out,
  /// or with [top] false of the last; null with none. The items are in
  /// the order of their rows: those laid out past the edge are looked at,
  /// not the window.
  int? _windowEdge({required bool top}) {
    if (!mounted) {
      return null;
    }
    final list = _render;
    if (list == null) {
      return null;
    }
    for (var c = top ? list.firstChild : list.lastChild; c != null;) {
      LogView.renderVisits++;
      final at = c.parentData as ListParentData;
      if (at.dy + c.height > 0 && at.dy < list.height) {
        if (_lineIn(c) case final line?) {
          return line.number;
        }
      }
      c = top ? at.nextSibling : at.previousSibling;
    }
    return null;
  }

  static _RenderLine? _lineIn(RenderObject o) {
    LogView.renderVisits++;
    return o is _RenderLine ? o : _lineBelow(o);
  }

  // apart from _lineIn, as _findList is from _render
  static _RenderLine? _lineBelow(RenderObject o) {
    _RenderLine? found;
    o.visitChildren((c) => found ??= _lineIn(c));
    return found;
  }

  /// [line] as it reads: its time, level and text.
  String _textOf(LogLine line) {
    final time = line.time;
    final shown = widget.showTime && time != null
        ? '${LogRecord.formatTime(time)} '
        : '';
    return '$shown${widget.showLevel ? _tags[line.level.index] : ''}'
        '${line.text}';
  }

  /// The text a selection selects in: made anew around the window after a
  /// press, made longer to the lines below the window otherwise.
  String _selectable() {
    final window = _window();
    if (window == null) {
      return _text;
    }
    final c = widget.controller;
    final first = c._shownIndexOf(window.$1);
    final last = c._shownIndexOf(window.$2);
    if (_pressed) {
      _pressed = false;
      _text = '';
      _numbers = [];
      _starts = [];
      _append(max(0, first - LogView.selectReach), last + 1 + _below);
    } else if (_numbers.isEmpty) {
      _append(first, last + 1 + _below);
    } else if (window.$2 > _numbers.last) {
      _append(c._shownIndexOf(_numbers.last + 1), last + 1 + _below);
    }
    return _text;
  }

  // the lines below the window the text takes in when it is made longer
  static const _below = 500;

  /// Adds the lines shown from index [from] to [to] to the text.
  void _append(int from, int to) {
    final c = widget.controller;
    final end = min(to, c.shownLength);
    if (from >= end) {
      return;
    }
    final out = StringBuffer(_text);
    for (var i = from; i < end; i++) {
      if (out.isNotEmpty || _numbers.isNotEmpty) {
        out.write('\n');
      }
      final line = c.shownAt(i);
      _numbers.add(line.number);
      _starts.add(out.length);
      out.write(_textOf(line));
    }
    _text = out.toString();
  }

  /// The index in [_numbers] of the first line of the text whose number
  /// is [number] or more: its length when there is none.
  int _firstFrom(int number) {
    var lo = 0;
    var hi = _numbers.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_numbers[mid] < number) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Where the line of [number] is in the text, as an index of [_numbers];
  /// -1 when it is not there.
  int _indexOfNumber(int number) {
    final k = _firstFrom(number);
    return k < _numbers.length && _numbers[k] == number ? k : -1;
  }

  /// Where the line at [k] of [_numbers] ends in the text, before its line
  /// break.
  int _endOf(int k) =>
      k + 1 < _starts.length ? _starts[k + 1] - 1 : _text.length;

  /// The part of the line of [number] that [selection] of the text covers,
  /// offsets in the line; null when none of it.
  (int, int)? _selectedOf(int number, (int, int)? selection) {
    if (selection == null) {
      return null;
    }
    final k = _indexOfNumber(number);
    if (k < 0) {
      return null;
    }
    final start = _starts[k];
    final s = max(selection.$1, start);
    final e = min(selection.$2, _endOf(k));
    return s < e ? (s - start, e - start) : null;
  }

  /// The range of the text the cell [x], [y] of [view] (what holds the
  /// list) stands for: in a line, as its paragraph gives it; right of its
  /// text, after its line break; above the lines laid out, where the first
  /// of them starts; below them, after the last one's line break.
  (int, int) _rangeAt(RenderObject view, int x, int y) {
    final list = _render;
    if (list == null || _numbers.isEmpty) {
      return (0, 0);
    }
    final (_, top) = _offsetIn(list, view);
    final row = y - top;
    RenderObject? hit;
    RenderObject? first;
    RenderObject? last;
    list.visitChildren((c) {
      final at = c.parentData as ListParentData;
      if (first == null || at.dy < (first!.parentData as ListParentData).dy) {
        first = c;
      }
      if (last == null || at.dy > (last!.parentData as ListParentData).dy) {
        last = c;
      }
      if (row >= at.dy && row < at.dy + c.height) {
        hit = c;
      }
    });
    final above = hit == null && first != null && row < _topOf(first!);
    final item = hit ?? (above ? first : last);
    final line = item == null ? null : _lineIn(item);
    if (line == null) {
      return (0, 0);
    }
    final k = _indexOfNumber(line.number);
    if (k < 0) {
      // a line the text does not have (above it, or shown since it was
      // made): where the first after it starts
      final after = _firstFrom(line.number);
      final at = after < _starts.length ? _starts[after] : _text.length;
      return (at, at);
    }
    final start = _starts[k];
    final end = _endOf(k);
    final next = min(end + 1, _text.length);
    if (hit == null) {
      return above ? (start, start) : (next, next);
    }
    final paragraph = line.child;
    if (paragraph is! RenderParagraph) {
      return (start, start);
    }
    final (px, py) = _offsetIn(paragraph, view);
    final (s, e) = paragraph.textRangeAt(x - px, y - py);
    if (s >= end - start) {
      return (next, next);
    }
    return (start + s, start + min(e, end - start));
  }

  static int _topOf(RenderObject item) =>
      (item.parentData as ListParentData).dy;

  /// Scrolls the list by [rows] for a drag past its edge that selects;
  /// up no further than the first line of the text. Whether it moved.
  bool _scrollToSelect(int rows) {
    if (!_list.hasClients || rows == 0) {
      return false;
    }
    if (rows < 0) {
      final top = _windowEdge(top: true);
      if (top == null || _numbers.isEmpty || top <= _numbers.first) {
        return false;
      }
    }
    final p = _list.position;
    final from = p.pixels;
    p.jumpTo(from + rows);
    return p.pixels != from;
  }

  void _down(PointerEvent event) {
    if (event.button == 0) {
      _pressed = true;
    }
  }

  /// The widest a line is, in columns.
  int get _widest =>
      widget.controller._widest +
      (widget.showLevel ? 6 : 0) +
      (widget.showTime ? 13 : 0);

  /// Scrolls across by [delta] columns, as far as the widest line.
  void _scrollAcross(int delta) {
    final width = _render?.width ?? 0;
    final max = _widest - width > 0 ? _widest - width : 0;
    final to = (_shift + delta).clamp(0, max);
    if (to != _shift) {
      setState(() => _shift = to);
    }
  }

  /// Scrolls across the least that shows the first match on the line of
  /// [number], lines not wrapped.
  void _showAcross(int number) {
    final c = widget.controller;
    final width = _render?.width ?? 0;
    if (widget.wrap || width <= 0 || !c._kept(number)) {
      return;
    }
    final line = c._line(number);
    final at = c._queryCase.indexIn(line.text);
    if (at < 0) {
      return;
    }
    final start = _prefixWidth(line) + stringWidth(line.text.substring(0, at));
    final end = start + stringWidth(c.query);
    if (start < _shift) {
      _shift = start;
    } else if (end > _shift + width) {
      _shift = end - width;
    }
  }

  int _prefixWidth(LogLine line) =>
      (widget.showTime && line.time != null ? 13 : 0) +
      (widget.showLevel ? 6 : 0);

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);
    final look = (
      time: theme.muted,
      levels: [theme.muted, theme.info, theme.warning, theme.error],
      text: theme.text,
      debug: theme.muted,
      match: widget.matchStyle ?? const Style(attrs: Attr.reverse),
      current:
          widget.currentMatchStyle ??
          theme.fill(theme.accent.fg).merge(const Style(attrs: Attr.bold)),
      query: c._queryCase,
      shift: widget.wrap ? 0 : _shift,
      wrap: widget.wrap,
      showTime: widget.showTime,
      showLevel: widget.showLevel,
    );
    if (!_sameLook(look, _look)) {
      _look = look;
      _built.clear();
    }
    final match = c._match;
    if (match != _builtMatch) {
      _built
        ..remove(_builtMatch)
        ..remove(match);
      _builtMatch = match;
    }
    // the lines out of view are let go of now and then
    if (_built.length > 1024) {
      _built.clear();
    }
    Widget view = ListView.builder(
      itemCount: c.shownLength,
      itemExtent: widget.wrap ? null : 1,
      maxKept: 0,
      stickToBottom: true,
      controller: _list,
      style: widget.style,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      itemBuilder: (context, index) {
        final line = c.shownAt(index);
        return _built[line.number] ??= _lineWidget(line, look);
      },
    );
    if (widget.selectable) {
      view = SelectionArea(
        child: Listener(
          onPointerDown: _down,
          behavior: HitTestBehavior.translucent,
          child: _Selected(state: this, child: view),
        ),
      );
    }
    final fresh = c.newLines;
    // as of the last layout: none before it
    final room = _render?.width;
    final keysFor = (
      c,
      c.query.isNotEmpty,
      widget.wrap,
      _shift > 0,
      room == null || _shift < _widest - room,
    );
    if (keysFor != _keysFor) {
      _keysFor = keysFor;
      final (_, matches, wrap, left, right) = keysFor;
      _keys = {
        if (matches) ...{'n': c.nextMatch, 'N': c.previousMatch},
        if (!wrap) ...{
          'left': left ? () => _scrollAcross(-LogView.sideStep) : null,
          'right': right ? () => _scrollAcross(LogView.sideStep) : null,
        },
      };
      _keyHints = matches
          ? const {'n': 'next match', 'N': 'previous match'}
          : const {};
    }
    final arrow = fresh > 0
        ? ThemeMarks.of(context).text(Marks.arrowDown, theme.glyphs)
        : '';
    return KeyBindings(
      _keys,
      hints: _keyHints,
      child: Scrollbar(
        visibility: widget.scrollbar,
        child: Stack(
          fit: StackFit.expand,
          children: [
            view,
            if (fresh > 0)
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: c.follow,
                  child: Text(
                    ' $arrow $fresh new '
                    "${fresh == 1 ? 'line' : 'lines'} ",
                    style: theme.surface.merge(theme.primary),
                    wrap: TextWrap.none,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // the keys and their hints as last made, and what they were made of: the
  // same maps while that is the same, which the bindings parse once
  (LogController, bool, bool, bool, bool)? _keysFor;
  var _keys = const <String, VoidCallback?>{};
  var _keyHints = const <String, String>{};

  static bool _sameLook(_Look a, _Look? b) =>
      b != null &&
      a.time == b.time &&
      a.text == b.text &&
      a.debug == b.debug &&
      a.match == b.match &&
      a.current == b.current &&
      a.query.pattern == b.query.pattern &&
      a.shift == b.shift &&
      a.wrap == b.wrap &&
      a.showTime == b.showTime &&
      a.showLevel == b.showLevel &&
      _sameStyles(a.levels, b.levels);

  static bool _sameStyles(List<Style> a, List<Style> b) {
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

  Widget _lineWidget(LogLine line, _Look look) {
    final time = line.time;
    final text = line.text;
    final base = line.level == LogLevel.debug ? look.debug : look.text;
    final spans = <(String, Style)>[
      if (look.showTime && time != null)
        ('${LogRecord.formatTime(time)} ', look.time),
      if (look.showLevel)
        (_tags[line.level.index], look.levels[line.level.index]),
    ];
    final query = look.query;
    final current = line.number == widget.controller._match;
    final found = current ? look.current : look.match;
    final pieces = switch (line.spans) {
      final spans? => [for (final s in spans) (s.text, base.merge(s.style))],
      null => [(text, base)],
    };
    if (query.pattern.isEmpty) {
      spans.addAll(pieces);
    } else {
      final matches = <(int, int)>[];
      for (var i = query.indexIn(text); i >= 0;) {
        final end = i + query.pattern.length;
        matches.add((i, end));
        i = query.indexIn(text, end);
      }
      spans.addAll(_marked(pieces, matches, found));
    }
    if (spans.isEmpty) {
      spans.add(('', base));
    }
    return _Line(
      key: ValueKey(line.number),
      number: line.number,
      shift: look.wrap ? null : look.shift,
      spans: spans,
      current: current,
    );
  }
}

/// [pieces], text and its style one after another, with the text of
/// [matches] (start and end in the text of all of them, in order, apart)
/// in [mark] over its style; no empty piece.
List<(String, Style)> _marked(
  List<(String, Style)> pieces,
  List<(int, int)> matches,
  Style mark,
) {
  final out = <(String, Style)>[];
  var offset = 0;
  var m = 0;
  for (final (text, style) in pieces) {
    final end = offset + text.length;
    var at = offset;
    while (at < end) {
      while (m < matches.length && matches[m].$2 <= at) {
        m++;
      }
      if (m == matches.length || matches[m].$1 >= end) {
        out.add((text.substring(at - offset), style));
        break;
      }
      final (start, stop) = matches[m];
      if (start > at) {
        out.add((text.substring(at - offset, start - offset), style));
        at = start;
      }
      final to = stop < end ? stop : end;
      out.add((text.substring(at - offset, to - offset), style.merge(mark)));
      at = to;
    }
    offset = end;
  }
  return out;
}

const _tags = ['DEBUG ', 'INFO  ', 'WARN  ', 'ERROR '];

/// Where [o] is in [ancestor], as last laid out.
(int, int) _offsetIn(RenderObject o, RenderObject ancestor) {
  var x = 0;
  var y = 0;
  for (
    RenderObject? p = o;
    p != null && !identical(p, ancestor);
    p = p.parent
  ) {
    x += p.parentData.dx;
    y += p.parentData.dy;
  }
  return (x, y);
}

/// The list of a [LogView] as a [SelectionArea] selects in it: one
/// [Selectable] for all the lines shown, those out of view too.
final class _Selected extends SingleChildRenderObjectWidget {
  const _Selected({required this.state, required Widget super.child});

  final _LogViewState state;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderSelected createRenderObject(BuildContext context) =>
      _RenderSelected(state);

  @override
  void updateRenderObject(BuildContext context, _RenderSelected renderObject) =>
      renderObject.state = state;
}

/// What a [_Selected] lays out and paints: its child, as large as it; what
/// is selected of it is painted by the lines, each told when it changes.
final class _RenderSelected extends RenderObject
    with RenderObjectWithChildMixin, Selectable {
  _RenderSelected(this.state);

  _LogViewState state;

  // what the lines were last told
  (int, int)? _told;
  Style? _toldStyle;

  @override
  String get selectableText => state._selectable();

  @override
  (int, int) selectableRangeAt(int x, int y) => state._rangeAt(this, x, y);

  @override
  bool scrollSelectionBy(int rows) => state._scrollToSelect(rows);

  /// The part of the line of [number] selected, offsets in it.
  (int, int)? selectedOf(int number) => state._selectedOf(number, selection);

  /// Marked for paint by the area when what is selected changed: the lines
  /// are told.
  @override
  void markNeedsPaint() {
    super.markNeedsPaint();
    if (selection == _told && selectionStyle == _toldStyle) {
      return;
    }
    _told = selection;
    _toldStyle = selectionStyle;
    void visit(RenderObject o) {
      if (o is _RenderLine) {
        o.reselect();
        return;
      }
      o.visitChildren(visit);
    }

    visitChildren(visit);
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.minWidth;
      height = c.minHeight;
      return;
    }
    child.layout(c, parentUsesSize: true);
    child.parentData
      ..dx = 0
      ..dy = 0;
    width = child.width;
    height = child.height;
  }

  @override
  void paint(PaintContext ctx) {
    if (child case final child?) {
      paintChild(ctx, child);
    }
  }
}

/// A line of a [LogView]: its [number], and its [spans] scrolled [shift]
/// columns across, or wrapped when [shift] is null; [current] the line of
/// the current match.
final class _Line extends LeafRenderObjectWidget {
  const _Line({
    required this.number,
    required this.shift,
    required this.spans,
    required this.current,
    super.key,
  });

  final int number;
  final int? shift;
  final List<(String, Style)> spans;
  final bool current;

  /// [spans], their styles merged onto the [DefaultTextStyle] above.
  List<(String, Style)> _spansIn(BuildContext context) {
    final style = DefaultTextStyle.of(context);
    return [for (final (text, s) in spans) (text, style.merge(s))];
  }

  @override
  _RenderLine createRenderObject(BuildContext context) =>
      _RenderLine(number, shift, _spansIn(context))..current = current;

  @override
  void updateRenderObject(BuildContext context, _RenderLine renderObject) =>
      renderObject
        ..number = number
        ..shift = shift
        ..spans = _spansIn(context)
        ..current = current;
}

/// What a [_Line] lays out and paints: a paragraph of its spans, what is
/// selected of it in the selection's style, as wide as it may be, or,
/// with a [shift], as wide as it likes, [shift] columns of it off to the
/// left and what does not fit cut off. The paragraph is its own, no
/// [Text]'s: a [SelectionArea] selects in the line through the
/// [_RenderSelected] above. The line of the current match puts the hidden
/// cursor on its first cell (`restCursor`), as an `ActiveItem` would, the
/// list's items left lines.
final class _RenderLine extends RenderObject with RenderObjectWithChildMixin {
  _RenderLine(this._number, this._shift, this._spans) {
    child = RenderParagraph(
      _pens(),
      wrap: _shift == null ? TextWrap.word : TextWrap.none,
    );
  }

  /// The number of the line.
  int get number => _number;
  int _number;
  set number(int n) {
    if (n != _number) {
      _number = n;
      reselect();
    }
  }

  List<(String, Style)> get spans => _spans;
  List<(String, Style)> _spans;
  set spans(List<(String, Style)> s) {
    var same = s.length == _spans.length;
    for (var i = 0; same && i < s.length; i++) {
      same = s[i] == _spans[i];
    }
    if (!same) {
      _spans = s;
      _paragraph.spans = _pens();
    }
  }

  int? _shift;
  int? get shift => _shift;
  set shift(int? s) {
    if (s == _shift) {
      return;
    }
    if ((s == null) != (_shift == null)) {
      _paragraph.wrap = s == null ? TextWrap.word : TextWrap.none;
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
    _shift = s;
    _place();
  }

  /// Whether it is the line of the current match.
  bool get current => _current;
  var _current = false;
  set current(bool c) {
    if (c != _current) {
      _current = c;
      markNeedsPaint();
    }
  }

  // what is selected of it, offsets in its text, and in what style
  (int, int)? _selected;
  Style? _selectedStyle;

  RenderParagraph get _paragraph => child! as RenderParagraph;

  /// Asks the [_RenderSelected] above what is selected of the line, and
  /// paints it so when that changed.
  void reselect() {
    _RenderSelected? view;
    for (var p = parent; p != null; p = p.parent) {
      if (p is _RenderSelected) {
        view = p;
        break;
      }
    }
    final selected = view?.selectedOf(_number);
    final style = selected == null ? null : view!.selectionStyle;
    if (selected == _selected && style == _selectedStyle) {
      return;
    }
    _selected = selected;
    _selectedStyle = style;
    _paragraph.spans = _pens();
  }

  /// The spans as (text, pen), each split where the selection starts and
  /// ends, the part selected in its style merged onto theirs.
  List<(String, Pen)> _pens() {
    final selected = _selected;
    final style = _selectedStyle;
    if (selected == null || style == null) {
      return [for (final (text, s) in _spans) (text, s.pen)];
    }
    final (start, end) = selected;
    final out = <(String, Pen)>[];
    var at = 0;
    for (final (text, s) in _spans) {
      final a = (start - at).clamp(0, text.length);
      final b = (end - at).clamp(a, text.length);
      if (a > 0) {
        out.add((text.substring(0, a), s.pen));
      }
      if (b > a) {
        out.add((text.substring(a, b), s.merge(style).pen));
      }
      if (b < text.length) {
        out.add((text.substring(b), s.pen));
      }
      at += text.length;
    }
    return out;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('number', _number)
      ..add('shift', _shift, defaultValue: null)
      ..add('current', _current, defaultValue: false)
      ..add('selected', _selected, defaultValue: null);
  }

  @override
  void performLayout(BoxConstraints c) {
    reselect();
    final child = _paragraph;
    if (_shift == null) {
      child.layout(c, parentUsesSize: true);
      width = child.width;
      height = child.height;
    } else {
      child.layout(
        BoxConstraints(minHeight: c.minHeight, maxHeight: c.maxHeight),
        parentUsesSize: true,
      );
      width = c.maxWidth;
      height = c.constrainHeight(child.height);
    }
    _place();
  }

  void _place() {
    _paragraph.parentData
      ..dx = -(_shift ?? 0)
      ..dy = 0;
  }

  @override
  void paint(PaintContext ctx) {
    // the hidden cursor on the current match's line
    if (_current) {
      restCursor(ctx, this, 0, 0);
    } else {
      clearRestCursor(ctx, this);
    }
    ctx.canvas
      ..save()
      ..clipRect(0, 0, width, height);
    paintChild(ctx, _paragraph);
    ctx.canvas.restore();
  }
}

/// Lines a [LogController] takes from a stream or a file
/// ([LogController.addOutput], [LogController.followFile]): [cancel] it when
/// they are not wanted, await [done] for the end of them.
final class LogSource {
  LogSource._();

  StreamSubscription<void>? _subscription;
  void Function()? _onCancel;
  final _done = Completer<void>();

  /// Stops the lines and frees the source; the line not ended is not added.
  /// Cancelling again, or one already done, does nothing more.
  Future<void> cancel() {
    _onCancel?.call();
    final cancelled = _subscription?.cancel() ?? Future<void>.value();
    if (!_done.isCompleted) {
      _done.complete();
    }
    return cancelled;
  }

  /// Completes when the output ends (its last unended line added) or the
  /// source is cancelled; with the error of the output where it failed.
  Future<void> get done => _done.future;

  void _finish(Object? error, StackTrace? stack) {
    if (_done.isCompleted) {
      return;
    }
    if (error == null) {
      _done.complete();
    } else {
      // an error nobody awaits is not an uncaught one
      _done.future.ignore();
      _done.completeError(error, stack);
    }
  }
}
