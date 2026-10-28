/// Highlighted source as a widget: [CodeView], and the
/// [CodeViewController] that scrolls it, highlights its lines and finds
/// text in them.
///
/// @docImport 'languages.dart';
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show RenderParagraph;

import 'highlighter.dart';
import 'lexer.dart';
import 'syntax_theme.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// late BuildContext context;
// late String source;

/// [code] in [language], each token in the style the [SyntaxTheme] at its
/// place ([SyntaxTheme.of]) gives its kind: its lines one under another,
/// and with [lineNumbers] each line's number in a gutter before it.
///
/// A line break at the end of [code] ends its last line rather than
/// starting another. A tab moves to the next multiple of [tabWidth]
/// columns. Lines are broken as [wrap] says: by default not at all, so
/// that a line wider than the view is cut off. The numbers count from
/// [firstLineNumber], right-aligned, in the [ThemeData.muted] style of the
/// [Theme], a blank between them and the code; a line wrapped onto more
/// rows has its number on the first.
///
/// [signs] puts an app's own marks in the gutter, a [CodeSign] by the
/// number of the line it is beside (as the gutter numbers them, from
/// [firstLineNumber]): a diagnostic, a breakpoint, a change since the last
/// commit. They are a column of their own, before the numbers, or before
/// the code without them, a blank after it; as wide as the widest sign as
/// the canvas draws it, one column at least, each sign at its left on the
/// first row of its line, in its own style. A line with none has blanks
/// there, and with [signs] empty the column is there all the same, so that
/// the code does not move as signs come and go; null for no column.
///
/// Below a [SelectionArea] its code is selected and copied as a [Text]'s
/// is, its lines joined by line breaks and its tabs as tabs; the signs and
/// the numbers are not text, left out of what is selected and copied.
///
/// With none of [controller], [focusNode] and [autofocus] it is as tall as
/// its lines, to be put in a view that scrolls ([SingleChildScrollView])
/// or in one that does not. With any of them it scrolls its lines itself,
/// as a [ListView] of them that builds those in view: it takes all the
/// room it is given, which must be bounded, and while it has the focus the
/// arrows, PageUp, PageDown, Home and End scroll it, those that would move
/// it hinted for a `KeyHintsBar`; Left and Right scroll lines that are not
/// wrapped across, [sideStep] columns at a time, as far as the widest. The
/// [controller] scrolls it to a line, says which lines are in view,
/// highlights lines (in [highlightStyle] by default, a tint of the
/// [ThemeData.primary] color) and finds text in them: what it finds is
/// drawn in [matchStyle] (reverse video) merged onto the code, the current
/// match in [currentMatchStyle] ([ThemeData.accent] in reverse video and
/// bold), and `n` and `N` go to the next and the previous match while it
/// has a query.
///
/// When [code] changes, only the lines an edit changed are lexed again
/// ([Highlighter.update]); a new [language] lexes it whole. A line whose
/// tokens, sign, highlight and matches are what they were keeps its
/// widget.
///
/// A Dart file with its line numbers and a mark beside the line with an
/// error, in a box of 20 rows that scrolls with the keys once focused:
///
/// ```dart
/// SizedBox(
///   height: 20,
///   child: CodeView(
///     source,
///     language: languageNamed('dart'),
///     lineNumbers: true,
///     signs: {12: CodeSign('●', style: Theme.of(context).error)},
///     autofocus: true,
///   ),
/// )
/// ```
///
/// See also:
///
///  * [CodeViewController], to scroll it to a line, highlight lines and
///    find text in it.
///  * [SyntaxThemeScope], to set the colors of the code.
///  * [Highlighter], the tokens of the lines without a widget.
final class CodeView extends StatefulWidget {
  /// Shows [code] in [language], plain text by default: no line numbers,
  /// counting from 1 when shown, tabs 4 columns apart, lines not wrapped,
  /// no column of signs, and as tall as its lines unless a [controller],
  /// a [focusNode] or [autofocus] makes it scroll them.
  const CodeView(
    this.code, {
    super.key,
    this.language = Language.plain,
    this.lineNumbers = false,
    this.firstLineNumber = 1,
    this.tabWidth = 4,
    this.wrap = TextWrap.none,
    this.signs,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.highlightStyle,
    this.matchStyle,
    this.currentMatchStyle,
  }) : assert(tabWidth > 0, 'tabWidth < 1');

  /// The source shown, its lines apart at each `\n` or `\r\n`.
  final String code;

  /// The language of [code]; [languageNamed] finds one by name.
  final Language language;

  /// Whether a gutter before the lines shows their numbers.
  final bool lineNumbers;

  /// The number of the first line.
  final int firstLineNumber;

  /// Columns between tab stops.
  final int tabWidth;

  /// How a line wider than the view is broken onto more rows:
  /// [TextWrap.none] by default, cut off at the view's right edge.
  final TextWrap wrap;

  /// The sign beside each line that has one, by its number; null for no
  /// column of signs.
  final Map<int, CodeSign>? signs;

  /// Scrolls it to a line, highlights lines and finds text in them; given
  /// to one view at a time. With one it scrolls its lines itself.
  final CodeViewController? controller;

  /// See [Focus.focusNode]. With one it scrolls its lines itself.
  final FocusNode? focusNode;

  /// See [Focus.autofocus]. Set, it scrolls its lines itself.
  final bool autofocus;

  /// Merged onto a line the [controller] highlights without a style of its
  /// own, across the view; a tint of the [ThemeData.primary] color when
  /// null (reverse video where that is a color of the terminal's palette).
  final Style? highlightStyle;

