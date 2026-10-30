/// A diff as a widget: [DiffView], in a [DiffLayout].
///
/// @docImport 'package:twk/twk.dart';
library;

import 'dart:math' as math;

import 'package:twk/twk.dart';

import '../highlight/highlight.dart';
import 'diff_theme.dart';
import 'model.dart';
import 'words.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// late String output;

/// How a [DiffView] puts the two sides of a diff.
enum DiffLayout {
  /// One column: a row for each line in the order of the diff, with both
  /// its numbers.
  unified,

  /// Two columns, the old side on the left and the new on the right: a
  /// line of context on both, each line removed beside the line added
  /// that pairs with it, if any, and the other side blank where none does.
  sideBySide,
}

/// [diff] in a list of rows that scrolls, laid out as [layout] says.
///
/// A gutter before each line shows its number and a sign: `-` for a line
/// removed, `+` for one added. Its code is highlighted in [language], by
/// default the one the extension of the file's path names
/// ([languageNamed]), in the styles of the [SyntaxTheme] at its place;
/// each side is lexed as one source, from its first line down as far as
/// the rows shown need: the whole file where the diff was found from it
/// ([FileDiff.oldLines]), its lines in the hunks otherwise. In a run of
/// lines removed and added, the first removed and the first added are a
/// pair, the second and the second, and so on; the words a pair changed
/// ([changedWords]) are marked over the syntax colors. A file with a path
/// starts with a row that names it (`old → new` where it was renamed),
/// and the unchanged lines a diff leaves out before a hunk, between hunks
/// and, where it knows the whole file, after the last, are a row that
/// counts them, with the section the hunk after it names. A tab moves to
/// the next multiple of [tabWidth] columns; a line wider than its column
/// is cut off.
///
/// Only the rows in view and a few past them are built, as a [ListView]
/// builds its items: past that, a diff of any length costs a list of its
/// rows, made again when [diff], [layout] or [language] changes, and the
/// lexing of each side down to the rows shown. It takes all the room it is
/// given, which must be bounded, in the styles of [theme], by default
/// [DiffTheme.from] the [Theme]; [controller], [focusNode] and [autofocus]
/// are the list's.
///
/// The output of `git diff --color`, side by side, scrolled with the keys
/// once focused:
///
/// ```dart
/// DiffView(
///   Diff.parse(stripAnsi(output)),
///   layout: DiffLayout.sideBySide,
///   autofocus: true,
/// )
/// ```
///
/// See also:
///
///  * [Diff.between], the diff of two texts the app holds.
///  * [CodeView], code without a diff, in the same syntax colors.
final class DiffView extends StatefulWidget {
  /// Shows [diff] in [layout], unified by default, its code in [language]
  /// or that of each file's path, its tabs [tabWidth] columns apart, 4 by
  /// default, in [theme] or that of the [Theme].
  const DiffView(
    this.diff, {
    super.key,
    this.layout = DiffLayout.unified,
    this.language,
    this.tabWidth = 4,
    this.theme,
    this.controller,
    this.focusNode,
    this.autofocus = false,
  }) : assert(tabWidth > 0, 'tabWidth < 1');

  /// The files, hunks and lines shown; another diff makes the rows again.
  final Diff diff;

  /// Whether the two sides are in one column or side by side.
  final DiffLayout layout;

  /// The language of the code of every file; null for that of each file's
  /// path.
  final Language? language;

  /// Columns between tab stops.
  final int tabWidth;

  /// The styles; null for [DiffTheme.from] the [Theme].
  final DiffTheme? theme;

  /// See [ListView.controller].
  final ScrollController? controller;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  @override
  State<DiffView> createState() => _DiffViewState();
}

final class _DiffViewState extends State<DiffView> {
  /// The rows of the diff in its layout.
  var _rows = <_Row>[];

  /// The digits of the largest line number.
  var _digits = 1;

  @override
  void initState() {
    super.initState();
    _layOut();
  }

