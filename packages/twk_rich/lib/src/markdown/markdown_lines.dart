/// A Markdown document as lines of styled text: [renderMarkdown].
///
/// @docImport 'markdown_view.dart';
library;

import 'dart:math' as math;

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show TextSegmenter, TextWrap, breakLines, graphemeBoundaries;

import '../highlight/highlight.dart';
import 'inline_spans.dart';
import 'markdown_theme.dart';
import 'markdown_view.dart';
import 'nodes.dart';
import 'stream.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// late String readme;
// late MarkdownTheme theme;

/// Renders the Markdown document [text] as lines of styled text, each
/// wrapped to [width] columns, in the styles of [theme]: for an app that draws
/// the lines itself, in a panel it cuts and colours by the cell, where a
/// [MarkdownView] (which lays out its widgets itself) cannot go. A line is
/// its spans; its cells are the columns of its text, with no cell beyond
/// [width], and no trailing spaces except on a line of code, which a fill
/// of the code block's style takes to [width]. An empty line, between
/// blocks, has no spans.
///
/// The document looks as [MarkdownView] shows it and is parsed, styled and
/// worded the same ([parseMarkdown], [MarkdownTheme], the same lists'
/// markers and quotes' bars and tables' lines): a paragraph or a heading
/// wraps by words (CJK text between its characters), a long word between
/// graphemes; a list item has its marker before its first line and its
/// blocks under it; a block quote has its bar down its left side; a table
/// has its columns as wide as their text, shrunk to fit [width] when they
/// are not. The styles of the spans are the whole of each: the quote's
/// style, a heading's and an emphasis's are merged in already. A link and
/// an image are hyperlinks (`Style.link`) where they lead to the web or an
/// address, as in a [MarkdownView] by default; they are not told apart
/// otherwise, as a panel of one's own has its own pointer. A block of code
/// is highlighted in the language its info string names, in the styles of
/// [MarkdownTheme.syntax], over the code block's style, with its tabs 4
/// columns apart and its lines broken between graphemes. Lines break as
/// the core breaks them ([breakLines]). The marks (the bullets, a task's
/// box, the rule, the quote's bar, the table's lines) are those of [glyphs].
///
/// Where it differs from the widgets: the rule under a table's header
/// ends with its last column, not at the view's edge, and a column too
/// wide for [width] is shrunk by its widest cells rather than clipped. At a
/// [width] too narrow for its decoration, the decoration gives way and the
/// text keeps its column: a table's separators shrink to a line alone, and
/// then its last columns are left out; a quote's bar loses its space, then
/// itself; a list loses its markers and indent; a block of code its padding.
/// Only a character wider than [width] itself is beyond it.
///
/// Widths and breaks are those of [segmenter], the terminal's
/// (`segmenterOf(context)`): a plain `TextSegmenter()` counts ambiguous-wide
/// letters one column, and lines come out wider than [width] on a terminal
/// that draws them in two.
///
/// The marks (bullets, task boxes, rules, a quote's bar) are those of
/// [glyphs], `Glyphs.unicode` unless given: it has no context to read a
/// theme from, so a widget passes `Theme.of(context).glyphs`, as
/// `MarkdownView` takes its own.
///
/// ```dart
/// final lines = renderMarkdown(TextSegmenter(), readme, 40, theme);
/// ```
List<List<Span>> renderMarkdown(
  TextSegmenter segmenter,
  String text,
  int width,
  MarkdownTheme theme, {
  Glyphs glyphs = Glyphs.unicode,
}) {
  assert(width > 0, 'width < 1');
  final stream = MarkdownStream(text);
  return _Renderer(segmenter, stream.definitions, theme, glyphs)._blocks(
    stream.blocks,
    width,
    1,
    0,
    const Style(),
  );
}

/// The lines of one document.
final class _Renderer {
  _Renderer(this.segmenter, this.definitions, this.theme, this.glyphs);

  final TextSegmenter segmenter;