  /// Merged onto what the [controller]'s query finds; reverse video when
  /// null.
  final Style? matchStyle;

  /// Merged onto the current match; [ThemeData.accent] in reverse video
  /// and bold when null.
  final Style? currentMatchStyle;

  /// The columns Left and Right scroll lines that are not wrapped across.
  static const sideStep = 4;

  @override
  State<CodeView> createState() => _CodeViewState();
}

/// A mark in the gutter of a [CodeView] beside a line ([CodeView.signs]):
/// [glyph], a character or a few (`●`, `E`, `▎`), in [style] merged onto
/// the text's.
final class CodeSign {
  /// A sign showing [glyph] in [style], by default the style of the text.
  const CodeSign(this.glyph, {this.style = const Style()});

  /// What the sign shows.
  final String glyph;

  /// Merged onto the style of the text where the sign is drawn.
  final Style style;

  @override
  bool operator ==(Object other) =>
      other is CodeSign && other.glyph == glyph && other.style == style;

  @override
  int get hashCode => Object.hash(glyph, style);

  @override
  String toString() => 'CodeSign($glyph)';
}

/// What a [CodeViewController]'s query found: on the line of number
/// [line] (as the gutter numbers it), from [start] up to [end], offsets in
/// UTF-16 code units of the line's text.
final class CodeMatch {
  /// A match on line [line], from [start] up to [end].
  const CodeMatch(this.line, this.start, this.end);

  /// The number of the line, as the gutter numbers it.
  final int line;

  /// The offset in the line's text where the match starts.
  final int start;

  /// The offset in the line's text after the match's last code unit.
  final int end;

  @override
  bool operator ==(Object other) =>
      other is CodeMatch &&
      other.line == line &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(line, start, end);

  @override
  String toString() => 'CodeMatch($line, $start, $end)';
}

/// What is done to the [CodeView] it is given to: scrolled to a line
/// ([scrollToLine]), with the lines in its window read back
/// ([linesInView]); lines highlighted ([highlightLines]), an error or the
/// line a debugger stopped at; and text found ([query], [matches]) and
/// gone through ([nextMatch], [previousMatch]). A line is named by its
/// number, as the gutter numbers it, from [CodeView.firstLineNumber].
///
/// [query] ignores the case while it is all in lower case and heeds it
/// otherwise (as vim's smartcase: [Smartcase]). The matches are found
/// in the code of the view it is given to, when first asked for after the
/// query or the code changed: none while it is given to none.
///
/// It notifies its listeners of each change it is asked for, whenever the
/// view scrolls, and, after the build, as the view, its code or its line
/// numbers change what the query finds. Given to one [CodeView] at a
/// time; given to one built in place of its view (a key changed), it goes
/// over to that one.
///
/// The line a debugger stopped at, highlighted in the middle of the view;
/// then every `TODO` in the code found, the first at or below the top of
/// the window made current:
///
/// ```dart
/// final controller = CodeViewController();
/// // in build: CodeView(source, controller: controller, lineNumbers: true)
/// controller
///   ..clearHighlights()
///   ..highlightLines([42])
///   ..scrollToLine(42, alignment: 0.5);
/// controller.query = 'TODO';
/// controller.nextMatch();
/// ```
final class CodeViewController extends ChangeNotifier {
  /// A controller finding [query], none by default, with no line
  /// highlighted, to be given to a [CodeView].
  CodeViewController({this._query = ''});

  // the view it is given to
  final _hosts = ControllerHost<_CodeViewState>();

  // bumped by each change of what the view draws
  var _changes = 0;

  // the move asked for and not made yet: the line, and where in the window
  ({int line, double? alignment})? _request;

  // whether the view is to scroll across to show the current match
  var _across = false;

  final _highlights = <int, Style?>{};

  /// Scrolls the view to show line [line], as the gutter numbers it: with
  /// no [alignment] the least that shows it, else to put it that far down
  /// the window, 0 at the top, 0.5 in the middle and 1 at the bottom, as
  /// far as the ends allow. A line before the first or after the last is
  /// taken as that one. Asked for before the view is laid out, it is made
  /// as it is first laid out. With lines wrapped onto more rows,
  /// [alignment] counts the lines above it as a row each.
  void scrollToLine(int line, {double? alignment}) {
    assert(
      alignment == null || (alignment >= 0 && alignment <= 1),
      'an alignment from 0 to 1',
    );
    _request = (line: line, alignment: alignment);
    _hosts.host?._scrollAsked();
  }

  /// The numbers of the first and the last line with a row in the window,
  /// as the view was last laid out; null while it is given to no view or
  /// before the view is laid out.
  ({int first, int last})? get linesInView => _hosts.host?._linesInView();

  /// The lines highlighted, by number, each with its style; null for the
  /// view's [CodeView.highlightStyle].
  Map<int, Style?> get highlights => Map.unmodifiable(_highlights);

  /// Highlights [lines], by number, in [style] merged onto them across the
  /// view, or in the view's [CodeView.highlightStyle] without one.
  void highlightLines(Iterable<int> lines, {Style? style}) {
    for (final line in lines) {
      _highlights[line] = style;
    }
    _changed();
  }

  /// Highlights the lines from [first] to [last], both of them too, as
  /// [highlightLines] does.
  void highlightRange(int first, int last, {Style? style}) =>
      highlightLines([for (var n = first; n <= last; n++) n], style: style);

  /// Takes the highlight off [lines].
  void unhighlightLines(Iterable<int> lines) {
    lines.forEach(_highlights.remove);
    _changed();
  }

  /// Takes the highlight off every line.
  void clearHighlights() {
    _highlights.clear();
    _changed();
  }

