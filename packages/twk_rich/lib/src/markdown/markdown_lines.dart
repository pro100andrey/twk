/// A Markdown document as lines of styled text: [renderMarkdown].
///
/// @docImport 'markdown_view.dart';
library;

import 'dart:math' as math;

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show TextSegmenter, graphemeBoundaries;

import 'inline_spans.dart';
import 'markdown_theme.dart';
import 'markdown_view.dart';
import 'nodes.dart';
import 'stream.dart';
import 'wrap_spans.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// late String readme;
// late MarkdownTheme theme;

/// The Markdown document [text] as lines of styled text, each wrapped to
/// [width] columns, in the styles of [theme]: for an app that draws the
/// lines itself, in a panel it cuts and colours by the cell, where a
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
/// is not highlighted, only in the code block's style, with its tabs 4
/// columns apart and its lines broken between graphemes.
///
/// Where it differs from the widgets: the rule under a table's header
/// ends with its last column, not at the view's edge, and a column too
/// wide for [width] is shrunk by its widest cells rather than clipped.
///
/// ```dart
/// final lines = renderMarkdown(readme, 40, theme);
/// ```
List<List<Span>> renderMarkdown(
  String text,
  int width,
  MarkdownTheme theme,
) {
  assert(width > 0, 'width < 1');
  final stream = MarkdownStream(text);
  return _Renderer(stream.definitions, theme)._blocks(
    stream.blocks,
    width,
    1,
    0,
    const Style(),
  );
}

final _segmenter = TextSegmenter();

int _widthOf(String text) => _segmenter.width(text);

/// The lines of one document.
final class _Renderer {
  _Renderer(this.definitions, this.theme);

  final Map<String, MdDefinition> definitions;
  final MarkdownTheme theme;

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
        MdCodeBlock(:final code) => _code(code, width, base),
        MdThematicBreak() => [
          [Span('─' * width, theme.rule)],
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
    final lines = _blocks(
      children,
      math.max(1, width - 2),
      1,
      depth,
      base.merge(theme.quote),
    );
    final bar = Span('│', theme.quoteBar);
    return [
      for (final line in lines)
        [bar, if (line.isNotEmpty) const Span(' '), ...line],
    ];
  }

  List<List<Span>> _list(MdList list, int width, int depth, Style base) {
    final (:markers, :column) = listMarkers(list, depth);
    final columnWidth = column.fold(0, (w, m) => math.max(w, _widthOf(m)));
    final ordered = list.start != null;
    final gap = list.tight ? 0 : 1;
    final inner = math.max(1, width - columnWidth - 1);
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
      final marker = markers[k];
      final pad = columnWidth - _widthOf(marker);
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
  /// code block's style.
  List<List<Span>> _code(String code, int width, Style base) {
    final style = base.merge(theme.codeBlock);
    final rows = code.split('\n');
    if (rows.length > 1 && rows.last.isEmpty) {
      rows.removeLast();
    }
    final inner = math.max(1, width - 2);
    final out = <List<Span>>[];
    for (final row in rows) {
      final text = _expandTabs(row, 4);
      final pieces = _wrap([Span(text)], inner, const Style(), grapheme: true);
      for (final piece in pieces.isEmpty ? [const <Span>[]] : pieces) {
        final shown = piece.map((span) => span.text).join();
        final fill = width - 1 - _widthOf(shown);
        out.add([Span(' $shown${' ' * math.max(0, fill)}', style)]);
      }
    }
    return out;
  }

  static String _expandTabs(String row, int tabWidth) {
    if (!row.contains('\t')) {
      return row;
    }
    final out = StringBuffer();
    var column = 0;
    for (final (from, to) in graphemeBoundaries(row)) {
      final cluster = row.substring(from, to);
      if (cluster == '\t') {
        final n = tabWidth - column % tabWidth;
        out.write(' ' * n);
        column += n;
      } else {
        out.write(cluster);
        column += _widthOf(cluster);
      }
    }
    return out.toString();
  }

  List<List<Span>> _table(MdTable table, int width, Style base) {
    final columns = table.align.length;
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
        .fold(0, (w, line) => math.max(w, _widthOf(line)));
    for (var j = 0; j < columns; j++) {
      widths[j] = math.max(widths[j], widest(header[j]));
      for (final row in body) {
        widths[j] = math.max(widths[j], widest(row[j]));
      }
    }
    final gaps = 3 * (columns - 1);
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
    final border = Span('│', theme.tableBorder);
    List<List<Span>> row(List<List<Span>> cells, Style style) {
      final wrapped = [
        for (var j = 0; j < columns; j++) _wrap(cells[j], widths[j], style),
      ];
      final height = wrapped.fold(0, (h, c) => math.max(h, c.length));
      return [
        for (var l = 0; l < height; l++)
          _trimmed([
            for (var j = 0; j < columns; j++) ...[
              if (j > 0) ...[const Span(' '), border, const Span(' ')],
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
              '${j > 0 ? '─┼─' : ''}${'─' * widths[j]}',
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
    final pad = cell - line.fold<int>(0, (w, span) => w + _widthOf(span.text));
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
  /// own style.
  List<List<Span>> _wrap(
    List<Span> spans,
    int width,
    Style base, {
    bool grapheme = false,
  }) => wrapSpans(spans, width, base, grapheme: grapheme);
}