  final Map<String, MdDefinition> definitions;
  final MarkdownTheme theme;
  final Glyphs glyphs;

  // a piece of the set's lines
  String _piece({
    bool up = false,
    bool right = false,
    bool down = false,
    bool left = false,
  }) => String.fromCharCode(
    glyphs.lines.glyph(up: up, right: right, down: down, left: left),
  );

  List<Span> _spans(List<MdInline> inlines) => inlineSpans(
    inlines,
    definitions,
    theme,
    hyperlinks: true,
    schemes: MarkdownView.webSchemes,
  ).spans;

  /// [blocks] one under another, [gap] blank lines apart, lists in them
  /// [depth] lists deep, in [width] columns, in the text style [base].
  List<List<Span>> _blocks(
    List<MdBlock> blocks,
    int width,
    int gap,
    int depth,
    Style base,
  ) {
    final out = <List<Span>>[];
    for (final block in blocks) {
      if (out.isNotEmpty) {
        for (var k = 0; k < gap; k++) {
          out.add(const []);
        }
      }
      out.addAll(_block(block, width, depth, base));
    }
    return out;
  }

  List<List<Span>> _block(MdBlock block, int width, int depth, Style base) =>
      switch (block) {
        MdParagraph(:final children) => _wrap(_spans(children), width, base),
        MdHeading(:final children, :final level) => _wrap(
          _spans(children),
          width,
          base.merge(theme.heading(level)),
        ),
        MdCodeBlock(:final code, :final language) => _code(
          code,
          languageNamed(language),
          width,
          base,
        ),
        MdThematicBreak() => [
          [Span(_piece(left: true, right: true) * width, theme.rule)],
        ],
        MdBlockQuote(:final children) => _quote(children, width, depth, base),
        final MdList list => _list(list, width, depth, base),
        final MdTable table => _table(table, width, base),
      };

  List<List<Span>> _quote(
    List<MdBlock> children,
    int width,
    int depth,
    Style base,
  ) {
    // the bar and the space after it, as many columns of them as leave one
    // for the text: at 2 the bar alone, at 1 neither
    final gutter = math.min(2, width - 1);
    final lines = _blocks(
      children,
      width - gutter,
      1,
      depth,
      base.merge(theme.quote),
    );
    if (gutter == 0) {
      return lines;
    }
    final bar = Span(glyphs.separator, theme.quoteBar);
    return [
      for (final line in lines)
        [bar, if (line.isNotEmpty && gutter == 2) const Span(' '), ...line],
    ];
  }

  List<List<Span>> _list(MdList list, int width, int depth, Style base) {
    final (:markers, :column) = listMarkers(list, depth, glyphs);
    final columnWidth = column.fold(
      0,
      (w, m) => math.max(w, segmenter.width(m)),
    );
    final ordered = list.start != null;
    final gap = list.tight ? 0 : 1;
    // no marker column where it leaves no column for the text
    final prefix = columnWidth + 1 < width ? columnWidth + 1 : 0;
    final inner = width - prefix;
    final markerStyle = base.merge(theme.marker);
    final out = <List<Span>>[];
    for (var k = 0; k < list.items.length; k++) {
      if (k > 0) {
        for (var g = 0; g < gap; g++) {
          out.add(const []);
        }
      }
      final lines = _blocks(
        list.items[k].children,
        inner,
        gap,
        depth + 1,
        base,
      );
      if (prefix == 0) {
        out.addAll(lines);
        continue;
      }
      final marker = markers[k];
      final pad = columnWidth - segmenter.width(marker);
      final first = [
        if (ordered && pad > 0) Span(' ' * pad),
        Span(marker, markerStyle),
        if (!ordered && pad > 0) Span(' ' * pad),
        const Span(' '),
      ];
      final indent = Span(' ' * (columnWidth + 1));
      if (lines.isEmpty) {
        out.add(first.sublist(0, first.length - 1));
        continue;
      }
      for (var l = 0; l < lines.length; l++) {
        final line = lines[l];
        out.add(
          l == 0
              ? [...first, ...line]
              : line.isEmpty
              ? line
              : [indent, ...line],
        );
      }
    }
    return out;
  }

