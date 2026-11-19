/// What a [ListView] with `itemText` gives a `SelectionArea` to select
/// in: [ItemText], the text of an item, and [ItemSelection], the part of
/// it that is selected, for the item to draw.
///
/// @docImport 'list_view.dart';
library;

import 'dart:math' show max, min;

import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        ListParentData,
        PaintContext,
        RenderList,
        RenderObject,
        RenderObjectWithChildMixin,
        graphemeBoundaries,
        stringWidth;

import '../framework/framework.dart';
import '../gestures/selection.dart' show ExcludeSelection, Selectable;
import '../layout/one_child.dart';
import '../style/style.dart';
import 'scrollable.dart';

/// The text of item [index] of a [ListView], for a selection.
typedef ItemTextBuilder = ItemText Function(int index);

/// The text a [ListView]'s item is selected and copied as: one line, in
/// one or more runs, each at a column of the item.
///
/// A run is the text of what the item shows at a column: the cell at or
/// right of its column and left of the next run's selects the cluster
/// there, at either cell of a wide one. What is shown but is not text (a
/// line number, a sign, a border) is in no run: its cells select nothing.
/// The text is what is drawn, a tab as the blanks it is drawn as. The
/// runs of one item are copied joined by a tab.
final class ItemText {
  /// One run, [text], at [column] of the item (inside the list's padding).
  ItemText(String text, {int column = 0}) : runs = [(column, text)];

  /// The runs of an item that has more than one text on its line (the two
  /// sides of a side by side diff): each a column and the text from
  /// there, in the order of the columns.
  ItemText.runs(this.runs)
    : assert(runs.isNotEmpty, 'a run or more'),
      assert(
        runs.every((r) => !r.$2.contains('\n')),
        'runs of one line: no line break in a run',
      );

  /// The runs: the column of each and its text.
  final List<(int column, String text)> runs;

  /// The runs joined, as they are copied.
  String get text => runs.map((r) => r.$2).join('\t');
}

/// The part of an item's [ItemText] that is selected, as the item's
/// builder gets it from [ListView.selectionOf] to draw it: the offsets
/// ([start], [end], UTF-16 code units, start before end) in the text of the
/// item, and the [style] the area selects in.
final class ItemSelection {
  const ItemSelection._(this.start, this.end, this.style, this._runs);

  /// Where the selection starts in the item's text, as [ItemText.text]
  /// has it.
  final int start;

  /// Where the selection ends in the item's text, past its last code unit.
  final int end;

  /// What the area merges onto the style of the text it selects.
  final Style style;

  // where each run starts in the item's text, and its length
  final List<(int, int)> _runs;

  /// The part of run [run] that is selected, as offsets in the run's own
  /// text; null when none of it is.
  (int, int)? rangeOf([int run = 0]) {
    final (from, length) = _runs[run];
    final s = max(start, from);
    final e = min(end, from + length);
    return s < e ? (s - from, e - from) : null;
  }

  /// [text], the text of run [run], as the spans to draw it: the selected
  /// part in [style] and the rest as it is, for `Text.rich`.
  List<Span> spans(String text, {int run = 0}) => mark([Span(text)], run: run);