  @override
  void didUpdateWidget(DiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.diff, oldWidget.diff) ||
        widget.layout != oldWidget.layout ||
        !identical(widget.language, oldWidget.language)) {
      _layOut();
    }
  }

  void _layOut() {
    final sideBySide = widget.layout == DiffLayout.sideBySide;
    final rows = <_Row>[];
    var largest = 1;
    for (final file in widget.diff.files) {
      final language = widget.language ?? _languageOf(file.path);
      final oldWhole = file.oldLines;
      final newWhole = file.newLines;
      final old = _Side(language, oldWhole ?? []);
      final now = _Side(language, newWhole ?? []);
      // where a line is in the lines of its side
      int oldIndex(DiffLine line) {
        if (oldWhole != null) {
          return line.oldNumber! - 1;
        }
        old.lines.add(line.text);
        return old.lines.length - 1;
      }

      int newIndex(DiffLine line) {
        if (newWhole != null) {
          return line.newNumber! - 1;
        }
        now.lines.add(line.text);
        return now.lines.length - 1;
      }

      if (file.path != null) {
        rows.add(_FileRow(file));
      }
      // the numbers of the lines after those shown so far
      var nextOld = 1;
      var nextNew = 1;
      for (final hunk in file.hunks) {
        final lines = hunk.lines;
        if (lines.isEmpty) {
          continue;
        }
        final first = lines.first;
        final gap = switch (first.oldNumber) {
          final number? => number - nextOld,
          null => first.newNumber! - nextNew,
        };
        if (gap > 0) {
          rows.add(_GapRow(gap, hunk.section));
        }
        nextOld += gap;
        nextNew += gap;
        for (var k = 0; k < lines.length;) {
          final line = lines[k];
          if (line.kind == DiffLineKind.context) {
            final o = oldIndex(line);
            final n = newIndex(line);
            rows.add(
              sideBySide
                  ? _PairRow(_Half(line, old, o), _Half(line, now, n), null)
                  : _LineRow(_Half(line, now, n), null),
            );
            k++;
            continue;
          }
          // a run of lines removed and added, each removed line paired
          // with the added line in its place
          final removed = <_Half>[];
          final added = <_Half>[];
          final unified = <_Half>[];
          for (
            ;
            k < lines.length && lines[k].kind != DiffLineKind.context;
            k++
          ) {
            final line = lines[k];
            final half = line.kind == DiffLineKind.removed
                ? _Half(line, old, oldIndex(line))
                : _Half(line, now, newIndex(line));
            (line.kind == DiffLineKind.removed ? removed : added).add(half);
            unified.add(half);
          }
          final pairs = [
            for (var i = 0; i < math.min(removed.length, added.length); i++)
              _Pair(removed[i].line.text, added[i].line.text),
          ];
          if (sideBySide) {
            for (var i = 0; i < math.max(removed.length, added.length); i++) {
              rows.add(
                _PairRow(
                  i < removed.length ? removed[i] : null,
                  i < added.length ? added[i] : null,
                  i < pairs.length ? pairs[i] : null,
                ),
              );
            }
          } else {
            // the how-manyth line removed or added each is
            var r = 0;
            var a = 0;
            for (final half in unified) {
              final i = half.line.kind == DiffLineKind.removed ? r++ : a++;
              rows.add(_LineRow(half, i < pairs.length ? pairs[i] : null));
            }
          }
        }
        for (final line in lines) {
          if (line.oldNumber case final number?) {
            nextOld = number + 1;
            largest = math.max(largest, number);
          }
          if (line.newNumber case final number?) {
            nextNew = number + 1;
            largest = math.max(largest, number);
          }
        }
      }
      if (oldWhole != null && oldWhole.length >= nextOld) {
        rows.add(_GapRow(oldWhole.length + 1 - nextOld, ''));
      }
    }
    _rows = rows;
    _digits = '$largest'.length;
  }

  @override
  Widget build(BuildContext context) {
    final paint = _Paint(
      theme: widget.theme ?? DiffTheme.from(Theme.of(context)),
      syntax: SyntaxTheme.of(context),
      digits: _digits,
      tabWidth: widget.tabWidth,
      sideBySide: widget.layout == DiffLayout.sideBySide,
    );
    final rows = _rows;
    return ListView.builder(
      itemCount: rows.length,
      itemExtent: 1,
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      itemBuilder: (context, index) => rows[index].build(paint),
    );
  }
}