  /// The lines of [code], a cell in from either side on the fill of the
  /// code block's style, its tokens in [language] in the styles of the
  /// theme's [MarkdownTheme.syntax].
  List<List<Span>> _code(
    String code,
    Language language,
    int width,
    Style base,
  ) {
    final style = base.merge(theme.codeBlock);
    final source = Highlighter(language, code);
    var rows = source.lineCount;
    if (rows > 1 && source.line(rows - 1).isEmpty) {
      rows--;
    }
    // a cell in from either side where there is room for it: from the left
    // from 2 columns, from the right from 3
    final lead = width >= 2 ? 1 : 0;
    final inner = width - lead - (width >= 3 ? 1 : 0);
    final out = <List<Span>>[];
    for (var r = 0; r < rows; r++) {
      var column = 0;
      final spans = <Span>[];
      for (final token in source.tokens(r)) {
        final (text, next) = _expandTabs(token.text, 4, column);
        column = next;
        spans.add(Span(text, theme.syntax.styleOf(token.kind)));
      }
      for (final piece in _wrap(spans, inner, style, grapheme: true)) {
        final shown = piece.fold<int>(0, (w, s) => w + segmenter.width(s.text));
        final fill = width - lead - shown;
        out.add(
          _merged([
            if (lead > 0) Span(' ', style),
            ...piece,
            Span(' ' * math.max(0, fill), style),
          ]),
        );
      }
    }
    return out;
  }

  /// [spans] with adjacent ones of one style made one, and none empty.
  static List<Span> _merged(List<Span> spans) {
    final out = <Span>[];
    for (final span in spans) {
      if (span.text.isEmpty) {
        continue;
      }
      if (out.isNotEmpty && out.last.style == span.style) {
        out.last = Span(out.last.text + span.text, span.style);
      } else {
        out.add(span);
      }
    }
    return out;
  }

  /// [text] with its tabs spaces up to the next multiple of [tabWidth]
  /// columns, [from0] being the column it starts at; and the column it ends at.
  (String, int) _expandTabs(String text, int tabWidth, int from0) {
    var column = from0;
    if (!text.contains('\t')) {
      return (text, column + segmenter.width(text));
    }
    final out = StringBuffer();
    for (final (from, to) in graphemeBoundaries(text)) {
      final cluster = text.substring(from, to);
      if (cluster == '\t') {
        final n = tabWidth - column % tabWidth;
        out.write(' ' * n);
        column += n;
      } else {
        out.write(cluster);
        column += segmenter.width(cluster);
      }
    }
    return (out.toString(), column);
  }