  /// [spans], which together are the text of run [run], with the part of
  /// it that is selected in [style] merged onto theirs: a span cut where
  /// the selection starts or ends. Spans of a text and a style: a gradient
  /// or a tap of one is dropped where it is cut.
  List<Span> mark(List<Span> spans, {int run = 0}) {
    final range = rangeOf(run);
    if (range == null) {
      return spans;
    }
    final (s, e) = range;
    final out = <Span>[];
    var at = 0;
    for (final span in spans) {
      final text = span.text;
      final from = at;
      at += text.length;
      if (at <= s || from >= e || text.isEmpty) {
        out.add(span);
        continue;
      }
      final a = max(s, from) - from;
      final b = min(e, at) - from;
      if (a > 0) {
        out.add(Span(text.substring(0, a), span.style));
      }
      out.add(Span(text.substring(a, b), span.style.merge(style)));
      if (b < text.length) {
        out.add(Span(text.substring(b), span.style));
      }
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is ItemSelection &&
      other.start == start &&
      other.end == end &&
      other.style == style;

  @override
  int get hashCode => Object.hash(start, end, style);
}

/// Puts the selectable text of a [ListView] around [child], the list: a
/// [Selectable] for all the items, those not built too, over a child in
/// which the items are [ExcludeSelection]s.
final class ListSelectionHost extends StatefulWidget {
  /// Selects in [itemCount] items whose text [itemText] gives, of a list
  /// [reverse] (item 0 at the bottom) or not, whose [separated] children
  /// are the items at the even indices, scrolled by [position].
  const ListSelectionHost({
    required this.itemCount,
    required this.itemText,
    required this.reverse,
    required this.separated,
    required this.position,
    required this.child,
    super.key,
  });

  /// How many items the list has.
  final int itemCount;

  /// The text of an item.
  final ItemTextBuilder itemText;

  /// Whether item 0 is at the bottom.
  final bool reverse;

  /// Whether a separator is between each two items.
  final bool separated;

  /// What scrolls the list.
  final ScrollPosition position;

  /// The list.
  final Widget child;

  /// The part of item [index] selected, as of the host above [context],
  /// which [context] then depends on; null for none, or no host.
  static ItemSelection? of(BuildContext context, int index) {
    final scope = context.dependOnInheritedWidgetOfExactType<_SelectionScope>();
    return scope?.state._selectedOf(index, scope.selection, scope.style);
  }

  @override
  State<ListSelectionHost> createState() => _ListSelectionHostState();
}

final class _ListSelectionHostState extends State<ListSelectionHost> {
  // the text, made at the first ask after a widget changed; the runs of the
  // items in the order of the screen, where each starts in the text
  String? _text;
  List<ItemText> _items = const [];
  List<int> _starts = const [];

  (int, int)? _selection;
  var _style = const Style();

  @override
  void didUpdateWidget(ListSelectionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    // the builder may give other text: made anew when next asked
    _text = null;
  }

  /// The item of the screen's position [k] (0 the top).
  int _indexOf(int k) => widget.reverse ? widget.itemCount - 1 - k : k;

  String _selectable() {
    final made = _text;
    if (made != null) {
      return made;
    }
    final n = widget.itemCount;
    final items = <ItemText>[];
    final starts = <int>[];
    final out = StringBuffer();
    for (var k = 0; k < n; k++) {
      if (k > 0) {
        out.write('\n');
      }
      final item = widget.itemText(_indexOf(k));
      starts.add(out.length);
      items.add(item);
      out.write(item.text);
    }
    _items = items;
    _starts = starts;
    return _text = out.toString();
  }

  // where the item at position k of the screen ends in the text, before its
  // line break
  int _endOf(int k) => _starts[k] + _items[k].text.length;

  ItemSelection? _selectedOf(int index, (int, int)? selection, Style style) {
    if (selection == null || index < 0 || index >= widget.itemCount) {
      return null;
    }
    _selectable();
    final k = widget.reverse ? widget.itemCount - 1 - index : index;
    final start = _starts[k];
    final s = max(selection.$1, start);
    final e = min(selection.$2, _endOf(k));
    if (s >= e) {
      return null;
    }
    var at = 0;
    final runs = <(int, int)>[];
    for (final (_, text) in _items[k].runs) {
      runs.add((at, text.length));
      at += text.length + 1;
    }
    return ItemSelection._(s - start, e - start, style, runs);
  }

  void _select((int, int)? selection, Style style) {
    if (!mounted || (selection == _selection && style == _style)) {
      return;
    }
    setState(() {
      _selection = selection;
      _style = style;
    });
  }

  @override
  Widget build(BuildContext context) => _SelectionScope(
    state: this,
    selection: _selection,
    style: _style,
    child: _SelectableList(
      state: this,
      child: ExcludeSelection(child: widget.child),
    ),
  );
}

/// What the items of the list depend on: what of them is selected.
final class _SelectionScope extends InheritedWidget {
  const _SelectionScope({
    required this.state,
    required this.selection,
    required this.style,
    required super.child,
  });

  final _ListSelectionHostState state;
  final (int, int)? selection;
  final Style style;

  @override
  bool updateShouldNotify(_SelectionScope oldWidget) =>
      selection != oldWidget.selection || style != oldWidget.style;
}

final class _SelectableList extends SingleChildRenderObjectWidget {
  const _SelectableList({required this.state, required Widget super.child});

  final _ListSelectionHostState state;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderSelectableList createRenderObject(BuildContext context) =>
      _RenderSelectableList(state);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSelectableList renderObject,
  ) => renderObject.state = state;
}

/// What a [_SelectableList] lays out and paints: its child, as large as it,
/// and the [Selectable] the area selects the items in.
final class _RenderSelectableList extends RenderObject
    with RenderObjectWithChildMixin, Selectable {
  _RenderSelectableList(this.state);

  _ListSelectionHostState state;

  // what the host was last told
  (int, int)? _told;
  Style? _toldStyle;

  @override
  String get selectableText => state._selectable();

  @override
  (int, int) selectableRangeAt(int x, int y) => _rangeAt(x, y);

  @override
  bool scrollSelectionBy(int rows) {
    final p = state.widget.position;
    if (!p.hasExtents || rows == 0) {
      return false;
    }
    final from = p.pixels;
    p.jumpTo(state.widget.reverse ? from - rows : from + rows);
    return p.pixels != from;
  }

  /// Marked for paint by the area when what is selected changed: the host
  /// is told, which has the items built again.
  @override
  void markNeedsPaint() {
    super.markNeedsPaint();
    if (selection == _told && selectionStyle == _toldStyle) {
      return;
    }
    _told = selection;
    _toldStyle = selectionStyle;
    state._select(selection, selectionStyle);
  }

  RenderList? _list() {
    RenderList? found;
    void visit(RenderObject o) {
      if (found != null) {
        return;
      }
      if (o is RenderList) {
        found = o;
        return;
      }
      o.visitChildren(visit);
    }

    visitChildren(visit);
    return found;
  }

  (int, int) _rangeAt(int x, int y) {
    final text = state._selectable();
    final list = _list();
    if (list == null || text.isEmpty) {
      return (0, 0);
    }
    var left = 0;
    var top = 0;
    for (
      RenderObject? p = list;
      p != null && !identical(p, this);
      p = p.parent
    ) {
      left += p.parentData.dx;
      top += p.parentData.dy;
    }
    final row = y - top;
    final separated = state.widget.separated;
    final n = state.widget.itemCount;
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
    if (first == null || last == null) {
      return (0, 0);
    }
    // the position on the screen of the item a child is, or the item
    // before a separator
    int positionOf(RenderObject c) {
      final index = (c.parentData as ListParentData).index;
      return separated ? index ~/ 2 : index;
    }

    bool isSeparator(RenderObject c) =>
        separated && (c.parentData as ListParentData).index.isOdd;

    // where item k ends, after its line break
    int after(int k) => k + 1 < n ? state._starts[k + 1] : text.length;

    final item = hit;
    if (item == null) {
      final above = row < (first!.parentData as ListParentData).dy;
      if (above) {
        final k = positionOf(first!);
        final at = isSeparator(first!) ? after(k) : state._starts[k];
        return (at, at);
      }
      final at = after(positionOf(last!));
      return (at, at);
    }
    final k = positionOf(item);
    if (isSeparator(item)) {
      final at = after(k);
      return (at, at);
    }
    final data = item.parentData as ListParentData;
    final start = state._starts[k];
    final next = after(k);
    if (row > data.dy) {
      return (next, next);
    }
    final lx = x - left - data.dx;
    var runStart = start;
    final runs = state._items[k].runs;
    for (var r = 0; r < runs.length; r++) {
      final (column, run) = runs[r];
      if (lx < column) {
        return (runStart, runStart);
      }
      var at = column;
      int? pending;
      for (final (a, b) in graphemeBoundaries(run)) {
        final w = stringWidth(run.substring(a, b));
        if (w == 0) {
          pending ??= a;
          continue;
        }
        if (lx < at + w) {
          return (runStart + (pending ?? a), runStart + b);
        }
        at += w;
        pending = null;
      }
      runStart += run.length + 1;
    }
    return (next, next);
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