  /// What [matches] are, drawn in the view's [CodeView.matchStyle]; empty
  /// for none. Set, there is no current match.
  String get query => _query;
  String _query;

  set query(String query) {
    if (query == _query) {
      return;
    }
    _query = query;
    _matches = null;
    _current = null;
    _changed();
  }

  List<CodeMatch>? _matches;
  CodeMatch? _current;

  /// Where [query] is in the code, in order, none overlapping another.
  List<CodeMatch> get matches => _matches ??= List.unmodifiable(_find());

  /// The match [nextMatch] or [previousMatch] went to, while the code still
  /// has it; null when there is none.
  CodeMatch? get currentMatch {
    final i = currentMatchIndex;
    return i == null ? null : matches[i];
  }

  /// Where [currentMatch] is in [matches]; null when there is none.
  int? get currentMatchIndex {
    final c = _current;
    if (c == null) {
      return null;
    }
    final i = _firstAtOrAfter(c.line, c.start);
    final ms = matches;
    return i < ms.length && ms[i] == c ? i : null;
  }

  /// Makes the match after the current one current, round to the first
  /// past the last; with no current match, the first on a line at or
  /// below the top of the window. The view scrolls the least that shows
  /// it, across too. Returns whether there is a match.
  bool nextMatch() => _seek(forward: true);

  /// Makes the match before the current one current, round to the last
  /// past the first; with no current match, the last on a line at or above
  /// the bottom of the window. The view scrolls the least that shows it,
  /// across too. Returns whether there is a match.
  bool previousMatch() => _seek(forward: false);

  bool _seek({required bool forward}) {
    final ms = matches;
    if (ms.isEmpty) {
      return false;
    }
    final n = ms.length;
    var i = currentMatchIndex;
    if (i != null) {
      i = (i + (forward ? 1 : -1) + n) % n;
    } else {
      final window = linesInView;
      if (forward) {
        i = window == null ? 0 : _firstAtOrAfter(window.first, 0);
        i = i < n ? i : 0;
      } else {
        i = window == null ? n : _firstAtOrAfter(window.last + 1, 0);
        i = i > 0 ? i - 1 : n - 1;
      }
    }
    final m = ms[i];
    _current = m;
    _request = (line: m.line, alignment: null);
    _across = true;
    _changed();
    _hosts.host?._scrollAsked();
    return true;
  }