  List<List<Span>> _table(MdTable table, int width, Style base) {
    // the columns shown: all, unless even one cell wide each they do not fit
    // with their separators, which are then a line alone, and then the first
    // that do
    final all = table.align.length;
    final sep = all + 3 * (all - 1) <= width ? 3 : 1;
    final columns = sep == 3 ? all : math.min(all, (width + 1) ~/ 2);
    final headerStyle = base.merge(theme.tableHeader);
    final header = [
      for (var j = 0; j < columns; j++)
        [
          Span(
            _spans(table.header[j]).map((span) => span.text).join(),
            headerStyle,
          ),
        ],
    ];
    final body = [
      for (final row in table.rows)
        [for (var j = 0; j < columns; j++) _spans(row[j])],
    ];
    // the columns: as wide as the widest text, the widest shrunk by one
    // until all fit
    final widths = List.filled(columns, 1);
    int widest(List<Span> cell) => cell
        .map((span) => span.text)
        .join()
        .split('\n')
        .fold(0, (w, line) => math.max(w, segmenter.width(line)));
    for (var j = 0; j < columns; j++) {
      widths[j] = math.max(widths[j], widest(header[j]));
      for (final row in body) {
        widths[j] = math.max(widths[j], widest(row[j]));
      }
    }
    final gaps = sep * (columns - 1);
    while (widths.fold(0, (a, b) => a + b) + gaps > width) {
      var at = 0;
      for (var j = 1; j < columns; j++) {
        if (widths[j] > widths[at]) {
          at = j;
        }
      }
      if (widths[at] == 1) {
        break;
      }
      widths[at]--;
    }
    final border = Span(glyphs.separator, theme.tableBorder);
    final across = _piece(left: true, right: true);
    final cross = _piece(up: true, right: true, down: true, left: true);
    List<List<Span>> row(List<List<Span>> cells, Style style) {
      final wrapped = [
        for (var j = 0; j < columns; j++) _wrap(cells[j], widths[j], style),
      ];
      final height = wrapped.fold(0, (h, c) => math.max(h, c.length));
      return [
        for (var l = 0; l < height; l++)
          _trimmed([
            for (var j = 0; j < columns; j++) ...[
              if (j > 0) ...[
                if (sep == 3) const Span(' '),
                border,
                if (sep == 3) const Span(' '),
              ],
              ..._aligned(
                l < wrapped[j].length ? wrapped[j][l] : const [],
                widths[j],
                table.align[j],
              ),
            ],
          ]),
      ];
    }

    return [
      ...row(header, headerStyle),
      [
        Span(
          [
            for (var j = 0; j < columns; j++)
              (j > 0 ? (sep == 3 ? '$across$cross$across' : cross) : '') +
                  across * widths[j],
          ].join(),
          theme.tableBorder,
        ),
      ],
      for (final cells in body) ...row(cells, base),
    ];
  }

  /// [line] without the spaces of no style that end it.
  static List<Span> _trimmed(List<Span> line) {
    var end = line.length;
    while (end > 0 &&
        line[end - 1].style == const Style() &&
        line[end - 1].text.trim().isEmpty) {
      end--;
    }
    return end == line.length ? line : line.sublist(0, end);
  }

  /// [line] in a cell [cell] columns wide.
  List<Span> _aligned(
    List<Span> line,
    int cell,
    MdAlign align,
  ) {
    final pad =
        cell - line.fold<int>(0, (w, span) => w + segmenter.width(span.text));
    final (before, after) = switch (align) {
      MdAlign.none || MdAlign.left => (0, pad),
      MdAlign.center => (pad ~/ 2, pad - pad ~/ 2),
      MdAlign.right => (pad, 0),
    };
    return [
      if (before > 0) Span(' ' * before),
      ...line,
      if (after > 0) Span(' ' * after),
    ];
  }

  /// [spans] wrapped to [width] columns, each in [base] merged under its
  /// own style, as a `Text` breaks lines ([breakLines]); between any two
  /// graphemes with [grapheme].
  List<List<Span>> _wrap(
    List<Span> spans,
    int width,
    Style base, {
    bool grapheme = false,
  }) {
    final text = spans.map((span) => span.text).join();
    final ranges = breakLines(
      segmenter,
      text,
      width,
      wrap: grapheme ? TextWrap.grapheme : TextWrap.word,
    );
    final lines = <List<Span>>[];
    var k = 0; // the span the cursor is in
    var at = 0; // where span k starts in [text]
    for (final (from, to) in ranges) {
      while (k < spans.length && at + spans[k].text.length <= from) {
        at += spans[k].text.length;
        k++;
      }
      final line = <Span>[];
      var i = k;
      var start = at;
      while (i < spans.length && start < to) {
        final piece = spans[i].text;
        final a = math.max(from, start) - start;
        final b = math.min(to, start + piece.length) - start;
        if (b > a) {
          line.add(Span(piece.substring(a, b), base.merge(spans[i].style)));
        }
        start += piece.length;
        i++;
      }
      lines.add(_merged(line));
    }
    return lines;
  }
}
