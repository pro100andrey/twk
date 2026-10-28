/// Terms and what they stand for, the values in a column of their own: a
/// [DescriptionList] of [DescriptionItem]s.
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Attr,
        BoxConstraints,
        ContainerParentDataMixin,
        ContainerRenderObjectMixin,
        PaintContext,
        ParentData,
        RenderObject;

import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../layout/child_list.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import '../text/widgets.dart';

/// A row of a [DescriptionList]: a [term] and its [value], or the heading
/// of a group of rows ([DescriptionItem.group]).
@immutable
final class DescriptionItem {
  /// [term] and the widget that shows its [value]: a `Badge`, a
  /// `ProgressBar`, a [Text.rich]. A screen reader reads the row as
  /// `term: ` followed by [semanticsValue]; where that is null, the
  /// default, by the text of [value] if it is a [Text], and otherwise reads
  /// the term on a line of its own, then what it reads of [value].
  const DescriptionItem(
    this.term,
    Widget this.value, {
    this.semanticsValue,
  });

  /// [term] and the text of [value], in [style] merged onto the list's
  /// [DescriptionList.valueStyle].
  DescriptionItem.text(this.term, String value, {Style? style})
    : value = Text(value, style: style ?? const Style()),
      semanticsValue = value;

  /// The heading of a group, [term] its title: the rows after it, up to
  /// the next heading, are a group whose values are aligned after its own
  /// longest term.
  const DescriptionItem.group(String title)
    : term = title,
      value = null,
      semanticsValue = null;

  /// What the value stands for; the title of a group's heading.
  final String term;

  /// What shows the value; null for a group's heading.
  final Widget? value;

  /// What a screen reader reads as the value; null for what it reads of
  /// [value].
  final String? semanticsValue;

  /// Whether it is the heading of a group ([DescriptionItem.group]).
  bool get isGroup => value == null;
}

/// Terms and their values, a row each, the values in a column of their
/// own: what `docker inspect`, `kubectl describe` or the header of `htop`
/// prints.
///
/// ```text
/// Status:       ● Running (healthy)
/// IP Address:   192.168.1.42
/// Memory Usage: 342 MB / 16 GB (2.1%)
/// ```
///
/// Each term is followed by [separator] (`:` by default; empty for none)
/// and placed in its column as [termAlign] says, on the left by default.
/// The values start [gap] columns after the term column, which is
/// [termWidth] wide, or where that is null, as wide as the longest term
/// of its group with its separator; but where the group's rows do not all
/// fit so, no wider than [maxTermFraction] of the list's width: a term
/// that does not fit in its column is cut off with `…`. A
/// [DescriptionItem.group] starts a group: its title in bold, a blank row
/// above it where rows come before. A value is laid out in the
/// room its column has, from the term column to the right edge: a text
/// that does not fit wraps under its own column, a hanging indent, and a
/// widget is given that width (a `ProgressBar` fills it). A row is as tall
/// as its value. Narrower than [stackBelowWidth], and than its widest row,
/// each value goes under its term, indented two columns: a list whose
/// rows all fit stays as it is.
///
/// The list is as wide as it may be, and as tall as its rows; where its
/// width is not bounded, as wide as its widest row. It paints only its
/// text and its values, over what is under it.
///
/// The styles, each merged over those before it: the theme's
/// [ThemeData.muted] and [termStyle] for a term; the theme's
/// [ThemeData.text], [valueStyle] and then the value's own for a value
/// ([DescriptionItem.text] takes one); the theme's text in bold for the
/// heading of a group.
///
/// Its terms and values are [Text]s: below a `SelectionArea` they are
/// selected and copied as any are, a row as its term and its value on
/// lines of their own. On plain output its rows are the lines written. A
/// screen reader reads a row as `term: value`, the whole term however
/// much of it is shown ([DescriptionItem.semanticsValue]), and the
/// heading of a group as a heading.
///
/// A service's state, its limits a group of their own:
///
/// ```dart
/// DescriptionList(
///   items: [
///     DescriptionItem.text('Status', 'Running'),
///     DescriptionItem.text('IP Address', '192.168.1.42'),
///     const DescriptionItem.group('Limits'),
///     DescriptionItem.text('CPU', '2 cores'),
///     const DescriptionItem('Memory', ProgressBar(value: 0.25)),
///   ],
/// )
/// ```
///
/// See also:
///
///  * `Table`, for rows of several columns under headers.
///  * `TreeView`, for keys whose values hold more of them.
final class DescriptionList extends StatelessWidget {
  /// Shows [items], a row each.
  const DescriptionList({
    required this.items,
    super.key,
    this.separator = ':',
    this.gap = 1,
    this.termAlign = TextAlign.left,
    this.termWidth,
    this.maxTermFraction = 0.4,
    this.stackBelowWidth = 30,
    this.termStyle,
    this.valueStyle,
  }) : assert(gap >= 0, 'a gap of 0 columns or more'),
       assert(termWidth == null || termWidth >= 0, 'a term width of 0 or more'),
       assert(
         maxTermFraction >= 0 && maxTermFraction <= 1,
         'a fraction from 0 to 1',
       );