  /// The index of the first match at or after [start] of line [line]; the
  /// length of [matches] when there is none.
  int _firstAtOrAfter(int line, int start) {
    final ms = matches;
    var lo = 0;
    var hi = ms.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      final m = ms[mid];
      if (m.line < line || (m.line == line && m.start < start)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  List<CodeMatch> _find() {
    final view = _hosts.host;
    final q = _query;
    if (view == null || q.isEmpty) {
      return const [];
    }
    final first = view.widget.firstLineNumber;
    final search = Smartcase(q);
    return [
      for (var i = 0; i < view._lineCount; i++)
        for (
          var at = search.indexIn(view._code.line(i));
          at >= 0;
          at = search.indexIn(view._code.line(i), at + q.length)
        )
          CodeMatch(first + i, at, at + q.length),
    ];
  }

  void _changed() {
    _changes++;
    notifyListeners();
  }

  /// The view scrolled, or was laid out.
  void _scrolled() => notifyListeners();

  /// The code of the view, or the numbers of its lines, changed, or the
  /// view: the matches are found again when next asked for, and the
  /// listeners told after the build, where there is a query.
  void _codeChanged() {
    _matches = null;
    if (_query.isNotEmpty && !_telling) {
      _telling = true;
      _hosts.afterBuild(() {
        _telling = false;
        notifyListeners();
      });
    }
  }

  // the listeners are to be told after the build
  var _telling = false;

  @override
  void dispose() {
    _hosts.dispose();
    super.dispose();
  }
}

/// [line] with each tab as the blanks up to the next multiple of [tab]
/// columns, and where each of its code units, and its end, are in it;
/// null for where, when it has no tab.
(String, List<int>?) _expandTabs(String line, int tab) {
  if (!line.contains('\t')) {
    return (line, null);
  }
  final out = StringBuffer();
  final at = List<int>.filled(line.length + 1, 0);
  var column = 0;
  var run = 0;
  for (var i = 0; i < line.length; i++) {
    at[i] = out.length;
    if (line.codeUnitAt(i) == 0x09) {
      column += stringWidth(line.substring(run, i));
      final blanks = tab - column % tab;
      out.write(' ' * blanks);
      column += blanks;
      run = i + 1;
    } else {
      out.writeCharCode(line.codeUnitAt(i));
    }
  }
  at[line.length] = out.length;
  return (out.toString(), at);
}

/// What the rows of a [CodeView] are made with: when it changes, every row
/// is made again.
typedef _Look = (
  SyntaxTheme,
  (Style, int, int)?,
  String?,
  int,
  TextWrap,
  int?,
  Style,
  Style,
);

final class _CodeViewState extends State<CodeView> {
  late Highlighter _code;
  final _list = ListController();

  // the controller attached, and its changes as of the last build
  CodeViewController? _controller;
  var _changes = 0;

  // the columns lines not wrapped are scrolled across
  var _shift = 0;

  // the render object that selects in the lines, as last made
  _RenderCodeSelection? _selection;

  /// The row made of each line, as last made, and what it was made of: a
  /// line whose tokens, sign, highlight and matches are those it was made
  /// of keeps its row, so that its element is not updated.
  final _rows = <Widget?>[];
  final _rowKeys = <Object?>[];
  _Look? _look;

  // the text a selection selects in, and where each line starts in it
  String? _text;
  var _starts = <int>[];

  // the widest line, tabs expanded, in columns
  int? _widest;

  bool get _scrolls =>
      widget.controller != null || widget.focusNode != null || widget.autofocus;

  /// The lines shown: those of the code but the empty one after a final
  /// line break.
  int get _lineCount {
    final count = _code.lineCount;
    return count > 1 && _code.line(count - 1).isEmpty ? count - 1 : count;
  }

  @override
  void initState() {
    super.initState();
    _code = Highlighter(widget.language, widget.code);
    _list.addListener(_scrolled);
    _attach(widget.controller);
  }

  @override
  void didUpdateWidget(CodeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    var changed = widget.firstLineNumber != oldWidget.firstLineNumber;
    if (!identical(widget.language, oldWidget.language)) {
      _code = Highlighter(widget.language, widget.code);
      changed = true;
    } else if (widget.code != oldWidget.code) {
      _code.update(widget.code);
      changed = true;
    }
    if (changed) {
      _text = null;
      _widest = null;
      _controller?._codeChanged();
    }
    if (widget.tabWidth != oldWidget.tabWidth) {
      _widest = null;
    }
    if (!identical(widget.controller, oldWidget.controller)) {
      _detach();
      _attach(widget.controller);
    }
  }

  @override
  void dispose() {
    _detach();
    _list
      ..removeListener(_scrolled)
      ..dispose();
    super.dispose();
  }

  /// Serves [c], in place of the view that did.
  void _attach(CodeViewController? c) {
    if (c == null) {
      return;
    }
    c._hosts.attach(this);
    _controller = c
      .._codeChanged()
      ..addListener(_changed);
    _changes = c._changes;
  }

  /// Lets go of the controller, which, where this view still has it, finds
  /// no matches now.
  void _detach() {
    final c = _controller;
    if (c == null) {
      return;
    }
    c.removeListener(_changed);
    if (c._hosts.detach(this)) {
      c._codeChanged();
    }
    _controller = null;
  }

  /// The controller changed: what is drawn, or a move asked for. Nothing
  /// once a view built in this one's place has it.
  void _changed() {
    final c = _controller!;
    if (c._changes == _changes || !c._hosts.isHost(this)) {
      return;
    }
    _changes = c._changes;
    if (c._across) {
      c._across = false;
      _showAcross(c.currentMatch);
    }
    setState(() {});
  }

  /// The room of the code changed as it was laid out: the keys are bound
  /// anew.
  void _relaid() {
    if (mounted) {
      setState(() {});
    }
  }

  /// The controller asked for a move, which the next layout makes.
  void _scrollAsked() => _selection?.markNeedsLayout();

  /// The list scrolled, or was laid out.
  void _scrolled() => _controller?._scrolled();

  /// Makes the move the controller asked for, if any, in a window of
  /// [height] rows: what the selection's layout calls, before it lays the
  /// list out.
  void _move(int height) {
    final c = _controller;
    final request = c?._request;
    if (c == null || request == null) {
      return;
    }
    c._request = null;
    final count = _lineCount;
    final index = (request.line - widget.firstLineNumber).clamp(0, count - 1);
    if (request.alignment case final alignment?) {
      final above = (alignment * (height - 1)).round();
      _list.jumpToIndex(index - above > 0 ? index - above : 0);
    } else {
      _list.ensureIndexVisible(index);
    }
  }

  /// The numbers of the first and the last line with a row in the window,
  /// as last laid out.
  ({int first, int last})? _linesInView() {
    final view = _selection;
    if (!mounted || view == null || !view._laidOut) {
      return null;
    }
    int? first;
    int? last;
    for (final (line, _, y) in view._lines()) {
      if (y + line.height > 0 && y < view.height) {
        first = first == null ? line.index : math.min(first, line.index);
        last = last == null ? line.index : math.max(last, line.index);
      }
    }
    if (first == null || last == null) {
      return null;
    }
    final n = widget.firstLineNumber;
    return (first: n + first, last: n + last);
  }

  /// The text a selection selects in: the lines joined by line breaks.
  String get _selectable {
    if (_text case final text?) {
      return text;
    }
    final out = StringBuffer();
    final starts = <int>[];
    for (var i = 0; i < _lineCount; i++) {
      if (i > 0) {
        out.write('\n');
      }
      starts.add(out.length);
      out.write(_code.line(i));
    }
    _starts = starts;
    return _text = out.toString();
  }

  /// Where line [index] starts in the text and where it ends, before its
  /// line break.
  (int, int) _lineRange(int index) {
    _selectable;
    if (index >= _starts.length) {
      final end = _text!.length;
      return (end, end);
    }
    return (_starts[index], _starts[index] + _code.line(index).length);
  }

  /// The range of the text the cell [x], [y] of the selection stands for.
  (int, int) _rangeAt(_RenderCodeSelection view, int x, int y) {
    final text = _selectable;
    (_RenderCodeLine, int, int)? hit;
    (_RenderCodeLine, int, int)? top;
    (_RenderCodeLine, int, int)? bottom;
    for (final placed in view._lines()) {
      final (line, _, ly) = placed;
      if (y >= ly && y < ly + line.height) {
        hit = placed;
      }
      if (top == null || ly < top.$3) {
        top = placed;
      }
      if (bottom == null || ly > bottom.$3) {
        bottom = placed;
      }
    }
    if (top == null || bottom == null) {
      return (0, 0);
    }
    if (hit == null) {
      if (y < top.$3) {
        final (start, _) = _lineRange(top.$1.index);
        return (start, start);
      }
      final (_, end) = _lineRange(bottom.$1.index);
      final next = math.min(end + 1, text.length);
      return (next, next);
    }
    final (line, lx, ly) = hit;
    final (start, end) = _lineRange(line.index);
    final range = line.rangeAt(x - lx, y - ly);
    if (range == null) {
      final next = math.min(end + 1, text.length);
      return (next, next);
    }
    return (start + range.$1, start + range.$2);
  }

  /// Scrolls the list by [rows] for a drag past its edge that selects;
  /// whether it moved.
  bool _scrollToSelect(int rows) {
    if (!_scrolls || !_list.hasClients || rows == 0) {
      return false;
    }
    final p = _list.position;
    final from = p.offset;
    p.jumpTo(from + rows);
    return p.offset != from;
  }

  /// The columns of the code in view, as last laid out; null before.
  int? get _room => _selection?._codeWidth;

  /// The widest line, tabs expanded, in columns.
  int get _widestLine {
    if (_widest case final widest?) {
      return widest;
    }
    var widest = 0;
    for (var i = 0; i < _lineCount; i++) {
      final (text, _) = _expandTabs(_code.line(i), widget.tabWidth);
      widest = math.max(widest, stringWidth(text));
    }
    return _widest = widest;
  }

  /// Scrolls lines not wrapped across by [delta] columns, as far as the
  /// widest; whether they moved.
  bool _scrollAcross(int delta) {
    if (!_scrolls || widget.wrap != TextWrap.none) {
      return false;
    }
    final room = _room ?? 0;
    final most = math.max(0, _widestLine - room);
    final to = (_shift + delta).clamp(0, most);
    if (to == _shift) {
      return false;
    }
    setState(() => _shift = to);
    return true;
  }

  /// Scrolls across the least that shows [match], lines not wrapped.
  void _showAcross(CodeMatch? match) {
    final room = _room;
    if (match == null ||
        room == null ||
        room <= 0 ||
        widget.wrap != TextWrap.none) {
      return;
    }
    final index = match.line - widget.firstLineNumber;
    if (index < 0 || index >= _lineCount) {
      return;
    }
    final (text, at) = _expandTabs(_code.line(index), widget.tabWidth);
    int column(int offset) =>
        stringWidth(text.substring(0, at == null ? offset : at[offset]));
    final start = column(match.start);
    final end = column(match.end);
    if (start < _shift) {
      _shift = start;
    } else if (end > _shift + room) {
      _shift = end - room;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final syntax = SyntaxTheme.of(context);
    final count = _lineCount;
    final first = widget.firstLineNumber;
    final digits = '${first + count - 1}'.length;
    final signs = widget.signs;
    // the glyphs the column of signs is as wide as the widest of
    final glyphs = signs == null
        ? null
        : ({for (final sign in signs.values) sign.glyph}.toList()..sort());
    final c = _controller;
    final unwrapped = widget.wrap == TextWrap.none;
    // no further across than the widest line now
    final room = _room;
    if (_shift > 0 && room != null) {
      _shift = math.min(_shift, math.max(0, _widestLine - room));
    }
    final shift = unwrapped ? (_scrolls ? _shift : 0) : null;
    final look = (
      syntax,
      widget.lineNumbers ? (theme.muted, digits, first) : null,
      glyphs?.join('\n'),
      widget.tabWidth,
      widget.wrap,
      shift,
      widget.matchStyle ?? const Style(attrs: Attr.reverse),
      widget.currentMatchStyle ??
          theme.accent.merge(const Style(attrs: Attr.reverse | Attr.bold)),
    );
    if (look != _look) {
      _look = look;
      _rows.clear();
      _rowKeys.clear();
    }
    _rows.length = count;
    _rowKeys.length = count;
    final highlight = widget.highlightStyle ?? _tint(theme.primary);
    final highlights = c?._highlights ?? const <int, Style?>{};
    // the matches of each line by its index, the current one first
    final found = <int, List<CodeMatch>>{};
    if (c != null && c.query.isNotEmpty) {
      for (final m in c.matches) {
        (found[m.line - first] ??= []).add(m);
      }
    }
    final current = c?.currentMatch;

    Widget row(int i) {
      final tokens = _code.tokens(i);
      final sign = signs?[first + i];
      final lit = highlights.containsKey(first + i)
          ? highlights[first + i] ?? highlight
          : null;
      final matches = found[i] ?? const <CodeMatch>[];
      final key = (
        tokens,
        sign,
        lit,
        [
          for (final m in matches)
            '${m.start}-${m.end}${m == current ? '*' : ''}',
        ].join(','),
      );
      if (key == _rowKeys[i]) {
        return _rows[i]!;
      }
      final made = _row(i, look, glyphs, sign, lit, matches, current);
      _rows[i] = made;
      _rowKeys[i] = key;
      return made;
    }

    if (!_scrolls) {
      return _CodeSelection(
        state: this,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (var i = 0; i < count; i++) row(i)],
        ),
      );
    }
    final canLeft = unwrapped && _shift > 0;
    final canRight = unwrapped && (room == null || _shift < _widestLine - room);
    final bindings = <String, VoidCallback>{
      if (c != null && c.query.isNotEmpty) ...{
        'n': c.nextMatch,
        'N': c.previousMatch,
      },
      if (canLeft) 'left': () => _scrollAcross(-CodeView.sideStep),
      if (canRight) 'right': () => _scrollAcross(CodeView.sideStep),
    };
    return KeyBindings(
      bindings,
      hints: {
        if (bindings.containsKey('n')) ...{
          'n': 'next match',
          'N': 'previous match',
        },
        if (canLeft) 'left': 'scroll',
        if (canRight) 'right': 'scroll',
      },
      child: _CodeSelection(
        state: this,
        child: ListView.builder(
          itemCount: count,
          itemExtent: unwrapped ? 1 : null,
          controller: _list,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          itemBuilder: (context, index) => row(index),
        ),
      ),
    );
  }

  /// The row of line [index], made with [look]: [sign] in the column of
  /// [glyphs], its highlight [lit], and its [matches], [current] among
  /// them or not.
  Widget _row(
    int index,
    _Look look,
    List<String>? glyphs,
    CodeSign? sign,
    Style? lit,
    List<CodeMatch> matches,
    CodeMatch? current,
  ) {
    final (syntax, numbers, _, tab, wrap, shift, match, now) = look;
    // the tokens as pieces, each match a piece of its own over them
    final pieces = <(String, Style)>[];
    final onFill = lit == null ? null : _overFill(lit);
    var at = 0;
    var m = 0;
    for (final token in _code.tokens(index)) {
      var style = syntax.styleOf(token.kind);
      if (onFill != null) {
        style = style.merge(onFill);
      }
      final text = token.text;
      for (var from = 0; from < text.length;) {
        while (m < matches.length && matches[m].end <= at + from) {
          m++;
        }
        final inMatch = m < matches.length && matches[m].start <= at + from;
        final end = m < matches.length
            ? math.min(
                (inMatch ? matches[m].end : matches[m].start) - at,
                text.length,
              )
            : text.length;
        pieces.add((
          text.substring(from, end),
          inMatch ? style.merge(matches[m] == current ? now : match) : style,
        ));
        from = end;
      }
      at += text.length;
    }
    // each tab as the blanks up to the next tab stop
    final line = _code.line(index);
    final (_, map) = _expandTabs(line, tab);
    final segments = map == null ? pieces : _expandPieces(pieces, line, map);
    final muted = numbers?.$1;
    return _CodeLine(
      index: index,
      segments: segments,
      offsets: map,
      glyphs: glyphs,
      sign: sign,
      number: numbers == null
          ? null
          : '${numbers.$3 + index}'.padLeft(numbers.$2),
      numberStyle: muted ?? const Style(),
      highlight: lit,
      shift: shift,
      wrap: wrap,
    );
  }
}

/// [pieces] of [line], each tab in them as the blanks [map] says it takes.
List<(String, Style)> _expandPieces(
  List<(String, Style)> pieces,
  String line,
  List<int> map,
) {
  final out = <(String, Style)>[];
  var at = 0;
  for (final (text, style) in pieces) {
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x09) {
        buffer.write(' ' * (map[at + i + 1] - map[at + i]));
      } else {
        buffer.writeCharCode(text.codeUnitAt(i));
      }
    }
    out.add((buffer.toString(), style));
    at += text.length;
  }
  return out;
}