/// The language the extension of [path] names; plain text without one.
Language _languageOf(String? path) {
  final name = path?.substring(path.lastIndexOf('/') + 1) ?? '';
  final dot = name.lastIndexOf('.');
  return dot < 0 ? Language.plain : languageNamed(name.substring(dot + 1));
}

/// A side of a file: its [lines] in [language], lexed from the first down
/// as far as [tokens] has been asked for, and a few more.
final class _Side {
  _Side(this.language, this.lines);

  final Language language;
  final List<String> lines;

  /// How many lines past the one asked for are lexed with it.
  static const _ahead = 256;

  /// [lines] lexed so far: the first [_lexed] of them.
  late final _code = Highlighter(language);
  var _lexed = 0;

  /// The tokens of line [index].
  List<Token> tokens(int index) {
    if (index >= _lexed) {
      final to = math.min(lines.length, index + _ahead);
      // the first lines take the place of the empty line it starts with
      _code.replaceLines(
        _lexed,
        _lexed == 0 ? 1 : _lexed,
        lines.sublist(_lexed, to),
      );
      _lexed = to;
    }
    return _code.tokens(index);
  }
}

/// A line removed and the line added that pairs with it, and the [words]
/// they changed, found when first asked for.
final class _Pair {
  _Pair(this.before, this.after);

  final String before;
  final String after;

  late final (List<(int, int)>, List<(int, int)>)? words = changedWords(
    before,
    after,
  );
}

/// A line as one side shows it: [line], line [index] of [side].
final class _Half {
  _Half(this.line, this.side, this.index);

  final DiffLine line;
  final _Side side;
  final int index;
}

/// What the rows are built with.
final class _Paint {
  _Paint({
    required this.theme,
    required this.syntax,
    required this.digits,
    required this.tabWidth,
    required this.sideBySide,
  });

  final DiffTheme theme;
  final SyntaxTheme syntax;
  final int digits;
  final int tabWidth;
  final bool sideBySide;

  /// The blanks before the `⋯` of a row of lines left out, so that it
  /// stands where the signs do.
  int get _indent => sideBySide ? digits + 1 : 2 * digits + 2;

  /// [half] after [gutter], on the background of its kind, the words
  /// [pair] says it changed marked.
  Widget line(_Half half, List<Span> gutter, _Pair? pair) {
    final removed = half.line.kind == DiffLineKind.removed;
    final words = switch (pair?.words) {
      null => null,
      (final before, final after) => removed ? before : after,
    };
    final (style, sign, signStyle, wordStyle) = switch (half.line.kind) {
      DiffLineKind.context => (null, ' ', theme.lineNumbers, theme.lineNumbers),
      DiffLineKind.removed => (
        theme.removed,
        '-',
        theme.removedSign,
        theme.removedWords,
      ),
      DiffLineKind.added => (
        theme.added,
        '+',
        theme.addedSign,
        theme.addedWords,
      ),
    };
    return _row(style, [
      ...gutter,
      Span(sign, signStyle),
      const Span(' '),
      ..._code(half, words ?? const [], wordStyle),
    ]);
  }

  /// The number [number] right-aligned in the gutter, a blank after it.
  Span number(int? number) =>
      Span('${'${number ?? ''}'.padLeft(digits)} ', theme.lineNumbers);