  /// The rows, in order: pairs of a term and a value, and the headings
  /// that start groups.
  final List<DescriptionItem> items;

  /// What follows each term; empty for nothing.
  final String separator;

  /// The columns between the term column and the values.
  final int gap;

  /// Where a term is placed in its column.
  final TextAlign termAlign;

  /// The width of the term column, for every group; null, the default, for
  /// the longest term of each group, up to [maxTermFraction] of the width.
  final int? termWidth;

  /// The most of the list's width the term column takes where [termWidth]
  /// is null and the rows of its group do not all fit beside its longest
  /// term: a longer term is cut off.
  final double maxTermFraction;

  /// The width below which each value goes under its term, unless the
  /// rows all fit.
  final int stackBelowWidth;

  /// A term's style, over the theme's [ThemeData.muted]; null for that
  /// alone.
  final Style? termStyle;

  /// A value's style, over the theme's [ThemeData.text]; null for that
  /// alone.
  final Style? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final term = theme.muted.merge(termStyle ?? const Style());
    final value = theme.text.merge(valueStyle ?? const Style());
    final heading = theme.text.merge(const Style(attrs: Attr.bold));
    return _Rows(
      groups: [for (final item in items) item.isGroup],
      gap: gap,
      termWidth: termWidth,
      maxTermFraction: maxTermFraction,
      stackBelowWidth: stackBelowWidth,
      children: [
        for (final item in items)
          if (item.value case final shown?) ...[
            ExcludeSemantics(
              child: Text(
                '${item.term}$separator',
                style: term,
                wrap: TextWrap.none,
                overflow: TextOverflow.ellipsis,
                align: termAlign,
              ),
            ),
            _read(
              item.term,
              item.semanticsValue ?? _textOf(shown),
              DefaultTextStyle(style: value, child: shown),
            ),
          ] else
            Semantics(
              role: SemanticsRole.heading,
              child: Text(
                item.term,
                style: heading,
                wrap: TextWrap.none,
                overflow: TextOverflow.ellipsis,
              ),
            ),
      ],
    );
  }
}

/// [value] read as the value of [term]: as [spoken] where it is given,
/// after [term] otherwise.
Widget _read(String term, String? spoken, Widget value) => spoken == null
    ? Semantics(
        label: term,
        child: Semantics(child: value),
      )
    : Semantics(
        label: term,
        value: spoken,
        child: ExcludeSemantics(child: value),
      );

/// The text [value] shows where it is a [Text]; null otherwise.
String? _textOf(Widget value) => switch (value) {
  Text(:final String data) => data,
  Text(:final List<Span> spans) => spans.map((s) => s.text).join(),
  _ => null,
};