/// [lit], a line's highlight, as merged onto what is drawn over the
/// line's fill: its background left as the fill painted it, so that a
/// translucent one tints the line once, under the text as under blanks.
Style _overFill(Style lit) =>
    lit.bg == null ? lit : lit.merge(Style(bg: lit.bg, bgAlpha: 0));

/// A background of the text color of [style] at a low alpha; reverse
/// video where that is no RGB color.
Style _tint(Style style) => switch (style.fg) {
  final color? when color.isRgb => Style(bg: color, bgAlpha: 0x30),
  _ => const Style(attrs: Attr.reverse),
};

/// The lines of a [CodeView] as a [SelectionArea] selects in them: one
/// [Selectable] for all of them, those out of view too.
final class _CodeSelection extends SingleChildRenderObjectWidget {
  const _CodeSelection({required this.state, required Widget super.child});

  final _CodeViewState state;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderCodeSelection createRenderObject(BuildContext context) =>
      state._selection = _RenderCodeSelection(state);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCodeSelection renderObject,
  ) {
    renderObject.state = state;
    state._selection = renderObject;
  }
}

/// What a [_CodeSelection] lays out and paints: its child, as large as it,
/// the move the controller asked for made before the child's layout. What
/// is selected of it is painted by the lines, each told when it changes.
final class _RenderCodeSelection extends RenderObject
    with RenderObjectWithChildMixin, Selectable {
  _RenderCodeSelection(this.state);

  _CodeViewState state;

  // what the lines were last told
  (int, int)? _told;
  Style? _toldStyle;

  // the columns of the code in view, as the lines were last laid out
  int? _codeWidth;

  // whether it has been laid out
  var _laidOut = false;

  @override
  String get selectableText => state._selectable;

  @override
  (int, int) selectableRangeAt(int x, int y) => state._rangeAt(this, x, y);

  @override
  bool scrollSelectionBy(int rows) => state._scrollToSelect(rows);

  @override
  bool scrollSelectionAcross(int columns) => state._scrollAcross(columns);

  /// The lines laid out below it, each with where it is in it.
  List<(_RenderCodeLine, int, int)> _lines() {
    final out = <(_RenderCodeLine, int, int)>[];
    void visit(RenderObject o, int x, int y) {
      if (o is _RenderCodeLine) {
        out.add((o, x, y));
        return;
      }
      o.visitChildren(
        (c) => visit(c, x + c.parentData.dx, y + c.parentData.dy),
      );
    }

    if (child case final child?) {
      visit(child, child.parentData.dx, child.parentData.dy);
    }
    return out;
  }

  /// The part of line [index] selected, offsets in its text.
  (int, int)? selectedOf(int index) {
    final s = selection;
    if (s == null) {
      return null;
    }
    final (start, end) = state._lineRange(index);
    final a = math.max(s.$1, start);
    final b = math.min(s.$2, end);
    return a < b ? (a - start, b - start) : null;
  }

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
    for (final (line, _, _) in _lines()) {
      line.reselect();
    }
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void performLayout(BoxConstraints c) {
    if (c.maxH < BoxConstraints.unbounded) {
      invokeLayoutCallback(() => state._move(c.maxH));
    }
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    child.layout(c, parentUsesSize: true);
    child.parentData
      ..dx = 0
      ..dy = 0;
    width = child.width;
    height = child.height;
    _laidOut = true;
    final lines = _lines();
    final room = lines.isEmpty ? null : lines.first.$1.codeWidth;
    if (room != _codeWidth) {
      _codeWidth = room;
      // the keys that scroll across are bound by the room there is
      if (state._scrolls) {
        scheduleMicrotask(state._relaid);
      }
    }
  }

  @override
  void paint(PaintContext ctx) {
    if (child case final child?) {
      paintChild(ctx, child);
    }
  }
}