  /// The tokens of [half] as spans in the styles of [syntax], those within
  /// [words] in [wordStyle] over them, each tab as the blanks up to the
  /// next tab stop.
  List<Span> _code(_Half half, List<(int, int)> words, Style wordStyle) {
    final spans = <Span>[];
    var at = 0;
    var w = 0;
    for (final token in half.side.tokens(half.index)) {
      final style = syntax.styleOf(token.kind);
      final text = token.text;
      for (var from = 0; from < text.length;) {
        while (w < words.length && words[w].$2 <= at + from) {
          w++;
        }
        final inWord = w < words.length && words[w].$1 <= at + from;
        final end = w < words.length
            ? math.min((inWord ? words[w].$2 : words[w].$1) - at, text.length)
            : text.length;
        spans.add(
          Span(
            text.substring(from, end),
            inWord ? style.merge(wordStyle) : style,
          ),
        );
        from = end;
      }
      at += text.length;
    }
    if (!half.line.text.contains('\t')) {
      return spans;
    }
    var column = 0;
    return [
      for (final span in spans)
        Span(
          span.text.split('\t').indexed.map((piece) {
            final (k, text) = piece;
            final blanks = k == 0 ? 0 : tabWidth - column % tabWidth;
            column += blanks + stringWidth(text);
            return '${' ' * blanks}$text';
          }).join(),
          span.style,
        ),
    ];
  }
}

/// [spans] on a line of their own, cut off at its end, in [style]: its
/// background fills the line, the rest of it is the text's; without a
/// style, on the line as it is.
Widget _row(Style? style, List<Span> spans) {
  if (style == null) {
    return Text.rich(spans, wrap: TextWrap.none);
  }
  return Box(
    style: style,
    child: Text.rich(
      spans,
      style: Style(
        fg: style.fg,
        fgAlpha: style.fgAlpha,
        underlineColor: style.underlineColor,
        attrs: style.attrs,
        attrsOff: style.attrsOff,
        link: style.link,
      ),
      wrap: TextWrap.none,
    ),
  );
}

/// A row of a [DiffView].
sealed class _Row {
  Widget build(_Paint paint);
}

/// The row that names [file].
final class _FileRow extends _Row {
  _FileRow(this.file);

  final FileDiff file;

  @override
  Widget build(_Paint paint) {
    final FileDiff(:oldPath, :newPath) = file;
    return _row(paint.theme.file, [
      Span(
        oldPath != null && newPath != null && oldPath != newPath
            ? '$oldPath → $newPath'
            : file.path!,
      ),
    ]);
  }
}

/// The row that stands for [count] unchanged lines left out before a hunk
/// in [section].
final class _GapRow extends _Row {
  _GapRow(this.count, this.section);

  final int count;
  final String section;

  @override
  Widget build(_Paint paint) => _row(paint.theme.collapsed, [
    Span(
      '${' ' * paint._indent}⋯ $count unchanged '
      '${count == 1 ? 'line' : 'lines'}'
      '${section.isEmpty ? '' : '  $section'}',
    ),
  ]);
}

/// A line of the unified layout: both its numbers, its sign and its code.
final class _LineRow extends _Row {
  _LineRow(this.half, this.pair);

  final _Half half;
  final _Pair? pair;

  @override
  Widget build(_Paint paint) => paint.line(half, [
    paint.number(half.line.oldNumber),
    paint.number(half.line.newNumber),
  ], pair);
}

/// A row of the side-by-side layout: [left] on the old side, [right] on
/// the new one, either blank when null.
final class _PairRow extends _Row {
  _PairRow(this.left, this.right, this.pair);

  final _Half? left;
  final _Half? right;
  final _Pair? pair;

  @override
  Widget build(_Paint paint) => Row(
    children: [
      Expanded(child: _half(paint, left, (line) => line.oldNumber)),
      Text('│', style: paint.theme.divider),
      Expanded(child: _half(paint, right, (line) => line.newNumber)),
    ],
  );

  Widget _half(_Paint paint, _Half? half, int? Function(DiffLine) number) =>
      half == null
      ? const SizedBox()
      : paint.line(half, [paint.number(number(half.line))], pair);
}