/// The rows of a [DescriptionList]: a child for each heading of a group
/// ([groups] true) and two for each pair, its term and its value.
final class _Rows extends MultiChildRenderObjectWidget {
  const _Rows({
    required this.groups,
    required this.gap,
    required this.termWidth,
    required this.maxTermFraction,
    required this.stackBelowWidth,
    super.children,
  });

  final List<bool> groups;
  final int gap;
  final int? termWidth;
  final double maxTermFraction;
  final int stackBelowWidth;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  _RenderRows createRenderObject(BuildContext context) => _RenderRows(
    groups: groups,
    gap: gap,
    termWidth: termWidth,
    maxTermFraction: maxTermFraction,
    stackBelowWidth: stackBelowWidth,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderRows renderObject) {
    renderObject
      ..groups = groups
      ..gap = gap
      ..termWidth = termWidth
      ..maxTermFraction = maxTermFraction
      ..stackBelowWidth = stackBelowWidth;
  }
}

final class _RowData extends ParentData with ContainerParentDataMixin {}

/// The columns a value goes in from the left edge where it is under its
/// term.
const _stackIndent = 2;

/// What a [DescriptionList] lays out and paints: for each item, the
/// heading of a group a child of its own ([groups] true), a pair two, its
/// term and its value, laid out as [DescriptionList] says.
final class _RenderRows extends RenderObject
    with ContainerRenderObjectMixin<_RowData> {
  _RenderRows({
    required this._groups,
    required this._gap,
    required this._termWidth,
    required this._maxTermFraction,
    required this._stackBelowWidth,
  });

  List<bool> _groups;
  List<bool> get groups => _groups;
  set groups(List<bool> g) {
    if (!sameList(g, _groups)) {
      _groups = g;
      markNeedsLayout();
    }
  }

  int _gap;
  int get gap => _gap;
  set gap(int g) {
    if (g != _gap) {
      _gap = g;
      markNeedsLayout();
    }
  }

  int? _termWidth;
  int? get termWidth => _termWidth;
  set termWidth(int? w) {
    if (w != _termWidth) {
      _termWidth = w;
      markNeedsLayout();
    }
  }

  double _maxTermFraction;
  double get maxTermFraction => _maxTermFraction;
  set maxTermFraction(double f) {
    if (f != _maxTermFraction) {
      _maxTermFraction = f;
      markNeedsLayout();
    }
  }

  int _stackBelowWidth;
  int get stackBelowWidth => _stackBelowWidth;
  set stackBelowWidth(int w) {
    if (w != _stackBelowWidth) {
      _stackBelowWidth = w;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _RowData) {
      child.parentData = _RowData();
    }
  }

  /// The children, in order.
  List<RenderObject> get _children => [
    for (var c = firstChild; c != null; c = childAfter(c)) c,
  ];

  /// The width of the term column of each item at [width] columns (0 for
  /// a heading): [termWidth], or the widest term of its group, no wider
  /// than [maxTermFraction] of [width] where the group's rows do not all
  /// fit beside it; at most what leaves a value a column.
  List<int> _columns(List<RenderObject> children, int width) {
    const unbounded = BoxConstraints.unbounded;
    final bounded = width < unbounded;
    final most = bounded ? (width * _maxTermFraction).floor() : width;
    final columns = List.filled(_groups.length, 0);
    var start = 0;
    var longest = 0;
    var widest = 0;
    void group(int end) {
      var column =
          _termWidth ??
          (longest < most || longest + _gap + widest <= width ? longest : most);
      if (bounded) {
        final room = width - _gap - 1;
        column = column < room ? column : (room > 0 ? room : 0);
      }
      for (var i = start; i < end; i++) {
        if (!_groups[i]) {
          columns[i] = column;
        }
      }
    }

    var k = 0;
    for (var i = 0; i < _groups.length; i++) {
      if (_groups[i]) {
        group(i);
        start = i + 1;
        longest = 0;
        widest = 0;
        k++;
      } else {
        final t = children[k++].getMaxIntrinsicWidth(1);
        longest = t > longest ? t : longest;
        final v = children[k++].getMaxIntrinsicWidth(unbounded);
        widest = v > widest ? v : widest;
      }
    }
    group(_groups.length);
    return columns;
  }

  /// Whether [children] are as many as the items take.
  bool _matches(List<RenderObject> children) {
    var n = 0;
    for (final g in _groups) {
      n += g ? 1 : 2;
    }
    return n == children.length;
  }

  /// The rows at [width] columns, their height: the children laid out and
  /// placed with [place], measured by their intrinsic heights without.
  int _rows(List<RenderObject> children, int width, {required bool place}) {
    assert(_matches(children), 'a child for each heading, two for each pair');
    final bounded = width < BoxConstraints.unbounded;
    final stacked =
        bounded && width < _stackBelowWidth && width < _widest(children);
    final columns = stacked ? const <int>[] : _columns(children, width);
    // the height of child at x, y, laid out from minW to maxW wide
    int lay(RenderObject child, int x, int y, int minW, int maxW, int maxH) {
      if (!place) {
        final h = child.getMaxIntrinsicHeight(maxW);
        return h < maxH ? h : maxH;
      }
      child.layout(
        BoxConstraints(minW, maxW, 0, maxH),
        parentUsesSize: true,
      );
      child.parentData
        ..dx = x
        ..dy = y;
      return child.height;
    }

    const tall = BoxConstraints.unbounded;
    var y = 0;
    var k = 0;
    for (var i = 0; i < _groups.length; i++) {
      if (_groups[i]) {
        y += i > 0 ? 1 : 0;
        y += lay(children[k++], 0, y, 0, width, tall);
        continue;
      }
      final term = children[k++];
      final value = children[k++];
      if (stacked) {
        y += lay(term, 0, y, 0, width, 1);
        final indent = width > _stackIndent ? _stackIndent : 0;
        y += lay(value, indent, y, 0, width - indent, tall);
      } else {
        final column = columns[i];
        final t = lay(term, 0, y, column, column, 1);
        final x = column + _gap;
        final room = bounded ? (width > x ? width - x : 0) : width;
        final v = lay(value, x, y, 0, room, tall);
        y += t > v ? t : v;
      }
    }
    return y;
  }

  /// The width of the widest row, the widths not bounded.
  int _widest(List<RenderObject> children) {
    const unbounded = BoxConstraints.unbounded;
    final columns = _columns(children, unbounded);
    var most = 0;
    var k = 0;
    for (var i = 0; i < _groups.length; i++) {
      final int w;
      if (_groups[i]) {
        w = children[k++].getMaxIntrinsicWidth(unbounded);
      } else {
        k++;
        w = columns[i] + _gap + children[k++].getMaxIntrinsicWidth(unbounded);
      }
      most = w > most ? w : most;
    }
    return most;
  }

  @override
  int computeMinIntrinsicWidth(int height) => 0;

  @override
  int computeMaxIntrinsicWidth(int height) => _widest(_children);

  @override
  int computeMinIntrinsicHeight(int width) => computeMaxIntrinsicHeight(width);

  @override
  int computeMaxIntrinsicHeight(int width) {
    final children = _children;
    return _rows(
      children,
      width < BoxConstraints.unbounded ? width : _widest(children),
      place: false,
    );
  }

  @override
  void performLayout(BoxConstraints c) {
    final children = _children;
    final w = c.maxW < BoxConstraints.unbounded ? c.maxW : _widest(children);
    width = c.constrainW(w);
    height = c.constrainH(_rows(children, width, place: true));
  }

  @override
  void paint(PaintContext ctx) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      paintChild(ctx, child);
    }
  }
}