/// Line [index] of a [CodeView]: its [segments], tabs expanded, where its
/// code units are in them ([offsets], null for a line without a tab), and
/// its gutter: [sign] in a column as wide as the widest of [glyphs] (none
/// when null) and its [number] (none when null) in [numberStyle]. With
/// [highlight] all of it is on that style; with a [shift], the code is
/// that many columns scrolled across and cut off, or else wrapped as
/// [wrap] says.
final class _CodeLine extends LeafRenderObjectWidget {
  const _CodeLine({
    required this.index,
    required this.segments,
    required this.offsets,
    required this.glyphs,
    required this.sign,
    required this.number,
    required this.numberStyle,
    required this.highlight,
    required this.shift,
    required this.wrap,
  });

  final int index;
  final List<(String, Style)> segments;
  final List<int>? offsets;
  final List<String>? glyphs;
  final CodeSign? sign;
  final String? number;
  final Style numberStyle;
  final Style? highlight;
  final int? shift;
  final TextWrap wrap;

  _LinePaint _stylesIn(BuildContext context) {
    final base = DefaultTextStyle.of(context);
    final lit = highlight;
    final onFill = lit == null ? null : _overFill(lit);
    Style over(Style s) => onFill == null ? s : s.merge(onFill);
    return (
      segments: [for (final (text, s) in segments) (text, base.merge(s))],
      sign: over(base.merge(sign?.style ?? const Style())),
      number: over(base.merge(numberStyle)),
      fill: lit == null ? null : base.merge(lit),
    );
  }

  @override
  _RenderCodeLine createRenderObject(BuildContext context) => _RenderCodeLine(
    index: index,
    styles: _stylesIn(context),
    offsets: offsets,
    glyphs: glyphs,
    glyph: sign?.glyph ?? '',
    number: number,
    shift: shift,
    wrap: wrap,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderCodeLine renderObject) =>
      renderObject
        ..index = index
        ..offsets = offsets
        ..glyphs = glyphs
        ..glyph = sign?.glyph ?? ''
        ..number = number
        ..shift = shift
        ..wrap = wrap
        ..styles = _stylesIn(context);
}

/// The styles a line is drawn in, merged onto the text's: its code in
/// segments, its sign, its number, and what fills it, if anything.
typedef _LinePaint = ({
  List<(String, Style)> segments,
  Style sign,
  Style number,
  Style? fill,
});

/// What a [_CodeLine] lays out and paints: its gutter, and a paragraph of
/// its code after it, what is selected of the code in the selection's
/// style. The paragraph is its own, no [Text]'s: a [SelectionArea]
/// selects in the line through the [_RenderCodeSelection] above.
final class _RenderCodeLine extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderCodeLine({
    required this.index,
    required this._styles,
    required this.offsets,
    required this._glyphs,
    required this._glyph,
    required this._number,
    required this._shift,
    required this._wrap,
  }) {
    child = RenderParagraph(_pens(), wrap: _paragraphWrap);
  }

  /// The index of the line in the code.
  int index;

  /// Where each code unit of the line is in its segments; null for the
  /// same place.
  List<int>? offsets;

  _LinePaint _styles;
  _LinePaint get styles => _styles;
  set styles(_LinePaint p) {
    final same =
        p.sign == _styles.sign &&
        p.number == _styles.number &&
        p.fill == _styles.fill &&
        _sameSegments(p.segments, _styles.segments);
    _styles = p;
    if (!same) {
      _paragraph.spans = _pens();
      markNeedsPaint();
    }
  }

  static bool _sameSegments(
    List<(String, Style)> a,
    List<(String, Style)> b,
  ) {
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

  List<String>? _glyphs;
  List<String>? get glyphs => _glyphs;
  set glyphs(List<String>? g) {
    if (g?.join('\n') != _glyphs?.join('\n')) {
      _glyphs = g;
      markNeedsLayout();
    }
  }

  String _glyph;
  String get glyph => _glyph;
  set glyph(String g) {
    if (g != _glyph) {
      _glyph = g;
      markNeedsPaint();
    }
  }

  String? _number;
  String? get number => _number;
  set number(String? n) {
    if (n != _number) {
      _number = n;
      markNeedsLayout();
    }
  }

  int? _shift;
  int? get shift => _shift;
  set shift(int? s) {
    if (s != _shift) {
      _shift = s;
      _paragraph.wrap = _paragraphWrap;
      markNeedsLayout();
    }
  }

  TextWrap _wrap;
  TextWrap get wrap => _wrap;
  set wrap(TextWrap w) {
    if (w != _wrap) {
      _wrap = w;
      _paragraph.wrap = _paragraphWrap;
      markNeedsLayout();
    }
  }

  TextWrap get _paragraphWrap => _shift == null ? _wrap : TextWrap.none;

  RenderParagraph get _paragraph => child! as RenderParagraph;

  // what is selected of it, offsets in its segments, and in what style
  (int, int)? _selected;
  Style? _selectedStyle;

  /// The columns of the code in view, as last laid out.
  int? codeWidth;

  /// Asks the [_RenderCodeSelection] above what is selected of the line,
  /// and paints it so when that changed.
  void reselect() {
    _RenderCodeSelection? view;
    for (var p = parent; p != null; p = p.parent) {
      if (p is _RenderCodeSelection) {
        view = p;
        break;
      }
    }
    final part = view?.selectedOf(index);
    final at = offsets;
    final selected = part == null || at == null
        ? part
        : (at[part.$1], at[part.$2]);
    final style = selected == null ? null : view!.selectionStyle;
    if (selected == _selected && style == _selectedStyle) {
      return;
    }
    _selected = selected;
    _selectedStyle = style;
    _paragraph.spans = _pens();
  }

  /// The segments as (text, pen), each split where the selection starts
  /// and ends, the part selected in its style merged onto theirs.
  List<(String, Pen)> _pens() {
    final segments = _styles.segments;
    final selected = _selected;
    final style = _selectedStyle;
    if (selected == null || style == null) {
      return [for (final (text, s) in segments) (text, s.pen)];
    }
    final (start, end) = selected;
    final out = <(String, Pen)>[];
    var at = 0;
    for (final (text, s) in segments) {
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

  /// The range of the line's text the cell [x], [y] (in its own
  /// coordinates) stands for: in the gutter where the line starts; null
  /// right of its code, where the next line starts.
  (int, int)? rangeAt(int x, int y) {
    final left = _gutter;
    if (x < left) {
      return (0, 0);
    }
    final p = _paragraph;
    final (s, e) = p.textRangeAt(x - p.parentData.dx, y - p.parentData.dy);
    final at = offsets;
    final length = at == null
        ? _styles.segments.fold(0, (n, s) => n + s.$1.length)
        : at.last;
    if (s >= length) {
      return null;
    }
    if (at == null) {
      return (s, e);
    }
    // the code unit whose expansion holds each end
    var a = 0;
    while (a + 1 < at.length && at[a + 1] <= s) {
      a++;
    }
    var b = a;
    while (b < at.length - 1 && at[b] < e) {
      b++;
    }
    return (a, b);
  }

  /// The columns the widest glyph takes as the owner's segmenter measures
  /// it, one at least.
  int get _signWidth {
    final glyphs = _glyphs;
    if (glyphs == null) {
      return 0;
    }
    final segmenter = owner?.segmenter;
    var widest = 1;
    for (final glyph in glyphs) {
      final w = segmenter == null
          ? stringWidth(glyph)
          : stringWidth(
              glyph,
              mode: segmenter.mode,
              ambiguousWidth: segmenter.ambiguousWidth,
            );
      widest = w > widest ? w : widest;
    }
    return widest;
  }

  /// The columns before the code: the signs and the numbers, a blank after
  /// each.
  int get _gutter =>
      (_glyphs == null ? 0 : _signWidth + 1) +
      (_number == null ? 0 : _number!.length + 1);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('index', index)
      ..add('shift', _shift, defaultValue: null)
      ..add('selected', _selected, defaultValue: null);
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      _gutter + _paragraph.getMinIntrinsicWidth(height);

  @override
  int computeMaxIntrinsicWidth(int height) =>
      _gutter + _paragraph.getMaxIntrinsicWidth(height);

  @override
  int computeMinIntrinsicHeight(int width) => math.max(
    1,
    _paragraph.getMinIntrinsicHeight(math.max(0, width - _gutter)),
  );

  @override
  int computeMaxIntrinsicHeight(int width) => math.max(
    1,
    _paragraph.getMaxIntrinsicHeight(math.max(0, width - _gutter)),
  );

  @override
  void performLayout(BoxConstraints c) {
    reselect();
    final gutter = _gutter;
    final p = _paragraph;
    if (_shift == null) {
      final room = c.maxW < BoxConstraints.unbounded
          ? math.max(0, c.maxW - gutter)
          : BoxConstraints.unbounded;
      p.layout(
        BoxConstraints(0, room, 0, BoxConstraints.unbounded),
        parentUsesSize: true,
      );
    } else {
      p.layout(
        const BoxConstraints(
          0,
          BoxConstraints.unbounded,
          0,
          BoxConstraints.unbounded,
        ),
        parentUsesSize: true,
      );
    }
    width = c.constrainW(gutter + p.width);
    height = c.constrainH(math.max(1, p.height));
    codeWidth = math.max(0, width - gutter);
    p.parentData
      ..dx = gutter - (_shift ?? 0)
      ..dy = 0;
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas
      ..save()
      ..clipRect(0, 0, width, height);
    final styles = canvas.styles;
    if (_styles.fill case final fill?) {
      canvas.fill(0, 0, width, height, fill.penIn(styles));
    }
    if (_glyphs != null && _glyph.isNotEmpty) {
      canvas.text(0, 0, _glyph, _styles.sign.penIn(styles));
    }
    if (_number case final number?) {
      final x = _glyphs == null ? 0 : _signWidth + 1;
      canvas.text(x, 0, number, _styles.number.penIn(styles));
    }
    final gutter = _gutter;
    canvas
      ..save()
      ..clipRect(gutter, 0, width - gutter, height);
    paintChild(ctx, _paragraph);
    canvas
      ..restore()
      ..restore();
  }
}
